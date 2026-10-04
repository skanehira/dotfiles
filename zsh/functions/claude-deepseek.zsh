# Claude Code のバックエンドを DeepSeek に切り替えて起動する (現在のシェルのみ)
#
#   ccds      DeepSeek モードに切替えて claude を起動 (1Password から API キーを取得)
#   ccds off  Anthropic に戻す
#
# alias と export はシェルプロセスローカルなので、他のシェルには影響しない。
ccds() {
  local settings="$GHQ_ROOT/github.com/skanehira/dotfiles/agents/bindings/claude/settings.deepseek.json"

  if [[ "$1" == "off" ]]; then
    unset ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL
    unalias claude 2>/dev/null
    echo "ccds: Anthropic に戻しました"
    return 0
  fi

  if [[ ! -f "$settings" ]]; then
    echo "ccds: 設定ファイルが見つかりません: $settings" >&2
    return 1
  fi

  if [[ -z "$ANTHROPIC_AUTH_TOKEN" ]]; then
    local token
    token="$(op read 'op://Personal/DeepSeek API Key/credential')" || {
      echo "ccds: 1Password から API キーを取得できませんでした" >&2
      return 1
    }
    export ANTHROPIC_AUTH_TOKEN="$token"
  fi

  alias claude="claude --settings $settings"
  echo "ccds: DeepSeek モード (このシェルのみ)。ccds off で解除"

  # 接続先を整えたらそのまま起動する。alias は同じシェルで打ち直す用に残す
  command claude --settings "$settings" "$@"
}
