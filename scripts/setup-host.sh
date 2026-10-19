#!/usr/bin/env bash
# Prepare the host for Android device analysis, Linux porting and flashing.
#
# This script installs tooling on the HOST computer. It never touches a phone.
# It never removes, downgrades or upgrades packages that are already installed.
#
# Usage:
#   setup-host.sh --check              report what is missing (read-only)
#   setup-host.sh --minimal            install only adb + fastboot
#   setup-host.sh --full               install the full analysis/porting toolchain
#   setup-host.sh --full --prefix DIR  install user-space binaries into DIR/bin
#   setup-host.sh --full --dry-run     print the plan and exit
#
# Options:
#   --prefix DIR   where to put downloaded binaries (default: ~/.local)
#   --yes          do not ask for confirmation
#   --dry-run      never install anything, only print the plan
#
# Exit codes: 0 ok, 1 error, 2 nothing to do, 3 missing required tool.
set -uo pipefail

PROFILE="check"
PREFIX="${HOME}/.local"
ASSUME_YES=0
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --check)    PROFILE="check" ;;
    --minimal)  PROFILE="minimal" ;;
    --full)     PROFILE="full" ;;
    --prefix)   shift; PREFIX="${1:-}" ;;
    --prefix=*) PREFIX="${arg#--prefix=}" ;;
    --yes|-y)   ASSUME_YES=1 ;;
    --dry-run)  DRY_RUN=1 ;;
    -h|--help)  sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

[ -n "$PREFIX" ] || { echo "--prefix needs a directory" >&2; exit 1; }
BIN="$PREFIX/bin"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/android-device-lab"
LOG="$LOG_DIR/setup-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$LOG_DIR"

say()  { printf '%s\n' "$*"; }
step() { printf '==> %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------- tool table
# name | why we need it | tier
TOOLS=(
  "adb|device shell, props, pull: Tier 0/1"
  "fastboot|bootloader protocol, flashing, getvar: Tier 0-2"
  "dtc|device tree compiler, read model/compatible: analysis"
  "lz4|decompress Samsung/MTK firmware members: analysis"
  "unzip|open vendor zip packages: analysis"
  "7z|open .7z / read EROFS & ext4 images: analysis"
  "strings|find kernel version strings in images: analysis"
  "file|identify image types in the manifest: analysis"
  "python3|run the bundled parsers: required"
  "git|fetch kernels, DTS and postmarketOS recipes: porting"
  "curl|download vendor kernels and tools: porting"
  "e2fsck|read ext4 images read-only: analysis"
  "fsck.erofs|read EROFS images read-only: analysis"
  "simg2img|convert sparse images to raw: analysis"
  "lpunpack|split super.img dynamic partitions: analysis"
  "avbtool|inspect vbmeta, rollback index, signing: analysis"
  "payload-dumper-go|extract partitions from OTA payload.bin: analysis"
  "unpack_bootimg|AOSP boot image unpacker: analysis"
  "pmbootstrap|build and flash postmarketOS: porting"
  "mtkclient|MediaTek BROM/DA mode: recovery (expert)"
)

# ------------------------------------------------------------------- helpers
SUDO=""
ask_sudo() {
  have sudo || die "sudo not found; install packages manually or use --prefix for user-space tools"
  if [ "$ASSUME_YES" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
    say "This needs root privileges to install system packages."
    read -r -p "Continue with sudo? [y/N] " reply
    case "$reply" in
      [yY]*) ;;
      *) die "Aborted by user" ;;
    esac
  fi
  SUDO="sudo"
}

pkg_install() {
  # pkg_install <apt|dnf|pacman|apk|brew> <pkg>...
  local mgr="$1"; shift
  local pkgs=("$@")
  [ ${#pkgs[@]} -eq 0 ] && return 0
  case "$mgr" in
    apt)
      local missing=()
      for p in "${pkgs[@]}"; do
        dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
      done
      [ ${#missing[@]} -eq 0 ] && return 0
      step "apt install: ${missing[*]}"
      ask_sudo
      $SUDO apt-get update -qq >/dev/null 2>&1 || warn "apt-get update failed, continuing"
      $SUDO apt-get install -y --no-install-recommends "${missing[@]}" 2>&1 | tee -a "$LOG" | tail -5
      ;;
    dnf) step "dnf install: ${pkgs[*]}"; ask_sudo; $SUDO dnf install -y "${pkgs[@]}" 2>&1 | tee -a "$LOG" | tail -5 ;;
    pacman) step "pacman -S: ${pkgs[*]}"; ask_sudo; $SUDO pacman -S --needed --noconfirm "${pkgs[@]}" 2>&1 | tee -a "$LOG" | tail -5 ;;
    apk) step "apk add: ${pkgs[*]}"; ask_sudo; $SUDO apk add "${pkgs[@]}" 2>&1 | tee -a "$LOG" | tail -5 ;;
    brew) step "brew install: ${pkgs[*]}"; brew install "${pkgs[@]}" 2>&1 | tee -a "$LOG" | tail -5 ;;
  esac
}

pipx_install() {
  # Python tools go to pipx when available, otherwise a private venv.
  local pkg="$1"
  if have pipx; then
    step "pipx install $pkg"
    pipx install "$pkg" 2>&1 | tee -a "$LOG" | tail -3
  else
    local venv="$HOME/.local/share/android-device-lab/venv"
    if [ ! -d "$venv" ]; then
      step "creating private venv at $venv"
      python3 -m venv "$venv" 2>&1 | tee -a "$LOG"
    fi
    step "pip install $pkg (private venv)"
    "$venv/bin/pip" install --quiet --upgrade pip 2>&1 | tee -a "$LOG" | tail -2
    "$venv/bin/pip" install --quiet "$pkg" 2>&1 | tee -a "$LOG" | tail -3
  fi
}

github_asset() {
  # github_asset <owner/repo> <asset-regex>  -> local path
  # Uses the GitHub releases API so version numbers never rot in this file.
  local repo="$1" pattern="$2" url api
  have curl || { warn "curl missing, cannot download $repo"; return 1; }
  have jq || { warn "jq missing, cannot query GitHub releases"; return 1; }
  api="https://api.github.com/repos/$repo/releases/latest"
  url=$(curl -fsSL "$api" 2>/dev/null | jq -r --arg p "$pattern" \
        '.assets[] | select(.name | test($p)) | .browser_download_url' 2>/dev/null | head -1)
  [ -n "$url" ] && [ "$url" != "null" ] || { warn "no asset matching /$pattern/ in $repo"; return 1; }
  local out
  out="$BIN/$(basename "$url")"
  mkdir -p "$BIN"
  step "download $(basename "$url")"
  curl -fL --retry 2 -o "$out" "$url" 2>&1 | tee -a "$LOG" | tail -2 || return 1
  chmod +x "$out"
  say "  sha256: $(sha256sum "$out" | cut -d' ' -f1)"
  say "  (verify against the release page before trusting it)"
  printf '%s\n' "$out"
}

# ------------------------------------------------------------------ reporting
report_tools() {
  say ""
  say "Tool status"
  say "-----------"
  local missing_count=0
  local entry name why
  for entry in "${TOOLS[@]}"; do
    name="${entry%%|*}"; why="${entry#*|}"
    if have "$name"; then
      printf '  [ok]      %-18s %s\n' "$name" "$why"
    else
      printf '  [missing] %-18s %s\n' "$name" "$why"
      missing_count=$((missing_count + 1))
    fi
  done
  say ""
  say "$missing_count tool(s) missing."
}

# --------------------------------------------------------------------- checks
check_profile() {
  say "Host: $(uname -srm)"
  if [ -r /etc/os-release ]; then . /etc/os-release; say "OS:   ${PRETTY_NAME:-unknown}"; fi
  say ""
  report_tools
  return 0
}

# ------------------------------------------------------------------ installer
install_linux() {
  if have apt-get; then
    pkg_install apt android-tools-adb android-tools-fastboot || true
    pkg_install apt adb fastboot dtc lz4 unzip p7zip-full file git curl python3 python3-venv python3-pip \
          e2fsprogs jq xz-utils bzip2
    pkg_install apt erofs-utils || true
    pkg_install apt android-sdk-libsparse-utils || true
    pkg_install apt android-sdk-ext4-utils || true
  elif have dnf; then
    pkg_install dnf android-tools dtc lz4 p7zip unzip file git curl python3 python3-pip e2fsprogs jq xz
    pkg_install dnf erofs-utils || true
    pkg_install dnf android-sdk-libsparse-utils || true
  elif have pacman; then
    mgr="pacman"
    pkg_install pacman android-tools dtc lz4 p7zip unzip file git curl python python-pip e2fsprogs jq xz
    pkg_install pacman erofs-utils || true
  elif have apk; then
    mgr="apk"
    pkg_install apk dtc lz4 p7zip unzip file git curl python3 py3-pip e2fsprogs jq xz
  else
    die "Unsupported package manager. Install the tools listed by --check manually."
  fi
}

install_macos() {
  have brew || die "Homebrew not found: https://brew.sh"
  pkg_install brew dtc lz4 p7zip jq
  step "brew install --cask android-platform-tools"
  brew install --cask android-platform-tools 2>&1 | tee -a "$LOG" | tail -3
}

install_extras() {
  # User-space binaries that are not reliably packaged everywhere.
  mkdir -p "$BIN"
  case "$(uname -m)" in
    x86_64|amd64) ASSET_ARCH="amd64" ;;
    aarch64|arm64) ASSET_ARCH="arm64" ;;
    *) ASSET_ARCH="" ;;
  esac

  if ! have payload-dumper-go && [ -n "$ASSET_ARCH" ]; then
    github_asset "ssut/payload-dumper-go" "payload-dumper-go_linux_${ASSET_ARCH}$" >/dev/null || true
  fi
  if ! have lpunpack; then
    github_asset "AndroidDumps/Ext4Extractor" "lpunpack" >/dev/null || true
  fi
  if ! have simg2img && [ -n "$ASSET_ARCH" ]; then
    github_asset "anestisb/android-image-tools" "simg2img.*${ASSET_ARCH}" >/dev/null || true
  fi
  if ! have unpack_bootimg; then
    github_asset "osm0sis/bootimg" "unpack_bootimg" >/dev/null || true
  fi

  # Python tooling: avbtool (vbmeta inspection), mtkclient (MediaTek recovery),
  # pmbootstrap (postmarketOS build+flash).
  pipx_install "avbtool @ git+https://github.com/google/avb" || true
  pipx_install "mtkclient" || true
  pipx_install "pmbootstrap" || true
  pipx_install "payload-dumper" || true
}

install_minimal() {
  if have apt-get; then
    pkg_install apt adb fastboot
  elif have dnf; then
    pkg_install dnf android-tools
  elif have pacman; then
    pkg_install pacman android-tools
  elif have brew; then
    pkg_install brew dtc
    step "brew install --cask android-platform-tools"
    brew install --cask android-platform-tools 2>&1 | tee -a "$LOG" | tail -3
  else
    die "Unsupported platform: install adb and fastboot manually (see --check)"
  fi
}

case "$PROFILE" in
  check)
    check_profile
    ;;
  minimal)
    if [ "$DRY_RUN" -eq 1 ]; then
      say "DRY RUN: would install adb + fastboot only."
    else
      install_minimal
    fi
    check_profile
    ;;
  full)
    if [ "$DRY_RUN" -eq 1 ]; then
      say "DRY RUN: would install the full toolchain into $PREFIX (binaries) and via the system package manager."
    else
      if [ "$(uname -s)" = "Darwin" ]; then install_macos; else install_linux; fi
      install_extras
    fi
    say ""
    say "Next steps:"
    say "  adb devices            # confirm the phone is seen"
    say "  fastboot devices       # confirm bootloader mode"
    say "  bash scripts/device-info.sh ./recon-<codename>"
    report_tools
    ;;
esac

exit 0
