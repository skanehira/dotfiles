#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

die() {
  printf '%s: %s\n' "$SCRIPT_NAME" "$*" >&2
  exit 1
}

log() {
  printf '%s\n' "$*" >&2
}

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME --init PATH [options]

Captures a Neovim plugin UI in a NEW WezTerm window on macOS.
The window is captured as an app-window region, not the desktop.

Options:
  --init PATH       Lua init file for nvim -u (required)
  --out PATH        Output PNG (default: /tmp/nvim-ui-capture/<timestamp>.png)
  --nvim PATH       Neovim binary (default: nvim; use 0.10.4 for github.nvim)
  --cwd DIR         Working directory (default: current directory)
  --path DIR        Prepend DIR to PATH for nvim (repeatable; e.g. fake gh)
  --width N         Window width (default: screen width)
  --height N        Window height (default: screen height - y)
  --x N             Window x position (default: 0)
  --y N             Window y position (default: 30)
  --wait SECONDS    Wait after launch before capture (default: 2.5)
  --settle SECONDS  Wait after window creation before typing (default: 1.0)
  --crop WxH+X+Y    Crop the PNG after capture (sips; H is height)
  --dry-run         Print the command and geometry; do not open/capture
  --verbose         Print progress
  -h, --help        Show this help

Requires macOS, WezTerm, and Accessibility permission for System Events.
EOF
}

init=""
out=""
nvim="nvim"
cwd="$PWD"
width=""
height=""
# Default origin is below the macOS menu bar.
x=0
y=30
# Enough for the init's deferred UI open; increase for slow plugins.
wait_s=2.5
# Wait for the new window to appear before typing.
settle_s=1.0
crop=""
dry_run=0
verbose=0
path_dirs=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --init)
      init="${2:-}"
      shift 2
      ;;
    --out)
      out="${2:-}"
      shift 2
      ;;
    --nvim)
      nvim="${2:-}"
      shift 2
      ;;
    --cwd)
      cwd="${2:-}"
      shift 2
      ;;
    --path)
      path_dirs+=("${2:-}")
      shift 2
      ;;
    --width)
      width="${2:-}"
      shift 2
      ;;
    --height)
      height="${2:-}"
      shift 2
      ;;
    --x)
      x="${2:-}"
      shift 2
      ;;
    --y)
      y="${2:-}"
      shift 2
      ;;
    --wait)
      wait_s="${2:-}"
      shift 2
      ;;
    --settle)
      settle_s="${2:-}"
      shift 2
      ;;
    --crop)
      crop="${2:-}"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --verbose)
      verbose=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1 (see --help)"
      ;;
  esac
done

[[ -n "$init" ]] || die "--init is required"
[[ -f "$init" ]] || die "init file not found: $init"
[[ -d "$cwd" ]] || die "cwd not found: $cwd"
[[ "$(uname -s)" == "Darwin" ]] || die "macOS is required (uses osascript/screencapture)"
command -v osascript >/dev/null || die "osascript not found"
command -v screencapture >/dev/null || die "screencapture not found"
command -v pbcopy >/dev/null || die "pbcopy not found"
command -v pbpaste >/dev/null || die "pbpaste not found"
command -v wezterm >/dev/null || die "wezterm not found"

if [[ "$nvim" != /* ]]; then
  resolved="$(command -v "$nvim" || true)"
  [[ -n "$resolved" ]] || die "nvim not found: $nvim"
  nvim="$resolved"
fi
[[ -x "$nvim" ]] || die "nvim is not executable: $nvim"

init="$(cd "$(dirname "$init")" && pwd)/$(basename "$init")"
cwd="$(cd "$cwd" && pwd)"

if [[ -z "$out" ]]; then
  out="${TMPDIR:-/tmp}/nvim-ui-capture/$(date +%Y%m%d-%H%M%S).png"
fi
mkdir -p "$(dirname "$out")"
out="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")"

bounds="$(osascript -e 'tell application "Finder" to get bounds of window of desktop' 2>/dev/null || true)"
# Fallback screen bounds; Finder normally reports the real display size.
screen_w=1920
screen_h=1080
if [[ "$bounds" =~ ^[[:space:]]*([0-9]+),[[:space:]]*([0-9]+),[[:space:]]*([0-9]+),[[:space:]]*([0-9]+)[[:space:]]*$ ]]; then
  screen_w="${BASH_REMATCH[3]}"
  screen_h="${BASH_REMATCH[4]}"
fi
if [[ -z "$width" ]]; then
  width="$screen_w"
fi
if [[ -z "$height" ]]; then
  height="$((screen_h - y))"
fi
[[ "$width" -gt 0 && "$height" -gt 0 ]] || die "invalid window size: ${width}x${height}"

quote() {
  local value="$1"
  printf "'%s'" "${value//\'/\'\\\'\'}"
}

path_prefix=""
if [[ ${#path_dirs[@]} -gt 0 ]]; then
  for dir in "${path_dirs[@]}"; do
    [[ -d "$dir" ]] || die "path not found: $dir"
    dir="$(cd "$dir" && pwd)"
    if [[ -z "$path_prefix" ]]; then
      path_prefix="$dir"
    else
      path_prefix="$path_prefix:$dir"
    fi
  done
fi

cmd="cd $(quote "$cwd") && "
if [[ -n "$path_prefix" ]]; then
  cmd+="env PATH=$(quote "$path_prefix:$PATH") "
fi
cmd+="$(quote "$nvim") -u $(quote "$init")"

if [[ $verbose -eq 1 || $dry_run -eq 1 ]]; then
  log "command: $cmd"
  log "window: x=$x y=$y width=$width height=$height"
  log "output: $out"
fi
if [[ $dry_run -eq 1 ]]; then
  exit 0
fi

clip_tmp="$(mktemp "${TMPDIR:-/tmp}/nvim-ui-clip.XXXXXX")"
had_clip=0
if pbpaste >"$clip_tmp" 2>/dev/null; then
  had_clip=1
fi
restore_clip() {
  if [[ $had_clip -eq 1 ]]; then
    pbcopy <"$clip_tmp" 2>/dev/null || true
  fi
  rm -f "$clip_tmp"
}
trap restore_clip EXIT

if ! osascript -e 'application "WezTerm" is running' >/dev/null 2>&1; then
  log "starting WezTerm"
  open -a WezTerm
  sleep 2
fi

log "opening a new WezTerm window"
osascript <<APPLESCRIPT
tell application "System Events"
  if not (exists process "WezTerm") then error "WezTerm is not running"
  tell process "WezTerm"
    set frontmost to true
    perform action "AXRaise" of window 1
    try
      click menu item "New Window" of menu "Shell" of menu bar 1
    on error
      keystroke "n" using command down
    end try
  end tell
end tell
delay $settle_s
tell application "System Events"
  tell process "WezTerm"
    set frontmost to true
    perform action "AXRaise" of window 1
    set position of window 1 to {$x, $y}
    set size of window 1 to {$width, $height}
  end tell
end tell
APPLESCRIPT

printf '%s' "$cmd" | pbcopy
osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "WezTerm"
    set frontmost to true
  end tell
  keystroke "v" using command down
  delay 0.3
  key code 36
end tell
APPLESCRIPT

# Let the shell consume the pasted command before restoring the clipboard.
sleep 0.5
restore_clip
trap - EXIT

log "waiting ${wait_s}s for Neovim"
sleep "$wait_s"

log "capturing app window region"
screencapture -x -R"${x},${y},${width},${height}" "$out"
[[ -s "$out" ]] || die "screencapture produced no image: $out"

if [[ -n "$crop" ]]; then
  if [[ ! "$crop" =~ ^([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+)$ ]]; then
    die "--crop must be WxH+X+Y (e.g. 640x420+0+60)"
  fi
  cw="${BASH_REMATCH[1]}"
  ch="${BASH_REMATCH[2]}"
  cx="${BASH_REMATCH[3]}"
  cy="${BASH_REMATCH[4]}"
  sips -c "$ch" "$cw" --cropOffset "$cy" "$cx" "$out" >/dev/null
fi

dims="$(sips -g pixelWidth -g pixelHeight "$out" | awk '/pixelWidth|pixelHeight/ {print $2}' | paste -sd x -)"
printf 'captured: %s\n' "$out"
printf 'window: %s,%s %sx%s\n' "$x" "$y" "$width" "$height"
printf 'image: %s\n' "$dims"
printf 'note: the new WezTerm window is left open for inspection; close it when done.\n'
