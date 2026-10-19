# Firmware analysis

Everything in this file happens **offline, on the host, read-only**. Nothing is
executed, installed or mounted from the firmware.

## Formats
| Source | Container | Tool |
|---|---|---|
| Pixel / AOSP factory images | zip with images + flash-all | unzip, fastboot |
| A/B OTA | zip with `payload.bin` | payload-dumper-go |
| Samsung | AP/BL/CP/CSC `.tar.md5` (+ lz4) | tar, lz4 |
| Qualcomm full | `rawprogram*.xml`, `patch*.xml`, firehose `.mbn` | read XML to get partition map |
| MediaTek | scatter file + images | scatter.txt gives partition map |
| Sparse images | `system.img` etc. | simg2img |
| Dynamic partitions | `super.img` | lpunpack |
| Filesystems | ext4 / EROFS / f2fs | `debugfs -R`, `fsck.erofs --extract`, 7z; read-only, never run binaries |

## One-shot triage

```bash
bash scripts/firmware-triage.sh <firmware> ./fw-<name>
```

It extracts the container, unpacks `payload.bin` and `super.img` when the tools are
available, identifies every image by magic bytes, parses the boot headers, dumps the
AVB information and writes `manifest.md` with hashes and sizes.

## What to extract
- Boot images: header version, kernel cmdline, page size, offsets, dtb (`unpack_bootimg`, `pmbootstrap bootimg_analyze`, or the bundled `scripts/lib/bootimg.py`).
- Kernel version: `strings boot.img | grep 'Linux version'`; decompress `kernel` if needed (gzip/lz4) and re-run strings.
- Device tree: `dtc -I dtb -O dts` then check `model`, `compatible`, panel nodes, touch IC, regulators.
- vbmeta: `avbtool info_image` for rollback index, flags and chained partitions.
- Partition map: from `/dev/block/by-name` (device) or scatter/rawprogram (firmware).
- Vendor blobs: list only (`ls`), identify GPU/Wi-Fi/modem firmware names; do not redistribute them.

## Boot image headers in practice

```bash
python3 scripts/lib/bootimg.py info boot.img            # header, cmdline, page size, sizes
python3 scripts/lib/bootimg.py extract boot.img ./out     # kernel / ramdisk / dtb
python3 scripts/lib/bootimg.py dts boot.img               # dtb model + compatible
```

The parser understands the classic layout (v0-v3) and the v4 layout (Android 12+),
plus `vendor_boot`. It prints what it could not determine instead of guessing.

Key fields and what they break when wrong:

| Field | Breaks when wrong |
|---|---|
| `header_version` | the bootloader refuses or mis-parses the image |
| `page_size` | image is read at the wrong offsets (wrong kernel, empty screen) |
| `cmdline` (`root=`, `console=`, `androidboot.*`) | wrong rootfs, no console, no USB gadget |
| `dtb` | wrong panel/touch/regulators, black screen |
| `os_version` | the bootloader may reject the image on some devices |

## Super / dynamic partitions

```bash
lpunlock super.img ./unpacked/      # logical partitions
simg2img system.img system.raw.img   # sparse -> raw
fsck.erofs --extract=./erofs system.img   # EROFS, read-only
```

## Integrity and trust
- Compare SHA256 with the vendor's published value.
- Be suspicious of repacked/unsigned firmware from forums; analyse in a VM or container without network and never run extracted binaries.
- Keep a manifest: file name, hash, source URL, date.

## What the manifest must contain
File name, size, sha256, detected type, boot header fields, kernel version string,
dtb model/compatible, AVB rollback index and flags, partition map source, and a note
of which tools were missing (so a follow-up run can fill the gaps).
