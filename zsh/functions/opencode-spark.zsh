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

# モデルの短縮名を vLLM の SERVED_MODEL_NAME に展開する。
# 短縮名に無いものはそのまま返し、配信名として扱う (ccsp と同じ表)。
_ocsp_served_name() {
  case "$1" in
    qwen) echo "qwen3.8-flash-next" ;;
    vision) echo "deepseek-v4-flash-vision-exp" ;;
    0731) echo "deepseek-v4-flash-0731" ;;
    *) echo "$1" ;;
  esac
}

# 配信中のモデル名を 1 行ずつ返す。引数: $1 = base URL, $2 = Bearer トークン
_ocsp_models() {
  curl -fs -m 10 -H "Authorization: Bearer $2" "$1/models" 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin).get("data", [])
except Exception:
    sys.exit(1)
for m in data:
    print(m["id"])
' 2>/dev/null
}

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
  ocsp qwen                 モデルを指定して起動 (qwen / vision / 0731)
  ocsp run "<指示>"          headless で 1 回実行
  ocsp qwen run "<指示>"     モデルを指定して headless 実行
  ocsp model <名前>          このシェルの既定モデルを切り替える
  ocsp status               接続先・モデル・サーバの状態を表示
モデル名の短縮:
  qwen    -> qwen3.8-flash-next
  vision  -> deepseek-v4-flash-vision-exp
  0731    -> deepseek-v4-flash-0731
モデルを省略すると配信中のモデルを自動で使う。
USAGE
      return 0
      ;;
    model)
      if [[ -z "$2" ]]; then
        echo "ocsp: モデル名が要ります (qwen / vision / 0731 / 明示名)" >&2
        return 1
      fi
      OCSP_MODEL="$(_ocsp_served_name "$2")"
      echo "ocsp: モデルを $OCSP_MODEL にしました"
      return 0
      ;;
    status)
      echo "  接続先: $base"
      echo "  要求  : ${OCSP_MODEL:-(指定なし。配信中のモデルを使う)}"
      echo -n "  サーバ: "
      if curl -fs -m 5 -o /dev/null "${base%/v1}/health"; then
        # /v1/models は Bearer が要る。opencode が読むのと同じ経路で解決する
        local key models
        if key=$(_ocsp_resolve "$cfg" apiKey 2>/dev/null); then
          models=$(_ocsp_models "$base" "$key" | paste -sd, -)
        fi
        echo "health OK / 配信中: ${models:-(取得できず)}"
      else
        echo "応答なし"
      fi
      return 0
      ;;
  esac

  # 先頭がモデル短縮名ならこの起動だけそれを使う (シェルの既定は変えない)。
  # 指定が無ければ配信中のモデルを採る。Spark は同時に 1 モデルしか配信しない
  # ので、表を持たずにサーバへ聞くのが常に正しい。
  local model="" key served
  case "$1" in
    qwen|vision|0731) model="$(_ocsp_served_name "$1")"; shift ;;
  esac
  : ${model:=$OCSP_MODEL}

  # 配信中の一覧が引けないまま起動すると、モデル名の検査を素通りしたうえで
  # opencode が同じ鍵で 401 になる。ccsp と同じく、ここで止める。
  key=$(_ocsp_resolve "$cfg" apiKey 2>/dev/null) || key=""
  served=$(_ocsp_models "$base" "$key")
  if [[ -z "$served" ]]; then
    echo "ocsp: 配信中のモデルを $base から取得できません" >&2
    echo "      /v1/models は Bearer が要る。opencode.json の apiKey が指すファイル" >&2
    echo "      (既定は /tmp/spark.key。再起動で消える) とサーバの状態を確認する" >&2
    echo "      サーバ側の切り分けは ocsp status" >&2
    return 1
  fi
  if [[ -z "$model" ]]; then
    model=$(echo "$served" | head -1)
  elif ! echo "$served" | grep -qx -- "$model"; then
    echo "ocsp: $model は配信されていません" >&2
    echo "      配信中: $(echo "$served" | paste -sd, -)" >&2
    return 1
  fi

  if [[ "$1" == "run" ]]; then
    shift
    if [[ -z "$1" ]]; then
      echo 'ocsp: 指示文が要ります  例: ocsp run "README を要約して"' >&2
      return 1
    fi
    command opencode run --model "spark/$model" --dir "$PWD" "$@"
    return $?
  fi

  command opencode --model "spark/$model" "$@"
}
