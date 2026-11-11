#!/usr/bin/env bash
# usage: agent-loop-install.sh [--uninstall]
#
# agent-loop を launchd のユーザー用エージェント (Label: local.agent-loop) として、このマシンにだけ入れる。
# nix で配らないのは、agent-loop を動かすマシンを 1 台に限るため (nix-darwin の設定はすべての mac に入る)。
# 何度実行しても同じ結果になる。plist を書き直して読み込み直す。
set -euo pipefail

label=local.agent-loop
plist="$HOME/Library/LaunchAgents/$label.plist"
script="$(cd "$(dirname "$0")" && pwd)/agent-loop.ts"
domain="gui/$(id -u)"

launchctl bootout "$domain/$label" 2>/dev/null || true
if [ "${1:-}" = "--uninstall" ]; then
  rm -f "$plist"
  echo "uninstalled $label"
  exit 0
fi

mkdir -p "$HOME/Library/LaunchAgents"
# launchd の既定の PATH には gh / claude / deno / terminal-notifier が無いので、明示する
cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>$HOME/.deno/bin/deno</string>
    <string>run</string>
    <string>--allow-env</string>
    <string>--allow-run</string>
    <string>--allow-read</string>
    <string>--allow-write</string>
    <string>$script</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key>
    <string>$HOME</string>
    <key>PATH</key>
    <string>$HOME/.local/bin:$HOME/.deno/bin:/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>StartInterval</key>
  <integer>3600</integer>
  <key>RunAtLoad</key>
  <true/>
  <key>ProcessType</key>
  <string>Background</string>
  <key>StandardOutPath</key>
  <string>$HOME/Library/Logs/agent-loop.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/Library/Logs/agent-loop.log</string>
</dict>
</plist>
EOF
plutil -lint "$plist" >/dev/null
launchctl bootstrap "$domain" "$plist"
echo "installed $label ($plist)"
