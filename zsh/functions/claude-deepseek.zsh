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
# - ccsp は接続先を整えたうえで claude をその場で起動する。alias も張るので、
#   同じシェルで claude を打ち直しても --settings が効く。ただし alias は子プロセスに
#   継承されないため、サブシェルやスクリプトからは ccsp 経由で起動する
# - 別のバックエンドに切り替えるときは先に off を打つ。ANTHROPIC_AUTH_TOKEN が
#   残っていると使い回され、相手先で 401 になる
ccsp() {
  local settings="$GHQ_ROOT/github.com/skanehira/dotfiles/claude/settings.spark.json"
  # LAN 側のホストは CCSP_LAN_HOST で上書きできる。mDNS 名は到達できない IPv6 を
  # 2 つ返し、curl / Node が毎回それを試してから IPv4 に落ちるため接続が 220ms 増える
  # (IPv4 強制なら 12ms)。IP を直に使いたいときは CCSP_LAN_HOST に IP を入れる。
  # このリポジトリは公開のため IP は直書きしない。
  local lan_url="http://${CCSP_LAN_HOST:-spark-head.local}:8888"
  local ts_url="http://spark-head:8888"
  local base_url url token

  case "$1" in
    off)
      unset ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL
      # NODE_OPTIONS は ccsp が足した分だけ戻す (元から入っていた値は残す)
      if [[ -n "${_CCSP_NODE_OPTIONS_SAVED+x}" ]]; then
        if [[ -n "$_CCSP_NODE_OPTIONS_SAVED" ]]; then
          export NODE_OPTIONS="$_CCSP_NODE_OPTIONS_SAVED"
        else
          unset NODE_OPTIONS
        fi
        unset _CCSP_NODE_OPTIONS_SAVED
      fi
      unalias claude 2>/dev/null
      echo "ccsp: Anthropic に戻しました"
      return 0
      ;;
    status)
      echo "  接続先: ${ANTHROPIC_BASE_URL:-(未設定)}"
      echo "  設定  : $settings"
      echo -n "  モデル: "
      python3 -c "import json;print(json.load(open('$settings'))['env']['ANTHROPIC_MODEL'])" 2>/dev/null || echo "(読めず)"
      echo -n "  LAN   : "
      curl -fs -o /dev/null --connect-timeout 3 --max-time 5 "$lan_url/health" && echo "$lan_url に到達" || echo "$lan_url に届かない"
      echo -n "  TS    : "
      curl -fs -o /dev/null --connect-timeout 3 --max-time 5 "$ts_url/health" && echo "$ts_url に到達" || echo "$ts_url に届かない"
      return 0
      ;;
    lan) base_url="$lan_url"; shift ;;
    ts) base_url="$ts_url"; shift ;;
    -h|--help)
      echo "usage: ccsp [lan|ts|off|status] [claude に渡す引数...]" >&2
      return 0
      ;;
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
    # それ以外の引数は claude にそのまま渡す (接続先は自動選択)
    *)
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

  # mDNS 名は到達できない IPv6 を 2 つ返し、Node が毎回それを試してから IPv4 に
  # 落ちるため接続が 210ms 増えて network retry の原因になる (実測: 名前解決 8ms /
  # 接続 223ms、IPv4 強制なら 12ms)。IPv4 を先に試させて回避する。
  if [[ "$NODE_OPTIONS" != *--dns-result-order=* ]]; then
    : ${_CCSP_NODE_OPTIONS_SAVED=$NODE_OPTIONS}
    export _CCSP_NODE_OPTIONS_SAVED
    export NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--dns-result-order=ipv4first"
  fi

  alias claude="claude --settings $settings"
  echo "ccsp: Spark モード ($base_url)。ccsp off で解除"

  # 接続先を整えたらそのまま起動する。alias は同じシェルで打ち直す用に残す
  command claude --settings "$settings" "$@"
}
