# DGX Spark の vLLM に向くクライアント (ccsp / ocsp) が共有するヘルパー。
#
# 短縮名の表と /v1/models の照会をここに 1 つだけ置く。以前はクライアントごとに
# 同じ表を持っていたため、片方にだけモデルを足すとその側でしか通らなかった。
#
# 接続先のホスト名は関数に直書きしない値を 1 つだけ持つ (CCSP_LAN_HOST)。
# このリポジトリは公開なので IP は置かず、IP を使いたいマシンだけが
# CCSP_LAN_HOST に入れる。

# LAN 側 (自宅) の接続先。mDNS 名は到達できない IPv6 を先に返すため接続が
# 210ms ほど遅い。IP を入れたいときは CCSP_LAN_HOST を使う。
_spark_lan_url() { echo "http://${CCSP_LAN_HOST:-spark-head.local}:8888" }

# Tailscale 側 (出先) の接続先。ssh_config を通らないので MagicDNS 名で解決される。
_spark_ts_url() { echo "http://spark-head:8888" }

# 使う接続先を 1 つ決めて標準出力に返す。
# 引数: $1 = lan / ts / 空 (空なら /health が返る方を LAN → Tailscale の順で選ぶ)
# どちらにも届かなければ何も出さずに 1 を返す。
_spark_base_url() {
  case "$1" in
    lan) _spark_lan_url; return 0 ;;
    ts)  _spark_ts_url;  return 0 ;;
  esac
  local url
  # /health は無認証なので API キー無しで叩ける。--connect-timeout は名前解決にも
  # 効く (curl は AsynchDNS 付き) ため、mDNS がハングしてもここで打ち切られる。
  for url in "$(_spark_lan_url)" "$(_spark_ts_url)"; do
    if curl -fs -o /dev/null --connect-timeout 3 --max-time 5 "$url/health"; then
      echo "$url"
      return 0
    fi
  done
  return 1
}

# モデルの短縮名を vLLM の SERVED_MODEL_NAME に展開する。
# 短縮名に無いものはそのまま返し、配信名として扱う。
_spark_served_name() {
  case "$1" in
    qwen) echo "qwen3.8-flash-next" ;;
    vision) echo "deepseek-v4-flash-vision-exp" ;;
    *) echo "$1" ;;
  esac
}

# 配信中のモデルを「配信名 max_model_len」の行で返す。
# 引数: $1 = base URL ($ 末尾の /v1 は有っても無くてもよい), $2 = Bearer トークン (空可)
# トークンが空のときは Authorization ヘッダ自体を送らない (無認証のサーバ向け)。
_spark_models() {
  local base="${1%/}"
  base="${base%/v1}"
  local -a auth=()
  [[ -n "$2" ]] && auth=(-H "Authorization: Bearer $2")
  curl -fs -m 10 "${auth[@]}" "$base/v1/models" 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin).get("data", [])
except Exception:
    sys.exit(1)
for m in data:
    print(m["id"], m.get("max_model_len", 0))
' 2>/dev/null
}
