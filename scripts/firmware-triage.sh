#!/usr/bin/env bash
# Safe offline inventory/unpack of Android firmware.
# Extracts and reads only. It never executes, installs or mounts anything from
# the firmware, and it never touches a connected device.
#
# Usage:
#   firmware-triage.sh <firmware.zip|payload.bin|*.img|*.tar|*.tar.md5|*.7z> [outdir]
#
# Exit codes: 0 ok, 1 usage, 2 not enough disk space.
set -uo pipefail

IN=""
OUT=""
for a in "$@"; do
  case "$a" in
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    -*) echo "Unknown option: $a" >&2; exit 1 ;;
    *) if [ -z "$IN" ]; then IN="$a"; else OUT="$a"; fi ;;
  esac
done

[ -n "$IN" ] || { echo "Usage: $0 <firmware file> [outdir]" >&2; exit 1; }
[ -f "$IN" ] || { echo "No such file: $IN" >&2; exit 1; }
[ -n "$OUT" ] || OUT="./fw-triage-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT/extracted" "$OUT/images" || exit 1

HERE="$(cd "$(dirname "$0")" && pwd)"
BOOTIMG_PY="$HERE/lib/bootimg.py"

have() { command -v "$1" >/dev/null 2>&1; }
hex_at() { dd if="$1" bs=1 skip="$2" count="$3" 2>/dev/null | od -An -tx1 | tr -d ' \n'; }
M="$OUT/manifest.md"

# Disk space sanity check: need ~3x input size.
need_kb=$(( $(stat -c %s "$IN") / 1024 * 3 ))
avail_kb=$(df -Pk "$OUT" | awk 'NR==2{print $4}')
if [ "${avail_kb:-0}" -lt "$need_kb" ]; then
  echo "Not enough free space (need ~${need_kb}KB, have ${avail_kb:-0}KB)." >&2
  exit 2
fi

{
  echo "# Firmware manifest"
  echo "- File: $(basename "$IN")"
  echo "- Size: $(stat -c %s "$IN") bytes"
  echo "- SHA256: $(sha256sum "$IN" | cut -d' ' -f1)"
  if have file; then echo "- Type: $(file -b "$IN")"; fi
  echo "- Analysed (UTC): $(date -u +%FT%TZ)"
  echo
  echo "> Compare the SHA256 with the vendor's published value before trusting this file."
  echo
} > "$M"

# 1. Container handling (extract only, never run).
case "$IN" in
  *.zip)
    have unzip || { echo "unzip not installed" >&2; exit 1; }
    unzip -l "$IN" > "$OUT/zip-listing.txt"
    # unzip refuses absolute paths and '../' by default; -n never overwrites.
    unzip -n -q "$IN" -d "$OUT/extracted"
    ;;
  *.tar|*.tar.md5)
    tar -tf "$IN" > "$OUT/tar-listing.txt" 2>/dev/null
    tar -xf "$IN" -C "$OUT/extracted" --no-same-owner --no-same-permissions
    ;;
  *.7z)
    if have 7z; then 7z x -y -o"$OUT/extracted" "$IN" >/dev/null; else echo "7z not available" >&2; fi ;;
  *)
    cp -n "$IN" "$OUT/extracted/" 2>/dev/null || true ;;
esac

# Samsung AP/BL/CP tars often contain .lz4 members.
if have lz4; then
  find "$OUT/extracted" -name '*.lz4' -print0 | while IFS= read -r -d '' f; do
    lz4 -dq "$f" "${f%.lz4}" 2>/dev/null
  done
fi

# 2. A/B OTA payload.
P=$(find "$OUT/extracted" -name payload.bin -print -quit)
if [ -n "$P" ]; then
  echo "## OTA payload.bin found" >> "$M"
  if have payload-dumper-go; then
    payload-dumper-go -o "$OUT/images" "$P" >/dev/null 2>&1 \
      && echo "- Extracted with payload-dumper-go" >> "$M" \
      || echo "- payload-dumper-go failed" >> "$M"
  elif have payload_dumper; then
    # The python payload_dumper writes to ./output
    ( cd "$OUT/images" && payload_dumper "$P" >/dev/null 2>&1 )
    [ -d "$OUT/images/output" ] && mv "$OUT/images/output"/* "$OUT/images/" 2>/dev/null
    echo "- Extracted with payload_dumper" >> "$M"
  else
    echo "- Install payload-dumper-go to extract partitions from payload.bin" >> "$M"
  fi
  PP="$(dirname "$P")/payload_properties.txt"
  if [ -f "$PP" ]; then { echo '```'; cat "$PP"; echo '```'; } >> "$M"; fi
fi

# 3. super.img (dynamic partitions) -> split with lpunpack when available.
SUPER=$(find "$OUT/extracted" "$OUT/images" -name 'super*.img' -print -quit 2>/dev/null)
if [ -n "$SUPER" ]; then
  echo "## Dynamic partitions (super.img)" >> "$M"
  if have lpunpack; then
    lpunpack "$SUPER" "$OUT/images" >/dev/null 2>&1 \
      && echo "- Split with lpunpack into $OUT/images" >> "$M" \
      || echo "- lpunpack failed" >> "$M"
  else
    echo "- Install lpunpack to split super.img into its logical partitions" >> "$M"
  fi
fi

# 4. Inventory every image by magic bytes.
{
  echo "## Images"
  echo "| file | size | sha256 (first 16) | detected |"
  echo "|---|---|---|---|"
} >> "$M"
find "$OUT/extracted" "$OUT/images" -type f \
     \( -name '*.img' -o -name '*.bin' -o -name '*.mbn' -o -name '*.elf' -o -name '*.raw' \) \
  | sort | while read -r f; do
  kind="unknown"
  h8=$(hex_at "$f" 0 8); h4=$(hex_at "$f" 0 4)
  [ "$h8" = "414e44524f494421" ] && kind="Android boot image (ANDROID!)"
  [ "$h8" = "564e4452424f4f54" ] && kind="vendor_boot (VNDRBOOT)"
  [ "$h4" = "41564230" ] && kind="vbmeta (AVB0)"
  [ "$h4" = "3aff26ed" ] && kind="Android sparse image (needs simg2img)"
  [ "$h4" = "d00dfeed" ] && kind="flattened device tree (DTB)"
  [ "$(hex_at "$f" 1024 4)" = "e2e1f5e0" ] && kind="EROFS filesystem"
  [ "$(hex_at "$f" 1080 2)" = "53ef" ] && kind="ext2/3/4 filesystem"
  [ "$(hex_at "$f" 4096 4)" = "616c5067" ] && kind="super (LP metadata)"
  echo "| $(basename "$f") | $(stat -c %s "$f") | $(sha256sum "$f" | cut -c1-16) | $kind |" >> "$M"
done

# 5. Boot image header analysis.
find "$OUT/extracted" "$OUT/images" -type f \
     \( -name 'boot*.img' -o -name 'vendor_boot*.img' -o -name 'init_boot*.img' -o -name 'recovery*.img' \) \
  | sort | while read -r b; do
  n=$(basename "$b" .img)
  echo "## Boot analysis: $n" >> "$M"
  if have python3 && [ -f "$BOOTIMG_PY" ]; then
    python3 "$BOOTIMG_PY" info "$b" 2>&1 | sed 's/^/    /' >> "$M"
  fi
  if have unpack_bootimg; then
    echo "    - unpack_bootimg output:" >> "$M"
    unpack_bootimg --boot_img "$b" --out "$OUT/boot-$n" --format=mkbootimg 2>&1 | sed 's/^/      /' >> "$M"
  elif have pmbootstrap; then
    echo "    - pmbootstrap bootimg_analyze:" >> "$M"
    pmbootstrap bootimg_analyze "$b" 2>&1 | sed 's/^/      /' >> "$M"
  else
    echo "    - (bundled parser above; install unpack_bootimg or pmbootstrap for extra detail)" >> "$M"
  fi
  # Kernel version string (text search only).
  kv=$(strings -n 12 "$b" 2>/dev/null | grep -m1 'Linux version')
  [ -n "$kv" ] && echo "    - kernel: $kv" >> "$M"
  # Embedded device tree model.
  if have python3 && [ -f "$BOOTIMG_PY" ]; then
    dt=$(python3 "$BOOTIMG_PY" dts "$b" 2>/dev/null)
    [ -n "$dt" ] && [ "$dt" != "(no embedded DTB model found)" ] && echo "    - dtb model/compatible: $dt" >> "$M"
  fi
done

# 6. AVB info.
AV=$(command -v avbtool || command -v avbtool.py || true)
if [ -n "$AV" ]; then
  find "$OUT/extracted" "$OUT/images" -type f -name 'vbmeta*.img' | sort | while read -r v; do
    echo "## AVB: $(basename "$v")" >> "$M"
    "$AV" info_image --image "$v" 2>&1 | sed 's/^/    /' >> "$M"
  done
else
  echo "## AVB" >> "$M"
  echo "- avbtool not installed: rollback index and flags could not be checked" >> "$M"
fi

# 7. Standalone device trees.
if have dtc; then
  find "$OUT" -type f \( -name '*.dtb' -o -name 'dtb' \) | sort | head -20 | while read -r d; do
    echo "## DT: $(basename "$d")" >> "$M"
    dtc -I dtb -O dts "$d" 2>/dev/null | grep -E '^\s*(model|compatible)\s*=' | head -4 | sed 's/^/    /' >> "$M"
  done
fi

# 8. Rawprogram / scatter partition maps (Qualcomm, MediaTek).
for map in $(find "$OUT/extracted" -maxdepth 3 -type f \( -name 'rawprogram*.xml' -o -name 'partition*.xml' -o -name 'scatter.txt' \) 2>/dev/null | sort); do
  echo "## Partition map: $(basename "$map")" >> "$M"
  case "$map" in
    *.xml) grep -oE 'label="[^"]+"|filename="[^"]+"|physical_partition_number="[0-9]+"' "$map" | head -60 | sed 's/^/    /' >> "$M" ;;
    *)     sed -n '1,60p' "$map" | sed 's/^/    /' >> "$M" ;;
  esac
done

{
  echo
  echo "## Notes"
  echo "- Nothing from the firmware was executed, installed or mounted."
  echo "- Vendor blobs (GPU/Wi-Fi/modem firmware) are listed only; do not redistribute them."
  echo "- Verify the SHA256 of the source package against the vendor's published value."
} >> "$M"

echo "Done. Manifest: $M"
echo "Nothing from the firmware was executed or mounted."
