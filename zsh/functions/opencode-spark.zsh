# OpenCode を DGX Spark の vLLM に向けて起動する。
#
# ccsp (Claude Code 版) との違い:
# - 1Password を使わない。API キーは opencode.json の {file:...} が直接読む
# - 環境変数も alias も張らないので off に相当する解除操作が要らない
#
# 接続先とキーは ~/.config/opencode/opencode.json の provider.spark が持つ。
# このファイルは dotfiles 管理外 (ローカル実体)。ホスト名ではなく IP を書いて
# あるのは、mDNS 名が到達できない IPv6 を返して接続が 210ms 遅くなるため
# (ccsp が NODE_OPTIONS=--dns-result-order=ipv4first で回避しているのと同じ問題)。

: ${OCSP_MODEL:=deepseek-v4-flash-vision-exp}

ocsp() {
  local cfg="$HOME/.config/opencode/opencode.json"
  local base

  if [[ ! -f "$cfg" ]]; then
    echo "ocsp: OpenCode の設定がありません: $cfg" >&2
    echo "      provider.spark を定義してから使ってください" >&2
    return 1
  fi

  base=$(python3 -c "
import json, sys
try:
    print(json.load(open('$cfg'))['provider']['spark']['options']['baseURL'])
except Exception:
    sys.exit(1)
" 2>/dev/null) || {
    echo "ocsp: $cfg に provider.spark がありません" >&2
    return 1
  }

  case "$1" in
    -h|--help|help)
      cat <<'USAGE'
使い方:
  ocsp                      対話 TUI をカレントディレクトリで起動
  ocsp run "<指示>"          headless で 1 回実行
  ocsp model <名前>          使うモデルを切り替える (0731 / vision / 明示名)
  ocsp status               接続先・モデル・サーバの状態を表示
モデル名の短縮:
  0731    -> deepseek-v4-flash-0731
  vision  -> deepseek-v4-flash-vision-exp
USAGE
      return 0
      ;;
    model)
      case "$2" in
        0731) OCSP_MODEL=deepseek-v4-flash-0731 ;;
        vision) OCSP_MODEL=deepseek-v4-flash-vision-exp ;;
        '')
          echo "ocsp: モデル名が要ります (0731 / vision / 明示名)" >&2
          return 1
          ;;
        *) OCSP_MODEL="$2" ;;
      esac
      echo "ocsp: モデルを $OCSP_MODEL にしました"
      return 0
      ;;
    status)
      echo "  接続先: $base"
      echo "  モデル: $OCSP_MODEL"
      echo -n "  サーバ: "
      if curl -fs -m 5 -o /dev/null "${base%/v1}/health"; then
        # /v1/models は Bearer が要る。キーは opencode.json の {file:...} と同じものを読む
        local keyfile models
        keyfile=$(python3 -c "
import json, re
v = json.load(open('$cfg'))['provider']['spark']['options'].get('apiKey', '')
m = re.fullmatch(r'\{file:(.+)\}', v)
print(m.group(1) if m else '')
" 2>/dev/null)
        if [[ -n "$keyfile" && -f "$keyfile" ]]; then
          models=$(curl -s -m 5 -H "Authorization: Bearer $(cat "$keyfile")" "${base}/models" \
            | python3 -c "import json,sys; print(', '.join(m['id'] for m in json.load(sys.stdin).get('data',[])))" 2>/dev/null)
        fi
        echo "health OK / 配信中: ${models:-(取得できず)}"
      else
        echo "応答なし"
      fi
      return 0
      ;;
    run)
      shift
      if [[ -z "$1" ]]; then
        echo 'ocsp: 指示文が要ります  例: ocsp run "README を要約して"' >&2
        return 1
      fi
      command opencode run --model "spark/$OCSP_MODEL" --dir "$PWD" "$@"
      return $?
      ;;
  esac

  command opencode --model "spark/$OCSP_MODEL" "$@"
}
