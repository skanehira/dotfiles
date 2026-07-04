#!/usr/bin/env bash
# Claude Code hooks から呼ばれ、Claude が動いている tmux window に状態を反映する。
# usage: tmux-status.sh <start|working|waiting|idle|clear>
#   start:   セッション開始 (SessionStart) → 手空きで登録
#   working: 作業中 (UserPromptSubmit / PostToolUse)
#   waiting: 承認・入力待ち (Notification)
#   idle:    応答完了・手空き (Stop)
#   clear:   登録解除 (SessionEnd)
#
# 書き込む window オプション:
#   @claude_status: 状態アイコン (tmux.conf の window-status-format と claude-switch が参照)
#   @claude_pane:   Claude が動くペイン ID (claude-switch のプレビュー/ジャンプ先)
#     ※ Claude Code はプロセスタイトルを "2.1.199" のようなバージョン文字列に書き換えるため、
#       pane_current_command ではペインを特定できない。hook 経由の自己申告で解決する。
#
# tmux 外 (TMUX_PANE 無し = launchd の claude -p 実行など) では何もしない。
set -eu

[ -z "${TMUX_PANE:-}" ] && exit 0

case "${1:-}" in
  start | idle) icon="✅" ;;
  working)      icon="🤖" ;;
  waiting)      icon="🔔" ;;
  clear)        icon="" ;;
  *)            exit 0 ;;
esac

# ペイン破棄と hook 実行が競合しても失敗させない (非ゼロ終了は Claude 側にエラー表示されるため)
if [ -n "$icon" ]; then
  tmux set-option -w -t "$TMUX_PANE" @claude_status "$icon" 2>/dev/null || true
  tmux set-option -w -t "$TMUX_PANE" @claude_pane "$TMUX_PANE" 2>/dev/null || true
else
  tmux set-option -w -t "$TMUX_PANE" -u @claude_status 2>/dev/null || true
  tmux set-option -w -t "$TMUX_PANE" -u @claude_pane 2>/dev/null || true
fi
