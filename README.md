# android-device-lab

An [opencode](https://opencode.ai) skill for **safe analysis of Android phones and
tablets** and for **porting them to Linux / postmarketOS**.

It gives an agent the workflow, the tooling and the guard rails to:

- identify a device (SoC, codename, partitions, A/B, Treble, dynamic partitions),
  read-only, over `adb` or `fastboot`;
- triage firmware offline (factory images, OTA payloads, vendor tarballs) without
  executing anything from them;
- judge whether a bootloader can be unlocked and whether a postmarketOS port is
  realistic;
- prepare a port (kernel, device tree, `deviceinfo`, initramfs bring-up) and flash
  only when every safety gate has passed.

Everything destructive is behind a gate: read-only first, verified backup before any
write, the exact command shown before it runs, and an explicit confirmation.

## Install

The skill id is the directory name, so the folder has to be called `android-device-lab`.

```bash
# global (recommended)
git clone https://github.com/<you>/android-device-lab.git ~/.config/opencode/skills/android-device-lab

# project-local
git clone https://github.com/<you>/android-device-lab.git .opencode/skills/android-device-lab
```

opencode also reads `~/.claude/skills/`, `~/.agents/skills/`, `.claude/skills/` and
`.agents/skills/`, so the same folder works with the Claude-style layout.

### Permissions (recommended)

Copy `assets/opencode.permissions.example.json` (opencode V2) or
`assets/opencode.permissions.v1.example.json` (opencode V1) into your
`opencode.json(c)` and merge the `permissions` array. Those rules allow the
read-only commands, ask before any write to a device, and deny the operations that
can hard-brick a phone.

> The last matching rule wins, so the broad `"*": "ask"` rule comes first and the
> specific rules follow it.

## Host requirements

`bash scripts/setup-host.sh --check` reports what is missing.

| Tool | Required | Purpose |
|---|---|---|
| `adb`, `fastboot` | yes | device access |
| `python3` | yes | bundled boot image parser |
| `dtc`, `lz4`, `unzip`, `7z`, `strings`, `file` | recommended | firmware analysis |
| `avbtool`, `payload-dumper-go`, `simg2img`, `lpunpack`, `unpack_bootimg` | optional | deeper firmware analysis |
| `pmbootstrap`, `git`, `curl` | optional | building and flashing postmarketOS |

```bash
bash scripts/setup-host.sh --minimal   # adb + fastboot
bash scripts/setup-host.sh --full      # the full toolchain (never removes or downgrades)
```

## Usage

```bash
# 1. read-only reconnaissance
bash scripts/device-info.sh ./recon-<codename>
bash scripts/device-info.sh ./recon-<codename> --fastboot   # bootloader mode

# 2. offline firmware triage
bash scripts/firmware-triage.sh firmware.zip ./fw-<name>

# 3. back up the device-unique partitions (read-only on the phone)
bash scripts/backup-partitions.sh --list
bash scripts/backup-partitions.sh --group all --yes

# 4. inspect a boot image without any extra dependency
python3 scripts/lib/bootimg.py info boot.img
```

Then ask opencode: *"analyze this phone with android-device-lab"*, *"can this device
run postmarketOS?"*, *"prepare a port for <codename>"*.

## Safety model

| Tier | Meaning | Rule |
|---|---|---|
| 0 | Read-only (recon, `getvar`, offline firmware analysis) | run freely |
| 1 | Reversible (reboot, pull, RAM boot, host installs) | say what you are doing |
| 2 | Persistent writes (`fastboot flash`, unlock, sideload) | backup + exact command + confirmation |
| 3 | Irreversible (erase, format, bootloader/modem/persist, re-lock) | refused unless explicitly overridden |

Hard rules: never write to the device before the recon report exists, never touch
bootloader/modem/persist/efs/nvram partitions, never flash without a verified
backup, never bypass FRP/activation locks or modify IMEI, and never present an
assumption as a fact.

## Repository layout

```
android-device-lab/
├── SKILL.md                        the skill itself
├── scripts/
│   ├── setup-host.sh               install/verify the host toolchain
│   ├── device-info.sh              read-only recon (adb / fastboot)
│   ├── firmware-triage.sh          offline firmware unpack + inventory
│   ├── backup-partitions.sh        read-only backup of unique partitions
│   ├── lint.sh                     repository self-check
│   └── lib/bootimg.py              dependency-free boot image parser
├── references/
│   ├── safety.md                   tiers, brick risks, recovery paths
│   ├── pmos-porting.md             postmarketOS flow (existing + new ports)
│   ├── porting-playbook.md         bring-up order, failure table, package layout
│   ├── kernel-and-dts.md           kernel, device tree, defconfig workflow
│   ├── firmware-analysis.md        formats, tools, what to extract
│   ├── tooling.md                  every tool: what it does, how to install it
│   ├── ecosystem.md                upstream wiki, DTS, kernels, specs
│   └── report-template.md          REPORT.md skeleton
├── assets/
│   ├── opencode.permissions.example.json      opencode V2 rules
│   ├── opencode.permissions.v1.example.json   opencode V1 rules
│   └── opencode.example.json                  full config example
├── tests/smoke.sh                  offline smoke tests (no device needed)
└── .github/workflows/ci.yml        lint + smoke tests on every push
```

## Development

```bash
make lint     # syntax, frontmatter, internal links, JSON validity
make test     # offline smoke tests (no device required)
make package  # build android-device-lab.zip
```

Contributions are welcome: read [CONTRIBUTING.md](CONTRIBUTING.md). Any change that
weakens a safety rule must be argued in the pull request.

## Disclaimer

This project is not affiliated with Google, Samsung, Xiaomi, OnePlus, the
postmarketOS project or any vendor. You flash your own device, at your own risk.
A bricked phone is a dead phone: the risk and the recovery path are stated before
every write, and the final decision is always the user's.

## License

MIT - see [LICENSE](LICENSE).
