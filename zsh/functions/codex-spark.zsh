# Codex を DGX Spark 上のローカル vLLM に向けて起動する (この起動 1 回だけ)
#
#   cxsp                自動判定 (LAN に届けば LAN、届かなければ Tailscale)
#   cxsp lan            自宅 LAN 直結を強制 (プローブしない)
#   cxsp ts             Tailscale 経由を強制 (プローブしない)
#   cxsp qwen           使うモデルを指定する (qwen / vision / v41)
#   cxsp lan qwen       接続先とモデルは順不同で並べられる
#   cxsp exec "<指示>"  codex のサブコマンドはそのまま渡る
#   cxsp status         起動せずに要求モデル・両経路の到達性・配信中モデルを表示
#   cxsp -- <引数...>   解釈をやめて残り全部を codex へ (予約語を本体に渡す解除語)
#
# ccsp / ocsp との違い:
# - ccsp と違い環境変数も alias も張らない。設定はすべて codex の -c で渡すので、
#   1 回の起動にしか効かず off に相当する解除操作が要らない (ocsp と同じ方針)
# - ocsp と違い、サブコマンドでも検査と注入を飛ばさない。codex は root の -c を
#   subcommand の前に置けるので (実測: codex -c ... exec ...)、全経路で同じ注入が通る
#
# 設定ファイルは使わない。--profile は $CODEX_HOME/<名前>.config.toml を読むので
# ~/.codex/ に状態を残すことになり、素の codex (ChatGPT ログイン) と混ざる。
# -c は /etc/codex/config.toml と ~/.codex/config.toml の両方より優先される。
#
# Spark の vLLM は認証を無効にしてあるので API キーを扱わない。codex は
# model_providers.<id>.env_key を省くと Authorization ヘッダ自体を送らず、
# ChatGPT のトークンも流用しない (requires_openai_auth の既定が false のため)。
#
# LAN 側に IP を使いたいマシンは ccsp / ocsp と共通の CCSP_LAN_HOST に入れる
# (このリポジトリは公開なので関数に IP を書かない)。

# codex に渡す -c の一式を配列で組み立てて標準出力に 1 行 1 個で返す。
# 引数: $1 = base URL (末尾に /v1 を含まない形), $2 = 配信名, $3 = コンテキスト上限, $4 = effort
#
# model_providers.spark.name は空にできない。空だと codex が
# 「provider name must not be empty」で設定全体の読み込みに失敗する (実測)。
#
# wire_api は responses だけが有効。codex 0.154.0 が chat を削除しており、
# "chat" を渡すと設定を読んだ時点でエラーになる。
#
# model_context_window には max_model_len を CXSP_CONTEXT_MAX (既定 500,000) で
# 頭打ちにした値を入れる。codex は未知モデルに effective_context_window_percent
# = 95 を掛けるので、500,000 なら 25,000 が出力用の余白として自動的に残る
# (ccsp のように自分で引かないのはこのため)。明示しないと未知モデルの
# fallback 272,000 で頭打ちになる。
#
# web_search は disabled にする。agents/bindings/codex/config.toml が live を
# 配っており、カスタム provider でも hosted の web_search tool が tools に載る。
# vLLM がこの tool 型を受けるか未確認なので経路ごと切る。
_cxsp_config_args() {
  print -r -- "model_provider=\"spark\""
  print -r -- "model_providers.spark.name=\"DGX Spark vLLM\""
  print -r -- "model_providers.spark.base_url=\"$1/v1\""
  print -r -- "model_providers.spark.wire_api=\"responses\""
  print -r -- "model=\"$2\""
  print -r -- "model_context_window=$3"
  print -r -- "model_reasoning_effort=\"$4\""
  print -r -- "web_search=\"disabled\""
}

cxsp() {
  local lan_url="$(_spark_lan_url)"
  local ts_url="$(_spark_ts_url)"
  local base_url requested transport served ctx effort line
  local -a cfg

  case "$1" in
    -h|--help|help)
      cat <<'USAGE'
使い方:
  cxsp [lan|ts] [qwen|vision|v41] [codex に渡す引数...]
  cxsp exec "<指示>"        headless で 1 回実行 (codex のサブコマンドは素通し)
  cxsp status               起動せずに接続先・配信モデル・到達性を表示
  cxsp -- [codex に渡す引数...]
                            解釈をやめて残り全部を codex へ渡す
                            (status / -h など予約語を codex 側に届けたいとき)
モデル名の短縮:
  qwen    -> qwen3.8-flash-next
  vision  -> deepseek-v4-flash-vision-exp
  v41     -> DeepSeek-v4.1-Flash-EXL3
モデルを省略すると配信中のモデルを自動で使う。短縮名に無いものは
CXSP_MODEL=<配信名> cxsp で渡す。接続先を省略すると LAN -> Tailscale の順に
/health をプローブして到達する方を使う。
コンテキスト上限は max_model_len と 500000 の小さい方 (CXSP_CONTEXT_MAX で
変更可)。codex はこの値の 95% を実効値に使い、残りが出力用の余白になる。
reasoning effort は配信モデルごとの最大値を使う (qwen3.8-flash-next は xhigh、
DeepSeek-v4.1-Flash-EXL3 は max、他は high)。CXSP_EFFORT=<値> cxsp で上書き
できるが、モデルの語彙に無い値を渡すと最初のリクエストが 400 で落ちる。
環境変数も alias も残さないので解除操作は要らない (素の codex は ChatGPT の
ままで、この関数は一切触らない)。
USAGE
      return 0
      ;;
    status)
      echo "  要求  : ${CXSP_MODEL:-(指定なし。配信中のモデルを使う)}"
      echo "  effort: ${CXSP_EFFORT:-(配信モデルで決める: qwen3.8-flash-next→xhigh / DeepSeek-v4.1-Flash-EXL3→max / 他→high)}"
      local reachable=""
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
        _spark_models "$reachable" "" | awk '{printf "%s (max_model_len %s) ", $1, $2}' || true
        echo
      else
        echo "(どちらにも届かないので取得できない)"
      fi
      return 0
      ;;
  esac

  # 接続先とモデルは順不同で並べられる。認識しない語はそこで打ち切り、
  # 残りをすべて codex への引数として渡す。-- も打ち切り語で、予約語
  # (status / -h) を codex 側に届けたいときの解除語にする。-- 自体は cxsp で
  # 消費して渡さない (渡すと codex が option 解析の終端として扱う)。
  while (( $# > 0 )); do
    case "$1" in
      lan) transport="$lan_url"; shift ;;
      ts) transport="$ts_url"; shift ;;
      qwen|vision|v41) requested="$(_spark_served_name "$1")"; shift ;;
      --) shift; break ;;
      *) break ;;
    esac
  done
  : ${requested:=$CXSP_MODEL}

  if [[ -n "$transport" ]]; then
    base_url="$transport"
  else
    base_url="$(_spark_base_url)" || {
      echo "cxsp: LAN にも Tailscale にも届きません (cxsp lan / cxsp ts で強制できます)" >&2
      return 1
    }
  fi

  # モデル名とコンテキスト上限はサーバに聞く。表を持たないので配信側を変えても
  # ここは追従不要で、要求したモデルが載っていなければ起動前に落とせる。
  local models
  models=$(_spark_models "$base_url" "")
  if [[ -n "$requested" ]]; then
    # 配信名そのものと完全一致で比べる。grep の正規表現で照合すると、配信名に
    # 含まれる . (qwen3.8-flash-next 等) が任意の 1 文字に化けて別名にも当たる。
    line=$(echo "$models" | awk -v want="$requested" '{ name = $0; sub(/ [^ ]*$/, "", name); if (name == want) { print; exit } }')
  else
    line=$(echo "$models" | head -1)
  fi
  if [[ -z "$line" ]]; then
    local served_list
    served_list=$(echo "$models" | awk 'NF {print $1}' | paste -sd, -)
    echo "cxsp: ${requested:-配信中のモデル} を $base_url から取得できません" >&2
    echo "      配信中: ${served_list:-(取得できず)}" >&2
    return 1
  fi
  # 配信名に空白が混じっても最後のフィールドが max_model_len である形は変わらない。
  ctx="${line##* }"
  served="${line% *}"

  # codex に渡すコンテキスト上限。サーバの max_model_len をそのまま渡すと、
  # codex が掛ける 95% でも実効 570,000 トークンと長すぎるので上限で頭を打つ。
  # 既定 500,000 は agents/bindings/codex/config.toml の model_context_window と同じ値。
  local ctx_max="${CXSP_CONTEXT_MAX:-500000}"
  (( ctx > ctx_max )) && ctx=$ctx_max
  if (( ctx < 1 )); then
    echo "cxsp: コンテキスト上限が $ctx です ($base_url の /v1/models が max_model_len を返していない)" >&2
    return 1
  fi

  effort="${CXSP_EFFORT:-$(_spark_effort "$served")}"

  cfg=()
  local kv
  while IFS= read -r kv; do
    cfg+=(-c "$kv")
  done < <(_cxsp_config_args "$base_url" "$served" "$ctx" "$effort")

  # exec が headless の入口なので、この案内は stdout に混ぜず stderr に出す
  echo "cxsp: Spark モード ($base_url / $served / コンテキスト $ctx / effort $effort)" >&2

  command codex "${cfg[@]}" "$@"
}
