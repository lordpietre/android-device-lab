#!/usr/bin/env bash
# Back up device-unique partitions to the host. READ-ONLY on the device.
#
# This script only reads from the phone. It never writes a partition, never
# flashes and never modifies device state. The copies it makes contain unique
# identifiers (IMEI/Wi-Fi/Bluetooth/sensor calibration): keep them local,
# never commit them and never publish them.
#
# Usage:
#   backup-partitions.sh --list                     show available partitions
#   backup-partitions.sh --plan                     show what would be backed up
#   backup-partitions.sh --group core --yes         back up boot-like partitions
#   backup-partitions.sh --group all --yes          back up core + calibration
#   backup-partitions.sh --include boot,persist --yes
#
# Options:
#   --out DIR      output directory (default ./device-backup-<timestamp>)
#   --serial S     target one device (required when several are attached)
#   --group NAME   core | calibration | all   (default: core)
#   --include LIST comma separated partition names (overrides --group)
#   --yes          actually pull (without it the script only prints the plan)
#
# Exit codes: 0 ok, 1 usage, 2 no device, 3 several devices, 4 no root, 5 nothing backed up.
set -uo pipefail

OUT=""
GROUP="core"
INCLUDE=""
SERIAL="${ANDROID_SERIAL:-}"
DO_PULL=0
LIST_ONLY=0
PLAN_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --out) shift; OUT="${1:-}" ;;
    --out=*) OUT="${1#--out=}" ;;
    --serial) shift; SERIAL="${1:-}" ;;
    --serial=*) SERIAL="${1#--serial=}" ;;
    --group) shift; GROUP="${1:-core}" ;;
    --group=*) GROUP="${1#--group=}" ;;
    --include) shift; INCLUDE="${1:-}" ;;
    --include=*) INCLUDE="${1#--include=}" ;;
    --yes|-y) DO_PULL=1 ;;
    --list) LIST_ONLY=1 ;;
    --plan) PLAN_ONLY=1 ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

say()  { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$1" >&2; exit "${2:-1}"; }
have() { command -v "$1" >/dev/null 2>&1; }

have adb || die "adb not found (run: bash scripts/setup-host.sh --minimal)" 1

count=$(adb devices 2>/dev/null | awk 'NR>1 && $2=="device"' | wc -l | tr -d ' ')
[ "${count:-0}" -eq 0 ] && { say "No adb device in 'device' state." >&2; adb devices >&2; exit 2; }
if [ "$count" -gt 1 ] && [ -z "$SERIAL" ]; then
  say "Several adb devices attached. Re-run with --serial <serial>:" >&2
  adb devices >&2
  exit 3
fi
ADB=(adb); [ -n "$SERIAL" ] && ADB=(adb -s "$SERIAL")

sh_() { "${ADB[@]}" shell "$@" 2>&1 | tr -d '\r'; }

# ------------------------------------------------------------------ partition sets
CORE_PARTS="boot init_boot vendor_boot recovery dtbo dtbo_v2 vbmeta vbmeta_system vbmeta_vendor oem"
CALIB_PARTS="persist efs modemst1 modemst2 fsc fsg nvdata nvram proinfo protect_f protect_s frp mst misc"

case "$GROUP" in
  core)        WANT="$CORE_PARTS" ;;
  calibration) WANT="$CALIB_PARTS" ;;
  all)         WANT="$CORE_PARTS $CALIB_PARTS" ;;
  *) die "Unknown group: $GROUP (core|calibration|all)" ;;
esac
[ -n "$INCLUDE" ] && WANT=$(printf '%s' "$INCLUDE" | tr ',' ' ')

# ---------------------------------------------------------------------- listing
by_name_path() {
  for p in /dev/block/by-name /dev/block/bootdevice/by-name /dev/block/platform/*/by-name; do
    if [ -e "$p" ] || sh_ "test -d $p" >/dev/null 2>&1; then echo "$p"; return 0; fi
  done
  return 1
}
BYNAME=$(by_name_path)
[ -n "$BYNAME" ] || die "No /dev/block/by-name directory found on the device" 1

if [ "$LIST_ONLY" -eq 1 ]; then
  say "# Partitions on the device ($BYNAME)"
  sh_ 'for p in /dev/block/by-name/*; do
          n=$(basename "$p"); t=$(readlink "$p")
          s=$(blockdev --getsize64 "$t" 2>/dev/null) || s=$(stat -c %s "$t" 2>/dev/null)
          [ -z "$s" ] && s=0
          [ "$s" -gt 0 ] 2>/dev/null || s=0
          [ -n "$t" ] && printf "%s %s %s\n" "$n" "$t" "$s"
        done' 2>/dev/null | sort | LC_ALL=C awk '
        { size = ($3 ~ /^[0-9]+$/ && $3 > 0) ? sprintf("%.1f MiB", $3/1048576) : "(needs root)"
          printf "  %-24s %-28s %s\n", $1, $2, size }'
  exit 0
fi

# ------------------------------------------------------------------- root check
IS_ROOT=0
[ "$(sh_ id -u | tr -d ' \r')" = "0" ] && IS_ROOT=1
if [ "$IS_ROOT" -eq 0 ] && sh_ "su -c id -u" 2>/dev/null | tr -d ' \r' | grep -q '^0$'; then
  IS_ROOT=1
  ROOT_CMD="su"
else
  ROOT_CMD=""
fi
[ "$IS_ROOT" -eq 0 ] && die "Device is not rooted: partition images cannot be read.
   Options: 'adb root' on a userdebug build, a custom recovery (TWRP) with adb,
   or back up only what is readable without root." 4

# --------------------------------------------------------- resolve partition list
RESOLVED=""
for p in $WANT; do
  for cand in "$p" "${p}_a" "${p}_b"; do
    if sh_ "test -e $BYNAME/$cand" >/dev/null 2>&1; then RESOLVED="$RESOLVED $cand"; fi
  done
done

if [ -z "$(printf '%s' "$RESOLVED" | tr -d ' ')" ]; then
  die "None of the requested partitions exist on this device." 5
fi

# ------------------------------------------------------------------------ plan
say "Backup plan (read-only on the device):"
for p in $RESOLVED; do
  target=$(sh_ "readlink $BYNAME/$p" 2>/dev/null | tr -d ' \r')
  size=$(sh_ "blockdev --getsize64 $BYNAME/$p 2>/dev/null || stat -c %s $BYNAME/$p 2>/dev/null" | tr -d ' \r')
  [ -z "$target" ] && target="$BYNAME/$p"
  case "$size" in
    ''|*[!0-9]*) size="size unknown without root" ;;
    0) size="size unknown without root" ;;
    *) size="$((size / 1048576)) MiB" ;;
  esac
  say "  $p -> $target ($size)"
done
say ""
say "Output: ${OUT:-./device-backup-<timestamp>}"
say "NOTE: these images contain device-unique identifiers. Keep them local, do not commit or publish them."

if [ "$PLAN_ONLY" -eq 1 ] || [ "$DO_PULL" -eq 0 ]; then
  say ""
  say "Dry run. Re-run with --yes to perform the backup."
  exit 0
fi

[ -n "$OUT" ] || OUT="./device-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT" || die "Cannot create $OUT"

read_part() {
  local part="$1" dest="$2"
  if [ -n "$ROOT_CMD" ]; then
    "${ADB[@]}" exec-out "$ROOT_CMD -c 'cat $BYNAME/$part'" > "$dest" 2>/dev/null
  else
    "${ADB[@]}" exec-out "cat $BYNAME/$part" > "$dest" 2>/dev/null
  fi
}

OK=0
FAILED=""
for p in $RESOLVED; do
  dest="$OUT/$p.img"
  printf 'pulling %-20s ' "$p"
  read_part "$p" "$dest"
  if [ -s "$dest" ]; then
    printf 'ok (%s bytes)\n' "$(stat -c %s "$dest")"
    OK=$((OK + 1))
  else
    printf 'FAILED\n'
    rm -f "$dest"
    FAILED="$FAILED $p"
  fi
done

# --------------------------------------------------------------------- manifest
{
  echo "# Device backup manifest"
  echo
  echo "- Device hash: $(printf '%s' "${SERIAL:-unknown}" | sha256sum | cut -c1-8)"
  echo "- Created (UTC): $(date -u +%FT%TZ)"
  echo "- Read-only source: $BYNAME (no partition was written)"
  echo "- Partitions copied: $OK"
  echo
  echo "| partition | size | sha256 |"
  echo "|---|---|---|"
  for f in "$OUT"/*.img; do
    [ -e "$f" ] || continue
    echo "| $(basename "$f" .img) | $(stat -c %s "$f") | $(sha256sum "$f" | cut -d' ' -f1) |"
  done
  echo
  echo "## Restore (Tier 2, needs explicit confirmation)"
  echo "  fastboot flash <partition> $OUT/<partition>.img    # slot aware, check A/B"
  echo
  echo "## Warning"
  echo "  These files contain device-unique identifiers (IMEI, Wi-Fi/BT addresses,"
  echo "  sensor calibration). Do not commit them, do not upload them, do not share them."
  echo "  Flashing 'modem'/'frp' is destructive: do not restore them without reading"
  echo "  references/safety.md first."
} > "$OUT/backup-manifest.md"

( cd "$OUT" && sha256sum *.img > SHA256SUMS 2>/dev/null )

say ""
say "Backed up $OK partition(s) to $OUT"
[ -n "$FAILED" ] && warn "Failed:$FAILED"
say "Manifest: $OUT/backup-manifest.md"
[ "$OK" -eq 0 ] && exit 5
exit 0
