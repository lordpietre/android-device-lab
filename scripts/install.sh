#!/usr/bin/env bash
# Install (or update) the android-device-lab skill into opencode.
#
#   curl -fsSL https://raw.githubusercontent.com/lordpietre/android-device-lab/main/scripts/install.sh | bash
#
# Options:
#   --global           install into ~/.config/opencode (default)
#   --project          install into ./.opencode of the current directory
#   --no-permissions   do not touch opencode.json
#   --uninstall        remove the skill and the permission rules
#   --yes              do not ask for confirmation
#
# The installer only writes inside the opencode configuration directory (or the
# project directory) and always takes a backup before modifying a config file.
set -uo pipefail

REPO_URL="https://github.com/lordpietre/android-device-lab.git"
SKILL_ID="android-device-lab"
BRANCH="main"

SCOPE="global"
DO_PERMS=1
UNINSTALL=0
ASSUME_YES=0

for arg in "$@"; do
  case "$arg" in
    --global) SCOPE="global" ;;
    --project) SCOPE="project" ;;
    --no-permissions) DO_PERMS=0 ;;
    --uninstall) UNINSTALL=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

say()  { printf '%s\n' "$*"; }
step() { printf '==> %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$1" >&2; exit "${2:-1}"; }

if [ "$SCOPE" = "project" ]; then
  ROOT="${PWD}/.opencode"
else
  ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
fi
SKILL_DIR="$ROOT/skills/$SKILL_ID"
CONFIG="$ROOT/opencode.json"

# The source of the skill: the checkout this script lives in, or a fresh clone.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE=""
if [ -f "$HERE/../SKILL.md" ] && grep -q "^name: $SKILL_ID" "$HERE/../SKILL.md" 2>/dev/null; then
  SOURCE="$(cd "$HERE/.." && pwd)"
fi

confirm() {
  [ "$ASSUME_YES" -eq 1 ] && return 0
  read -r -p "$1 [y/N] " reply
  case "$reply" in [yY]*) return 0 ;; *) return 1 ;; esac
}

# ------------------------------------------------------------------ uninstall
if [ "$UNINSTALL" -eq 1 ]; then
  if [ -f "$CONFIG" ] && command -v python3 >/dev/null 2>&1; then
    RULES_SRC="$SKILL_DIR/assets/opencode.permissions.example.json"
    cp "$CONFIG" "$CONFIG.bak"
    step "removing the permission rules from $CONFIG (backup: $CONFIG.bak)"
    python3 - "$CONFIG" "$RULES_SRC" "$SKILL_ID" <<'PY'
import json, os, sys
config_path, rules_path, skill = sys.argv[1], sys.argv[2], sys.argv[3]

try:
    with open(config_path) as fh:
        data = json.load(fh)
except Exception as exc:
    print("WARN: could not parse %s: %s" % (config_path, exc))
    sys.exit(0)

incoming = []
if os.path.exists(rules_path):
    try:
        with open(rules_path) as fh:
            incoming = json.load(fh).get("permissions", [])
    except Exception:
        incoming = []

incoming_keys = {json.dumps(r, sort_keys=True) for r in incoming}
rules = data.get("permissions")
removed = 0
if isinstance(rules, list):
    kept = []
    for rule in rules:
        key = json.dumps(rule, sort_keys=True)
        if key in incoming_keys or (isinstance(rule, dict) and rule.get("resource") == skill):
            removed += 1
            continue
        kept.append(rule)
    data["permissions"] = kept
    with open(config_path, "w") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
print("  %d rule(s) removed, %d left" % (removed, len(kept)))
PY
  fi
  if [ -d "$SKILL_DIR" ]; then
    rm -rf "$SKILL_DIR"
    step "removed $SKILL_DIR"
  else
    say "Skill not installed at $SKILL_DIR"
  fi
  say "Uninstalled."
  exit 0
fi

# --------------------------------------------------------------------- install
step "Installing the '$SKILL_ID' skill into $ROOT"

if [ -d "$SKILL_DIR/.git" ]; then
  if command -v git >/dev/null 2>&1; then
    step "updating the existing checkout"
    git -C "$SKILL_DIR" pull --ff-only >/dev/null 2>&1 \
      && say "  updated to $(git -C "$SKILL_DIR" rev-parse --short HEAD)" \
      || warn "  git pull failed; keeping the current version"
  fi
else
  if [ -n "$SOURCE" ]; then
    step "copying the local checkout ($SOURCE)"
    mkdir -p "$ROOT/skills"
    rm -rf "$SKILL_DIR"
    cp -a "$SOURCE" "$SKILL_DIR"
  else
    command -v git >/dev/null 2>&1 || die "git is required to install the skill" 1
    step "cloning $REPO_URL"
    mkdir -p "$ROOT/skills"
    rm -rf "$SKILL_DIR"
    git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$SKILL_DIR" >/dev/null \
      || die "clone failed" 1
  fi
  say "  installed at $SKILL_DIR"
fi

# ----------------------------------------------------------------- permissions
if [ "$DO_PERMS" -eq 1 ]; then
  RULES_SRC="$SKILL_DIR/assets/opencode.permissions.example.json"
  if [ -f "$RULES_SRC" ] && command -v python3 >/dev/null 2>&1; then
    if [ -f "$CONFIG" ]; then
      cp "$CONFIG" "$CONFIG.bak"
      step "merging the permission rules into $CONFIG (backup: $CONFIG.bak)"
    else
      step "creating $CONFIG"
    fi
    python3 - "$CONFIG" "$RULES_SRC" "$SKILL_ID" <<'PY'
import json, os, sys
config_path, rules_path, skill = sys.argv[1], sys.argv[2], sys.argv[3]

with open(rules_path) as fh:
    incoming = json.load(fh)["permissions"]

data = {}
if os.path.exists(config_path):
    try:
        with open(config_path) as fh:
            data = json.load(fh)
    except Exception:
        print("WARN: %s is not plain JSON (comments?), leaving it untouched." % config_path)
        print("      Add the rules manually from %s" % rules_path)
        sys.exit(0)

data.setdefault("$schema", "https://opencode.ai/config.json")
existing = data.get("permissions")
if not isinstance(existing, list):
    existing = []
seen = {json.dumps(r, sort_keys=True) for r in existing}
added = 0
for rule in incoming:
    key = json.dumps(rule, sort_keys=True)
    if key not in seen:
        existing.append(rule)
        seen.add(key)
        added += 1
data["permissions"] = existing

with open(config_path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
print("  %d rule(s) added, %d already present" % (added, len(incoming) - added))
PY
  else
    warn "rules file not found ($RULES_SRC); skipping the permission merge"
    warn "copy assets/opencode.permissions.example.json into $CONFIG manually"
  fi
fi

cat <<'EOF'

Done. Next steps:

  1. Restart opencode (or start a new session) so it picks the skill up.
  2. Check that it is listed:
       opencode
       /skill android-device-lab
  3. Prepare the host tools (installs adb, fastboot and the analysis toolchain):
       bash ~/.config/opencode/skills/android-device-lab/scripts/setup-host.sh --check
       bash ~/.config/opencode/skills/android-device-lab/scripts/setup-host.sh --full

The skill id is the directory name, so the folder must stay called
"android-device-lab". To update it later, re-run this installer.
EOF
exit 0
