---
# 常駐読み込みさせないためのマーカー (このパスにマッチするファイルは存在しない)。
# 本ファイルは必要になったときに Read で参照する。
paths:
  - "__read-on-demand-only__"
---

# DGX Spark 2 台構成 (自宅のローカル LLM クラスタ)

- 種別: 環境リファレンス
- 対象読者: 別セッション・別マシンで作業する Claude
- 最終確認: 2026-09-17 (Codex (`cxsp`) の節と、`/v1/responses` にまたがる記述)
- 他の節の確認日: 2026-09-06 (一部は 2026-09-09 / 2026-09-10 / 2026-09-15 に再確認。2026-09-15 は「系統の切り替え」「sparkDash の `workerLabel` を直す」「重みの置き場所 (3 系統)」「メモリの使われ方」「障害時」「既知の制約」8・10・11)。「実測値」節の性能値のみ 2026-09-05。日付は表のセルか本文に書いてある

自宅に NVIDIA DGX Spark (GB10) が 2 台あり、vLLM の TP=2 (tensor parallel、2 台に重みを分割する並列方式) でローカル LLM を常時サービングしている。Mac の Claude Code (`ccsp`) / OpenCode (`ocsp`) / Codex (`cxsp`) の 3 つからバックエンドとして使える。

**レシピは 3 系統ある。** DeepSeek 系 (Vision-Exp)、Qwen 系 (Qwen3.8-Flash-Next)、V4.1 EXL3 系 (DeepSeek-V4.1-Flash EXL3 2.9bpw) で、ポート 8888 と GPU を共有するため**同時には 1 つしか配信できない**。2026-09-17 時点の配信は V4.1 EXL3 系である。系統ごとにスクリプト名・コンテナ名・設定ファイル名が違うので、作業前にどれが動いているかを確かめる (`ssh -n spark-head 'docker ps --format "{{.Names}}" | grep -E "vllm|dsv41"'`。**`--filter name=vllm` だけでは V4.1 EXL3 系のコンテナ `dsv41-exl3-head` を拾わない**)。

**dotfiles リポジトリの所在は `~/dev/github.com/skanehira/dotfiles` である。** 本書でリポジトリ相対で書くパスはすべてここを基点とする。**本書の表で「—」は該当なしを意味する。**

## 用語・成果物一覧

| 名前 | 意味 | 定義箇所 | 生成者 | 消費者 |
| --- | --- | --- | --- | --- |
| DeepSeek 系 / Qwen 系 / V4.1 EXL3 系 | レシピの系統。スクリプト名・コンテナ名・設定ファイルが異なり、同時には配信できない | 冒頭の「レシピは 3 系統ある」 | — | 人 |
| head / worker | TP=2 の rank 0 / rank 1。head だけが HTTP API を持ち、worker は headless | `.env.dspark` の `WORKER_HOST` | 人 (初期構築) | 起動スクリプト |
| レシピ | 上流が配布する compose + シェルスクリプト一式 | head の `~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark/` | 上流 (`git clone`) | 人 |
| Vision-Exp | `deepseek-ai/DeepSeek-V4-Flash-Vision-Exp` の略。画像入力が使える。DeepSeek 系のモデル | 「サービングの構成 (DeepSeek 系)」 | 上流のチェックポイント | vLLM |
| Qwen3.8-Flash-Next | `nvidia/Qwen3.8-Flash-Next-NVFP4` の略。他の 2 系統とは別レシピで配信する | 「Qwen3.8-Flash-Next」 | 上流のチェックポイント | vLLM |
| 0731 | `deepseek-ai/DeepSeek-V4-Flash-0731` の略。**配信候補ではない。** 重みと専用 worktree がディスクに残っているだけ | 「触らないもの」 | — | — |
| RoCE | RDMA over Converged Ethernet。QSFP ポート上でノード間の NCCL 集団通信を運ぶ | `.env.dspark` の `NCCL_IB_HCA` | NetworkManager の接続 `roce` / `roce2` | vLLM (NCCL) |
| NCCL | NVIDIA Collective Communications Library。TP=2 のランク間通信を担う | 本表 | — | vLLM |
| DSpark | チェックポイント内蔵の投機デコード。draft 用の別モデルを持たない。DeepSeek 系と V4.1 EXL3 系が使う | vLLM の CLI フラグ `--speculative-config` | DeepSeek 系はレシピの compose、V4.1 EXL3 系はレシピの `.env` の `SPEC_METHOD` / `DSPARK_TOKENS` から `start.sh` | vLLM |
| MTP | multi-token prediction。1 ステップで出す draft トークン数。**キー名が系統で違う** (DeepSeek 系 = `.env.dspark` の `MTP_NUM_TOKENS` / Qwen 系 = Qwen レシピの `.env` の `MTP_NUM_SPECULATIVE_TOKENS` / V4.1 EXL3 系は DSpark の行の `DSPARK_TOKENS`) | 各系統の設定ファイル | 人 | vLLM |
| `nvfp4_ds_mla` / `fp8_ds_mla` | MLA (multi-head latent attention) の KV キャッシュを 4bit / 8bit で保持する形式。前者は DeepSeek 系、後者は V4.1 EXL3 系 | vLLM の CLI フラグ `--kv-cache-dtype` | DeepSeek 系はレシピの compose が指定、V4.1 EXL3 系は vLLM が自分で選ぶ | vLLM |
| TTFT | time to first token。送信から最初のトークンが返るまでの時間。ほぼ prefill の所要時間 | 本表 | `~/spark-bench/bench.py` | 「L1」表 |
| 受理率 | 投機デコードが出した draft トークンのうち採用された割合。decode 速度をほぼ決める | 本表 | vLLM の `/metrics` | 「L2 / L3」表・「遅いと感じたときに疑う順序」4 |
| L1 / L2 / L3 | 計測の層。L1 = サーバを直叩き (クライアント無し) / L2 = Claude Code 経由 / L3 = OpenCode 経由 | 本表 | `bench.py` (L1) / `snap.py` (L2・L3) | 「実測値」節 |
| `ccsp` | Claude Code を本クラスタに向けて**起動する**ところまで行う zsh 関数 | `zsh/functions/claude-deepseek.zsh` | dotfiles | 人 |
| `ccds` | 同じく DeepSeek 本家 API へ向けて**起動する**ところまで行う zsh 関数。`agents/bindings/claude/settings.deepseek.json` を `--settings` で渡す。**予約語は第 1 引数の `off` だけ**で、それ以外の語はそのまま `claude` に渡る (`off` の後ろに書いた引数は無視される。`ccds off` で Anthropic に戻す)。`ccsp` と環境変数 `ANTHROPIC_AUTH_TOKEN` を共有する (入る値は別) | 同上 | dotfiles | 人 |
| `CCSP_LAN_HOST` | LAN 側ホスト名を上書きするシェル変数。`CCSP_LAN_HOST=<IP> ccsp` と前置きしても export しても効く。**名前は `ccsp` 由来だが 3 つのクライアントが共有する** | `zsh/functions/spark-common.zsh` | 人 | `ccsp` / `ocsp` / `cxsp` |
| `ocsp` | OpenCode を本クラスタに向けて起動する zsh 関数。API キーも alias も持たない。接続先は `ccsp` と同じく到達する方を選ぶ | `zsh/functions/opencode-spark.zsh` | dotfiles | 人 |
| `cxsp` | Codex を本クラスタに向けて起動する zsh 関数。設定ファイルを置かず、`codex` の `-c` で 8 キーを起動ごとに注入する。API キーも alias も環境変数も持たない | `zsh/functions/codex-spark.zsh` | dotfiles | 人 |
| `spark-common.zsh` | 3 つのクライアントが共有するヘルパー。短縮名の表・接続先の URL とプローブ・`/v1/models` の照会・reasoning effort の表を持つ | `zsh/functions/spark-common.zsh` | dotfiles | `ccsp` / `ocsp` / `cxsp` |
| `_spark_models` | `/v1/models` を引いて「配信名 max_model_len」の行を返すヘルパー。Bearer が空なら Authorization ヘッダ自体を送らない | `zsh/functions/spark-common.zsh` | dotfiles | 3 クライアントの配信前検査と `status` |
| `_spark_effort` | 配信名から reasoning effort を決める関数。`/v1/models` は受理される effort を返さないので、サーバに聞けない値としてここだけが表を持つ | `zsh/functions/spark-common.zsh` | dotfiles | `ccsp` / `cxsp` (`ocsp` は `opencode.json` の静的値を使う) |
| `CCSP_MODEL` | `ccsp` が使う配信名を保持するシェル変数。短縮名に無いモデルを渡すときだけ使う。**未設定が既定で、その場合は配信中のモデルを採る** | `zsh/functions/claude-deepseek.zsh` | 人 | `ccsp` |
| `OCSP_MODEL` | 同じく `ocsp` 用。`ocsp model` が書き換える。**未設定が既定で、その場合は配信中のモデルを採る** | `zsh/functions/opencode-spark.zsh` | `ocsp model` | `ocsp` |
| `CXSP_MODEL` | 同じく `cxsp` 用。書き換えるサブコマンドは持たない (`ocsp model` に相当するものが無い)。**未設定が既定で、その場合は配信中のモデルを採る** | `zsh/functions/codex-spark.zsh` | 人 | `cxsp` |
| `CCSP_OUTPUT_RESERVE` | `max_model_len` から差し引く出力用の余白 (トークン数)。既定は 32,768 | `zsh/functions/claude-deepseek.zsh` | 人 | `ccsp` |
| 短縮名 | モデル名の短縮。`qwen` / `vision` / `v41` の 3 つで、`SERVED_MODEL_NAME` に展開する (`v41` → `DeepSeek-v4.1-Flash-EXL3`)。**モデルとして渡せるのはこの 3 語だけで、短縮名にも `lan` / `ts` にも当たらない語はクライアント本体の引数 (`ocsp` ではサブコマンド検知) に回る。** 配信名を直に指定する経路は `CCSP_MODEL=` / `CXSP_MODEL=` / `ocsp model <名前>` の 3 つ | `spark-common.zsh` の `_spark_served_name` と各クライアントの `case` ガード | dotfiles | `ccsp` / `ocsp` / `cxsp` |
| `lan` / `ts` | 接続先を強制する選択語。省略時は `/health` のプローブで決まる。短縮名とは順不同で並べられるが、**予約語 (`status` / `model` / `off`) とは併用できない** (予約語は第 1 引数でしか効かず、`ocsp lan status` の `status` はクライアント本体の引数に回る。`cxsp` の予約語は `status` / `-h` (`--help` / `help` を含む) で同じ制約を持つ) | `spark-common.zsh` の `_spark_lan_url` / `_spark_ts_url` と各クライアントの引数解釈 | dotfiles | `ccsp` / `ocsp` / `cxsp` |
| 配信前検査 | クライアントが起動前に `/v1/models` を引いて、要求されたモデルが配信されているかを確かめる段。`ccsp` は `--settings` 注入の前、`ocsp` は接続先の決定後、`cxsp` は `-c` の組み立ての前に行う | `zsh/functions/claude-deepseek.zsh` / `zsh/functions/opencode-spark.zsh` / `zsh/functions/codex-spark.zsh` | — | `ccsp` / `ocsp` / `cxsp` |
| `--` (解除語) | 解釈の打ち切り語。`ccsp` は `lan` / `ts` / 短縮名の認識領域 (`while` ループ) に出た `--` をどこでも消費し、`ocsp` は先頭出た 1 個だけ消費する (短縮名のうしろに置いた `--` は opencode に素で渡る非対称)。いずれも以降を `claude` / `opencode` にそのまま渡す。予約語 (`ccsp` の `off` / `status` / `-h`、`ocsp` の `model` / `status` / `help`) や `ocsp` のサブコマンド検知を迂回できる。`--` 自体はクライアント本体に渡さない (渡すと option 解析の終端として後続の語を別枠に取り扱うため)。`ccsp --` は配信前検査と `--settings` 注入を通過するが、`ocsp --` は接続先の上書きも配信前検査も `--model` 注入も通らない (素の `opencode` と同じになる)。**`cxsp` は `ccsp` と同型**で、認識領域に出た `--` をどこでも消費し、配信前検査と `-c` の注入は通る (予約語は `status` / `-h` / `--help` / `help`) | `claude-deepseek.zsh` と `opencode-spark.zsh` と `codex-spark.zsh` の引数解釈 | dotfiles | `ccsp` / `ocsp` / `cxsp` |
| `settings.spark.json` | Claude Code 側の設定の土台。**モデル名・コンテキスト上限・reasoning effort は持たない**ので、モデルを増やしても変更点は無い | `agents/bindings/claude/settings.spark.json` | dotfiles | `ccsp` (生成の入力) |
| `settings.deepseek.json` | `ccds` が `--settings` で渡す DeepSeek 本家 API の設定。**主なキーは接続先 (`env.ANTHROPIC_BASE_URL`)・モデル名 5 キー・`CLAUDE_CODE_EFFORT_LEVEL` (静的な `max`)・`fallbackModel` (既定モデルが使えないときの退避)**。`env` の残り 2 キーと `enabledPlugins` は `settings.spark.json` と共通で、**`ccsp` と違い起動ごとの生成をしない** (配信名に追従する必要が無いため) | `agents/bindings/claude/settings.deepseek.json` | dotfiles | `ccds` |
| `CLAUDE_CODE_EFFORT_LEVEL` | Claude Code の推論の深さ。**`ccsp` が配信名から決めて起動のたびに注入する** (`qwen3.8-flash-next` → `xhigh` / `DeepSeek-v4.1-Flash-EXL3` → `max` / それ以外 → `high`)。受け付ける値は配信中のモデルが決める (`ccsp` から渡せるのは、Qwen 配信中なら `low` / `medium` / `xhigh`、V4.1 EXL3 配信中なら `low` / `high` / `xhigh` / `max`。`none` はどちらでも `/v1/messages` のスキーマが弾く → 「Qwen の reasoning effort の語彙」と「V4.1 EXL3 の reasoning effort の語彙」。DeepSeek 系は未確認 → 確かめ方は「依拠する外部事実」の reasoning effort の行) | `zsh/functions/spark-common.zsh` の `_spark_effort` | `ccsp` / `ccds` (`settings.deepseek.json` の静的な `max` を `--settings` で渡す) | `claude` 本体 (`/v1/messages` の `output_config.effort` として送る) |
| `CCSP_EFFORT` | `_spark_effort` の決定を上書きするシェル変数。**未設定が既定** (Qwen 配信中に入れてよいのは `low` / `medium` / `xhigh`、V4.1 EXL3 配信中は `low` / `high` / `xhigh` / `max`)。語彙に無い値を入れると最初のリクエストが 400 で落ちる | `zsh/functions/claude-deepseek.zsh` | 人 | `ccsp` |
| `CXSP_CONTEXT_MAX` | `cxsp` が `model_context_window` に渡す値の上限 (トークン数)。既定 500,000。**サーバの `max_model_len` がこれを超えたら頭打ちにする** | `zsh/functions/codex-spark.zsh` | 人 | `cxsp` |
| `CXSP_EFFORT` | 同じものを `cxsp` 側で上書きするシェル変数。**未設定が既定。** V4.1 EXL3 配信中に `/v1/responses` で入れてよいのは `low` / `high` / `xhigh` / `max` の 4 語で、`medium` は 400 になる (2026-09-17 実測 →「V4.1 EXL3 の reasoning effort の語彙」)。**Qwen 系と DeepSeek 系のこの経路は未実測** | `zsh/functions/codex-spark.zsh` | 人 | `cxsp` |
| `reasoningEffort` | `ocsp` 側の同じもの。`opencode.json` の `provider.spark.models.<配信名>.options` が**モデルごとに静的に持つ** (`qwen3.8-flash-next` = `xhigh` / `deepseek-v4-flash-vision-exp` = `high` / `DeepSeek-v4.1-Flash-EXL3` = `max`)。省略するとクライアントは送らず、モデルのテンプレート既定が効く | `agents/bindings/opencode/opencode.json` | dotfiles | `opencode` 本体 (`/v1/chat/completions` の `reasoning_effort` として送る) |
| `~/.cache/ccsp/settings.json` | `ccsp` が起動のたびに `settings.spark.json` へモデル名 5 キー (`ANTHROPIC_MODEL` と `ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU,FABLE}_MODEL`)・`CLAUDE_CODE_MAX_CONTEXT_TOKENS`・`CLAUDE_CODE_EFFORT_LEVEL`・`fallbackModel` を注入して書き出す実ファイル | Mac の `~/.cache/ccsp/settings.json` (`XDG_CACHE_HOME` があればその下) | `ccsp` | `claude` 本体 (`--settings` で渡される) |
| `opencode.json` | OpenCode の `provider.spark` (接続先・モデル宣言・モデルごとの `reasoningEffort`)。**キーは持たない。** 認証を戻すときだけ `options.apiKey` を足す (値は `{file:…}` / `{env:…}` で外部へ逃がす)。トップレベルの `permission` は OpenCode のツール実行の承認方針で、`allow` は全ツール自動承認を意味する。dotfiles 管理。`~/.config/opencode/` の他のファイル (`node_modules` / `package.json` / `package-lock.json` / `.gitignore` など) は opencode 自身のもの。**`skills/` / `agents/` / `AGENTS.md` は `nix/modules/home/harness.nix` の生成物** | `agents/bindings/opencode/opencode.json` | dotfiles (`nix/modules/home/opencode.nix` が symlink) | `opencode` 本体 / `ocsp` |
| `tui.json` | OpenCode の TUI 設定 (keybinds / theme) | `agents/bindings/opencode/tui.json` | dotfiles (`nix/modules/home/opencode.nix` が symlink) | `opencode` 本体 |
| `_cxsp_config_args` | `cxsp` が `codex` に渡す `-c` 8 キーを組み立てるヘルパー。1 行 1 キーで返す | `zsh/functions/codex-spark.zsh` | dotfiles | `cxsp` |
| `agents/bindings/codex/config.toml` | Codex の共通設定。`/etc/codex/config.toml` (system レイヤー) として配られる。**`cxsp` からは触らない** — `model` / `model_context_window` / `model_reasoning_effort` / `web_search` は `-c` が上書きする | `agents/bindings/codex/config.toml` | dotfiles (mac は `nix/modules/darwin/codex.nix` の `environment.etc`) | `codex` 本体 |
| `patch_responses_content_parts.py` | head のパッチ。`/v1/responses` が送る `input_text` パーツを配信中のイメージの tokenizer に受けさせる。**これが無いと `cxsp` だけが 400 で落ちる** (→「既知の制約」12 に全文) | head の `~/dsv41-local/` | 人 (dotfiles に控えは無く、制約 12 の全文が正本) | `start.sh` のパッチループ経由で head のコンテナ |
| `OPENCODE_CONFIG_CONTENT` | OpenCode がインライン JSON として読む環境変数。既存の設定に `options` の中まで再帰的にディープマージされる。`ocsp` はこれで `baseURL` の 1 キーだけを起動ごとに差し替える (前置代入なのでシェルには残らない) | `_ocsp_config_override` (中身) と `ocsp` の起動 2 か所 (変数名)。いずれも `zsh/functions/opencode-spark.zsh` | `ocsp` | `opencode` 本体 |
| `_ocsp_resolve` | `opencode.json` の値に書いた `{file:~/…}` / `{env:…}` を解くヘルパー。認証を戻したときの `apiKey` を平文で置かずに済ませる (opencode 本体も同じ記法を解くので、`ocsp` の配信前検査と本体の双方に同じ値が届く) | `zsh/functions/opencode-spark.zsh` | dotfiles | `ocsp` |
| `/tmp/spark.key` | vLLM の Bearer トークンを平文で置いた作業ファイル。**head にだけ要る。`bench.py` 専用で、無認証の現在は中身が使われない。再起動で消える** | head の `/tmp/spark.key` | 人 (1Password から書き出す) | `bench.py` |
| `nv-gpu-clock-limit.service` / `nv-cpu-clock-limit.service` | 両ノードに手で置いた systemd unit 2 本。前者は GPU の SM クロックを 2,200 MHz にロックし、後者は X925 の `scaling_max_freq` を下げる (**後者はハードウェアのクロック上限を変えていない** → 「既知の制約」5)。dotfiles に控えが無い | 「既知の制約」4・5 (後者は unit 全文も) | 人 | systemd |
| `drs` | dotfiles の Nix 設定を Mac に適用する zsh alias | `nix/modules/home/zsh.nix` | dotfiles | 人 |
| `.env.dspark` | DeepSeek 系レシピの設定を集約した 1 枚。git 管理外 (`.gitignore` 済み) | head の `~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark/` | 人 (`.env.dspark.example` から複製) | 起動・停止・検証スクリプト |
| `PROJECT_NAME` | `docker compose` のプロジェクト名。コンテナ名 `deepseek-v4-flash-vllm-dspark-1` の接頭辞になる | 起動スクリプトの既定値 (`.env.dspark` のキーではない) | 起動スクリプト | `docker compose` |
| Qwen レシピ | Qwen3.8-Flash-Next を TP=2 で配信する別系統のレシピ。他の 2 系統とは別リポジトリ・別イメージ・別スクリプト名 | head の `~/Qwen3.8-Flash-Next-Dual-DGX-Sparks/` | 上流 (`git clone`) | 人 |
| `stop` / `start` | 本書で使う DeepSeek 系スクリプト (`stop-deepseek-v4-flash-dspark.sh` / `start-deepseek-v4-flash-dspark.sh`) の略記。**Qwen 系と V4.1 EXL3 系の `stop.sh` / `start.sh` とは別物** | 「起動と停止 (DeepSeek 系)」 | 上流 | 人 |
| `start.sh` / `stop.sh` | **Qwen レシピと V4.1 EXL3 レシピが同名で別々に持つ**スクリプト。Qwen 版は `--launch` で取得を飛ばして起動し、停止は `stop.sh`。V4.1 EXL3 版は引数なしで起動し、`stop` / `pack` / `status` / `logs` をサブコマンドで持つ (`stop.sh` は `start.sh stop` を呼ぶだけ)。本書では所属するレシピの節の中でだけ素の名前で書く | 「系統の切り替え」の表 | 上流 | 人 |
| `.env` | **Qwen レシピと V4.1 EXL3 レシピが同名で別々に持つ**設定 1 枚。DeepSeek 系の `.env.dspark` とは別物。本書では「Qwen レシピの `.env`」「V4.1 EXL3 レシピの `.env`」と書き分ける | head の `~/Qwen3.8-Flash-Next-Dual-DGX-Sparks/.env` / `~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks/.env` | 人 (前者は `.env.sample`、後者は `.env.example` から複製) | 各レシピのスクリプト |
| `vllm-fn` | Qwen レシピのコンテナ名。**head と worker で同名** | Qwen レシピの `start.sh` | `start.sh` | `docker` |
| DeepSeek-V4.1-Flash EXL3 | `deepseek-ai/DeepSeek-V4.1-Flash` を EXL3 2.9 bpw に量子化した `Mia-AiLab/DeepSeek-V4.1-Flash-EXL3-2.9bpw` の略。配信名は `DeepSeek-v4.1-Flash-EXL3`、短縮名は `v41`。画像入力は使えない。2026-09-15 時点の常用モデル | 「DeepSeek-V4.1-Flash EXL3」 | 上流のチェックポイント | vLLM |
| EXL3 | 推論ライブラリ ExLlamaV3 の量子化形式 (Cornell RelaxML の QTIP を簡略化した変種)。テンソルごとにビット数を変えられるので平均が 2.9 bpw のような端数になる。vLLM 本家は非対応で、V4.1 EXL3 レシピがイメージに後付けしている | 「DeepSeek-V4.1-Flash EXL3」の表 | 上流 | vLLM (レシピの overlay) |
| V4.1 EXL3 レシピ | DeepSeek-V4.1-Flash の EXL3 2.9bpw 量子化版を TP=2 で配信する別系統のレシピ。起動・停止・pack は `start.sh` のサブコマンドで行う | head の `~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks/` | 上流 (`git clone`) | 人 |
| `dsv41-exl3-head` / `dsv41-exl3-worker` | V4.1 EXL3 レシピのコンテナ名。**head と worker で名前が違う** | V4.1 EXL3 レシピの `start.sh` | `start.sh` | `docker` |
| Engram | DeepSeek-V4.1 の n-gram 埋め込み表 (layer 1 と 14)。**量子化されておらず、元チェックポイントの shard 47/48 から取る**。メモリには載せず、ファイルから行を読む | 「DeepSeek-V4.1-Flash EXL3」 | 上流のチェックポイント | vLLM (file-backed lookup) |
| slim dir | Engram の読み込みに要るファイル (shard 47 / 48 のハードリンク、Engram のキーだけに絞った index、`config.json` のコピー) だけを集めたディレクトリ。起動と pack のたびに作り直され、worker への rsync の元にもなる | head の `~/.cache/vllm-dsv41-flash-exl3/engram-src/` (「Engram の流れ」) | V4.1 EXL3 レシピの `scripts/prepare_engram_src.py` | pack / head のコンテナ / worker への rsync |
| `~/.cache/dsv41-image` | V4.1 EXL3 系のイメージを手で取ったときの blob 置き場 (9.1 GiB)。**読み込み済みなので消してよい** | 両ノードの `~/.cache/dsv41-image/` | 「導入手順」の「イメージを手で取る」 | なし (再読み込みのときだけ) |
| memguard | V4.1 EXL3 レシピの監視スクリプト (`scripts/memguard.sh`)。配信中に 1 秒ごとに `MemAvailable` を見て、2 回続けて `DSV41_MEM_GUARD_GIB` (既定 1.5 GiB) を下回ったノードのコンテナを kill する。**起動前のメモリ検査 (`memory headroom`、閾値 111.5 GiB) とは別物**。`.env` の `DSV41_MEM_GUARD=0` で無効 (上流既定) | V4.1 EXL3 レシピの `.env` と `scripts/memguard.sh` | `start.sh` (有効時のみ起動) | — |
| pack | Engram を rank ごとの行ファイル (`engram-l{1,14}-r<rank>of2.bin`、1 本 47.2 GiB) に書き出す操作。head が rank 0 の 2 本、worker が rank 1 の 2 本を作る。起動時に `/engram-packed` へ mount される | 両ノードの `~/dsv41-engram/` | `./start.sh pack` | vLLM |
| `resolve_snapshot.py` / `check-weights.sh` / `verify-weights.py` | Qwen レシピ**限定**の重み検証ツール 3 種。1 つ目はシャードの完全性だけを見る起動前の門、2 つ目は両ノードを見る入口、3 つ目は 1 ノードを HF の manifest と照合する本体 (2 つ目が各ノードで呼ぶ)。**`utility-spark-model-fetch` 同梱の `verify_shards.py` とは別実装で、配布中はスキル側、起動前はレシピ側を使う** | 「重みの検証」 | 上流 (`git clone`) | `start.sh` (1 つ目) / `check-weights.sh` (3 つ目) / 人 |
| `~/spark-bench` | 計測ハーネス一式 (主に `bench.py` / `snap.py` / `pc_probe.py` / `results/`)。**dotfiles 管理外で再作成手段が無い** | head の `~/spark-bench/` | 人 | 人 / Claude |
| `utility-spark-model-fetch` | 新しい重みを head で 1 回落として worker へ rsync するスキル。`scripts/verify_shards.py` を同梱する (head 上の同名ファイルは配布済みコピーで、正本はこちら) | `agents/skills/utility-spark-model-fetch/SKILL.md` | dotfiles | Claude |
| sparkDash | 監視・SSH 操作・Wake-on-LAN を持つ Web UI。**認証が無い** | head の `~/sparkDash/` | 上流 (`git clone`) | 人 (ブラウザ) |
| `workerLabel` | sparkDash が worker 行に表示するモデル名。**手書きの静的文字列で、実機を見ていない** | head の `~/sparkDash/config/sparks.json` | 人 | sparkDash の UI |
| `docker-compose.override.yml` | sparkDash のポーリング間隔などの上書き。未追跡 | head の `~/sparkDash/` | 人 | `docker compose` |
| `security-guidance` | Claude Code の公式プラグイン。Stop hook でレビュー用モデルを呼ぶ。`enabledPlugins` の完全キーは `security-guidance@claude-plugins-official` | `~/.claude/plugins/cache/claude-plugins-official/security-guidance/` | プラグイン marketplace | `settings.*.json` の `enabledPlugins` |
| 上流 | レシピの配布元。DeepSeek 系は [MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark](https://github.com/MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark)、Qwen 系は [MiaAI-Lab/Qwen3.8-Flash-Next-Dual-DGX-Sparks](https://github.com/MiaAI-Lab/Qwen3.8-Flash-Next-Dual-DGX-Sparks)、V4.1 EXL3 系は [MiaAI-Lab/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks](https://github.com/MiaAI-Lab/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks) | — | — | — |

## ハードウェアと OS

2 台とも同一構成である。

| 項目 | 値 |
| --- | --- |
| GPU | NVIDIA GB10 (CPU と共有する統合メモリ 128 GB。カタログ値で、`/proc/meminfo` は 121.7 GiB を返す) |
| CPU | 20 コアの big.LITTLE 構成。性能コア Cortex-X925 ×10 (cpu5-9・cpu15-19、`cpuinfo_max_freq` が返す素の上限 3,900 MHz)、効率コア Cortex-A725 ×10 (cpu0-4・cpu10-14、上限 2,808 MHz)。cpufreq は 1 コア 1 policy で、driver は `cppc_cpufreq`、governor は全コア `performance`。**X925 の `scaling_max_freq` は 2,808 MHz に下げてあるが、これはハードウェアのクロック上限を変えていない** (→ 「既知の制約」5)。2026-09-10 に両ノードで実測。確認コマンドは「依拠する外部事実」 |
| OS | Ubuntu 24.04.4 LTS / aarch64 |
| カーネル | `6.17.0-1032-nvidia` |
| ドライバ | `580.173.02` |
| ディスク | 3.7 TiB (使用 1,022 GiB / 空き 2.5 TiB。重み 4 チェックポイント分と V4.1 EXL3 系の pack を置いた状態。両ノードとも同じ。`df -h /` の実測、2026-09-15) |

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

**手で読み替えるのは `ssh` と手打ちの `curl` だけである。** HTTP 側の接続先は 3 つのクライアントが自分で選ぶ (`/health` をプローブして LAN → Tailscale の順に決める。実装は `spark-common.zsh` の `_spark_base_url` で、`ccsp` / `ocsp` / `cxsp` が共有する)。`opencode.json` の `baseURL` に書いてある LAN 側の値が効くのは、`ocsp` を通さず素の `opencode` を打ったときだけである。

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

LAN は 2.4 GHz の WiFi (両ノードとも freq 2437) で、リンク速度は 230〜290 Mbit/s と出る (`iw dev wlP9s9 link`、2026-09-15)。**それでも HuggingFace からのダウンロードは合計で約 8 MB/s しか出ない** (`du -sh` で 156〜158 GiB のモデルに約 5.5 時間)。2 本を同時に流すとこの 8 MB/s を分け合う。**律速が WiFi の実効速度か自宅のインターネット回線かは切り分けていない。** ノード間のコピーは RoCE を使えば 260〜605 MB/s 出る。

## 動いているもの

| サービス | 自宅 LAN | 出先 (Tailscale) | 認証 |
| --- | --- | --- | --- |
| vLLM (3 系統のどれでも) | `http://spark-head.local:8888` | `http://spark-head:8888` | **なし** |
| sparkDash | `http://spark-head.local:5555` | `http://spark-head:5555` | **なし** |

**8888 はどの系統でも無認証である。** Qwen 系はレシピが `--api-key` を渡さない。V4.1 EXL3 系はレシピの `.env` の `VLLM_API_KEY` がコメントアウトされたままで、起動ログの `auth` 行も `none (VLLM_API_KEY empty)` と出す (2026-09-15)。DeepSeek 系は `.env.dspark` の `VLLM_API_KEY` を `docker-compose.dspark.yml` がコンテナの環境変数に渡すしくみだが、**`VLLM_API_KEY` を空にしてある**ので素の無認証で上がる (2026-09-06 に確認)。Qwen 配信中の 8888 は、ヘッダ無しでも出まかせの Bearer でも `/v1/models` が 200 を返すことを実測した (同じ日に存在しないパスが 404 を返すことも確かめてある)。`/health` は 3 つのクライアントの到達判定 (`ccsp` / `ocsp` / `cxsp` の起動時と `status`) が、`/metrics` は sparkDash と `~/spark-bench/snap.py` がポーリングして消費する。**生成に使うパスはクライアントごとに違う**: `ccsp` が `/v1/messages`、`ocsp` が `/v1/chat/completions`、`cxsp` が `/v1/responses` である。**`/v1/responses` だけはサーバ側にパッチが要る** (→「既知の制約」12)。**接続先を強制した起動 (`ccsp lan` / `ocsp ts` / `cxsp lan`) はプローブを飛ばして `/v1/models` に直行する。`status` は接続先の選択とは無関係に両経路の `/health` を叩く。**

**したがってポート 8888 を信頼できないネットワークへ出さない。** sparkDash のポート 5555 と同じ扱いにする。

sparkDash は head の `~/sparkDash` に clone した [MiaAI-Lab/sparkDash](https://github.com/MiaAI-Lab/sparkDash) である。同梱の `docker-compose.yml` は編集せず、上書きは未追跡の `docker-compose.override.yml` に置く (`git pull` との衝突を避けるため)。反映・停止・更新は `~/sparkDash` で `docker compose up -d` / `down` / `pull` を打つ。**認証が無く tailnet の全端末から SSH 操作と Wake-on-LAN が可能なので、ポート 5555 を信頼できないネットワークへ出さない。**

### API キーの流れ

**現在はどのクライアントも API キーを使わない。** `ccsp` / `ocsp` / `cxsp` のいずれもキーを持たず、起動前に打つ `/v1/models` の照会も Bearer が空なら Authorization ヘッダ自体を送らない。**1Password が要るのは `ccds` (DeepSeek 本家 API) だけである。**

**`ccsp` には承知のうえの副作用がある。** `ANTHROPIC_AUTH_TOKEN` が空だと、Claude Code は自分が持っている**本物の Anthropic 認証情報**を `Authorization: Bearer` で `ANTHROPIC_BASE_URL` へ送る。宛先は自宅 LAN の Spark で経路は平文 HTTP なので、自宅に閉じている限り許容する方針である。**信頼できないネットワーク越しに使うときはダミー値を export してから打つ。** `ocsp` と `cxsp` にはこの経路が無い (`cxsp` は `env_key` を省くので Authorization ヘッダ自体を送らない)。

**DeepSeek 系を認証ありに戻すときは、サーバとクライアントの両方を直す。** 直し忘れた側で症状が変わる。**サーバだけ直すと 3 つのクライアントが `/v1/models` の 401 で起動前に止まる** (騒がしいので気づける)。**クライアントだけ直しても無認証のサーバは Bearer を無視して 200 を返すので、認証が効いていると誤認したまま運用が続く** (静かなので気づけない)。

1. サーバ側 — `.env.dspark` の `VLLM_API_KEY` に値を入れて `stop` → `start`
2. クライアント側 — `ccsp` の前に `ANTHROPIC_AUTH_TOKEN` を export し、`opencode.json` の `options` に `apiKey` を足し、`cxsp` には `model_providers.spark.env_key="SPARK_API_KEY"` の `-c` を 9 本目として足し、その環境変数を人が export する (`cxsp` は現在このキーを持たないので `-c` は 8 本 → 「Codex (`cxsp`)」)
3. **反映経路が 3 つで違う。** `ANTHROPIC_AUTH_TOKEN` はそのシェルで即時、`opencode.json` は `mkOutOfStoreSymlink` が効いている世代なら編集した瞬間から (2026-09-06 時点は効いている。**まだ store コピーを指している世代では `drs` を当てるまで反映されない。判定は `readlink -f` で行う** →「OpenCode (`ocsp`)」)、`cxsp` の 9 本目の `-c` は zsh 関数の編集なので `drs` と新しいシェルが要る
4. **効いたことを確認する** — `curl -s -o /dev/null -w '%{http_code}\n' http://spark-head.local:8888/v1/models` が **401** を返すこと。200 のままならサーバ側が直っていない (これは「依拠する外部事実」の 200 判定の陽性対照でもある)

**`bench.py` は無認証でもキー文字列を要求する。** `--key-file` か環境変数 `SPARK_KEY` のどちらも無いと起動時に exit する実装で、渡した値はそのまま `Authorization: Bearer` に載る。無認証のサーバはそれを無視するので、いまは中身が何でも通る。正本は 1Password の `op://Personal/DGX Spark vLLM API Key/credential` である。

```bash
op read 'op://Personal/DGX Spark vLLM API Key/credential' | ssh spark-head 'cat > /tmp/spark.key && chmod 600 /tmp/spark.key'
```

- **`/tmp` は再起動で消える。** 2026-09-06 時点では存在しない。`bench.py` を打つときに書き直す
- **`.env.dspark` の控えを作ったら使い終わりに消す。** `.gitignore` が拾うのは `.env.dspark` そのものだけなので、`.env.dspark.bak` のような名前は追跡対象に入りうる。キー行ごと公開リポジトリの clone にステージされる

### サービングの構成 (DeepSeek 系)

**この節は DeepSeek 系を配信しているときの話である。** Qwen 系の構成は「Qwen3.8-Flash-Next」、V4.1 EXL3 系の構成は「DeepSeek-V4.1-Flash EXL3」にある。**本書の「DeepSeek 系」は Vision-Exp のレシピだけを指し、同じ DeepSeek のモデルでも V4.1 EXL3 系を含まない。**レシピ名は DSpark だが、載せているチェックポイントは Vision-Exp である。値の出所はすべて `.env.dspark` (「KV キャッシュ」と「レシピの commit」の 2 行を除く)。

| 項目 | 値 |
| --- | --- |
| チェックポイント (`DSPARK_MODEL_OFFICIAL` / `DSPARK_REVISION`) | `deepseek-ai/DeepSeek-V4-Flash-Vision-Exp` @ `86f746b36186f0e567729a5c06a8c918caba82a9` |
| API 上のモデル名 (`SERVED_MODEL_NAME`) | `deepseek-v4-flash-vision-exp` |
| コンテキスト上限 (`MAX_MODEL_LEN`) | サーバ 1,048,576 トークン (ネイティブ。YaRN 不要) / Claude Code からは 1,015,808 (`ccsp` が出力用の余白 32,768 を引く) |
| 同時リクエスト上限 (`MAX_NUM_SEQS`) | 6 リクエスト。超過分はエラーにならずキューで待つ |
| 投機デコード (`MTP_NUM_TOKENS`) | DSpark、draft 6 トークン |
| メモリ確保率 (`GPU_MEMORY_UTILIZATION_TEXT`) | 0.835 (意味は「メモリの使われ方」) |
| KV キャッシュ | `nvfp4_ds_mla` (`.env.dspark` にキーは無く、`docker-compose.dspark.yml` が `--kv-cache-dtype` に直書きしている) |
| 既定の reasoning (`DEFAULT_THINKING`) | `low` (取りうる値: `off` / `low` / `high` / `max`。リクエスト単位の指定が優先する)。**この既定が効くのは effort を送らないクライアントだけである** — 3 つのクライアントは常に明示的に送り、`bench.py` も `chat_template_kwargs` で明示する。**リクエスト単位で受ける値の一覧は未確認** (確認コマンドは「依拠する外部事実」。DeepSeek 系を配信中でないと打てない)。**3 つのクライアントはこの系統に `high` を送る** (`ccsp` と `cxsp` は `_spark_effort` の既定、`ocsp` は `opencode.json` の `reasoningEffort`)。この値もこの表の語彙に合わせただけで実測していないので、DeepSeek 系に戻したら最初の 1 回で 400 が出ないことを確かめる |
| コンテナイメージ | `ghcr.io/anemll/dspark-vllm-gx10:0.1.1@sha256:a83948492cf13df455170fb42885f5ef4db54fefe0feff0f841ecbff464ac9d8` (DSpark ランタイムの配布元 Anemll) |
| レシピの commit | `f5665e8`。上流 `main` はここから先行している (件数と中身は「依拠する外部事実」の確認コマンドで見る。速い変化があるので本書に数を書かない) |

### 重みの置き場所 (3 系統)

DeepSeek 系と Qwen 系の重みは両ノードの `~/.cache/huggingface/hub/` にある。V4.1 EXL3 系だけは HF キャッシュを使わず、レシピのディレクトリに実ファイルで置く (置き場所は「DeepSeek-V4.1-Flash EXL3」節)。worker は NFS ではなくローカルコピーを持つ。値は `du -sh` の実測 (V4.1 EXL3 系の行は 2026-09-15、それ以外は 2026-09-06)。ディスク全体の使用量は「ハードウェアと OS」の表にある。

| チェックポイント | head | worker | 備考 |
| --- | --- | --- | --- |
| Vision-Exp | 158 GiB | 157 GiB | DeepSeek 系 |
| Qwen3.8-Flash-Next | 124 GiB | 124 GiB | Qwen 系 (「Qwen3.8-Flash-Next」節) |
| DeepSeek-V4.1-Flash EXL3 | 197 GiB (EXL3) + 190 GiB (Engram) + 95 GiB (pack) | 同じ | V4.1 EXL3 系。ほかにイメージの blob 9.1 GiB が両ノードの `~/.cache/dsv41-image/` に残っている (→ 用語表の `~/.cache/dsv41-image`) |
| DeepSeek-V4-Flash-0731 | 156 GiB | 156 GiB | **使わない。** 消していないだけで、起動手順は本書に無い |

**配信の候補は Vision-Exp、Qwen3.8-Flash-Next、DeepSeek-V4.1-Flash EXL3 の 3 つで、どれか 1 つだけが動く。** 3 系統はポート 8888 と GPU を共有するので同時に起動できない。0731 の重みは置いてあるだけで配信候補ではない (→「触らないもの」)。

### メモリの使われ方

GB10 は CPU と GPU が同じ物理メモリを共有する統合メモリ構成である。**`GPU_MEMORY_UTILIZATION_TEXT=0.835` は通常の GPU なら VRAM の 83.5% を指すが、ここではシステムメモリ全体の 83.5% を意味する。** 起動直後から 100 GiB 超が vLLM に確保されて `free` の残りが数 GiB になる (DeepSeek 系で 6〜8 GiB、Qwen 系の head は 1.3〜5.7 GiB) が、これは設定どおりの先取りであって、リークでも不足でもない。**V4.1 EXL3 系は仕組みが違う。** 確保率のキーを予算に使わず、重み (起動ログで 98.86 GiB) と KV プール (`KV_CACHE_MEMORY_BYTES` で固定した 2.5 GiB) を確保する。head の残りは 6.0〜6.5 GiB で、これは先取りではなく実際の余裕の少なさなので、扱いは「既知の制約」11 に従う。

**値は配信中の系統で変わる。** DeepSeek 系の列は 2026-09-06 の実測、Qwen 系の列は 2026-09-09 の再起動後に無負荷で採った値 (`MemAvailable` だけは 2026-09-06 の高負荷時からの幅)、V4.1 EXL3 系の列は 2026-09-15 の起動直後に短い生成を 2 回流した後の値である。

| 項目 | DeepSeek 系 head / worker | Qwen 系 head / worker | V4.1 EXL3 系 head / worker |
| --- | --- | --- | --- |
| 物理メモリ合計 | 121.7 / 121.7 GiB | 121.7 / 121.7 GiB | 121.7 / 121.7 GiB |
| vLLM の確保 | 101.4 / 101.4 GiB | 100.7 / 100.8 GiB | 103.5 / 103.5 GiB (`nvidia-smi` の 105,987 MiB) |
| `MemAvailable` | 6.1 / 7.5 GiB | 1.3〜5.7 / 5.6〜10.1 GiB | 6.0〜6.5 / 7.2〜7.5 GiB |
| swap 使用 | 3.9 / 2.9 GiB | 5.0 / 4.1 GiB | 4.7 / 4.7 GiB |

DeepSeek 系と Qwen 系は期待値 121.7 × 0.835 = 101.6 GiB の近傍に収まる (DeepSeek 系 101.4 GiB / Qwen 系 100.7 GiB)。V4.1 EXL3 系は確保率ではなく KV プールをバイト数で固定する方式なので、この式は当てはまらない (→「DeepSeek-V4.1-Flash EXL3」)。head の残りが worker より少ないのは、head だけがデスクトップセッション・sparkDash・tailscaled を抱えているためである。**Qwen 配信中の head の空きは負荷と稼働時間で 1.3〜5.7 GiB を動く** (2026-09-06 の高負荷時 1.3〜1.7 GiB / 2026-09-09 の再起動直後 5.7 GiB)。**これも先取りであって不足ではない。メモリを空けたくなったらプロセスを探す前にこの値を疑う。**

## 起動と停止 (DeepSeek 系)

**この節は DeepSeek 系の話である。** Qwen 系の起動・停止は「Qwen3.8-Flash-Next」節の「起動と判定 (Qwen 系)」、V4.1 EXL3 系は「DeepSeek-V4.1-Flash EXL3」節の「起動と判定」にある。系統をまたいで切り替える手順は「系統の切り替え」にある。

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
| `DSPARK_MAX_INFLIGHT_PREFILLS` | 同時に走らせる prefill の件数 | 1 | 2 | 上流の A/B (head の `~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark/docs/CLAUDE/ab-results-2026-09-03.md`) | **上流計測値**: 4 並列時の TTFT のばらつきが 11.9 秒 → 7.7 秒、単一利用時の初動が 4.9 秒 → 7.2 秒に悪化、集約スループットは有意差なし。自環境では未計測 |
| `DSPARK_ENABLE_SP_INDEXER` | 0 = 無効 / 1 = 有効 | 0 | 1 | 上流の最終構成に追従 | 自環境では未計測 |
| `DSPARK_ENABLE_DEEPGEMM_SM121_ALIAS` | 0 = 無効 / 1 = 有効 | 0 | 1 | 上流の最終構成に追従 | 自環境では未計測 |

**この差分を自分で取り直すときは正規表現に注意する。** `grep -E '^[A-Z_]+='` はキー名に数字を含む `DSPARK_ENABLE_DEEPGEMM_SM121_ALIAS` を落とす (90 行中 75 行しか拾わない)。`^[A-Za-z0-9_]+=` を使う。同様に、キー行を伏せるための `grep -vi token` は `MTP_NUM_TOKENS` も巻き込む。

## モデルの追加と切り替え

**同じレシピの中でモデルを 1 つ足すときに触るのは次の 6 か所である** (Qwen や V4.1 EXL3 のように別系統のレシピごと足す場合は、これに加えて clone・`.env`・イメージ取得が要る。V4.1 EXL3 系ではさらに Engram の取得と pack が要った → 「DeepSeek-V4.1-Flash EXL3」の「導入手順」)。

1. **重みを両ノードに配る** — `utility-spark-model-fetch` スキル (下記)
2. **短縮名を足す** — **表 1 か所では足りず、動作に効くのは計 7 か所。** `spark-common.zsh` の `_spark_served_name` の展開表に 1 か所、3 クライアントの引数解釈ループ (接続先の `lan` / `ts` と並んで `qwen|vision|v41)` を消費する `case`) に 3 か所、3 クライアントの `-h` の usage に 3 か所。**`case` ガードに足さないと、その語は短縮名として認識されずクライアント本体の引数に回る** (`claude` へのプロンプトとして無言で渡ってしまう)。加えて**表示だけの列挙が 4 か所**ある (`claude-deepseek.zsh` と `codex-spark.zsh` の冒頭のコメント、`ocsp` の usage 本文とモデル名不足のエラー文)。動作は変わらないが、直さないと案内が古いまま残る
3. **reasoning effort をモデルごとに決める** — `spark-common.zsh` の `_spark_effort` の `case` (`ccsp` と `cxsp` が共有する) と、次項で足す `opencode.json` の宣言の `options.reasoningEffort` の 2 か所。**受け付ける語彙はモデルのチャットテンプレートが決めるので、他のモデルの値を流用しない** (確かめ方は「依拠する外部事実」の reasoning effort の行)。`_spark_effort` に足さなければ既定の `high` が送られ、それを受けないモデルでは最初のリクエストが 400 で落ちる
4. **`agents/bindings/opencode/opencode.json` の `provider.spark.models` に宣言を足す** — 宣言の無いモデルは OpenCode が拒否する
5. **`drs` と新しいシェル** — zsh 関数は Nix store 経由なので、これを踏まないと古い定義が動き続ける
6. **sparkDash の `workerLabel`** — 手書きの静的文字列なので配信を切り替えたら直す (→「sparkDash の `workerLabel` を直す」)

`agents/bindings/claude/settings.spark.json` は**触らない**。モデル名・コンテキスト上限・reasoning effort のいずれも持たず、`ccsp` が配信名から決めて注入するので、モデルが増えても変更点は無い。

**HF キャッシュに置く形の新しい open-weight を入れるときは `utility-spark-model-fetch` スキルを使う。** V4.1 EXL3 系はこの対象外で、レシピ直下に実ファイルで取り、worker へのコピーは `start.sh` の rsync が作る (→「導入手順」)。 素直にレシピ同梱の `prepare-dspark-model-cache.sh` を使うと worker でも HuggingFace から再ダウンロードして同じ重みを 2 回落とすことになる。head で 1 回落として RoCE 経由で rsync すれば転送は 5〜8 分で済む。所有権の修正・シャードの検証・監視コマンドの落とし穴はスキル側に書いてある。

### 系統の切り替え

**系統を切り替えるときは、配信中の系統を止めてから目的の系統を起動する。** 停止と起動のコマンドは系統ごとに違う。どれも head の上で打つ。

| 系統 | 停止 | 起動 | 起動の判定 | `workerLabel` に入れる値 |
| --- | --- | --- | --- | --- |
| DeepSeek 系 | `cd ~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark && ./stop-deepseek-v4-flash-dspark.sh` | `cd ~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark && ./start-deepseek-v4-flash-dspark.sh` | 「起動と停止 (DeepSeek 系)」の 2 段 | `deepseek-v4-flash-vision-exp` |
| Qwen 系 | `cd ~/Qwen3.8-Flash-Next-Dual-DGX-Sparks && ./stop.sh` | `cd ~/Qwen3.8-Flash-Next-Dual-DGX-Sparks && ./start.sh --launch` | 「起動と判定 (Qwen 系)」の 3 段 | `qwen3.8-flash-next` |
| V4.1 EXL3 系 | `cd ~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks && ./start.sh stop` (同じディレクトリの `./stop.sh` も同じ動作) | `cd ~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks && ./start.sh` (Claude から打つ形は「起動と判定」) | 「DeepSeek-V4.1-Flash EXL3」の「起動と判定」の 3 段 | `DeepSeek-v4.1-Flash-EXL3` |

手順は次の 5 段である。

1. **稼働中のリクエストを確かめる** — `curl -s http://spark-head.local:8888/metrics | grep -E '^vllm:num_requests_(running|waiting)\{'` が両方 0。Mac 側は稼働中の `claude` を終了して `ccsp off` で退避し、**`CCSP_EFFORT` / `CXSP_EFFORT` を export していたら `unset` する** (語彙は系統で違うので、残すと切り替え先で 400 が続く → 「既知の制約」7)
2. **配信中の系統を止める** — 表の「停止」
3. **止まったことを確かめる** — **停止コマンドの exit code は成否を表さない** (V4.1 EXL3 系の `stop` は worker への ssh が失敗しても「stopped.」と出して exit 0 で終わる)。両ノードで次が 0 行であることを見る (worker は「worker に入る」節の入れ子 ssh で同じものを打つ)

   ```bash
   docker ps --format '{{.Names}}' | grep -E 'vllm|dsv41'
   ```

   V4.1 EXL3 系を起動するなら、加えて両ノードの `grep MemAvailable /proc/meminfo` が 111.5 GiB 以上であること
4. **目的の系統を起動して判定する** — 表の「起動」と「起動の判定」
5. **sparkDash の `workerLabel` を表の値に直す** — 次の小節。稼働中だった `ccsp` / `ocsp` / `cxsp` のセッションは起動し直す

**DeepSeek 系に戻したら effort を 1 回確かめる。** 3 つのクライアントがこの系統に送る `high` はレシピの `DEFAULT_THINKING` の語彙に合わせただけで実測していないので、最初の起動で `Unexpected reasoning effort` が出ないことを見る (出たら `_spark_effort` と `opencode.json` の値を直す → 「Qwen の reasoning effort の語彙」)。

**先に相手系統を停止する。** ポート 8888 を共有するうえ、起動側の事前検査が拒否する。Qwen 系は `REQUIRE_IDLE_GPU=true` がどちらかのノードで GPU を掴むプロセスを見つけた時点で止まる。V4.1 EXL3 系は、**どちらか一方のノードでも** `MemAvailable` が 111.5 GiB に届かなければ止まる (閾値は、レシピの `scripts/weight_budget.py` が safetensors の index から見積もる 1 ランク分の重み 99.5 GiB に、余裕 `DSV41_BOOT_MARGIN_GIB` の既定 12 GiB を足した値。見積りが取れないと警告だけ出して検査を飛ばす)。**停止コマンドを取り違えると相手系統のコンテナは消えないので、「止めたつもり」で次の起動が拒否される。**

### sparkDash の `workerLabel` を直す

配信モデルを切り替えたら必ず打つ。**実機を見ずに表示するだけの手書き文字列なので、直さないと worker 行が古いモデル名のままになる。** ファイルは root 所有なのでコンテナ経由で書く。`~/sparkDash/config` は `/app/config` に bind mount されているので、編集はコンテナを作り直しても残る。

**ファイルを書き換えただけでは画面は変わらない。** sparkDash のサーバは `sparks.json` を起動時に読んでメモリに持つので (`~/sparkDash/server/sparks/SparkRegistry.js`)、書き換えた後に `docker restart sparkDash` で読み直させる。確認はファイルではなく API の応答で行う (2026-09-15 確認)。

下のコマンドの `DeepSeek-v4.1-Flash-EXL3` を、配信中の `SERVED_MODEL_NAME` に差し替えて使う。

```bash
ssh -n spark-head "docker exec sparkDash node -e \"const f='/app/config/sparks.json',fs=require('fs');const j=JSON.parse(fs.readFileSync(f));j.sparks.find(s=>s.role==='worker').workerLabel='DeepSeek-v4.1-Flash-EXL3';fs.writeFileSync(f,JSON.stringify(j,null,2))\""
ssh -n spark-head 'docker restart sparkDash'
ssh -n spark-head 'curl -s http://127.0.0.1:5555/api/sparks' | python3 -c 'import json,sys; d=json.load(sys.stdin); d=d.get("sparks",d) if isinstance(d,dict) else d; w=[s["workerLabel"] for s in d if s.get("role")=="worker"]; print(w); sys.exit(0 if w==["DeepSeek-v4.1-Flash-EXL3"] else 1)'   # exit 0 で合格。期待値も書き込んだ値に差し替える
```

クライアント側 (`ccsp` / `ocsp` / `cxsp`) の設定変更は要らない。**いずれも `/v1/models` を見て配信中のモデルを採る。** ただし効くのは次に起動する分からで、稼働中のセッションは起動時のモデル名を送り続けるので起動し直す (「既知の制約」7 の退避手順)。

### Qwen3.8-Flash-Next (別系統のレシピ)

**他の 2 系統とは別リポジトリ・別イメージ・別スクリプト名である。** 混同すると停止スクリプトが効かない。2026-09-06 に配置・起動・`ccsp` / `ocsp` からの疎通まで確認した (`cxsp` の `/v1/responses` はこの系統では未試行 → 下の「使える API」) (`ocsp` は `drs` 未適用のため検証用の `HOME` に設定を置いて確認した)。2026-09-09 の更新後に起動の 3 段判定と reasoning effort の語彙を取り直しており、クライアント 2 つからの疎通はそのとき再確認していない。

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
| 既定の reasoning | `xhigh` (`.env` に該当キーが無く、チャットテンプレートの既定が効く)。**2 経路 (`ccsp` の `/v1/messages` と `ocsp` の `/v1/chat/completions`) から使えるのは `low` / `medium` / `xhigh` の 3 つ。`high` と `max` はどちらの経路でも 400 になる** (詳細は直下の「Qwen の reasoning effort の語彙」) |
| コンテナイメージ | `vllm/vllm-openai:qwen38-flash-next` (Id `sha256:d464f3b466fa9c45ddbff8a812e80564503b6879a9fd95c1a47514f3f0df5a4a`、20.6 GB、arm64)。**両ノードに配置済み** |
| コンテナ名 | `vllm-fn` (head と worker で同名。`start.sh` が付ける) |
| 追加の vLLM 引数 (`EXTRA_VLLM_ARGS`) | 未設定 (`.env` でコメントアウトされている)。認証を付けるならここに `--api-key <値>` を書く |
| 起動前の GPU ガード (`REQUIRE_IDLE_GPU`) | `true` (上流既定のまま。取りうる値: `true` / `false`)。どちらかのノードで GPU を掴むプロセスがあれば起動を拒否する |
| 上流既定からの差分 | **値を変えた**キーが 5 つ (下の「書いていない上流キー」2 つは別勘定)。**サイト固有が 2 つ**: `IFACE` = `enp1s0f1np1` / `IB_HCA` = `=rocep1s0f1` (先頭の `=` は「完全一致で 1 デバイスだけ」を意味する上流の記法で、typo ではない)。**常用長に合わせたものが 3 つ**: `MAX_MODEL_LEN` 262144 → 524288 / `YARN_ENABLE` false → true / `YARN_FACTOR` 4.0 → 2.0 (理由は下の「YaRN」)。`HEAD_IP` / `WORKER_IP` は配布既定のまま実機と一致するので変更していない (実値は「依拠する外部事実」の確認コマンドで引く) |
| `.env` に**書いていない**上流キー | 2 つ。どちらも未設定が現行動作なので `.env` に足していない (値の出所はこの行だけ `.env.sample` と上流の CHANGELOG)。**`ABLIT`** (未設定 = 0。1 は値の切り替えではなく**別チェックポイントへの乗り換え**で、`drowzeys/keys-Qwen3.8-Flash-Next-NVFP4-dual-ablit-house-qsa-L3-47` を full snapshot で取り直す。HF 上での規約同意と `HF_TOKEN` (`.env` に書くか環境変数で渡す。この 2 キーだけは環境が `.env` に優先する) に加えて、124 GiB 級の取得と worker への配布が要る → `utility-spark-model-fetch`)。**`MAMBA_SSM_CACHE_DTYPE`** (未設定 = チェックポイントの float32。`bfloat16` にすると再帰状態の dtype が半分になる。**上流の「集約 decode スループット +8.5%」は単 Spark TP=1 での計測で、この 2 ノード TP=2 では未計測**と上流自身が書いている)。採用は `.env` に 1 行足して停止 → 起動、戻すのは行を消して同じ再起動 (13〜14 分止まる → 「既知の制約」7)。**`.env.sample` 側の既定は `ABLIT=0` / `MAMBA_SSM_CACHE_DTYPE=bfloat16` なので、`.env` を作り直すと後者が黙って有効になる** |

#### Qwen の reasoning effort の語彙

**受理される値はエンドポイントで違う。** 2026-09-06 に両経路で全値を実測した (確認コマンドは「依拠する外部事実」の reasoning effort の行)。

| 値 | `/v1/messages` (`ccsp`) | `/v1/chat/completions` (`ocsp`) | 弾く層 |
| --- | --- | --- | --- |
| `low` / `medium` / `xhigh` | 200 | 200 | — |
| `none` | **400** | 200 | `/v1/messages` のスキーマ |
| `high` / `max` | 400 | 400 | チャットテンプレート |
| 指定なし | 200 (既定 `xhigh`) | 200 (既定 `xhigh`) | — |

**したがってこの 2 経路から使える値は `low` / `medium` / `xhigh` の 3 つである。`cxsp` の `/v1/responses` はこの系統では未実測なので、Qwen 配信中に `cxsp` を使うなら最初の 1 回で 400 が出ないことを見る。**

- **`high` と `max` を弾くのはチャットテンプレートである。** `xhigh` / `medium` / `low` 以外で `raise_exception` する。エラー本文 `Unexpected reasoning effort high. Supported types are xhigh (default), medium, and low.` は既定値を自分で名乗る。**この層は両経路に共通する**ので、Anthropic ルータ (`/v1/messages`) も同じく 400 になる。ルータは `output_config.effort` を `reasoning_effort` に写して同じテンプレートへ渡すだけである
- **`none` が `/v1/chat/completions` でだけ通るのは、テンプレートに届く前に効果が消えるためである。** vLLM は `reasoning_effort != "none"` を `enable_thinking` に導出し、テンプレートは `enable_thinking` が偽なら effort を見ない (`reasoning_effort` 自体はテンプレートに渡るが、その分岐に入らない)。**`/v1/messages` にはこの抜け道が無い。** `AnthropicOutputConfig.effort` の Literal が `low` / `medium` / `high` / `xhigh` / `max` で `none` を含まず、スキーマ検証で先に 400 になる (本文は `Input should be 'low', 'medium', 'high', 'xhigh' or 'max'`)
- **値の実体は system への 1 文の指示である。** `xhigh` と `low` だけが文を足し、`medium` は何も足さない。長さや打ち切りを変える仕組みではない

#### 起動と判定 (Qwen 系)

**この小節は Qwen 系の起動の話である。** 他の系統から切り替えるときは、先に「系統の切り替え」の手順で配信中の系統を止める。

**`--launch` を使う。** Qwen レシピの引数なしの `./start.sh` は HuggingFace からのダウンロードと worker への rsync から始める。どちらも完了済みなので `--launch` が両方を飛ばす。**`--launch` でも head 側のシャード完全性の検査は必ず通り、欠落があればコンテナを作らずに止まる** (→「重みの検証」)。

**Qwen 系の cold start は約 11 分である** (上流計測、2026-09-05 時点の README: NCCL 約 40 秒、重みロード 458 秒、engine init 92 秒、graph capture 約 7 秒)。DeepSeek 系の約 6 分より長い。20 分を過ぎても上がらなければ両ノードで `docker logs vllm-fn` を見る (worker は「worker に入る」節の入れ子 ssh)。

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

**Qwen 系が起動できたかは 3 段で判定する。**

```bash
curl -fs -o /dev/null http://spark-head.local:8888/health && echo health-ok  # 1. API が生きている
curl -s http://spark-head.local:8888/v1/models                               # 2. qwen3.8-flash-next が返る
ocsp lan qwen run "1+1 は?"                                                   # 3. 実際に生成が通る (exit 0 で答えが出れば合格)
```

2 段目に Bearer が要らないのは無認証だからである (どの系統でもヘッダは要らない → 「API キーの流れ」)。**3 段目は `drs` 適用済みの Mac でしか通らない** (`ocsp` 関数が配られていることが要る。設定の symlink は別物で、こちらは既に dotfiles を指している)。1・2 段目に合わせて `lan` を付け、3 段が同じ経路を見るようにしてある (出先では 3 つとも Tailscale 側に読み替える)。未適用なら次で代用する。

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

最後の `diff` は**上流にキーが増えていないか**を見るために打つ (出力に IP を含む行があるので証跡として貼らない)。増えていたら「Qwen3.8-Flash-Next」の表の「`.env` に**書いていない**上流キー」行を更新する。そのうえで停止 → 起動する (→「系統の切り替え」の手順 2〜4)。

**更新後は次の 4 点で悪化していないことを確かめる。** 起動の 3 段判定は起動の可否しか見ないので足りない。2 と 3 は**停止する前に取っておき**、起動後の値と突き合わせる。

1. 起動の 3 段判定 (`/health` → `/v1/models` → 実際の生成)
2. `/v1/models` の `id` と `max_model_len` が更新前と一致すること。**`created` と `permission` は起動のたびに変わるので全文比較に使わない** (常に不一致になり検出器として働かない)
3. reasoning effort の語彙が変わっていないこと (→「Qwen の reasoning effort の語彙」。**2 経路とも打つ**)
4. `docker inspect vllm-fn --format '{{.HostConfig.RestartPolicy.Name}}'` が `no` のままであること

**KV プールのトークン数は起動ごとに動くので不合格の根拠にしない** (→「起動と判定 (Qwen 系)」)。

戻すときは `git checkout <旧 sha>` してから停止 → 起動する (detached HEAD になるので復帰は `git checkout main`)。重み・イメージ・`.env` のいずれも変わらないので戻せる。

#### 重みの検証

`0b62e12` のレシピは重みの検証手段を 3 つ持つ (新規に入ったのは 1 つ目と 3 つ目で、2 つ目は既存スクリプトの拡張)。**いずれも Qwen レシピ限定である** (他の 2 系統には無い。V4.1 EXL3 系の重みの確認は「依拠する外部事実」の「V4.1 EXL3 の重みがそろっているか」の行)。パスはレシピディレクトリからの相対で、実行も同ディレクトリで行う。

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

**3 つとも API キーを扱わないので 1Password は要らない。** ただし `ccsp` だけは本物の Anthropic 資格情報が Spark へ飛ぶ経路を持つ (→「API キーの流れ」)。

#### 使える API

**Claude Code と OpenCode の 2 つから使える (2026-09-06 に実測)。`cxsp` が使う `/v1/responses` はこの系統では未試行である** (判定は「依拠する外部事実」のコードブロック 8 のモデル名を配信名に差し替えて打つ)。 このイメージの vLLM は複数の API をフラグ無しで持つ。`/v1/messages` (Anthropic Messages API) は `vllm/entrypoints/generate/api_router.py` が `register_anthropic_api_router(app)` を無条件に呼ぶので `ccsp` が通り、`/v1/chat/completions` で `ocsp` が通る。`ccsp qwen` は `max_model_len` 524,288 から出力用の余白 32,768 を引いた 491,520 をコンテキスト上限に入れて起動する。

### DeepSeek-V4.1-Flash EXL3 (別系統のレシピ)

**他の 2 系統とは別リポジトリ・別イメージ・別スクリプトである。** 2026-09-15 に導入し、常用配信をこの系統にした。起動の 3 段判定、`ccsp lan v41` と `ocsp lan v41 run` からの生成、reasoning effort の語彙まで確認済み。2026-09-17 に `cxsp` (`/v1/responses`) の生成とツール呼び出しも確認した (head のパッチが前提 →「既知の制約」12)。**クライアント 2 つの確認は、リポジトリの zsh 関数を直接 source して行った。この Mac は 2026-09-15 時点で `drs` を当てていない**ので、素のシェルで `ccsp v41` を打つと `v41` がプロンプトとして `claude` に渡る (→「Claude Code (`ccsp`)」の反映経路)。

**この構成には認証が無い** (根拠は「動いているもの」。認証を戻す手順は DeepSeek 系向けにしか書いていない)。

値の出所はレシピの `.env` と、起動ログが出す `config:` 行である。ただし「レシピ」「量子化」「重み (本体)」「重み (Engram)」「pack」「既定の reasoning」「コンテナイメージ」「コンテナ名」「上流既定からの差分」の 9 行を除く (これらは HF API・`files/` 配下・`docker inspect`・`.env.example` との差分から取った)。

| 項目 | 値 |
| --- | --- |
| レシピ | head の `~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks` @ `8530568` |
| 量子化 | EXL3 (→ 用語表) の平均 2.9 bpw。テンソルごとにビット数が違う (routed experts は 3 bit で層 18〜22 だけ 2 bit、shared experts は 5 bit / 4 bit、attention は 5 bit。レシピの `files/exl3_k_map.json`) |
| 重み (本体) | `Mia-AiLab/DeepSeek-V4.1-Flash-EXL3-2.9bpw` @ `64ba41b6c916a587db06eae2e19b7845f7be6e6b`。49 ファイル / safetensors 39 本 / 196.2 GiB。head はレシピ直下の `model/`、worker は `~/.cache/dsv41-flash-exl3/model/`。HF の org 表記は `Mia-AiLab` で、GitHub の `MiaAI-Lab` とは綴りが違う (どちらも実在する表記) |
| 重み (Engram) | `deepseek-ai/DeepSeek-V4.1-Flash` @ `dba1be0a40aa45a94ad051997016db3960a90277` の shard 47 / 48 (各 94.6 GiB) と `model.safetensors.index.json` と `config.json`。head はレシピ直下の `engram-src/`。この先の経路は下の「Engram の流れ」 |
| pack | head が rank 0 の 2 本、worker が rank 1 の 2 本を、それぞれ自分の Engram コピーから `~/dsv41-engram/` に作る (1 本 47.2 GiB、ファイル所有者は root)。コンテナに `/engram-packed` として mount される |
| API 上のモデル名 (`SERVED_MODEL_NAME`) | `DeepSeek-v4.1-Flash-EXL3` (大文字を含む。短縮名は `v41`) |
| コンテキスト上限 (`MAX_MODEL_LEN`) | サーバ 600,000 トークン / Claude Code からは 567,232 (`ccsp` が出力用の余白 32,768 を引く) |
| 同時リクエスト上限 (`MAX_NUM_SEQS`) | **2 リクエスト** (3 系統で最も少ない。超過分はキューで待つ) |
| 投機デコード (`SPEC_METHOD` / `DSPARK_TOKENS`) | DSpark (draft はチェックポイント内の `mtp.*`)、draft 3 トークン |
| KV キャッシュ | vLLM が `fp8_ds_mla` を自分で選ぶ (`--kv-cache-dtype` は渡さない)。プールは `KV_CACHE_MEMORY_BYTES` で 2.5 GiB に固定 |
| `GPU_MEM_UTIL` | 0.88。KV プールを固定しているので予算ではなく、vLLM が起動時に空きメモリと比べる検査値 |
| 画像入力 | **使えない** (`LANGUAGE_MODEL_ONLY=1`。GB10 の FlashInfer に対応カーネルが無い) |
| 既定の reasoning | thinking ON。effort を送らないときの既定は `high` (レシピの `files/chat_template.jinja` の `reasoning_effort` の既定値) |
| コンテナイメージ | `ghcr.io/miaai-lab/deepseek-v4.1-flash-exl3-2x-dgx-sparks:2.9bpw` (Id `sha256:4cdba4e946da2d19bf5b5a20c6d3a1a4bf421fa4d6db5082f271a986168176cb`、展開後 22.5 GB、arm64、ラベル `dsv41.recipe.stamp` = `8c01a8543ff7e7b222ae1cd46b8be5051838dc7a7b075b4e647f3785c0429584`)。**両ノードに配置済み** |
| コンテナ名 | `dsv41-exl3-head` / `dsv41-exl3-worker`。restart policy は両方 `no` |
| 上流既定からの差分 | 4 キー。`WORKER_USER=skanehira` (上流は作者のユーザー名)、`WORKER_CX7_IF=enp1s0f1np1` / `WORKER_CX7_IB=rocep1s0f1` (上流の作者機は worker が `f0`。当方は両ノードとも `f1`)、`WEIGHT_SYNC=rsync` (上流既定は `nfs`)。これに `HF_HUB_ENABLE_HF_TRANSFER=0` を 1 行足してある (head に `hf_transfer` が無いため)。確かめ方は「依拠する外部事実」のコードブロック 6 |

**`WEIGHT_SYNC=rsync` にしている理由。** 上流既定の NFS では worker が head の export を RoCE (上流は CX7 = ConnectX-7 と呼ぶ) 越しに読み、head が配信中の単一障害点になる。pack した Engram はどちらの方式でもローカル NVMe から読まれるので、配信中の速度は変わらない見込みである。**上流は rsync を fallback 扱いにしている**ので、検証の厚みは NFS 経路より薄い。

**Engram の流れ。** head の `engram-src/` → `start.sh` が起動と pack のたびに作り直す slim dir (`~/.cache/vllm-dsv41-flash-exl3/engram-src/`。shard 2 本はハードリンク、`config.json` はコピー、index は Engram のキーだけに書き直す) → 3 か所で使う。(1) head の pack と head のコンテナ (`/engram-src`) が読む。(2) worker へはこの slim dir を rsync して `~/.cache/dsv41-flash-exl3/engram-src/` にする。(3) worker の pack と worker のコンテナがそのコピーを読む。rsync はシャードのサイズと mtime から作ったマーカー (`.dsv41-engram-synced`) が一致すると省略される。

#### 起動と判定

```bash
ssh spark-head
cd ~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks
./start.sh            # 起動 (GPU 自己検査 → 重みの同期確認 → 両ランク起動 → health 待ち → warmup)
./start.sh status     # 両ランクのコンテナ状態と health
./start.sh logs       # head のログを追う (worker は ./start.sh logs worker)
./start.sh stop       # 両ランク停止 (./stop.sh も同じ)。成否は「系統の切り替え」の手順 3 で確かめる
./start.sh pack       # Engram を pack し直す (重みを差し替えたときだけ)
```

- **重みが無いと `./start.sh` は自動でダウンロードを始める** (`AUTO_DOWNLOAD=1`)。revision は固定されない (→「導入手順」2)
- **GPU 自己検査**は、head で使い捨てコンテナを立てて EXL3 のカーネルと Engram の逆量子化を合成データで確かめる段である。結果は `logs/overlay-verify.log` に出て、不合格ならコンテナを作らずに止まる
- **起動に失敗してもコンテナは消えない。** `start.sh` は `logs/head.log` / `logs/worker.log` (head のログが 420 秒止まったときは `logs/hang-{head,worker}-pyspy.txt` も) を書いて止まる。コンテナがメモリを掴んだまま残るので、**原因を見たら `./start.sh stop` → 「系統の切り替え」の手順 3 の判定 → 起動し直す**。health 待ちは 1,500 秒で打ち切られる
- **前置で上書きできるキーは限られる。** `start.sh` は `DSPARK_TOKENS` / `SPEC_METHOD` / `MAX_MODEL_LEN` / `MAX_NUM_SEQS` / `MAX_NUM_BATCHED_TOKENS` / `GPU_MEM_UTIL` / `LANGUAGE_MODEL_ONLY` / `IMAGE` / `ENFORCE_EAGER` と EXL3 のカーネル設定だけを `.env` の読み込み前に退避して書き戻す。それ以外の `.env` のキー (`WEIGHT_SYNC` / `WORKER_*` / `KV_CACHE_MEMORY_BYTES` / `SERVED_MODEL_NAME` など) は前置しても `.env` の値が勝つので、`.env` を編集する。`.env` に無い `FORCE_SYNC=1` (worker への rsync を強制) / `SKIP_SYNC=1` (worker への同期を丸ごと省く) / `BUILD=1` (イメージをローカルでビルド) / `SKIP_BUILD=1` (stamp が違ってもビルドしない) / `SKIP_SHIP=1` (worker へイメージを送らない) は前置で効く

**Claude の Bash ツールから起動するときは、ssh を切り離してログを残す。** 起動全体は 8〜10 分かかり、Bash ツールの上限 (600 秒) を越えうる。ssh ごと切れると warmup が走らないまま中断する。

```bash
ssh -n spark-head 'cd ~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks && setsid nohup ./start.sh > ~/dsv41-start.log 2>&1 < /dev/null & echo started'
# 終わるまで待つ ({{@background-run}} で流す)。`^bash ./start.sh$` に固定しているので、この ssh のコマンド文字列には一致しない
until ! ssh -n spark-head 'pgrep -f "^bash ./start.sh$" >/dev/null'; do sleep 30; done
ssh -n spark-head 'tail -25 ~/dsv41-start.log'   # 「DeepSeek-V4.1-Flash EXL3 is UP」が出ていれば起動は完了。出ていなければ上の失敗時の手順
```

**起動できたかは 3 段で判定する。** どれも exit code で合否が出る。

```bash
curl -fs -o /dev/null http://spark-head.local:8888/health && echo health-ok   # 1. API が生きている
curl -s http://spark-head.local:8888/v1/models | python3 -c 'import json,sys; d={m["id"]:m.get("max_model_len") for m in json.load(sys.stdin)["data"]}; print(d); sys.exit(0 if d.get("DeepSeek-v4.1-Flash-EXL3")==600000 else 1)'   # 2. 配信名と上限
ssh -n spark-head 'cd ~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks && bash tests/test_smoke.sh'   # 3. exit 0 で「smoke OK: 17*19 -> 323」
```

加えて pack が使われていることを見る。head では `docker inspect dsv41-exl3-head --format '{{range .Mounts}}{{.Destination}} {{end}}'`、worker では「worker に入る」節の入れ子 ssh で `docker inspect dsv41-exl3-worker` を同じ形で打ち、両方に `/engram-packed` が出れば合格 (各ノードには自分のコンテナしか無いので、1 ノードで 2 つの名前を打つと片方が必ずエラーになる)。

**起動の実測値 (2026-09-15、pack 済み・重みの同期済み)。**

| 項目 | 値 |
| --- | --- |
| コンテナ起動から `/health` 200 まで | 470 秒 |
| 重みロード | 本体 191.75 秒 + draft 32.27 秒 (ログの `Loading weights took` が 2 行出る)。`Model loading took 98.86 GiB memory and 270.5 seconds`。合計との差 46 秒の内訳は取っていない |
| `MemAvailable` の推移 (head / worker) | 起動前 116.1 / 114.9 GiB → 重みロード後 16 / 16 GiB → health 通過時 6.0 / 7.2 GiB |
| pack の所要 | 1 本 (47.2 GiB) あたり約 90 秒、両ノードで計 4 本。`FORCE_SYNC=1` を付けても、変わったファイルが `config.json` だけなら rsync は 1 分以内に終わった |
| 単一リクエストの decode | コード生成 400 トークン (thinking OFF、temperature 0) で約 36 tok/s、TTFT 0.60 秒。上流の散文での値は 31.6 tok/s |

**起動ログの `boot shape warmup incomplete` は致命的ではない。** warmup リクエストは 14/14 通っており、sampler のカーネル 1 通り (top-p だけの組み合わせ) が事前コンパイルされなかったという意味である。その組み合わせを初めて使うリクエストで 1 回だけ JIT の待ちが入りうる。

#### V4.1 EXL3 の reasoning effort の語彙

`/v1/messages` と `/v1/chat/completions` は 2026-09-15 に、`/v1/responses` は 2026-09-17 に全値を実測した。確認コマンドは「依拠する外部事実」の reasoning effort の行と同じ形で、**モデル名を `DeepSeek-v4.1-Flash-EXL3` に、陽性対照の値を `high` から `medium` に差し替える** (V4.1 は `high` を受理するので、`high` では 400 にならない)。`/v1/responses` は「依拠する外部事実」のコードブロック 8 に `"reasoning":{"effort":"<値>"}` を足した形で打つ。

| 値 | `/v1/messages` (`ccsp`) | `/v1/chat/completions` (`ocsp`) | `/v1/responses` (`cxsp`) |
| --- | --- | --- | --- |
| `low` / `high` / `xhigh` / `max` | 200 | 200 | 200 |
| `medium` | 400 | 400 | 400 |
| `none` | 400 (スキーマ) | 200 | 200 |
| 指定なし | 200 | 200 | 200 |

- **3 つのクライアントに `max` を送らせている** (`ccsp` と `cxsp` は `_spark_effort`、`ocsp` は `opencode.json`)
- **`medium` の 400 の本文は語彙を名乗る**: `DeepSeek V4.1 reasoning_effort must be low, high, xhigh, max, or an integer within [1, 100] in chat_template_kwargs`。弾く層は vLLM 側の検査で、Qwen 系のようなチャットテンプレートの `raise_exception` ではない。レシピの `files/chat_template.jinja` のコメントは `xhigh` を挙げていないが、実測で受理されるので実測に従う
- **`none` の非対称は Qwen 系と同じ構造である** (→「Qwen の reasoning effort の語彙」)。**弾くのは `/v1/messages` のスキーマだけ**で、`/v1/chat/completions` と `/v1/responses` は通す

#### 導入手順

レシピを入れ直すときの順序と、各段の完了判定である。どれも head の上で打つ (6・7 は worker でも)。**配信中の系統を止めずに進められるのは 1〜6 まで**で、7 からは 8888 が止まる。

1. **clone と `.env`** — `git clone https://github.com/MiaAI-Lab/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks ~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks` → `cp .env.example .env` → 表の「上流既定からの差分」の 4 キーと 1 行を入れる。**完了判定**: 「依拠する外部事実」のコードブロック 6 の差分がその 5 キーだけになる。`ip route get` で worker の RoCE アドレスへの経路が `dev enp1s0f1np1` を通り、両ノードの `/sys/class/infiniband/rocep1s0f1/ports/1/gid_attrs/types/3` が `RoCE v2` を返す
2. **本体の重み** — `mkdir -p model engram-src` (落とし穴 1) の後に取る。**`download.sh` と `start.sh` の自動取得は revision を固定しない**ので、固定するなら `hf download Mia-AiLab/DeepSeek-V4.1-Flash-EXL3-2.9bpw --revision 64ba41b6c916a587db06eae2e19b7845f7be6e6b --local-dir model --max-workers 2` を手で打つ (この形は未実行。当方は `download.sh` で取り、取得時点の `main` が同じ revision だったことを照合で確かめた)。配信中のノードでは `HF_HUB_DISABLE_XET=1` を付け、メモリ上限を掛けて流す (落とし穴 2)。**完了判定**: 「依拠する外部事実」の「V4.1 EXL3 の重みがそろっているか」が exit 0
3. **Engram** — 下のコードブロックで shard 2 本と index と `config.json` を取る (落とし穴 3・4)。**完了判定**: 同ブロック末尾の `sha256sum -c` が 2 本とも `OK`
4. **イメージ** — `docker pull ghcr.io/miaai-lab/deepseek-v4.1-flash-exl3-2x-dgx-sparks:2.9bpw` を両ノードで打つ。取り切れなければ下の「イメージを手で取る」 (落とし穴 5)。**完了判定**: 両ノードの `docker image inspect <イメージ> --format '{{index .Config.Labels "dsv41.recipe.stamp"}}'` が落とし穴 6 のコマンドの値と一致する
5. **worker への事前コピー** (任意) — 8888 を止める時間を縮めたいときだけ。`rsync -a --partial model/ <worker の RoCE アドレス>:.cache/dsv41-flash-exl3/model/` を head で打つ (Engram は slim dir ができる 7 で `start.sh` が送る)。**完了判定**: worker 側で 2 の照合を `~/.cache/dsv41-flash-exl3/model` に向けて exit 0、rsync の出力に `denied` が 0 件
6. **止める準備** — 「系統の切り替え」の手順 1
7. **配信中の系統を止めて pack** — 「系統の切り替え」の手順 2・3 → `./start.sh pack` (worker への同期も同時に行う)。**完了判定**: head の `ls -la ~/dsv41-engram` に `engram-l{1,14}-r0of2.bin`、worker に `engram-l{1,14}-r1of2.bin` があり、各 47.2 GiB
8. **head のパッチ** — 「既知の制約」12 の全文を `~/dsv41-local/patch_responses_content_parts.py` に置き、`start.sh` に 2 行を足す。**`cxsp` を使わないなら飛ばしてよい** (`ccsp` / `ocsp` には要らない)。**完了判定**: `git diff --stat start.sh` が 2 insertions
9. **起動と判定** — 上の「起動と判定」。**完了判定**: 3 段と `/engram-packed` の確認。`cxsp` を使うなら「依拠する外部事実」のコードブロック 8 が 200 を返すことも見る
10. **クライアント側と表示** — 短縮名・effort・`opencode.json` はコミット済みなので、`drs` と新しいシェルだけ。sparkDash の `workerLabel` を直す

Engram の取得 (手順 3)。HF の resolve URL は Range 指定に 206 を返すので、`curl -C -` で途中から再開できる。サイズを先に見るのは、取り終えたファイルに `-C -` を打つと範囲外の要求になるため。

```bash
cd ~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks/engram-src
REPO=deepseek-ai/DeepSeek-V4.1-Flash REV=dba1be0a40aa45a94ad051997016db3960a90277
curl -s "https://huggingface.co/api/models/$REPO/revision/$REV?blobs=true" | python3 -c '
import json,sys
want={"model-00047-of-00048.safetensors","model-00048-of-00048.safetensors","model.safetensors.index.json","config.json"}
for s in json.load(sys.stdin)["siblings"]:
    if s["rfilename"] in want: print(s["rfilename"], s["size"], (s.get("lfs") or {}).get("sha256",""))' > manifest.txt
while read -r f size sha; do
  until [ "$(stat -c %s "$f" 2>/dev/null || echo 0)" -eq "$size" ]; do
    curl -sS -L --fail -C - --speed-time 120 --speed-limit 102400 "https://huggingface.co/$REPO/resolve/$REV/$f" -o "$f" || sleep 10
  done
done < manifest.txt
awk '$3!="" {print $3"  "$1}' manifest.txt | sha256sum -c -
```

イメージを手で取る (手順 4 で `docker pull` が取り切れないとき)。blob を 1 本ずつ再開可能に取り、`docker save` 形式にまとめて読み込む。2026-09-15 に使ったスクリプトを短くした形で、この形のままでは流していない。

```bash
REPO=miaai-lab/deepseek-v4.1-flash-exl3-2x-dgx-sparks TAG=2.9bpw W=~/.cache/dsv41-image
mkdir -p $W/oci/blobs/sha256 && cd $W
tok(){ curl -fsS "https://ghcr.io/token?scope=repository:$REPO:pull&service=ghcr.io" | python3 -c 'import json,sys;print(json.load(sys.stdin)["token"])'; }
curl -fsS -H "Authorization: Bearer $(tok)" -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
  "https://ghcr.io/v2/$REPO/manifests/$TAG" -o manifest.json    # 単一プラットフォーム (arm64) の manifest が返る
python3 -c 'import json;m=json.load(open("manifest.json"));[print(b["digest"][7:],b["size"]) for b in [m["config"]]+m["layers"]]' > blobs.txt
while read -r d size; do
  f=oci/blobs/sha256/$d
  until [ "$(stat -c %s $f 2>/dev/null || echo 0)" -eq "$size" ]; do
    curl -sS -L --fail -C - -H "Authorization: Bearer $(tok)" "https://ghcr.io/v2/$REPO/blobs/sha256:$d" -o $f || sleep 5
  done
  echo "$d  $f" | sha256sum -c --quiet - || exit 1
done < blobs.txt
python3 -c 'import json;m=json.load(open("manifest.json"));json.dump([{"Config":"blobs/sha256/"+m["config"]["digest"][7:],"RepoTags":["ghcr.io/'$REPO':'$TAG'"],"Layers":["blobs/sha256/"+l["digest"][7:] for l in m["layers"]]}],open("oci/manifest.json","w"))'
tar -C oci -cf - manifest.json blobs | docker load
```

もう 1 ノードへは、この `~/.cache/dsv41-image/` を RoCE で rsync して最後の `tar … | docker load` だけを打つ。**読み込み後の `~/.cache/dsv41-image/` (9.1 GiB) は消してよい。** 残しているのは、イメージを消したときに再取得せず読み込み直すためである。

#### 導入と再導入の落とし穴

上流 README の手順を素直に流すと、この環境では次の 6 か所で止まる。上の「導入手順」はこれを避ける順序になっている。

1. **`download.sh` は `model/` が無いと何も出さずに exit 1 で終わる。** 先頭のシャード数の数え方が `set -o pipefail` 下で `find` の失敗を拾うためである。先に `mkdir -p model engram-src` しておく
2. **xet (HuggingFace の Xet ストレージ経由の転送。huggingface_hub 1.x の既定) は受信データをメモリに溜める。** Qwen 配信中の head で並列 8 のまま流すと、ディスクへの書き込みが 0 MB/s のまま `MemAvailable` が 1 GiB を切った。本体 (1 ファイル 6 GiB 前後) は `HF_HUB_DISABLE_XET=1` + `HF_MAX_WORKERS=2` で HTTP のストリーム書き込みにすると安全に取れる (8 MB/s で約 7 時間)。**配信中のノードで流すときはメモリ上限を掛ける** (→「既知の制約」11)
3. **Engram の shard 47 / 48 (各 94.6 GiB) は huggingface_hub が xet 以外での取得を拒否する** (`The file is too large to be downloaded using the regular download method`)。上の curl のコードブロックで取る
4. **Engram 側に元チェックポイントの `config.json` が要る。** `download.sh` は取らないが、`pack_engram.py` と起動時の Engram ローダーの両方が `text_config.engram_layer_ids` を読む。無いと pack が `FileNotFoundError: /models/config.json` で落ちる (`/models` は pack のコンテナに mount した slim dir)。`config.json` を `engram-src/` に置けば、pack と起動のたびに slim dir が作り直されるので head 側には届く。**worker 側には届かないので `FORCE_SYNC=1 ./start.sh pack` にする** (rsync のマーカーはシャードのサイズと mtime だけを見るので、`config.json` の追加では省略が外れない)
5. **GHCR のイメージは `docker pull` で取り切れないことがある。** 4.81 GiB などの大きいレイヤーが `unexpected EOF` で切れ、dockerd はリトライのたびにそのレイヤーを最初から取り直すので終わらない (1 時間で 149 回リトライした)。上の「イメージを手で取る」で取る。**この docker は OCI layout の `index.json` だけの tar を読まない** (`invalid archive: does not contain a manifest.json`) ので、`docker save` 形式の `manifest.json` が要る
6. **イメージの stamp が手元の clone と一致しないと、起動時にビルドが始まる。** `start.sh` は `Dockerfile` と `overlay/` `files/` `tests/` のハッシュをイメージのラベル `dsv41.recipe.stamp` と比べる。**この 4 つのどれかを上流が変えたら**、公開イメージを pull し直すかビルドが要る (README や `start.sh` だけの変更ではずれない)。clone 側の値はレシピのディレクトリで次を打って出す

   ```bash
   { printf "%s\n" Dockerfile; find overlay files tests -type f ! -path "*/__pycache__/*" ! -name "*.pyc" ! -name "*.so"; } | LC_ALL=C sort | xargs -d "\n" -r sha256sum | sha256sum
   ```

**pack のファイルは root 所有である。** Spark には passwordless sudo が無いので、消すときはイメージ経由で消す (`docker run --rm -v ~/dsv41-engram:/e --entrypoint rm ghcr.io/miaai-lab/deepseek-v4.1-flash-exl3-2x-dgx-sparks:2.9bpw -f /e/engram-l1-r0of2.bin /e/engram-l14-r0of2.bin`。worker は `r1`)。作り直すだけなら `./start.sh pack` が上書きする。

#### レシピを更新する (V4.1 EXL3 系)

```bash
ssh spark-head
cd ~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks
git fetch -q && git log --stat --oneline HEAD..origin/main   # 先行分と、変わったファイルを読む
git pull --ff-only
```

- **`Dockerfile` / `overlay/` / `files/` / `tests/` が変わっていたら**、落とし穴 6 のコマンドの値とイメージのラベルがずれる。公開イメージを両ノードで pull し直し、値が一致することを確かめてから起動する
- **`.env.example` にキーが増えていないか**を「依拠する外部事実」のコードブロック 6 で見る。`.env` は追跡外なので `git pull` では消えない
- **`start.sh` のローカル差分 2 行は `git pull` で消える** (→「既知の制約」12)。`git pull` の直後に `git diff --stat start.sh` を打ち、空になっていたら 2 行を足し直す。**これを忘れると `cxsp` だけが静かに壊れる** (`ccsp` / `ocsp` は無傷なので他の確認はすべて green のまま通る)
- **更新後の悪化確認**は Qwen 系と同じ 4 点 (→「レシピを更新する」(Qwen 系) の 1〜4) を、V4.1 EXL3 系のコマンドと語彙に読み替えて行い、5 点目として「依拠する外部事実」のコードブロック 8 (`input_text` が 200) を打つ。コンテナ名は `dsv41-exl3-head`、語彙の確認は「V4.1 EXL3 の reasoning effort の語彙」
- **戻すとき**は `git checkout 8530568` してから停止 → 起動する。**`git checkout` も 2 行を消す**ので、起動の前に足し直す

## Mac から使う

クライアントは 3 つある。**接続先とモデルの決め方は共通である。** どれも `spark-common.zsh` で接続先を選び (自宅 LAN → Tailscale の順に `/health` をプローブ)、`/v1/models` を聞いて配信名を採るので、モデルを切り替えても設定は触らなくてよい。**窓 (コンテキスト上限) をサーバから採るのは `ccsp` と `cxsp` の 2 つだけで、`ocsp` は `opencode.json` の人が書く静的値を使う** (乖離は現に起きている →「OpenCode (`ocsp`)」)。違うのは次の 6 点である。

| 観点 | `ccsp` (Claude Code) | `ocsp` (OpenCode) | `cxsp` (Codex) |
| --- | --- | --- | --- |
| 使う API | `/v1/messages` | `/v1/chat/completions` | `/v1/responses` |
| シェルへの副作用 | `ANTHROPIC_BASE_URL` / `NODE_OPTIONS` の export と `claude` の alias。**`ccsp off` で戻す** | なし (接続先は 1 回の起動にだけ効く環境変数で渡す) | なし (設定は `codex` の `-c` で 1 回の起動にだけ渡す) |
| 引数の素通し | `lan` / `ts` / 短縮名を消費した残りをそのまま claude へ。どの経路でも配信前検査と `--settings` 注入は必ず通る | opencode のサブコマンド (`run` 以外) では**接続先の決定も配信前検査も `--model` 注入も飛ばす**。`--model` を前置するとサブコマンド的文脈で unknown option 扱いになり実行の代わりに help 表示になる (2026-09-06 実測) | 消費した残りをそのまま codex へ。**サブコマンドでも検査と注入を飛ばさない** — codex は root の `-c` を subcommand の前に置けるので (`codex -c … exec …`)、全経路で同じ注入が通る |
| モデルを増やしたとき | `_spark_effort` に effort を足す (`cxsp` と共有) | `opencode.json` の `models` に宣言と effort が要る | `ccsp` と同じ (共有の `_spark_effort` だけ) |
| reasoning effort の決め方 | 配信名から自動 (`CCSP_EFFORT` で上書き) | `opencode.json` の静的値 | 配信名から自動 (`CXSP_EFFORT` で上書き) |
| 資格情報の漏れ | **本物の Anthropic トークンが Spark へ飛ぶ** (→「API キーの流れ」) | なし | なし (`env_key` を省くと Authorization ヘッダ自体を送らない) |

速度はクライアント側の作りで 10 倍以上変わる (→「実測値」節の「L2 / L3: クライアント込み」)。**`cxsp` の速度は未計測で、L2 / L3 に相当する層のラベルも定義していない。**

### 新しいマシンで手で用意するもの

Nix (`drs`) では入らないものが 5 つある。

| もの | 用途 | 作り方 |
| --- | --- | --- |
| `~/.ssh/config` と鍵 2 本 | ssh エイリアス | 「接続する」節 |
| `known_hosts` の 3 エントリ | Claude の非対話 ssh | 「接続する」節の `ssh-keyscan` (人が実行) |
| Tailscale へのサインイン | 出先から使うとき (`ccsp` / `ocsp` / `cxsp` の 3 つとも)。cask はアプリを置くだけで tailnet 参加は手作業 | アプリを開いてログイン。**`tailscale status` に `spark-head` の行が出れば合格** |
| 1Password へのサインイン | `ccds` のトークン取得と、下の `/tmp/spark.key` の書き出し。**Spark 向けの 3 つ (`ccsp` / `ocsp` / `cxsp`) には要らない** | `op signin` |
| `/tmp/spark.key` (head のみ) | `bench.py` を打つときだけ。無認証の現在も文字列自体は要る | 「API キーの流れ」節 |

`ccsp` / `ocsp` / `cxsp` の関数本体と `opencode` のバイナリは Nix 経由なので、**`drs` を実行してから新しいシェルを開くまで存在しない** (既存シェルには旧定義が残る)。**`codex` 本体だけは Homebrew の cask で入る** (`nix/modules/darwin/homebrew.nix`)。Tailscale 本体は `nix/modules/darwin/homebrew.nix` の cask `tailscale-app` で入る。

### Claude Code (`ccsp`)

```bash
ccsp                       # 到達する方を自動選択し、配信中のモデルで claude を起動
ccsp lan                   # 自宅 LAN を強制 (プローブしない)
ccsp ts                    # Tailscale を強制
ccsp qwen                  # モデルを指定 (qwen / vision / v41)
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
- **2 つの設定ファイルで反映経路が違う。** `settings.spark.json` は `ccsp` が dotfiles を直参照するので編集すれば次の起動から効く。`zsh/functions/*.zsh` は Nix store 経由で配られるので `drs` と新しいシェルが要る。**この差は片側だけ適用された状態を作る。** 例えば effort を `settings.spark.json` から `_spark_effort` へ移す変更では、削除が即時に効く一方で注入する側が届かないため、`drs` を当てるまで effort を送らない状態になる (`grep -c _spark_effort ~/.config/zsh/functions/claude-deepseek.zsh` が 0 なら未適用)。**旧定義が残っているかは `ccsp -h` で判る** (新しい版は短縮名の表を出す)。旧のまま `ccsp qwen` を打つと `qwen` が短縮名として認識されず `claude` への引数に回り、プロンプト "qwen" として無言で起動してしまう
- **モデル名とコンテキスト上限は `ccsp` が `/v1/models` から取る。** 配信名をそのまま使い、`CLAUDE_CODE_MAX_CONTEXT_TOKENS` には `max_model_len` から出力用の余白 (既定 32,768。`CCSP_OUTPUT_RESERVE` で変更可) を引いた値を入れて `~/.cache/ccsp/settings.json` を毎回生成する。`max_model_len` は入力と出力の合計なので、窓をそれと同値にすると生成時に溢れる。配信側のモデルを変えても Mac 側の編集は要らない。短縮名 (`qwen` / `vision` / `v41`) を渡した場合はそれが配信されているかを起動前に検査し、載っていなければ配信中の一覧を出して exit 1 で止まる。短縮名に無いモデルは `CCSP_MODEL=<配信名> ccsp` で渡す
- **reasoning effort も `ccsp` が配信名から決める。** `_spark_effort` の表 (`qwen3.8-flash-next` → `xhigh` / `DeepSeek-v4.1-Flash-EXL3` → `max` / それ以外 → `high`) を引いて `CLAUDE_CODE_EFFORT_LEVEL` に注入する。**これはサーバに聞けない値なので、モデル名と違って表を持つしかない** (`/v1/models` は受理される effort を返さない)。上書きは `CCSP_EFFORT=<値> ccsp`。**モデルの語彙に無い値は起動前ではなく最初のリクエストで 400 になる** (検査がチャットテンプレートとスキーマにあるため、`ccsp` からは事前に判定できない → 「Qwen の reasoning effort の語彙」)。**解決した値が出るのは起動時の 1 行 (`ccsp: Spark モード (… / effort <値>)`) だけである。** `ccsp status` は起動せずに表示する都合で配信名を確定させないため、`CCSP_EFFORT` があればその値を、無ければ規則の文言を出す (読者が同じ画面の「配信中:」行と突き合わせる)
- **`ccsp status` の「配信中」行は `ANTHROPIC_BASE_URL` を優先して照会する。** `ccds` はこれをシェルへ export しないので、素のシェルでは到達した方 (Spark) のモデルが出る。**空になるのは照会先が答えないとき**である (典型は `ccds` が起動した Claude Code の配下 — settings の `env` を継承して DeepSeek 本家を照会する。Spark 側が落ちている場合も同じ。`ocsp status` は常に到達した方を照会する。2026-09-09 実測)

`settings.spark.json` は **`security-guidance` プラグインを無効にしている** (`enabledPlugins` のキーは完全名 `security-guidance@claude-plugins-official`)。このプラグインの Stop hook は自前の既定モデル名 `claude-opus-4-7` を `ANTHROPIC_BASE_URL` に投げるため、Spark 相手では 404 を受けて延々とリトライし、レビューを 1 件も出さないまま 1 セッションあたり約 231 秒を捨てる。`settings.deepseek.json` (DeepSeek 本家) も同じ理由で無効にしてある。

### OpenCode (`ocsp`)

```bash
ocsp                       # 到達する方 (LAN → Tailscale) を選んで対話 TUI をカレントディレクトリで起動
ocsp lan                   # 自宅 LAN を強制 (プローブしない)
ocsp ts                    # Tailscale を強制
ocsp qwen                  # モデルを指定して起動 (qwen / vision / v41)
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

**モデルの決め方は `ccsp` と同じである。** 引数で短縮名を渡せばその起動だけそれを使い、渡さなければ `/v1/models` の配信中モデルを採る。`ocsp model <名前>` はシェル変数 `OCSP_MODEL` を書き換えるので以降の起動に効く (新しいシェルでは未設定に戻り、また配信中のモデルを採る)。要求したモデルが配信されていなければ起動前に exit 1 で止まる。**配信中の一覧そのものが引けないときも止まる** (`ccsp` と同じ挙動)。**`opencode.json` に `apiKey` は無い。** `ocsp` はキーが空なら Authorization ヘッダ自体を送らないので、Qwen 配信中 (無認証) はそのまま一覧が引けて起動する (2026-09-06 実測)。DeepSeek 系を認証ありで起動すると 401 になるので、そのときは `options` に `apiKey` を足す。**値は `{file:~/…}` か `{env:…}` で外部に逃がす** (`opencode.json` は公開リポジトリの追跡ファイルなので平文で置かない。→「API キーの流れ」)。**`opencode.json` の `models` に宣言が無いモデルは OpenCode 側が拒否するので、モデルを増やしたらこの JSON にも足す。** 値の決め方は `limit.context` = `/v1/models` の `max_model_len`、`limit.output` = 65536、`reasoning` と `tool_call` は `true`、`options.reasoningEffort` はそのモデルで受理を確かめた最大値 (Vision-Exp だけは未実測なので語彙に合わせた値。現在は `qwen3.8-flash-next` = `xhigh` / `deepseek-v4-flash-vision-exp` = `high` / `DeepSeek-v4.1-Flash-EXL3` = `max`) である。**`ccsp` と違ってこれは人が書く静的値なので、サーバ側の `MAX_MODEL_LEN` を変えると取り残される** (`workerLabel` と同型の乖離経路)。**`reasoningEffort` を省くと `ocsp` は effort を送らず、テンプレート既定 (Qwen なら `xhigh`) が効く。** 明示してあるのは既定が変わったときに黙って浅くならないようにするためで、Qwen については省略時と同じ値である。

**opencode のサブコマンドは素通しする。** 短縮名や接続先の語のうしろの先頭語がサブコマンド名 (`session` / `models` / `stats` / `mcp` / `serve` など) のとき、接続先の決定・配信前検査・`--model` 注入の 3 段を飛ばして `command opencode` にそのまま渡す。**プローブより手前で分岐するので、サーバが両経路とも落ちていてもサブコマンドは打てる** (接続先の語を渡しても無視される)。モデルを使うのは `pr` だけ (checkout 後に起動する opencode が既定モデルを解決する。これも `opencode pr --model <任意> <番号>` が unknown option で help 表示に化けるため注入不能。実測) で、他は検査を絡めるとサーバが落ちていて一覧も見られないという誤った失敗方になるうえ、`--model` はサブコマンド側で unknown option として弾かれ、実行の代わりに help 表示になるだけだからである (2026-09-06 実測: `opencode --model spark/fake session list` は help しか出さず、素の `ocsp session list` はセッション表を出す)。**`run` は例外で、`--model spark/<名前>` と `--dir` を付けた専用経路のまま** (`run` は `--model` を受け付ける)。素通し対象は `opencode-spark.zsh` のホワイトリストで `opencode --help` の commands と対応しているが、**opencode のアップグレードで増えたサブコマンドはホワイトリストに無いため TUI 起動の組み立てに回る** (サーバが落ちているとそこまでに達せず配信前検査で止まる)。**その間は先頭 `--` の解除語で素通しできる** (2026-09-06 実測: `ocsp -- --version` は `opencode` 本体が `1.18.18` を出す)。

**その乖離は現に起きている。** `DeepSeek-v4.1-Flash-EXL3` の 600,000 はサーバと一致しているが、Vision-Exp と Qwen の 2 モデルは `limit.context` が 524,288 で、DeepSeek 系 (Vision-Exp) のサーバ上限は 1,048,576 である (「サービングの構成」)。Vision-Exp を配信しても OpenCode は 524,288 で頭打ちになる。**害は早めに圧縮が走ることだけで壊れはしない**ので放置してもよいが、直すなら `agents/bindings/opencode/opencode.json` の当該エントリを 1048576 にする。

**設定は `agents/bindings/opencode/{opencode.json,tui.json}` として dotfiles にあり、`nix/modules/home/opencode.nix` が `mkOutOfStoreSymlink` で `~/.config/opencode/` に貼る** (`agents/bindings/claude/settings.json` と同じ live edit)。`~/.config/opencode/` には opencode 自身が書くファイル (`node_modules` / `package.json` / `package-lock.json` / `.gitignore` など) と `nix/modules/home/harness.nix` が生成する `skills/` / `agents/` / `AGENTS.md` が同居する (移行時の残骸が残ることもある) ので、**symlink するのは `opencode.json` と `tui.json` の 2 枚だけ**である。**`opencode.json` 自体は `ocsp` 経由でも要る** (`provider.spark` の `npm` と `models` の宣言がここにしかないため。無ければ `ocsp` は起動前に止まる)。

**live edit になるのは `drs` を当てた世代からである。** それ以前の世代では同じパスが Nix store 内のコピーを指しており、dotfiles を編集しても反映されない。**どちらの状態かは `readlink -f` で判る** (→「依拠する外部事実」)。**単 hop の `readlink` では判らない。** `mkOutOfStoreSymlink` は 2 段の symlink を作り、1 段目は live でも `/nix/store/…-home-manager-files/…` を指すためである。2026-09-07 に再確認した時点でもこのマシンは live edit 側で、`opencode.json` の編集は `drs` 無しで次の起動から効く。

**`baseURL` に書いてある mDNS 名 (`http://spark-head.local:8888/v1`) は素の `opencode` 用の既定値である。** IP を書けば接続あたり約 210 ms 速いが (実測 224 ms 対 7〜21 ms)、このリポジトリは公開なので置かない。mDNS 名が遅いのは、到達できない IPv6 を 2 つ返し、それを試してから IPv4 に落ちるためである。`ccsp` は `NODE_OPTIONS=--dns-result-order=ipv4first` で回避しているが、opencode には相当する手段が無い。**`ocsp` からはこれを `CCSP_LAN_HOST` に IP を入れて避ける。Tailscale 側 (`http://spark-head`) に同種の遅延が出るかは未計測で、そちらを上書きする変数も無い。**

`autoupdate` は `false` にしてある (本体は Nix 管理で、store は書き換えられないため)。

### Codex (`cxsp`)

```bash
cxsp                       # 到達する方を自動選択し、配信中のモデルで codex を起動
cxsp lan                   # 自宅 LAN を強制 (プローブしない)
cxsp ts                    # Tailscale を強制
cxsp qwen                  # モデルを指定 (qwen / vision / v41)
cxsp lan qwen              # 接続先とモデルは順不同で並べられる
cxsp exec --skip-git-repo-check "README を要約して"   # codex のサブコマンドは素通し
cxsp status                # 起動せずに要求モデル・effort・両経路の到達性・配信中モデルを表示
cxsp -h                    # usage を出して終了 (`--help` / `help` も同じ)
cxsp -- --version          # 解釈を打ち切り (-- 自体を消費して) 以降を全部 codex へ
```

実体は `zsh/functions/codex-spark.zsh` である。**`ccsp` と違ってシェルに環境変数も alias も残さないので、`off` に相当する解除操作が要らない** (`ocsp` と同じ)。**素の `codex` は ChatGPT ログインのままで、この関数は一切触らない。**

押さえるべき点が 12 つある。

- **設定ファイルを置かず、`codex` の `-c` で 8 キーを起動ごとに注入する。** `--profile` は `$CODEX_HOME/<名前>.config.toml` を読む仕組みなので、使うと `~/.codex/` に状態が増えて素の `codex` と混ざる。`-c` はレイヤの最上位に近く、`/etc/codex/config.toml` (system) も `~/.codex/config.toml` (user) も上書きする。**root の `-c` は subcommand の前に置ける**ので (`codex -c … exec …`、2026-09-17 実測)、TUI も `exec` も `resume` も同じ注入で通る

  | キー | 値 | 理由 |
  | --- | --- | --- |
  | `model_provider` | `"spark"` | — |
  | `model_providers.spark.name` | `"DGX Spark vLLM"` | **空にすると設定全体が読めなくなる** (`model_providers.spark: provider name must not be empty`)。必須キーの一覧には現れないので、`-c` を書き足すときに落としやすい |
  | `model_providers.spark.base_url` | `<選んだ URL>/v1` | — |
  | `model_providers.spark.wire_api` | `"responses"` | **唯一の有効値。** `"chat"` は codex 0.154.0 で削除され、設定を読んだ時点でエラーになる |
  | `model` | `/v1/models` の配信名 | 短縮名を渡した場合は起動前に配信中かを検査する |
  | `model_context_window` | `max_model_len` と `CXSP_CONTEXT_MAX` (既定 500,000) の小さい方 | **このキーだけでは効かない** (下の `model_catalog_json` が要る)。上限を設けるのは、サーバの 600,000 をそのまま渡すと実効 570,000 トークンと長すぎるため。既定値は `agents/bindings/codex/config.toml` の `model_context_window` と同じ 500,000 に揃えてある |
| `model_catalog_json` | `cxsp` が起動ごとに書き出す catalog のパス (`~/.cache/cxsp/model-catalog.json`) | **これが無いと `model_context_window` は無視される。** codex は未知のモデル名に fallback metadata (`context_window` / `max_context_window` とも 272,000) を当て、設定値を `min(設定値, max_context_window)` でクランプする。`max_context_window` を宣言できるのは catalog だけである |
  | `model_reasoning_effort` | `_spark_effort` の値 | 上書きは `CXSP_EFFORT` |
  | `web_search` | `"disabled"` | `agents/bindings/codex/config.toml` が `"live"` を配っており、カスタム provider でも hosted の `web_search` tool が `tools` に載る。vLLM がこの tool 型を受けるかは未確認なので経路ごと切る |

- **`agents/bindings/codex/config.toml` は触らない。** `model` / `model_context_window` / `model_reasoning_effort` / `web_search` はすべて `-c` が上書きする。レイヤの優先度は低い順に system (`/etc/codex/config.toml`) < user (`~/.codex/config.toml`) < profile < project < `-c` である
- **API キーを扱わない。** `model_providers.<id>.env_key` を省くと codex は Authorization ヘッダ自体を送らず、**ChatGPT のトークンも流用しない** (`requires_openai_auth` の既定が false のため、ログイン画面も出ない)。`ccsp` のような資格情報の漏れ経路が無い
- **`/v1/responses` を使うのは `cxsp` だけである。** codex 0.154.0 が Responses API しか話さないため。この経路には**サーバ側にパッチが要る** (→「既知の制約」12)。パッチが当たっていないサーバへ向けると、最初のリクエストが `DeepSeek V4.1 supports text and image content only; got 'input_text'` の 400 で落ちる
- **モデル名とコンテキスト上限は `/v1/models` から取る。** 表を持たないので配信側のモデルを変えても Mac 側の編集は要らない。短縮名 (`qwen` / `vision` / `v41`) を渡した場合はそれが配信されているかを起動前に検査し、載っていなければ配信中の一覧を出して exit 1 で止まる。短縮名に無いモデルは `CXSP_MODEL=<配信名> cxsp` で渡す
- **reasoning effort は `ccsp` と同じ `_spark_effort` を引く。** V4.1 EXL3 については `/v1/responses` の全値を実測した (`low` / `high` / `xhigh` / `max` / `none` が 200、`medium` が 400。2026-09-17 →「V4.1 EXL3 の reasoning effort の語彙」)。**Qwen 系と DeepSeek 系についてこの経路の語彙は未実測である** (実測済みなのは `/v1/messages` と `/v1/chat/completions` だけ → 「Qwen の reasoning effort の語彙」)
- **コンテキスト上限は catalog で宣言する。** `-c model_context_window` だけでは効かない (上の表)。`cxsp` は起動ごとに codex 同梱の catalog へ配信名を 1 件 append して `~/.cache/cxsp/model-catalog.json` に書き、`-c model_catalog_json` で渡す。**全置換にしない**のは、codex がその一覧を全世界として扱い `/model` から OpenAI のモデルが消えるため。**`use_responses_lite` は `false` に落とす** — 土台 (`gpt-6-astra`) の `true` のままだと codex がツール定義を `tools` パラメータではなく `input` の先頭の `{"type": "additional_tools"}` item として送り、vLLM が `'AdditionalTools' object has no attribute 'get'` の 500 を返す (2026-09-17 実測)。`effective_context_window_percent` は土台の 95 のまま使う (100 にすると強制コンパクションの上限にも 100% が使われ、出力用の余白が消える)
- **呼び出し側が `-c` を渡しても安全にしてある。** codex は **subcommand 側に `-c` を 1 つでも置くと root 側の `-c` をすべて捨てる** (実測: `codex -c 'model_provider="nonexistent"' debug prompt-input "hi"` は exit 1、同じものに subcommand 側の `-c` を足すと exit 0 になる)。素直に `cxsp exec -c … ` と書くと Spark 向けの注入が丸ごと消えて**素の codex (ChatGPT ログイン) で走る**ので、`cxsp` は残り引数から `-c` / `--config` / `--config=` を拾って root 位置へ移す。cxsp の既定より後ろに積むので、渡した値が既定を上書きする
- **`/status` の分母は 1 回目と 2 回目で変わる。** 1 リクエストも送っていない間は `-c model_context_window` の生値 (500K)、最初の応答の後は catalog 由来の実効値 (500,000 × 95% = 475K) になる。**catalog を渡していないと 2 回目以降が 258K** (= 272,000 × 95%) に落ちるので、これが効いているかの判定に使える (2026-09-17 実測)
- **起動のたびに無害な警告が 2 種類出る。** どちらも 2026-09-17 に実測したもので、推論そのものは通る。
  - `failed to refresh available models: … missing field 'models' … body: {"object":"list","data":[…]}` — codex のモデルカタログ更新が OpenAI 専用の形を期待している。vLLM の `/v1/models` は OpenAI 互換の `data` 配列を返すので形が合わない。**推論の経路とは別**で、1 起動につき 2 回出る
  - `warning: Model metadata for 'DeepSeek-v4.1-Flash-EXL3' not found. Defaulting to fallback metadata` — **catalog を渡すようになって出なくなった** (2026-09-17 実測)。出るようになったら catalog が届いていない
- **Neovim の `<leader>xx` 系は `cxsp` を経由する。** herdr のペインには `agent="codex"` が付くのでペインの復元は効くが、`agent_session` (セッション UUID) は zsh を挟むと `null` になるので **herdr の `resume_agents_on_restore` は効かない** (`ocsp` も同じ。2026-09-17 実測)。**Spark に届かないときは `cxsp` が exit 1 で止まるのでペインがすぐ閉じる** — 素の `codex` (ChatGPT) を使いたいときは端末から直接打つ
- **`drs` を当てて新しいシェルを開くまで存在しない。** 関数本体は Nix store 経由で配られるので、既存シェルには定義が無い (`command not found`)

**合格判定**: `cxsp lan exec --skip-git-repo-check "1+1 は?"` が exit 0 で答えを返すこと。**2026-09-17 に V4.1 EXL3 配信中で実測した範囲**: 単発の生成 (`cxsp exec`)、ストリーミング (codex は常に `stream:true` を送る)、シェルツールの呼び出しとその結果を載せた 2 ターン目、effort の全値。**Qwen 系と Vision-Exp 系では `/v1/responses` 自体を試していない。**

**codex を上げたら 3 つ打ち直す** (`nix/modules/darwin/homebrew.nix` は `onActivation.upgrade` を立てていないので、上がるのは手動の `brew upgrade` のときだけ): `cxsp -- --version` で版を見て、「依拠する外部事実」の `codex doctor` の行と上の合格判定を流す。`wire_api` の有効値も root の `-c` の位置も 0.154.0 での実測なので、版が変わったら確かめ直す。

## 実測値

数値は条件が変わると簡単に 25% 動くので、表ごとに条件を書いてある。**閾値だけを覚えて条件を変えて測ると誤診する。**

**この節の値はすべて GPU クロック制限 (2,200 MHz) が有効な状態で採ってある。X925 の `scaling_max_freq` を下げたのは 2026-09-10 なので、それより前の日付の表はその前の値である** (前後で単一ストリームの所要時間に差が出ないことは確かめてあるが、この節の並列条件では取り直していない → 「既知の制約」4・5)。

### L1: サーバ単体 (2026-09-05)

`~/spark-bench/bench.py` でサーバを直叩きした値である。条件はプロンプト 6,000 トークン、`max_tokens` 256、`chat_template_kwargs={"thinking": true, "reasoning_effort": "low"}` (サーバ既定の `DEFAULT_THINKING=low` と同じ)、指示は「上記は無視して、TypeScript の関数を 1 つ書いてください。説明は不要でコードだけ返してください。」`c` は `--concurrency`。中央値と (最小〜最大)。

**`chat_template_kwargs` は `--extra-body` でしか渡せない。** `bench.py` はこのキーの既定を持たないので、下の再現コマンドから `--extra-body` を落とすと条件が変わる (思考が既定のまま走る)。**これはテンプレートに直接渡す第 4 の経路である。** 3 つのクライアントが使う `reasoning_effort` (`ocsp`) / `output_config.effort` (`ccsp`) / `reasoning.effort` (`cxsp`) と違い、スキーマの Literal 検査を通らずにテンプレートへ届く。`bench.py` は `min_tokens` を `max_tokens` と同値にし `ignore_eos` を立てるので、生成長は常に 256 トークン固定である。

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

測定はいずれも Vision-Exp 配信中に取った。**effort の条件は現行の既定と違う。** この計測は Claude Code 側が静的な `medium`、OpenCode 側が未指定 (テンプレート既定) だった時点のもので、現在は `_spark_effort` と `opencode.json` が配信モデルごとに決めた値を送る。**effort は system への指示文を変えるので、下の受理率とプロンプト長は条件を跨いで比較しない。**

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
5. **サーバ本体** — ここまで潰してから L1 のベンチを上のフラグで回す。**GPU クロックは 2,200 MHz に制限してあり、X925 の `scaling_max_freq` も下げてある** (→ 「既知の制約」4・5)。どちらも外しても速度はほぼ変わらないと実測済みなので、ここを最初に疑わない。切り分けのために外すなら、**外して測って戻すところまでを 1 セットで行う** (戻し忘れると温度だけが上がった状態が残り、サーバ側に履歴が無いので誰も気づけない → 制約 6)

3 と 4 の計算は `/metrics` から行う。**キー名は完全一致で拾う。** `prefix_cache` には `vllm:external_prefix_cache_*` が、`spec_decode_num_.*_total` には `vllm:spec_decode_num_accepted_tokens_per_pos_total` が別に存在し、緩い grep は別系列を合算して値を過大に出す。

```bash
curl -s http://spark-head.local:8888/metrics | grep -E '^vllm:(prefix_cache_(hits|queries)_total|spec_decode_num_(accepted_tokens|draft_tokens)_total|request_(prompt|generation)_tokens_sum|request_success_total)'
```

- prefix ヒット率 = `prefix_cache_hits_total` ÷ `prefix_cache_queries_total`
- 受理率 = `spec_decode_num_accepted_tokens_total` ÷ `spec_decode_num_draft_tokens_total`
- 1 リクエストの平均生成長 = `request_generation_tokens_sum` ÷ `request_success_total` の**全 `finished_reason` の合計** (`stop` / `length` / `abort` / `error` / `repetition` の 5 行に分かれて出るので足す。`length` が多ければ出力の打ち切りが起きている)

**本構成の律速は decode ではなく prefill である。** 実負荷での累計プロンプト対生成トークン比は 100:1 前後、1 リクエストの生成長は数百トークンにとどまる。decode を速くする施策は体感に効きにくい。**これらの counter は vLLM コンテナの再起動でリセットされるので、値は「現コンテナが起動してからの累計」として読む** (絶対値は窓の取り方で動く)。

## 障害時

**コンテナ名は系統で違う。** DeepSeek 系は `deepseek-v4-flash-vllm-dspark-1`、Qwen 系は `vllm-fn` (両ノードとも同名)、V4.1 EXL3 系は `dsv41-exl3-head` / `dsv41-exl3-worker` である。

**表の確認手段に `ccsp status` / `ocsp status` / `cxsp status` を使う行があるが、Claude の Bash ツールから打っても正しい判定にならない** (関数自体はスナップショットに入っているが `_spark_*` ヘルパーが無く、URL が空のまま「に届かない」と表示する →「依拠する外部事実」)。切り分けは `curl -fs -o /dev/null http://spark-head.local:8888/health` で行う。

| 症状 | 確認 | よくある原因 |
| --- | --- | --- |
| 応答しない | 下の待ち行列コマンド | コンテナは生きていて過負荷。同時リクエスト上限 (DeepSeek 系 6 / Qwen 系 8 / V4.1 EXL3 系 2) を超えた分が待つので、待ち行列が 0 でなければ過負荷。**V4.1 EXL3 系は 2 本しか並ばないので、subagent を並列に投げると待ちやすい** |
| コンテナが無い | 両ノードで「系統の切り替え」の手順 3 のコマンド (3 系統すべてを拾う。表のセルに書くと `\|` のエスケープが混ざってそのまま打てないので、そちらをコピーする) | 停止コマンドで止めたまま、またはノードの再起動 (Qwen 系と V4.1 EXL3 系は再起動で上がらない。DeepSeek 系は上がる → 「既知の制約」8)。起動し直す |
| 起動に失敗する | `./logs-deepseek-v4-flash-dspark.sh` (Qwen 系は `docker logs vllm-fn`、V4.1 EXL3 系は `./start.sh logs` / `./start.sh logs worker` と、レシピの `logs/head.log` / `logs/worker.log` / `logs/overlay-verify.log`) | DeepSeek 系の `no usable RoCEv2 GID` は RoCE 2 本目の IP か MTU (Qwen 系は `IB_HCA` が 1 本なのでこの形では出ない)。Qwen 系は相手系統が GPU を掴んだままだと `REQUIRE_IDLE_GPU` で拒否される。V4.1 EXL3 系は `not enough free unified memory` (相手系統が動いている → 「系統の切り替え」の手順 3)、`FileNotFoundError: /models/config.json` (→「導入と再導入の落とし穴」4)、`logs/hang-*-pyspy.txt` (head のログが 420 秒止まると書かれる)。**V4.1 EXL3 系は失敗してもコンテナが残るので、`./start.sh stop` してから起動し直す** |
| Qwen 系がコンテナを作らずに `Checkpoint snapshot is incomplete` で止まる | `python3 files/resolve_snapshot.py <hub の repo ディレクトリ>` の exit code (0 以外) | シャードの欠落。`0b62e12` から `start.sh` が起動前に検査するようになった (→「重みの検証」)。**コンテナが 1 つも作られないので `docker logs vllm-fn` は空振りする。`start.sh` の標準出力を見る。** 復旧は Qwen レシピ同梱の `./download.sh` (HuggingFace から重みを取り直すスクリプト。`--launch` を付けない素の `./start.sh` が内部で呼ぶのと同じもの) での再取得だが、**revision を指定しないと配信 revision が動く** |
| `model not found` が出る | `curl .../v1/models` で配信名を見る | セッション起動後にサーバ側で切り替えた。`ccsp` / `ocsp` / `cxsp` は起動時のモデル名を送り続けるので起動し直す |
| `ocsp` が「`<名前>` は配信されていません」で止まる | メッセージが出す配信中の一覧 | 要求した短縮名と実際の配信モデルが違う。これは異常ではなく配信前検査が効いた状態。**この文言を出すのは `ocsp` だけ** |
| `ccsp` / `ocsp` / `cxsp` が「取得できません」で止まる | `ccsp status` / `ocsp status` / `cxsp status` でサーバの生死を見る。メッセージが出す URL も見る | **`ccsp` と `cxsp` はこの 1 文言に 2 つの原因を束ねている。** 要求したモデルが配信されていない場合と、サーバに届かない場合の両方。メッセージが続けて出す「配信中: …」が空なら後者。認証を復活させた場合も 401 でこうなる (→「API キーの流れ」)。**接続先を誤った側に強制した場合 (出先で `lan`、自宅で `ts`) もプローブを飛ばしてここに落ちる** |
| `ccsp` / `ocsp` / `cxsp` が「LAN にも Tailscale にも届きません」で止まる | `ccsp status` / `ocsp status` / `cxsp status` の LAN 行と TS 行 | どちらの `/health` にも届かなかった。サーバが落ちているか、出先で Tailscale にサインインしていない。接続先が判っているなら `lan` / `ts` で強制できる (プローブを飛ばす)。**強制した先も死んでいれば次は上の「取得できません」に変わる** |
| `cxsp` が `DeepSeek V4.1 supports text and image content only; got 'input_text'` の 400 で落ちる | `ssh -n spark-head 'docker logs dsv41-exl3-head 2>&1 \| grep dsv41-responses-parts'` | サーバ側のパッチが当たっていない。配信を上げ直したときにパッチファイルか `start.sh` の 2 行が失われている (典型は `git pull` で `start.sh` が上書きされたとき) → 「既知の制約」12 |
| `codex` が `provider name must not be empty` で設定を読めない | `cxsp` が組み立てる `-c` の一覧 | `model_providers.spark.name` が空。このキーは必須キーの一覧に現れないので落としやすい (→「Codex (`cxsp`)」) |
| `codex exec` が git リポジトリの外で実行を拒否する | 実行したディレクトリ | `--skip-git-repo-check` を付ける。`cxsp` は素通しするので `cxsp exec --skip-git-repo-check "…"` と書く |
| `ocsp` が「OpenCode の設定がありません」で止まる | `ls -l ~/.config/opencode/opencode.json` (`readlink -f` はファイルが無いと空出力 + exit 1 を返すので実体を見る) | `drs` 未実行でファイルが無い。`provider.spark` の `npm` と `models` の宣言がここにしかないので、接続先を上書きする方式でも起動前に止まる |
| `Unexpected reasoning effort <値>` の 400 | 送っている effort の値 (`CCSP_EFFORT` / `CXSP_EFFORT` / `opencode.json`) | **3 つの経路すべてで出る。** 検査はチャットテンプレートにあり、`/v1/messages` も `/v1/chat/completions` も `/v1/responses` も同じテンプレートを通る (→「Qwen の reasoning effort の語彙」)。Qwen で使えるのは `low` / `medium` / `xhigh` の 3 つ。**Qwen 配信中は既定の設定で踏まない** (`_spark_effort` と `opencode.json` が `xhigh` を持つ)。踏むのは (1) `CCSP_EFFORT` に語彙外の値を入れたとき (2) `_spark_effort` / `opencode.json` に登録していないモデルを配信したとき (既定の `high` が飛ぶ) (3) **DeepSeek 系に切り替えた最初の 1 回** (3 つのクライアントが送る `high` はレシピの語彙に合わせただけで未実測)。**V4.1 EXL3 系では文言が違い**、`DeepSeek V4.1 reasoning_effort must be low, high, xhigh, max, or an integer within [1, 100]` の 400 になる。弾くのは vLLM 側の検査で、踏むのは `medium` を送ったとき (Qwen 用の `CCSP_EFFORT=medium` / `CXSP_EFFORT=medium` が残っている場合が典型 → 「系統の切り替え」の手順 1) |
| `Input should be 'low', 'medium', ...` の 400 | 送っている effort の値 | `ccsp` の経路 (`/v1/messages`) に `none` を渡した。スキーマが `none` を持たないため、テンプレートより手前で弾かれる。**`ocsp` の経路では `none` が通る**という非対称がある (→「Qwen の reasoning effort の語彙」) |
| OpenCode がモデルを拒否する | `agents/bindings/opencode/opencode.json` の `provider.spark.models` | 宣言の無いモデル名は OpenCode 側が受け付けない |
| 起動待ちが長すぎる | head は `docker logs <コンテナ名>`、worker は「worker に入る」節のコマンドで同じものを打つ | 正常な所要は DeepSeek 系が約 6 分、Qwen 系が約 13〜14 分、V4.1 EXL3 系がコンテナ起動から health まで約 8 分 (いずれも実測)。DeepSeek 系は 10 分、Qwen 系は 20 分を超えたら worker 側だけ落ちていることがあるので両ランクを見る。V4.1 EXL3 系は 15 分を超えたら `./start.sh logs worker` で worker 側を見る。`start.sh` は health を 1,500 秒待って諦め、そのときもコンテナは残る (→「起動に失敗する」の行) |
| 推論中に CPU が熱い・ファンがうるさい | 「依拠する外部事実」の温度の行と、同節のコードブロック 5 | 正常。vLLM のスレッドが GPU / NCCL の完了をビジーポーリングで待ち、100% の使用率で回る (→ 「既知の制約」5)。計算しているわけではないので、`nvidia-smi` の GPU 使用率が高いこととは独立に CPU 側センサーが上がる。X925 の `scaling_max_freq` を下げる対処は既に入れてあり (制約 5)、それでも高いなら室温か吸気を疑う |
| 起動直後から空きメモリが少ない | `free -h` | DeepSeek 系と Qwen 系なら正常。確保率 0.835 の先取りで、残る量は DeepSeek 系 6〜8 GiB、Qwen 系の head は 1.3〜5.7 GiB。**V4.1 EXL3 系の head の 6.0〜6.5 GiB は先取りではなく実際の余裕** (重み 98.86 GiB + 固定の KV プール 2.5 GiB) で、配信中はこれ以上減らさない (→「既知の制約」11) |
| 配信中に応答が止まった (V4.1 EXL3 系) | `curl -fs -o /dev/null http://spark-head.local:8888/health`、待ち行列コマンド、両ノードの `docker ps` | 起動中の hang 検知 (420 秒) は配信中には働かない。health が返らない、または `num_requests_running` が動かないまま時間が経つなら、`./start.sh stop` → 「系統の切り替え」の手順 3 → `./start.sh`。片方のノードに ssh も通らない場合は「既知の制約」11 |
| `hi` と打っただけで network retry | `ccsp status` で LAN 到達を確認 | mDNS の IPv6 フォールバック。`NODE_OPTIONS` に `--dns-result-order=ipv4first` が入っているか見る |
| 応答後に 200 秒以上返らない | `settings.spark.json` の `enabledPlugins` | `security-guidance` の Stop hook (→「遅いと感じたときに疑う順序」1) |
| 全体的に遅い | 「遅いと感じたときに疑う順序」を上から | クライアント側が大半 |
| ダッシュボードの worker が古いモデル | `curl -s http://spark-head.local:5555/api/sparks` の worker 行 | `workerLabel` は手書きの静的文字列で、実機とは無関係に表示される。ファイルを直しても `docker restart sparkDash` するまで画面は変わらない。直し方は→「sparkDash の `workerLabel` を直す」 |
| ssh 出力が途中で切れる | 打ったコマンド | 入れ子の `ssh` が標準入力を飲んでいる。内側に `-n` を付ける |
| `ccsp` / `ocsp` / `cxsp` が `command not found` | `type ccsp` が `function` を返すか | 3 つとも Nix 配布なので、`drs` 未実行か、`drs` 後に新しいシェルを開いていない |

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
- **head の `~/dsv41-local/` と `start.sh` のローカル差分 2 行** — 消すと `cxsp` だけが静かに壊れる (`ccsp` / `ocsp` は無傷なので他の確認は green のまま通る →「既知の制約」12)
- **公開リポジトリ内のファイルへの IP 直書き** — 本書・`zsh/functions/*.zsh`・`agents/bindings/opencode/opencode.json` のいずれにも書かない。IP は `CCSP_LAN_HOST` (シェル変数) で渡す。**3 つのクライアントがこの変数を見る**ので、`opencode.json` を編集する必要は無い
- **公開リポジトリ内のファイルへの API キー直書き** — 認証を戻すときも `opencode.json` に平文で置かない。`{file:~/…}` か `{env:…}` で外部へ逃がす (`_ocsp_resolve` と opencode 本体の両方が解く → 「API キーの流れ」)
- **クロック制限の 2 unit** (`nv-gpu-clock-limit.service` / `nv-cpu-clock-limit.service`) — 切り分けで一時的に外すのは構わないが、外したままにしない。サーバ側に温度の履歴が無いので戻し忘れに誰も気づけない (→ 「既知の制約」4・5・6)
- **sparkDash のポート 5555** — 認証が無いので信頼できないネットワークへ出さない
- **ポート 8888** — 系統を問わず無認証なので外に出さない (→「API キーの流れ」)
- **0731 の残置物** — head の `~/dspark-0731` (detached `70a7cc4` の git worktree、4.4 MB) と両ノードの重み 156 GiB ずつ。**使わないが消さない。** ディスクは 2.5 TiB 空いていて (→「ハードウェアと OS」) 消す動機が無く、再取得は HuggingFace から約 5.5 時間かかる

## 既知の制約

1. **Spark には passwordless sudo が無い。** `/etc/sudoers.d/` は README のみである。`nvidia-smi --lock-gpu-clocks`・`scaling_max_freq` への書き込み・systemd の操作など sudo が要る作業は Claude からは実行できないので、コマンドを提示して人間に実行してもらう (パスワードは `skanehira` の Ubuntu ログインパスワードで、本書には保管しない)。Mac の Touch ID による sudo は Linux ノードには効かない。**コンテナ内で root が必要な作業は `docker run --entrypoint` で代替できる** (重みの所有権修正など)
2. **worker への直接 ssh は `known_hosts` の登録が前提である。** 未登録のマシンでは Claude から入れないので「worker に入る」節の head 経由を使う
3. **worker は Tailscale に参加していない** (`tailscaled` が未インストール)。出先から worker を見るには head を経由する
4. **GPU クロックを 2,200 MHz に制限している。** 両ノードの `/etc/systemd/system/nv-gpu-clock-limit.service` (手で配置した unit、enabled + active) が起動時に `nvidia-smi --lock-gpu-clocks=0,2200` を実行する。2026-09-05 の計測 (n=5、L1 とは別条件で結果ファイルは残っていない) では、解除しても decode +1.3% / 最悪 TTFT 約 +2% しか上がらず温度が 7 °C 以上上がった (制限あり 52〜58 °C / 制限なし 60〜65 °C) ので、制限は維持する
5. **X925 の `scaling_max_freq` を 2,808 MHz に下げてある。unit 名に反して、これはハードウェアのクロック上限を変えていない。** 両ノードの `/etc/systemd/system/nv-cpu-clock-limit.service` (手で配置した unit、`Type=oneshot` + `RemainAfterExit=yes`、enabled + active) が起動時に cpu5-9・cpu15-19 の `scaling_max_freq` へ `2808000` (kHz = 2,808 MHz。sysfs の周波数はすべて kHz) を書く。**dotfiles に控えが無いので下に全文を載せる** (制約 9 の `~/spark-bench` と同じく再作成手段が無い資産である)。**効いていないもの (実測)**: 書き込みは受理されるが CPPC のレジスタに伝播しない。`max_perf` は cpu5 が 3900000、cpu19 が 4004000 のままで、負荷中に X925 のコアが走るとその実効クロック (`cpuinfo_avg_freq`) は 3,886,695〜3,898,425 に達する。**`scaling_cur_freq` は `cppc_cpufreq` では要求値のエコーなので実効値と読んではいけない** (busy な A725 は要求値と実効値が一致するのに busy な X925 だけ 1.1 GHz 乖離する。この非対称がエコーであることの対照になる)。**実際に起きていること (実測)**: 書き込みの前後で **vLLM の busy スレッドの載り先が X925 から A725 へ移った**。前は cpu15 が 70%・cpu18 が 78% と X925 が主だったのに対し、後は cpu0〜cpu4 のうち 3 本が 91〜100% で回る。**X925 が使われなくなったわけではない** — 連続負荷中に 8 回サンプルしたうち 1 回は cpu19 が 92% で busy になり、そのときの実効クロックは 3,882,785 だった。**どういう条件で X925 に載るかは特定していない。****理由は「`scaling_max_freq` を下げたことでスケジューラの capacity の見立てが変わり X925 を選ばなくなった」と読んでいるが、確認していない (推測)。** **推論中に CPU が熱くなるのは計算しているからではない。** vLLM のスレッド 3 本 (`VLLM::EngineCore` / `VLLM::Worker_TP` / `VLLM::Worker`) が 100% の使用率で回り続け、その間クロックが最大に張り付く。**実測から言えるのはここまでで、「ビジーポーリングで待っている」は推測である** — 同じ区間で GPU が 93% 動いており、スレッドが自発的にブロックする回数が 1 ステップあたり 2〜5 回しかないことから、CPU 時間の大半は実処理ではなく完了待ちのスピンだと読んでいる。スタックは追っていないので、待ち先が CUDA の同期か NCCL かは未確認である (1 decode ステップ 63 ms のうち GPU 使用率は 93%、スレッドが自発的にブロックするのは 1 ステップあたり 2〜5 回。取得手段は「依拠する外部事実」の該当行)。**需要に追従する governor (`schedutil` / `ondemand` / `conservative`) に変えても効かない。** スピンするスレッドは使用率 100% に見えるので、どれも最大クロックを選ぶ。**唯一の例外は `powersave` で、これは最小クロックに固定するため温度は下がるが、直列処理まで 338 MHz に落ちるので速度への影響が別物になる。本書では試していない (未検証)。****2026-09-10 の計測 (Qwen3.8-Flash-Next 配信中、単一ストリーム・800 トークン、GPU 制限は両方の条件で有効、n = 制限前 3 / 制限後 2、結果ファイルは残していない) では速度低下は無く** (制限前 26.06〜26.80 秒 / 制限後 24.55〜26.02 秒)。**2 群のレンジはわずかに重ならず、制限後の方が速い。これは説明できていない** (n が 3 と 2 と少ない、prefix cache の状態が揃っていない、直前の熱状態が違う、のいずれもありうる)。**言えるのは「遅くなってはいない」までで、「速くなった」とは読まない。** 温度は **TS0P が 62.0 → 47.7〜49.5 °C、TSOC が 62.5 → 52.5〜53.6 °C に下がった** (センサー名は下の制約 6 とその読み方を参照)。**速度が変わらないことは効果の判別に使えない** — 設定が効いていなくても速度は変わらないので、両方の仮説と整合してしまう。判別材料は温度と busy コアの載り先だけである。**並列時 (Qwen は最大 8 リクエスト) は未計測である。****この設定は目的 (温度を下げる) を達しているが、意図した機構では動いていない。** 素直にクロックを縛りたいなら CPPC の `max_perf` を動かす手段を別に探す必要がある。解除は両ノードで `sudo systemctl disable --now nv-cpu-clock-limit.service` (`ExecStop` が `cpuinfo_max_freq` の値を `scaling_max_freq` へ書き戻す)、戻すのは `sudo systemctl enable --now nv-cpu-clock-limit.service`。worker には「worker に入る」節のコマンドで同じものを打つ (sudo が要るので実行は人間)

   ```ini
   [Unit]
   Description=Limit Cortex-X925 max clock to 2808 MHz (CPU thermal headroom during vLLM inference)
   ConditionPathExists=/sys/devices/system/cpu/cpu19/cpufreq/scaling_max_freq

   [Service]
   Type=oneshot
   RemainAfterExit=yes
   ExecStart=/bin/sh -c 'for c in 5 6 7 8 9 15 16 17 18 19; do echo 2808000 > /sys/devices/system/cpu/cpu$c/cpufreq/scaling_max_freq; done'
   ExecStop=/bin/sh -c 'for c in 5 6 7 8 9 15 16 17 18 19; do cat /sys/devices/system/cpu/cpu$c/cpufreq/cpuinfo_max_freq > /sys/devices/system/cpu/cpu$c/cpufreq/scaling_max_freq; done'

   [Install]
   WantedBy=multi-user.target
   ```

6. **温度センサーは ACPI の 7 つで、履歴はどこにも残っていない。** `/sys/class/thermal/thermal_zone{0..6}/temp` がミリ °C を返す。名前は起動ログ (`journalctl -b -q -o cat | grep 'Thermal Zone \['`) が登録順に出す。zone0 = `TSOC` (SoC 全体) / zone1 = `TS0E` / zone2 = `TS0P` / zone3 = `TS1E` / zone4 = `TS1P` / zone5 = `TGPU` / zone6 = `TUNC`。**`TS<n>E` / `TS<n>P` が効率コアと性能コアに対応するという読み方は本書の推測で、NVIDIA の公表資料では裏を取っていない** (X925 の制限で `TS0P` が 14.3 °C 下がった実測とは整合する)。トリップ点は全 zone とも 104.8 °C、`policy` は `step_wise` である。`TSOC` の 3 文字目は英字の O、`TS0P` / `TS0E` の 3 文字目は数字のゼロで、grep するとき紛らわしい。**サーバ側に残る履歴は無い。** sparkDash は CPU 温度も採るが (head の `~/sparkDash/server/collectors/SystemCollector.js` が hwmon の `acpitz` と thermal zone を読む)、履歴はブラウザのメモリ (`~/sparkDash/src/hooks/metricsStore.ts` の `HISTORY_MAX` = 1,800 サンプル。このリポジトリの `docker-compose.override.yml` が `POLL_INTERVAL_CPU` を 15 秒にしているので約 7.5 時間分) にしか無く、ページを閉じれば消える。journald に出るのは起動時の 1 回だけ (7 zone 分 7 行)。`collectd` / `netdata` / prometheus exporter の類は両ノードとも動いていない (2026-09-10 実測)。**したがって過去に遡った統計は取れない。** 必要になったら記録の仕組みを先に用意する
7. **停止と再起動はユーザーの作業を止める。** 打つ前に `curl -s http://spark-head.local:8888/metrics | grep -E '^vllm:num_requests_running\{'` で稼働中リクエストの有無を確認し、Mac 側では先に `claude` を終了して `ccsp off` で退避する (`ocsp` と `cxsp` は環境変数を残さないので退避操作が要らない。`CCSP_EFFORT` / `CXSP_EFFORT` を export していたら `unset` する)
8. **vLLM の自動復帰は系統で違う。** DeepSeek 系コンテナの restart policy は `unless-stopped` だが、**Qwen 系 `vllm-fn` と V4.1 EXL3 系 `dsv41-exl3-head` / `dsv41-exl3-worker` は両ノードとも `no` なので、ノードを再起動すると上がってこない** (Qwen 系は 2026-09-06、V4.1 EXL3 系は 2026-09-15 に実測)。手で Qwen 系は `./start.sh --launch`、V4.1 EXL3 系は `./start.sh` を打ち直す (重みの同期はマーカーで省略されるので速い)。sparkDash は `always`、`docker` と (head の) `tailscaled` は enabled、RoCE は NetworkManager の autoconnect、GPU と CPU のクロック制限は 2 つの unit がどちらも enabled である (→ 制約 4・5)。どの系統も停止スクリプトで止めた後はコンテナ自体が消えるので再起動しても復帰しない。**cold boot での復帰は未確認なので、電源断の後は `docker ps` で確かめる**
9. **`~/spark-bench` は再作成手段が無い。** dotfiles にも上流にも無い手書きのハーネスなので、head を作り直すと失われる
10. **3 系統の vLLM は同時に起動できない。** ポート 8888 と GPU を共有し、Qwen 側は `REQUIRE_IDLE_GPU=true`、V4.1 EXL3 側はメモリの事前検査が明示的に拒否する。切り替えは必ず「相手を停止 → 起動」の順で行う (→「系統の切り替え」)
11. **V4.1 EXL3 系はメモリの余裕が薄い。** 配信中の head の `MemAvailable` は 6 GiB 前後である。上流は `MAX_MODEL_LEN` 614,400 の構成で 601k トークンの prefill 中に 2.1 GiB まで下がったと書いている (当方の 600,000 では同じ入力は入らないが、長い prefill ほど下がる傾向は同じと見ている。未検証)。**上流の報告では、GB10 は統合メモリが尽きるとエラーではなくノードごと固まり、ハード再起動まで戻らなかった。** 当方では起きていないので、固まったときの兆候と復旧は未確認である。想定される兆候は、ssh も sparkDash も応答しないことと、worker だけが固まった場合に head の `/health` が応答しなくなることである。その場合は人が電源を入れ直す (sparkDash の Wake-on-LAN は電源断からの起動用で、固まったノードに効くかは未確認)。**配信中のノードで重い処理 (ダウンロード・ビルド・大きなファイルの展開) を流すときは `systemd-run --user --scope -p MemoryMax=<上限>` で上限を付ける** (`ssh -n` 経由では `XDG_RUNTIME_DIR=/run/user/$(id -u)` を前置する。head では 2026-09-15 に効くことを確かめた。worker では未確認)。**memguard (→ 用語表) は上流既定のまま無効にしている。** 上流によれば、有効にして唯一発動したときは無関係なホストのプロセスがメモリを取った場面で、原因ではない vLLM を kill しただけだった。代わりに両コンテナは `--oom-score-adj 1000` で起動されていて、カーネルの OOM killer が動けばデスクトップより先に vLLM が落ちる
12. **`/v1/responses` は head のパッチに依存している。** 配信イメージ `ghcr.io/miaai-lab/deepseek-v4.1-flash-exl3-2x-dgx-sparks:2.9bpw` が `FROM` で使うベース `vllm/vllm-openai:deepseekv41-flash-0909` (レシピの `Dockerfile` の `ARG BASE`) に入っている `vllm/tokenizers/deepseek_v41.py` の `_normalize_messages` は、メッセージの content パーツを `text` / `image_url` / `input_image` / `image_pil` しか受けない。Responses API と Codex が使う `input_text` は 400 になる (`DeepSeek V4.1 supports text and image content only; got 'input_text'`)。**上流 vLLM の `main` は既に `("text", "input_text", "output_text")` を受けるので、これはイメージが古いだけである。** head の `~/dsv41-local/patch_responses_content_parts.py` がその 1 行を起動のたびに当て直す (**`ccsp` と `ocsp` の経路はパッチが無くても動く**ので、壊れていることに気づくのは `cxsp` だけである)。

    - **パッチ本体は clone の外 (`~/dsv41-local/`) に置いてある。** レシピの `overlay/` に置くと `overlay_recipe_hash` (`Dockerfile` + `overlay/` + `files/` + `tests/` の hash) が動き、イメージの `dsv41.recipe.stamp` と食い違って**レジストリから約 9 GiB を pull し直す**。この分岐を止めるのは `SKIP_PULL` / `BUILD` であって `SKIP_BUILD` ではない
    - **`start.sh` は上流追跡ファイルなので 2 行がローカル差分になる。`git pull` で消える。** head 用スクリプトのパッチループに `         /opt/dsv41/patch_responses_content_parts.py \`、head コンテナの `docker run` の `-v` ブロックに `        -v "$HOME/dsv41-local/patch_responses_content_parts.py:/opt/dsv41/patch_responses_content_parts.py:ro" \` を足してある。**worker 側には足していない** — トークナイズは head の API サーバでしか走らないため
    - **パッチループは失敗を `WARN` で握り潰す。** そのためパッチ自身がアンカーの有無を検査して非 0 で終わるようにしてある。適用できたかは `docker logs dsv41-exl3-head` の `[dsv41-responses-parts]` の行で見る (レシピの `logs/` には出ない)。**判定の本体は「依拠する外部事実」の `input_text` の curl である**
    - **上流がイメージを更新したらパッチは不要になる。** アンカーが見つからないと非 0 で終わるので、そのときは `docker logs dsv41-exl3-head` に FATAL が出る。撤去は `start.sh` の 2 行を戻して `~/dsv41-local/` を消す
    - **Qwen 系と Vision-Exp 系で同じ問題が出るかは未確認である。** このトークナイザは V4.1 EXL3 系だけが使う
    - **`git pull` と再 clone の後は必ず当て直す。** 手順は「レシピを更新する (V4.1 EXL3 系)」と「導入手順」に組み込んである。合格判定は「依拠する外部事実」のコードブロック 8 が 200 を返すことである
    - **dotfiles に控えが無いので下に全文を載せる** (制約 5 の systemd unit と同じ扱い)。head を作り直したらこれを `~/dsv41-local/patch_responses_content_parts.py` に書き、実行ビットを立てる

    ```python
    #!/usr/bin/env python3
    """Accept Responses-API content parts in the DeepSeek V4.1 tokenizer.

    The image `vllm/vllm-openai:deepseekv41-flash-0909` ships a
    `_normalize_messages` that only accepts `text` for textual content parts, so a
    request whose message content is `[{"type": "input_text", ...}]` fails with

        DeepSeek V4.1 supports text and image content only; got 'input_text'

    That is the exact shape the OpenAI Responses API uses, and the only shape the
    Codex CLI (>= 0.154.0, which dropped `wire_api = "chat"`) can send. vLLM main
    already widened the tuple to ("text", "input_text", "output_text"); this is a
    backport of that one line onto the pinned image.

    Upstream: vllm/tokenizers/deepseek_v41.py on vllm-project/vllm@main.

    Idempotent: re-running after the patch is a no-op. Exits non-zero when the
    anchor is missing, because start.sh's patch loop swallows failures with a WARN
    and a silent no-op would look exactly like a working server until the first
    Codex request.
    """

    from __future__ import annotations

    import sys
    from pathlib import Path

    OLD = '                if part_type == "text":\n'
    NEW = '                if part_type in ("text", "input_text", "output_text"):\n'
    MARK = NEW.strip()


    def main() -> int:
        try:
            import vllm
        except Exception as exc:  # pragma: no cover
            print(f"[dsv41-responses-parts] FATAL: cannot import vllm: {exc!r}")
            return 1

        target = Path(vllm.__file__).resolve().parent / "tokenizers" / "deepseek_v41.py"
        if not target.is_file():
            print(f"[dsv41-responses-parts] FATAL: {target} not found")
            return 1

        text = target.read_text()

        if MARK in text:
            print(f"[dsv41-responses-parts] already patched: {target}")
            return 0

        count = text.count(OLD)
        if count != 1:
            print(
                f"[dsv41-responses-parts] FATAL: anchor found {count} times "
                f"(expected 1) in {target}; upstream changed, patch not applied"
            )
            return 1

        target.write_text(text.replace(OLD, NEW))
        print(f"[dsv41-responses-parts] patched: {target} (input_text/output_text accepted)")
        return 0


    if __name__ == "__main__":
        sys.exit(main())
    ```

## 依拠する外部事実

2026-09-06 に実機で確認した (**行に日付があるものはその日付が優先**。「実測値」節の性能値のみ 2026-09-05)。作業前に変わっていないか確かめる。**いまはどのエンドポイントも無認証なので、確認コマンドにキーは要らない。**

| 事実 | 確認コマンド |
| --- | --- |
| IP・インタフェース構成・MTU | `ssh -n spark-head 'ip -4 -o addr show; ip -o link show'` |
| ドライバとカーネル | `ssh -n spark-head 'nvidia-smi --query-gpu=driver_version --format=csv,noheader; uname -r'` |
| ディスクの空き | `ssh -n spark-head 'df -h /'` |
| メモリの内訳 | `ssh -n spark-head 'grep -E "^Mem" /proc/meminfo; swapon --show; nvidia-smi --query-compute-apps=used_memory --format=csv,noheader'` |
| DeepSeek 系のサービングの設定値 | `ssh -n spark-head 'cd ~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark && ./validate-dspark-config.sh \| head -20'` (絞らないと解決値の後に vLLM コマンド全文が数 KB 続く) |
| DeepSeek 系レシピの上流の先行コミット | `ssh -n spark-head 'cd ~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark && git fetch -q && git rev-list --count HEAD..origin/main && git log --oneline HEAD..origin/main'` |
| 全モデルの重み | `ssh -n spark-head 'du -sh ~/.cache/huggingface/hub/models--* ~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks/{model,engram-src} ~/dsv41-engram'` (HF キャッシュの全モデルとレシピ直下の V4.1 EXL3 系を拾う。worker の V4.1 EXL3 系は `~/.cache/dsv41-flash-exl3/{model,engram-src}` と `~/dsv41-engram`) |
| Qwen レシピの commit | `ssh -n spark-head 'cd ~/Qwen3.8-Flash-Next-Dual-DGX-Sparks && git log --oneline -1'`。上流の先行分は同じディレクトリで `git fetch -q && git log --oneline HEAD..origin/main` |
| V4.1 EXL3 レシピの commit | `ssh -n spark-head 'cd ~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks && git log --oneline -1'` (2026-09-15 時点 `8530568`)。上流が先行していたら `git log --stat HEAD..origin/main` で `Dockerfile` / `overlay/` / `files/` / `tests/` に変更があるかを見る (あればイメージの stamp がずれる →「導入と再導入の落とし穴」6) |
| V4.1 EXL3 の重みがそろっているか | 下のコードブロック 7 (本体 49 ファイルのサイズを revision 固定の HF API と比べる。`OFF=1` にすると期待値を 1 本だけ 1 バイトずらす陽性対照になり、exit 1 を返す)。2026-09-15 に両ノードで exit 0、`OFF=1` で exit 1 を確認。Engram の 2 本は「導入手順」の Engram のコードブロック末尾の `sha256sum -c` で照合し、`engram-src/` に `config.json` と `model.safetensors.index.json` があることも見る |
| V4.1 EXL3 系の上流既定からの差分 | 下のコードブロック 6 |
| HF 側の `main` が動いていないか | `curl -s https://huggingface.co/api/models/nvidia/Qwen3.8-Flash-Next-NVFP4 \| python3 -c 'import json,sys;print(json.load(sys.stdin)["sha"])'`。**`fab0aecb` 以外を返すならキャッシュより先に進んでいる** (2026-09-09 時点は `fc694b54`。意味は → 「重みの検証」) |
| Qwen 系の重みが完全か | `ssh -n spark-head 'cd ~/Qwen3.8-Flash-Next-Dual-DGX-Sparks && python3 files/resolve_snapshot.py ~/.cache/huggingface/hub/models--nvidia--Qwen3.8-Flash-Next-NVFP4; echo $?'` (0 で合格)。**陽性対照は存在しないディレクトリを渡して 2 が返ること。** head 1 ノードを manifest と突き合わせるなら「重みの検証」節の `verify-weights.py --revision`、両ノードなら同節の `--save-manifest` + `check-weights.sh --manifest` を使う (revision を省くと HF の `main` と比べて必ず 2 件不一致になる)。2026-09-09 実測 |
| 両ノードのイメージ | `ssh -n spark-head 'docker images --format "{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}"'` (worker は「worker に入る」節経由で同じもの) |
| worker 側の同じ確認 | 「worker に入る」節のコマンドの `<worker で実行するコマンド>` に上記を入れる |
| 稼働中のモデル名と上限 | `curl http://spark-head.local:8888/v1/models` |
| 8888 が無認証のままか | `curl -s -o /dev/null -w "%{http_code}\n" http://spark-head.local:8888/v1/models` (200 なら無認証。対照に `/v1/nope` が 404 を返すことも見る) |
| 各種メトリクス | 「遅いと感じたときに疑う順序」の `curl` 1 本 (完全一致の grep) |
| CPU のトポロジと governor | `ssh -n spark-head 'lscpu \| grep -E "Model name\|^CPU\(s\)"; for c in 0 5 10 15; do echo "cpu$c $(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_driver) $(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_governor) $(cat /sys/devices/system/cpu/cpu$c/cpufreq/cpuinfo_max_freq)"; done'` (worker は「worker に入る」節経由)。**cpu5 / cpu15 が 3900000、cpu0 / cpu10 が 2808000 なら「ハードウェアと OS」表のコア割り当てどおり。** unit が書き込む対象コアがこの割り当てに依存するので、別ロットで番号が入れ替わっていないかをここで見る。2026-09-10 実測 |
| クロック制限の unit が有効か | `ssh -n spark-head 'systemctl is-active nv-gpu-clock-limit.service nv-cpu-clock-limit.service'` (worker は head 経由。両方 `active` で合格)。**どちらも `Type=oneshot` + `RemainAfterExit=yes` なので `active` のまま残る** (この 2 行が無い素の oneshot は実行後に `inactive` になり、この判定は使えない)。**`is-active` は unit が走ったことしか言わないので、実効値は下の 2 行で別に見る** |
| GPU クロック制限が実際に効いているか | `ssh -n spark-head 'nvidia-smi --query-gpu=clocks.max.sm,clocks.applications.graphics --format=csv'` と、負荷中の `nvidia-smi --query-gpu=clocks.sm --format=csv,noheader`。**負荷中に 2200 MHz 前後を超えなければ効いている。** ロックは unit が `active` のままでも外部要因で解けうるので、`is-active` を実効性の証跡にしない |
| X925 の `scaling_max_freq` が下げてあるか | `ssh -n spark-head 'for c in 5 19; do echo "$(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_max_freq) $(cat /sys/devices/system/cpu/cpu$c/cpufreq/cpuinfo_max_freq) $(cat /sys/devices/system/cpu/cpu$c/cpufreq/max_perf)"; done'` (worker は「worker に入る」節経由)。単位はすべて kHz。**`2808000 3900000 3900000`(cpu5) / `2808000 3900000 4004000`(cpu19) が現状で、意味は「policy は下げたがハードウェアには届いていない」。** 3 列目 (`max_perf`) が 2808000 になって初めて本当のクロック制限である。1 列目と 2 列目が同値なら unit が当たっていない。sudo は要らない。2026-09-10 実測 |
| X925 の実効クロック (**`scaling_cur_freq` は見ない**) | **`scaling_cur_freq` は `cppc_cpufreq` では要求値のエコーで、負荷と無関係に `scaling_max_freq` と同じ値を返すため検査に使えない** (これで「上限以下」を確認しても、原理的に不合格になりえない)。実効値は `cpuinfo_avg_freq` (直近区間の delivered performance) を **busy なコアに限って**読む。手順は下のコードブロック 5。**陰性対照は busy な A725 で、要求値 2808000 と実効値がほぼ一致する。** X925 が同時に 3.8〜3.9 GHz を返せば、エコーではなく実効値を見られている。**idle のコアに打つと値が動かないか `Resource temporarily unavailable` を返すので、busy 判定と必ず組で使う。** 2026-09-10 実測 |
| 推論中に CPU を使っているのが誰か (「既知の制約」5 の因果の根拠) | 4 値をそれぞれ別の手段で採る。**(a) decode 1 ステップの時間** = 推論 1 本の前後で `curl -s http://spark-head.local:8888/metrics \| grep '^vllm:iteration_tokens_total_count'` の増分でその間の所要秒を割る。**(b) 同区間の GPU 使用率** = 負荷中に `ssh -n spark-head 'nvidia-smi --query-gpu=utilization.gpu,clocks.sm,power.draw --format=csv'`。**(c) スレッドごとの CPU 時間** = 負荷の前後で `/proc/<tid>/stat` の 14・15 列 (user / sys、単位は 10 ms) の増分を取る。**(d) 自発的にブロックした回数** = 同じ区間で `/proc/<tid>/status` の `voluntary_ctxt_switches` の増分を (a) のステップ数で割る。**tid は `ps -eLo tid,pcpu,comm` で `VLLM` を含むものを拾う** (`docker exec` は要らない。コンテナのスレッドもホストの `/proc` に見える)。2026-09-10 に (a) 63 ms / (b) 93% / (c) 3 本が 91〜99% / (d) 2〜5 回を実測。**スタックまでは追っていないので、スピンの出所が CUDA の同期待ちか NCCL かは未確認である** (コンテナに `py-spy` が無く、`perf` / `strace` は sudo が要る) |
| CPU / SoC の温度 | `ssh -n spark-head 'for z in 0 1 2 3 4 5 6; do awk "{printf \"zone%s=%.1f \", $z, \$1/1000}" /sys/class/thermal/thermal_zone$z/temp; done; echo'` (worker は「worker に入る」節経由)。**zone の名前と読み方は「既知の制約」6。** 単位は °C。**履歴は残らないので、比較したいときは負荷の前後で自分で採る** |
| 再起動後の復帰条件 | `ssh -n spark-head 'docker inspect <コンテナ名> --format "{{.HostConfig.RestartPolicy.Name}}"'` (DeepSeek 系は `deepseek-v4-flash-vllm-dspark-1`、Qwen 系は `vllm-fn`、V4.1 EXL3 系は `dsv41-exl3-head`。worker 側は `dsv41-exl3-worker`) |
| `/v1/responses` が `input_text` を受けるか (`cxsp` の前提) | 下のコードブロック 8。**200 で合格。** パッチ前は 400 を返すことを 2026-09-17 に実測してあり、それがこの検査の陰性対照である |
| head のパッチが走ったか | `ssh -n spark-head 'docker logs dsv41-exl3-head 2>&1 \| grep "dsv41-responses-parts" \| tail -1'`。`patched:` か `already patched:` なら適用済み、`FATAL` なら当たっていない (→「既知の制約」12)。**レシピの `logs/` には出ない** — パッチはコンテナ内で走るので docker のログに入る。2026-09-17 実測 |
| `start.sh` のローカル差分が残っているか | `ssh -n spark-head 'cd ~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks && git diff --stat start.sh'` (2 insertions が出れば残っている。空なら `git pull` で消えている)。2026-09-17 実測 |
| codex の設定が読めるか | Mac 側で `codex doctor --no-color --summary <cxsp が組み立てる -c の一式>` の Configuration 行が `config loaded`。**陽性対照は `model_providers.spark.name=""` を混ぜること** (`could not be loaded` になる)。2026-09-17 実測 |
| Tailscale の参加状況 | Mac 側で `tailscale status` |
| OpenCode の設定 | Mac 側で `python3 -c "import json;print(list(json.load(open('$HOME/.config/opencode/opencode.json'))['provider']))"` |
| `ocsp` の接続先上書きが効くか | Mac 側で `OPENCODE_CONFIG_CONTENT='{"provider":{"spark":{"options":{"baseURL":"http://example.invalid:9/v1"}}}}' opencode debug config`。**`provider.spark.options.baseURL` がその値になり、`opencode.json` に宣言した全モデルと `npm` が残っていれば合格** (ディープマージの確認)。**陰性対照として環境変数を外した同じコマンドを打ち、`spark-head.local` が返ることも見る** (2026-09-07 に opencode 1.18.18 で実測) |
| 上書きが `options` の兄弟キーを消さないか | 認証を戻す前に確かめる。`opencode.json` を写した検証用の `HOME` を作って `provider.spark.options.apiKey` に目印の文字列を入れ、`HOME=<検証用> OPENCODE_CONFIG_CONTENT='…baseURL のみ…' opencode debug config` を打つ。**`baseURL` が差し替わったうえで `apiKey` の目印が残っていれば合格** (2026-09-07 に実測。マージは `options` の中まで再帰する) |
| OpenCode の設定が live edit か | Mac 側で `readlink -f ~/.config/opencode/opencode.json`。**dotfiles 配下を返せば live、`/nix/store/…` で終われば store コピー。** **`-f` を落とすと判定が壊れる**: `mkOutOfStoreSymlink` は `~/.config/…` → `…-home-manager-files/…` → dotfiles の 2 段になるので、単 hop の `readlink` は live でも `/nix/store/…` を返し、常に「`drs` 待ち」と誤判定する (2026-09-06 に実測。この行は live) |
| zsh 関数が配布済みか | Mac 側で `diff -q "$(readlink -f ~/.config/zsh/functions/claude-deepseek.zsh)" zsh/functions/claude-deepseek.zsh` (dotfiles で実行)。**こちらは store の実コピーなので `readlink -f` も常に `/nix/store/…` を返す。** パスではなく内容を比べる。差があれば `drs` 待ち |
| 3 つのクライアントの疎通 | Mac 側で `ccsp status` / `ocsp status` / `cxsp status`。**`drs` を当てて新しいシェルを開くまで関数は `command not found` になる** (配布済みかは上の `diff -q` の行で判る)。**Claude の Bash ツールのシェルスナップショットには `_spark_*` ヘルパーが入らないため、そこから打つと `command not found` と「に届かない」の誤判定になる (2026-09-09 実測)。切り分けは `curl -fs -o /dev/null http://spark-head.local:8888/health` で行う** |
| 配信中のモデルが受ける reasoning effort と既定値 | **経路ごとに 2 本打つ** (語彙が違う → 「Qwen の reasoning effort の語彙」)。`ocsp` 側は `curl -s http://spark-head.local:8888/v1/chat/completions -H 'Content-Type: application/json' -d '{"model":"<配信名>","messages":[{"role":"user","content":"x"}],"reasoning_effort":"high","max_tokens":1}'`、`ccsp` 側は `curl -s http://spark-head.local:8888/v1/messages -H 'Content-Type: application/json' -H 'anthropic-version: 2023-06-01' -d '{"model":"<配信名>","messages":[{"role":"user","content":"x"}],"max_tokens":1,"output_config":{"effort":"high"}}'`。**語彙外の値を投げて 400 のエラー本文を読むのが陽性対照** (対応値を列挙する)。**陰性対照として受理される値でも打ち、200 が返ることを確かめる** (常に 400 を返す壊れた検出でないことの確認)。値は系統で変える。Qwen 系は陽性対照 `high` / 陰性対照 `xhigh`、V4.1 EXL3 系は陽性対照 `medium` / 陰性対照 `max` (`high` は受理されるので陽性対照にならない)。**Qwen 系 (2026-09-06) と V4.1 EXL3 系 (2026-09-15) は全値で実測済み。DeepSeek 系は未確認** |
| 3 つのクライアントが実際に送る effort | **設定値**は Mac 側で `python3 -c "import json;print({k:v.get('options') for k,v in json.load(open('$HOME/.config/opencode/opencode.json'))['provider']['spark']['models'].items()})"` (`ocsp` が読むのはこの実体。dotfiles 側を読むと、まだ `drs` を当てていない世代では送っていない値を報告してしまう。どちらを指しているかは上の `readlink` の行で判る) と、`ccsp` / `cxsp` の起動時の 1 行 (`cxsp` は `cxsp: Spark モード (… / effort <値>)`)。**送信値そのものを見るには記録プロキシを挟む** (下のコードブロック 4。`cxsp` を通すときは `CCSP_LAN_HOST=127.0.0.1 cxsp lan exec --skip-git-repo-check "1+1 は?"` と打ち、プロキシが写し取るキーに `reasoning` を足す — `/v1/responses` は effort を `reasoning.effort` に載せる)。**`ccsp` 側は `drs` と新しいシェルを経ないと新実装が動かない**ので、`grep -c _spark_effort ~/.config/zsh/functions/claude-deepseek.zsh` が 0 を返す間は effort を送らない |
| DeepSeek 系の上流既定からの差分 | 下のコードブロック 1 (**キー行と RoCE 側の IP を持つ 4 行が出るので画面外に出さない**) |
| Qwen 系の上流既定からの差分 | 下のコードブロック 2 |
| 常時展開される rules | 下のコードブロック 3 |
| L1 の再計測 | 「L1」節の `bench.py` 2 本をそのまま打つ。**前提が 2 つある**: DeepSeek 系 (Vision-Exp) を配信中であることと、`/tmp/spark.key` を書き直してあること (無認証でも中身は何でもよいが、ファイルが無いと `bench.py` が exit する) |

表に入らないもの (1〜3 と 5〜7 はパイプを含むため、4 はヒアドキュメントを含むため、8 は複数行にわたるため)。

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

# 5. 推論中に busy なコアと、そのコアの実効クロック (ノード上で実行)
# 「既知の制約」5 の 2 つの主張 (載り先が A725 へ移った / X925 は走れば 3.9 GHz)
# を両方この 1 本で確かめる。推論を流している間に打つ。
pc(){ awk '/^cpu[0-9]/ {print $1, $2+$3+$4+$6+$7+$8, $5}' /proc/stat; }
pc > /tmp/c1; sleep 5; pc > /tmp/c2
paste /tmp/c1 /tmp/c2 | awk '{b=$5-$2; i=$6-$3; t=b+i; p=(t>0?100*b/t:0); if (p>50) print substr($1,4)+0, int(p)}' |
while read c p; do
  cls=A725; case $c in 5|6|7|8|9|15|16|17|18|19) cls=X925;; esac
  printf "cpu%s(%s) busy=%s%% avg=%s scal=%s\n" "$c" "$cls" "$p" \
    "$(cat /sys/devices/system/cpu/cpu$c/cpufreq/cpuinfo_avg_freq 2>&1)" \
    "$(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq)"
done
# 読み方: A725 は avg ≈ scal (2805257 前後)。X925 が出てきたら avg は 3.88 GHz 前後で
# scal は 2808000 のまま = scal がエコーである証拠。X925 が出るのは 8 回に 1 回程度
# なので、出なくても異常ではない (何度か打つ)。1 行も出なければ負荷が掛かっていない
# ので、先に推論が走っていることを確かめる (陰性対照: 無負荷では 0 行になる)。
```

```bash
# 6. V4.1 EXL3 レシピの .env と配布既定の差分 (キー名だけを出す。値に IP を含む行があるので値は出さない)
# 行頭の < は配布既定、> は当方の値。2026-09-15 時点は HF_HUB_ENABLE_HF_TRANSFER (> だけ) と WEIGHT_SYNC / WORKER_CX7_IB / WORKER_CX7_IF / WORKER_USER (< と > の両方) の 5 キーが出る
ssh -n spark-head 'cd ~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks && diff <(grep -E "^[A-Za-z0-9_]+=" .env.example | sort) <(grep -E "^[A-Za-z0-9_]+=" .env | sort) | grep -E "^[<>]" | sed -E "s/=.*//" | sort -u'

# 7. V4.1 EXL3 の本体の重みが revision 固定の HF API とサイズで一致するか (head で実行。worker は DIR を ~/.cache/dsv41-flash-exl3/model に)
#    exit 0 = 全一致 / 1 = 不一致。OFF=1 は期待値を 1 本だけ 1 バイトずらす陽性対照で、必ず exit 1 になる
cd ~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks
curl -s "https://huggingface.co/api/models/Mia-AiLab/DeepSeek-V4.1-Flash-EXL3-2.9bpw/revision/64ba41b6c916a587db06eae2e19b7845f7be6e6b?blobs=true" \
| OFF=0 DIR=model python3 -c 'import json,os,sys
m={s["rfilename"]:s["size"] for s in json.load(sys.stdin)["siblings"]}
m[sorted(m)[0]]+=int(os.environ["OFF"])
bad=[n for n,z in m.items() if not os.path.isfile(os.path.join(os.environ["DIR"],n)) or os.path.getsize(os.path.join(os.environ["DIR"],n))!=z]
print(len(m),"files, mismatch:",bad[:3]); sys.exit(1 if bad else 0)'
```

```bash
# 8. /v1/responses が Responses API の content パーツ (input_text) を受けるか。
#    200 なら head のパッチが効いている。400 なら当たっていない (→「既知の制約」12)。
curl -s -o /dev/null -w '%{http_code}\n' -m 60 http://spark-head.local:8888/v1/responses \
  -H 'Content-Type: application/json' \
  -d '{"model":"DeepSeek-v4.1-Flash-EXL3","store":false,"stream":false,"max_output_tokens":24,
       "input":[{"type":"message","role":"user","content":[{"type":"input_text","text":"say OK"}]}]}'
```

**コードブロック 4. クライアントが実際に送る本文を見る (記録プロキシ)。** effort のように「設定に書いた値が本当に飛んでいるか」は、サーバのログにもクライアントの出力にも出ない。両者の間に中継を挟んで本文を写し取る。下は Mac のローカルに立てて上流へそのまま流す最小の実装である (上の 1〜3 と 5 と違いヒアドキュメントを含むので、1 つのフェンスに収まらない)。

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

**陽性対照を必ず取る** (不変則 4)。異常な値を入れたときに記録が反応することの確認で、これが取れて初めて、既定で記録された値 (Qwen 配信中なら `xhigh`、V4.1 EXL3 配信中なら `max`) が本当に送信経路を通っていると言える。**下の `CCSP_EFFORT=high` は Qwen 配信中の語彙外の値である。V4.1 EXL3 配信中は `high` が 200 になるので `medium` に差し替える** (400 本文も `DeepSeek V4.1 reasoning_effort must be …` になる)。**`CCSP_LAN_HOST` を落とさない** — 落とすと本物のサーバへ直行し、400 は端末に出てもログには 1 行も残らないので、この対照は成立しない。

```bash
CCSP_LAN_HOST=127.0.0.1 CCSP_EFFORT=high ccsp lan -p "1+1?"
# ログ上で 2 行が隣接することを確認する:
#   {"path": "/v1/messages…", … "output_config": {"effort": "high"}}
#   {"resp": 400, … "Unexpected reasoning effort high…"}
grep -E 'output_config|resp' /tmp/ccsp.log | tail -2
```

**この手順は 1 回の Bash 呼び出しで流し切る** (または `{{@background-run}}`)。Claude のハーネスは呼び出しごとにシェルが変わるので、`&` で起動したプロキシが次の呼び出しまで残る保証が無い。

**使い終わったらプロキシを止める** (`pkill -f spark-proxy.py`)。**素の `ccsp` / `ocsp` / `cxsp` は止め忘れても本物に届く** (プロキシは `127.0.0.1` にしか bind せず、既定の宛先は `spark-head.local`)。実害は 2 つで、`CCSP_EFFORT` / `CCSP_LAN_HOST` を export したシェルだけが中継を向き続けることと、野良プロセスとログが残り続けることである。**`ccsp off` はこの 2 つの変数を消さない**ので手で `unset` する。停止後は `curl -s http://spark-head.local:8888/v1/models` が配信名を返すことまで確かめる。
