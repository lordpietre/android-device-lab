# Porting playbook

Expert procedure to bring a new phone or tablet to a native Linux/postmarketOS port.
Read `references/kernel-and-dts.md` in parallel: it covers the kernel and device tree work.

## 0. Decide what "port" means

| Goal | Effort | Risk | Typical route |
|---|---|---|---|
| Boot a mainline kernel to initramfs | days–weeks | low (RAM only) | `pmbootstrap` + `fastboot boot` |
| Booting with display + touch | weeks | medium | mainline panel/touch drivers, deviceinfo |
| Daily driver with modem, camera, sensors | months | medium | vendor firmware blobs + community patches |
| Non-persistent install (no persistence, no data wipe) | hours | low–medium | `fastboot boot` of a stock-compatible kernel |
| Persistent install with a custom OS | hours | high | `fastboot flash boot` / `pmbootstrap flasher flash_rootfs` |

Always offer the lowest-risk option that satisfies the user. A RAM boot that works
today beats a persistent install that bricks on Friday.

## 1. Bring-up order (do not skip ahead)

1. **Initramfs + USB networking.** Nothing else matters until you can reach a shell.
2. **SSH/telnet debug access.** `172.16.42.1` over USB RNDIS (postmarketOS initfs
   uses telnet on port 23 in the initfs, SSH on 22 in the installed system).
3. **Display** (panel + backlight + DRM/DRM-KMS driver).
4. **Touch** and **hardware buttons**.
5. **Storage** (UFS/eMMC, filesystem, GPT, fstab, encryption).
6. **Wi-Fi / Bluetooth**.
7. **GPU / 3D** (Panfrost, Freedreno, Mali via Panfrost or Lima).
8. **Audio, sensors, modem, cameras, fingerprint**.

Track it in a status table (see `references/report-template.md`) so progress is visible
and comparable with the wiki page.

## 2. The first boot (RAM only)

```bash
pmbootstrap init                      # vendor, codename, ui, init options
pmbootstrap initfs                    # build a minimal initramfs
apk add --root .initfs --initdb --allow-untrusted -a /path/to/extra.apk   # optional
pmbootstrap flasher boot              # fastboot boot of the initfs image
```

While the initfs runs on the device:

- Serial console: `pmbootstrap flasher --serial`? (pmbootstrap exposes `pmbootstrap
  console`/`pmbootstrap flasher --list`; the usual approach is `fastboot boot` with
  `console=ttyMSM0,115200` in the cmdline and a UART/USB-serial adapter.)
- USB networking: the postmarketOS initfs brings up an RNDIS gadget; on the host run
  `ip addr` and look for `172.16.42.1`, then `telnet 172.16.42.1 23`.
- Logs: `pmbootstrap log`, and `dmesg` on the device.

**Never flash persistently while the RAM boot is not stable.** Every change to the
kernel, cmdline or initfs must be validated with `fastboot boot` first.

## 3. Common failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| No USB gadget, no telnet | kernel lacks `CONFIG_USB_CONFIGFS_F_FS` + `CONFIG_USB_GADGET` + RNDIS | enable in the kernel config; check `dmesg` for gadget errors |
| `initramfs panic: unable to mount` | wrong rootfs/partition layout | verify cmdline `root=` against the real GPT layout, and `CONFIG_BLK_DEV_INITRD` |
| Kernel panic very early | wrong dtb / wrong `console=` | try the vendor dtb from the stock boot image; add `earlycon` |
| Black screen but system boots | panel driver missing or wrong `compatible` | check `dmesg` for panel probe, add the matching `drm_panel_` driver, verify the regulator/timing nodes |
| Bootloop after `fastboot flash boot` | A/B slot mismatch, or the flashed image is wrong | flash the other slot (`fastboot flash boot --slot other`), keep the stock image at hand |
| `Verification failed` / orange state | AVB | `fastboot flash vbmeta --disable-verity --disable-verification vbmeta_empty.img` (Tier 2) or boot a signed kernel |
| `dm-verity` / `dm-verity` fails to mount system | verity mismatch after wiping super | flash the whole `super`/`system` from the vendor package, or disable verity |
| Root filesystem not found | wrong `root=`, wrong partition, storage driver missing | dump `cat /proc/partitions` and the GPT from recovery |
| Initramfs starts, rootfs fails | fstab entries, encryption (FBE), SELinux | inspect `dmesg` for mount errors, check `cryptsetup`/`fscrypt` support |
| Wi-Fi missing | no vendor firmware or no mainline driver | use `firmware` blobs from the vendor GPL release, load with `modprobe` |
| Antenna/modem dead | calibration partitions were overwritten | restore `persist`/`efs`/`nvdata` from the backup; never flash the `modem` partition |

## 4. Slot, dynamic partitions and persistence

- A/B devices: `fastboot flash boot --slot _a` and `--slot _b`; check
  `fastboot getvar current-slot` and `ro.boot.slot_suffix`. After flashing, verify
  the other slot still holds a working image: `fastboot set_active` is Tier 2.
- Dynamic partitions (`super`): a custom OS that does not use `super` needs the
  vendor `super.img` to stay intact for OTA/rollback. Prefer installing to `userdata`
  or a dedicated partition, or accept losing OTA updates.
- `vbmeta`: flashing `vbmeta` with `--disable-verity --disable-verification` is the
  standard entry point for custom kernels. It is Tier 2 and it weakens the
  verified boot chain: state the consequences.
- Re-locking the bootloader with a custom OS can permanently brick the device. Do
  not suggest it (`references/safety.md`).

## 5. Package structure (postmarketOS)

```
device-<vendor>-<codename>/
  APKBUILD            # metadata, depends, install scripts
  deviceinfo          # board description used to build the boot image
  init-boot.sh        # first-boot tweaks, fstab, firmware loading
linux-<vendor>-<codename>/
  APKBUILD            # kernel package: source, config, patches
  config             # kernel configuration (or config fragment + defaults)
  patches/            # out-of-tree patches
```

- `deviceinfo` keys that matter: `name`, `manufacturer`, `codename`, `arch`,
  `arch64`, `qemu`, `flash_method`, `bootimg_header_version`, `page_size`,
  `cmdline`, `dtb`, `deviceinfo_generate_bootimg`, `fdt`, `allowed_unsafe_access`.
- Test the metadata before building: `pmbootstrap kconfig check` and
  `pmbootstrap kconfig merge` (kernel config), `pmbootstrap build --dry-run`? (the
  build itself is `pmbootstrap build`).
- Keep the kernel in version control, one commit per functional change, and keep
  the patches minimal enough to be upstreamable.

## 6. Definition of done for a port

- Boots reliably to a shell over USB with the stock `fastboot` (RAM) image.
- Boots persistently from a slot, survives a reboot, and can be restored with the
  stock boot image.
- Display, touch, storage and network are documented as working.
- The status table is complete and honest about what is broken.
- The device page on the postmarketOS wiki is updated (or a patch is prepared).
