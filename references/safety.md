# Safety reference

## Before any write to a device
- Battery above 60%, original cable, no hubs, stable host (no sleep/suspend).
- Identify the exact model + region variant. Firmware for a sibling model is the classic way to brick.
- Know the recovery path BEFORE flashing: fastboot recovery, Odin/download mode, Qualcomm EDL (9008), MediaTek BROM/preloader (SP Flash Tool / mtkclient), Rockchip maskrom, Pixel/Google factory images.
- Unlocking the bootloader usually wipes /data. Say so and confirm the user's data is backed up.
- Calibration partitions (persist, efs, modemst1/2, nvdata/nvram, proinfo, protect_f/s) are device-unique and are not in any firmware package. Back them up first when possible.

## Pre-flight checklist (run before every Tier 2 command)
1. `fastboot devices` / `adb devices` shows exactly the intended device.
2. Battery > 60% and the cable is stable.
3. The exact firmware/image file was hashed (`sha256sum`) and the hash recorded.
4. The stock image for the current slot is backed up and verified.
5. The device-unique calibration partitions are backed up, or the user explicitly accepted the risk.
6. The recovery path for this exact model is known and reachable.
7. Anti-rollback was checked (`fastboot getvar anti`, vbmeta rollback index): the image to flash is not older than what is installed.
8. The user saw the flash-gate checklist and answered "yes" to that exact command.

## Anti-rollback and verified boot
- Many vendors (Xiaomi, Samsung, Oppo/OnePlus, Google, Qualcomm devices with rollback index) refuse older bootloaders/firmware and can hard-brick. Never flash an older bootloader/firmware than installed without checking the rollback index (`fastboot getvar anti`, vbmeta rollback_index, vendor docs).
- vbmeta: flashing with `--disable-verity --disable-verification` is a Tier 2 action; state why.
- Re-locking the bootloader with a non-stock OS can brick. Do not suggest it.

## Vendor notes (verify with current docs; policies change)
- Samsung: Odin/download mode, KG/RMM state (can block unlock for a week or permanently), Knox eFuse trips irreversibly.
- Xiaomi: Mi Unlock account + waiting period; anti-rollback (`anti` var); fastbootd vs fastboot.
- Pixel/OnePlus: `fastboot flashing unlock`; A/B slots; flash both slots consciously.
- MediaTek: preloader corruption = no fastboot; need BROM tools and a donor preloader.
- Qualcomm: EDL needs a signed firehose loader on many newer models; keep stock firehose if available.
- Carrier-locked / enterprise-managed (MDM) / FRP-locked devices: do not attempt bypasses. Ask for proof of ownership context; refuse circumvention of theft protections (FRP, activation lock, IMEI changes).

## Recovery paths by platform

| Platform | Emergency path | Notes |
|---|---|---|
| Qualcomm | EDL 9008 + firehose loader | Loader is model-specific and vendor-signed; keep a copy of the stock one |
| MediaTek | BROM (preloader absent) / DA mode | `mtkclient` can read calibration and write in BROM |
| Samsung | Odin download mode | Needs the exact model/region firmware |
| Rockchip | Maskrom / Loader | Requires the vendor loader and rkdeveloptool |
| Exynos | Download mode | Vendor tools only |
| AOSP/Google | `fastboot flashing unlock` + factory images | Factory images are region-locked; check the model suffix |

If no recovery path is confirmed for the exact model, do not perform Tier 2 or 3
actions. State the risk and let the user decide with full information.

## Forbidden by default (Tier 3)
`fastboot erase *`, `fastboot format *`, `fastboot flash` of bootloader/aboot/abl/xbl/sbl/tz/hyp/modem/radio/preloader/persist/efs/nvram, `dd of=/dev/block/*`, anything that changes IMEI/serial/baseband identity, `flashing lock` on custom OS.

Also forbidden: FRP/activation-lock bypass, IMEI/serial modification, baseband identity
changes, and defeating carrier locks. These are theft protections, not obstacles to
"unlock a phone".

## When the user insists on a Tier 3 action
1. Restate the concrete risk: what bricks, what is unrecoverable, which eFuse trips.
2. Show the recovery path, or state that there is none.
3. Require an explicit, informed override in the conversation.
4. If the action is an anti-theft bypass rather than a technical risk, refuse.

## Reporting
Always list: what was changed, how to revert, what could not be reverted (eFuse, rollback counters, data wipe).
Never include serials, IMEIs or MAC addresses in the report; use the device hash.
