# postmarketOS: existing ports and new ports

Verify current syntax with `pmbootstrap --help` and the postmarketOS wiki; flags and
device categories change between releases. The authoritative guides are listed in
`references/ecosystem.md`.

## A. Device already supported

1. Look up the codename on the wiki device page. Note category (main/community/testing), what works, install method, known bootloader quirks.
2. `pmbootstrap init` (choose vendor, codename, user interface, init options). Work inside the pmbootstrap chroot only.
3. `pmbootstrap install` builds the rootfs and boot image.
4. Non-persistent test first: `pmbootstrap flasher boot` (RAM boot via fastboot). If it works, continue.
5. Persistent flash (Tier 2, confirmation gate): `pmbootstrap flasher flash_kernel` then `pmbootstrap flasher flash_rootfs` (or the method the device page specifies: fastboot, heimdall, sideload, etc.). Mind A/B slot and the partition names on the device page.
6. Recovery: keep stock boot.img backed up; reflash with `fastboot flash boot stock_boot.img` (slot-aware).

### Useful pmbootstrap commands

| Command | Purpose |
|---|---|
| `pmbootstrap init` | create the build environment |
| `pmbootstrap shell` | shell inside the chroot (use it to edit the kernel package) |
| `pmbootstrap info` | show the current configuration |
| `pmbootstrap install` | build rootfs + boot image |
| `pmbootstrap initfs` | build a minimal initramfs for RAM boots |
| `pmbootstrap flasher boot` | RAM boot (fastboot boot), non-persistent |
| `pmbootstrap flasher flash_kernel` | write the kernel/boot image (Tier 2) |
| `pmbootstrap flasher flash_rootfs` | write the rootfs/rootfs image (Tier 2) |
| `pmbootstrap kconfig merge` / `check` | merge and validate the kernel config |
| `pmbootstrap linux` | build the kernel inside the chroot |
| `pmbootstrap log` | show the build log |
| `pmbootstrap clean` | remove the build directory |

### Notes for existing ports
- The wiki page may specify `fastbootd` instead of `fastboot` (dynamic partition
  devices): flashing a partition that lives in `super` requires the userspace
  fastboot (`adb reboot fastboot`).
- If the device is A/B, flash the *other* slot first so the working slot stays
  bootable: `fastboot flash boot --slot _b pmos.img`, verify, then `fastboot set_active _b`.
- Some pages require `fastboot flash vbmeta --disable-verity --disable-verification`
  before a custom kernel boots: that is a Tier 2 action with a real security
  consequence (the verified boot chain no longer protects the device).
- postmarketOS images expect a specific `cmdline` and page size; copying the
  `deviceinfo` from the wiki page is safer than inventing one.

## B. New port

Goal order: (1) boots to initramfs with USB networking, (2) SSH/telnet debug, (3) display + framebuffer, (4) touch, (5) storage, (6) Wi-Fi/BT, (7) GPU, (8) modem/audio/sensors.

1. From recon + firmware triage collect: SoC/platform, kernel version, `cmdline`, boot header version, page size, kernel/ramdisk/dtb offsets, dtb model/compatible, partition names, A/B flag, display panel name, touch IC, Wi-Fi chip.
2. `pmbootstrap bootimg_analyze stock_boot.img` (or `python3 scripts/lib/bootimg.py info stock_boot.img`) to seed `deviceinfo` values (cmdline, offsets, pagesize, header version, dtb).
3. Create packages `device-<vendor>-<codename>` and `linux-<vendor>-<codename>` following the wiki "Porting to a new device" guide. Start from the vendor downstream kernel (download from the vendor's GPL source release; match the exact build) or from mainline, and add a defconfig; use `pmbootstrap kconfig check`.
4. Fill `deviceinfo` (name, manufacturer, codename, arch, chassis, flash method, cmdline, page size, boot image header version, dtb, `deviceinfo_generate_bootimg`, etc.).
5. Iterate with `pmbootstrap flasher boot` (never persistent until it boots). Use serial/USB debug (`pmbootstrap initfs`, telnet to 172.16.42.1 on USB networking).
6. Only after stable RAM boots, flash persistently with the full gate in SKILL.md.
7. Document status per subsystem in the device wiki page format; aim to upstream.

The detailed bring-up order, the failure table and the package layout are in
`references/porting-playbook.md`. The kernel, device tree and config workflow is in
`references/kernel-and-dts.md`.

## Tips
- Mainline is cleaner long-term; downstream is faster to first boot. Say which one you choose and why.
- Keep all kernel config/patch changes in version control.
- If the device lacks `fastboot boot`, use a separate test slot (A/B) or a dedicated recovery partition; if neither exists, state the added risk explicitly.
- Ship the port with a status table: the wiki page format, with each subsystem marked
  working / partial / broken. Honest tables get more upstream contributions than
  optimistic ones.
