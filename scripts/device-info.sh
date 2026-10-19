#!/usr/bin/env bash
# Read-only Android reconnaissance over adb (and optionally fastboot).
# Never writes to the device. Redacts serial, IMEI, MAC and similar identifiers.
#
# Usage:
#   device-info.sh [outdir] [--fastboot] [--serial <serial>] [--list]
#   ANDROID_SERIAL=<serial> device-info.sh        # when several devices are attached
#
# Exit codes: 0 ok, 1 missing tool, 2 no device, 3 several devices, 4 unauthorized.
set -uo pipefail

OUT=""
MODE="adb"
SERIAL="${ANDROID_SERIAL:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --fastboot) MODE="fastboot" ;;
    --serial) shift; SERIAL="${1:-}" ;;
    --serial=*) SERIAL="${1#--serial=}" ;;
    --list) MODE="list" ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) OUT="$1" ;;
  esac
  shift
done

[ -n "$OUT" ] || OUT="./android-recon-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT" || { echo "Cannot create $OUT" >&2; exit 1; }

REDACT='serial|imei|meid|imsi|iccid|phonenumber|macaddr|mac_addr|bdaddr|wifi.*addr|bluetooth.*addr|android_id|ssid|account|token|msisdn|iccid'
redact() { grep -viE "$REDACT" || true; }
short_hash() { printf '%s' "$1" | sha256sum | cut -c1-8; }
have() { command -v "$1" >/dev/null 2>&1; }

# ------------------------------------------------------------------ list mode
if [ "$MODE" = "list" ]; then
  echo "adb:"
  have adb && adb devices -l | sed 's/^/  /' || echo "  (adb not installed)"
  echo "fastboot:"
  have fastboot && fastboot devices | sed 's/^/  /' || echo "  (fastboot not installed)"
  exit 0
fi

# ---------------------------------------------------------------- fastboot mode
if [ "$MODE" = "fastboot" ]; then
  have fastboot || { echo "fastboot not found (run: bash scripts/setup-host.sh --minimal)" >&2; exit 1; }
  n=$(fastboot devices 2>/dev/null | grep -c . || true)
  [ "${n:-0}" -eq 0 ] && { echo "No fastboot device found." >&2; exit 2; }
  if [ "$n" -gt 1 ] && [ -z "$SERIAL" ]; then
    echo "Several fastboot devices attached. Re-run with --serial <serial>:" >&2
    fastboot devices >&2
    exit 3
  fi
  FB=(fastboot); [ -n "$SERIAL" ] && FB=(fastboot -s "$SERIAL")
  # getvar is read-only.
  "${FB[@]}" getvar all 2>&1 | tr -d '\r' | redact > "$OUT/fastboot-getvar.txt"
  {
    echo "# Fastboot summary"
    for v in product variant device unlocked secure is-userspace current-slot slot-count \
             super-partition-name snapshot-update-status anti version-bootloader version-baseband \
             max-download-size; do
      val=$(grep -iE "^(\(bootloader\) )?$v:" "$OUT/fastboot-getvar.txt" | head -1 \
            | sed -E "s/^(\(bootloader\) )?$v:[[:space:]]*//I")
      printf '%s: %s\n' "$v" "${val:-}"
    done
    echo
    echo "## partition sizes reported by fastboot"
    grep -iE "partition-size" "$OUT/fastboot-getvar.txt" | sed 's/^/  /' || echo "  (not reported by this bootloader)"
  } > "$OUT/summary.md"
  cat "$OUT/summary.md"
  echo "Raw output: $OUT/fastboot-getvar.txt"
  exit 0
fi

# --------------------------------------------------------------------- adb mode
have adb || { echo "adb not found (run: bash scripts/setup-host.sh --minimal)" >&2; exit 1; }
if adb devices 2>/dev/null | awk 'NR>1' | grep -q unauthorized; then
  echo "Device is 'unauthorized': accept the RSA prompt on the device screen and retry." >&2
  exit 4
fi
count=$(adb devices 2>/dev/null | awk 'NR>1 && $2=="device"' | wc -l | tr -d ' ')
[ "${count:-0}" -eq 0 ] && { echo "No adb device in 'device' state. adb devices says:" >&2; adb devices >&2; exit 2; }
if [ "$count" -gt 1 ] && [ -z "$SERIAL" ]; then
  echo "Several adb devices attached. Re-run with --serial <serial>:" >&2
  adb devices >&2
  exit 3
fi
ADB=(adb); [ -n "$SERIAL" ] && ADB=(adb -s "$SERIAL")

# adb shell for text, adb exec-out for binary-safe reads (device tree blobs).
sh_() { "${ADB[@]}" shell "$@" 2>&1 | tr -d '\r'; }
bin_() { "${ADB[@]}" exec-out "$@" 2>/dev/null; }
prop() { sh_ getprop "$1" | tr -d '\r'; }

SERIAL_RAW="${SERIAL:-$(adb get-serialno 2>/dev/null | tr -d '\r')}"
{
  echo "device_hash: $(short_hash "$SERIAL_RAW")"
  echo "collected_utc: $(date -u +%FT%TZ)"
  echo "mode: adb"
} > "$OUT/meta.txt"

# ------------------------------------------------------------------- properties
sh_ getprop | redact > "$OUT/props_full.txt"
{
  for p in ro.product.manufacturer ro.product.brand ro.product.model ro.product.device ro.product.name \
           ro.board.platform ro.hardware ro.hardware.chipname ro.soc.manufacturer ro.soc.model \
           ro.product.cpu.abi ro.product.cpu.abilist ro.product.first_api_level \
           ro.build.version.release ro.build.version.sdk ro.build.version.security_patch \
           ro.vendor.build.security_patch ro.build.fingerprint ro.build.type ro.build.tags \
           ro.build.ab_update ro.boot.slot_suffix ro.boot.dynamic_partitions ro.boot.super_partition \
           ro.boot.verifiedbootstate ro.boot.flash.locked ro.boot.vbmeta.device_state \
           ro.oem_unlock_supported sys.oem_unlock_allowed ro.treble.enabled \
           ro.bootloader ro.boot.bootloader ro.boot.hardware ro.boot.hardware.platform \
           ro.boot.serialno ro.boot.verifiedbootstate; do
    printf '%s=%s\n' "$p" "$(prop "$p")"
  done
} > "$OUT/props_key.txt"

# ------------------------------------------------------- kernel / SoC / device tree
{
  echo "## uname"; sh_ uname -a
  echo "## /proc/version"; sh_ cat /proc/version
  echo "## /proc/cmdline"; sh_ cat /proc/cmdline | redact
  echo "## device-tree model"; bin_ cat /proc/device-tree/model | tr '\0' ' ' | sed 's/[[:space:]]*$//'
  echo "## device-tree compatible"; bin_ cat /proc/device-tree/compatible | tr '\0' '\n' | sed '/^$/d'
  echo "## cpuinfo (summary)"
  sh_ cat /proc/cpuinfo | grep -iE 'hardware|model name|cpu part|cpu implementer' | sort | uniq -c
  echo "## memory"; sh_ head -3 /proc/meminfo
  echo "## SELinux"; sh_ getenforce
} > "$OUT/kernel.txt"

# ---------------------------------------------------------------- storage / parts
{
  echo "## /proc/partitions"; sh_ cat /proc/partitions
  echo "## by-name"
  sh_ 'ls -l /dev/block/by-name 2>/dev/null || ls -l /dev/block/bootdevice/by-name 2>/dev/null || ls -l /dev/block/platform/*/by-name 2>/dev/null'
  echo "## df"; sh_ df -h
  echo "## mounts (summary)"
  sh_ 'mount | grep -E " / | /system | /vendor | /product | /data | /metadata "'
  echo "## slot info"; sh_ 'ls /dev/block/by-name 2>/dev/null | grep -E "_a$|_b$" | head -20'
} > "$OUT/storage.txt"

# -------------------------------------------------------------------- hardware
{
  echo "## display"; sh_ wm size; sh_ wm density
  echo "## battery"; sh_ dumpsys battery | grep -iE 'level|status|health|technology|present'
  echo "## power_supply"; sh_ ls /sys/class/power_supply
  echo "## input devices"; sh_ 'grep -E "^N:" /proc/bus/input/devices'
  echo "## loaded modules"; sh_ lsmod
  echo "## features"; sh_ pm list features | head -80
  echo "## usb gadget (kernel)"; sh_ 'ls /sys/class/udc 2>/dev/null'
} > "$OUT/hardware.txt"

# --------------------------------------------------------------------- summary
get() { grep -m1 "^$1=" "$OUT/props_key.txt" | cut -d= -f2-; }
{
  echo "# Recon summary (device $(short_hash "$SERIAL_RAW"))"
  echo
  echo "- Manufacturer/model: $(get ro.product.manufacturer) / $(get ro.product.model)"
  echo "- Codename (ro.product.device): $(get ro.product.device)"
  echo "- Platform/SoC: $(get ro.board.platform) | hardware: $(get ro.hardware) | soc: $(get ro.soc.manufacturer) $(get ro.soc.model)"
  echo "- ABI: $(get ro.product.cpu.abilist)"
  echo "- Android: $(get ro.build.version.release) (SDK $(get ro.build.version.sdk)), patch $(get ro.build.version.security_patch)"
  echo "- First API level: $(get ro.product.first_api_level) | Treble: $(get ro.treble.enabled)"
  echo "- A/B: $(get ro.build.ab_update) (slot '$(get ro.boot.slot_suffix)') | dynamic partitions: $(get ro.boot.dynamic_partitions)"
  echo "- Bootloader locked flag: $(get ro.boot.flash.locked) | vbmeta state: $(get ro.boot.vbmeta.device_state) | verifiedboot: $(get ro.boot.verifiedbootstate)"
  echo "- OEM unlock supported: $(get ro.oem_unlock_supported) | allowed: $(get sys.oem_unlock_allowed)"
  echo "- Bootloader version: $(get ro.bootloader)"
  echo "- Kernel: $(sed -n '/## uname/{n;p;}' "$OUT/kernel.txt")"
  echo "- Fingerprint: $(get ro.build.fingerprint)"
  echo
  echo "Empty values mean the property is not exposed on this device, not that the feature is absent."
  echo "Files: props_key.txt props_full.txt kernel.txt storage.txt hardware.txt"
} > "$OUT/summary.md"
cat "$OUT/summary.md"
