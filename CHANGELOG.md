# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `scripts/install.sh`: one-command installer. It installs the skill into
  `~/.config/opencode/skills/android-device-lab` (or a project directory) and
  merges the permission rules into `opencode.json`, keeping a `.bak` of the
  previous config. Supports `--project`, `--no-permissions`, `--uninstall` and
  `--yes`.
- `scripts/setup-host.sh`: installs and verifies the host toolchain (adb, fastboot,
  dtc, avbtool, payload-dumper-go, simg2img, lpunpack, pmbootstrap, mtkclient) with
  `--check`, `--minimal`, `--full`, `--dry-run` and `--prefix`. It never removes or
  downgrades packages and prints the sha256 of every downloaded binary.
- `scripts/backup-partitions.sh`: read-only backup of the device-unique partitions
  (boot-like, vbmeta, persist/efs/nvdata/proinfo...) with sha256 manifest, A/B aware,
  and a `--list` / `--plan` mode that prints before reading.
- `scripts/lib/bootimg.py`: dependency-free parser for `boot`, `init_boot` and
  `vendor_boot` images (header version, cmdline, page size, kernel/ramdisk/dtb
  extraction, embedded DTB model). The field layout follows AOSP's
  `system/tools/mkbootimg`, and the smoke tests cross-validate the extraction
  byte-for-byte against `unpack_bootimg` for boot v0-v4 and vendor_boot v3-v4.
- `scripts/lint.sh`: repository self-check (shell syntax, shellcheck, python syntax,
  JSON validity, frontmatter rules, internal links, executable bits).
- `references/porting-playbook.md`: bring-up order, failure table, package layout,
  definition of done for a port.
- `references/kernel-and-dts.md`: kernel base selection, device tree extraction and
  conversion, kernel configuration, boot image construction.
- `references/tooling.md`: what every tool does and how to install it.
- `references/ecosystem.md`: authoritative upstream sources (postmarketOS wiki,
  mainline DTS, AOSP specs, vendor GPL sources) and unlock policies.
- `references/report-template.md`: REPORT.md skeleton separating observed,
  documented and assumed facts.
- `tests/smoke.sh`: offline smoke tests (synthetic boot image, firmware triage,
  script help output) that need no device.
- `.github/workflows/ci.yml`: lint + smoke tests on push and pull request.

### Changed
- `SKILL.md`: added the host-preparation step, the backup gate, the scripting
  references and a tenth prime directive about ownership and anti-theft limits.
- `scripts/device-info.sh`: `--help`, `--list`, `--serial`, binary-safe device tree
  reads via `adb exec-out`, fastboot partition sizes and anti-rollback variable,
  more properties, better error messages.
- `scripts/firmware-triage.sh`: uses the bundled parser when `unpack_bootimg` is
  absent, handles `super.img` with `lpunpack`, supports the python `payload_dumper`
  output layout, and documents Qualcomm/MediaTek partition maps.
- `assets/opencode.permissions.example.json`: converted to the opencode V2 schema
  (`permissions` array with `action`/`resource`/`effect`, `shell` instead of `bash`)
  and extended with rules for the new scripts.
- Repository layout: the skill now lives at the repository root, so
  `git clone <repo> ~/.config/opencode/skills/android-device-lab` installs it.

### Added (compatibility)
- `assets/opencode.permissions.v1.example.json`: the same rules for opencode V1.
- `assets/opencode.example.json`: a complete example configuration.

### Removed
- The duplicated `SKILL.md` at the workspace root (identical copy of the skill file).
- The stale `android-device-lab.zip` build artifact (regenerate with `make package`).
