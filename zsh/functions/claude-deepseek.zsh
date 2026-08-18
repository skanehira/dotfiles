# Claude Code のバックエンドを DeepSeek に切り替える (現在のシェルのみ)
#
#   ccds      DeepSeek モードに切替 (1Password から API キーを取得)
#   ccds off  Anthropic に戻す
#
# alias と export はシェルプロセスローカルなので、他のシェルには影響しない。
ccds() {
  local settings="$GHQ_ROOT/github.com/skanehira/dotfiles/claude/settings.deepseek.json"

  if [[ "$1" == "off" ]]; then
    unset ANTHROPIC_AUTH_TOKEN
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
  echo "ccds: DeepSeek モード (このシェルのみ)。claude で起動、ccds off で解除"
}
