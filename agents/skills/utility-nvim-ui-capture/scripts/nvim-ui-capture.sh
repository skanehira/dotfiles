#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

Captures a Neovim plugin UI in a browser terminal.
rtty runs the Neovim command; ghost starts rtty in the background and this
script stops it after the screenshot. The screenshot is the browser page
(the terminal), not the desktop.

Options:
  --init PATH       Lua init file for nvim -u (required)
  --out PATH        Output PNG (default: /tmp/nvim-ui-capture/<timestamp>.png)
  --nvim PATH       Neovim binary (default: nvim; use 0.10.4 for github.nvim)
  --cwd DIR         Working directory (default: current directory)
  --path DIR        Prepend DIR to PATH for rtty/nvim (repeatable; e.g. fake gh)
  --port N          rtty port (default: 9999; falls back to a free port)
  --width N         Browser viewport width (default: 1280)
  --height N        Browser viewport height (default: 800)
  --wait SECONDS    Wait after the terminal loads before capture (default: 2.5)
  --keys KEYS       Semicolon-separated Playwright keys (default: none).
                    Prefix literal text with "text:" (e.g. "text::w;Enter").
  --after-keys SECONDS
                    Wait after sending keys before capture (default: 0.5)
  --headless        Run Chromium headless (no visible browser window)
  --font NAME       Browser terminal font family (default: Cica)
                    Use a Nerd Font/Powerline-capable font; otherwise the
                    glyphs Neovim draws (e.g. label caps) render blank.
  --font-size N     Browser terminal font size (default: 15)
  --crop WxH+X+Y    Crop the PNG after capture (sips; H is height)
  --dry-run         Print the commands; do not start rtty or capture
  --verbose         Print progress
  -h, --help        Show this help

Requires macOS, ghost, rtty, node/npm, and Playwright Chromium.
Install rtty with: go install github.com/skanehira/rtty@latest
If Chromium is missing: npx playwright install chromium
EOF
}

init=""
out=""
nvim="nvim"
cwd="$PWD"
port="9999"
width="1280"
height="800"
wait_s="2.5"
keys=""
after_keys_s="0.5"
headless=0
font="Cica"
font_size="15"
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
    --port)
      port="${2:-}"
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
    --wait)
      wait_s="${2:-}"
      shift 2
      ;;
    --keys)
      keys="${2:-}"
      shift 2
      ;;
    --after-keys)
      after_keys_s="${2:-}"
      shift 2
      ;;
    --headless)
      headless=1
      shift
      ;;
    --font)
      font="${2:-}"
      shift 2
      ;;
    --font-size)
      font_size="${2:-}"
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
[[ "$(uname -s)" == "Darwin" ]] || die "macOS is required (uses sips for image checks)"
command -v ghost >/dev/null || die "ghost not found"
command -v node >/dev/null || die "node not found"
command -v npm >/dev/null || die "npm not found"
command -v curl >/dev/null || die "curl not found"
command -v sips >/dev/null || die "sips not found"

rtty_bin="${RTTY_BIN:-}"
if [[ -z "$rtty_bin" ]]; then
  rtty_bin="$(command -v rtty || true)"
  if [[ -z "$rtty_bin" && -x "$HOME/go/bin/rtty" ]]; then
    rtty_bin="$HOME/go/bin/rtty"
  fi
fi
[[ -n "$rtty_bin" ]] || die "rtty not found; go install github.com/skanehira/rtty@latest"

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

port_free() {
  if command -v lsof >/dev/null 2>&1; then
    ! lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
  else
    ! nc -z 127.0.0.1 "$1" >/dev/null 2>&1
  fi
}

if ! port_free "$port"; then
  found=""
  for candidate in $(seq 10000 10099); do
    if port_free "$candidate"; then
      found="$candidate"
      break
    fi
  done
  [[ -n "$found" ]] || die "no free port (tried $port and 10000-10099)"
  log "port $port is in use; using $found"
  port="$found"
fi

nvim_cmd="$nvim -u $init"
rtty_cmd="$rtty_bin run \"$nvim_cmd\" -p $port -a localhost"
if [[ -n "$font" ]]; then
  rtty_cmd+=" --font \"$font\""
fi
if [[ -n "$font_size" ]]; then
  rtty_cmd+=" --font-size \"$font_size\""
fi

ghost_args=(run -c "$cwd")
ghost_args+=(-e "TERM=xterm-256color")
ghost_args+=(-e "COLORTERM=truecolor")
if [[ -n "$path_prefix" ]]; then
  ghost_args+=(-e "PATH=$path_prefix:$PATH")
fi
ghost_args+=("$rtty_cmd")

playwright_home="${XDG_CACHE_HOME:-$HOME/.cache}/nvim-ui-capture/playwright"
node_args=(
  --url "http://localhost:$port"
  --out "$out"
  --width "$width"
  --height "$height"
  --wait "$wait_s"
  --after-keys "$after_keys_s"
  --keys "$keys"
)
if [[ $headless -eq 1 ]]; then
  node_args+=(--headless)
fi

if [[ $verbose -eq 1 || $dry_run -eq 1 ]]; then
  log "rtty command: $rtty_cmd"
  log "ghost command: ghost ${ghost_args[*]}"
  log "playwright command: NODE_PATH=$playwright_home/node_modules node $SCRIPT_DIR/browser-capture.cjs ${node_args[*]}"
  log "output: $out"
fi
if [[ $dry_run -eq 1 ]]; then
  exit 0
fi

task_id=""
cleanup() {
  if [[ -n "${task_id:-}" ]]; then
    ghost stop "$task_id" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

log "starting rtty via ghost"
start_output="$(ghost "${ghost_args[@]}" 2>&1)" || die "ghost run failed: $start_output"
task_id="$(printf '%s\n' "$start_output" | sed -n 's/^[[:space:]]*Task ID:[[:space:]]*//p' | head -1)"
[[ -n "$task_id" ]] || die "could not parse the ghost task id: $start_output"
log "rtty task: $task_id"

ready=0
for _ in $(seq 1 50); do
  if curl -sf "http://localhost:$port/" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.2
done
if [[ $ready -eq 0 ]]; then
  ghost log "$task_id" 2>/dev/null | tail -20 || true
  die "rtty did not start on http://localhost:$port"
fi
log "rtty is ready: http://localhost:$port"

if [[ ! -f "$playwright_home/node_modules/playwright/package.json" ]]; then
  log "installing Playwright into $playwright_home (one-time)"
  mkdir -p "$playwright_home"
  (
    cd "$playwright_home"
    npm init -y >/dev/null 2>&1
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install --no-audit --no-fund playwright@1.65.1 >/dev/null
  ) || die "failed to install Playwright; run npx playwright install chromium"
fi

log "capturing with Chromium"
NODE_PATH="$playwright_home/node_modules" node "$SCRIPT_DIR/browser-capture.cjs" "${node_args[@]}"
[[ -s "$out" ]] || die "Playwright produced no image: $out"

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
printf 'browser: http://localhost:%s\n' "$port"
printf 'viewport: %sx%s\n' "$width" "$height"
printf 'image: %s\n' "$dims"
printf 'rtty: %s (stopped)\n' "$task_id"
