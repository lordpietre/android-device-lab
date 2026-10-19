# Tooling

What each tool does, which tier it belongs to and how to install it.
`bash scripts/setup-host.sh --check` prints the status of all of them on this host;
`--full` installs everything that is missing.

## Core (required)

| Tool | Purpose | Tier | Install |
|---|---|---|---|
| `adb` | device shell, properties, logcat, pull/push, sideload | 0–2 | `apt install adb` / `dnf install android-tools` / `pacman -S android-tools` / `brew install --cask android-platform-tools` |
| `fastboot` | bootloader protocol: `getvar`, `boot`, `flash`, `flashing unlock` | 0–2 | same package as `adb` |
| `python3` | runs the bundled parsers | 0 | everywhere |

## Analysis

| Tool | Purpose | Install |
|---|---|---|
| `dtc` | compile/decompile device trees (`dtc -I dtb -O dts`) | `apt install device-tree-compiler` / `dnf install dtc` / `pacman -S dtc` / `brew install dtc` |
| `unpack_bootimg` | split a boot image into kernel/ramdisk/dtb (AOSP `mkbootimg`) | not packaged by most distros: build from AOSP `platform/tools/mkbootimg`, use the `osm0sis/bootimg` release, or rely on the bundled `scripts/lib/bootimg.py` |
| `scripts/lib/bootimg.py` | bundled dependency-free boot image parser (header, cmdline, dtb extraction) | already here |
| `avbtool` | vbmeta inspection: rollback index, flags, chained descriptors | `pipx install "avbtool @ git+https://github.com/google/avb"` |
| `payload-dumper-go` | extract partitions from an A/B OTA `payload.bin` | GitHub release binary (the setup script fetches the latest release asset) |
| `simg2img` | convert Android sparse images to raw | `apt install android-sdk-libsparse-utils` or the `anestisb/android-image-tools` release |
| `lpunpack` | split `super.img` into its logical partitions | `apt install android-sdk-ext4-utils`? not packaged: `AndroidDumps/Ext4Extractor` release, or build from AOSP `system/extras` |
| `fsck.erofs` | read EROFS images read-only | `apt install erofs-utils` / `dnf install erofs-utils` |
| `e2fsck`/`debugfs` | read ext4 images read-only | `apt install e2fsprogs` |
| `lz4` | decompress Samsung/MTK firmware members | `apt install lz4` |
| `unzip`, `7z`, `file`, `strings` | open and identify vendor packages | `apt install unzip p7zip-full file binutils` |
| `binwalk` | signature scan of firmware (optional) | `pipx install binwalk` |

## Porting

| Tool | Purpose | Notes |
|---|---|---|
| `pmbootstrap` | build and flash postmarketOS | `pipx install pmbootstrap`; needs `sudo` for the chroot, `qemu-user-static` for foreign architectures |
| `git`, `curl` | fetch kernels, DTS and the pmOS port recipes | `apt install git curl` |
| `dtc` + `fdtget` | device tree work | as above |

## Recovery (expert, use only on a device you own)

| Tool | Purpose | Notes |
|---|---|---|
| `mtkclient` | MediaTek BROM/DA mode, preloader, partition read/write | `pipx install mtkclient`; `mtk rca` (read calibration), `mtk download` (write) |
| EDL / firehose loader | Qualcomm emergency download mode | The loader is vendor-signed per model; use only the one matching your device, and only for your own device |
| Odin | Samsung download mode (Windows) | Samsung firmware must match the exact model/region |
| SP Flash Tool | MediaTek scatter-file flashing (Windows) | Needs the vendor preloader and scatter file |

## Minimal host checklist

`adb`, `fastboot`, `python3`, `dtc`, `unzip`, `strings`, `file`, `jq`, `git`, `curl`.
Everything else is optional and only unlocks deeper analysis.

## Rules

- Prefer the packaged tool over a random binary from a forum. If you download one,
  record its sha256 and compare it with the release's published checksum.
- Never run a binary extracted from a firmware package. Analyse it, list it, hash it.
- Keep the host toolchain and the device toolchain (`adb`/`fastboot`) in sync with
  the platform-tools version the vendor expects when a command fails oddly.
