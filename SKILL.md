---
name: android-device-lab
description: Safe analysis of Android phones and tablets via adb/fastboot, firmware triage, and planning or executing postmarketOS / Linux ports and installs. Use whenever the user mentions adb, fastboot, bootloader unlock, identifying an Android device (SoC, partitions, A/B, Treble, dynamic partitions), firmware/OTA/factory images, boot.img, vendor_boot, dtb, vendor kernel, postmarketOS, pmbootstrap, mainline Linux on a phone or tablet, or flashing a custom OS, even if they do not say "skill". Enforces read-only-first, backup-before-write and explicit confirmation before anything destructive.
license: MIT
compatibility: opencode (also works as a Claude-style skill). Needs adb and fastboot (android-platform-tools); optional pmbootstrap, avbtool, unpack_bootimg, payload-dumper-go, simg2img, lpunpack, fsck.erofs, dtc, binwalk. scripts/setup-host.sh installs them.
metadata:
  domain: android-hardware
  risk: high-when-flashing
---

# Android Device Lab

Analyse Android phones/tablets, assess whether Linux / postmarketOS can run on them,
prepare ports, and flash only when every safety gate has passed.
Reply in the language of the user. Keep commands and file names in English.

Skill id in opencode is the directory name (`android-device-lab`); the frontmatter
`name` is only a display label.

## Prime directives

1. **Read-only first.** Always start with `scripts/device-info.sh`. Do not write to the device until the report exists and the user has read it.
2. **One device, one serial.** If more than one device is connected, stop and ask which serial. Always use `adb -s <serial>` / `fastboot -s <serial>` once chosen.
3. **Never improvise destructive commands.** Anything in Tier 2 or 3 (see below) requires: backup verified, exact command shown, user confirmation in this conversation. Never chain it with `&&` to other actions.
4. **Prefer non-persistent tests.** Use `fastboot boot <img>` (RAM only) before `fastboot flash`. If the target does not support it, say so and explain the added risk.
5. **Never touch low-level partitions** (bootloader, aboot/abl/xbl, sbl, tz, modem/radio, preloader, persist, efs, nvram/nvdata, frp, rpmb) unless the user explicitly asks, understands that this can hard-brick the device, and a recovery path (EDL, BROM, Odin download mode, etc.) is confirmed for that exact model.
6. **Treat firmware as untrusted.** Extract into a work directory, never execute or mount-as-root anything from it, verify hashes against the vendor source when available.
7. **Privacy.** Do not print or store IMEI, serial in clear, MAC addresses, account names. The scripts redact these; keep it that way in reports. Partition backups contain unique identifiers: keep them local, never commit or upload them.
8. **Say what you don't know.** If a model/SoC is not in the postmarketOS device list or the unlock status is unclear, say so instead of guessing.
9. **Verify, never assume.** Device support, unlock policy and rollback indexes change; check the current wiki/vendor documentation instead of relying on memory.
10. **The user keeps ownership of their phone.** This skill assists the owner of a device they own. Never assist with FRP/activation-lock bypass, IMEI/serial rewriting, anti-theft circumvention or locked-carrier defeat.

## Safety tiers

| Tier | Meaning | Examples | Rule |
|---|---|---|---|
| 0 | Read-only | `adb devices`, `adb shell getprop`, `fastboot getvar`, reading files, offline firmware analysis | Run freely |
| 1 | Reversible, device-side or host-side state | `adb reboot`, `adb pull`, `adb install`, `fastboot boot`, `adb shell settings`, installing host packages | Tell the user what you are doing |
| 2 | Modifies persistent storage or security state | `fastboot flash boot/recovery/vbmeta/system`, `fastboot flashing unlock`, `adb sideload`, `fastboot set_active` | Backup + exact command + explicit confirmation |
| 3 | Can brick or wipe irrecoverably | `fastboot erase`, `fastboot format`, `flashing lock` with custom OS, flashing bootloader/modem/persist, `dd of=/dev/block/*`, anti-rollback bumps | Refuse by default; only with explicit, informed override |

Full rules and per-vendor pitfalls: `references/safety.md`.

## Workflow

### 0. Prepare the host (Tier 1 on the PC, never on the phone)

```bash
bash scripts/setup-host.sh --check      # what is missing (read-only)
bash scripts/setup-host.sh --minimal    # adb + fastboot
bash scripts/setup-host.sh --full       # + dtc, lz4, avbtool, payload-dumper-go, simg2img,
                                        #   lpunpack, pmbootstrap, mtkclient
```

The script only installs what is missing, never removes or downgrades packages,
and prints the sha256 of every binary it downloads. Run `--dry-run` first if the
user wants to see the plan. If the machine is locked down, fall back to manual
install using `references/tooling.md`.

### 1. Recon (Tier 0)
```bash
bash scripts/device-info.sh ./recon-<codename>           # adb mode
bash scripts/device-info.sh ./recon-<codename> --fastboot  # bootloader mode
bash scripts/device-info.sh --list                       # what is attached
```
Read `summary.md` and the raw files. Report: manufacturer, model, codename, SoC/platform,
Android version and security patch, bootloader lock state, verified boot state, A/B or not,
dynamic partitions, Treble, kernel version, partition layout, display, battery.
Every claim in the report must be traceable to a file in the recon directory.

### 2. Feasibility assessment
- Check the postmarketOS wiki device list for the codename (`references/ecosystem.md`): classify as already supported (community/main/testing), supported on a close sibling (same SoC/board), or no port.
- Check whether the bootloader can be unlocked (vendor policy, waiting periods, carrier locks, OEM unlock toggle, data wipe on unlock, warranty/Knox/eFuse effects).
- Check SoC tier: Qualcomm (mainline support varies; EDL recovery often available), MediaTek (preloader/BROM, vendor kernels common), Exynos/Unisoc/Rockchip/Allwinner (case by case).
- Check anti-rollback (`fastboot getvar anti`, vbmeta rollback index) before proposing any flash.
- Give the user a go/no-go with risks before proposing any write.

### 3. Backup gate (Tier 1 → required before Tier 2)

```bash
bash scripts/backup-partitions.sh --list            # what exists on this device
bash scripts/backup-partitions.sh --group core --plan
bash scripts/backup-partitions.sh --group all --yes  # pulls + sha256 + manifest
```

`core` covers boot-like and vbmeta partitions; `all` adds the device-unique
calibration partitions (persist, efs, modemst, nvdata, proinfo, protect_*). These
hold the unique IMEI/Wi-Fi/sensor calibration and exist in **no** firmware
download, so a factory reflash does not restore them. The script reads only;
it never writes a partition. If the device is not rooted, say so and offer the
alternatives (`adb root` on userdebug builds, a custom recovery, or accepting
the risk explicitly). Also remind the user to copy their own data (photos,
messages, authenticator seeds) - `adb backup` is deprecated and unreliable.

Do not proceed to Tier 2 without a verified backup of at least boot + the
calibration partitions, or an explicit "I accept the risk".

### 4. Firmware analysis (offline, Tier 0 on the host)
```bash
bash scripts/firmware-triage.sh <firmware.zip|payload.bin|image.img> ./fw-<name>
```
Details and tool usage: `references/firmware-analysis.md`. Produce: manifest with hashes,
image types, AVB/vbmeta info, boot header (kernel cmdline, page size, header version, dtb),
partition scheme (super/dynamic), kernel version string, device tree model/compatible.
The bundled parser (`scripts/lib/bootimg.py`) reads boot/vendor_boot/init_boot
headers with no extra dependency; `unpack_bootimg` and `pmbootstrap
bootimg_analyze` add detail when installed.

### 5. Install path
- **A. Existing postmarketOS port**: follow `references/pmos-porting.md` section A. Use `pmbootstrap` for build and flash; test with `pmbootstrap flasher boot` (or `fastboot boot`) first.
- **B. New port**: follow `references/pmos-porting.md` section B and `references/porting-playbook.md`. Start from the stock boot image analysis, a downstream vendor kernel, and a `deviceinfo`; get "boots to initramfs with USB networking/telnet" first, then display, touch, storage, Wi-Fi, etc. Track the status per subsystem.
- **C. Generic Linux (Droidian, UBports, Halium, chroot/proot)**: lower risk options on stock Android. Offer them as alternatives when a native port is too risky.

### 6. Flash gate
Before every Tier 2 command, print this checklist and wait for "yes":
```
Device:        <model> / <codename> / serial hash <xxxxxxxx>
Mode:          fastboot | recovery | download
Bootloader:    unlocked? yes/no
Backup:        <path> (sha256 verified)
Image:         <file> sha256 <...>
Command:       <exact command>
Effect:        <what changes, what is lost>
Recovery path: <how to restore stock if it fails>
```
One command per confirmation. No `&&` chains. If the user asks for a Tier 3
action, restate the brick risk and the recovery path, and require an explicit
override; if there is no confirmed recovery path for that exact model, refuse.

### 7. Report
Write `REPORT.md` in the work directory (template: `references/report-template.md`):
device facts, evidence (file references), feasibility verdict, steps taken with
exact commands, backups with hashes, open issues, and a clear separation of
**observed** / **documented** / **assumed** facts.

## Output style
Short, factual. Distinguish **observed** (from the device/firmware), **documented**
(wiki/vendor), and **assumed** (your inference). Never present an assumption as a fact.
Use tables for device facts and subsystem status. Keep the exact commands you ran.

## Bundled resources
- `scripts/install.sh`: install the skill into opencode and merge the permission rules.
- `scripts/setup-host.sh`: install and verify the host toolchain.
- `scripts/device-info.sh`: read-only recon over adb/fastboot with redaction.
- `scripts/firmware-triage.sh`: safe offline unpack and inventory of firmware.
- `scripts/backup-partitions.sh`: read-only backup of device-unique partitions with hashes.
- `scripts/lib/bootimg.py`: dependency-free Android boot image header parser.
- `scripts/lint.sh`: repository self-check (run before committing changes).
- `references/safety.md`: tiers, vendor-specific brick risks, recovery modes.
- `references/pmos-porting.md`: postmarketOS flow for existing and new ports.
- `references/porting-playbook.md`: expert bring-up order, subsystem matrix, failure table.
- `references/kernel-and-dts.md`: kernel, device tree and defconfig workflow.
- `references/firmware-analysis.md`: formats, tools, what to extract.
- `references/tooling.md`: what each tool does and how to install it.
- `references/ecosystem.md`: authoritative upstream sources (wiki, DTS, kernels, specs).
- `references/report-template.md`: REPORT.md skeleton.
- `assets/opencode.permissions.example.json`: opencode V2 permission rules enforcing the tiers.
- `assets/opencode.permissions.v1.example.json`: same rules for opencode V1.
