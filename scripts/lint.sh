#!/usr/bin/env bash
# Repository self-check: syntax, frontmatter, internal links, JSON validity.
# Run it before every commit:  bash scripts/lint.sh
# Exit codes: 0 ok, 1 failures found.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
STRICT=0
[ "${1:-}" = "--strict" ] && STRICT=1

FAIL=0
WARN=0
ok()   { printf '  [ok]   %s\n' "$*"; }
bad()  { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL + 1)); }
warn() { printf '  [warn] %s\n' "$*"; WARN=$((WARN + 1)); }
have() { command -v "$1" >/dev/null 2>&1; }

cd "$ROOT" || exit 1

echo "== shell syntax"
while IFS= read -r f; do
  if bash -n "$f" 2>/tmp/lint-err; then ok "$f"; else bad "$f"; sed 's/^/         /' /tmp/lint-err; fi
done < <(find . -name '*.sh' -not -path './.git/*' | sort)

echo "== shellcheck"
if have shellcheck; then
  while IFS= read -r f; do
    if shellcheck -S warning -e SC1091 "$f" >/tmp/lint-sc 2>&1; then ok "$f"; else
      bad "$f"; sed 's/^/         /' /tmp/lint-sc
    fi
  done < <(find . -name '*.sh' -not -path './.git/*' | sort)
else
  warn "shellcheck not installed (brew/apt install shellcheck) - skipping"
fi

echo "== python syntax"
if have python3; then
  while IFS= read -r f; do
    if python3 -m py_compile "$f" 2>/tmp/lint-py; then ok "$f"; else bad "$f"; sed 's/^/         /' /tmp/lint-py; fi
    rm -rf "${f%/*}/__pycache__" 2>/dev/null
  done < <(find . -name '*.py' -not -path './.git/*' | sort)
else
  warn "python3 missing - skipping"
fi

echo "== json"
while IFS= read -r f; do
  if have jq; then
    if jq empty "$f" 2>/tmp/lint-json; then ok "$f"; else bad "$f"; sed 's/^/         /' /tmp/lint-json; fi
  elif have python3; then
    if python3 -c "import json,sys;json.load(open(sys.argv[1]))" "$f" 2>/tmp/lint-json; then ok "$f"; else bad "$f"; sed 's/^/         /' /tmp/lint-json; fi
  else
    warn "no jq/python3 - skipping $f"
  fi
done < <(find . -name '*.json' -not -path './.git/*' | sort)

echo "== SKILL.md frontmatter"
SKILL="SKILL.md"
if [ ! -f "$SKILL" ]; then
  bad "$SKILL missing"
else
  fm=$(awk 'NR==1 && $0=="---"{f=1;next} f && $0=="---"{exit} f{print}' "$SKILL")
  for key in name description license compatibility; do
    if printf '%s\n' "$fm" | grep -qE "^$key:"; then ok "frontmatter: $key"; else bad "frontmatter: $key missing"; fi
  done
  sname=$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p' | head -1)
  dirname=$(basename "$ROOT")
  if printf '%s' "$sname" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$'; then ok "name is kebab-case: $sname"; else bad "name is not kebab-case: $sname"; fi
  if [ "$sname" = "$dirname" ]; then ok "name matches directory ($dirname)"; else warn "name '$sname' != directory '$dirname'"; fi
  desc=$(printf '%s\n' "$fm" | sed -n 's/^description:[[:space:]]*//p' | head -1)
  if [ "${#desc}" -lt 60 ]; then bad "description too short (<60 chars)"; else ok "description length ${#desc}"; fi
  if printf '%s\n' "$desc" | grep -qiE 'adb|fastboot|android'; then ok "description mentions the trigger words"; else warn "description has no trigger words"; fi
fi

echo "== internal links"
if [ -f "$SKILL" ]; then
  for ref in $(grep -oE '(scripts|references|assets)/[A-Za-z0-9._/-]+' "$SKILL" | sort -u); do
    if [ -e "$ref" ]; then ok "referenced: $ref"; else bad "referenced but missing: $ref"; fi
  done
fi

echo "== executable bits"
for f in scripts/*.sh; do
  [ -e "$f" ] || continue
  if [ -x "$f" ]; then ok "executable: $f"; else bad "not executable: $f (chmod +x)"; fi
done

echo "== opencode permission assets"
for f in assets/opencode.permissions.example.json assets/opencode.permissions.v1.example.json; do
  [ -e "$f" ] || continue
  if have jq; then
    # V2: array of {action, resource, effect}. V1: {permission: {bash: {pattern: effect}}}.
    eff=$(jq -r 'if has("permissions") then (.permissions[]?.effect // empty)
                 else (.permission.bash // {} | to_entries[]?.value) end' "$f" | sort -u | tr '\n' ' ')
    if [ -z "$eff" ]; then
      bad "$f: no permission rules found"
    elif printf '%s' "$eff" | grep -qE '[^a-z ]'; then
      bad "$f: invalid effect values: $eff"
    else
      ok "$f effects: $eff"
    fi
  fi
done

echo ""
echo "lint: $FAIL failure(s), $WARN warning(s)"
[ "$FAIL" -eq 0 ] || exit 1
[ "$STRICT" -eq 1 ] && [ "$WARN" -gt 0 ] && exit 1
exit 0
