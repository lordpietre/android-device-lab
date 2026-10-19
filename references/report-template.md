# REPORT.md template

Copy this into the work directory (`./recon-<codename>/REPORT.md`) and fill it in.
Keep the three levels of certainty separate: **observed** (read from the device or
firmware), **documented** (vendor/wiki statement, with the source), **assumed**
(inference by the assistant).

```markdown
# Device report: <manufacturer> <model> (<codename>)

- Date (UTC): <YYYY-MM-DDTHH:MM:SSZ>
- Device hash: <first 8 hex of sha256 of the serial - never the serial itself>
- Host tooling: adb <ver>, fastboot <ver>, pmbootstrap <ver>
- Work directory: <path>

## 1. Device facts (observed)

| Field | Value | Source |
|---|---|---|
| Manufacturer / model | | props_key.txt |
| Codename (ro.product.device) | | props_key.txt |
| SoC / platform | | props_key.txt, kernel.txt |
| Android version / SDK / patch | | props_key.txt |
| Kernel version | | kernel.txt |
| A/B / slots | | props_key.txt |
| Dynamic partitions | | props_key.txt |
| Treble | | props_key.txt |
| Bootloader locked | | props_key.txt |
| Verified boot state | | props_key.txt |
| OEM unlock supported/allowed | | props_key.txt |
| Display | | hardware.txt |
| Battery | | hardware.txt |
| Partition layout | | storage.txt |

## 2. Firmware analysis (observed)

- Package: <file> sha256 <hash>
- Boot header: header version <v>, page size <n>, cmdline `<...>`
- Kernel string: <Linux version ...>
- Device tree model: <model> / compatible <...>
- AVB: rollback index <n>, flags <...>
- Partition scheme: <A/B, dynamic, sparse...>

## 3. Feasibility verdict

- postmarketOS support: <supported (category)> / <sibling port> / <no port>
  - Source: <wiki URL, checked on <date>>
- Bootloader unlock: <possible / blocked by X>
- Mainline status of the SoC: <...>
- **Verdict: GO / GO WITH CONDITIONS / NO-GO**
- Conditions: <what must be true before flashing>

## 4. Backups

| Partition | File | Size | sha256 |
|---|---|---|---|
| boot | backups/boot.img | | |
| persist | | | |

Verified: <yes/no>. Storage location: <path> (contains device-unique identifiers,
not to be published).

## 5. Actions taken

| # | Command | Tier | Result |
|---|---|---|---|
| 1 | `adb devices` | 0 | |

## 6. Not done / refused

- <command> - refused because <reason>

## 7. Open issues and risks

- <anti-rollback, eFuse/Knox, warranty, data wipe, missing recovery path...>

## 8. Next steps

1. <...>
```

## Rules for the report

- Never paste a serial, IMEI, MAC address or account name. Use the device hash.
- Never paste a full `getprop` dump; reference the files instead.
- Quote exact commands, including the `-s <serial>` form.
- State explicitly which claims are observed and which are assumed.
- If a step was not performed, say so. A hole in the record is more useful than a
  confident guess.
