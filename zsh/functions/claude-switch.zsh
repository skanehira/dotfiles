# Claude Code が動いている tmux window を全セッションから列挙し、
# fzf (プレビュー = Claude 画面) で選んでジャンプする。tmux.conf の prefix+f から popup で起動。
#
# 一覧は claude/hooks/tmux-status.sh が設定する window オプションを参照する:
#   @claude_status: 状態アイコン (🔔 承認・入力待ち / 🤖 作業中 / ✅ 手空き)
#   @claude_pane:   Claude が動くペイン ID
# 並び順: 🔔 → 🤖 → ✅ (次に触るべき window が先頭に来る)
function claude-switch() {
  local sep=$'\t'

  # フィールド: icon, pane_id, session:window, dir (window 名は全て nvim なので dir で識別)
  local list
  list=$(tmux list-windows -a -F "#{@claude_status}${sep}#{@claude_pane}${sep}#{session_name}:#{window_index}${sep}#{b:pane_current_path}" |
    awk -F '\t' '$1 != "" && $2 != "" {
      prio = ($1 == "🔔") ? 0 : ($1 == "🤖") ? 1 : 2
      printf "%d\t%s\n", prio, $0
    }' |
    sort -t "$sep" -k1,1n |
    cut -f2-)

  if [[ -z "$list" ]]; then
    echo "Claude が動いている window はありません"
    return 1
  fi

  local selected
  selected=$(print -r -- "$list" |
    fzf --ansi \
      --delimiter "$sep" \
      --with-nth 1,4,3 \
      --preview 'tmux capture-pane -ep -t {2}' \
      --preview-window 'right:60%' \
      --bind 'ctrl-d:preview-half-page-down,ctrl-u:preview-half-page-up' \
      --header '🔔 要対応 / 🤖 作業中 / ✅ 手空き')

  [[ -z "$selected" ]] && return 0

  local pane target
  pane=$(print -r -- "$selected" | cut -f2)
  target=$(print -r -- "$selected" | cut -f3)
  tmux switch-client -t "$target"

  # フォーカスは Claude ペインではなく同 window の Neovim ペインへ
  # (プロンプト入力は Neovim の float から行うフローのため)。
  # Neovim が居ない window (Claude 単独起動など) は Claude ペインにフォールバック
  local nvim_pane
  nvim_pane=$(tmux list-panes -t "$target" -F "#{pane_current_command}${sep}#{pane_id}" |
    awk -F '\t' '$1 == "nvim" { print $2; exit }')
  tmux select-pane -t "${nvim_pane:-$pane}"
}
