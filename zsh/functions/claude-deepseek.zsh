# Claude Code のバックエンドを DeepSeek に切り替える (現在のシェルのみ)
#
#   ccds      DeepSeek モードに切替 (1Password から API キーを取得)
#   ccds off  Anthropic に戻す
#
# alias と export はシェルプロセスローカルなので、他のシェルには影響しない。
ccds() {
  local settings="$GHQ_ROOT/github.com/skanehira/dotfiles/claude/settings.deepseek.json"

  if [[ "$1" == "off" ]]; then
    # ccsp が ANTHROPIC_BASE_URL を export するので、ここでも消さないと Spark を向いたまま残る
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
  echo "ccds: DeepSeek モード (このシェルのみ)。claude で起動、ccds off で解除"
}

# Claude Code のバックエンドを DGX Spark 上のローカル vLLM に切り替える (現在のシェルのみ)
#
#   ccsp      自動判定 (LAN に届けば LAN、届かなければ Tailscale)
#   ccsp lan  自宅 LAN 直結を強制 (プローブしない)
#   ccsp ts   Tailscale 経由を強制 (プローブしない)
#   ccsp off  Anthropic に戻す
#
# 接続先 (ANTHROPIC_BASE_URL) は settings JSON に置かず、ここで export する。
# settings JSON の env はシェルの export を無条件に上書きするため、JSON に書くと
# 出先での切り替えができなくなる。
#
# vLLM の認証は Authorization: Bearer のみを受け付けるため、x-api-key で送られる
# ANTHROPIC_API_KEY ではなく ANTHROPIC_AUTH_TOKEN を使う。
#
# 注意:
# - export は子プロセスに継承されるが alias は継承されない。ccsp の後にサブシェルや
#   スクリプトから「素の claude」を打つと --settings が効かず、本体 settings.json の
#   モデル名を vLLM に送って model not found になる。claude は必ずこのシェルで起動する
# - 別のバックエンドに切り替えるときは先に off を打つ。ANTHROPIC_AUTH_TOKEN が
#   残っていると使い回され、相手先で 401 になる
ccsp() {
  local settings="$GHQ_ROOT/github.com/skanehira/dotfiles/claude/settings.deepseek-spark.json"
  local lan_url="http://spark-head.local:8888"
  local ts_url="http://spark-head:8888"
  local base_url url token

  case "$1" in
    off)
      unset ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL
      unalias claude 2>/dev/null
      echo "ccsp: Anthropic に戻しました"
      return 0
      ;;
    lan) base_url="$lan_url" ;;
    ts) base_url="$ts_url" ;;
    '')
      # 到達した方を選ぶ。/health は無認証なので API キー無しで叩ける。
      # --connect-timeout は名前解決にも効く (curl は AsynchDNS 付き) ため、
      # mDNS がハングしてもここで打ち切られる。
      for url in "$lan_url" "$ts_url"; do
        if curl -fs -o /dev/null --connect-timeout 3 --max-time 5 "$url/health"; then
          base_url="$url"
          break
        fi
      done
      if [[ -z "$base_url" ]]; then
        echo "ccsp: LAN にも Tailscale にも届きません (ccsp lan / ccsp ts で強制できます)" >&2
        return 1
      fi
      ;;
    *)
      echo "usage: ccsp [lan|ts|off]" >&2
      return 1
      ;;
  esac

  if [[ ! -f "$settings" ]]; then
    echo "ccsp: 設定ファイルが見つかりません: $settings" >&2
    return 1
  fi

  # 失敗しても状態を変えないよう、トークン取得が成功してから export と alias をまとめて行う
  if [[ -z "$ANTHROPIC_AUTH_TOKEN" ]]; then
    token="$(op read 'op://Personal/DGX Spark vLLM API Key/credential')" || {
      echo "ccsp: 1Password から API キーを取得できませんでした" >&2
      return 1
    }
    export ANTHROPIC_AUTH_TOKEN="$token"
  fi

  export ANTHROPIC_BASE_URL="$base_url"
  alias claude="claude --settings $settings"
  echo "ccsp: Spark モード ($base_url)。claude で起動、ccsp off で解除"
}
