# Kernel and device tree workflow

Everything needed to turn a stock Android boot image into a bootable mainline Linux.

## 1. Identify the kernel you are replacing

From the recon (`scripts/device-info.sh`):

```bash
adb shell uname -a
adb shell cat /proc/version
adb shell cat /proc/cmdline
```

- `Linux version 4.4.302-perf+ ...` → the vendor kernel is 4.4 (2016-era). Mainline
  support for that SoC may exist or may not.
- `Linux version 5.10.177-android13-8-...` → a recent GKI/vendor kernel, mainline is
  usually closer.
- `Hardware : Qualcomm Technologies, Inc SM6375` in `/proc/cpuinfo` → the SoC codename
  is what you need, not the marketing name.

Map the marketing name to the SoC codename (`SM6375`, `MSM8998`, `MT6781`, `Exynos
2100`, ...) before looking for DTS files.

## 2. Get the device tree

### From the stock boot image

```bash
bash scripts/firmware-triage.sh boot.img ./fw-boot
python3 scripts/lib/bootimg.py extract boot.img ./fw-boot/unpacked   # vendor_boot/init_boot too
dtc -I dtb -O dts -o vendor.dts fw-boot/unpacked/boot.dtb
```

`bootimg.py info` prints the header (cmdline, page size, header version, dtb size)
without any extra tool.

For `vendor_boot` images the board DTB is usually appended to the vendor ramdisk
(`boot.img`/`vendor_boot.img` may not contain the DTB at all on Treble devices).

### From the kernel source

- Mainline: `arch/arm64/boot/dts/<vendor>/` in the Linux tree. Look for the board
  file, not just the SoC file: `<vendor>/<soc>.dtsi` + `<vendor>/<board>.dts`.
- Vendor (GPL release, mandatory by the GPL): the vendor's kernel source tarball,
  `arch/arm64/boot/dts/`.

### Converting a vendor DTB to a source DTS

```bash
dtc -I dtb -O dts -o vendor.dts vendor.dtb        # decompile
dtc -I dts -O dtb -o vendor-clean.dtb vendor.dts  # recompile (may warn)
```

Then hand-edit: fix `model`/`compatible`, drop vendor-specific nodes, and add the
mainline driver bindings the panel/touch/regulator need. Keep the decompiled file
as a reference, not as a build input.

Useful helpers: `fdtget`, `fdtdump` (device-tree-compiler package), `dtdiff`.

## 3. Choose the kernel base

| Base | When |
|---|---|
| Mainline (`torvalds/linux`) | long term, cleanest, needs DTS + driver work |
| postmarketOS kernel fork | pmOS-specific patches (initramfs, USB gadget) already applied |
| Vendor downstream kernel | fastest to first boot; huge diff, rarely upstreamable |

postmarketOS ports normally use the pmOS kernel fork with per-device patches in
`linux-<vendor>-<codename>`. Say explicitly which base you chose and why.

## 4. Kernel configuration

Minimum set for a phone/tablet bring-up:

```
CONFIG_USB_GADGET=y
CONFIG_USB_CONFIGFS=y
CONFIG_USB_CONFIGFS_F_FS=y
CONFIG_USB_CONFIGFS_RNDIS=y
CONFIG_USB_OTG=y
CONFIG_BLK_DEV_INITRD=y
CONFIG_EXT4_FS=y
CONFIG_SCSI=y / CONFIG_UFS=y / CONFIG_MMC=y      (storage)
CONFIG_DRM=y + CONFIG_DRM_PANEL_*=y              (display)
CONFIG_TOUCHSCREEN_*=y                           (touch)
CONFIG_SND_SOC=y                                 (audio)
CONFIG_WLAN_VENDOR_* / CONFIG_WLAN=y             (wifi)
```

Workflow with pmbootstrap:

```bash
pmbootstrap kconfig merge     # merge the device config with the kernel defaults
pmbootstrap kconfig check      # verify the merged config is valid
pmbootstrap linux              # build the kernel inside the chroot
```

Keep the config in the kernel package directory (`config` file or a fragment
applied by the APKBUILD) so the build is reproducible.

## 5. Build a boot image

The boot image is: header + kernel + ramdisk + (dtb) + (footer for v1-v3).

- `deviceinfo_generate_bootimg: true` lets pmbootstrap build the image from
  `deviceinfo` (cmdline, page size, header version, dtb).
- Manual build with `mkbootimg`:
  ```bash
  mkbootimg --header_version 4 --kernel Image --ramdisk initramfs \
            --cmdline "..." --output boot.img
  ```
- The bundled `scripts/lib/bootimg.py` can inspect what you produced, and
  `unpack_bootimg --format=mkbootimg` gives the full split.

Header versions: v0-v3 (classic, 32-bit era layout) vs v4 (Android 12+, 64-bit
layout with a 1536-byte cmdline). Mismatching the header version of the original
image is a classic "it worked with the vendor kernel but not with mine" bug.

## 6. DTB in the image, or DTB from the bootloader?

Some devices pass the DTB in the boot image, others expect the bootloader to
append it. The stock header tells you which: `dt_size`/`dtb_size` non-zero means
the DTB travels inside the image. If the original image has no DTB, the board DTB
must be loaded by the bootloader (or flashed to `dtbo`) and referenced by
`androidboot.dtb`/partition name.

## 7. Patches and hygiene

- One patch per driver/bug, with a `Signed-off-by` and a description of the
  hardware it touches.
- Never mix "make it boot" changes with "make it clean" changes.
- Keep a `NOTES.md` in the port directory: what was tried, what failed, and why.
- When the port becomes useful to others, upstream the kernel patches and open a
  pull request against the postmarketOS device list.

## 8. Verification checklist before flashing

```bash
sha256sum boot.img
python3 scripts/lib/bootimg.py info boot.img     # cmdline, page size, header version
fastboot boot boot.img                            # RAM only, no persistence
```
