# Ecosystem: where the ground truth lives

Policies, device support and vendor procedures change constantly. **Always check the
current page instead of trusting memory or this file.** These are the starting points.

## postmarketOS

| What | Where |
|---|---|
| Device list (supported / testing / community) | <https://wiki.postmarketos.org/wiki/Device_list> |
| Porting to a new device (authoritative guide) | <https://wiki.postmarketos.org/wiki/Porting_to_a_new_device> |
| `deviceinfo` reference | <https://wiki.postmarketos.org/wiki/Deviceinfo> |
| APKBUILD reference | <https://wiki.postmarketos.org/wiki/APKBUILD> |
| Kernel package reference | <https://wiki.postmarketos.org/wiki/Kernel_package> |
| pmbootstrap documentation | <https://docs.postmarketos.org/pmbootstrap/> |
| Port recipes (pmaports) | <https://gitlab.com/postmarketOS/pmaports> |
| pmbootstrap source | <https://gitlab.com/postmarketOS/pmbootstrap> |
| Mainline kernel fork used by pmOS | <https://gitlab.com/postmarketOS/linux> |
| Project chat | <https://matrix.to/#/#postmarketos:matrix.org> |

How to check a device quickly:

```bash
# Device page name is usually <vendor>_<codename>
curl -fsSL "https://wiki.postmarketos.org/wiki/Device_list" | grep -i "<codename>"
```

If the codename is absent, look for a sibling with the same SoC: a port for the
same board/SoC is a realistic starting point, but the panel, touch and regulators
usually differ.

## Mainline Linux

| What | Where |
|---|---|
| Kernel tree | <https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git> |
| ARM64 device trees | `arch/arm64/boot/dts/` in the tree above |
| Kernel releases | <https://kernel.org> |
| Patchwork / arm64 mailing list | <https://lore.kernel.org/linux-arm-kernel/> |

To know whether a SoC is supported upstream, look for its `.dtsi` in
`arch/arm64/boot/dts/<vendor>/` and for the driver in `drivers/`.

## Android internals

| What | Where |
|---|---|
| Boot image header (v0-v3) | <https://source.android.com/docs/core/architecture/boot-image/header> |
| Boot image header v4 | <https://source.android.com/docs/core/architecture/boot-image/header-v4> |
| Vendor boot image header | <https://source.android.com/docs/core/architecture/boot-image/vendor-boot-header> |
| Payload file format (OTA) | <https://source.android.com/docs/core/ota/payload-file> |
| AVB (verified boot) | <https://source.android.com/docs/security/features/verifiedboot/avb> |
| AOSP `avbtool` | <https://android.googlesource.com/platform/external/avb/> |
| AOSP `mkbootimg` | <https://android.googlesource.com/platform/tools/mkbootimg/> |
| AOSP device sources (DTS, drivers) | <https://android.googlesource.com/device/> |
| AOSP kernel sources | <https://android.googlesource.com/kernel/common/> |
| Treble / dynamic partitions | <https://source.android.com/docs/core/architecture/treble> |

## Vendor kernel sources (GPL releases)

The GPL requires vendors to publish their kernel source. The published tarball
usually matches the firmware build exactly - that matters, because the DTB and the
driver configuration must match the running kernel.

- Samsung: <https://opensource.samsung.com/>
- Xiaomi: <https://github.com/MiCode/Xiaomi_Kernel_OpenSource>
- OnePlus / Oppo / Realme: <https://github.com/OnePlusOSS/> and vendor pages
- Google (Pixel): <https://android.googlesource.com/device/google/> and the matching
  `kernel/google` branch
- LineageOS kernels: <https://github.com/LineageOS/android_kernel_manufacturers>

Match the release with the running kernel: `adb shell cat /proc/version` gives the
exact build string and the `uname -r` release number.

## Third-party tools

| Tool | Where | Note |
|---|---|---|
| `payload-dumper-go` | <https://github.com/ssut/payload-dumper-go> | OTA payload extraction |
| `android-image-tools` (`simg2img`) | <https://github.com/anestisb/android-image-tools> | sparse image conversion |
| `avbtool` | <https://github.com/google/avb> | vbmeta inspection and signing |
| `mtkclient` | <https://github.com/nelz9999/mtk-client> | MediaTek BROM/DA recovery |
| `libufdt` / `pyfdt` | <https://github.com/dgibson/libufdt> | device tree manipulation |

## Unlock policies (check the current vendor page)

- Google/Pixel and most AOSP vendors: developer options -> OEM unlocking, then
  `fastboot flashing unlock`. Expect a data wipe.
- Xiaomi/Redmi/POCO: Mi Unlock account, a binding period, and anti-rollback
  (`fastboot getvar anti`).
- Samsung: OEM unlock toggle, KG/RMM state, and an irreversible Knox eFuse trip.
- OnePlus/Oppo/Realme: OEM unlock, and their own fastbootd quirks.
- MediaTek and Unisoc: usually unlockable, but the preloader/BROM path is
  vendor-specific.

## Ethic and legality

- Only work on devices the user owns or is authorised to modify.
- Never assist with IMEI/serial rewriting, FRP or activation-lock bypass, baseband
  identity changes or defeating carrier locks.
- Vendor firmware blobs (GPU, Wi-Fi, modem) are usually not redistributable:
  reference them, do not republish them.
- Anti-theft protections exist for a reason. A bricked phone is a dead phone:
  the risk belongs to the user and must be stated plainly before any Tier 2 action.
