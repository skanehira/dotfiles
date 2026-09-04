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

# Claude Code のバックエンドを DGX Spark 上のローカル vLLM に切り替える (現在のシェルのみ)
#
#   ccsp      Spark モードに切替 (1Password から vLLM の API キーを取得)
#   ccsp off  Anthropic に戻す
#
# vLLM の認証は Authorization: Bearer のみを受け付けるため、x-api-key で送られる
# ANTHROPIC_API_KEY ではなく ANTHROPIC_AUTH_TOKEN を使う。
ccsp() {
  local settings="$GHQ_ROOT/github.com/skanehira/dotfiles/claude/settings.deepseek-spark.json"

  if [[ "$1" == "off" ]]; then
    unset ANTHROPIC_AUTH_TOKEN
    unalias claude 2>/dev/null
    echo "ccsp: Anthropic に戻しました"
    return 0
  fi

  if [[ ! -f "$settings" ]]; then
    echo "ccsp: 設定ファイルが見つかりません: $settings" >&2
    return 1
  fi

  if [[ -z "$ANTHROPIC_AUTH_TOKEN" ]]; then
    local token
    token="$(op read 'op://Personal/DGX Spark vLLM API Key/credential')" || {
      echo "ccsp: 1Password から API キーを取得できませんでした" >&2
      return 1
    }
    export ANTHROPIC_AUTH_TOKEN="$token"
  fi

  alias claude="claude --settings $settings"
  echo "ccsp: Spark モード (このシェルのみ)。claude で起動、ccsp off で解除"
}
