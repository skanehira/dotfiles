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
#   ccsp                自動判定 (LAN に届けば LAN、届かなければ Tailscale)
#   ccsp lan            自宅 LAN 直結を強制 (プローブしない)
#   ccsp ts             Tailscale 経由を強制 (プローブしない)
#   ccsp qwen           使うモデルを指定する (qwen / vision)
#   ccsp lan qwen       接続先とモデルは順不同で並べられる
#   ccsp off            Anthropic に戻す
#   ccsp status         起動せずに接続先・モデル・両経路の到達性を表示
#   ccsp -- <引数...>   解釈をやめて残り全部を claude へ (予約語を本体に渡す解除語)
#
# モデルを指定しなかった場合は /v1/models が返す配信中のモデルをそのまま使う。
# Spark は同時に 1 モデルしか配信しないので、これが常に正しい既定値になる。
# 短縮名にないモデルは CCSP_MODEL=<配信名> ccsp で渡す。
#
# reasoning effort は配信モデルごとに受け付ける語彙が違うので _ccsp_effort が
# 配信名から決める。上書きは CCSP_EFFORT=<値> ccsp で行う。
#
# 接続先 (ANTHROPIC_BASE_URL) は settings JSON に置かず、ここで export する。
# settings JSON の env はシェルの export を無条件に上書きするため、JSON に書くと
# 出先での切り替えができなくなる。
#
# Spark の vLLM は認証を無効にしてあるので、ccsp は API キーを一切扱わない
# (1Password も見ない)。
#
# 承知のうえの副作用: ANTHROPIC_AUTH_TOKEN が空だと Claude Code は自分が持っている
# 本物の Anthropic 認証情報を Authorization: Bearer で ANTHROPIC_BASE_URL へ送る
# (実測)。宛先は自宅 LAN の Spark なので許容している。信頼できないネットワーク
# 越しに使うときはこの前提が崩れるので、ダミー値を export してから使う。
#
# 注意:
# - ccsp は接続先を整えたうえで claude をその場で起動する。alias も張るので、
#   同じシェルで claude を打ち直しても --settings が効く。ただし alias は子プロセスに
#   継承されないため、サブシェルやスクリプトからは ccsp 経由で起動する
# - ccds から切り替えるときは先に off を打つ。ccsp は token を設定しないが、
#   ccds が入れた ANTHROPIC_AUTH_TOKEN が残っていると、それがそのまま Spark へ
#   送られる (無認証なので通ってしまい、気づきにくい)

# 短縮名の表・接続先・/v1/models の照会は zsh/functions/spark-common.zsh が持つ
# (ccsp / ocsp の 2 つで共有する)。

# 配信モデルに対して使える最大の reasoning effort を返す。
# 値はモデルのチャットテンプレートが検査するので、語彙にない値を送ると最初の
# リクエストが 400 で止まる (ccsp の経路 /v1/messages で Qwen が受けるのは
# low / medium / xhigh の 3 つ。high と max はテンプレートが、none はスキーマが
# 弾く)。vision (DeepSeek 系) の high はレシピの DEFAULT_THINKING の語彙
# (off / low / high / max) に合わせた値で、配信中に実測していない。
_ccsp_effort() {
  case "$1" in
    qwen3.8-flash-next) echo "xhigh" ;;
    *) echo "high" ;;
  esac
}

# base の settings にモデル名・コンテキスト上限・reasoning effort を注入した
# 設定を書き出す。毎回上書きするので、base を編集すれば次の起動から効く。
# 引数: $1 = base, $2 = 配信名, $3 = コンテキスト上限, $4 = effort, $5 = 出力先
_ccsp_render_settings() {
  python3 - "$1" "$2" "$3" "$4" "$5" <<'PY'
import json, sys

base, model, ctx, effort, out = sys.argv[1:6]
cfg = json.load(open(base))
env = cfg.setdefault("env", {})
for key in (
    "ANTHROPIC_MODEL",
    "ANTHROPIC_DEFAULT_OPUS_MODEL",
    "ANTHROPIC_DEFAULT_SONNET_MODEL",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL",
    "ANTHROPIC_DEFAULT_FABLE_MODEL",
):
    env[key] = model
env["CLAUDE_CODE_MAX_CONTEXT_TOKENS"] = str(ctx)
env["CLAUDE_CODE_EFFORT_LEVEL"] = effort
cfg["fallbackModel"] = [model]
with open(out, "w") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY
}

ccsp() {
  local base="$GHQ_ROOT/github.com/skanehira/dotfiles/claude/settings.spark.json"
  local rendered="${XDG_CACHE_HOME:-$HOME/.cache}/ccsp/settings.json"
  local lan_url="$(_spark_lan_url)"
  local ts_url="$(_spark_ts_url)"
  local base_url requested transport served ctx effort line

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
    -h|--help)
      cat <<'USAGE' >&2
使い方:
  ccsp [lan|ts] [qwen|vision] [claude に渡す引数...]
  ccsp status               起動せずに接続先・配信モデル・到達性を表示
  ccsp off                  Anthropic に戻す
  ccsp -- [claude に渡す引数...]
                            解釈をやめて残り全部を claude へ渡す
                            (status / -h など予約語を claude 側に届けたいとき)
モデル名の短縮:
  qwen    -> qwen3.8-flash-next
  vision  -> deepseek-v4-flash-vision-exp
モデルを省略すると配信中のモデルを自動で使う。短縮名に無いものは
CCSP_MODEL=<配信名> ccsp で渡す。
コンテキスト上限は max_model_len から出力用の余白 (既定 32768、
CCSP_OUTPUT_RESERVE で変更可) を引いた値になる。
reasoning effort は配信モデルごとの最大値を使う (qwen3.8-flash-next は
xhigh、他は high)。CCSP_EFFORT=<値> ccsp で上書きできるが、モデルの語彙に
無い値を渡すと最初のリクエストが 400 で落ちる (Qwen で渡せるのは
low / medium / xhigh の 3 つ)。
USAGE
      return 0
      ;;
    status)
      echo "  接続先: ${ANTHROPIC_BASE_URL:-(未設定)}"
      echo "  base  : $base"
      echo "  要求  : ${CCSP_MODEL:-(指定なし。配信中のモデルを使う)}"
      echo "  effort: ${CCSP_EFFORT:-(配信モデルで決める: qwen3.8-flash-next→xhigh / 他→high)}"
      local reachable="" probe
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
      probe="${ANTHROPIC_BASE_URL:-$reachable}"
      if [[ -n "$probe" ]]; then
        _spark_models "$probe" "$ANTHROPIC_AUTH_TOKEN" | awk '{printf "%s (max_model_len %s) ", $1, $2}' || true
        echo
      else
        echo "(どちらにも届かないので取得できない)"
      fi
      return 0
      ;;
  esac

  # 接続先とモデルは順不同で並べられる。認識しない語はそこで打ち切り、
  # 残りをすべて claude への引数として渡す。-- も打ち切り語で、予約語
  # (off / status / -h) を claude 側に届けたいときの解除語にする。-- 自体は
  # ccsp で消費して渡さない (渡すと claude が option 解析の終端として扱い、
  # 後続の語を prompt 位置に回してしまって意図に合わない)。
  while (( $# > 0 )); do
    case "$1" in
      lan) transport="$lan_url"; shift ;;
      ts) transport="$ts_url"; shift ;;
      qwen|vision) requested="$(_spark_served_name "$1")"; shift ;;
      --) shift; break ;;
      *) break ;;
    esac
  done
  : ${requested:=$CCSP_MODEL}

  if [[ -n "$transport" ]]; then
    base_url="$transport"
  else
    base_url="$(_spark_base_url)" || {
      echo "ccsp: LAN にも Tailscale にも届きません (ccsp lan / ccsp ts で強制できます)" >&2
      return 1
    }
  fi

  if [[ ! -f "$base" ]]; then
    echo "ccsp: 設定ファイルが見つかりません: $base" >&2
    return 1
  fi

  # モデル名とコンテキスト上限はサーバに聞く。表を持たないので配信側を変えても
  # ここは追従不要で、要求したモデルが載っていなければ起動前に落とせる。
  line=$(_spark_models "$base_url" "$ANTHROPIC_AUTH_TOKEN" | if [[ -n "$requested" ]]; then grep -x -- "$requested [0-9]*" || true; else head -1; fi)
  if [[ -z "$line" ]]; then
    echo "ccsp: ${requested:-配信中のモデル} を $base_url から取得できません" >&2
    echo "      配信中: $(_spark_models "$base_url" "$ANTHROPIC_AUTH_TOKEN" | awk '{print $1}' | paste -sd, - 2>/dev/null || echo '(取得できず)')" >&2
    return 1
  fi
  served="${line%% *}"
  # サーバの max_model_len は入力と出力の合計なので、出力用の余白を引いた分を
  # Claude Code の窓にする。既定の余白は CCSP_OUTPUT_RESERVE で変えられる。
  # 半分にしていた頃の根拠 (1M のまま使うと長文脈の品質劣化とプレフィル遅延を
  # 招く) は、サーバ側を常用長に合わせて設定する運用に切り替えたので不要になった。
  ctx=$(( ${line##* } - ${CCSP_OUTPUT_RESERVE:-32768} ))
  if (( ctx < 1 )); then
    echo "ccsp: max_model_len (${line##* }) が出力用の余白 ${CCSP_OUTPUT_RESERVE:-32768} 以下です" >&2
    return 1
  fi

  # reasoning effort もモデル依存なので配信名から決める (上書きは CCSP_EFFORT)。
  effort="${CCSP_EFFORT:-$(_ccsp_effort "$served")}"

  mkdir -p "${rendered:h}" || return 1
  _ccsp_render_settings "$base" "$served" "$ctx" "$effort" "$rendered" || {
    echo "ccsp: 設定の生成に失敗しました: $rendered" >&2
    return 1
  }

  export ANTHROPIC_BASE_URL="$base_url"

  # mDNS 名は到達できない IPv6 を 2 つ返し、Node が毎回それを試してから IPv4 に
  # 落ちるため接続が 210ms 増えて network retry の原因になる (実測: 名前解決 8ms /
  # 接続 223ms、IPv4 強制なら 12ms)。IPv4 を先に試させて回避する。
  if [[ "$NODE_OPTIONS" != *--dns-result-order=* ]]; then
    : ${_CCSP_NODE_OPTIONS_SAVED=$NODE_OPTIONS}
    export _CCSP_NODE_OPTIONS_SAVED
    export NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--dns-result-order=ipv4first"
  fi

  alias claude="claude --settings $rendered"
  echo "ccsp: Spark モード ($base_url / $served / コンテキスト $ctx / effort $effort)。ccsp off で解除"

  # 接続先を整えたらそのまま起動する。alias は同じシェルで打ち直す用に残す
  command claude --settings "$rendered" "$@"
}
