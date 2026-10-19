# Security policy

## Scope

This repository ships instructions and scripts that run on a **host** computer and
talk to a **device the user owns**. The risks that matter here are:

- the skill performing a destructive operation on a device it should not;
- the skill leaking device-unique identifiers (serials, IMEIs, MAC addresses,
  calibration data) into logs, reports or the repository;
- the skill executing code that came from an untrusted firmware package.

## Reporting a problem

Open a private security advisory on the repository (GitHub: *Security* -> *Report a
vulnerability*) or contact the maintainer privately. Please include:

- what the skill did or proposed to do;
- the exact command and the tier it should have been in;
- how someone could be harmed by it (brick, data loss, leaked identifiers);
- the steps to reproduce, with identifiers redacted.

Do not include real serials, IMEIs, MAC addresses or partition dumps in the report.
Use the device hash (`sha256` prefix) that the scripts print.

## What is considered a vulnerability

- a command that writes to the device without passing the backup gate or the
  explicit confirmation;
- a Tier 3 operation (erase, format, bootloader/modem/persist, re-lock) that the
  skill would perform without an informed override;
- any path that leaks or stores device-unique identifiers in clear;
- any code path that executes or mounts content extracted from a firmware package;
- a rule in the permission examples that would allow a destructive command.

## What is not a vulnerability

- the documented risk of flashing a phone (the user accepts it explicitly);
- vendor firmware behaving unexpectedly;
- a device that bricks when the vendor's own tooling is used incorrectly;
- the skill refusing an unsafe request.

## Hardening notes for maintainers

- Keep `assets/opencode.permissions.example.json` in sync with the tiers in
  `SKILL.md`; the `deny` rules are the last line of defence.
- `scripts/backup-partitions.sh` produces files that contain unique identifiers:
  they must stay outside the repository (see `.gitignore`).
- `scripts/firmware-triage.sh` must never execute extracted content. If a new
  feature needs a tool that runs firmware content, it does not belong in this skill.
