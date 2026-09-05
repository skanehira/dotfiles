# OpenCode を DGX Spark の vLLM に向けて起動する。
#
# ccsp (Claude Code 版) との違い:
# - 1Password を使わない。API キーは opencode.json の {file:...} が直接読む
# - 環境変数も alias も張らないので off に相当する解除操作が要らない
#
# 接続先とキーは ~/.config/opencode/opencode.json の provider.spark が持つ。
# この設定は dotfiles 管理 (nix/modules/home/opencode.nix が symlink する) だが、
# 接続先の実値は opencode の {file:...} 置換で ~/.config/opencode/spark-base-url
# から読む。このリポジトリは公開なので IP を置けないため。
# IP を使うのは、mDNS 名が到達できない IPv6 を返して接続が 210ms 遅くなるため
# (ccsp が NODE_OPTIONS=--dns-result-order=ipv4first で回避しているのと同じ問題)。

: ${OCSP_MODEL:=deepseek-v4-flash-vision-exp}

# opencode の設定値は {file:...} / {env:...} 置換を通してから使う。接続先も鍵も
# その形で外部ファイルに逃がしてあるので、リテラルのままでは繋がらない。
# 引数: $1 = 設定ファイル, $2 = provider.spark.options のキー名
_ocsp_resolve() {
  python3 - "$1" "$2" <<'PY'
import json, os, re, sys

cfg, key = sys.argv[1], sys.argv[2]
try:
    value = json.load(open(cfg))["provider"]["spark"]["options"][key]
except Exception:
    sys.exit(1)

m = re.fullmatch(r"\{file:(.+)\}", value)
if m:
    path = os.path.expanduser(m.group(1))
    try:
        value = open(path).read().strip()
    except OSError:
        sys.stderr.write(f"{key}: {path} が読めません\n")
        sys.exit(2)

m = re.fullmatch(r"\{env:(.+)\}", value)
if m:
    value = os.environ.get(m.group(1), "")

if not value:
    sys.exit(3)
print(value)
PY
}

ocsp() {
  local cfg="$HOME/.config/opencode/opencode.json"
  local base

  if [[ ! -f "$cfg" ]]; then
    echo "ocsp: OpenCode の設定がありません: $cfg" >&2
    echo "      provider.spark を定義してから使ってください" >&2
    return 1
  fi

  base=$(_ocsp_resolve "$cfg" baseURL 2>/dev/null) || {
    echo "ocsp: $cfg の provider.spark.options.baseURL を解決できません" >&2
    echo "      {file:...} で外部ファイルを指している場合は、そのファイルを作ってください" >&2
    echo "      例: printf 'http://<spark-head の IP>:8888/v1' > ~/.config/opencode/spark-base-url" >&2
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
        # /v1/models は Bearer が要る。opencode が読むのと同じ経路で解決する
        local key models
        if key=$(_ocsp_resolve "$cfg" apiKey 2>/dev/null); then
          models=$(curl -s -m 5 -H "Authorization: Bearer $key" "${base}/models" \
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
