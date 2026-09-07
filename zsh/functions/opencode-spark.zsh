# OpenCode を DGX Spark の vLLM に向けて起動する。
#
# ccsp (Claude Code 版) との違い:
# - 1Password を使わない。vLLM が認証を要求しないので API キーを持たない
# - 環境変数も alias も張らないので off に相当する解除操作が要らない
#
# 接続先は ccsp と同じく spark-common.zsh の _spark_base_url が決める。自宅 LAN と
# Tailscale の /health をこの順にプローブして到達する方を採り、その値で
# opencode.json の provider.spark.options.baseURL を起動ごとに上書きする。
# 上書きは環境変数 OPENCODE_CONFIG_CONTENT の前置代入で行う。opencode は
# このインライン JSON を設定にディープマージするので、models と npm の宣言は
# opencode.json のものがそのまま残る。前置代入は子プロセス限りなので、素の
# opencode を打った場合は従来どおり opencode.json の baseURL (LAN) が効く。
#
# LAN 側に IP を使いたいマシンは ccsp と同じ CCSP_LAN_HOST に入れる
# (このリポジトリは公開なので関数にも opencode.json にも IP を書かない)。
#
# サーバが認証を要求するようになったら opencode.json の options に apiKey を足す。
# {file:...} / {env:...} 置換は下の _ocsp_resolve が解いてから使う。

# 短縮名の表・接続先・/v1/models の照会は zsh/functions/spark-common.zsh が持つ
# (ccsp / ocsp の 2 つで共有する)。ocsp は max_model_len を使わないので
# 配信名の列だけを取り出す。
_ocsp_models() { _spark_models "$1" "$2" | awk '{print $1}' }

# opencode に渡す設定の上書き分。baseURL の 1 キーだけを差し替える。
# 引数: $1 = base URL (末尾に /v1 を含まない形)
_ocsp_config_override() {
  printf '{"provider":{"spark":{"options":{"baseURL":"%s/v1"}}}}' "$1"
}

# opencode の設定値は {file:...} / {env:...} 置換を通してから使う。認証を戻したとき
# の鍵はその形で外部ファイルに逃がせるので、リテラルのままでは繋がらない。
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
  local lan_url="$(_spark_lan_url)"
  local ts_url="$(_spark_ts_url)"
  local base_url transport model key served

  # provider.spark の宣言 (npm / models) は opencode.json にしかないので、
  # 接続先を上書きする方式でもこのファイル自体は要る。
  if [[ ! -f "$cfg" ]]; then
    echo "ocsp: OpenCode の設定がありません: $cfg" >&2
    echo "      provider.spark を定義してから使ってください" >&2
    return 1
  fi

  case "$1" in
    -h|--help|help)
      cat <<'USAGE'
使い方:
  ocsp                      到達する方 (LAN → Tailscale) を選んで対話 TUI を起動
  ocsp lan                  自宅 LAN を強制 (プローブしない)
  ocsp ts                   Tailscale を強制 (プローブしない)
  ocsp qwen                 モデルを指定して起動 (qwen / vision)
  ocsp ts qwen              接続先とモデルは順不同で並べられる
  ocsp run "<指示>"          headless で 1 回実行
  ocsp qwen run "<指示>"     モデルを指定して headless 実行
  ocsp model <名前>          このシェルの既定モデルを切り替える
  ocsp status               両経路の到達性・モデル・サーバの状態を表示
  ocsp session list ...     opencode のサブコマンドは素通し (検査・--model なし)
  ocsp -- <引数...>           解釈をやめて残り全部を opencode へ
                             (help / model / status など予約語を本体に渡す解除語)
モデル名の短縮:
  qwen    -> qwen3.8-flash-next
  vision  -> deepseek-v4-flash-vision-exp
モデルを省略すると配信中のモデルを自動で使う。接続先を省略すると
LAN -> Tailscale の順に /health をプローブして到達する方を使う。
status と model は先頭に置く (ocsp ts status は通らない)。
LAN 側に IP を使いたいときは CCSP_LAN_HOST に入れる (ccsp と共通)。
USAGE
      return 0
      ;;
    model)
      if [[ -z "$2" ]]; then
        echo "ocsp: モデル名が要ります (qwen / vision / 明示名)" >&2
        return 1
      fi
      OCSP_MODEL="$(_spark_served_name "$2")"
      echo "ocsp: モデルを $OCSP_MODEL にしました"
      return 0
      ;;
    status)
      local reachable=""
      echo "  要求  : ${OCSP_MODEL:-(指定なし。配信中のモデルを使う)}"
      echo -n "  LAN   : "
      if curl -fs -o /dev/null --connect-timeout 3 --max-time 5 "$lan_url/health"; then
        reachable="$lan_url"; echo "$lan_url に到達"
      else
        echo "$lan_url に届かない"
      fi
      echo -n "  TS    : "
      if curl -fs -o /dev/null --connect-timeout 3 --max-time 5 "$ts_url/health"; then
        : ${reachable:=$ts_url}; echo "$ts_url に到達"
      else
        echo "$ts_url に届かない"
      fi
      echo -n "  配信中: "
      if [[ -n "$reachable" ]]; then
        # apiKey は設定にあれば opencode と同じ経路で解決して使う (無ければ無認証)
        key=$(_ocsp_resolve "$cfg" apiKey 2>/dev/null) || key=""
        served=$(_ocsp_models "$reachable" "$key" | paste -sd, -)
        echo "${served:-(取得できず)}"
      else
        echo "(どちらにも届かないので取得できない)"
      fi
      return 0
      ;;
  esac

  # 先頭の -- は ocsp の解釈を打ち切る解除語で、残り全部を opencode に素渡しする
  # (help / model / status など予約語や、サブコマンド先頭の組み立てを迂回したいとき)。
  # 接続先の上書きも配信検査も --model 注入も通らないので、サーバが落ちていても
  # 素の opencode と同じ挙動になる。-- 自体は opencode に渡さない (option 解析の
  # 終端マーカーとして後続の組み立てに影響させる意図はない)。
  if [[ "$1" == "--" ]]; then
    shift
    command opencode "$@"
    return $?
  fi

  # 接続先とモデルは順不同で並べられる。認識しない語はそこで打ち切り、
  # 残りをすべて opencode への引数として渡す。
  # 指定が無ければ配信中のモデルを採る。Spark は同時に 1 モデルしか配信しない
  # ので、表を持たずにサーバへ聞くのが常に正しい。
  while (( $# > 0 )); do
    case "$1" in
      lan) transport="$lan_url"; shift ;;
      ts) transport="$ts_url"; shift ;;
      qwen|vision) model="$(_spark_served_name "$1")"; shift ;;
      *) break ;;
    esac
  done
  : ${model:=$OCSP_MODEL}

  # opencode のサブコマンド (run を除く) はモデルを使わないので、接続先の決定も
  # 配信検査も --model 注入もしない。--model を前置すると yargs がそのサブコマンドで
  # 未知の option として扱い、実行の代わりに help 表示になる (実測:
  # opencode --model spark/fake session list は help を出すだけ)。
  # run は --model を受け付けるので下の専用経路に任せる。一覧は opencode --help の commands と対応。
  # プローブより前に置く: サーバが落ちていてもサブコマンドは打てる必要がある。
  if [[ "$1" != "run" ]]; then
    case "$1" in
      completion|acp|mcp|attach|providers|auth|agent|upgrade|uninstall|serve|\
      web|models|stats|export|import|github|pr|session|plugin|plug|db|debug)
        command opencode "$@"
        return $?
        ;;
    esac
  fi

  if [[ -n "$transport" ]]; then
    base_url="$transport"
  else
    base_url="$(_spark_base_url)" || {
      echo "ocsp: LAN にも Tailscale にも届きません (ocsp lan / ocsp ts で強制できます)" >&2
      return 1
    }
  fi

  # 配信中の一覧が引けないまま起動すると、モデル名の検査を素通りしたうえで
  # opencode が同じ経路で失敗する。ccsp と同じく、ここで止める。
  key=$(_ocsp_resolve "$cfg" apiKey 2>/dev/null) || key=""
  served=$(_ocsp_models "$base_url" "$key")
  if [[ -z "$served" ]]; then
    echo "ocsp: 配信中のモデルを $base_url から取得できません" >&2
    echo "      サーバが落ちているか、認証を要求するようになった可能性がある" >&2
    echo "      (後者なら opencode.json の options に apiKey を足す)" >&2
    echo "      切り分けは ocsp status" >&2
    return 1
  fi
  if [[ -z "$model" ]]; then
    model=$(echo "$served" | head -1)
  elif ! echo "$served" | grep -qx -- "$model"; then
    echo "ocsp: $model は配信されていません" >&2
    echo "      配信中: $(echo "$served" | paste -sd, -)" >&2
    return 1
  fi

  # 接続先は前置代入で渡す。export しないのでシェルには何も残らない。
  local override="$(_ocsp_config_override "$base_url")"

  if [[ "$1" == "run" ]]; then
    shift
    if [[ -z "$1" ]]; then
      echo 'ocsp: 指示文が要ります  例: ocsp run "README を要約して"' >&2
      return 1
    fi
    OPENCODE_CONFIG_CONTENT="$override" command opencode run --model "spark/$model" --dir "$PWD" "$@"
    return $?
  fi

  OPENCODE_CONFIG_CONTENT="$override" command opencode --model "spark/$model" "$@"
}
