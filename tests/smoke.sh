#!/usr/bin/env bash
# Offline smoke tests. No device, no network, no root required.
#   bash tests/smoke.sh
# Exit codes: 0 all good, 1 at least one failure.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
WORK="$(mktemp -d)"
PASS=0
FAIL=0

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

ok()   { PASS=$((PASS + 1)); printf '  [ok]   %s\n' "$*"; }
bad()  { FAIL=$((FAIL + 1)); printf '  [FAIL] %s\n' "$*"; }
note() { printf '  [skip] %s\n' "$*"; }

expect_contains() {
  # expect_contains <file> <pattern> <label>
  if grep -qE "$2" "$1" 2>/dev/null; then ok "$3"; else bad "$3 (pattern not found: $2)"; fi
}

echo "== scripts exist and are executable"
for s in setup-host.sh device-info.sh firmware-triage.sh backup-partitions.sh lint.sh; do
  if [ -x "$ROOT/scripts/$s" ]; then ok "scripts/$s"; else bad "scripts/$s missing or not executable"; fi
done
[ -f "$ROOT/scripts/lib/bootimg.py" ] && ok "scripts/lib/bootimg.py" || bad "scripts/lib/bootimg.py missing"

echo "== --help works"
for s in setup-host.sh device-info.sh firmware-triage.sh backup-partitions.sh; do
  if bash "$ROOT/scripts/$s" --help >/dev/null 2>&1; then ok "$s --help"; else bad "$s --help failed"; fi
done

echo "== synthetic boot images"
if command -v python3 >/dev/null 2>&1; then
  python3 - "$WORK" <<'PY'
import struct, sys, os
work = sys.argv[1]

# --- classic boot image (AOSP header_version 0) -----------------------------
page = 4096
cmdline = b"console=ttyMSM0,115200 androidboot.hardware=vendor\0"
kernel = b"KERNEL-BLOB-" * 64            # raw kernel payload
ramdisk = b"\x1f\x8b" + b"RAMDISK" * 32  # gzip magic + payload
hdr = bytearray(2048)
hdr[0:8] = b"ANDROID!"
struct.pack_into("<I", hdr, 8, len(kernel))       # kernel_size
struct.pack_into("<I", hdr, 12, 0x00008000)       # kernel_addr
struct.pack_into("<I", hdr, 16, len(ramdisk))     # ramdisk_size
struct.pack_into("<I", hdr, 20, 0x01000000)       # ramdisk_addr
struct.pack_into("<I", hdr, 24, 0)                # second_size
struct.pack_into("<I", hdr, 28, 0x00000000)       # second_addr
struct.pack_into("<I", hdr, 32, 0x00000100)       # tags_addr
struct.pack_into("<I", hdr, 36, page)             # page_size
struct.pack_into("<I", hdr, 40, 0)                # header_version
struct.pack_into("<I", hdr, 44, 0)                # os_version_patch_level
hdr[48:62] = b"testboard\0"                      # product_name
hdr[64:64 + len(cmdline)] = cmdline              # cmdline
blob = bytes(hdr).ljust(page, b"\x00")
blob += kernel.ljust(page, b"\x00")
blob += ramdisk.ljust(page, b"\x00")
open(os.path.join(work, "boot.img"), "wb").write(blob)

# --- v4 boot image (new 64-bit header) -------------------------------------
cmdline4 = b"console=ttyMSM0,115200 androidboot.hardware=v4\0"
kernel4 = b"KERNEL4" * 32
ramdisk4 = b"\x1f\x8b" + b"RAM4" * 32
os_version = (13 << 14) | (0 << 7) | 0
h4 = bytearray(2048)
h4[0:8] = b"ANDROID!"
struct.pack_into("<I", h4, 8, len(kernel4))       # kernel_size
struct.pack_into("<I", h4, 12, len(ramdisk4))     # ramdisk_size
struct.pack_into("<I", h4, 16, os_version << 11)  # os_version_patch_level
struct.pack_into("<I", h4, 20, 1580)              # header_size
struct.pack_into("<I", h4, 40, 4)                # header_version
h4[44:44 + len(cmdline4)] = cmdline4
b4 = bytes(h4).ljust(page, b"\x00")
b4 += kernel4
b4 += ramdisk4
open(os.path.join(work, "boot_v4.img"), "wb").write(b4)

# --- vendor_boot image (v3) ------------------------------------------------
vh = bytearray(2112)
vh[0:8] = b"VNDRBOOT"
struct.pack_into("<I", vh, 8, 3)                 # header_version
struct.pack_into("<I", vh, 12, page)             # page_size
struct.pack_into("<I", vh, 16, 0x00008000)       # kernel_addr
struct.pack_into("<I", vh, 20, 0x01000000)       # ramdisk_addr
struct.pack_into("<I", vh, 24, 64)               # vendor_ramdisk_size
vh[28:48] = b"vendor cmdline\0"
vendor_ramdisk = b"\x1f\x8b" + b"VRD" * 16
vb = bytes(vh).ljust(page, b"\x00") + vendor_ramdisk
open(os.path.join(work, "vendor_boot.img"), "wb").write(vb)

# --- vbmeta and sparse -----------------------------------------------------
open(os.path.join(work, "vbmeta.img"), "wb").write(b"AVB0" + b"\x00" * 60)
open(os.path.join(work, "system.img"), "wb").write(b"\x3a\xff\x26\xed" + b"\x00" * 60)
print("ok")
PY
  if [ $? -eq 0 ]; then ok "synthetic images created"; else bad "synthetic image generation failed"; fi
else
  note "python3 missing - skipping image tests"
fi

echo "== bootimg.py"
if command -v python3 >/dev/null 2>&1 && [ -f "$WORK/boot.img" ]; then
  python3 "$ROOT/scripts/lib/bootimg.py" info "$WORK/boot.img" > "$WORK/info.txt" 2>&1
  expect_contains "$WORK/info.txt" "page_size: 4096" "boot.img: page size parsed"
  expect_contains "$WORK/info.txt" "androidboot.hardware=vendor" "boot.img: cmdline parsed"
  expect_contains "$WORK/info.txt" "header_version: 0" "boot.img: header version parsed"
  expect_contains "$WORK/info.txt" "name: testboard" "boot.img: product name parsed"

  python3 "$ROOT/scripts/lib/bootimg.py" info "$WORK/boot_v4.img" > "$WORK/info4.txt" 2>&1
  expect_contains "$WORK/info4.txt" "header_version: 4" "boot_v4.img: v4 header detected"
  expect_contains "$WORK/info4.txt" "os_version: 13.0.0" "boot_v4.img: os version parsed"

  python3 "$ROOT/scripts/lib/bootimg.py" info "$WORK/vendor_boot.img" > "$WORK/info_vb.txt" 2>&1
  expect_contains "$WORK/info_vb.txt" "type: vendor_boot" "vendor_boot.img: type detected"
  expect_contains "$WORK/info_vb.txt" "vendor cmdline" "vendor_boot.img: cmdline parsed"

  python3 "$ROOT/scripts/lib/bootimg.py" extract "$WORK/boot.img" "$WORK/unpacked" >/dev/null 2>&1
  if [ -f "$WORK/unpacked/boot.kernel" ] && [ -f "$WORK/unpacked/boot.ramdisk" ]; then
    ok "boot.img: kernel and ramdisk extracted"
  else
    bad "boot.img: extraction failed"
  fi
else
  note "python3 missing - skipping parser tests"
fi

echo "== firmware-triage.sh"
if [ -f "$WORK/boot.img" ]; then
  ( cd "$WORK" && zip -qr firmware.zip boot.img boot_v4.img vendor_boot.img vbmeta.img system.img ) 2>/dev/null
  if bash "$ROOT/scripts/firmware-triage.sh" "$WORK/firmware.zip" "$WORK/fw" >"$WORK/triage.log" 2>&1; then
    ok "firmware-triage.sh completed"
  else
    bad "firmware-triage.sh failed: $(tail -3 "$WORK/triage.log")"
  fi
  M="$WORK/fw/manifest.md"
  if [ -f "$M" ]; then
    ok "manifest written"
    expect_contains "$M" "SHA256" "manifest: sha256 recorded"
    expect_contains "$M" "Android boot image" "manifest: boot image identified"
    expect_contains "$M" "vendor_boot" "manifest: vendor_boot identified"
    expect_contains "$M" "vbmeta \(AVB0\)" "manifest: vbmeta identified"
    expect_contains "$M" "sparse image" "manifest: sparse image identified"
    expect_contains "$M" "page_size: 4096" "manifest: boot header parsed"
  else
    bad "manifest.md not created"
  fi
else
  note "no synthetic images - skipping triage tests"
fi

echo "== cross-validation against AOSP unpack_bootimg"
if command -v mkbootimg >/dev/null 2>&1 && command -v unpack_bootimg >/dev/null 2>&1; then
  MKDIR="$WORK/mk"
  mkdir -p "$MKDIR"
  ( cd "$MKDIR" \
    && head -c 4096 /dev/urandom > kernel.bin \
    && { printf '\x1f\x8b\x08\x00'; head -c 2048 /dev/urandom; } > ramdisk.bin \
    && printf 'dtbdata' > dtb.bin \
    && head -c 3000 /dev/urandom > vrd.bin ) 2>/dev/null
  for v in 0 1 2 3 4; do
    extra=""
    [ "$v" = "2" ] && extra="--dtb dtb.bin"
    ( cd "$MKDIR" && mkbootimg --kernel kernel.bin --ramdisk ramdisk.bin $extra \
        --cmdline "console=ttyS0,115200" --board "testboard" --pagesize 4096 \
        --header_version $v -o "boot_v$v.img" ) >/dev/null 2>&1
    if [ ! -f "$MKDIR/boot_v$v.img" ]; then
      note "mkbootimg could not build a v$v image"
      continue
    fi
    mkdir -p "$WORK/aosp/v$v" "$WORK/mine/v$v"
    ( cd "$WORK" && unpack_bootimg --boot_img "mk/boot_v$v.img" --out "aosp/v$v" --format=mkbootimg ) >/dev/null 2>&1
    python3 "$ROOT/scripts/lib/bootimg.py" extract "$MKDIR/boot_v$v.img" "$WORK/mine/v$v" >/dev/null 2>&1
    same=1
    for f in "$WORK/aosp/v$v"/*; do
      [ -f "$f" ] || continue
      cmp -s "$f" "$WORK/mine/v$v/boot_v$v.$(basename "$f")" || same=0
    done
    if [ "$same" -eq 1 ]; then ok "boot v$v: identical to AOSP unpack_bootimg"; else bad "boot v$v: differs from AOSP unpack_bootimg"; fi
  done
  for v in 3 4; do
    ( cd "$MKDIR" && mkbootimg --vendor_boot "vb_v$v.img" --vendor_ramdisk vrd.bin \
        --header_version $v --pagesize 4096 ) >/dev/null 2>&1
    [ -f "$MKDIR/vb_v$v.img" ] || { note "mkbootimg could not build a vendor_boot v$v image"; continue; }
    mkdir -p "$WORK/aospvb$v" "$WORK/minevb$v"
    ( cd "$WORK" && unpack_bootimg --boot_img "mk/vb_v$v.img" --out "aospvb$v" --format=mkbootimg ) >/dev/null 2>&1
    python3 "$ROOT/scripts/lib/bootimg.py" extract "$MKDIR/vb_v$v.img" "$WORK/minevb$v" >/dev/null 2>&1
    same=1
    for f in "$WORK/aospvb$v"/*; do
      [ -f "$f" ] || continue
      case "$(basename "$f")" in vendor-ramdisk-by-name) continue ;; esac
      [ -s "$f" ] || continue
      cmp -s "$f" "$WORK/minevb$v/vb_v$v.$(basename "$f")" || same=0
    done
    if [ "$same" -eq 1 ]; then ok "vendor_boot v$v: identical to AOSP unpack_bootimg"; else bad "vendor_boot v$v: differs from AOSP unpack_bootimg"; fi
  done
else
  note "mkbootimg/unpack_bootimg not installed - skipping the AOSP cross-validation"
fi

echo "== device-info.sh without a device"
if command -v adb >/dev/null 2>&1; then
  n=$(adb devices 2>/dev/null | awk 'NR>1 && $2=="device"' | wc -l | tr -d ' ')
  if [ "${n:-0}" -gt 0 ]; then
    note "a device is connected - skipping the no-device check"
  else
    bash "$ROOT/scripts/device-info.sh" "$WORK/recon" >/dev/null 2>&1
    rc=$?
    if [ "$rc" -ne 0 ]; then ok "exits non-zero without a device (rc=$rc)"; else bad "should fail without a device"; fi
  fi
else
  note "adb not installed - skipping"
fi

echo "== backup-partitions.sh dry run"
if bash "$ROOT/scripts/backup-partitions.sh" --help >/dev/null 2>&1; then
  ok "backup-partitions.sh --help"
fi

echo ""
echo "smoke: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
