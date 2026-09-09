---
# 常駐読み込みさせないためのマーカー (このパスにマッチするファイルは存在しない)。
# 本ファイルは必要になったときに Read で参照する。
paths:
  - "__read-on-demand-only__"
---

# DGX Spark 2 台構成 (自宅のローカル LLM クラスタ)

- 種別: 環境リファレンス
- 対象読者: 別セッション・別マシンで作業する Claude
- 最終確認: 2026-09-09 (Qwen レシピを `0b62e12` へ更新して再起動。ccds の起動挙動と、監査で挙がった記述の実機突合)
- 他の節の確認日: 2026-09-06 (一部は 2026-09-09 に再確認)。「実測値」節の性能値のみ 2026-09-05。表ごとに計測日を書いてある

自宅に NVIDIA DGX Spark (GB10) が 2 台あり、vLLM の TP=2 (tensor parallel、2 台に重みを分割する並列方式) でローカル LLM を常時サービングしている。Mac の Claude Code (`ccsp`) / OpenCode (`ocsp`) の 2 つからバックエンドとして使える。

**レシピは 2 系統ある。** DeepSeek 系 (Vision-Exp) と Qwen 系 (Qwen3.8-Flash-Next) で、ポート 8888 と GPU を共有するため**同時には 1 つしか配信できない**。2026-09-09 時点の配信は Qwen3.8-Flash-Next である。系統ごとにスクリプト名・コンテナ名・設定ファイル名が違うので、作業前にどちらが動いているかを確かめる (`ssh -n spark-head 'docker ps --filter name=vllm'`)。

**dotfiles リポジトリの所在は `~/dev/github.com/skanehira/dotfiles` である。** 本書でリポジトリ相対で書くパスはすべてここを基点とする。**本書の表で「—」は該当なしを意味する。**

## 用語・成果物一覧

| 名前 | 意味 | 定義箇所 | 生成者 | 消費者 |
| --- | --- | --- | --- | --- |
| DeepSeek 系 / Qwen 系 | レシピの系統。スクリプト名・コンテナ名・認証の有無が異なり、同時には配信できない | 冒頭の「レシピは 2 系統ある」 | — | 人 |
| head / worker | TP=2 の rank 0 / rank 1。head だけが HTTP API を持ち、worker は headless | `.env.dspark` の `WORKER_HOST` | 人 (初期構築) | 起動スクリプト |
| レシピ | 上流が配布する compose + シェルスクリプト一式 | head の `~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark/` | 上流 (`git clone`) | 人 |
| Vision-Exp | `deepseek-ai/DeepSeek-V4-Flash-Vision-Exp` の略。画像入力が使える。DeepSeek 系の常用モデル | 「サービングの構成 (DeepSeek 系)」 | 上流のチェックポイント | vLLM |
| Qwen3.8-Flash-Next | `nvidia/Qwen3.8-Flash-Next-NVFP4` の略。DeepSeek 系とは別レシピで配信する | 「Qwen3.8-Flash-Next」 | 上流のチェックポイント | vLLM |
| 0731 | `deepseek-ai/DeepSeek-V4-Flash-0731` の略。**配信候補ではない。** 重みと専用 worktree がディスクに残っているだけ | 「触らないもの」 | — | — |
| RoCE | RDMA over Converged Ethernet。QSFP ポート上でノード間の NCCL 集団通信を運ぶ | `.env.dspark` の `NCCL_IB_HCA` | NetworkManager の接続 `roce` / `roce2` | vLLM (NCCL) |
| NCCL | NVIDIA Collective Communications Library。TP=2 のランク間通信を担う | 本表 | — | vLLM |
| DSpark | チェックポイント内蔵の投機デコード。draft 用の別モデルを持たない | vLLM の CLI フラグ `--speculative-config` | レシピの compose | vLLM |
| MTP | multi-token prediction。DSpark が 1 ステップで出す draft トークン数 (`MTP_NUM_TOKENS`) | `.env.dspark` | 人 | vLLM |
| `nvfp4_ds_mla` | MLA (multi-head latent attention) の KV キャッシュを 4bit で保持する形式 | vLLM の CLI フラグ `--kv-cache-dtype` | レシピの compose | vLLM |
| TTFT | time to first token。送信から最初のトークンが返るまでの時間。ほぼ prefill の所要時間 | 本表 | `~/spark-bench/bench.py` | 「L1」表 |
| 受理率 | 投機デコードが出した draft トークンのうち採用された割合。decode 速度をほぼ決める | 本表 | vLLM の `/metrics` | 「L2 / L3」表・「遅いと感じたときに疑う順序」4 |
| L1 / L2 / L3 | 計測の層。L1 = サーバを直叩き (クライアント無し) / L2 = Claude Code 経由 / L3 = OpenCode 経由 | 本表 | `bench.py` (L1) / `snap.py` (L2・L3) | 「実測値」節 |
| `ccsp` | Claude Code を本クラスタに向けて**起動する**ところまで行う zsh 関数 | `zsh/functions/claude-deepseek.zsh` | dotfiles | 人 |
| `ccds` | 同じく DeepSeek 本家 API へ向けて**起動する**ところまで行う zsh 関数。`agents/bindings/claude/settings.deepseek.json` を `--settings` で渡す。**予約語は第 1 引数の `off` だけ**で、それ以外の語はそのまま `claude` に渡る (`off` の後ろに書いた引数は無視される。`ccds off` で Anthropic に戻す)。`ccsp` と環境変数 `ANTHROPIC_AUTH_TOKEN` を共有する (入る値は別) | 同上 | dotfiles | 人 |
| `CCSP_LAN_HOST` | LAN 側ホスト名を上書きするシェル変数。`CCSP_LAN_HOST=<IP> ccsp` と前置きしても export しても効く。**名前は `ccsp` 由来だが 2 つのクライアントが共有する** | `zsh/functions/spark-common.zsh` | 人 | `ccsp` / `ocsp` |
| `ocsp` | OpenCode を本クラスタに向けて起動する zsh 関数。API キーも alias も持たない。接続先は `ccsp` と同じく到達する方を選ぶ | `zsh/functions/opencode-spark.zsh` | dotfiles | 人 |
| `spark-common.zsh` | 2 つのクライアントが共有するヘルパー。短縮名の表・接続先の URL とプローブ・`/v1/models` の照会を持つ | `zsh/functions/spark-common.zsh` | dotfiles | `ccsp` / `ocsp` |
| `CCSP_MODEL` | `ccsp` が使う配信名を保持するシェル変数。短縮名に無いモデルを渡すときだけ使う。**未設定が既定で、その場合は配信中のモデルを採る** | `zsh/functions/claude-deepseek.zsh` | 人 | `ccsp` |
| `OCSP_MODEL` | 同じく `ocsp` 用。`ocsp model` が書き換える。**未設定が既定で、その場合は配信中のモデルを採る** | `zsh/functions/opencode-spark.zsh` | `ocsp model` | `ocsp` |
| `CCSP_OUTPUT_RESERVE` | `max_model_len` から差し引く出力用の余白 (トークン数)。既定は 32,768 | `zsh/functions/claude-deepseek.zsh` | 人 | `ccsp` |
| 短縮名 | モデル名の短縮。`qwen` と `vision` の 2 つで、`SERVED_MODEL_NAME` に展開する。**モデルとして渡せるのはこの 2 語だけで、短縮名にも `lan` / `ts` にも当たらない語はクライアント本体の引数 (`ocsp` ではサブコマンド検知) に回る。** 配信名を直に指定する経路は `CCSP_MODEL=` / `ocsp model <名前>` の 2 つ | `spark-common.zsh` の `_spark_served_name` と各クライアントの `case` ガード | dotfiles | `ccsp` / `ocsp` |
| `lan` / `ts` | 接続先を強制する選択語。省略時は `/health` のプローブで決まる。短縮名とは順不同で並べられるが、**予約語 (`status` / `model` / `off`) とは併用できない** (予約語は第 1 引数でしか効かず、`ocsp lan status` の `status` はクライアント本体の引数に回る) | `spark-common.zsh` の `_spark_lan_url` / `_spark_ts_url` と各クライアントの引数解釈 | dotfiles | `ccsp` / `ocsp` |
| 配信前検査 | クライアントが起動前に `/v1/models` を引いて、要求されたモデルが配信されているかを確かめる段。`ccsp` は `--settings` 注入の前、`ocsp` は接続先の決定後に行う | `zsh/functions/claude-deepseek.zsh` / `zsh/functions/opencode-spark.zsh` | — | `ccsp` / `ocsp` |
| `--` (解除語) | 解釈の打ち切り語。`ccsp` は `lan` / `ts` / 短縮名の認識領域 (`while` ループ) に出た `--` をどこでも消費し、`ocsp` は先頭出た 1 個だけ消費する (短縮名のうしろに置いた `--` は opencode に素で渡る非対称)。いずれも以降を `claude` / `opencode` にそのまま渡す。予約語 (`ccsp` の `off` / `status` / `-h`、`ocsp` の `model` / `status` / `help`) や `ocsp` のサブコマンド検知を迂回できる。`--` 自体はクライアント本体に渡さない (渡すと option 解析の終端として後続の語を別枠に取り扱うため)。`ccsp --` は配信前検査と `--settings` 注入を通過するが、`ocsp --` は接続先の上書きも配信前検査も `--model` 注入も通らない (素の `opencode` と同じになる) | `claude-deepseek.zsh` と `opencode-spark.zsh` の引数解釈 | dotfiles | `ccsp` / `ocsp` |
| `settings.spark.json` | Claude Code 側の設定の土台。**モデル名・コンテキスト上限・reasoning effort は持たない**ので、モデルを増やしても変更点は無い | `agents/bindings/claude/settings.spark.json` | dotfiles | `ccsp` (生成の入力) |
| `settings.deepseek.json` | `ccds` が `--settings` で渡す DeepSeek 本家 API の設定。**主なキーは接続先 (`env.ANTHROPIC_BASE_URL`)・モデル名 5 キー・`CLAUDE_CODE_EFFORT_LEVEL` (静的な `max`)・`fallbackModel` (既定モデルが使えないときの退避)**。`env` の残り 2 キーと `enabledPlugins` は `settings.spark.json` と共通で、**`ccsp` と違い起動ごとの生成をしない** (配信名に追従する必要が無いため) | `agents/bindings/claude/settings.deepseek.json` | dotfiles | `ccds` |
| `CLAUDE_CODE_EFFORT_LEVEL` | Claude Code の推論の深さ。**`ccsp` が配信名から決めて起動のたびに注入する** (`qwen3.8-flash-next` → `xhigh` / それ以外 → `high`)。受け付ける値は配信中のモデルが決める (Qwen 配信中に `ccsp` から渡せるのは `low` / `medium` / `xhigh` の 3 つ。`none` は `/v1/messages` のスキーマが弾く → 「reasoning effort の語彙」。DeepSeek 系は未確認 → 確かめ方は「依拠する外部事実」の reasoning effort の行) | `zsh/functions/claude-deepseek.zsh` の `_ccsp_effort` | `ccsp` / `ccds` (`settings.deepseek.json` の静的な `max` を `--settings` で渡す) | `claude` 本体 (`/v1/messages` の `output_config.effort` として送る) |
| `CCSP_EFFORT` | `_ccsp_effort` の決定を上書きするシェル変数。**未設定が既定** (Qwen 配信中に入れてよいのは `low` / `medium` / `xhigh`)。語彙に無い値を入れると最初のリクエストが 400 で落ちる | `zsh/functions/claude-deepseek.zsh` | 人 | `ccsp` |
| `reasoningEffort` | `ocsp` 側の同じもの。`opencode.json` の `provider.spark.models.<配信名>.options` が**モデルごとに静的に持つ** (`qwen3.8-flash-next` = `xhigh` / `deepseek-v4-flash-vision-exp` = `high`)。省略するとクライアントは送らず、モデルのテンプレート既定が効く | `agents/bindings/opencode/opencode.json` | dotfiles | `opencode` 本体 (`/v1/chat/completions` の `reasoning_effort` として送る) |
| `~/.cache/ccsp/settings.json` | `ccsp` が起動のたびに `settings.spark.json` へモデル名 5 キー (`ANTHROPIC_MODEL` と `ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU,FABLE}_MODEL`)・`CLAUDE_CODE_MAX_CONTEXT_TOKENS`・`CLAUDE_CODE_EFFORT_LEVEL`・`fallbackModel` を注入して書き出す実ファイル | Mac の `~/.cache/ccsp/settings.json` (`XDG_CACHE_HOME` があればその下) | `ccsp` | `claude` 本体 (`--settings` で渡される) |
| `opencode.json` | OpenCode の `provider.spark` (接続先・モデル宣言・モデルごとの `reasoningEffort`)。**キーは持たない。** 認証を戻すときだけ `options.apiKey` を足す (値は `{file:…}` / `{env:…}` で外部へ逃がす)。トップレベルの `permission` は OpenCode のツール実行の承認方針で、`allow` は全ツール自動承認を意味する。dotfiles 管理。`~/.config/opencode/` の他のファイル (`node_modules` / `package.json` / `package-lock.json` / `.gitignore` など) は opencode 自身のもの。**`skills/` / `agents/` / `AGENTS.md` は `nix/modules/home/harness.nix` の生成物** | `agents/bindings/opencode/opencode.json` | dotfiles (`nix/modules/home/opencode.nix` が symlink) | `opencode` 本体 / `ocsp` |
| `tui.json` | OpenCode の TUI 設定 (keybinds / theme) | `agents/bindings/opencode/tui.json` | dotfiles (`nix/modules/home/opencode.nix` が symlink) | `opencode` 本体 |
| `OPENCODE_CONFIG_CONTENT` | OpenCode がインライン JSON として読む環境変数。既存の設定に `options` の中まで再帰的にディープマージされる。`ocsp` はこれで `baseURL` の 1 キーだけを起動ごとに差し替える (前置代入なのでシェルには残らない) | `_ocsp_config_override` (中身) と `ocsp` の起動 2 か所 (変数名)。いずれも `zsh/functions/opencode-spark.zsh` | `ocsp` | `opencode` 本体 |
| `_ocsp_resolve` | `opencode.json` の値に書いた `{file:~/…}` / `{env:…}` を解くヘルパー。認証を戻したときの `apiKey` を平文で置かずに済ませる (opencode 本体も同じ記法を解くので、`ocsp` の配信前検査と本体の双方に同じ値が届く) | `zsh/functions/opencode-spark.zsh` | dotfiles | `ocsp` |
| `/tmp/spark.key` | vLLM の Bearer トークンを平文で置いた作業ファイル。**head にだけ要る。`bench.py` 専用で、無認証の現在は中身が使われない。再起動で消える** | head の `/tmp/spark.key` | 人 (1Password から書き出す) | `bench.py` |
| `drs` | dotfiles の Nix 設定を Mac に適用する zsh alias | `nix/modules/home/zsh.nix` | dotfiles | 人 |
| `.env.dspark` | DeepSeek 系レシピの設定を集約した 1 枚。git 管理外 (`.gitignore` 済み) | head の `~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark/` | 人 (`.env.dspark.example` から複製) | 起動・停止・検証スクリプト |
| `PROJECT_NAME` | `docker compose` のプロジェクト名。コンテナ名 `deepseek-v4-flash-vllm-dspark-1` の接頭辞になる | 起動スクリプトの既定値 (`.env.dspark` のキーではない) | 起動スクリプト | `docker compose` |
| Qwen レシピ | Qwen3.8-Flash-Next を TP=2 で配信する別系統のレシピ。DeepSeek 系とは別リポジトリ・別イメージ・別スクリプト名 | head の `~/Qwen3.8-Flash-Next-Dual-DGX-Sparks/` | 上流 (`git clone`) | 人 |
| `stop` / `start` | 本書で使う DeepSeek 系スクリプト (`stop-deepseek-v4-flash-dspark.sh` / `start-deepseek-v4-flash-dspark.sh`) の略記。**Qwen 系の `stop.sh` / `start.sh` とは別物** | 「起動と停止」 | 上流 | 人 |
| `.env` | Qwen レシピの設定 1 枚。DeepSeek 系の `.env.dspark` とは別物 | head の `~/Qwen3.8-Flash-Next-Dual-DGX-Sparks/.env` | 人 (`.env.sample` から複製) | Qwen レシピのスクリプト |
| `vllm-fn` | Qwen レシピのコンテナ名。**head と worker で同名** | Qwen レシピの `start.sh` | `start.sh` | `docker` |
| `resolve_snapshot.py` / `check-weights.sh` / `verify-weights.py` | Qwen レシピ**限定**の重み検証ツール 3 種。1 つ目はシャードの完全性だけを見る起動前の門、2 つ目は両ノードを見る入口、3 つ目は 1 ノードを HF の manifest と照合する本体 (2 つ目が各ノードで呼ぶ)。**`utility-spark-model-fetch` 同梱の `verify_shards.py` とは別実装で、配布中はスキル側、起動前はレシピ側を使う** | 「重みの検証」 | 上流 (`git clone`) | `start.sh` (1 つ目) / `check-weights.sh` (3 つ目) / 人 |
| `~/spark-bench` | 計測ハーネス一式 (主に `bench.py` / `snap.py` / `pc_probe.py` / `results/`)。**dotfiles 管理外で再作成手段が無い** | head の `~/spark-bench/` | 人 | 人 / Claude |
| `utility-spark-model-fetch` | 新しい重みを head で 1 回落として worker へ rsync するスキル。`scripts/verify_shards.py` を同梱する (head 上の同名ファイルは配布済みコピーで、正本はこちら) | `agents/skills/utility-spark-model-fetch/SKILL.md` | dotfiles | Claude |
| sparkDash | 監視・SSH 操作・Wake-on-LAN を持つ Web UI。**認証が無い** | head の `~/sparkDash/` | 上流 (`git clone`) | 人 (ブラウザ) |
| `workerLabel` | sparkDash が worker 行に表示するモデル名。**手書きの静的文字列で、実機を見ていない** | head の `~/sparkDash/config/sparks.json` | 人 | sparkDash の UI |
| `docker-compose.override.yml` | sparkDash のポーリング間隔などの上書き。未追跡 | head の `~/sparkDash/` | 人 | `docker compose` |
| `security-guidance` | Claude Code の公式プラグイン。Stop hook でレビュー用モデルを呼ぶ。`enabledPlugins` の完全キーは `security-guidance@claude-plugins-official` | `~/.claude/plugins/cache/claude-plugins-official/security-guidance/` | プラグイン marketplace | `settings.*.json` の `enabledPlugins` |
| 上流 | レシピの配布元。DeepSeek 系は [MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark](https://github.com/MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark)、Qwen 系は [MiaAI-Lab/Qwen3.8-Flash-Next-Dual-DGX-Sparks](https://github.com/MiaAI-Lab/Qwen3.8-Flash-Next-Dual-DGX-Sparks) | — | — | — |

## ハードウェアと OS

2 台とも同一構成である。

| 項目 | 値 |
| --- | --- |
| GPU | NVIDIA GB10 (CPU と共有する統合メモリ 128 GB。カタログ値で、`/proc/meminfo` は 121.7 GiB を返す) |
| OS | Ubuntu 24.04.4 LTS / aarch64 |
| カーネル | `6.17.0-1032-nvidia` |
| ドライバ | `580.173.02` |
| ディスク | 3.7 TB (使用 512 GB / 空き 3.0 TB。重み 3 モデル分を置いた状態。両ノードとも同じ) |

## 接続する

自宅 LAN では SSH エイリアスが使える。

```bash
ssh spark-head
ssh spark-worker
```

`~/.ssh/config` は **dotfiles 管理外の実ファイル**なので、別マシンでは次を自分で書く。鍵 `~/.ssh/spark-head` / `~/.ssh/spark-worker` も既存機からコピーするか、新規生成して `ssh-copy-id` で登録する。

```text
Host spark-head
	User skanehira
	Hostname spark-head.local
	IdentityFile ~/.ssh/spark-head
	ServerAliveInterval 60
	ServerAliveCountMax 60
	TCPKeepAlive yes

Host spark-worker
	User skanehira
	Hostname spark-worker.local
	IdentityFile ~/.ssh/spark-worker
	ServerAliveInterval 60
	ServerAliveCountMax 60
	TCPKeepAlive yes

Host spark-head-ts
	User skanehira
	Hostname spark-head
	IdentityFile ~/.ssh/spark-head
```

**`Host spark-head` は `Hostname spark-head.local` に解決されるので、`ssh skanehira@spark-head` と書いても LAN の mDNS 名に化ける。** 出先で Tailscale の MagicDNS 名を使いたいときは上の `spark-head-ts` を経由する。HTTP 側 (`http://spark-head:8888` / `ccsp ts`) は ssh_config を通らないのでこの影響を受けない。

**新しいマシンでは `known_hosts` の登録が要る。** ホスト鍵の受理には TTY での対話が必要で、Claude の非対話セッションからは `Host key verification failed` で落ちる。ユーザーに次を依頼する (**`known_hosts` は Claude が書き換えない**)。

```bash
ssh-keyscan spark-head.local spark-worker.local spark-head >> ~/.ssh/known_hosts
```

### 出先 (Tailscale) からのコマンドの読み替え

**本書のコマンドはすべて自宅 LAN 前提で書いてある。** 出先では次の 2 つを読み替える。tailnet (Tailscale ネットワーク) に head しか居ないので、worker には head 経由でしか届かない。

| LAN での書き方 | 出先での書き方 |
| --- | --- |
| `ssh spark-head` | `ssh spark-head-ts` |
| `http://spark-head.local:8888` | `http://spark-head:8888` |

**手で読み替えるのは `ssh` と手打ちの `curl` だけである。** HTTP 側の接続先は 2 つのクライアントが自分で選ぶ (`/health` をプローブして LAN → Tailscale の順に決める。実装は `spark-common.zsh` の `_spark_base_url` で、`ccsp` と `ocsp` が共有する)。`opencode.json` の `baseURL` に書いてある LAN 側の値が効くのは、`ocsp` を通さず素の `opencode` を打ったときだけである。

**`ssh spark-head-ts` を使う前に `~/.ssh/config` に 3 ブロック目があるか確かめる。** この Mac には 1・2 ブロック目しか無く、`ssh -G spark-head-ts` が `hostname spark-head-ts` を返す (2026-09-09 実測)。無ければ「接続する」節の雛形の 3 ブロック目を追記する。

### worker に入る

`known_hosts` に `spark-worker.local` の鍵があれば Mac から直接入れる。無いマシン (および鍵を足せない場面) では head の中から入る。head の `known_hosts` には RoCE 側アドレスの鍵が入っている。

```bash
ssh -n spark-head 'W=$(grep -E "^WORKER_HOST=" ~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark/.env.dspark | cut -d= -f2); ssh -n -o BatchMode=yes "$W" "<worker で実行するコマンド>"'
```

外側がシングルクォートなので `$W` は head 側で展開される。`WORKER_HOST` の値はクォートされていないので `cut -d= -f2` で足りる。

**入れ子の `ssh` には `-n` を付ける。** 付けずに外側をヒアドキュメントや `bash -s` で流し込むと、内側の ssh が残りのスクリプトを標準入力ごと飲み込み、以降のコマンドが実行されないまま正常終了する (出力が途中で切れていたらこれを疑う)。

### ネットワーク

| 用途 | netdev 名 | RDMA デバイス名 | 割り当て | MTU (バイト) |
| --- | --- | --- | --- | --- |
| LAN (WiFi) | `wlP9s9` | — | 両ノード。mDNS 名 `spark-head.local` / `spark-worker.local` | 1500 |
| RoCE 1 本目 | `enp1s0f1np1` | `rocep1s0f1` | 専用の /24。head が `.1`、worker が `.2` | 9000 |
| RoCE 2 本目 | `enP2p1s0f1np1` | `roceP2p1s0f1` | 別の /24。head が `.1`、worker が `.2` | 9000 |
| Tailscale | `tailscale0` | — | head のみ。MagicDNS 名 `spark-head` | 1280 |

**具体的な IP アドレスは本書に書かない。** このリポジトリは公開されており、アドレスを認証の無いサービス (sparkDash) の説明と並べる利点が無いためである。必要になったら「依拠する外部事実」節の引き方で調べる。日常の操作は名前 (`spark-head` / `spark-worker`) と `.env.dspark` の `WORKER_HOST` で足りる。

**RoCE が 2 本あるのは GB10 の仕様である。** QSFP ポートが 2 つの仮想 NIC (各 PCIe Gen5 x4) として見えるため、`.env.dspark` の `NCCL_IB_HCA` に `rocep1s0f1,roceP2p1s0f1` と両方を並べる。**2 本は別サブネットに置き、MTU 9000 にする。** 片方に IP が無い、または同一サブネットに置くと vLLM が `no usable RoCEv2 GID` で起動に失敗する。IP と MTU は NetworkManager の接続 `roce` / `roce2` (autoconnect 有効) で永続化してあり、再起動後も残る。

LAN は 2.4 GHz の WiFi で、実効 8 MB/s しか出ない。**HuggingFace からの重みのダウンロードはここが律速になる** (`du -sh` で 156〜158 GiB のモデルに約 5.5 時間)。ノード間のコピーは RoCE を使えば 285〜605 MB/s 出る。

## 動いているもの

| サービス | 自宅 LAN | 出先 (Tailscale) | 認証 |
| --- | --- | --- | --- |
| vLLM (DeepSeek 系 / Qwen 系のどちらでも) | `http://spark-head.local:8888` | `http://spark-head:8888` | **なし** |
| sparkDash | `http://spark-head.local:5555` | `http://spark-head:5555` | **なし** |

**8888 はどちらの系統でも無認証である。** Qwen 系はレシピが `--api-key` を渡さない。DeepSeek 系は `.env.dspark` の `VLLM_API_KEY` を `docker-compose.dspark.yml` がコンテナの環境変数に渡すしくみだが、**`VLLM_API_KEY` を空にしてある**ので素の無認証で上がる (2026-09-06 に確認)。Qwen 配信中の 8888 は、ヘッダ無しでも出まかせの Bearer でも `/v1/models` が 200 を返すことを実測した (同じ日に存在しないパスが 404 を返すことも確かめてある)。`/health` は 2 つのクライアントの到達判定 (`ccsp` / `ocsp` の起動時と `status`) が、`/metrics` は sparkDash と `~/spark-bench/snap.py` がポーリングして消費する。**接続先を強制した起動 (`ccsp lan` / `ocsp ts`) はプローブを飛ばして `/v1/models` に直行する。`status` は接続先の選択とは無関係に両経路の `/health` を叩く。**

**したがってポート 8888 を信頼できないネットワークへ出さない。** sparkDash のポート 5555 と同じ扱いにする。

sparkDash は head の `~/sparkDash` に clone した [MiaAI-Lab/sparkDash](https://github.com/MiaAI-Lab/sparkDash) である。同梱の `docker-compose.yml` は編集せず、上書きは未追跡の `docker-compose.override.yml` に置く (`git pull` との衝突を避けるため)。反映・停止・更新は `~/sparkDash` で `docker compose up -d` / `down` / `pull` を打つ。**認証が無く tailnet の全端末から SSH 操作と Wake-on-LAN が可能なので、ポート 5555 を信頼できないネットワークへ出さない。**

### API キーの流れ

**現在はどのクライアントも API キーを使わない。** `ccsp` と `ocsp` はいずれもキーを持たず、起動前に打つ `/v1/models` の照会も Bearer が空なら Authorization ヘッダ自体を送らない。**1Password が要るのは `ccds` (DeepSeek 本家 API) だけである。**

**`ccsp` には承知のうえの副作用がある。** `ANTHROPIC_AUTH_TOKEN` が空だと、Claude Code は自分が持っている**本物の Anthropic 認証情報**を `Authorization: Bearer` で `ANTHROPIC_BASE_URL` へ送る。宛先は自宅 LAN の Spark で経路は平文 HTTP なので、自宅に閉じている限り許容する方針である。**信頼できないネットワーク越しに使うときはダミー値を export してから打つ。** `ocsp` にはこの経路が無い。

**DeepSeek 系を認証ありに戻すときは、サーバとクライアントの両方を直す。** 直し忘れた側で症状が変わる。**サーバだけ直すと両クライアントが `/v1/models` の 401 で起動前に止まる** (騒がしいので気づける)。**クライアントだけ直しても無認証のサーバは Bearer を無視して 200 を返すので、認証が効いていると誤認したまま運用が続く** (静かなので気づけない)。

1. サーバ側 — `.env.dspark` の `VLLM_API_KEY` に値を入れて `stop` → `start`
2. クライアント側 — `ccsp` の前に `ANTHROPIC_AUTH_TOKEN` を export し、`opencode.json` の `options` に `apiKey` を足す
3. **反映経路が 2 つで違う。** `ANTHROPIC_AUTH_TOKEN` はそのシェルで即時、`opencode.json` は `mkOutOfStoreSymlink` が効いている世代なら編集した瞬間から (2026-09-06 時点は効いている)。**まだ store コピーを指している世代では `drs` を当てるまで反映されない。判定は `readlink -f` で行う** (→「OpenCode (`ocsp`)」)
4. **効いたことを確認する** — `curl -s -o /dev/null -w '%{http_code}\n' http://spark-head.local:8888/v1/models` が **401** を返すこと。200 のままならサーバ側が直っていない (これは「依拠する外部事実」の 200 判定の陽性対照でもある)

**`bench.py` は無認証でもキー文字列を要求する。** `--key-file` か環境変数 `SPARK_KEY` のどちらも無いと起動時に exit する実装で、渡した値はそのまま `Authorization: Bearer` に載る。無認証のサーバはそれを無視するので、いまは中身が何でも通る。正本は 1Password の `op://Personal/DGX Spark vLLM API Key/credential` である。

```bash
op read 'op://Personal/DGX Spark vLLM API Key/credential' | ssh spark-head 'cat > /tmp/spark.key && chmod 600 /tmp/spark.key'
```

- **`/tmp` は再起動で消える。** 2026-09-06 時点では存在しない。`bench.py` を打つときに書き直す
- **`.env.dspark` の控えを作ったら使い終わりに消す。** `.gitignore` が拾うのは `.env.dspark` そのものだけなので、`.env.dspark.bak` のような名前は追跡対象に入りうる。キー行ごと公開リポジトリの clone にステージされる

### サービングの構成 (DeepSeek 系)

**この節は DeepSeek 系を配信しているときの話である。** Qwen 系の構成は「Qwen3.8-Flash-Next」にある。レシピ名は DSpark だが、載せているチェックポイントは Vision-Exp である。値の出所はすべて `.env.dspark` (「KV キャッシュ」と「レシピの commit」の 2 行を除く)。

| 項目 | 値 |
| --- | --- |
| チェックポイント (`DSPARK_MODEL_OFFICIAL` / `DSPARK_REVISION`) | `deepseek-ai/DeepSeek-V4-Flash-Vision-Exp` @ `86f746b36186f0e567729a5c06a8c918caba82a9` |
| API 上のモデル名 (`SERVED_MODEL_NAME`) | `deepseek-v4-flash-vision-exp` |
| コンテキスト上限 (`MAX_MODEL_LEN`) | サーバ 1,048,576 トークン (ネイティブ。YaRN 不要) / Claude Code からは 1,015,808 (`ccsp` が出力用の余白 32,768 を引く) |
| 同時リクエスト上限 (`MAX_NUM_SEQS`) | 6 リクエスト。超過分はエラーにならずキューで待つ |
| 投機デコード (`MTP_NUM_TOKENS`) | DSpark、draft 6 トークン |
| メモリ確保率 (`GPU_MEMORY_UTILIZATION_TEXT`) | 0.835 (意味は「メモリの使われ方」) |
| KV キャッシュ | `nvfp4_ds_mla` (`.env.dspark` にキーは無く、`docker-compose.dspark.yml` が `--kv-cache-dtype` に直書きしている) |
| 既定の reasoning (`DEFAULT_THINKING`) | `low` (取りうる値: `off` / `low` / `high` / `max`。リクエスト単位の指定が優先する)。**この既定が効くのは effort を送らないクライアントだけである** — 2 つのクライアントは常に明示的に送り、`bench.py` も `chat_template_kwargs` で明示する。**リクエスト単位で受ける値の一覧は未確認** (確認コマンドは「依拠する外部事実」。DeepSeek 系を配信中でないと打てない)。**2 つのクライアントはこの系統に `high` を送る** (`_ccsp_effort` の既定と `opencode.json` の `reasoningEffort`)。この値もこの表の語彙に合わせただけで実測していないので、DeepSeek 系に戻したら最初の 1 回で 400 が出ないことを確かめる |
| コンテナイメージ | `ghcr.io/anemll/dspark-vllm-gx10:0.1.1@sha256:a83948492cf13df455170fb42885f5ef4db54fefe0feff0f841ecbff464ac9d8` (DSpark ランタイムの配布元 Anemll) |
| レシピの commit | `f5665e8`。上流 `main` はここから先行している (件数と中身は「依拠する外部事実」の確認コマンドで見る。速い変化があるので本書に数を書かない) |

重みは両ノードの `~/.cache/huggingface/hub/` にある。worker は NFS ではなくローカルコピーを持つ。値は `du -sh` の実測 (2026-09-06)。

| チェックポイント | head | worker | 備考 |
| --- | --- | --- | --- |
| Vision-Exp | 158 GiB | 157 GiB | DeepSeek 系 |
| Qwen3.8-Flash-Next | 124 GiB | 124 GiB | Qwen 系 (「Qwen3.8-Flash-Next」節) |
| DeepSeek-V4-Flash-0731 | 156 GiB | 156 GiB | **使わない。** 消していないだけで、起動手順は本書に無い |

**配信の候補は Vision-Exp と Qwen3.8-Flash-Next の 2 つで、そのどちらか 1 つだけが動く。** 2 系統はポート 8888 と GPU を共有するので同時に起動できない。0731 の重みは置いてあるだけで配信候補ではない (→「触らないもの」)。

### メモリの使われ方

GB10 は CPU と GPU が同じ物理メモリを共有する統合メモリ構成である。**`GPU_MEMORY_UTILIZATION_TEXT=0.835` は通常の GPU なら VRAM の 83.5% を指すが、ここではシステムメモリ全体の 83.5% を意味する。** 起動直後から 100 GiB 超が vLLM に確保されて `free` の残りが数 GiB になる (DeepSeek 系で 6〜8 GiB、Qwen 系の head は 1.3〜5.7 GiB) が、これは設定どおりの先取りであって、リークでも不足でもない。

**値は配信中の系統で変わる。** 左が DeepSeek 系 (Vision-Exp) 配信時、右が Qwen 系配信時である (DeepSeek 系の列は 2026-09-06 の実測、Qwen 系の列は 2026-09-09 の再起動後に無負荷で採った値。`MemAvailable` の Qwen 列だけは 2026-09-06 の高負荷時からの幅で書いてある)。

| 項目 | DeepSeek 系 head / worker | Qwen 系 head / worker |
| --- | --- | --- |
| 物理メモリ合計 | 121.7 / 121.7 GiB | 121.7 / 121.7 GiB |
| vLLM の確保 | 101.4 / 101.4 GiB | 100.7 / 100.8 GiB |
| `MemAvailable` | 6.1 / 7.5 GiB | 1.3〜5.7 / 5.6〜10.1 GiB |
| swap 使用 | 3.9 / 2.9 GiB | 5.0 / 4.1 GiB |

どちらの系統も期待値 121.7 × 0.835 = 101.6 GiB の近傍に収まる (DeepSeek 系 101.4 GiB / Qwen 系 100.7 GiB)。head の残りが worker より少ないのは、head だけがデスクトップセッション・sparkDash・tailscaled を抱えているためである。**Qwen 配信中の head の空きは負荷と稼働時間で 1.3〜5.7 GiB を動く** (2026-09-06 の高負荷時 1.3〜1.7 GiB / 2026-09-09 の再起動直後 5.7 GiB)。**これも先取りであって不足ではない。メモリを空けたくなったらプロセスを探す前にこの値を疑う。**

## 起動と停止

**この節は DeepSeek 系の話である。** Qwen 系の起動・停止は「Qwen3.8-Flash-Next」節の「切り替えと起動」にある。

head の `~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark` が上流レシピの clone である。**head で起動すると `.env.dspark` を worker へ SSH で配り直して両ランクを立ち上げるので、worker で直接コマンドを打つ必要はない。** head から worker へは head 上で生成して worker に登録済みの鍵 `~/.ssh/id_ed25519` を使い、`.env.dspark` の `WORKER_HOST` (RoCE 側のアドレス) に入る。

```bash
ssh spark-head
cd ~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark
./validate-dspark-config.sh            # 起動せずに解決値だけ確認する
./start-deepseek-v4-flash-dspark.sh    # 両ランク起動。約 6 分 (実測 390 秒)
./smoke-deepseek-v4-flash-dspark.sh    # 疎通確認
./status-deepseek-v4-flash-dspark.sh   # 両ランクのコンテナ状態
./logs-deepseek-v4-flash-dspark.sh     # head 側のログを追う
./stop-deepseek-v4-flash-dspark.sh     # 両ランク停止
```

**以下この節の `stop` / `start` は DeepSeek 系スクリプトの略記である** (Qwen 系は `stop.sh` / `start.sh` で別物)。**設定を変えたら `docker compose restart` を使わず、`stop` → `start` で作り直す。** 起動時にコンテナ内の vLLM へ多数のパッチを当てる構成なので、restart では古いバイト列が残る。

正常稼働の判定は 2 段で行う。

1. `curl -fs http://spark-head.local:8888/health` — exit 0 なら API は生きている
2. `./smoke-deepseek-v4-flash-dspark.sh` — 実際に生成が通る。`set -euo pipefail` で書かれており失敗時は exit 1 または 2 を返すので、**exit 0 で合格**

`.env.dspark` の既定値は `.env.dspark.example` にある。サイト固有の値 (IP・NCCL のデバイス名・API キー) を除くと、上流の配布既定から変更しているのは次の 3 つである。

| キー | 値の意味 | 既定 | 現在 | 採用根拠 | 効果 |
| --- | --- | --- | --- | --- | --- |
| `DSPARK_MAX_INFLIGHT_PREFILLS` | 同時に走らせる prefill の件数 | 1 | 2 | 上流の A/B (`docs/CLAUDE/ab-results-2026-09-03.md`) | **上流計測値**: 4 並列時の TTFT のばらつきが 11.9 秒 → 7.7 秒、単一利用時の初動が 4.9 秒 → 7.2 秒に悪化、集約スループットは有意差なし。自環境では未計測 |
| `DSPARK_ENABLE_SP_INDEXER` | 0 = 無効 / 1 = 有効 | 0 | 1 | 上流の最終構成に追従 | 自環境では未計測 |
| `DSPARK_ENABLE_DEEPGEMM_SM121_ALIAS` | 0 = 無効 / 1 = 有効 | 0 | 1 | 上流の最終構成に追従 | 自環境では未計測 |

**この差分を自分で取り直すときは正規表現に注意する。** `grep -E '^[A-Z_]+='` はキー名に数字を含む `DSPARK_ENABLE_DEEPGEMM_SM121_ALIAS` を落とす (90 行中 75 行しか拾わない)。`^[A-Za-z0-9_]+=` を使う。同様に、キー行を伏せるための `grep -vi token` は `MTP_NUM_TOKENS` も巻き込む。

## モデルの追加と切り替え

**同じレシピの中でモデルを 1 つ足すときに触るのは次の 6 か所である** (Qwen のように別系統のレシピごと足す場合は、これに加えて clone・`.env`・イメージ取得が要る)。

1. **重みを両ノードに配る** — `utility-spark-model-fetch` スキル (下記)
2. **短縮名を足す** — **表 1 か所では足りず、動作に効くのは計 5 か所。** `spark-common.zsh` の `_spark_served_name` の展開表に 1 か所、2 クライアントの引数解釈ループ (接続先の `lan` / `ts` と並んで `qwen|vision)` を消費する `case`) に 2 か所、2 クライアントの `-h` の usage に 2 か所。**`case` ガードに足さないと、その語は短縮名として認識されずクライアント本体の引数に回る** (`claude` へのプロンプトとして無言で渡ってしまう)。加えて**表示だけの列挙が 2 か所**ある (`claude-deepseek.zsh` 冒頭のコメントと `ocsp` のモデル名不足のエラー文)。動作は変わらないが、直さないと案内が古いまま残る
3. **reasoning effort をモデルごとに決める** — `claude-deepseek.zsh` の `_ccsp_effort` の `case` と、次項で足す `opencode.json` の宣言の `options.reasoningEffort` の 2 か所。**受け付ける語彙はモデルのチャットテンプレートが決めるので、他のモデルの値を流用しない** (確かめ方は「依拠する外部事実」の reasoning effort の行)。`_ccsp_effort` に足さなければ既定の `high` が送られ、それを受けないモデルでは最初のリクエストが 400 で落ちる
4. **`agents/bindings/opencode/opencode.json` の `provider.spark.models` に宣言を足す** — 宣言の無いモデルは OpenCode が拒否する
5. **`drs` と新しいシェル** — zsh 関数は Nix store 経由なので、これを踏まないと古い定義が動き続ける
6. **sparkDash の `workerLabel`** — 手書きの静的文字列なので配信を切り替えたら直す (→「sparkDash の `workerLabel` を直す」)

`agents/bindings/claude/settings.spark.json` は**触らない**。モデル名・コンテキスト上限・reasoning effort のいずれも持たず、`ccsp` が配信名から決めて注入するので、モデルが増えても変更点は無い。

**新しい open-weight を入れるときは `utility-spark-model-fetch` スキルを使う。** 素直にレシピ同梱の `prepare-dspark-model-cache.sh` を使うと worker でも HuggingFace から再ダウンロードして同じ重みを 2 回落とすことになる。head で 1 回落として RoCE 経由で rsync すれば転送は 5〜8 分で済む。所有権の修正・シャードの検証・監視コマンドの落とし穴はスキル側に書いてある。

### sparkDash の `workerLabel` を直す

配信モデルを切り替えたら必ず打つ。**実機を見ずに表示するだけの手書き文字列なので、直さないと worker 行が古いモデル名のままになる。** ファイルは root 所有なのでコンテナ経由で書き、読み戻して確認する。`~/sparkDash/config` は `/app/config` に bind mount されているので、編集はコンテナを作り直しても残る。

下のコマンドの `qwen3.8-flash-next` を、配信中の `SERVED_MODEL_NAME` に差し替えて使う。

```bash
ssh -n spark-head "docker exec sparkDash node -e \"const f='/app/config/sparks.json',fs=require('fs');const j=JSON.parse(fs.readFileSync(f));j.sparks.find(s=>s.role==='worker').workerLabel='qwen3.8-flash-next';fs.writeFileSync(f,JSON.stringify(j,null,2))\""
ssh -n spark-head "docker exec sparkDash node -e \"console.log(JSON.parse(require('fs').readFileSync('/app/config/sparks.json')).sparks.map(s=>s.role+':'+s.workerLabel).join(' '))\""
```

クライアント側 (`ccsp` / `ocsp`) の設定変更は要らない。**いずれも `/v1/models` を見て配信中のモデルを採る。** ただし効くのは次に起動する分からで、稼働中のセッションは起動時のモデル名を送り続けるので起動し直す (「既知の制約」5 の退避手順)。

### Qwen3.8-Flash-Next (別系統のレシピ)

**DeepSeek 系とは別リポジトリ・別イメージ・別スクリプト名である。** 混同すると停止スクリプトが効かない。2026-09-06 に配置・起動・`ccsp` / `ocsp` からの疎通まで確認した (`ocsp` は `drs` 未適用のため検証用の `HOME` に設定を置いて確認した)。2026-09-09 の更新後に起動の 3 段判定と reasoning effort の語彙を取り直しており、クライアント 2 つからの疎通はそのとき再確認していない。

**この構成には認証が無い。** 下の「認証」を先に読む。

値の出所はレシピの `.env` である (「レシピ」「重み」「画像入力」「既定の reasoning」「コンテナ名」「`.env` に**書いていない**上流キー」の 6 行と、「コンテナイメージ」の Id・サイズを除く。最後の 1 行だけは定義上 `.env` に無い値なので、出所は `.env.sample` と上流の CHANGELOG である)。

| 項目 | 値 |
| --- | --- |
| レシピ | head の `~/Qwen3.8-Flash-Next-Dual-DGX-Sparks` @ `0b62e12` |
| チェックポイント (`MODEL_ID`) | `nvidia/Qwen3.8-Flash-Next-NVFP4`。**revision を固定するキーは `.env` に無い**。`files/resolve_snapshot.py` が `refs/main` の指す snapshot を優先し、`model.safetensors.index.json` が名指すシャードが全て揃っていることを起動前に検査する (`refs/main` が不完全なら他の完全な snapshot を探し、それも無ければ `start.sh` が止まる)。当方の `refs/main` は `fab0aecb760cec45227f6656abcaafa11abca87a` で、snapshot もこれ 1 つだけ (検証手段と revision が動く条件は → 「重みの検証」) |
| 重み | 124 GiB / safetensors 11 本 (`du -sh` の実測)。レシピの `.env` のコメントの 133G は 10 進 GB での表記で、実測と食い違わない (HF の manifest は 132.7 GB、vLLM の起動ログは 123.57 GiB と出る)。**両ノードに配置済み** |
| API 上のモデル名 (`SERVED_MODEL_NAME`) | `qwen3.8-flash-next` |
| 画像入力 | 使える (2026-09-06 に実測。8x8 の赤い PNG を data URL で渡して「赤」と回答) |
| コンテキスト上限 (`MAX_MODEL_LEN`) | サーバ 524,288 トークン / Claude Code からは 491,520 (`ccsp` が出力用の余白 32,768 を引く)。**ネイティブは 262,144 で、`YARN_ENABLE=true` + `YARN_FACTOR=2.0` で伸ばしている** |
| 同時リクエスト上限 (`MAX_NUM_SEQS`) | 8 リクエスト |
| 投機デコード (`MTP_NUM_SPECULATIVE_TOKENS`) | MTP、draft 3 トークン |
| KV キャッシュ (`KV_CACHE_DTYPE`) | `fp8` |
| メモリ確保率 (`GPU_MEMORY_UTILIZATION`) | 0.835 (DeepSeek 系と同値だがキー名が違う。意味は「メモリの使われ方」) |
| 既定の reasoning | `xhigh` (`.env` に該当キーが無く、チャットテンプレートの既定が効く)。**両クライアントから使えるのは `low` / `medium` / `xhigh` の 3 つ。`high` と `max` はどちらの経路でも 400 になる** (詳細は直下の「reasoning effort の語彙」) |
| コンテナイメージ | `vllm/vllm-openai:qwen38-flash-next` (Id `sha256:d464f3b466fa9c45ddbff8a812e80564503b6879a9fd95c1a47514f3f0df5a4a`、20.6 GB、arm64)。**両ノードに配置済み** |
| コンテナ名 | `vllm-fn` (head と worker で同名。`start.sh` が付ける) |
| 追加の vLLM 引数 (`EXTRA_VLLM_ARGS`) | 未設定 (`.env` でコメントアウトされている)。認証を付けるならここに `--api-key <値>` を書く |
| 起動前の GPU ガード (`REQUIRE_IDLE_GPU`) | `true` (上流既定のまま。取りうる値: `true` / `false`)。どちらかのノードで GPU を掴むプロセスがあれば起動を拒否する |
| 上流既定からの差分 | **値を変えた**キーが 5 つ (下の「書いていない上流キー」2 つは別勘定)。**サイト固有が 2 つ**: `IFACE` = `enp1s0f1np1` / `IB_HCA` = `=rocep1s0f1` (先頭の `=` は「完全一致で 1 デバイスだけ」を意味する上流の記法で、typo ではない)。**常用長に合わせたものが 3 つ**: `MAX_MODEL_LEN` 262144 → 524288 / `YARN_ENABLE` false → true / `YARN_FACTOR` 4.0 → 2.0 (理由は下の「YaRN」)。`HEAD_IP` / `WORKER_IP` は配布既定のまま実機と一致するので変更していない (実値は「依拠する外部事実」の確認コマンドで引く) |
| `.env` に**書いていない**上流キー | 2 つ。どちらも未設定が現行動作なので `.env` に足していない (値の出所はこの行だけ `.env.sample` と上流の CHANGELOG)。**`ABLIT`** (未設定 = 0。1 は値の切り替えではなく**別チェックポイントへの乗り換え**で、`drowzeys/keys-Qwen3.8-Flash-Next-NVFP4-dual-ablit-house-qsa-L3-47` を full snapshot で取り直す。HF 上での規約同意と `HF_TOKEN` (`.env` に書くか環境変数で渡す。この 2 キーだけは環境が `.env` に優先する) に加えて、124 GiB 級の取得と worker への配布が要る → `utility-spark-model-fetch`)。**`MAMBA_SSM_CACHE_DTYPE`** (未設定 = チェックポイントの float32。`bfloat16` にすると再帰状態の dtype が半分になる。**上流の「集約 decode スループット +8.5%」は単 Spark TP=1 での計測で、この 2 ノード TP=2 では未計測**と上流自身が書いている)。採用は `.env` に 1 行足して停止 → 起動、戻すのは行を消して同じ再起動 (13〜14 分止まる → 「既知の制約」5)。**`.env.sample` 側の既定は `ABLIT=0` / `MAMBA_SSM_CACHE_DTYPE=bfloat16` なので、`.env` を作り直すと後者が黙って有効になる** |

#### reasoning effort の語彙

**受理される値はエンドポイントで違う。** 2026-09-06 に両経路で全値を実測した (確認コマンドは「依拠する外部事実」の reasoning effort の行)。

| 値 | `/v1/messages` (`ccsp`) | `/v1/chat/completions` (`ocsp`) | 弾く層 |
| --- | --- | --- | --- |
| `low` / `medium` / `xhigh` | 200 | 200 | — |
| `none` | **400** | 200 | `/v1/messages` のスキーマ |
| `high` / `max` | 400 | 400 | チャットテンプレート |
| 指定なし | 200 (既定 `xhigh`) | 200 (既定 `xhigh`) | — |

**したがって両クライアントから使える値は `low` / `medium` / `xhigh` の 3 つである。**

- **`high` と `max` を弾くのはチャットテンプレートである。** `xhigh` / `medium` / `low` 以外で `raise_exception` する。エラー本文 `Unexpected reasoning effort high. Supported types are xhigh (default), medium, and low.` は既定値を自分で名乗る。**この層は両経路に共通する**ので、Anthropic ルータ (`/v1/messages`) も同じく 400 になる。ルータは `output_config.effort` を `reasoning_effort` に写して同じテンプレートへ渡すだけである
- **`none` が `/v1/chat/completions` でだけ通るのは、テンプレートに届く前に効果が消えるためである。** vLLM は `reasoning_effort != "none"` を `enable_thinking` に導出し、テンプレートは `enable_thinking` が偽なら effort を見ない (`reasoning_effort` 自体はテンプレートに渡るが、その分岐に入らない)。**`/v1/messages` にはこの抜け道が無い。** `AnthropicOutputConfig.effort` の Literal が `low` / `medium` / `high` / `xhigh` / `max` で `none` を含まず、スキーマ検証で先に 400 になる (本文は `Input should be 'low', 'medium', 'high', 'xhigh' or 'max'`)
- **値の実体は system への 1 文の指示である。** `xhigh` と `low` だけが文を足し、`medium` は何も足さない。長さや打ち切りを変える仕組みではない

#### 切り替えと起動

**Qwen に切り替える。**

```bash
ssh spark-head
cd ~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark && ./stop-deepseek-v4-flash-dspark.sh
cd ~/Qwen3.8-Flash-Next-Dual-DGX-Sparks && ./start.sh --launch
```

上がったら sparkDash の `workerLabel` を `qwen3.8-flash-next` に直す (→「sparkDash の `workerLabel` を直す」)。

**DeepSeek に戻す。** `workerLabel` も `deepseek-v4-flash-vision-exp` に戻す (→「sparkDash の `workerLabel` を直す」)。**戻したら effort を 1 回確かめる。** 両クライアントがこの系統に送る `high` はレシピの `DEFAULT_THINKING` の語彙に合わせただけで実測していないので、最初の起動で `Unexpected reasoning effort` が出ないことを見る (出たら `_ccsp_effort` と `opencode.json` の値を直す → 「reasoning effort の語彙」)。

```bash
ssh spark-head
cd ~/Qwen3.8-Flash-Next-Dual-DGX-Sparks && ./stop.sh
cd ~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark && ./start-deepseek-v4-flash-dspark.sh
```

**先に相手系統を停止する。** ポート 8888 を共有するうえ、`REQUIRE_IDLE_GPU=true` がどちらかのノードで GPU を掴むプロセスを見つけた時点で起動を拒否する。停止前に稼働中リクエストが 0 であることを確認する (「既知の制約」5)。**停止スクリプトを取り違えると相手系統のコンテナは消えないので、「止めたつもり」で次の起動が拒否される。**

**`--launch` を使う。** 引数なしの `./start.sh` は HuggingFace からのダウンロードと worker への rsync から始める。どちらも完了済みなので `--launch` が両方を飛ばす。**`--launch` でも head 側のシャード完全性の検査は必ず通り、欠落があればコンテナを作らずに止まる** (→「重みの検証」)。

**cold start は約 11 分である** (上流計測、2026-09-05 時点の README: NCCL 約 40 秒、重みロード 458 秒、engine init 92 秒、graph capture 約 7 秒)。DeepSeek 系の約 6 分より長い。20 分を過ぎても上がらなければ両ノードで `docker logs vllm-fn` を見る (worker は「worker に入る」節の入れ子 ssh)。

**起動の実測値。** 上流 README が載せている数字は別のチェックポイントで採ったものなので一致しない。列は 2 回の起動で、右が最新である。括弧内はそのときのレシピの commit。

| 項目 | 2026-09-06 (`c2325b2`) | 2026-09-09 (`0b62e12`) |
| --- | --- | --- |
| 重みロード (本体) | head 423 秒 / worker 463 秒 (11 シャード) | head 452 秒 (11 シャード。tqdm の経過表示 `[07:32]` から。同じログの `Loading weights took` 行は 455.41 秒。worker の内訳は未取得) |
| 重みロード (MTP ドラフタ) | head 75 秒 / worker 52 秒 | head 84 秒 (worker の内訳は未取得) |
| モデルロード合計 (`Model loading took`) | 未取得 | head 578 秒 / worker 491 秒 (各ノードが確保した 64.55 GiB を含む。本体 + ドラフタの内訳とは待機分だけずれる) |
| engine init (profile + KV 確保 + warmup) | 163 秒 | 122 秒 |
| CUDA graph capture | 16 秒 (head 0.39 GiB / worker 0.77 GiB) | 14 秒 (head 0.24 GiB / worker 0.30 GiB) |
| コンテナ起動から `/health` 200 まで | 823 秒 (13.7 分) | 794 秒 (13.2 分) |
| KV キャッシュ | head 35.35 GiB / worker 33.42 GiB、合計 3,809,995 トークン | head 35.55 GiB / worker 33.2 GiB、合計 4,214,141 トークン |
| 同時実行できる 524,288 トークンの文脈 | 7.27 本 (トークン数 ÷ 524,288 で算出) | 8.04 本 (vLLM が起動ログに出す値) |

上流 README の「約 11 分」より 2〜3 分長い。**判定にはこの実測値 (約 13〜14 分) を使う。**

**KV のバイト数はほぼ同じなのにトークン数が 10.6% 増えている** (68.77 GiB で 3,809,995 → 68.75 GiB で 4,214,141)。`.env` も vLLM の起動引数も同一 (`GPU_MEMORY_UTILIZATION` 0.835 / `MAX_MODEL_LEN` 524,288 / `MAX_NUM_SEQS` 8 / `MAX_NUM_BATCHED_TOKENS` 8,192 / `KV_CACHE_DTYPE` fp8 / MTP 3 トークン) なので、当方の設定変更によるものではない。**原因は特定していない** — 上流のパッチによる KV レイアウトの変化か、hybrid のブロック配置が起動ごとに動くだけかを切り分けていない。**プールのトークン数は固定値として扱わない。**

**起動できたかは 3 段で判定する。**

```bash
curl -fs -o /dev/null http://spark-head.local:8888/health && echo health-ok  # 1. API が生きている
curl -s http://spark-head.local:8888/v1/models                               # 2. qwen3.8-flash-next が返る
ocsp lan qwen run "1+1 は?"                                                   # 3. 実際に生成が通る (exit 0 で答えが出れば合格)
```

2 段目に Bearer が要らないのは無認証だからである (どちらの系統でもヘッダは要らない → 「API キーの流れ」)。**3 段目は `drs` 適用済みの Mac でしか通らない** (`ocsp` 関数が配られていることが要る。設定の symlink は別物で、こちらは既に dotfiles を指している)。1・2 段目に合わせて `lan` を付け、3 段が同じ経路を見るようにしてある (出先では 3 つとも Tailscale 側に読み替える)。未適用なら次で代用する。

```bash
curl -s http://spark-head.local:8888/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.8-flash-next","messages":[{"role":"user","content":"1+1 は?"}],"max_tokens":64}'
```

Qwen レシピには DeepSeek 系の `smoke-…sh` に相当するスクリプトが無いので、3 段目はクライアントから叩いて代用する。

#### レシピを更新する

上流の更新を取り込む順路である。**`.env` は追跡外なので `git pull` では消えない。**

```bash
ssh spark-head
cd ~/Qwen3.8-Flash-Next-Dual-DGX-Sparks
git fetch -q && git log --oneline HEAD..origin/main    # 先行分を読む
git pull --ff-only
diff <(grep -E '^[A-Za-z0-9_]+=' .env.sample | sort) <(grep -E '^[A-Za-z0-9_]+=' .env | sort)
```

最後の `diff` は**上流にキーが増えていないか**を見るために打つ (出力に IP を含む行があるので証跡として貼らない)。増えていたら「Qwen3.8-Flash-Next」の表の「`.env` に**書いていない**上流キー」行を更新する。そのうえで停止 → 起動する (→「切り替えと起動」)。

**更新後は次の 4 点で悪化していないことを確かめる。** 起動の 3 段判定は起動の可否しか見ないので足りない。2 と 3 は**停止する前に取っておき**、起動後の値と突き合わせる。

1. 起動の 3 段判定 (`/health` → `/v1/models` → 実際の生成)
2. `/v1/models` の `id` と `max_model_len` が更新前と一致すること。**`created` と `permission` は起動のたびに変わるので全文比較に使わない** (常に不一致になり検出器として働かない)
3. reasoning effort の語彙が変わっていないこと (→「reasoning effort の語彙」。**2 経路とも打つ**)
4. `docker inspect vllm-fn --format '{{.HostConfig.RestartPolicy.Name}}'` が `no` のままであること

**KV プールのトークン数は起動ごとに動くので不合格の根拠にしない** (→「実測値」)。

戻すときは `git checkout <旧 sha>` してから停止 → 起動する (detached HEAD になるので復帰は `git checkout main`)。重み・イメージ・`.env` のいずれも変わらないので戻せる。

#### 重みの検証

`0b62e12` のレシピは重みの検証手段を 3 つ持つ (新規に入ったのは 1 つ目と 3 つ目で、2 つ目は既存スクリプトの拡張)。**いずれも Qwen レシピ限定である** (DeepSeek 系には無い)。パスはレシピディレクトリからの相対で、実行も同ディレクトリで行う。

- `python3 files/resolve_snapshot.py <hub の repo ディレクトリ>` — `model.safetensors.index.json` が名指すシャードが揃っているかだけを見る。`refs/main` の指す snapshot が完全ならそれを、そうでなければ最も新しい完全な snapshot を、それも無ければ `refs/main` を返す。exit 0 = 完全 / 1 = 欠落あり / 2 = snapshot が無い。**`start.sh` が起動前に必ず通す門はこれで、完全でなければ起動せずに止まる**
- `./check-weights.sh` — **両ノード**を見る入口。引数なしは presence と size (124 GiB / 11 シャード) だけを数秒で見て exit 0 を返し、manifest を取りに行かない。**配信中に打てるのはここまで。** `--dry-run` は manifest を取って presence と size を照合する (hashing と worker への scp はしない)。`--verify` は worker へ検証器と manifest を scp したうえで全シャードの SHA-256 を照合するため、両ノードで 124 GiB ずつ読む。**`--verify` は停止中に打つ**
- `python3 verify-weights.py` — **1 ノード分**を HF の manifest と照合する本体 (`check-weights.sh` が各ノードで呼ぶのもこれ)。`--repo <ID>` で対象、`--revision <sha>` で照合先のリビジョン、`--manifest <ファイル>` で保存済み manifest (HF へ問い合わせない)、`--dry-run` は presence と size だけで内容ハッシュを飛ばす。exit 0 = 全一致 / 1 = 問題あり / 2 = manifest かディレクトリを解決できない

**manifest と照合するモードは revision を指定しないと当環境では必ず失敗するが、腐敗ではない。** 引数なしの `./check-weights.sh` は manifest を取りに行かず、両ノードの presence と size (124 GiB / 11 シャード) だけを見て exit 0 で通る。失敗するのは manifest を取る `--dry-run` と `--verify` である (2026-09-09 実測)。manifest を HF の `@main` から取るのに対し、キャッシュは取得当時の revision (`fab0aecb760cec45227f6656abcaafa11abca87a`。以下 `fab0aecb` と略す) に固定されているためである。HF 側の `main` は `fc694b54` へ進んでおり、2 つの revision で中身が違う `config.json` と `README.md` の 2 件だけが size 不一致として出る (リポジトリ全 25 ファイルのうち、safetensors 11 本を含む 23 件は一致する。2026-09-09 実測)。

head だけを見るなら revision を指定して打つ。

```bash
ssh -n spark-head 'cd ~/Qwen3.8-Flash-Next-Dual-DGX-Sparks && python3 verify-weights.py \
  --repo nvidia/Qwen3.8-Flash-Next-NVFP4 \
  --revision fab0aecb760cec45227f6656abcaafa11abca87a --dry-run'
# 25/25 一致で exit 0 (2026-09-09 実測)。--dry-run なので size まで。内容ハッシュまで見るなら外す
```

**両ノードを見るときは manifest を先に固定する。** `check-weights.sh` は `--revision` を受けないので、revision を固定した manifest を作って渡す (スクリプトのヘッダに書かれた順路。**当方では未実行**)。

```bash
ssh -n spark-head 'cd ~/Qwen3.8-Flash-Next-Dual-DGX-Sparks && \
  python3 verify-weights.py --repo nvidia/Qwen3.8-Flash-Next-NVFP4 \
    --revision fab0aecb760cec45227f6656abcaafa11abca87a \
    --save-manifest /tmp/qwen-manifest.json --fetch-only && \
  ./check-weights.sh --manifest /tmp/qwen-manifest.json'
```

**新しい revision へ上げるかは別の判断である。** `fc694b54` の `config.json` は MTP の routed experts を `FP8_PB_WO` と名乗り、`hf_quant_config.json` 側の `FP8_BLOCK_SCALES` と食い違う。`0b62e12` の `start.sh` はこれを別名として受理するようになったが、**当方の `fab0aecb` は両方とも `FP8_BLOCK_SCALES` なので、この修正は当環境では効いていない** (2026-09-09 実測)。**欠落を埋めるつもりで revision を指定せずに再取得すると `refs/main` が `fc694b54` へ動き、次の起動から配信 revision が黙って変わる。**

#### YaRN

**ネイティブは 262,144 で、それを超える分は rope スケーリングによる拡張である。**

| 項目 | 値 |
| --- | --- |
| ネイティブ長 (`config.json` の `text_config.max_position_embeddings`) | 262,144 トークン |
| `YARN_FACTOR` | 2.0 (262,144 × 2.0 = 524,288) |
| 出荷時の `config.json` の `text_config.rope_parameters.rope_type` | `default` (YaRN は無効。`start.sh` が `--hf-overrides` で `yarn` に差し替える) |

**係数は常用する長さに合わせる。** Qwen 公式のモデルカードが理由と選び方を書いている。

> All the notable open-source frameworks implement static YaRN, which means the scaling factor remains constant regardless of input length, potentially impacting performance on shorter texts. We advise modifying the `rope_parameters` configuration only when processing long contexts is required. It is also recommended to modify the `factor` as needed. For example, if the typical context length for your application is 524,288 tokens, it would be better to set `factor` as 2.0.

静的 YaRN は入力長によらず係数が一定なので、短い入力の品質にも影響する。だから必要な長さちょうどに合わせる。**係数 4.0 (1M) は常用 500k に対しては過剰である。**

**このキットでの YaRN は検証されていない。** 上流の CHANGELOG によれば、2026-09-05 まで `--hf-overrides` の出力先が誤っていて YaRN は無効 (silent no-op) だった。それ以前の「1M で動いた」報告はすべてスケーリングなしの rope で 1M を流していたものである。修正後に品質を測った報告は上流にもコミュニティにも無い。**長文脈の回答を信用する前に自分で確かめる。**

**262,144 に戻すなら YaRN も切る。** `start.sh` は `MAX_MODEL_LEN` が 262,144 以下のとき `YARN_ENABLE` を強制的に false にする (`0b62e12` では `start.sh:153-156`。**この行番号は上流の更新でずれるので、`grep -n 262144 start.sh` で引き直す**)。ネイティブ以下では rope スケーリングは品質を落とすだけだからである。

#### 認証

**このレシピは vLLM に `--api-key` を渡さないので、Qwen 配信中はポート 8888 が無認証になる。** `.env` にも `.env.sample` にも API キーのキーが無く (`grep -nE "API_KEY" .env` は 1 行も返さず exit 1)、`docker inspect vllm-fn` の実引数にも `--api-key` は無い。**Bearer 無しでも出まかせの Bearer でも `/v1/*` が通ることを実測で確認した。** DeepSeek 系も `VLLM_API_KEY` を空にしてあるので、いま切り替えても認証の有無は変わらない (→「API キーの流れ」)。sparkDash (ポート 5555) と同じく、ポート 8888 も信頼できないネットワークへ出さない。認証を付けたい場合は `.env` の `EXTRA_VLLM_ARGS="--api-key <値>"` で渡せる (未検証)。**その場合はクライアント側も直す。** サーバだけ直すと両方とも起動前に 401 で止まるので、「API キーの流れ」の「認証ありに戻す」手順 2 と 3 を同じく適用する。

**どちらも API キーを扱わないので 1Password は要らない。** ただし `ccsp` だけは本物の Anthropic 資格情報が Spark へ飛ぶ経路を持つ (→「API キーの流れ」)。

#### 使える API

**Claude Code と OpenCode の 2 つから使える (2026-09-06 に実測)。** このイメージの vLLM は複数の API をフラグ無しで持つ。`/v1/messages` (Anthropic Messages API) は `vllm/entrypoints/generate/api_router.py` が `register_anthropic_api_router(app)` を無条件に呼ぶので `ccsp` が通り、`/v1/chat/completions` で `ocsp` が通る。`ccsp qwen` は `max_model_len` 524,288 から出力用の余白 32,768 を引いた 491,520 をコンテキスト上限に入れて起動する。

## Mac から使う

クライアントは 2 つある。**接続先とモデルの決め方は共通である。** どちらも `spark-common.zsh` で接続先を選び (自宅 LAN → Tailscale の順に `/health` をプローブ)、`/v1/models` を聞いてモデルと窓を決めるので、モデルを切り替えても設定は触らなくてよい。違うのは次の 6 点である。

| 観点 | `ccsp` (Claude Code) | `ocsp` (OpenCode) |
| --- | --- | --- |
| 使う API | `/v1/messages` | `/v1/chat/completions` |
| シェルへの副作用 | `ANTHROPIC_BASE_URL` / `NODE_OPTIONS` の export と `claude` の alias。**`ccsp off` で戻す** | なし (接続先は 1 回の起動にだけ効く環境変数で渡す) |
| 引数の素通し | `lan` / `ts` / 短縮名を消費した残りをそのまま claude へ。どの経路でも配信前検査と `--settings` 注入は必ず通る | opencode のサブコマンド (`run` 以外) は**接続先の決定も配信前検査も `--model` 注入もしないで素通し**。`--model` を前置するとサブコマンド的文脈で unknown option 扱いになり実行の代わりに help 表示になる (2026-09-06 実測) |
| モデルを増やしたとき | `_ccsp_effort` に effort を足す | `opencode.json` の `models` に宣言と effort が要る |
| reasoning effort の決め方 | 配信名から自動 (`CCSP_EFFORT` で上書き) | `opencode.json` の静的値 |
| 資格情報の漏れ | **本物の Anthropic トークンが Spark へ飛ぶ** (→「API キーの流れ」) | なし |

速度はクライアント側の作りで 10 倍以上変わる (→「L2 / L3」)。

### 新しいマシンで手で用意するもの

Nix (`drs`) では入らないものが 5 つある。

| もの | 用途 | 作り方 |
| --- | --- | --- |
| `~/.ssh/config` と鍵 2 本 | ssh エイリアス | 「接続する」節 |
| `known_hosts` の 3 エントリ | Claude の非対話 ssh | 「接続する」節の `ssh-keyscan` (人が実行) |
| Tailscale へのサインイン | 出先から使うとき (`ccsp` / `ocsp` の両方)。cask はアプリを置くだけで tailnet 参加は手作業 | アプリを開いてログイン。**`tailscale status` に `spark-head` の行が出れば合格** |
| 1Password へのサインイン | `ccds` のトークン取得と、下の `/tmp/spark.key` の書き出し。**Spark 向けの 2 つ (`ccsp` / `ocsp`) には要らない** | `op signin` |
| `/tmp/spark.key` (head のみ) | `bench.py` を打つときだけ。無認証の現在も文字列自体は要る | 「API キーの流れ」節 |

`ccsp` / `ocsp` の関数本体と `opencode` のバイナリは Nix 経由なので、**`drs` を実行してから新しいシェルを開くまで存在しない** (既存シェルには旧定義が残る)。Tailscale 本体は `nix/modules/darwin/homebrew.nix` の cask `tailscale-app` で入る。

### Claude Code (`ccsp`)

```bash
ccsp                       # 到達する方を自動選択し、配信中のモデルで claude を起動
ccsp lan                   # 自宅 LAN を強制 (プローブしない)
ccsp ts                    # Tailscale を強制
ccsp qwen                  # モデルを指定 (qwen / vision)
ccsp lan qwen              # 接続先とモデルは順不同で並べられる
ccsp status                # 起動せずに接続先・設定ファイル・要求モデル・effort・両経路の到達性・配信中モデルを表示
ccsp off                   # Anthropic に戻す
ccsp -h                    # usage を出して終了
ccsp lan -p "..." --allowedTools Read   # 認識しない語から先は claude にそのまま渡る
ccsp -- status                     # 解釈を打ち切り (-- 自体を消費して) 以降を全部 claude へ。予約語の解除用
```

実体は `zsh/functions/claude-deepseek.zsh` の `ccsp` と `agents/bindings/claude/settings.spark.json` である。**前提は dotfiles が `$GHQ_ROOT/github.com/skanehira/dotfiles` にあることだけである** (`GHQ_ROOT` は `nix/modules/home/env.nix` が `$HOME/dev` に設定する。関数は fallback を持たないので `drs` 済みであることが要る)。1Password は要らない。`ccsp ts` は Mac が同じ tailnet に参加している必要がある。

押さえるべき点が 9 つある。

- **`ccsp` 自身が `claude` を起動する。** 続けて `claude` を打つ必要はない。同じシェルで打ち直せるよう alias も張るが、alias は子プロセスに継承されないので、**サブシェルやスクリプトからは `ccsp` 経由で起動する**
- **`ccsp off` が戻すのは `ANTHROPIC_AUTH_TOKEN` / `ANTHROPIC_BASE_URL` / `NODE_OPTIONS` と alias だけである。** `CCSP_EFFORT` / `CCSP_MODEL` / `CCSP_LAN_HOST` は export したまま残るので手で `unset` する。切り分けのために `CCSP_EFFORT` を入れたシェルでモデルを切り替えると、語彙が変わって 400 が続く
- **`ccds` から切り替えるときは、`claude` を終了してから `ccds off` を打つ。** `ccsp` はトークンを設定しないが、`ccds` が入れた `ANTHROPIC_AUTH_TOKEN` が残っているとそれがそのまま Spark へ送られる (無認証なので通ってしまい気づきにくい)。逆向き (`ccsp` → `ccds`) は `ccsp` が `ANTHROPIC_AUTH_TOKEN` を設定しないので起きない。**`ANTHROPIC_BASE_URL` と `NODE_OPTIONS` は残るが、`settings.deepseek.json` の `env.ANTHROPIC_BASE_URL` がシェルの export を上書きするので宛先は DeepSeek 本家になる** (2026-09-09 実測)。`off` は環境変数を消すだけなので、進行中のリクエストは止まらない
- **Spark 用の settings JSON に `ANTHROPIC_BASE_URL` を書かない。** settings の `env` はシェルの export を無条件に上書きするため (2026-09-09 実測)、JSON に書くと出先での切り替えが効かなくなる。接続先は `ccsp` が export する。`settings.deepseek.json` は宛先が DeepSeek 本家 1 つだけなので書いてある
- **`ccsp` は `NODE_OPTIONS` に `--dns-result-order=ipv4first` を足し、`off` で元に戻す。** mDNS 名は到達できない IPv6 を 2 つ返し、Node が毎回それを試してから IPv4 に落ちるため接続が 223 ms かかる (IPv4 強制なら約 12 ms)。IPv4 を強制しないと「`hi` と打っただけで network retry」になる。IP を直接使いたいときは `CCSP_LAN_HOST` に IP を入れる (公開リポジトリなので関数内には直書きしない)
- **2 つの設定ファイルで反映経路が違う。** `settings.spark.json` は `ccsp` が dotfiles を直参照するので編集すれば次の起動から効く。`zsh/functions/*.zsh` は Nix store 経由で配られるので `drs` と新しいシェルが要る。**この差は片側だけ適用された状態を作る。** 例えば effort を `settings.spark.json` から `_ccsp_effort` へ移す変更では、削除が即時に効く一方で注入する側が届かないため、`drs` を当てるまで effort を送らない状態になる (`grep -c _ccsp_effort ~/.config/zsh/functions/claude-deepseek.zsh` が 0 なら未適用)。**旧定義が残っているかは `ccsp -h` で判る** (新しい版は短縮名の表を出す)。旧のまま `ccsp qwen` を打つと `qwen` が短縮名として認識されず `claude` への引数に回り、プロンプト "qwen" として無言で起動してしまう
- **モデル名とコンテキスト上限は `ccsp` が `/v1/models` から取る。** 配信名をそのまま使い、`CLAUDE_CODE_MAX_CONTEXT_TOKENS` には `max_model_len` から出力用の余白 (既定 32,768。`CCSP_OUTPUT_RESERVE` で変更可) を引いた値を入れて `~/.cache/ccsp/settings.json` を毎回生成する。`max_model_len` は入力と出力の合計なので、窓をそれと同値にすると生成時に溢れる。配信側のモデルを変えても Mac 側の編集は要らない。短縮名 (`qwen` / `vision`) を渡した場合はそれが配信されているかを起動前に検査し、載っていなければ配信中の一覧を出して exit 1 で止まる。短縮名に無いモデルは `CCSP_MODEL=<配信名> ccsp` で渡す
- **reasoning effort も `ccsp` が配信名から決める。** `_ccsp_effort` の表 (`qwen3.8-flash-next` → `xhigh` / それ以外 → `high`) を引いて `CLAUDE_CODE_EFFORT_LEVEL` に注入する。**これはサーバに聞けない値なので、モデル名と違って表を持つしかない** (`/v1/models` は受理される effort を返さない)。上書きは `CCSP_EFFORT=<値> ccsp`。**モデルの語彙に無い値は起動前ではなく最初のリクエストで 400 になる** (検査がチャットテンプレートとスキーマにあるため、`ccsp` からは事前に判定できない → 「reasoning effort の語彙」)。**解決した値が出るのは起動時の 1 行 (`ccsp: Spark モード (… / effort <値>)`) だけである。** `ccsp status` は起動せずに表示する都合で配信名を確定させないため、`CCSP_EFFORT` があればその値を、無ければ規則の文言を出す (読者が同じ画面の「配信中:」行と突き合わせる)
- **`ccsp status` の「配信中」行は `ANTHROPIC_BASE_URL` を優先して照会する。** `ccds` はこれをシェルへ export しないので、素のシェルでは到達した方 (Spark) のモデルが出る。**空になるのは照会先が答えないとき**である (典型は `ccds` が起動した Claude Code の配下 — settings の `env` を継承して DeepSeek 本家を照会する。Spark 側が落ちている場合も同じ。`ocsp status` は常に到達した方を照会する。2026-09-09 実測)

`settings.spark.json` は **`security-guidance` プラグインを無効にしている** (`enabledPlugins` のキーは完全名 `security-guidance@claude-plugins-official`)。このプラグインの Stop hook は自前の既定モデル名 `claude-opus-4-7` を `ANTHROPIC_BASE_URL` に投げるため、Spark 相手では 404 を受けて延々とリトライし、レビューを 1 件も出さないまま 1 セッションあたり約 231 秒を捨てる。`settings.deepseek.json` (DeepSeek 本家) も同じ理由で無効にしてある。

### OpenCode (`ocsp`)

```bash
ocsp                       # 到達する方 (LAN → Tailscale) を選んで対話 TUI をカレントディレクトリで起動
ocsp lan                   # 自宅 LAN を強制 (プローブしない)
ocsp ts                    # Tailscale を強制
ocsp qwen                  # モデルを指定して起動 (qwen / vision)
ocsp ts qwen               # 接続先とモデルは順不同で並べられる
ocsp run "README を要約して" # headless で 1 回実行
ocsp qwen run "..."        # モデルを指定して headless 実行
ocsp model vision          # このシェルの既定モデルを切り替える
ocsp status                # 要求モデル・両経路の到達性・配信中モデルを表示
ocsp -h                    # 使い方とモデル名の短縮表を出して終了
ocsp session list          # opencode のサブコマンドは素通し (接続先の上書きも配信前検査も --model も付けない)
ocsp -- --help             # 解釈を打ち切り (-- 自体を消費して) 以降を全部 opencode へ。予約語の解除用
```

実体は `zsh/functions/opencode-spark.zsh` である。**`ccsp` と違ってシェルに残る環境変数も alias も作らない**ので、解除操作 (`off` に相当するもの) が要らない。**`status` と `model` は先頭に置く。** 接続先とモデルの語より前で分岐するので、`ocsp ts status` は `status` が opencode の引数に回って通らない (`ccsp` も同じ)。

**接続先の決め方は `ccsp` と同じである。** `lan` / `ts` を渡せばその起動だけ強制し、渡さなければ `spark-common.zsh` の `_spark_base_url` が `/health` を LAN → Tailscale の順にプローブして到達する方を採る。どちらにも届かなければ `opencode` を起動せず exit 1 で止まる。**出先では `ocsp ts` を渡すと LAN プローブの最大 3 秒 (`--connect-timeout 3`) を飛ばせる** (`ocsp run` を繰り返す使い方では毎回効く)。**LAN 側に IP を使いたいマシンは `ccsp` と共通の `CCSP_LAN_HOST` に入れる** (`opencode.json` は編集しない)。

**この挙動が効くのは `drs` を当てて新しいシェルを開いてからである。** 関数本体は Nix store 経由で配られるので、既存シェルには旧定義が残る。**旧定義かどうかは `ocsp -h` で判る** (新しい版は `lan` / `ts` の行を出す)。旧のまま `ocsp ts` を打つと `ts` が短縮名としても接続先としても認識されず opencode の引数に回る。

**選んだ接続先は環境変数 `OPENCODE_CONFIG_CONTENT` で渡す。** `ocsp` が `{"provider":{"spark":{"options":{"baseURL":"<選んだ URL>/v1"}}}}` を組み立てて `opencode` の前に置く。OpenCode はこのインライン JSON を設定にディープマージする。**マージは `options` の中まで再帰するので、差し替わるのは `baseURL` の 1 キーだけで、`models` / `npm` も `options.apiKey` も生き残る** (opencode 1.18.18 で実測 → 「依拠する外部事実」)。**前置代入なのでその 1 回の起動にしか効かず、シェルには何も残らない。**

**設定の読み取り経路が 2 本ある。** `ocsp` 自身の配信前検査 (`/v1/models` の照会と `apiKey` の解決) は `~/.config/opencode/opencode.json` を直読みし、`opencode` 本体だけがマージ後の設定を読む。**したがって `apiKey` を足すときはファイル側に書く** (両方の経路に同じ値が届く)。**選んだ経路は起動時に表示されない** (`ccsp` は `ANTHROPIC_BASE_URL` の export で判るが、`ocsp` はシェルに何も残さないため)。どちらに繋がるかを先に知りたいときは `ocsp status` を打つ。

**モデルの決め方は `ccsp` と同じである。** 引数で短縮名を渡せばその起動だけそれを使い、渡さなければ `/v1/models` の配信中モデルを採る。`ocsp model <名前>` はシェル変数 `OCSP_MODEL` を書き換えるので以降の起動に効く (新しいシェルでは未設定に戻り、また配信中のモデルを採る)。要求したモデルが配信されていなければ起動前に exit 1 で止まる。**配信中の一覧そのものが引けないときも止まる** (`ccsp` と同じ挙動)。**`opencode.json` に `apiKey` は無い。** `ocsp` はキーが空なら Authorization ヘッダ自体を送らないので、Qwen 配信中 (無認証) はそのまま一覧が引けて起動する (2026-09-06 実測)。DeepSeek 系を認証ありで起動すると 401 になるので、そのときは `options` に `apiKey` を足す。**値は `{file:~/…}` か `{env:…}` で外部に逃がす** (`opencode.json` は公開リポジトリの追跡ファイルなので平文で置かない。→「API キーの流れ」)。**`opencode.json` の `models` に宣言が無いモデルは OpenCode 側が拒否するので、モデルを増やしたらこの JSON にも足す。** 値の決め方は `limit.context` = `/v1/models` の `max_model_len`、`limit.output` = 65536、`reasoning` と `tool_call` は `true`、`options.reasoningEffort` はそのモデルが受ける最大値 (現在は `qwen3.8-flash-next` = `xhigh` / `deepseek-v4-flash-vision-exp` = `high`) である。**`ccsp` と違ってこれは人が書く静的値なので、サーバ側の `MAX_MODEL_LEN` を変えると取り残される** (`workerLabel` と同型の乖離経路)。**`reasoningEffort` を省くと `ocsp` は effort を送らず、テンプレート既定 (Qwen なら `xhigh`) が効く。** 明示してあるのは既定が変わったときに黙って浅くならないようにするためで、Qwen については省略時と同じ値である。

**opencode のサブコマンドは素通しする。** 短縮名や接続先の語のうしろの先頭語がサブコマンド名 (`session` / `models` / `stats` / `mcp` / `serve` など) のとき、接続先の決定・配信前検査・`--model` 注入の 3 段を飛ばして `command opencode` にそのまま渡す。**プローブより手前で分岐するので、サーバが両経路とも落ちていてもサブコマンドは打てる** (接続先の語を渡しても無視される)。モデルを使うのは `pr` だけ (checkout 後に起動する opencode が既定モデルを解決する。これも `opencode pr --model <任意> <番号>` が unknown option で help 表示に化けるため注入不能。実測) で、他は検査を絡めるとサーバが落ちていて一覧も見られないという誤った失敗方になるうえ、`--model` はサブコマンド側で unknown option として弾かれ、実行の代わりに help 表示になるだけだからである (2026-09-06 実測: `opencode --model spark/fake session list` は help しか出さず、素の `ocsp session list` はセッション表を出す)。**`run` は例外で、`--model spark/<名前>` と `--dir` を付けた専用経路のまま** (`run` は `--model` を受け付ける)。素通し対象は `opencode-spark.zsh` のホワイトリストで `opencode --help` の commands と対応しているが、**opencode のアップグレードで増えたサブコマンドはホワイトリストに無いため TUI 起動の組み立てに回る** (サーバが落ちているとそこまでに達せず配信前検査で止まる)。**その間は先頭 `--` の解除語で素通しできる** (2026-09-06 実測: `ocsp -- --version` は `opencode` 本体が `1.18.18` を出す)。

**その乖離は現に起きている。** 2 モデルとも `limit.context` は 524,288 だが、DeepSeek 系 (Vision-Exp) のサーバ上限は 1,048,576 である (「サービングの構成」)。Vision-Exp を配信しても OpenCode は 524,288 で頭打ちになる。**害は早めに圧縮が走ることだけで壊れはしない**ので放置してもよいが、直すなら `agents/bindings/opencode/opencode.json` の当該エントリを 1048576 にする。

**設定は `agents/bindings/opencode/{opencode.json,tui.json}` として dotfiles にあり、`nix/modules/home/opencode.nix` が `mkOutOfStoreSymlink` で `~/.config/opencode/` に貼る** (`agents/bindings/claude/settings.json` と同じ live edit)。`~/.config/opencode/` には opencode 自身が書くファイル (`node_modules` / `package.json` / `package-lock.json` / `.gitignore` など) と `nix/modules/home/harness.nix` が生成する `skills/` / `agents/` / `AGENTS.md` が同居する (移行時の残骸が残ることもある) ので、**symlink するのは `opencode.json` と `tui.json` の 2 枚だけ**である。**`opencode.json` 自体は `ocsp` 経由でも要る** (`provider.spark` の `npm` と `models` の宣言がここにしかないため。無ければ `ocsp` は起動前に止まる)。

**live edit になるのは `drs` を当てた世代からである。** それ以前の世代では同じパスが Nix store 内のコピーを指しており、dotfiles を編集しても反映されない。**どちらの状態かは `readlink -f` で判る** (→「依拠する外部事実」)。**単 hop の `readlink` では判らない。** `mkOutOfStoreSymlink` は 2 段の symlink を作り、1 段目は live でも `/nix/store/…-home-manager-files/…` を指すためである。2026-09-07 に再確認した時点でもこのマシンは live edit 側で、`opencode.json` の編集は `drs` 無しで次の起動から効く。

**`baseURL` に書いてある mDNS 名 (`http://spark-head.local:8888/v1`) は素の `opencode` 用の既定値である。** IP を書けば接続あたり約 210 ms 速いが (実測 224 ms 対 7〜21 ms)、このリポジトリは公開なので置かない。mDNS 名が遅いのは、到達できない IPv6 を 2 つ返し、それを試してから IPv4 に落ちるためである。`ccsp` は `NODE_OPTIONS=--dns-result-order=ipv4first` で回避しているが、opencode には相当する手段が無い。**`ocsp` からはこれを `CCSP_LAN_HOST` に IP を入れて避ける。Tailscale 側 (`http://spark-head`) に同種の遅延が出るかは未計測で、そちらを上書きする変数も無い。**

`autoupdate` は `false` にしてある (本体は Nix 管理で、store は書き換えられないため)。

## 実測値

数値は条件が変わると簡単に 25% 動くので、表ごとに条件を書いてある。**閾値だけを覚えて条件を変えて測ると誤診する。**

### L1: サーバ単体 (2026-09-05)

`~/spark-bench/bench.py` でサーバを直叩きした値である。条件はプロンプト 6,000 トークン、`max_tokens` 256、`chat_template_kwargs={"thinking": true, "reasoning_effort": "low"}` (サーバ既定の `DEFAULT_THINKING=low` と同じ)、指示は「上記は無視して、TypeScript の関数を 1 つ書いてください。説明は不要でコードだけ返してください。」`c` は `--concurrency`。中央値と (最小〜最大)。

**`chat_template_kwargs` は `--extra-body` でしか渡せない。** `bench.py` はこのキーの既定を持たないので、下の再現コマンドから `--extra-body` を落とすと条件が変わる (思考が既定のまま走る)。**これはテンプレートに直接渡す第 3 の経路である。** 2 つのクライアントが使う `reasoning_effort` / `output_config.effort` と違い、スキーマの Literal 検査を通らずにテンプレートへ届く。`bench.py` は `min_tokens` を `max_tokens` と同値にし `ignore_eos` を立てるので、生成長は常に 256 トークン固定である。

| 条件 | n | Vision-Exp |
| --- | --- | --- |
| c=1・decode (tok/s) | 5 | 40.77 (34.88〜62.80) |
| c=1・TTFT (秒) | 5 | 3.47 (3.20〜3.93) |
| c=4・decode (tok/s) | 8 (4 並列 × 2 回) | 21.95 (14.44〜34.88) |
| c=4・TTFT (秒) | 8 (4 並列 × 2 回) | 9.44 (4.93〜13.47) |

**判定: c=1 の decode 中央値が 35 tok/s を下回る、または c=4 の TTFT 中央値が 15 秒を超えたら異常を疑う。** 個別値ではなく中央値で見る (正常時でも最小値は 34.88 tok/s まで落ちる)。再現は次の 2 本で、結果は `~/spark-bench/results/<ラベル>-<日時>.json` に残る。

```bash
ssh -n spark-head 'python3 ~/spark-bench/bench.py --model deepseek-v4-flash-vision-exp \
  --key-file /tmp/spark.key --prompt-tokens 6000 --max-tokens 256 --concurrency 1 --n 5 \
  --extra-body "{\"chat_template_kwargs\":{\"thinking\":true,\"reasoning_effort\":\"low\"}}" \
  --instruction "上記は無視して、TypeScript の関数を 1 つ書いてください。説明は不要でコードだけ返してください。"'
ssh -n spark-head 'python3 ~/spark-bench/bench.py --model deepseek-v4-flash-vision-exp \
  --key-file /tmp/spark.key --prompt-tokens 6000 --max-tokens 256 --concurrency 4 --n 2 \
  --extra-body "{\"chat_template_kwargs\":{\"thinking\":true,\"reasoning_effort\":\"low\"}}" \
  --instruction "上記は無視して、TypeScript の関数を 1 つ書いてください。説明は不要でコードだけ返してください。"'
```

### L2 / L3: クライアント込み (2026-09-05)

同一の実タスク (TypeScript プロジェクトで Read → Edit → Edit → Grep の 4 tool call) を流し、`~/spark-bench/snap.py` で `/metrics` の前後差分を取った値である。列の意味は次のとおり。

- **サーバ内時間** = リクエストごとの queue + prefill + decode の**合算**。並列に走ればこの値は実時間を超える
- **クライアント側の待ち** = 実時間 − サーバ内時間。リクエストが重なると負になる (= クライアント側の待ちがほぼ無い)

測定はいずれも Vision-Exp 配信中に取った。**effort の条件は現行の既定と違う。** この計測は Claude Code 側が静的な `medium`、OpenCode 側が未指定 (テンプレート既定) だった時点のもので、現在は `_ccsp_effort` と `opencode.json` が配信モデルごとの最大値を送る。**effort は system への指示文を変えるので、下の受理率とプロンプト長は条件を跨いで比較しない。**

| 層 | 構成 | n | 実時間 (秒) | ターン数 (回) | 1 ターンのプロンプト (トークン) | 受理率 | prefix ヒット率 | クライアント側の待ち (秒) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| L2 | Claude Code (通常設定) | 2 | 329〜484 | 5〜12 | 54,794〜55,866 | 0.43〜0.48 | 0.66〜0.73 | **231〜233** |
| L2 | Claude Code (グローバル設定なし) | 1 | 41 | 5 | 18,335 | 0.60 | 0.68 | −18 |
| L3 | OpenCode | 2 | 21〜30 | 5 | 14,998〜15,008 | 0.66〜0.69 | 0.73〜0.90 | −3〜0 |

「グローバル設定なし」は `~/.claude/CLAUDE.md` と `agents/rules/` を外した `CLAUDE_CONFIG_DIR` で起動した回である。

**同じサーバ・同じモデル・同じタスクで実時間が 10 倍以上違う。差はすべてクライアント側にある。**

- **Claude Code 通常設定の「クライアント側の待ち」231〜233 秒はほぼ全量が `security-guidance` の Stop hook である。** 無効化した回では 0 以下に落ちる。この値は 2 回の走行でほぼ一定だった
- **1 ターンのプロンプトが 55,000 対 15,000 トークンなのは、グローバル `CLAUDE.md` と `rules` が毎ターン載るためである。** prefill 律速の本環境ではこれがそのまま待ち時間になる
- **`--settings` に `hooks: {}` を書いてもプラグインの hook は止まらない** (stream-json に `hook_started` が出続ける)。止めるには `enabledPlugins` で当該プラグインを `false` にする

### 遅いと感じたときに疑う順序

サーバを疑うのは最後である。上から順に見る。

1. **`security-guidance` が有効になっていないか** — 症状は「最後の応答が出てから 200 秒以上プロンプトが返らない」。`settings.spark.json` の `enabledPlugins` を見る
2. **グローバル設定の prefill** — `agents/rules/core/*.md` の 10 ファイルと `core/references/loop-engineering.md` は frontmatter を持たないため毎ターン展開される (合計 48,826 バイト / 22,907 文字、2026-09-09 実測)。`backend/**` や `frontend/**` は `paths:` で対象言語に絞られ、`core/references/` の他の 7 ファイルは `__read-on-demand-only__` で除外されているのに、この 11 本だけ素通しになっている。**これは dotfiles 側の設計課題であって Spark の問題ではない**
3. **prefix cache のヒット率** — 機構自体は正常に動く (同一プロンプトを 2 回送れば 2 回目にヒットが立つ)。実負荷のヒット率はクライアントがプレフィックスをどれだけ安定させるかで決まる。**L2 / L3 の実測レンジは 0.66〜0.90 で、0.5 を切ったらクライアント側の変動を疑う**
4. **投機デコードの受理率** — decode 速度をほぼ決める。**L2 / L3 の実測レンジは 0.43〜0.69 で、0.4 を切ったら疑う。** この値は生成させる内容で動く (構造化された出力で高く、散文で低い)
5. **サーバ本体** — ここまで潰してから L1 のベンチを上のフラグで回す

3 と 4 の計算は `/metrics` から行う。**キー名は完全一致で拾う。** `prefix_cache` には `vllm:external_prefix_cache_*` が、`spec_decode_num_.*_total` には `vllm:spec_decode_num_accepted_tokens_per_pos_total` が別に存在し、緩い grep は別系列を合算して値を過大に出す。

```bash
curl -s http://spark-head.local:8888/metrics | grep -E '^vllm:(prefix_cache_(hits|queries)_total|spec_decode_num_(accepted_tokens|draft_tokens)_total|request_(prompt|generation)_tokens_sum|request_success_total)'
```

- prefix ヒット率 = `prefix_cache_hits_total` ÷ `prefix_cache_queries_total`
- 受理率 = `spec_decode_num_accepted_tokens_total` ÷ `spec_decode_num_draft_tokens_total`
- 1 リクエストの平均生成長 = `request_generation_tokens_sum` ÷ `request_success_total` の**全 `finished_reason` の合計** (`stop` / `length` / `abort` / `error` / `repetition` の 5 行に分かれて出るので足す。`length` が多ければ出力の打ち切りが起きている)

**本構成の律速は decode ではなく prefill である。** 実負荷での累計プロンプト対生成トークン比は 100:1 前後、1 リクエストの生成長は数百トークンにとどまる。decode を速くする施策は体感に効きにくい。**これらの counter は vLLM コンテナの再起動でリセットされるので、値は「現コンテナが起動してからの累計」として読む** (絶対値は窓の取り方で動く)。

## 障害時

**コンテナ名は系統で違う。** DeepSeek 系は `deepseek-v4-flash-vllm-dspark-1`、Qwen 系は `vllm-fn` (両ノードとも同名) である。

**表の確認手段に `ccsp status` / `ocsp status` を使う行があるが、Claude の Bash ツールから打っても正しい判定にならない** (関数自体はスナップショットに入っているが `_spark_*` ヘルパーが無く、URL が空のまま「に届かない」と表示する →「依拠する外部事実」)。切り分けは `curl -fs -o /dev/null http://spark-head.local:8888/health` で行う。

| 症状 | 確認 | よくある原因 |
| --- | --- | --- |
| 応答しない | 下の待ち行列コマンド | コンテナは生きていて過負荷。同時リクエスト上限 (DeepSeek 系 6 / Qwen 系 8) を超えた分が待つので、待ち行列が 0 でなければ過負荷 |
| コンテナが無い | 両ノードで `docker ps --filter name=vllm` (DeepSeek 系・Qwen 系の両方を拾う) | 停止スクリプトで止めたまま。起動し直す |
| 起動に失敗する | `./logs-deepseek-v4-flash-dspark.sh` (Qwen 系は `docker logs vllm-fn`) | DeepSeek 系の `no usable RoCEv2 GID` は RoCE 2 本目の IP か MTU (Qwen 系は `IB_HCA` が 1 本なのでこの形では出ない)。Qwen 系は相手系統が GPU を掴んだままだと `REQUIRE_IDLE_GPU` で拒否される |
| Qwen 系がコンテナを作らずに `Checkpoint snapshot is incomplete` で止まる | `python3 files/resolve_snapshot.py <hub の repo ディレクトリ>` の exit code (0 以外) | シャードの欠落。`0b62e12` から `start.sh` が起動前に検査するようになった (→「重みの検証」)。**コンテナが 1 つも作られないので `docker logs vllm-fn` は空振りする。`start.sh` の標準出力を見る。** 復旧は `./download.sh` での再取得だが、**revision を指定しないと配信 revision が動く** |
| `model not found` が出る | `curl .../v1/models` で配信名を見る | セッション起動後にサーバ側で切り替えた。`ccsp` / `ocsp` は起動時のモデル名を送り続けるので起動し直す |
| `ocsp` が「`<名前>` は配信されていません」で止まる | メッセージが出す配信中の一覧 | 要求した短縮名と実際の配信モデルが違う。これは異常ではなく配信前検査が効いた状態。**この文言を出すのは `ocsp` だけ** |
| `ccsp` / `ocsp` が「取得できません」で止まる | `ccsp status` / `ocsp status` でサーバの生死を見る。メッセージが出す URL も見る | **`ccsp` はこの 1 文言に 2 つの原因を束ねている。** 要求したモデルが配信されていない場合と、サーバに届かない場合の両方。メッセージが続けて出す「配信中: …」が空なら後者。認証を復活させた場合も 401 でこうなる (→「API キーの流れ」)。**接続先を誤った側に強制した場合 (出先で `lan`、自宅で `ts`) もプローブを飛ばしてここに落ちる** |
| `ccsp` / `ocsp` が「LAN にも Tailscale にも届きません」で止まる | `ccsp status` / `ocsp status` の LAN 行と TS 行 | どちらの `/health` にも届かなかった。サーバが落ちているか、出先で Tailscale にサインインしていない。接続先が判っているなら `lan` / `ts` で強制できる (プローブを飛ばす)。**強制した先も死んでいれば次は上の「取得できません」に変わる** |
| `ocsp` が「OpenCode の設定がありません」で止まる | `ls -l ~/.config/opencode/opencode.json` (`readlink -f` はファイルが無いと空出力 + exit 1 を返すので実体を見る) | `drs` 未実行でファイルが無い。`provider.spark` の `npm` と `models` の宣言がここにしかないので、接続先を上書きする方式でも起動前に止まる |
| `Unexpected reasoning effort <値>` の 400 | 送っている effort の値 (`CCSP_EFFORT` / `opencode.json`) | **両方の経路で出る。** 検査はチャットテンプレートにあり、`/v1/messages` も `/v1/chat/completions` も同じテンプレートを通る (→「reasoning effort の語彙」)。Qwen で使えるのは `low` / `medium` / `xhigh` の 3 つ。**Qwen 配信中は既定の設定で踏まない** (`_ccsp_effort` と `opencode.json` が `xhigh` を持つ)。踏むのは (1) `CCSP_EFFORT` に語彙外の値を入れたとき (2) `_ccsp_effort` / `opencode.json` に登録していないモデルを配信したとき (既定の `high` が飛ぶ) (3) **DeepSeek 系に切り替えた最初の 1 回** (両クライアントが送る `high` はレシピの語彙に合わせただけで未実測) |
| `Input should be 'low', 'medium', ...` の 400 | 送っている effort の値 | `ccsp` の経路 (`/v1/messages`) に `none` を渡した。スキーマが `none` を持たないため、テンプレートより手前で弾かれる。**`ocsp` の経路では `none` が通る**という非対称がある (→「reasoning effort の語彙」) |
| OpenCode がモデルを拒否する | `agents/bindings/opencode/opencode.json` の `provider.spark.models` | 宣言の無いモデル名は OpenCode 側が受け付けない |
| 起動待ちが長すぎる | head は `docker logs <コンテナ名>`、worker は「worker に入る」節のコマンドで同じものを打つ | 正常な所要は DeepSeek 系が約 6 分、Qwen 系が約 13〜14 分 (実測)。DeepSeek 系は 10 分、Qwen 系は 20 分を超えたら worker 側だけ落ちていることがあるので両ランクを見る |
| 起動直後から空きメモリが少ない | `free -h` | 正常。`GPU_MEMORY_UTILIZATION_TEXT=0.835` の先取り。**残る量は系統と負荷で変わる** (DeepSeek 系 6〜8 GiB、Qwen 系の head は 1.3〜5.7 GiB。→「メモリの使われ方」) |
| `hi` と打っただけで network retry | `ccsp status` で LAN 到達を確認 | mDNS の IPv6 フォールバック。`NODE_OPTIONS` に `--dns-result-order=ipv4first` が入っているか見る |
| 応答後に 200 秒以上返らない | `settings.spark.json` の `enabledPlugins` | `security-guidance` の Stop hook (→「遅いと感じたときに疑う順序」1) |
| 全体的に遅い | 「遅いと感じたときに疑う順序」を上から | クライアント側が大半 |
| ダッシュボードの worker が古いモデル | `~/sparkDash/config/sparks.json` | `workerLabel` は手書きの静的文字列。実機とは無関係に表示される。直し方は→「sparkDash の `workerLabel` を直す」(root 所有なのでコンテナ経由で書く) |
| ssh 出力が途中で切れる | 打ったコマンド | 入れ子の `ssh` が標準入力を飲んでいる。内側に `-n` を付ける |
| `ccsp` / `ocsp` が `command not found` | `type ccsp` が `function` を返すか | 2 つとも Nix 配布なので、`drs` 未実行か、`drs` 後に新しいシェルを開いていない |

待ち行列と稼働中リクエストは次で見る。

```bash
curl -s http://spark-head.local:8888/metrics | grep -E '^vllm:num_requests_(running|waiting)\{'
```

## 触らないもの

- **`~/.ssh/known_hosts`** — Claude は書き換えない。登録が要るときは `ssh-keyscan` の 1 行をユーザーに依頼する
- **`drs` の実行** — Touch ID を伴うので Claude は打たない。`git add` までを Claude が行い、適用はユーザーに依頼する
- **`~/sparkDash/docker-compose.yml`** — 上流の追跡ファイル。上書きは `docker-compose.override.yml` に置く
- **`docker compose restart`** — vLLM には使わない。`stop` → `start`
- **`.env.dspark.bak` のような控え** — `.gitignore` が拾わずキーごと公開リポジトリに載る
- **公開リポジトリ内のファイルへの IP 直書き** — 本書・`zsh/functions/*.zsh`・`agents/bindings/opencode/opencode.json` のいずれにも書かない。IP は `CCSP_LAN_HOST` (シェル変数) で渡す。**`ccsp` と `ocsp` の両方がこの変数を見る**ので、`opencode.json` を編集する必要は無い
- **公開リポジトリ内のファイルへの API キー直書き** — 認証を戻すときも `opencode.json` に平文で置かない。`{file:~/…}` か `{env:…}` で外部へ逃がす (`_ocsp_resolve` と opencode 本体の両方が解く → 「API キーの流れ」)
- **sparkDash のポート 5555** — 認証が無いので信頼できないネットワークへ出さない
- **ポート 8888** — 系統を問わず無認証なので外に出さない (→「API キーの流れ」)
- **0731 の残置物** — head の `~/dspark-0731` (detached `70a7cc4` の git worktree、4.4 MB) と両ノードの重み 156 GiB ずつ。**使わないが消さない。** ディスクは 3.0 TB 空いていて消す動機が無く、再取得は HuggingFace から約 5.5 時間かかる

## 既知の制約

1. **Spark には passwordless sudo が無い。** `/etc/sudoers.d/` は README のみである。`nvidia-smi --lock-gpu-clocks` や systemd の操作など sudo が要る作業は Claude からは実行できないので、コマンドを提示して人間に実行してもらう (パスワードは `skanehira` の Ubuntu ログインパスワードで、本書には保管しない)。Mac の Touch ID による sudo は Linux ノードには効かない。**コンテナ内で root が必要な作業は `docker run --entrypoint` で代替できる** (重みの所有権修正など)
2. **worker への直接 ssh は `known_hosts` の登録が前提である。** 未登録のマシンでは Claude から入れないので「worker に入る」節の head 経由を使う
3. **worker は Tailscale に参加していない** (`tailscaled` が未インストール)。出先から worker を見るには head を経由する
4. **GPU クロックを 2200 MHz に制限している。** 両ノードの `/etc/systemd/system/nv-gpu-clock-limit.service` (手で配置した unit、enabled + active) が起動時に `nvidia-smi --lock-gpu-clocks=0,2200` を実行する。2026-09-05 の計測 (n=5、L1 とは別条件で結果ファイルは残っていない) では、解除しても decode +1.3% / 最悪 TTFT 約 +2% しか上がらず温度が 7 °C 以上上がった (制限あり 52〜58 °C / 制限なし 60〜65 °C) ので、制限は維持する
5. **停止と再起動はユーザーの作業を止める。** 打つ前に `curl -s http://spark-head.local:8888/metrics | grep -E '^vllm:num_requests_running\{'` で稼働中リクエストの有無を確認し、Mac 側では先に `claude` を終了して `ccsp off` で退避する (`ocsp` は環境変数を残さないので退避操作が要らない)
6. **vLLM の自動復帰は系統で違う。** DeepSeek 系コンテナの restart policy は `unless-stopped` だが、**Qwen 系 `vllm-fn` は両ノードとも `no` なので、ノードを再起動すると上がってこない** (2026-09-06 実測)。手で `./start.sh --launch` を打ち直す。sparkDash は `always`、`docker` と (head の) `tailscaled` は enabled、RoCE は NetworkManager の autoconnect である。どちらの系統も停止スクリプトで止めた後はコンテナ自体が消えるので再起動しても復帰しない。**cold boot での復帰は未確認なので、電源断の後は `docker ps` で確かめる**
7. **`~/spark-bench` は再作成手段が無い。** dotfiles にも上流にも無い手書きのハーネスなので、head を作り直すと失われる
8. **2 系統の vLLM は同時に起動できない。** ポート 8888 と GPU を共有し、Qwen 側は `REQUIRE_IDLE_GPU=true` が明示的に拒否する。切り替えは必ず「相手を停止 → 起動」の順で行う

## 依拠する外部事実

2026-09-06 に実機で確認した (**行に日付があるものはその日付が優先**。「実測値」節の性能値のみ 2026-09-05)。作業前に変わっていないか確かめる。**いまはどのエンドポイントも無認証なので、確認コマンドにキーは要らない。**

| 事実 | 確認コマンド |
| --- | --- |
| IP・インタフェース構成・MTU | `ssh -n spark-head 'ip -4 -o addr show; ip -o link show'` |
| ドライバとカーネル | `ssh -n spark-head 'nvidia-smi --query-gpu=driver_version --format=csv,noheader; uname -r'` |
| ディスクの空き | `ssh -n spark-head 'df -h /'` |
| メモリの内訳 | `ssh -n spark-head 'grep -E "^Mem" /proc/meminfo; swapon --show; nvidia-smi --query-compute-apps=used_memory --format=csv,noheader'` |
| サービングの設定値 | `ssh -n spark-head 'cd ~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark && ./validate-dspark-config.sh \| head -20'` (絞らないと解決値の後に vLLM コマンド全文が数 KB 続く) |
| 上流の先行コミット | `ssh -n spark-head 'cd ~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark && git fetch -q && git rev-list --count HEAD..origin/main && git log --oneline HEAD..origin/main'` |
| 全モデルの重み | `ssh -n spark-head 'du -sh ~/.cache/huggingface/hub/models--*'` (DeepSeek 系と Qwen 系の両方を拾う) |
| Qwen レシピの commit | `ssh -n spark-head 'cd ~/Qwen3.8-Flash-Next-Dual-DGX-Sparks && git log --oneline -1'`。上流の先行分は同じディレクトリで `git fetch -q && git log --oneline HEAD..origin/main` |
| HF 側の `main` が動いていないか | `curl -s https://huggingface.co/api/models/nvidia/Qwen3.8-Flash-Next-NVFP4 \| python3 -c 'import json,sys;print(json.load(sys.stdin)["sha"])'`。**`fab0aecb` 以外を返すならキャッシュより先に進んでいる** (2026-09-09 時点は `fc694b54`。意味は → 「重みの検証」) |
| Qwen 系の重みが完全か | `ssh -n spark-head 'cd ~/Qwen3.8-Flash-Next-Dual-DGX-Sparks && python3 files/resolve_snapshot.py ~/.cache/huggingface/hub/models--nvidia--Qwen3.8-Flash-Next-NVFP4; echo $?'` (0 で合格)。**陽性対照は存在しないディレクトリを渡して 2 が返ること。** head 1 ノードを manifest と突き合わせるなら「重みの検証」節の `verify-weights.py --revision`、両ノードなら同節の `--save-manifest` + `check-weights.sh --manifest` を使う (revision を省くと HF の `main` と比べて必ず 2 件不一致になる)。2026-09-09 実測 |
| 両ノードのイメージ | `ssh -n spark-head 'docker images --format "{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}"'` (worker は「worker に入る」節経由で同じもの) |
| worker 側の同じ確認 | 「worker に入る」節のコマンドの `<worker で実行するコマンド>` に上記を入れる |
| 稼働中のモデル名と上限 | `curl http://spark-head.local:8888/v1/models` |
| 8888 が無認証のままか | `curl -s -o /dev/null -w "%{http_code}\n" http://spark-head.local:8888/v1/models` (200 なら無認証。対照に `/v1/nope` が 404 を返すことも見る) |
| 各種メトリクス | 「遅いと感じたときに疑う順序」の `curl` 1 本 (完全一致の grep) |
| クロック制限の有効性 | `ssh -n spark-head 'systemctl is-active nv-gpu-clock-limit.service'` (worker は head 経由) |
| 再起動後の復帰条件 | `ssh -n spark-head 'docker inspect <コンテナ名> --format "{{.HostConfig.RestartPolicy.Name}}"'` (DeepSeek 系は `deepseek-v4-flash-vllm-dspark-1`、Qwen 系は `vllm-fn`) |
| Tailscale の参加状況 | Mac 側で `tailscale status` |
| OpenCode の設定 | Mac 側で `python3 -c "import json;print(list(json.load(open('$HOME/.config/opencode/opencode.json'))['provider']))"` |
| `ocsp` の接続先上書きが効くか | Mac 側で `OPENCODE_CONFIG_CONTENT='{"provider":{"spark":{"options":{"baseURL":"http://example.invalid:9/v1"}}}}' opencode debug config`。**`provider.spark.options.baseURL` がその値になり、`opencode.json` に宣言した全モデルと `npm` が残っていれば合格** (ディープマージの確認)。**陰性対照として環境変数を外した同じコマンドを打ち、`spark-head.local` が返ることも見る** (2026-09-07 に opencode 1.18.18 で実測) |
| 上書きが `options` の兄弟キーを消さないか | 認証を戻す前に確かめる。`opencode.json` を写した検証用の `HOME` を作って `provider.spark.options.apiKey` に目印の文字列を入れ、`HOME=<検証用> OPENCODE_CONFIG_CONTENT='…baseURL のみ…' opencode debug config` を打つ。**`baseURL` が差し替わったうえで `apiKey` の目印が残っていれば合格** (2026-09-07 に実測。マージは `options` の中まで再帰する) |
| OpenCode の設定が live edit か | Mac 側で `readlink -f ~/.config/opencode/opencode.json`。**dotfiles 配下を返せば live、`/nix/store/…` で終われば store コピー。** **`-f` を落とすと判定が壊れる**: `mkOutOfStoreSymlink` は `~/.config/…` → `…-home-manager-files/…` → dotfiles の 2 段になるので、単 hop の `readlink` は live でも `/nix/store/…` を返し、常に「`drs` 待ち」と誤判定する (2026-09-06 に実測。この行は live) |
| zsh 関数が配布済みか | Mac 側で `diff -q "$(readlink -f ~/.config/zsh/functions/claude-deepseek.zsh)" zsh/functions/claude-deepseek.zsh` (dotfiles で実行)。**こちらは store の実コピーなので `readlink -f` も常に `/nix/store/…` を返す。** パスではなく内容を比べる。差があれば `drs` 待ち |
| 2 つのクライアントの疎通 | Mac 側で `ccsp status` / `ocsp status`。**`drs` を当てて新しいシェルを開くまで関数は `command not found` になる** (配布済みかは上の `diff -q` の行で判る)。**Claude の Bash ツールのシェルスナップショットには `_spark_*` ヘルパーが入らないため、そこから打つと `command not found` と「に届かない」の誤判定になる (2026-09-09 実測)。切り分けは `curl -fs -o /dev/null http://spark-head.local:8888/health` で行う** |
| 配信中のモデルが受ける reasoning effort と既定値 | **経路ごとに 2 本打つ** (語彙が違う → 「reasoning effort の語彙」)。`ocsp` 側は `curl -s http://spark-head.local:8888/v1/chat/completions -H 'Content-Type: application/json' -d '{"model":"<配信名>","messages":[{"role":"user","content":"x"}],"reasoning_effort":"high","max_tokens":1}'`、`ccsp` 側は `curl -s http://spark-head.local:8888/v1/messages -H 'Content-Type: application/json' -H 'anthropic-version: 2023-06-01' -d '{"model":"<配信名>","messages":[{"role":"user","content":"x"}],"max_tokens":1,"output_config":{"effort":"high"}}'`。**`high` を投げて 400 のエラー本文を読むのが陽性対照** (対応値と既定値を列挙する)。**陰性対照として受理される値 (`xhigh`) でも打ち、200 が返ることを確かめる** (常に 400 を返す壊れた検出でないことの確認)。**Qwen 配信中に全値で実測済み。DeepSeek 系は未確認** |
| 2 つのクライアントが実際に送る effort | **設定値**は Mac 側で `python3 -c "import json;print({k:v.get('options') for k,v in json.load(open('$HOME/.config/opencode/opencode.json'))['provider']['spark']['models'].items()})"` (`ocsp` が読むのはこの実体。dotfiles 側を読むと、まだ `drs` を当てていない世代では送っていない値を報告してしまう。どちらを指しているかは上の `readlink` の行で判る) と `ccsp` の起動時の 1 行。**送信値そのものを見るには記録プロキシを挟む** (下の手順 4)。**`ccsp` 側は `drs` と新しいシェルを経ないと新実装が動かない**ので、`grep -c _ccsp_effort ~/.config/zsh/functions/claude-deepseek.zsh` が 0 を返す間は effort を送らない |
| DeepSeek 系の上流既定からの差分 | 下のコードブロック 1 (**キー行と RoCE 側の IP を持つ 4 行が出るので画面外に出さない**) |
| Qwen 系の上流既定からの差分 | 下のコードブロック 2 |
| 常時展開される rules | 下のコードブロック 3 |
| L1 の再計測 | 「L1」節の `bench.py` 2 本をそのまま打つ。**前提が 2 つある**: DeepSeek 系 (Vision-Exp) を配信中であることと、`/tmp/spark.key` を書き直してあること (無認証でも中身は何でもよいが、ファイルが無いと `bench.py` が exit する) |

表に入らないもの (1〜3 はパイプを含むため、4 はヒアドキュメントを含むため)。

```bash
# 1. .env.dspark と配布既定の差分
# 出力に VLLM_API_KEY と、IP を持つ 4 行 (MASTER_ADDR / VLLM_HOST_IP /
# WORKER_HOST / WORKER_VLLM_HOST_IP) が混じる。証跡として貼らない。
ssh -n spark-head 'cd ~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark && diff <(grep -E "^[A-Za-z0-9_]+=" .env.dspark.example | sort) <(grep -E "^[A-Za-z0-9_]+=" .env.dspark | sort)'

# 2. Qwen の .env と配布既定の差分。行の差は 6 か所出るが、うち IB_GID_INDEX は
# 値が両側とも 3 で末尾コメントだけが違う (表の「5 キー」は値が違うものの数)。
# 「書いていない上流キー」2 つは .env.sample 側にしか無い行として出る。
ssh -n spark-head 'cd ~/Qwen3.8-Flash-Next-Dual-DGX-Sparks && diff <(grep -E "^[A-Za-z0-9_]+=" .env.sample | sort) <(grep -E "^[A-Za-z0-9_]+=" .env | sort)'

# 3. frontmatter を持たず毎ターン展開される rules (dotfiles で実行)
for f in agents/rules/core/*.md agents/rules/core/references/loop-engineering.md; do
  head -8 "$f" | grep -q __read-on-demand-only__ || echo "$f"
done
```

**手順 4. クライアントが実際に送る本文を見る (記録プロキシ)。** effort のように「設定に書いた値が本当に飛んでいるか」は、サーバのログにもクライアントの出力にも出ない。両者の間に中継を挟んで本文を写し取る。下は Mac のローカルに立てて上流へそのまま流す最小の実装である (上の 1〜3 と違いヒアドキュメントを含むので、1 つのフェンスに収まらない)。

```bash
cat > /tmp/spark-proxy.py <<'PY'
import http.server, json, sys, urllib.request, urllib.error
UP, LOG, PORT = sys.argv[1], sys.argv[2], int(sys.argv[3])
class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *a): pass
    def do_GET(self): self._fwd()
    def do_POST(self): self._fwd()
    def _fwd(self):
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        rec = {"path": self.path}
        if body:
            try:
                j = json.loads(body)
                rec.update({k: j[k] for k in ("model", "output_config", "reasoning_effort") if k in j})
            except Exception:
                rec["raw"] = body[:200].decode(errors="replace")
        hdrs = {k: v for k, v in self.headers.items()
                if k.lower() not in ("host", "content-length", "connection", "accept-encoding")}
        req = urllib.request.Request(UP + self.path, data=body or None, headers=hdrs, method=self.command)
        try:
            r = urllib.request.urlopen(req, timeout=600); code, data = r.status, r.read()
        except urllib.error.HTTPError as e:
            code, data = e.code, e.read()
        with open(LOG, "a") as f:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
            f.write(json.dumps({"resp": code, "head": data[:200].decode(errors="replace")}, ensure_ascii=False) + "\n")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
http.server.ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
PY

# 上流は IP で渡す (mDNS 名だと Python 側で IPv6 を掴んで遅い)。dscacheutil は
# IPv6 を先に出すので、ip_address 行だけを取る (先頭を素直に拾うと IPv6 を掴む)。
IP=$(dscacheutil -q host -a name spark-head.local | awk '/^ip_address:/{print $2; exit}')

# 起動前に 8888 の空きを確かめる。塞がっていると ThreadingHTTPServer は即死し、
# それでも下の until はその別プロセスから 200 をもらって成立してしまう。
lsof -nP -iTCP:8888 -sTCP:LISTEN && { echo "8888 が塞がっている"; exit 1; }
: > /tmp/ccsp.log   # 追記されるので毎回空にする (前回 run の行を拾わないため)

python3 /tmp/spark-proxy.py "http://$IP:8888" /tmp/ccsp.log 8888 &
# 待受を待つ。sleep で決め打ちすると間に合わず、ccsp が「配信中: (空)」で落ちる
until curl -fs -o /dev/null -m 2 http://127.0.0.1:8888/health; do sleep 1; done

# ccsp 側: LAN のホスト名を差し替える。ポートは _spark_lan_url が 8888 を
# 直書きするので、プロキシも 8888 に立てるしかない (別ポートだと ccsp は
# 本物へ行き、プロキシは何も記録しないまま待機する)。
CCSP_LAN_HOST=127.0.0.1 ccsp lan -p "1+1?"

# ocsp 側: opencode 本体を直に起動して baseURL だけ差し替える。ocsp 関数は
# ~/.config/opencode/opencode.json を直読みして起動前プローブを打つので、
# ラッパ経由ではその経路が切り替わらない (OPENCODE_CONFIG_CONTENT は opencode
# 本体の設定を最後に上書きする公式の環境変数で、グローバル設定にマージされる)。
OPENCODE_CONFIG_CONTENT='{"provider":{"spark":{"options":{"baseURL":"http://127.0.0.1:8888/v1"}}}}' \
  opencode run --model spark/qwen3.8-flash-next "1+1?"

grep -E 'output_config|reasoning_effort|resp' /tmp/ccsp.log
```

**陽性対照を必ず取る** (不変則 4)。異常な値を入れたときに記録が反応することの確認で、これが取れて初めて、既定で記録された `xhigh` が本当に送信経路を通っていると言える。**`CCSP_LAN_HOST` を落とさない** — 落とすと本物のサーバへ直行し、400 は端末に出てもログには 1 行も残らないので、この対照は成立しない。

```bash
CCSP_LAN_HOST=127.0.0.1 CCSP_EFFORT=high ccsp lan -p "1+1?"
# ログ上で 2 行が隣接することを確認する:
#   {"path": "/v1/messages…", … "output_config": {"effort": "high"}}
#   {"resp": 400, … "Unexpected reasoning effort high…"}
grep -E 'output_config|resp' /tmp/ccsp.log | tail -2
```

**この手順は 1 回の Bash 呼び出しで流し切る** (または `{{@background-run}}`)。Claude のハーネスは呼び出しごとにシェルが変わるので、`&` で起動したプロキシが次の呼び出しまで残る保証が無い。

**使い終わったらプロキシを止める** (`pkill -f spark-proxy.py`)。**素の `ccsp` / `ocsp` は止め忘れても本物に届く** (プロキシは `127.0.0.1` にしか bind せず、既定の宛先は `spark-head.local`)。実害は 2 つで、`CCSP_EFFORT` / `CCSP_LAN_HOST` を export したシェルだけが中継を向き続けることと、野良プロセスとログが残り続けることである。**`ccsp off` はこの 2 つの変数を消さない**ので手で `unset` する。停止後は `curl -s http://spark-head.local:8888/v1/models` が配信名を返すことまで確かめる。
