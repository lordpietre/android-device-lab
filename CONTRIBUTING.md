# Contributing

Thanks for helping. This skill exists to keep other people's phones alive, so the
contribution bar is mostly about **not making the skill less safe**.

## Ground rules

1. **Never weaken a safety rule to make a task easier.** If a workflow needs a new
   dangerous command, it needs a new gate, a new tier and a new recovery path note.
2. **A pull request that removes a `deny` rule, raises the tier of a command, or
   allows a write without a backup gate will be rejected** unless the commit message
   explains what makes it safe.
3. **Keep the scripts read-only by default.** Any new script that writes to a device
   needs: an explicit `--yes`-style gate, a dry-run plan, a manifest, and a line in
   `SKILL.md` describing its tier.
4. **No device-unique data in the repository.** No logs with serials, IMEIs, MAC
   addresses, partition dumps or firmware images. The scripts redact; keep it that way.
5. **No binaries from vendor firmware.** The skill analyses firmware, it never
   republishes it.

## Development

```bash
make lint     # shellcheck + python syntax + JSON + frontmatter + links
make test     # offline smoke tests, no device required
make package  # build the distributable zip
```

Requirements: `bash`, `python3`, `shellcheck` (optional but recommended), `jq` or
`python3` for JSON checks.

## Style

- Bash: `set -uo pipefail`, `shopt -s nullglob` where globbing is used, POSIX-ish
  quoting, `shellcheck` clean, no `sudo` without an explicit user prompt.
- Python: standard library only, no third-party imports, functions small and typed
  with docstrings.
- Markdown: one sentence per idea, tables for anything with more than three fields.
- English for commands, identifiers and file names. Prose in the language of the
  reader.

## Adding a reference

- New topic -> new file in `references/`, linked from `SKILL.md` ("Bundled resources")
  and from `references/ecosystem.md` if it points upstream.
- Keep references short and actionable: commands the agent can run, tables of
  symptoms and causes, links with the date they were last verified.

## Adding a tool

1. Add it to the tool table in `scripts/setup-host.sh` and to `references/tooling.md`.
2. Add an install path for Debian/Ubuntu, Fedora, Arch, macOS and a user-space
   fallback (`--prefix`), or state clearly that it must be built from source.
3. Never make a tool mandatory for the read-only workflow.

## Commit and PR

- One logical change per commit, imperative subject line.
- Update `CHANGELOG.md` under `[Unreleased]`.
- Describe in the PR body which device/vendor/SoC you tested on, or state that you
  could not test it on hardware.

## Reporting a bug in the skill

Open an issue with: the command you ran, the output (with identifiers redacted), the
host OS, and the versions of `adb`/`fastboot`. If the bug could brick a device, say
so in the title.
