---
# 常駐読み込みさせないためのマーカー (このパスにマッチするファイルは存在しない)。
# 本ファイルは必要になったときに Read で参照する。
paths:
  - "__read-on-demand-only__"
---

# DGX Spark 2 台構成 (自宅のローカル LLM クラスタ)

- 種別: 環境リファレンス
- 対象読者: 別セッション・別マシンで作業するエージェント (Claude Code / Codex / OpenCode)
- 最終確認: 2026-10-04 (GLM 系の節と GLM に関わる記述、監査で指摘を受けた各節の記述)。OpenCode (V2 2.0.22) の節と OpenCode に関わる記述は 2026-10-03
- 他の節の確認日: 値ごとに表のセルか本文に書いてある (確認コマンドと組にした一覧は「依拠する外部事実」)。**OpenCode を通した疎通・速度の値のうち 2026-10-03 より前の日付のものは opencode 1.18.18 (V1) で取ったもので、V2 では測り直していない** (各箇所に版を書いてある)

自宅に NVIDIA DGX Spark (GB10) が 2 台あり、TP=2 (tensor parallel、2 台に重みを分割する並列方式) でローカル LLM を常時サービングしている。推論エンジンは GLM 系だけが TensorFold で、他の 3 系統は vLLM である。Mac の OpenCode (素の `opencode`) からバックエンドとして使える。

**レシピは 4 系統ある。** DeepSeek 系 (Vision-Exp または 0731。同じスクリプトとコンテナ名で、チェックポイントごとに別の作業ディレクトリから起動する)、Qwen 系 (Qwen3.8-Flash-Next)、V4.1 EXL3 系 (DeepSeek-V4.1-Flash EXL3 2.9bpw)、GLM 系 (GLM-5.3-Flash EXL3 4bpw、TensorFold で配信) で、ポート 8888 と GPU を共有するため**同時には 1 つしか配信できない**。**どれを配信しているかは本書に書かない** (切り替えが頻繁なので、書いた時点で古くなる)。系統ごとにスクリプト名・コンテナ名・設定ファイル名が違うので、作業前にどれが動いているかを確かめる (`ssh -n spark-head 'docker ps --format "{{.Names}}" | grep -E "vllm|dsv41|glm53"'`。**`--filter name=vllm` だけでは V4.1 EXL3 系の `dsv41-exl3-head` も GLM 系の `glm53-flash-tf` も拾わない**)。

**dotfiles リポジトリの所在は `~/dev/github.com/skanehira/dotfiles` である。** 本書でリポジトリ相対で書くパスはすべてここを基点とする。**本書の表で「—」は該当なしを意味する。**

## 用語・成果物一覧

「定義箇所」の列は、その名前の値や中身が書いてある場所を指す。本書の節名か、実機・dotfiles 上のファイルパスのどちらかである。

| 名前 | 意味 | 定義箇所 | 生成者 | 消費者 |
| --- | --- | --- | --- | --- |
| DeepSeek 系 / Qwen 系 / V4.1 EXL3 系 / GLM 系 | レシピの系統。スクリプト名・コンテナ名・設定ファイルが異なり、同時には配信できない | 冒頭の「レシピは 4 系統ある」 | — | 人 |
| head / worker | TP=2 の rank 0 / rank 1。head だけが HTTP API を持ち、worker は headless | `.env.dspark` の `WORKER_HOST` | 人 (初期構築) | 起動スクリプト |
| レシピ | 上流が配布する compose + シェルスクリプト一式 | head の `~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark/` | 上流 (`git clone`) | 人 |
| Vision-Exp | `deepseek-ai/DeepSeek-V4-Flash-Vision-Exp` の略。画像入力が使える。DeepSeek 系のモデル | 「サービングの構成 (DeepSeek 系)」 | 上流のチェックポイント | vLLM |
| Qwen3.8-Flash-Next | `nvidia/Qwen3.8-Flash-Next-NVFP4` の略。他の 3 系統とは別レシピで配信する | 「Qwen3.8-Flash-Next」 | 上流のチェックポイント | vLLM |
| 0731 | `deepseek-ai/DeepSeek-V4-Flash-0731` の略。DeepSeek 系のテキスト専用チェックポイント (画像入力は使えない)。Vision-Exp よりドラフタの受理率が高く、decode が速い | 「0731 版で配信する」 | 上流のチェックポイント | vLLM |
| `~/dspark-0731` | 0731 版を起動する作業ディレクトリ。DeepSeek 系レシピの git worktree で、`70a7cc4` に detached で固定してある。0731 用の `.env.dspark` を持つ | 「0731 版で配信する」 | 人 (`git worktree add`) | 人 / 起動スクリプト (worker 側の配布先も `~/dspark-0731` になる) |
| RoCE | RDMA over Converged Ethernet。QSFP ポート上でノード間の NCCL 集団通信を運ぶ | `.env.dspark` の `NCCL_IB_HCA` | NetworkManager の接続 `roce` / `roce2` | vLLM (NCCL) |
| NCCL | NVIDIA Collective Communications Library。TP=2 のランク間通信を担う | 本表 | — | vLLM |
| DSpark | チェックポイント内蔵の投機デコード。draft 用の別モデルを持たない。DeepSeek 系と V4.1 EXL3 系が使う | vLLM の CLI フラグ `--speculative-config` | DeepSeek 系はレシピの compose、V4.1 EXL3 系はレシピの `.env` の `SPEC_METHOD` / `DSPARK_TOKENS` から `start.sh` | vLLM |
| MTP | multi-token prediction。1 ステップで出す draft トークン数。**キー名が系統で違う** (DeepSeek 系 = `.env.dspark` の `MTP_NUM_TOKENS` / Qwen 系 = Qwen レシピの `.env` の `MTP_NUM_SPECULATIVE_TOKENS` / V4.1 EXL3 系は DSpark の行の `DSPARK_TOKENS`) | 各系統の設定ファイル | 人 | vLLM |
| `nvfp4_ds_mla` / `fp8_ds_mla` | MLA (multi-head latent attention) の KV キャッシュを 4bit / 8bit で保持する形式。前者は DeepSeek 系、後者は V4.1 EXL3 系 | vLLM の CLI フラグ `--kv-cache-dtype` | DeepSeek 系はレシピの compose が指定、V4.1 EXL3 系は vLLM が自分で選ぶ | vLLM |
| TTFT | time to first token。送信から最初のトークンが返るまでの時間。ほぼ prefill の所要時間 | 本表 | `~/spark-bench/bench.py` | 「L1: サーバ単体 (2026-09-05)」の表 |
| 受理率 | 投機デコードが出した draft トークンのうち採用された割合。decode 速度をほぼ決める | 本表 | vLLM の `/metrics` (vLLM の 3 系統)。GLM 系 (TensorFold) は `/health` の `accepted_total` / `drafted_total` (→「遅いと感じたときに疑う順序」) | 「L3: OpenCode 込み (2026-09-05)」の表・「遅いと感じたときに疑う順序」4 |
| L1 / L3 | 計測の層。L1 = サーバを直叩き (クライアント無し) / L3 = OpenCode 経由 (opencode 1.18.18 で計測) | 本表 | `bench.py` (L1) / `snap.py` (L3) | 「実測値」節 |
| `ccds` | Claude Code を DeepSeek 本家 API へ向けて起動する zsh 関数。`settings.deepseek.json` を `--settings` で渡す。予約語は第 1 引数の `off` だけで、それ以外はそのまま `claude` に渡す。`ccds off` は `ANTHROPIC_AUTH_TOKEN` / `ANTHROPIC_BASE_URL` と `claude` の alias を解除する | `zsh/functions/claude-deepseek.zsh` | dotfiles | 人 |
| `opencode` | OpenCode V2 (2.0.22) の本体。ラッパーを挟まず素の `opencode` を打つと本クラスタに繋がる。nixpkgs の `opencode` は V1 なので、npm 配布のビルド済みバイナリを展開する自前 derivation で入れる (フルセットと Android の両プロファイル) | `nix/pkgs/opencode.nix` | dotfiles (`packages.nix` / `packages-android.nix`) | 人 |
| `spark-served.ts` | OpenCode のローカルプラグイン。起動時と 30 秒ごとに `/v1/models` を引き、`opencode.json` に宣言したモデルのうち配信中のものだけを有効にして既定モデルに据える (→「OpenCode」) | `agents/bindings/opencode/plugins/spark-served.ts` | dotfiles (`nix/modules/home/opencode.nix` が `~/.config/opencode/plugins/` へ symlink) | `opencode` 本体 (同ディレクトリ直下の `*.ts` を自動で読む) |
| 常駐サービス | 素の `opencode` が起動して接続する常駐の `opencode serve --service`。TUI を閉じても残る。待ち受けは全インターフェースの 49374 番で、保護はパスワードだけ | 「OpenCode」 | `opencode` (最初の起動時) | `opencode` の TUI / `opencode run` |
| `settings.deepseek.json` | `ccds` が `--settings` で渡す DeepSeek 本家 API の静的な設定。接続先 (`env.ANTHROPIC_BASE_URL`)・モデル名 5 キー・`CLAUDE_CODE_EFFORT_LEVEL` (`max`)・`fallbackModel` を持つ | `agents/bindings/claude/settings.deepseek.json` | dotfiles | `ccds` |
| `CLAUDE_CODE_EFFORT_LEVEL` | DeepSeek 本家 API 向けの Claude Code の推論の深さ。`settings.deepseek.json` が静的な `max` を持つ | `agents/bindings/claude/settings.deepseek.json` | `ccds` が `--settings` で渡す | `claude` 本体 |
| `reasoningEffort` | OpenCode の推論の深さ。`opencode.json` の `provider.spark.models.<配信名>.options` が**モデルごとに静的に持つ** (`qwen3.8-flash-next` = `xhigh` / `deepseek-v4-flash-vision-exp` = `high` / `deepseek-v4-flash-0731` = `high` / `DeepSeek-v4.1-Flash-EXL3` = `max` / `GLM-5.3-Flash-EXL3` = `max`)。省略するとクライアントは送らず、モデルのテンプレート既定が効く | `agents/bindings/opencode/opencode.json` | dotfiles | `opencode` 本体 (`/v1/chat/completions` の `reasoning_effort` として送る) |
| `opencode.json` | OpenCode の `provider.spark` (接続先 `http://spark-head:8888/v1`・配信しうるモデルの宣言・モデルごとの `reasoningEffort` と `limit`) と、`spark` 以外の provider を選択肢に出さない `enabled_providers`。**キーは持たない。** 認証を戻すときだけ `options.apiKey` を足す (→「API キーの流れ」)。**接続先の URL は `spark-served.ts` の `BASE_URL` にもあり、2 か所で一致させる** (→「OpenCode」)。トップレベルの `permission` は OpenCode のツール実行の承認方針で、`allow` は全ツール自動承認を意味する。トップレベルの `default_agent: "plan"` は起動直後のエージェントを組み込みの `plan` にする (→「OpenCode」)。dotfiles 管理。トップレベルの `autoupdate: false` は本体の自動更新を止める (→「OpenCode」)。`~/.config/opencode/` の他のファイルは opencode 自身と他ツールのもの (`node_modules` / `package.json` / `package-lock.json` / `.gitignore` は V1 用のプラグイン SDK で、更新されていない。`spark-served.ts` はこれを import しない。V2 本体が読むかは確かめていない)。**`AGENTS.md`・`plugins/spark-served.ts`・`cli.json` は dotfiles への symlink、`agents/` は `sync-subagents.ts` の生成物**で、いずれも `nix/modules/home/opencode.nix` が配る | `agents/bindings/opencode/opencode.json` | dotfiles (`nix/modules/home/opencode.nix` が symlink) | `opencode` 本体 |
| `cli.json` | OpenCode の TUI 設定 (keybinds / theme)。`~/.config/opencode/cli.json` へ symlink で配る。TUI で設定を変えると symlink が実ファイルに化ける (→「OpenCode」) | `agents/bindings/opencode/cli.json` | dotfiles (`nix/modules/home/opencode.nix`) | `opencode` 本体 |
| `patch_responses_content_types.py` / `patch_responses_content_parts.py` | V4.1 EXL3 系の `/v1/responses` が送る `input_text` パーツを tokenizer に受けさせる。前者は上流公式、後者は `b9c49e9` 用のローカル backport。どちらか 1 つを使う (→「既知の制約」12) | 公式はレシピの `overlay/`、ローカルは head の `~/dsv41-local/` | 上流 (`git clone` / 更新) / 人 (ローカル版の全文は制約 12) | `start.sh` のパッチループ経由でコンテナ |
| `/tmp/spark.key` | vLLM の Bearer トークンを平文で置いた作業ファイル。**head にだけ要る。`bench.py` 専用で、無認証の現在は中身が使われない。再起動で消える** | head の `/tmp/spark.key` | 人 (無認証のいまは任意の文字列を書く。認証を戻した後は 1Password から書き出す →「API キーの流れ」) | `bench.py` |
| `nv-gpu-clock-limit.service` / `nv-cpu-clock-limit.service` | 両ノードに手で置いた systemd unit 2 本。前者は GPU の SM クロックを 2,200 MHz にロックし、後者は X925 の `scaling_max_freq` を下げる (**後者はハードウェアのクロック上限を変えていない** → 「既知の制約」5)。dotfiles に控えが無い | 「既知の制約」4・5 (後者は unit 全文も) | 人 | systemd |
| `drs` / `hms` | dotfiles の Nix 設定を適用する zsh alias。`drs` が Mac 用、`hms` が Linux 用 (Home Manager standalone) | `nix/modules/home/zsh.nix` | dotfiles | 人 |
| `.env.dspark` | DeepSeek 系レシピの設定を集約した 1 枚。git 管理外 (`.gitignore` 済み) | head の `~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark/` | 人 (`.env.dspark.example` から複製) | 起動・停止・検証スクリプト |
| Qwen レシピ | Qwen3.8-Flash-Next を TP=2 で配信する別系統のレシピ。他の 3 系統とは別リポジトリ・別イメージ・別スクリプト名 | head の `~/Qwen3.8-Flash-Next-Dual-DGX-Sparks/` | 上流 (`git clone`) | 人 |
| `stop` / `start` | 本書で使う DeepSeek 系スクリプト (`stop-deepseek-v4-flash-dspark.sh` / `start-deepseek-v4-flash-dspark.sh`) の略記。**Qwen 系・V4.1 EXL3 系・GLM 系の `stop.sh` / `start.sh` とは別物。** Vision-Exp 版と 0731 版は同じ名前のスクリプトを別の作業ディレクトリで打つ | 「DeepSeek 系 (Vision-Exp / 0731)」 | 上流 | 人 |
| `start.sh` / `stop.sh` | **Qwen・V4.1 EXL3・GLM の 3 レシピが同名で別々に持つ**スクリプト。Qwen 版は `--launch` で取得を飛ばして起動し、停止は `stop.sh`。V4.1 EXL3 版は引数なしで起動し、`stop` / `pack` / `status` / `logs` をサブコマンドで持つ (`stop.sh` は `start.sh stop` を呼ぶだけ)。GLM 版は引数なしで起動し、`restart` だけをサブコマンドで持つ。停止は `stop.sh` で、状態表示とログのサブコマンドは無い。本書では所属するレシピの節の中でだけ素の名前で書く | 「系統の切り替え」の表 | 上流 | 人 |
| `.env` | **Qwen レシピと V4.1 EXL3 レシピが同名で別々に持つ**設定 1 枚。DeepSeek 系の `.env.dspark` とは別物。本書では「Qwen レシピの `.env`」「V4.1 EXL3 レシピの `.env`」と書き分ける | head の `~/Qwen3.8-Flash-Next-Dual-DGX-Sparks/.env` / `~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks/.env` | 人 (前者は `.env.sample`、後者は `.env.example` から複製) | 各レシピのスクリプト |
| `vllm-fn` | Qwen レシピのコンテナ名。**head と worker で同名** | Qwen レシピの `start.sh` | `start.sh` | `docker` |
| DeepSeek-V4.1-Flash EXL3 | `deepseek-ai/DeepSeek-V4.1-Flash` を EXL3 2.9 bpw に量子化した `Mia-AiLab/DeepSeek-V4.1-Flash-EXL3-2.9bpw` の略。配信名は `DeepSeek-v4.1-Flash-EXL3`。画像入力が使える (量子化せずに残した vision tower をチェックポイントが持つ) | 「DeepSeek-V4.1-Flash EXL3」 | 上流のチェックポイント | vLLM |
| EXL3 | 推論ライブラリ ExLlamaV3 の量子化形式 (Cornell RelaxML の QTIP を簡略化した変種)。テンソルごとにビット数を変えられるので平均が 2.9 bpw のような端数になる。vLLM 本家は非対応で、V4.1 EXL3 レシピはイメージに後付けしている。GLM レシピは TensorFold の EXL3 対応を使う | 「DeepSeek-V4.1-Flash EXL3」の表 | 上流 | vLLM (V4.1 EXL3 レシピの overlay) / TensorFold |
| GLM-5.3-Flash EXL3 | `GLM-5.3-Flash` を EXL3 4 bpw に量子化した `Mia-AiLab/GLM-5.3-Flash-EXL3-4bpw-TensorFold` の略 (ライセンスは MIT)。配信名は `GLM-5.3-Flash-EXL3`。画像入力が使える | 「GLM-5.3-Flash EXL3」 | 上流のチェックポイント | TensorFold |
| GLM レシピ | GLM-5.3-Flash の EXL3 4bpw 量子化版を TensorFold の TP=2 で配信する別系統のレシピ。起動は `start.sh`、停止は `stop.sh` で行う | head の `~/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold/` | 上流 (`git clone`) | 人 |
| TensorFold | GLM 系だけが使う推論エンジン ([ashhart/TensorFold](https://github.com/ashhart/TensorFold))。GLM レシピは v0.6.0 に 70 本のパッチを当てたものをイメージに焼き込んで配る。OpenAI 互換の API を持つが、vLLM とは別実装で、`/v1/messages` と `vllm:` のメトリクスを持たない | 「GLM-5.3-Flash EXL3」 | 上流 | GLM レシピの `start.sh` |
| TR3 | `Mia-AiLab/GLM-5.3-Flash-EXL3-TR3-4bpw` の略。GLM レシピ v1.2 が使っていたチェックポイントで、HF から消えている。v1.2 へ戻す用に両ノードの HF キャッシュに残してある | 「GLM-5.3-Flash EXL3」の表の「戻す用に残している重み」 | 上流のチェックポイント (取り直せない) | GLM レシピ v1.2 (`1f3d909`) |
| `prepare.sh` | GLM レシピの準備スクリプト (`scripts/prepare.sh`)。イメージの取得・重みの取得・worker への配布を行い、終わると準備済みの状態を `~/.local/state/glm53-tensorfold/prepared` に書く。start.sh がこの状態と現在の構成を比べ、違えば自動で流す (`PREPARE=0` で飛ばす) | 「起動と判定 (GLM 系)」 | 上流 | GLM レシピの `start.sh` |
| `scripts/local.sh` | GLM レシピの手元設定 1 枚。`WORKER` (worker の ssh 先) だけを書く。**`.gitignore` に入っておらず、`git status` に未追跡として出る** | head の `~/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold/scripts/local.sh` | 人 (`scripts/local.sh.example` から作る) | GLM レシピの `scripts/config.sh` |
| `glm53-flash-tf` | GLM レシピのコンテナ名。**head と worker で同名** | GLM レシピの `scripts/config.sh` の `CONTAINER_NAME` | `start.sh` | `docker` |
| DFlash2 | GLM レシピの投機デコードが使う**別モデルのドラフタ** (`incoai/GLM-5.3-Flash-DFlash2`、2.2 GiB)。チェックポイント内蔵の DSpark / MTP と違い、重みを別に取って配る必要がある | GLM レシピの `scripts/config.sh` の `DRAFTER` / `DFLASH2_ID` / `DFLASH2_REVISION` | 上流のチェックポイント | TensorFold |
| stamp (`dsv41.recipe.stamp`) | V4.1 EXL3 レシピの入力ファイル群のハッシュ。イメージのラベル `dsv41.recipe.stamp` と比べて、ずれていれば起動時にビルドが走る。GLM レシピは代わりにパッチのハッシュをラベル `tf.patches` に持つ | V4.1 EXL3 レシピの `start.sh` の `overlay_recipe_hash` | `start.sh` | `start.sh` の起動前判定 |
| `~/.cache/glm53-tf-image` | GLM レシピ v1.2 のイメージ `tensorfold-glm53:v0.5.0` を手で取ったときの blob 置き場 (11 GiB)。現行の導入手順では作らない。v0.5.0 は両ノードに読み込み済みなので消してよい (→「残骸の片付け」) | 両ノードの `~/.cache/glm53-tf-image/` | 人 (v1.2 の導入時) | なし (v0.5.0 を読み込み直すときだけ) |
| V4.1 EXL3 レシピ | DeepSeek-V4.1-Flash の EXL3 2.9bpw 量子化版を TP=2 で配信する別系統のレシピ。起動・停止・pack は `start.sh` のサブコマンドで行う | head の `~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks/` | 上流 (`git clone`) | 人 |
| `dsv41-exl3-head` / `dsv41-exl3-worker` | V4.1 EXL3 レシピのコンテナ名。**head と worker で名前が違う** | V4.1 EXL3 レシピの `start.sh` | `start.sh` | `docker` |
| Engram | DeepSeek-V4.1 の n-gram 埋め込み表 (layer 1 と 14)。**量子化されておらず、元チェックポイントの shard 47/48 から取る**。メモリには載せず、ファイルから行を読む | 「DeepSeek-V4.1-Flash EXL3」 | 上流のチェックポイント | vLLM (file-backed lookup) |
| slim dir | Engram の読み込みに要るファイル (shard 47 / 48 のハードリンク、Engram のキーだけに絞った index、`config.json` のコピー) だけを集めたディレクトリ。起動と pack のたびに作り直され、worker への rsync の元にもなる | head の `~/.cache/vllm-dsv41-flash-exl3/engram-src/` (「Engram の流れ」) | V4.1 EXL3 レシピの `scripts/prepare_engram_src.py` | pack / head のコンテナ / worker への rsync |
| `~/.cache/dsv41-image` | V4.1 EXL3 系のイメージを手で取ったときの blob 置き場 (9.1 GiB)。**読み込み済みなので消してよい** (→「残骸の片付け」) | 両ノードの `~/.cache/dsv41-image/` | 「導入手順 (V4.1 EXL3 系)」の「イメージを手で取る」 | なし (再読み込みのときだけ) |
| memguard | V4.1 EXL3 レシピの監視スクリプト (`scripts/memguard.sh`)。配信中に 1 秒ごとに `MemAvailable` を見て、2 回続けて `DSV41_MEM_GUARD_GIB` (既定 1.5 GiB) を下回ったノードのコンテナを kill する。**起動前のメモリ検査 (`memory headroom`、閾値 111.5 GiB) とは別物**。`.env` の `DSV41_MEM_GUARD=0` で無効 (上流既定) | V4.1 EXL3 レシピの `.env` と `scripts/memguard.sh` | `start.sh` (有効時のみ起動) | — |
| pack | Engram を rank ごとの行ファイル (`engram-l{1,14}-r<rank>of2.bin`、1 本 47.2 GiB) に書き出す操作。head が rank 0 の 2 本、worker が rank 1 の 2 本を作る。起動時に `/engram-packed` へ mount される | 両ノードの `~/dsv41-engram/` | `./start.sh pack` | vLLM |
| `resolve_snapshot.py` / `check-weights.sh` / `verify-weights.py` | Qwen レシピ**限定**の重み検証ツール 3 種。1 つ目はシャードの完全性だけを見る起動前の門、2 つ目は両ノードを見る入口、3 つ目は 1 ノードを HF の manifest と照合する本体 (2 つ目が各ノードで呼ぶ)。**`utility-spark-model-fetch` 同梱の `verify_shards.py` とは別実装で、配布中はスキル側、起動前はレシピ側を使う** | 「重みの検証」 | 上流 (`git clone`) | `start.sh` (1 つ目) / `check-weights.sh` (3 つ目) / 人 |
| `~/spark-bench` | 計測ハーネス一式。`bench.py` が「L1: サーバ単体 (2026-09-05)」の表を、`snap.py` が `/metrics` の前後差分で「L3: OpenCode 込み (2026-09-05)」の表を出す。`results/` に出力が溜まる。**`pc_probe.py` は役割を記録していない** (head 上の実物を読むまで何を測るか分からない)。**dotfiles 管理外で再作成手段が無い** | head の `~/spark-bench/` | 人 | 人 / エージェント |
| `utility-spark-model-fetch` | 新しい重みを head で 1 回落として worker へ rsync するスキル。`scripts/verify_shards.py` を同梱する。使うときは Mac から head の `/tmp/vs.py` へ scp し、head から worker の `/tmp/vs.py` へ scp する (`/tmp` は再起動で消えるので、初回と再起動後は両ノードへ配り直す。手順はスキルの手順 5) | `agents/skills/utility-spark-model-fetch/SKILL.md` | dotfiles | エージェント |
| sparkDash | 監視・SSH 操作・Wake-on-LAN を持つ Web UI。**認証が無い** | head の `~/sparkDash/` | 上流 (`git clone`) | 人 (ブラウザ) |
| `workerLabel` | sparkDash が worker 行に表示するモデル名。**手書きの静的文字列で、実機を見ていない** | head の `~/sparkDash/config/sparks.json` | 人 | sparkDash の UI |
| `docker-compose.override.yml` | sparkDash のポーリング間隔などの上書き。未追跡 | head の `~/sparkDash/` | 人 | `docker compose` |
| 上流 | レシピの配布元。DeepSeek 系は [MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark](https://github.com/MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark)、Qwen 系は [MiaAI-Lab/Qwen3.8-Flash-Next-Dual-DGX-Sparks](https://github.com/MiaAI-Lab/Qwen3.8-Flash-Next-Dual-DGX-Sparks)、V4.1 EXL3 系は [MiaAI-Lab/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks](https://github.com/MiaAI-Lab/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks)、GLM 系は [MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold](https://github.com/MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold) | — | — | — |

## ハードウェアと OS

2 台とも同一構成である。

| 項目 | 値 |
| --- | --- |
| GPU | NVIDIA GB10 (CPU と共有する統合メモリ 128 GB。カタログ値で、`/proc/meminfo` は 121.7 GiB を返す) |
| CPU | 20 コアの big.LITTLE 構成。性能コア Cortex-X925 ×10 (cpu5-9・cpu15-19、`cpuinfo_max_freq` が返す素の上限 3,900 MHz)、効率コア Cortex-A725 ×10 (cpu0-4・cpu10-14、上限 2,808 MHz)。cpufreq は 1 コア 1 policy で、driver は `cppc_cpufreq`、governor は全コア `performance`。**X925 の `scaling_max_freq` は 2,808 MHz に下げてあるが、これはハードウェアのクロック上限を変えていない** (→ 「既知の制約」5)。2026-09-10 に両ノードで実測。確認コマンドは「依拠する外部事実」 |
| OS | Ubuntu 24.04.4 LTS / aarch64 |
| カーネル | `6.17.0-1032-nvidia` |
| ドライバ | `580.173.02` |
| ディスク | 3.7 TiB (使用 1.4 TiB / 空き 2.2 TiB。重み 6 チェックポイント分 (GLM 系の新旧 2 つを含む) と V4.1 EXL3 系の pack を置いた状態。両ノードとも同じ。`df -h /` の実測、2026-10-04) |

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

**`Host spark-head` は `Hostname spark-head.local` に解決されるので、`ssh skanehira@spark-head` と書いても LAN の mDNS 名に化ける。** 出先で Tailscale の MagicDNS 名を使いたいときは上の `spark-head-ts` を経由する。HTTP 側 (`http://spark-head:8888`) は ssh_config を通らないのでこの影響を受けない。

**新しいマシンでは `known_hosts` の登録が要る。** ホスト鍵の受理には TTY での対話が必要で、エージェントの非対話のシェル実行からは `Host key verification failed` で落ちる。ユーザーに次を依頼する (**`known_hosts` はエージェントが書き換えない**)。

```bash
ssh-keyscan spark-head.local spark-worker.local spark-head >> ~/.ssh/known_hosts
```

### 出先 (Tailscale) からのコマンドの読み替え

**本書のコマンドはすべて自宅 LAN 前提で書いてある。** 出先では次の 2 つを読み替える。tailnet (Tailscale ネットワーク) に head しか居ないので、worker には head 経由でしか届かない。

| LAN での書き方 | 出先での書き方 |
| --- | --- |
| `ssh spark-head` | `ssh spark-head-ts` |
| `http://spark-head.local:8888` | `http://spark-head:8888` |

**手で読み替えるのは `ssh` と手打ちの `curl` だけである。OpenCode は自宅でも出先でも Tailscale 側 (`http://spark-head:8888/v1`) に繋ぐ**ので読み替えは要らないが、自宅でも Tailscale へのサインインが要る (→「OpenCode」)。

**`ssh spark-head-ts` を使う前に `~/.ssh/config` に 3 ブロック目があるか確かめる。** この Mac には 1・2 ブロック目しか無く、`ssh -G spark-head-ts` が `hostname spark-head-ts` を返す (2026-09-09 実測)。無ければ「接続する」節の雛形の 3 ブロック目を追記する。

### worker に入る

`known_hosts` に `spark-worker.local` の鍵があれば Mac から直接入れる。無いマシン (および鍵を足せない場面) では head の中から入る。head の `known_hosts` には RoCE 側アドレスの鍵が入っている。

```bash
ssh -n spark-head 'W=$(grep -E "^WORKER_HOST=" ~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark/.env.dspark | cut -d= -f2); ssh -n -o BatchMode=yes "$W" "<worker で実行するコマンド>"'
```

外側がシングルクォートなので `$W` は head 側で展開される。`WORKER_HOST` の値はクォートされていないので `cut -d= -f2` で足りる。

**入れ子の `ssh` には `-n` を付ける。** 付けずに外側をヒアドキュメントや `bash -s` で流し込むと、内側の ssh が残りのスクリプトを標準入力ごと飲み込み、以降のコマンドが実行されないまま正常終了する (出力が途中で切れていたらこれを疑う)。

### 長い処理を ssh から切り離す

**数分を超える処理 (起動・ダウンロード・イメージの転送) をエージェントのシェル実行から流すときは、head 上で切り離し、終わりの印をログに書かせて待つ。** 1 回のコマンド実行には時間上限があり (Claude Code の Bash ツールは 600 秒)、ssh ごと切れると処理も止まりうる。Mac からの ssh 1 本で長い前景処理を流すと、出力が無い間に Mac 側の ssh がタイムアウトする (2026-10-04 に GLM のイメージ転送で実測。head 上の処理は続いていた)。

実行するコマンドは head 上の `~/<名前>.sh` に保存する。変数を使う処理は引用済みの heredoc (`cat > ~/<名前>.sh <<'SCRIPT'` … `SCRIPT`) で保存し、ファイルの先頭に `set -euo pipefail` を書く。変数はそのスクリプトを実行するときに評価される。`<名前>` は処理ごとに分け、同じ名前の処理を同時に走らせない。

```bash
# ~/<名前>.sh を保存してから起動する。heredoc の引用は Mac 側の展開を防ぐ。
ssh spark-head 'bash -s' <<'REMOTE'
cd <ディレクトリ> || exit 1
: > ~/<名前>.log
setsid nohup bash -lc 'bash "$1"; result=$?; printf "EXIT=%s\n" "$result"; exit "$result"' _ ~/<名前>.sh > ~/<名前>.log 2>&1 < /dev/null &
REMOTE
# 終わるまで待つ (この待ちもバックグラウンドで流す)
until ssh -n spark-head 'grep -q "^EXIT=" ~/<名前>.log'; do sleep 30; done
ssh -n spark-head 'tail -5 ~/<名前>.log'   # 最後の行が EXIT=0 なら成功
```

- **`bash -lc` はログインシェルを通すためである。** `hf` は `~/.local/bin` にあり、非ログインシェルの PATH に入っていない
- **起動の ssh が戻らないことがある** (2026-10-04 に GLM の start.sh を切り離して打ち、7 分戻らなかった)。起動の ssh 自体もバックグラウンドで打ち、待ちは別の ssh で行う
- **終わりの印は処理の終了コードを保存してから書く。** 起動前にログを空にするので、前回の `EXIT=0` を今回の成功として拾わない。処理が強制終了されて印が出ない場合は、完了扱いにせずプロセス状態を確認する
- **終わりの印で待つので、`pgrep -f` の自己マッチが起きない。** `pgrep -f <パターン>` は待ちの ssh 自身のコマンド文字列にも一致するので、パターンを `^…$` で固定しないと永久に成立する (V4.1 EXL3 系の起動の待ちはこの固定をしている →「起動と判定 (V4.1 EXL3 系)」)
- **メモリの上限は掛からない。** 配信中のノードで重い処理を流すときは「既知の制約」11 に従って上限付きのコンテナを使い、使えなければ停止後に流す
- **この型そのものは 2026-10-04 時点で未実行である。** 同じ日の作業は、前景の ssh と、プロセス番号を `kill -0` で見る待ちで行った

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
| 推論サーバ (4 系統のどれでも) | `http://spark-head.local:8888` | `http://spark-head:8888` | **なし** |
| sparkDash | `http://spark-head.local:5555` | `http://spark-head:5555` | **なし** |

**8888 はどの系統でも無認証である。** Qwen 系はレシピが `--api-key` を渡さない。GLM 系は TensorFold に API キーの設定項目が無く、ヘッダ無しの `/v1/models` が 200 を返す (2026-10-04)。V4.1 EXL3 系はレシピの `.env` の `VLLM_API_KEY` がコメントアウトされたままで、起動ログの `auth` 行も `none (VLLM_API_KEY empty)` と出す (2026-09-15)。DeepSeek 系は `.env.dspark` の `VLLM_API_KEY` を `docker-compose.dspark.yml` がコンテナの環境変数に渡すしくみだが、**`VLLM_API_KEY` を空にしてある**ので素の無認証で上がる (2026-09-06 に確認)。Qwen 配信中の 8888 は、ヘッダ無しでも出まかせの Bearer でも `/v1/models` が 200 を返すことを実測した (同じ日に存在しないパスが 404 を返すことも確かめてある)。`/health` は手動の到達判定とレシピの起動・停止が、`/v1/models` は OpenCode のプラグイン `spark-served.ts` (起動時と 30 秒ごと) が、`/metrics` は sparkDash と `~/spark-bench/snap.py` が使う。OpenCode が生成に使う経路は `/v1/chat/completions` である。**`/v1/responses` は V4.1 EXL3 系でだけサーバ側にパッチが要る** (→「既知の制約」12)。DeepSeek 系と GLM 系は素で通り (2026-09-23 / 2026-10-02 実測)、Qwen 系は未試行である。GLM 系 (TensorFold) は `/v1/messages` を持たない (→「使える API (GLM 系)」)。

**したがってポート 8888 を信頼できないネットワークへ出さない。** sparkDash のポート 5555 と同じ扱いにする。

sparkDash は head の `~/sparkDash` に clone した [MiaAI-Lab/sparkDash](https://github.com/MiaAI-Lab/sparkDash) である。同梱の `docker-compose.yml` は編集せず、上書きは未追跡の `docker-compose.override.yml` に置く (`git pull` との衝突を避けるため)。反映・停止・更新は `~/sparkDash` で `docker compose up -d` / `down` / `pull` を打つ。**認証が無く tailnet の全端末から SSH 操作と Wake-on-LAN が可能なので、ポート 5555 を信頼できないネットワークへ出さない。**

### API キーの流れ

**現在は OpenCode もそのプラグイン `spark-served.ts` も API キーを使わない。** `/v1/models` の照会にも Authorization ヘッダを付けない。無認証のいま 1Password が要るのは `ccds` (DeepSeek 本家 API) だけである。Spark のキーの正本は `op://Personal/DGX Spark vLLM API Key/credential` で、認証を戻すときはサーバと OpenCode の各段へ値を流す (下の手順 1・2)。

**認証ありに戻すときは、サーバと OpenCode の両方を直す。** サーバだけ直しても OpenCode は起動する。プラグインは 401 を「サーバに届かない」と同じに扱い直前の状態を保つので、常駐サービス起動時なら全モデルが選べるまま、稼働中なら直前の絞り込みのまま動き続け、最初の生成で失敗する (ソースから読んだ挙動で未実測)。クライアントだけ直しても無認証のサーバは Bearer を無視して 200 を返すので、両側を確認する。

1. サーバ側 — 系統ごとに置き場所が違う。値は正本の 1Password 項目から取り、人が書き込む。どのファイルも公開リポジトリの clone の中にあるが追跡外である
   - DeepSeek 系 — `.env.dspark` の `VLLM_API_KEY` に値を入れて `stop` → `start`。**`.env.dspark` は Vision-Exp 版 (`~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark`) と 0731 版 (`~/dspark-0731`) に 1 枚ずつあるので、両方に入れる**
   - Qwen 系 — Qwen レシピの `.env` の `EXTRA_VLLM_ARGS="--api-key <値>"` (未検証 →「Qwen3.8-Flash-Next」の「認証」)
   - V4.1 EXL3 系 — レシピの `.env` の `VLLM_API_KEY` (コメントアウトされたままの行) に値を入れて停止 → 起動する。**認証付きで起動したことは無い (未検証)**
   - GLM 系 — **レシピに API キーの設定項目が無い** (→「GLM-5.3-Flash EXL3」)。認証付きにする手段は確かめていない
2. クライアント側 — **認証用の改修は未実装・未検証である。**
   - OpenCode — 改修が 2 つ要る。(a) `opencode.json` の `provider.spark.options` に `apiKey` を足す。値を平文で置かずに `{file:~/…}` / `{env:…}` で外部へ逃がす記法は opencode 1.18.18 で使えたもので、**V2 で解かれるかは確かめていない**。(b) `spark-served.ts` の `/v1/models` の取得 (`fetchServedModels`) に `Authorization: Bearer <キー>` を付ける。付けないとプラグインは 401 を「届かない」と扱い、配信中モデルの絞り込みが効かなくなる。**キーの渡し方には制約が 3 つある**: プラグインは provider の設定を読めない (setup の時点で組み立てられていない)、公開リポジトリなのでソースに直書きできない、環境変数は常駐サービスに後から届かない (→「OpenCode」)。3 つ目は (a) の `{env:…}` にも同じく掛かる。候補は 2 つある。1 つはリポジトリの外に置いたキーのファイルを、プラグインと (a) の `{file:~/…}` の両方が読む形である。**このキーファイルのパス・書き出す人・権限は未設計である。** もう 1 つは、キーを export したシェルで `opencode service restart` し、新しいサービスにその環境を持たせる形である。restart が呼び出し元の環境を引き継ぐかは確かめていない
3. **OpenCode の設定とプラグインは symlink なので live edit で反映する。** 常駐サービスが変更を監視して読み直す (v2.0.22 のソースで確認、反映は未実測)。symlink が dotfiles に解決するかは `readlink -f` で確認する (→「OpenCode」)。
4. **サーバ側が効いたことを確認する** — `curl -s -o /dev/null -w '%{http_code}\n' http://spark-head.local:8888/v1/models` が **401** を返すこと。200 のままならサーバ側が直っていない (これは「依拠する外部事実」の 200 判定の陽性対照でもある)
5. **OpenCode が通ることを確認する** — `opencode models` が配信名の 1 行だけを返し (起動直後の打ち直しは「OpenCode」)、`opencode run "1+1 は?"` が答えを返すこと。プラグインが 401 を受けている間は絞り込みが効かず、常駐サービスの起動時からなら全モデルが一覧に残る (ソースから読んだ挙動)。

**`bench.py` は無認証でもキー文字列を要求する。** `--key-file` か環境変数 `SPARK_KEY` のどちらも無いと起動時に exit する実装で、渡した値はそのまま `Authorization: Bearer` に載る。無認証のサーバはそれを無視するので、**いまは任意の文字列を書けば足り、1Password は要らない。** 認証を戻した後は正本の 1Password 項目から書き出す。`SPARK_KEY` は head 上の `bench.py` が読む変数である。

```bash
# 無認証のいま (中身は何でもよい)
echo dummy | ssh spark-head 'cat > /tmp/spark.key && chmod 600 /tmp/spark.key'
# 認証を戻した後
op read 'op://Personal/DGX Spark vLLM API Key/credential' | ssh spark-head 'cat > /tmp/spark.key && chmod 600 /tmp/spark.key'
```

- **`/tmp` は再起動で消える。** 2026-09-06 時点では存在しない。`bench.py` を打つときに書き直す
- **`.env.dspark` の控えを作ったら使い終わりに消す。** `.gitignore` が拾うのは `.env.dspark` そのものだけなので、`.env.dspark.bak` のような名前は追跡対象に入りうる。キー行ごと公開リポジトリの clone にステージされる

### 重みの置き場所 (4 系統)

DeepSeek 系・Qwen 系・GLM 系の重みは両ノードの `~/.cache/huggingface/hub/` にある。V4.1 EXL3 系だけは HF キャッシュを使わず、レシピのディレクトリに実ファイルで置く (置き場所は「DeepSeek-V4.1-Flash EXL3」節)。worker は NFS ではなくローカルコピーを持つ。値は `du -sh` の実測 (GLM 系の行は 2026-10-04、V4.1 EXL3 系の行は 2026-09-15、それ以外は 2026-09-06)。ディスク全体の使用量は「ハードウェアと OS」の表にある。

| チェックポイント | head | worker | 備考 |
| --- | --- | --- | --- |
| Vision-Exp | 158 GiB | 157 GiB | DeepSeek 系 |
| Qwen3.8-Flash-Next | 124 GiB | 124 GiB | Qwen 系 (「Qwen3.8-Flash-Next」節) |
| DeepSeek-V4.1-Flash EXL3 | 197 GiB (EXL3) + 190 GiB (Engram) + 95 GiB (pack) | 同じ | V4.1 EXL3 系。ほかにイメージの blob 9.1 GiB が両ノードの `~/.cache/dsv41-image/` に残っている (→ 用語表の `~/.cache/dsv41-image`) |
| GLM-5.3-Flash EXL3 | 164 GiB + DFlash2 2.2 GiB | 同じ | GLM 系 (`models--Mia-AiLab--GLM-5.3-Flash-EXL3-4bpw-TensorFold`)。ドラフタ (`models--incoai--GLM-5.3-Flash-DFlash2`) が別リポジトリなので 2 つに分かれる。ほかに、レシピ v1.2 へ戻す用の TR3 (`models--Mia-AiLab--GLM-5.3-Flash-EXL3-TR3-4bpw`、164 GiB) と、v0.5.0 のイメージの blob 11 GiB (`~/.cache/glm53-tf-image/`) が両ノードにある |
| DeepSeek-V4-Flash-0731 | 156 GiB | 156 GiB | DeepSeek 系の 0731 版 (revision `9e165c30e2704aec5d9d593cce3eebd58bbef1cb`、両ノードで同一。2026-09-23 確認) |

**配信の候補は Vision-Exp、0731、Qwen3.8-Flash-Next、DeepSeek-V4.1-Flash EXL3、GLM-5.3-Flash EXL3 の 5 つで、どれか 1 つだけが動く。** Vision-Exp と 0731 は同じ DeepSeek 系のレシピで動き、コンテナ名も同じなので、どちらが配信中かは `/v1/models` の配信名で見分ける。5 つともポート 8888 と GPU を共有するので同時に起動できない。

### メモリの使われ方

GB10 は CPU と GPU が同じ物理メモリを共有する統合メモリ構成である。**`GPU_MEMORY_UTILIZATION_TEXT=0.835` は通常の GPU なら VRAM の 83.5% を指すが、ここではシステムメモリ全体の 83.5% を意味する。** 起動直後から 100 GiB 超が vLLM に確保されて `free` の残りが数 GiB になる (DeepSeek 系で 6〜8 GiB、Qwen 系の head は 1.3〜5.7 GiB) が、これは設定どおりの先取りであって、リークでも不足でもない。**V4.1 EXL3 系は仕組みが違う。** 確保率のキーを予算に使わず、重み (起動ログで 99.8 GiB。vision tower を含む) と KV プール (`KV_CACHE_MEMORY_BYTES` で固定した 2.5 GiB) を確保する。head の残りは 4.8 GiB になる。これは先取りではなく実際の余裕の少なさなので、扱いは「既知の制約」11 に従う。

**値は配信中の系統で変わる。** DeepSeek 系の列は 2026-09-23 に起動 15 分後の無負荷で採った値、Qwen 系の列は 2026-09-09 の再起動後に無負荷で採った値 (`MemAvailable` だけは 2026-09-06 の高負荷時からの幅)、V4.1 EXL3 系の列は 2026-09-30 に画像入力を有効にして起動し、smoke と画像 2 件を流した後の値、GLM 系の列は 2026-10-04 にレシピ v1.5 で起動し、検証の生成を 20 件ほどと OpenCode の 1 往復を流した後の値である。

| 項目 | DeepSeek 系 head / worker | Qwen 系 head / worker | V4.1 EXL3 系 head / worker | GLM 系 head / worker |
| --- | --- | --- | --- | --- |
| 物理メモリ合計 | 121.7 / 121.7 GiB | 121.7 / 121.7 GiB | 121.7 / 121.7 GiB | 121.7 / 121.7 GiB |
| 推論サーバの確保 | 101.1 / 101.1 GiB (`nvidia-smi` の 103,540 / 103,530 MiB) | 100.7 / 100.8 GiB | 104.4 / 104.4 GiB (`nvidia-smi` の 106,907 MiB) | 91.1 / 90.1 GiB (`nvidia-smi` の 93,318 / 92,240 MiB) |
| `MemAvailable` | 6.8 / 7.1 GiB | 1.3〜5.7 / 5.6〜10.1 GiB | 4.8 / 5.9 GiB | 14.3 / 12.8 GiB |
| swap 使用 | 4.3 / 5.4 GiB | 5.0 / 4.1 GiB | 4 / 7 GiB | 1.6 / 3.5 GiB |

**DeepSeek 系の swap は直前に何を配信していたかで動く。** 上の値は 44 時間 Qwen 系を配信した直後に切り替えたときのもので、前の系統が押し出したページを含む。**swap の量を系統の特性として読まない。**

DeepSeek 系と Qwen 系は期待値 121.7 × 0.835 = 101.6 GiB の近傍に収まる (DeepSeek 系 101.1 GiB / Qwen 系 100.7 GiB)。V4.1 EXL3 系は確保率ではなく KV プールをバイト数で固定する方式なので、この式は当てはまらない (→「DeepSeek-V4.1-Flash EXL3」)。GLM 系 (TensorFold) も確保率を持たず、起動時の空きから 14.5 GiB の予備を残して予算を決める (→「GLM-5.3-Flash EXL3」の表の「メモリの予算」の行)。配信中に重い処理を流すときは、どの系統でも「既知の制約」11 の上限付きで行う。head の残りが worker より少ないのは、head だけがデスクトップセッション・sparkDash・tailscaled を抱えているためである。**Qwen 配信中の head の空きは負荷と稼働時間で 1.3〜5.7 GiB を動く** (2026-09-06 の高負荷時 1.3〜1.7 GiB / 2026-09-09 の再起動直後 5.7 GiB)。**これも先取りであって不足ではない。メモリを空けたくなったらプロセスを探す前にこの値を疑う。**

## サービングの系統

**レシピは 4 系統あり、ポート 8888 と GPU を共有するので同時には 1 つしか配信できない。** 系統をまたいで切り替える手順は「系統の切り替え」にある。

### DeepSeek 系 (Vision-Exp / 0731)

**この節は DeepSeek 系の話である。** Qwen 系の起動・停止は「Qwen3.8-Flash-Next」節の「起動と判定 (Qwen 系)」、V4.1 EXL3 系は「起動と判定 (V4.1 EXL3 系)」、GLM 系は「起動と判定 (GLM 系)」にある。系統をまたいで切り替える手順は「系統の切り替え」にある。**以下の本文と小節は Vision-Exp 版の話で、0731 版との違いは末尾の「0731 版で配信する」にまとめてある。**

head の `~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark` が上流レシピの clone である。**head で起動すると `.env.dspark` を worker へ SSH で配り直して両ランクを立ち上げるので、worker で直接コマンドを打つ必要はない。** head から worker へは head 上で生成して worker に登録済みの鍵 `~/.ssh/id_ed25519` を使い、`.env.dspark` の `WORKER_HOST` (RoCE 側のアドレス) に入る。

```bash
ssh spark-head
cd ~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark
./validate-dspark-config.sh            # 起動せずに解決値だけ確認する
./start-deepseek-v4-flash-dspark.sh    # 両ランク起動。約 7〜8 分 (`97e8733` で実測 444 秒)
./smoke-deepseek-v4-flash-dspark.sh    # 疎通確認
./status-deepseek-v4-flash-dspark.sh   # 両ランクのコンテナ状態
./logs-deepseek-v4-flash-dspark.sh     # head 側のログを追う
./stop-deepseek-v4-flash-dspark.sh     # 両ランク停止
```

**`start` は API が応答するまで待ってから戻る** (スクリプトの末尾で `/health` を待ち、通ると `DeepSeek V4 Flash DSpark is running` を出す)。約 7〜8 分かかるので、エージェントのシェル実行からは「長い処理を ssh から切り離す」の型で流す。

**以下この節の `stop` / `start` は DeepSeek 系スクリプトの略記である** (Qwen 系は `stop.sh` / `start.sh` で別物)。**設定を変えたら `docker compose restart` を使わず、`stop` → `start` で作り直す。** 起動時にコンテナ内の vLLM へ多数のパッチを当てる構成なので、restart では古いバイト列が残る。

正常稼働の判定は 2 段で行う。

1. `curl -fs http://spark-head.local:8888/health` — exit 0 なら API は生きている
2. `./smoke-deepseek-v4-flash-dspark.sh` — 実際に生成が通る。`set -euo pipefail` で書かれており失敗時は exit 1 または 2 を返すので、**exit 0 で合格**

`.env.dspark` の既定値は `.env.dspark.example` にある。サイト固有の値 (IP・NCCL のデバイス名・API キー) を除くと、上流の配布既定から変更しているのは次の 3 つである。

| キー | 値の意味 | 既定 | 現在 | 採用根拠 | 効果 |
| --- | --- | --- | --- | --- | --- |
| `DSPARK_MAX_INFLIGHT_PREFILLS` | 同時に走らせる prefill の件数 | 1 | 2 | 上流 issue #217 の A/B | **上流計測値**: 2 ノード TP=2・`LONG_PREFILL_TOKEN_THRESHOLD=1024` で 3 回の cold boot にわたる ABA 比較。4 並列 8K で公平性の開き 1.50〜1.57 倍 (既定 1 では 1.53 倍)、preemption は両条件とも 0、TTFT の開きは 2.1〜2.4 倍 (既定 1 では 4.1 倍)。**ただし 4 並列 32K のバーストでは開きが 3.0〜3.3 倍に広がる** (既定 1 では 2.1 倍)。head の `docs/CLAUDE/ab-results-2026-09-03.md` にある古い A/B は、上流自身が「undercounting のスケジューラで走ったので現行の挙動を示さない」と取り下げている。自環境では未計測 |
| `DSPARK_ENABLE_SP_INDEXER` | 0 = 無効 / 1 = 有効 | 0 | 1 | 上流の最終構成に追従 | 自環境では未計測 |
| `DSPARK_ENABLE_DEEPGEMM_SM121_ALIAS` | 0 = 無効 / 1 = 有効 | 0 | 1 | 上流の最終構成に追従 | 自環境では未計測 |

**この差分を自分で取り直すときは正規表現に注意する。** `grep -E '^[A-Z_]+='` はキー名に数字を含む `DSPARK_ENABLE_DEEPGEMM_SM121_ALIAS` を落とす (90 行中 75 行しか拾わない)。`^[A-Za-z0-9_]+=` を使う。同様に、キー行を伏せるための `grep -vi token` は `MTP_NUM_TOKENS` も巻き込む。

#### サービングの構成 (DeepSeek 系)

**この節は DeepSeek 系を配信しているときの話である。** Qwen 系の構成は「Qwen3.8-Flash-Next」、V4.1 EXL3 系の構成は「DeepSeek-V4.1-Flash EXL3」、GLM 系の構成は「GLM-5.3-Flash EXL3」にある。**本書の「DeepSeek 系」は DSpark レシピで配信する Vision-Exp 版と 0731 版を指し、同じ DeepSeek のモデルでも V4.1 EXL3 系を含まない。** この節の表は Vision-Exp 版の値で、0731 版との違いは「0731 版で配信する」にある。値の出所はすべて `.env.dspark` (「KV キャッシュ」「画像入力」「レシピの commit」「`.env.dspark` に**書いていない**上流キー」の 4 行を除く)。

| 項目 | 値 |
| --- | --- |
| チェックポイント (`DSPARK_MODEL_OFFICIAL` / `DSPARK_REVISION`) | `deepseek-ai/DeepSeek-V4-Flash-Vision-Exp` @ `86f746b36186f0e567729a5c06a8c918caba82a9` (`start-deepseek-v4-flash-dspark.sh` と `validate-dspark-config.sh` が持つ上流既定 `DEFAULT_OFFICIAL_REVISION` と同値なので、`.env.dspark` の行を消しても同じ revision になる) |
| API 上のモデル名 (`SERVED_MODEL_NAME`) | `deepseek-v4-flash-vision-exp` |
| コンテキスト上限 (`MAX_MODEL_LEN`) | サーバ 1,048,576 トークン (ネイティブ。YaRN 不要) |
| 同時リクエスト上限 (`MAX_NUM_SEQS`) | 6 リクエスト。超過分はエラーにならずキューで待つ |
| 投機デコード (`MTP_NUM_TOKENS`) | DSpark、draft 6 トークン |
| メモリ確保率 (`GPU_MEMORY_UTILIZATION_TEXT`) | 0.835 (意味は「メモリの使われ方」)。**`.env.dspark` に `GPU_MEMORY_UTILIZATION` を書いても効かない** — `start-deepseek-v4-flash-dspark.sh` が `GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION_TEXT:-0.835}"` と無条件に代入するので、書いた値は黙って捨てられる |
| KV キャッシュ | `nvfp4_ds_mla` (`.env.dspark` にキーは無く、`docker-compose.dspark.yml` が `--kv-cache-dtype` に直書きしている) |
| 画像入力 (`LIMIT_MM_PER_PROMPT`) | 使える。1 プロンプトあたり 8 枚 (compose の既定。`.env.dspark` にキーは無い)。2026-09-23 に 8x8 の赤い PNG を data URL で `/v1/chat/completions` に渡して「赤」と回答することを実測した。ViT とアライナは起動時の `hotfix-dsv4-vision-exp.py` が入れる。**動画は配線されていない** (公式の重みに動画エンコーダが無く、GIF は静止画 1 枚として解釈される)。枚数を増やすときは `.env.dspark` に `LIMIT_MM_PER_PROMPT=image=N` と書く。**`{"image":N}` の形で書いてはいけない** — `start-deepseek-v4-flash-dspark.sh` が `source` する際に引用符が落ちて `{image:N}` になり、argparse の `json.loads` が弾く |
| 既定の reasoning (`DEFAULT_THINKING`) | `low` (取りうる値: `off` / `low` / `high` / `max`)。リクエスト単位の指定が優先する。OpenCode は `opencode.json` の `reasoningEffort` (`high`) を、`bench.py` は `chat_template_kwargs` を明示する。リクエスト単位の語彙はこのキーと違い、`off` は送れない (→「DeepSeek 系の reasoning effort の語彙」) |
| コンテナイメージ | `ghcr.io/anemll/dspark-vllm-gx10:0.1.1@sha256:a83948492cf13df455170fb42885f5ef4db54fefe0feff0f841ecbff464ac9d8` (DSpark ランタイムの配布元 Anemll) |
| レシピの commit | `97e8733` (2026-09-23 に `git pull --ff-only` で追従。上流の先行分は「依拠する外部事実」の確認コマンドで見る。速い変化があるので本書に数を書かない) |
| `.env.dspark` に**書いていない**上流キー | 8 つ。**すべて上流既定が `0` の opt-in で、書かないことが現行動作である** (値の出所はこの行だけ `.env.dspark.example` と上流の CHANGELOG)。内訳は投機・注意機構まわりの 6 つ (`DSPARK_ENABLE_ROPE_SWA_FIX` / `DSPARK_ENABLE_DSPARK_SWA_PREFIX` / `DSPARK_ENABLE_DSML_RECOVERY` / `DSPARK_ENABLE_MXFP4_INDEXER_CACHE` / `DSPARK_ENABLE_C128A_PREFILL_CACHE` / `DSPARK_ENABLE_ISSUE144_EFFORT_ALIGN`) と、refusal-direction の実行時射影に使う 2 つ (`DSV4_ABLATE_LAMBDA` / `DSV4_ABLATE_LAYERS`。`ABLITERATED=0` のとき無効で、有効化には HF の gated 規約への同意が要る)。**上流は 6 つすべてについて「有効化の前に実機の A/B を通せ」と書いているので、採用は 1 つずつ測ってから行う。** ほかにコメントアウトされた形でだけ現れるキーが 2 つある (`DSPARK_ABLATE_SOURCE_FILE` / `NCCL_GIN_ENABLE`)。後者は `0` にすると NCCL の comm-init が約 2 分から 13 秒に縮む (上流計測、2026-09-05、帯域は不変)。当方の起動は現に完走しているので入れていない |

#### DeepSeek 系の reasoning effort の語彙

**弾くのは 3 経路ともスキーマ (pydantic の Literal) で、Qwen 系のようなチャットテンプレートの `raise_exception` ではない。** 2026-09-23 に 3 経路で実測した。表のセルの 200 / 400 は HTTP ステータスである。確認コマンドは「依拠する外部事実」の reasoning effort の行と同じ形で、**モデル名を `deepseek-v4-flash-vision-exp` に、陽性対照の値を `bogus` にする** (この系統は `high` も `medium` も受理するので、既存の系統の陽性対照は流用できない)。

| 値 | `/v1/messages` | `/v1/chat/completions` (OpenCode) | `/v1/responses` |
| --- | --- | --- | --- |
| `low` / `medium` / `high` / `xhigh` / `max` | 200 | 200 | 200 |
| `none` / `minimal` | **400** (スキーマ) | 200 | 200 |
| `off` | 400 | 400 | 400 |
| 語彙外 (`bogus` など) | 400 | 400 | 400 |
| 指定なし | 200 (既定 `low`) | 200 (既定 `low`) | 200 (既定 `low`) |

- **400 の本文が受理語彙を名乗る。** `/v1/messages` は `Input should be 'low', 'medium', 'high', 'xhigh' or 'max'`、他の 2 経路は `Input should be 'none', 'minimal', 'low', 'medium', 'high', 'xhigh' or 'max'` を返す。**経路ごとに語彙が 2 語ずれるのはスキーマが別クラスだからである** (`/v1/messages` は `AnthropicOutputConfig.effort`、`/v1/chat/completions` は `reasoning_effort`、`/v1/responses` は `reasoning.effort`)
- **`none` の非対称は Qwen 系・V4.1 EXL3 系と同じ構造である** (→「Qwen の reasoning effort の語彙」)。弾くのは `/v1/messages` のスキーマだけ
- **`off` はリクエストからは送れない。** `DEFAULT_THINKING` のほうは `off` を取るが、それはサーバ起動時の既定を決めるキーであって、リクエストの effort とは語彙が別である。**混同すると 3 経路すべてで 400 になる**
- **OpenCode は `opencode.json` で `high` を送る。** この値は 3 API 経路とも 200 を実測済みである
- **コンテナ起動時に値のマッピングが書き換わる。** compose の起動チェーンが `vllm/tokenizers/deepseek_v4.py` に 1 か所パッチを当て、`max` / `xhigh` は `max` に、`high` は `high` に、**それ以外はすべて `low`** に落とす。つまり `medium` / `none` / `minimal` はスキーマを通っても深さは `low` と同じになり、**実効的な深さは `low` / `high` / `max` の 3 段である**。**これはパッチのソースから読んだもので、出力の深さの差そのものは測っていない。** パッチは encoder のコピーと同じ条件分岐の中にあるので、起動ログに `WARN: encoding_dsv4.py not found` が出た起動では当たっていない (`97e8733` の起動では 0 件)

#### 使える API (DeepSeek 系)

**3 経路すべてが通る (2026-09-23 に実測)。**

| 経路 | 用途 | 実測 |
| --- | --- | --- |
| `/v1/chat/completions` | OpenCode | `smoke-deepseek-v4-flash-dspark.sh` が 6 並列で 6/6 成功 (exit 0)。画像入力も同じ経路で確認 |
| `/v1/messages` | Anthropic Messages API | 生成が `stop_reason: end_turn` で返る。このイメージの vLLM は Anthropic ルータをフラグ無しで持つ |
| `/v1/responses` | Responses API | Responses API の `input_text` パーツが HTTP 200 で通る。**V4.1 EXL3 系で要る `patch_responses_content_parts.py` 相当のパッチは、この系統では要らない** (→「既知の制約」12) |

いずれも curl で経路を確かめたもので、**OpenCode を通した疎通とツール呼び出しはこの系統では未実測である。**

#### レシピを更新する (DeepSeek 系)

上流の更新を取り込む順路である。**`.env.dspark` は追跡外なので `git pull` では消えない。** `git pull` は稼働中のコンテナが読まないファイルしか触らないので、**他系統を配信したままでも打てる。**

```bash
ssh spark-head
cd ~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark
git fetch -q && git log --oneline HEAD..origin/main    # 先行分を読む
OLD=$(git rev-parse --short HEAD); echo "戻し先: $OLD"  # 戻すときに使うので控える
git pull --ff-only
./validate-dspark-config.sh | head -20                 # 解決値が変わっていないことを見る
diff <(grep -E '^[A-Za-z0-9_]+=' .env.dspark.example | sed -E 's/=.*//' | sort) \
     <(grep -E '^[A-Za-z0-9_]+=' .env.dspark | sed -E 's/=.*//' | sort)
```

最後の `diff` は**上流にキーが増えていないか**を見るために打つ (キー名だけを出すので値は漏れない)。`<` 側に出たものが「`.env.dspark` に**書いていない**上流キー」で、増えていたら「サービングの構成 (DeepSeek 系)」の同名の行を更新する。`>` 側は `VLLM_API_KEY` だけが出るのが正しい (空値で保持している)。

**`scripts/ci-validate.sh` は配信中に流さない。** 上流が足した CPU テスト一式を呼ぶので、`MemAvailable` が数 GiB しかない配信中のノードでは「既知の制約」11 の固まり方を招く。流すなら停止中に行う。

**更新後は次の 6 点で悪化していないことを確かめる。** 起動の 2 段判定は起動の可否しか見ないので足りない。2 と 3 は**停止する前に取っておき**、起動後の値と突き合わせる。

1. 起動の 2 段判定 (`/health` → `smoke-deepseek-v4-flash-dspark.sh` が exit 0)
2. `/v1/models` の `id` と `max_model_len` が `deepseek-v4-flash-vision-exp` / 1,048,576 で一致すること。`curl -s http://spark-head.local:8888/v1/models | python3 -c 'import json,sys; d={m["id"]:m.get("max_model_len") for m in json.load(sys.stdin)["data"]}; print(d); sys.exit(0 if d.get("deepseek-v4-flash-vision-exp")==1048576 else 1)'` が exit 0 で合格。**`created` と `permission` は起動のたびに変わるので全文比較に使わない**
3. reasoning effort の語彙が変わっていないこと (→「DeepSeek 系の reasoning effort の語彙」。**3 経路とも打つ**)
4. `docker inspect deepseek-v4-flash-vllm-dspark-1 --format '{{.HostConfig.RestartPolicy.Name}}'` が両ノードで `unless-stopped` のままであること
5. `/v1/responses` が `input_text` を 200 で受けること (「依拠する外部事実」のコードブロック 6 のモデル名を `deepseek-v4-flash-vision-exp` に差し替える)
6. 画像入力が通ること (「依拠する外部事実」のコードブロック 10 のモデル名を `deepseek-v4-flash-vision-exp` に差し替える)

**`./validate-dspark-config.sh` の `cudagraph capture size` の表示は実効値ではない。** 表示は `MAX_NUM_SEQS × (MTP_NUM_TOKENS + 1)` をそのまま出すが、compose が vLLM に渡すのは 8 の倍数へ切り上げた値である (6 × 7 = 42 と表示され、実際は 48)。**この差を不合格の根拠にしない。**

**起動ログの先頭に `WARN: serving an UNAUTHENTICATED API on 0.0.0.0:8888` が出るのは正常である。** `VLLM_API_KEY` を空にしている当方の構成を上流が警告しているだけで、起動は止まらない。**この警告が消えていたら、意図せず認証が付いたことを疑う** (→「API キーの流れ」)。**`.env.dspark` の mode に対する `chmod 600` の警告は、秘密キーを 1 つも設定していないので出ない。**

戻すときは `git checkout <旧 sha>` してから停止 → 起動する (`<旧 sha>` は上のコードブロックが `git pull` の前に出した「戻し先」。detached HEAD になるので復帰は `git checkout main`)。重み・イメージ・`.env.dspark` のいずれも変わらないので戻せる。

**この手順で更新するのは `~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark` (Vision-Exp 版) だけである。** `~/dspark-0731` は更新しない (→ 次の小節)。

#### 0731 版で配信する

**テキスト専用の 0731 を、同じ DeepSeek 系のスクリプトで配信する。** 画像入力を手放す代わりに decode が速い (→ 下の比較表)。

**起動は `~/dspark-0731` から行う。** 現行 `main` (`97e8733`) の起動スクリプトは Vision-Exp 専用で、`MTP_NUM_TOKENS` に「5 以上かつ 3 の倍数」を課し (Vision-Exp の `n_predict=3` に合わせた検査)、vision のホットフィックスを無条件に当てる。0731 は `n_predict=1` で k=5 が本来の形なので、`main` からは起動できない。`~/dspark-0731` は 0731 を配信していた当時の `70a7cc4` に detached で固定した git worktree で、0731 用の `.env.dspark` (mode 600) を持つ。**この worktree で `git pull` や `git checkout main` をしない。** Vision-Exp 専用の検査が入って 0731 が起動しなくなる。

| 項目 | 0731 版 | Vision-Exp 版との違い |
| --- | --- | --- |
| 作業ディレクトリ | head の `~/dspark-0731` @ `70a7cc4` | Vision-Exp 版は `~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark` @ `97e8733` |
| チェックポイント | `deepseek-ai/DeepSeek-V4-Flash-0731` @ `9e165c30e2704aec5d9d593cce3eebd58bbef1cb` | 別チェックポイント。重みは両ノードの HF キャッシュにある |
| 配信名 (`SERVED_MODEL_NAME`) | `deepseek-v4-flash-0731` | 別名。OpenCode は `opencode.json` の宣言が要る (宣言済み)。プラグインが `/v1/models` から選ぶ |
| 投機デコード (`MTP_NUM_TOKENS`) | DSpark、draft 5 トークン | Vision-Exp 版は 6 |
| 画像入力 | 使えない | — |
| コンテナ名 | `deepseek-v4-flash-vllm-dspark-1` | 同じ。どちらが動いているかは `/v1/models` で見る |
| worker 側の配布先 | worker の `~/dspark-0731` (`WORKER_DIR` が空なので head と同じパスになる) | 別ディレクトリなので、Vision-Exp 版の配布物は上書きされない |
| 同じもの | イメージ (同じ digest)、`MAX_MODEL_LEN` 1,048,576、`MAX_NUM_SEQS` 6、`GPU_MEMORY_UTILIZATION_TEXT` 0.835、チューニング 3 キー、`VLLM_API_KEY` 空、restart policy `unless-stopped` | — |
| cold start | health まで約 8.5 分 (2026-09-23 実測 507 秒) | Vision-Exp 版は約 7〜8 分 |

**起動と停止は同じスクリプトを `~/dspark-0731` で打つ。** 判定も Vision-Exp 版と同じ 2 段 (`/health` → `./smoke-deepseek-v4-flash-dspark.sh` が exit 0) で、2026-09-23 に 6/6 で通った。**`~/dspark-0731` の launcher は `97e8733` の堅牢化 (全 ssh の `BatchMode` と `ConnectTimeout`、stop のコンテナ名フィルタのアンカー化など) を持たない。** worker が途中で応答しなくなると起動がタイムアウトせずに止まり続けうる。

**reasoning effort の語彙は Vision-Exp 版と同じである** (2026-09-23 に 3 経路で全値を実測。→「DeepSeek 系の reasoning effort の語彙」)。OpenCode が送る `high` は 3 経路とも 200 になる。`/v1/responses` は `input_text` をパッチ無しで 200 で受ける。

**decode の比較** (2026-09-23、無負荷、各条件 3 回の中央値、計測方法は「実測値」節の「decode の分解 (2026-09-23)」)。

| 条件 | Vision-Exp (tok/s) | 0731 (tok/s) | 差 |
| --- | --- | --- | --- |
| コード、thinking off、短文 | 70.0 | 80.2 | +15% |
| コード、32K 文脈 | 66.6 | 80.0 | +20% |
| コード、100K 文脈 | 64.4 | 75.9 | +18% |
| 日本語の散文、thinking off | 26.8 | 33.8 | +26% |
| 数の列挙、thinking off | 81.0 | 90.5 | +12% |
| 6K フィラー + コード指示、thinking `low`、256 トークン強制 | 42.4 | 44.4 | +5% |
| 同じ入力で自然終了 | 44.8 | 46.1 | +3% |

- **thinking を切った条件では 12〜26% 速い。** 1 ステップのトークン数が増え (コードで 5.05 → 5.50、散文で 1.77 → 2.12)、k が 6 から 5 に減って 1 ステップも 3〜7 ms 軽くなる
- **thinking `low` の 2 条件では差が 3〜5% に縮む。** 1 ステップのトークン数はむしろ Vision-Exp 版のほうが多く (3.05 対 2.84)、差は 1 ステップが軽いぶんだけである。**推論を伴う実負荷での伸びは、thinking off の条件ほど大きくないと見込む**
- 上流が同じ機材で記録した比較 (greedy で −15〜20%、temperature 0.6 で −20〜30%、いずれも Vision-Exp 側) は thinking off の条件と整合する

**Vision-Exp 版へ戻すときは、`~/dspark-0731` で停止してから `~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark` で起動する** (→「系統の切り替え」の表)。重みと `.env.dspark` はチェックポイントごとに別で、イメージは同じものを読み取るだけなので、切り替えで書き換わるものは無い。

### Qwen3.8-Flash-Next

**他の 3 系統とは別リポジトリ・別イメージ・別スクリプト名である。** 混同すると停止スクリプトが効かない。2026-09-06 に配置・起動・OpenCode (opencode 1.18.18) からの疎通まで確認した。`/v1/responses` は未試行である。2026-09-09 の更新後に起動の 3 段判定と reasoning effort の語彙を取り直したが、OpenCode の疎通は再確認していない。V2 の OpenCode からは試していない。

**この構成には認証が無い。** 下の「認証」を先に読む。

値の出所はレシピの `.env` である (「レシピ」「重み」「画像入力」「既定の reasoning」「コンテナ名」「`.env` に**書いていない**上流キー」の 6 行と、「コンテナイメージ」の Id・サイズを除く。最後の 1 行だけは定義上 `.env` に無い値なので、出所は `.env.sample` と上流の CHANGELOG である)。

| 項目 | 値 |
| --- | --- |
| レシピ | head の `~/Qwen3.8-Flash-Next-Dual-DGX-Sparks` @ `0b62e12` |
| チェックポイント (`MODEL_ID`) | `nvidia/Qwen3.8-Flash-Next-NVFP4`。**revision を固定するキーは `.env` に無い**。`files/resolve_snapshot.py` が `refs/main` の指す snapshot を優先し、`model.safetensors.index.json` が名指すシャードが全て揃っていることを起動前に検査する (`refs/main` が不完全なら他の完全な snapshot を探し、それも無ければ `start.sh` が止まる)。当方の `refs/main` は `fab0aecb760cec45227f6656abcaafa11abca87a` で、snapshot もこれ 1 つだけ (検証手段と revision が動く条件は → 「重みの検証」) |
| 重み | 124 GiB / safetensors 11 本 (`du -sh` の実測)。レシピの `.env` のコメントの 133G は 10 進 GB での表記で、実測と食い違わない (HF の manifest は 132.7 GB、vLLM の起動ログは 123.57 GiB と出る)。**両ノードに配置済み** |
| API 上のモデル名 (`SERVED_MODEL_NAME`) | `qwen3.8-flash-next` |
| 画像入力 | 使える (2026-09-06 に実測。8x8 の赤い PNG を data URL で渡して「赤」と回答) |
| コンテキスト上限 (`MAX_MODEL_LEN`) | サーバ 524,288 トークン。**ネイティブは 262,144 で、`YARN_ENABLE=true` + `YARN_FACTOR=2.0` で伸ばしている** |
| 同時リクエスト上限 (`MAX_NUM_SEQS`) | 8 リクエスト |
| 投機デコード (`MTP_NUM_SPECULATIVE_TOKENS`) | MTP、draft 3 トークン |
| KV キャッシュ (`KV_CACHE_DTYPE`) | `fp8` |
| メモリ確保率 (`GPU_MEMORY_UTILIZATION`) | 0.835 (DeepSeek 系と同値だがキー名が違う。意味は「メモリの使われ方」) |
| 既定の reasoning | `xhigh` (`.env` に該当キーが無く、チャットテンプレートの既定が効く)。**2 経路 (`/v1/messages` と OpenCode の `/v1/chat/completions`) から使えるのは `low` / `medium` / `xhigh` の 3 つ。`high` と `max` はどちらの経路でも 400 になる** (詳細は直下の「Qwen の reasoning effort の語彙」) |
| コンテナイメージ | `vllm/vllm-openai:qwen38-flash-next` (Id `sha256:d464f3b466fa9c45ddbff8a812e80564503b6879a9fd95c1a47514f3f0df5a4a`、20.6 GB (`docker images` の 10 進表示)、arm64)。**両ノードに配置済み** |
| コンテナ名 | `vllm-fn` (head と worker で同名。`start.sh` が付ける) |
| 追加の vLLM 引数 (`EXTRA_VLLM_ARGS`) | 未設定 (`.env` でコメントアウトされている)。認証を付けるならここに `--api-key <値>` を書く |
| 起動前の GPU ガード (`REQUIRE_IDLE_GPU`) | `true` (上流既定のまま。取りうる値: `true` / `false`)。どちらかのノードで GPU を掴むプロセスがあれば起動を拒否する |
| 上流既定からの差分 | **値を変えた**キーが 5 つ (下の「書いていない上流キー」2 つは別勘定)。**サイト固有が 2 つ**: `IFACE` = `enp1s0f1np1` / `IB_HCA` = `=rocep1s0f1` (先頭の `=` は「完全一致で 1 デバイスだけ」を意味する上流の記法で、typo ではない)。**常用長に合わせたものが 3 つ**: `MAX_MODEL_LEN` 262144 → 524288 / `YARN_ENABLE` false → true / `YARN_FACTOR` 4.0 → 2.0 (理由は下の「YaRN」)。`HEAD_IP` / `WORKER_IP` は配布既定のまま実機と一致するので変更していない (実値は「依拠する外部事実」の確認コマンドで引く) |
| `.env` に**書いていない**上流キー | 2 つ。どちらも未設定が現行動作なので `.env` に足していない (値の出所はこの行だけ `.env.sample` と上流の CHANGELOG)。**`ABLIT`** (未設定 = 0。1 は値の切り替えではなく**別チェックポイントへの乗り換え**で、`drowzeys/keys-Qwen3.8-Flash-Next-NVFP4-dual-ablit-house-qsa-L3-47` を full snapshot で取り直す。HF 上での規約同意と `HF_TOKEN` (`.env` に書くか環境変数で渡す。この 2 キーだけは環境が `.env` に優先する) に加えて、124 GiB 級の取得と worker への配布が要る → `utility-spark-model-fetch`)。**`MAMBA_SSM_CACHE_DTYPE`** (未設定 = チェックポイントの float32。`bfloat16` にすると再帰状態の dtype が半分になる。**上流の「集約 decode スループット +8.5%」は単 Spark TP=1 での計測で、この 2 ノード TP=2 では未計測**と上流自身が書いている)。採用は `.env` に 1 行足して停止 → 起動、戻すのは行を消して同じ再起動 (13〜14 分止まる → 「既知の制約」7)。**`.env.sample` 側の既定は `ABLIT=0` / `MAMBA_SSM_CACHE_DTYPE=bfloat16` なので、`.env` を作り直すと後者が黙って有効になる** |

#### Qwen の reasoning effort の語彙

**受理される値はエンドポイントで違う。** 2026-09-06 に両経路で全値を実測した (確認コマンドは「依拠する外部事実」の reasoning effort の行)。表のセルの 200 / 400 は HTTP ステータスである。

| 値 | `/v1/messages` | `/v1/chat/completions` (OpenCode) | 弾く層 |
| --- | --- | --- | --- |
| `low` / `medium` / `xhigh` | 200 | 200 | — |
| `none` | **400** | 200 | `/v1/messages` のスキーマ |
| `high` / `max` | 400 | 400 | チャットテンプレート |
| 指定なし | 200 (既定 `xhigh`) | 200 (既定 `xhigh`) | — |

**両 API 経路で共通して使える値は `low` / `medium` / `xhigh` の 3 つである。`/v1/responses` はこの系統では未実測である。**

- **`high` と `max` を弾くのはチャットテンプレートである。** `xhigh` / `medium` / `low` 以外で `raise_exception` する。エラー本文 `Unexpected reasoning effort high. Supported types are xhigh (default), medium, and low.` は既定値を自分で名乗る。**この層は両経路に共通する**ので、Anthropic ルータ (`/v1/messages`) も同じく 400 になる。ルータは `output_config.effort` を `reasoning_effort` に写して同じテンプレートへ渡すだけである
- **`none` が `/v1/chat/completions` でだけ通るのは、テンプレートに届く前に効果が消えるためである。** vLLM は `reasoning_effort != "none"` を `enable_thinking` に導出し、テンプレートは `enable_thinking` が偽なら effort を見ない (`reasoning_effort` 自体はテンプレートに渡るが、その分岐に入らない)。**`/v1/messages` にはこの抜け道が無い。** `AnthropicOutputConfig.effort` の Literal が `low` / `medium` / `high` / `xhigh` / `max` で `none` を含まず、スキーマ検証で先に 400 になる (本文は `Input should be 'low', 'medium', 'high', 'xhigh' or 'max'`)
- **値の実体は system への 1 文の指示である。** `xhigh` と `low` だけが文を足し、`medium` は何も足さない。長さや打ち切りを変える仕組みではない

#### 起動と判定 (Qwen 系)

**この小節は Qwen 系の起動の話である。** 他の系統から切り替えるときは、先に「系統の切り替え」の手順で配信中の系統を止める。

**`--launch` を使う。** Qwen レシピの引数なしの `./start.sh` は HuggingFace からのダウンロードと worker への rsync から始める。どちらも完了済みなので `--launch` が両方を飛ばす。**`--launch` でも head 側のシャード完全性の検査は必ず通り、欠落があればコンテナを作らずに止まる** (→「重みの検証」)。

**`./start.sh --launch` は `/health` が 200 を返すまで待ってから戻る** (成功すると `vLLM is ready and serving on port 8888!` を出し、コンテナが途中で落ちると `Container vllm-fn exited unexpectedly` を出して止まる)。約 13〜14 分かかるので、エージェントのシェル実行からは「長い処理を ssh から切り離す」の型で流す。

**Qwen 系の cold start は上流の計測で約 11 分である** (2026-09-05 時点の README: NCCL 約 40 秒、重みロード 458 秒、engine init 92 秒、graph capture 約 7 秒)。DeepSeek 系の約 7〜8 分より長い。20 分を過ぎても上がらなければ両ノードで `docker logs vllm-fn` を見る (worker は「worker に入る」節の入れ子 ssh)。

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
curl -s http://spark-head.local:8888/v1/models | python3 -c 'import json,sys; d={m["id"]:m.get("max_model_len") for m in json.load(sys.stdin)["data"]}; print(d); sys.exit(0 if d.get("qwen3.8-flash-next")==524288 else 1)'   # 2. 配信名と上限
curl -s http://spark-head.local:8888/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.8-flash-next","messages":[{"role":"user","content":"17*19 を計算して、答えの数値だけを出力してください。説明や単位は不要です。"}],"temperature":0,"reasoning_effort":"low","max_tokens":4096}' \
  | python3 -c 'import json,sys; c=json.load(sys.stdin)["choices"][0]["message"]["content"].strip(); print(repr(c)); sys.exit(0 if "323" in c else 1)'   # 3. 生成が通る
```

**3 段とも exit code で合否が出る。** 2 段目と 3 段目の判定の形は Qwen 配信中に流していない (2026-10-04 に書いた形)。3 段目は思考を `low` にして答えを短くし、本文に `323` が含まれることを見る。

2 段目と 3 段目に Bearer が要らないのは無認証だからである (どの系統でもヘッダは要らない → 「API キーの流れ」)。**Qwen レシピには DeepSeek 系の `smoke-…sh` に相当するスクリプトが無い**ので、3 段目は curl で生成を通して代用する。経路は OpenCode と同じ `/v1/chat/completions` である。クライアントを通して見るなら `opencode run "1+1 は?"` を打つ。curl の 3 段は LAN 側を見る (出先では Tailscale 側に読み替える)。

#### レシピを更新する (Qwen 系)

上流の更新を取り込む順路である。**`.env` は追跡外なので `git pull` では消えない。**

```bash
ssh spark-head
cd ~/Qwen3.8-Flash-Next-Dual-DGX-Sparks
git fetch -q && git log --oneline HEAD..origin/main    # 先行分を読む
OLD=$(git rev-parse --short HEAD); echo "戻し先: $OLD"  # 戻すときに使うので控える
git pull --ff-only
diff <(grep -E '^[A-Za-z0-9_]+=' .env.sample | sort) <(grep -E '^[A-Za-z0-9_]+=' .env | sort)
```

最後の `diff` は**上流にキーが増えていないか**を見るために打つ (出力に IP を含む行があるので証跡として貼らない)。増えていたら「Qwen3.8-Flash-Next」の表の「`.env` に**書いていない**上流キー」行を更新する。

**更新後は次の 4 点で悪化していないことを確かめる。** 起動の 3 段判定は起動の可否しか見ないので足りない。**2 と 3 を採ってから停止し、起動 (「系統の切り替え」の手順 2〜4) の後に 1〜4 を照合する。** 2 と 3 は停止した後では採れない。

1. 起動の 3 段判定 (`/health` → `/v1/models` → 実際の生成)
2. `/v1/models` の `id` と `max_model_len` が更新前と一致すること。**`created` と `permission` は起動のたびに変わるので全文比較に使わない** (常に不一致になり検出器として働かない)
3. reasoning effort の語彙が変わっていないこと (→「Qwen の reasoning effort の語彙」。**2 経路とも打つ**)
4. `docker inspect vllm-fn --format '{{.HostConfig.RestartPolicy.Name}}'` が `no` のままであること

**KV プールのトークン数は起動ごとに動くので不合格の根拠にしない** (→「起動と判定 (Qwen 系)」)。

戻すときは `git checkout <旧 sha>` してから停止 → 起動する (`<旧 sha>` は上のコードブロックが出した「戻し先」。detached HEAD になるので復帰は `git checkout main`)。重み・イメージ・`.env` のいずれも変わらないので戻せる。

#### 重みの検証

`0b62e12` のレシピは重みの検証手段を 3 つ持つ。**いずれも Qwen レシピ限定である** (他の 3 系統には無い。V4.1 EXL3 系の重みの確認は「依拠する外部事実」の「V4.1 EXL3 の重みがそろっているか」の行)。パスはレシピディレクトリからの相対で、実行も同ディレクトリで行う。

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

**新しい revision へ上げるかは別の判断である。** `fc694b54` の `config.json` は MTP の routed experts を `FP8_PB_WO` と名乗り、`hf_quant_config.json` 側の `FP8_BLOCK_SCALES` と食い違う。`0b62e12` の `start.sh` はこれを別名として受理するが、**当方の `fab0aecb` は両方とも `FP8_BLOCK_SCALES` なので、この修正は当環境では効いていない** (2026-09-09 実測)。**欠落を埋めるつもりで revision を指定せずに再取得すると `refs/main` が `fc694b54` へ動き、次の起動から配信 revision が黙って変わる。**

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

**このレシピは vLLM に `--api-key` を渡さないので、Qwen 配信中はポート 8888 が無認証になる。** `.env` にも `.env.sample` にも API キーのキーが無く (`grep -nE "API_KEY" .env` は 1 行も返さず exit 1)、`docker inspect vllm-fn` の実引数にも `--api-key` は無い。**Bearer 無しでも出まかせの Bearer でも `/v1/*` が通ることを実測で確認した。** DeepSeek 系も `VLLM_API_KEY` を空にしてあるので、いま切り替えても認証の有無は変わらない (→「API キーの流れ」)。sparkDash (ポート 5555) と同じく、ポート 8888 も信頼できないネットワークへ出さない。認証を付けたい場合は `.env` の `EXTRA_VLLM_ARGS="--api-key <値>"` で渡せる (未検証)。**その場合はクライアント側も直す。** サーバだけ直すと OpenCode は起動して最初の生成で失敗するため、「API キーの流れ」の番号付き手順 2〜5 を同じく適用する。

**無認証の OpenCode には 1Password は要らない。**

#### 使える API (Qwen 系)

**OpenCode が使う `/v1/chat/completions` は 2026-09-06 に opencode 1.18.18 で実測した。** `/v1/messages` も使える。このイメージは `vllm/entrypoints/generate/api_router.py` が `register_anthropic_api_router(app)` を無条件に呼ぶ。`/v1/responses` は未試行である (「依拠する外部事実」のコードブロック 6 のモデル名を配信名に差し替えて確認する)。

### DeepSeek-V4.1-Flash EXL3

**他の 3 系統とは別リポジトリ・別イメージ・別スクリプトである。** 2026-09-15 に導入し、起動の 3 段判定、OpenCode (opencode 1.18.18) からの生成、reasoning effort の語彙を確認した。2026-09-17 に `/v1/responses` の生成とツール呼び出しも確認した (head のパッチが前提 →「既知の制約」12)。V2 の OpenCode からは試していない。

**この構成には認証が無い** (根拠は「動いているもの」。認証を付けるときの置き場所は「API キーの流れ」の手順 1 で、この系統では未検証)。

値の出所はレシピの `.env` と、起動ログが出す `config:` 行である。ただし「レシピ」「量子化」「重み (本体)」「重み (Engram)」「pack」「既定の reasoning」「コンテナイメージ」「コンテナ名」「上流既定からの差分」の 9 行を除く (これらは HF API・`files/` 配下・`docker inspect`・`.env.example` との差分から取った)。

| 項目 | 値 |
| --- | --- |
| レシピ | head の `~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks` @ `b9c49e9` |
| 量子化 | EXL3 (→ 用語表) の平均 2.9 bpw。テンソルごとにビット数が違う (routed experts は 3 bit で層 18〜22 だけ 2 bit、shared experts は 5 bit / 4 bit、attention は 5 bit。レシピの `files/exl3_k_map.json`) |
| 重み (本体) | `Mia-AiLab/DeepSeek-V4.1-Flash-EXL3-2.9bpw` @ `64ba41b6c916a587db06eae2e19b7845f7be6e6b`。49 ファイル / safetensors 39 本 / 196.2 GiB。head はレシピ直下の `model/`、worker は `~/.cache/dsv41-flash-exl3/model/`。HF の org 表記は `Mia-AiLab` で、GitHub の `MiaAI-Lab` とは綴りが違う (どちらも実在する表記) |
| 重み (Engram) | `deepseek-ai/DeepSeek-V4.1-Flash` @ `dba1be0a40aa45a94ad051997016db3960a90277` の shard 47 / 48 (各 94.6 GiB) と `model.safetensors.index.json` と `config.json`。head はレシピ直下の `engram-src/`。この先の経路は下の「Engram の流れ」 |
| pack | head が rank 0 の 2 本、worker が rank 1 の 2 本を、それぞれ自分の Engram コピーから `~/dsv41-engram/` に作る (1 本 47.2 GiB、ファイル所有者は root)。コンテナに `/engram-packed` として mount される |
| API 上のモデル名 (`SERVED_MODEL_NAME`) | `DeepSeek-v4.1-Flash-EXL3` (大文字を含む) |
| コンテキスト上限 (`MAX_MODEL_LEN`) | サーバ 600,000 トークン |
| 同時リクエスト上限 (`MAX_NUM_SEQS`) | **2 リクエスト** (4 系統で最も少ない。超過分はキューで待つ) |
| 投機デコード (`SPEC_METHOD` / `DSPARK_TOKENS`) | DSpark (draft はチェックポイント内の `mtp.*`)、draft 3 トークン |
| KV キャッシュ | vLLM が `fp8_ds_mla` を自分で選ぶ (`--kv-cache-dtype` は渡さない)。プールは `KV_CACHE_MEMORY_BYTES` で 2.5 GiB に固定 |
| `GPU_MEM_UTIL` | 0.88。KV プールを固定しているので予算ではなく、vLLM が起動時に空きメモリと比べる検査値 |
| 画像入力 | **使える** (`LANGUAGE_MODEL_ONLY=0`、`LIMIT_MM={"image":100}`)。**`MAX_NUM_BATCHED_TOKENS` を 1536 以上にすることが必須**で、1024 のままだと重みロードの数分後に `compute_mm_encoder_budget` の `ValueError` で起動が止まる (画像 1 枚の 1,025 トークンが 1 チャンクに収まる必要があるため。上流 README)。それに合わせて `LONG_PREFILL_TOKEN_THRESHOLD` を 1280 にしてある (上流は「`MAX_NUM_BATCHED_TOKENS` との差を 256 以上空ける」と規定している)。2026-09-30 に、左半分が青・右半分が黄の 64x32 PNG を data URL で `/v1/chat/completions` に渡すと「左: 青、右: 黄色」と答え (prompt 239 トークン)、同じ質問を画像なしで送ると「左: 赤、右: 青」と外れる (prompt 35 トークン) ことを実測した。**GB10 では画像内の双方向 attention が無効になる** (レシピの `patch_sm120_block64.py` が sliding window を 128 に固定するため)。上流は OCR と複数画像の取り違えに影響を測れなかったとしているが、確かめたのは合否判定だけで、元のチェックポイントと品質を比べた検証は無い |
| 既定の reasoning | thinking ON。effort を送らないときの既定は `high` (レシピの `files/chat_template.jinja` の `reasoning_effort` の既定値) |
| コンテナイメージ | `ghcr.io/miaai-lab/deepseek-v4.1-flash-exl3-2x-dgx-sparks:2.9bpw` (Id `sha256:4cdba4e946da2d19bf5b5a20c6d3a1a4bf421fa4d6db5082f271a986168176cb`、展開後 22.5 GB (`docker images` の 10 進表示)、arm64、ラベル `dsv41.recipe.stamp` = `8c01a8543ff7e7b222ae1cd46b8be5051838dc7a7b075b4e647f3785c0429584`)。**両ノードに配置済み** |
| コンテナ名 | `dsv41-exl3-head` / `dsv41-exl3-worker`。restart policy は両方 `no` |
| 上流既定からの差分 | 手元の `.env.example` (`b9c49e9`) と比べて 7 キー。`WORKER_USER=skanehira` (上流は作者のユーザー名)、`WORKER_CX7_IF=enp1s0f1np1` / `WORKER_CX7_IB=rocep1s0f1` (上流の作者機は worker が `f0`。当方は両ノードとも `f1`)、`WEIGHT_SYNC=rsync` (上流既定は `nfs`)、画像入力のための `LANGUAGE_MODEL_ONLY=0` / `MAX_NUM_BATCHED_TOKENS=1536` / `LONG_PREFILL_TOKEN_THRESHOLD=1280`。後ろの 3 キーは手元の `.env.example` とは違う。上流 `8404ac7` の `.env.example` では 3 キーとも当方と同じ値だが、2026-10-04 時点の上流 `main` (`6f7d159`) では `LONG_PREFILL_TOKEN_THRESHOLD` がコメントアウトされている。これに `HF_HUB_ENABLE_HF_TRANSFER=0` を 1 行足してある (head に `hf_transfer` が無いため)。確かめ方は「依拠する外部事実」のコードブロック 4 |

**`WEIGHT_SYNC=rsync` にしている理由。** 上流既定の NFS では worker が head の export を RoCE (上流は CX7 = ConnectX-7 と呼ぶ) 越しに読み、head が配信中の単一障害点になる。pack した Engram はどちらの方式でもローカル NVMe から読まれるので、配信中の速度は変わらない見込みである。**上流は rsync を fallback 扱いにしている**ので、検証の厚みは NFS 経路より薄い。

**Engram の流れ。** head の `engram-src/` → `start.sh` が起動と pack のたびに作り直す slim dir (`~/.cache/vllm-dsv41-flash-exl3/engram-src/`。shard 2 本はハードリンク、`config.json` はコピー、index は Engram のキーだけに書き直す) → 3 か所で使う。(1) head の pack と head のコンテナ (`/engram-src`) が読む。(2) worker へはこの slim dir を rsync して `~/.cache/dsv41-flash-exl3/engram-src/` にする。(3) worker の pack と worker のコンテナがそのコピーを読む。rsync はシャードのサイズと mtime から作ったマーカー (`.dsv41-engram-synced`) が一致すると省略される。

#### 起動と判定 (V4.1 EXL3 系)

```bash
ssh spark-head
cd ~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks
./start.sh            # 起動 (GPU 自己検査 → 重みの同期確認 → 両ランク起動 → health 待ち → warmup)
./start.sh status     # 両ランクのコンテナ状態と health
./start.sh logs       # head のログを追う (worker は ./start.sh logs worker)
./start.sh stop       # 両ランク停止 (./stop.sh も同じ)。成否は「系統の切り替え」の手順 3 で確かめる
./start.sh pack       # Engram を pack し直す (重みを差し替えたときだけ)
```

- **重みが無いと `./start.sh` は自動でダウンロードを始める** (`AUTO_DOWNLOAD=1`)。revision は固定されない (→「導入手順 (V4.1 EXL3 系)」2)
- **GPU 自己検査**は、head で使い捨てコンテナを立てて EXL3 のカーネルと Engram の逆量子化を合成データで確かめる段である。結果は `logs/overlay-verify.log` に出て、不合格ならコンテナを作らずに止まる
- **起動に失敗してもコンテナは消えない。** `start.sh` は `logs/head.log` / `logs/worker.log` (head のログが 420 秒止まったときは `logs/hang-{head,worker}-pyspy.txt` も) を書いて止まる。コンテナがメモリを掴んだまま残るので、**原因を見たら `./start.sh stop` → 「系統の切り替え」の手順 3 の判定 → 起動し直す**。health 待ちは 1,500 秒で打ち切られる
- **前置で上書きできるキーは限られる。** `start.sh` は `DSPARK_TOKENS` / `SPEC_METHOD` / `MAX_MODEL_LEN` / `MAX_NUM_SEQS` / `MAX_NUM_BATCHED_TOKENS` / `GPU_MEM_UTIL` / `LANGUAGE_MODEL_ONLY` / `IMAGE` / `ENFORCE_EAGER` と EXL3 のカーネル設定だけを `.env` の読み込み前に退避して書き戻す。それ以外の `.env` のキー (`WEIGHT_SYNC` / `WORKER_*` / `KV_CACHE_MEMORY_BYTES` / `SERVED_MODEL_NAME` など) は前置しても `.env` の値が勝つので、`.env` を編集する。`.env` に無い `FORCE_SYNC=1` (worker への rsync を強制) / `SKIP_SYNC=1` (worker への同期を丸ごと省く) / `BUILD=1` (イメージをローカルでビルド) / `SKIP_BUILD=1` (stamp が違ってもビルドしない) / `SKIP_SHIP=1` (worker へイメージを送らない) は前置で効く

**エージェントのシェル実行から起動するときは、ssh を切り離してログを残す。** 起動全体は 8〜10 分かかり、1 回のコマンド実行の時間上限 (Claude Code の場合は Bash ツールの 600 秒) を越えうる。ssh ごと切れると warmup が走らないまま中断する。

```bash
ssh -n spark-head 'cd ~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks && setsid nohup ./start.sh > ~/dsv41-start.log 2>&1 < /dev/null & echo started'
# 終わるまで待つ (バックグラウンドで流す)。`^bash ./start.sh$` に固定しているので、この ssh のコマンド文字列には一致しない
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
| `MemAvailable` の推移 (head / worker) | 起動前 116.1 / 114.9 GiB → 重みロード後 16 / 16 GiB → health 通過時 6.0 / 7.2 GiB。画像入力を有効にした 2026-09-30 の起動では、`Model loading took` が 99.8 GiB (0.9 GiB 増)、起動ログ末尾の `memory` 行が 5.1 / 6.0 GiB だった |
| pack の所要 | 1 本 (47.2 GiB) あたり約 90 秒、両ノードで計 4 本。`FORCE_SYNC=1` を付けても、変わったファイルが `config.json` だけなら rsync は 1 分以内に終わった |
| 単一リクエストの decode | コード生成 400 トークン (thinking OFF、temperature 0) で約 36 tok/s、TTFT 0.60 秒。上流の散文での値は 31.6 tok/s |

**起動ログの `boot shape warmup incomplete` は致命的ではない。** warmup リクエストは 14/14 通っており、sampler のカーネル 1 通り (top-p だけの組み合わせ) が事前コンパイルされなかったという意味である。その組み合わせを初めて使うリクエストで 1 回だけ JIT の待ちが入りうる。

#### V4.1 EXL3 の reasoning effort の語彙

`/v1/messages` と `/v1/chat/completions` は 2026-09-15 に、`/v1/responses` は 2026-09-17 に全値を実測した。表のセルの 200 / 400 は HTTP ステータスである。確認コマンドは「依拠する外部事実」の reasoning effort の行と同じ形で、**モデル名を `DeepSeek-v4.1-Flash-EXL3` に、陽性対照の値を `high` から `medium` に差し替える** (V4.1 は `high` を受理するので、`high` では 400 にならない)。`/v1/responses` は「依拠する外部事実」のコードブロック 6 に `"reasoning":{"effort":"<値>"}` を足した形で打つ。

| 値 | `/v1/messages` | `/v1/chat/completions` (OpenCode) | `/v1/responses` |
| --- | --- | --- | --- |
| `low` / `high` / `xhigh` / `max` | 200 | 200 | 200 |
| `medium` | 400 | 400 | 400 |
| `none` | 400 (スキーマ) | 200 | 200 |
| 指定なし | 200 | 200 | 200 |

- **OpenCode は `opencode.json` で `max` を送る**
- **`medium` の 400 の本文は語彙を名乗る**: `DeepSeek V4.1 reasoning_effort must be low, high, xhigh, max, or an integer within [1, 100] in chat_template_kwargs`。弾く層は vLLM 側の検査で、Qwen 系のようなチャットテンプレートの `raise_exception` ではない。レシピの `files/chat_template.jinja` のコメントは `xhigh` を挙げていないが、実測で受理されるので実測に従う
- **`none` の非対称は Qwen 系と同じ構造である** (→「Qwen の reasoning effort の語彙」)。**弾くのは `/v1/messages` のスキーマだけ**で、`/v1/chat/completions` と `/v1/responses` は通す

#### 使える API (V4.1 EXL3 系)

| API | 用途 | 状態 |
| --- | --- | --- |
| `/v1/messages` | Anthropic Messages API | 使える (2026-09-15 に生成を確認) |
| `/v1/chat/completions` | OpenCode | 使える (2026-09-15、opencode 1.18.18。V2 では試していない) |
| `/v1/responses` | Responses API | head のパッチを当てれば使える (2026-09-17、生成とツール呼び出しを確認 →「既知の制約」12)。パッチが無いと `input_text` で 400 になる |

#### 導入手順 (V4.1 EXL3 系)

レシピを入れ直すときの順序と、各段の完了判定である。どれも head の上で打つ (7 は worker でも)。**配信中に進められるのは 1〜5 まで**で、6 からは 8888 が止まる。手順 2・3 の取得と 4 のコピーは「既知の制約」11 のメモリ上限付きで行い、上限を掛けられなければ手順 5・6 を先に行う。**`docker pull` / `docker load` は必ず手順 6 の停止確認後に流す。**

1. **clone と `.env`** — `git clone https://github.com/MiaAI-Lab/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks ~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks` → `cp .env.example .env` → 表の「上流既定からの差分」のキーと `HF_HUB_ENABLE_HF_TRANSFER=0` の 1 行を入れる。**入れるキーの数は clone した commit で変わる。** 必ず入れるのは `WORKER_USER` / `WORKER_CX7_IF` / `WORKER_CX7_IB` / `WEIGHT_SYNC` の 4 キーと 1 行である。画像入力の 3 キー (`LANGUAGE_MODEL_ONLY` / `MAX_NUM_BATCHED_TOKENS` / `LONG_PREFILL_TOKEN_THRESHOLD`) は、clone した `.env.example` の値が当方と違うものだけを足す。`b9c49e9` なら 3 キーとも、`8404ac7` なら 0 キー、2026-10-04 時点の `main` (`6f7d159`) なら `LONG_PREFILL_TOKEN_THRESHOLD=1280` の 1 キーを足す。**完了判定**: 「依拠する外部事実」のコードブロック 4 の出力が、入れたキーと `HF_HUB_ENABLE_HF_TRANSFER` に一致する (`b9c49e9` なら同ブロックのコメントにある 8 キー。上流がキーを足していれば、それも出るので「レシピを更新する (V4.1 EXL3 系)」と同じく扱う。`b9c49e9` 以外の clone で入れて確かめてはいない)。worker の RoCE アドレスを `W=$(grep -E "^WORKER_HOST=" ~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark/.env.dspark | cut -d= -f2)` で引き (手順 4 でも使う)、`ip route get "$W"` の経路が `dev enp1s0f1np1` を通り、両ノードの `/sys/class/infiniband/rocep1s0f1/ports/1/gid_attrs/types/3` が `RoCE v2` を返す
2. **本体の重み (約 7 時間)** — `mkdir -p model engram-src` (落とし穴 1) の後に取る。**`download.sh` と `start.sh` の自動取得は revision を固定しない**ので、固定するなら `hf download` を手で打つ。数時間かかるので「長い処理を ssh から切り離す」の型で流す。次のコマンドを head の `~/dsv41-dl.sh` に引用済み heredoc で保存し (`set -euo pipefail` を先頭に書く)、`<ディレクトリ>` はレシピのディレクトリ、`<名前>` は `dsv41-dl` とする。**この形は未実行である** (当方は `download.sh` で取り、取得時点の `main` が同じ revision だったことを照合で確かめた)

   ```bash
   HF_HUB_DISABLE_XET=1 HF_MAX_WORKERS=2 hf download Mia-AiLab/DeepSeek-V4.1-Flash-EXL3-2.9bpw --revision 64ba41b6c916a587db06eae2e19b7845f7be6e6b --local-dir model --max-workers 2
   ```

   進捗は `du -sb model` の差分で見る (8 MB/s 前後)。`HF_HUB_DISABLE_XET=1` は配信中のノードのメモリを守るためである (落とし穴 2)。この型はメモリの上限を掛けないので、配信中なら「既知の制約」11 の上限付きコンテナで取得し、使えなければ手順 5・6 を先に行って停止中に取得する。**完了判定**: ログの最後が `EXIT=0` で、「依拠する外部事実」の「V4.1 EXL3 の重みがそろっているか」が exit 0
3. **Engram** — 下のコードブロックで shard 2 本と index と `config.json` を取る (落とし穴 3・4)。**完了判定**: 同ブロック末尾の `sha256sum -c` が 2 本とも `OK`
4. **worker への事前コピー** (任意) — 8888 を止める時間を縮めたいときだけ。`W=$(grep -E "^WORKER_HOST=" ~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark/.env.dspark | cut -d= -f2) && rsync -a --partial model/ "$W":.cache/dsv41-flash-exl3/model/` を head のレシピのディレクトリで打つ (`W` は手順 1 と同じ値だが、エージェントのシェル実行では呼び出しをまたいで変数が残らないので、同じ呼び出しの中で引き直す。Engram は slim dir ができる 8 で `start.sh` が送る)。**完了判定**: worker 側で 2 の照合を `~/.cache/dsv41-flash-exl3/model` に向けて exit 0、rsync の出力に `denied` が 0 件
5. **止める準備** — 「系統の切り替え」の手順 1
6. **配信中の系統を止める** — 「系統の切り替え」の手順 2・3。両ノードの停止と空きメモリを確認してから次へ進む
7. **イメージ** — `docker pull ghcr.io/miaai-lab/deepseek-v4.1-flash-exl3-2x-dgx-sparks:2.9bpw` を停止確認後に両ノードで打つ。取り切れなければ下の「イメージを手で取る」 (落とし穴 5)。**完了判定**: 両ノードの `docker image inspect <イメージ> --format '{{index .Config.Labels "dsv41.recipe.stamp"}}'` が落とし穴 6 のコマンドの値と一致する
8. **pack** — 停止確認とイメージの照合後に `./start.sh pack` (worker への同期も同時に行う)。**完了判定**: head の `ls -la ~/dsv41-engram` に `engram-l{1,14}-r0of2.bin`、worker に `engram-l{1,14}-r1of2.bin` があり、各 47.2 GiB
9. **head のパッチ** — 「既知の制約」12 の手順で、上流の公式パッチ・実行ループ・mount が揃っているか確認する。揃っていればローカル差分を足さず、無い版だけ `~/dsv41-local/patch_responses_content_parts.py` と 2 行のローカル差分を用意する。**`/v1/responses` を使わないなら飛ばしてよい。OpenCode には要らない。** **完了判定**: 公式またはローカルのパッチ本体・実行・mount の 3 点が揃っていること。実行の合否は起動後のコードブロック 6 の HTTP 200 で確かめる
10. **起動と判定** — 上の「起動と判定 (V4.1 EXL3 系)」。**完了判定**: 3 段と `/engram-packed` の確認。`/v1/responses` を使うなら「依拠する外部事実」のコードブロック 6 が 200 を返すことも見る
11. **クライアント側と表示** — `opencode.json` のモデル宣言と effort を確認し、sparkDash の `workerLabel` を直す。OpenCode の設定は symlink なので `drs` は要らない

Engram の取得 (手順 3)。HF の resolve URL は Range 指定に 206 を返すので、`curl -C -` で途中から再開できる。サイズを先に見るのは、取り終えたファイルに `-C -` を打つと範囲外の要求になるため。**2 本で約 190 GiB あり 6 時間を超えるので、このブロックを head 上のファイル (例: `~/dsv41-engram-dl.sh`) に保存し、「長い処理を ssh から切り離す」の型で `bash ~/dsv41-engram-dl.sh` として流す。** 結果は末尾の `sha256sum -c` の 2 行 (`OK`) をログで読む。

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

イメージを手で取る (手順 7 で `docker pull` が取り切れないとき)。blob を 1 本ずつ再開可能に取り、`docker save` 形式にまとめて読み込む。2026-09-15 に使ったスクリプトを短くした形で、この形のままでは流していない。**約 25 分かかるので、Engram と同じくファイルに保存して「長い処理を ssh から切り離す」の型で流す** (手順 6 の停止確認後に流す。最後の `docker load` も両ノードの配信を止めた状態で打つ)。

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

#### 導入の落とし穴 (V4.1 EXL3 系)

上流 README の手順を素直に流すと、この環境では次の 6 か所で止まる。上の「導入手順 (V4.1 EXL3 系)」はこれを避ける順序になっている。

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

**未コミットの `start.sh` の 2 行は `git pull` / `git checkout` で自動的に消えない。** 差分が維持されるか、上流変更と重なると Git が拒否する。更新前に差分を head の clone 外へ退避し、追跡版を clean にしてから fast-forward で更新する。退避した差分は無条件に適用せず、更新先の公式パッチの本体・実行・mount を確認して判断する。

```bash
ssh spark-head
cd ~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks
set -euo pipefail
git fetch -q && git log --stat --oneline HEAD..origin/main   # 先行分と変わったファイルを読む
OLD=$(git rev-parse --short HEAD); echo "戻し先: $OLD"
# start.sh 以外の追跡差分やステージ済み差分があれば、消さずに更新を中断する。
git diff --quiet -- . ':(exclude)start.sh' || exit 1
git diff --cached --quiet || exit 1
umask 077
mkdir -p ~/dsv41-local
BACKUP=$(mktemp "$HOME/dsv41-local/start.sh.patch.XXXXXX")
git diff --binary HEAD -- start.sh > "$BACKUP"
# BACKUP は head 上で保持し、内容を外部出力・公開リポジトリへコピーしない。
# 差分が制約 12 の既知の 2 行だけであることを head 上で確認する。
# 他の差分が含まれる場合は中断し、既存変更を維持する。
if test -s "$BACKUP"; then git apply --check --reverse "$BACKUP"; fi
# 停止前に /v1/models の配信名・上限と reasoning effort の語彙を控える。
# 稼働中リクエストを確認し、「系統の切り替え」の手順 1〜3 で停止する。
# 停止確認後、退避が確認できた start.sh だけを追跡版へ戻す。
git restore --source=HEAD --worktree -- start.sh
git diff --quiet -- start.sh || exit 1
git pull --ff-only
# 公式パッチ本体と start.sh の呼出・配布・mount を確認する (制約 12)。
if test -f overlay/patch_responses_content_types.py; then
  grep -n -e RESPONSES_PATCH_HOST -e patch_responses_content_types.py start.sh
else
  echo "official-patch-absent: 制約 12 のローカル版を用意する"
fi
```

- **公式パッチが揃っていれば 2 行を足さない。** 2026-10-04 に head の保存済み `origin/main` (fetch はしていない) で、`overlay/patch_responses_content_types.py` と、両ランクのパッチループ・worker への scp・両コンテナへの mount を確認した。更新先でもこれらを確認する。公式が無い版だけ「既知の制約」12 のローカル版と 2 行を用意する。退避ファイルは戻す先を判断する材料として保持し、公式がある版へ丸ごと `git apply` しない
- **`Dockerfile` / `overlay/` / `files/` / `tests/` が変わっていたら**、落とし穴 6 のコマンドの値とイメージのラベルがずれる。停止を確認してから公開イメージを両ノードで pull し直し、値が一致することを確かめてから起動する
- **`.env.example` にキーが増えていないか**を「依拠する外部事実」のコードブロック 4 で見る。増えていたら「DeepSeek-V4.1-Flash EXL3」の表の「上流既定からの差分」の行と、コードブロック 4 のコメントにある期待するキーの一覧を更新する。`.env` は追跡外なので `git pull` では消えない
- **更新後の悪化確認**は Qwen 系と同じ 4 点 (→「レシピを更新する (Qwen 系)」の 1〜4) を、V4.1 EXL3 系のコマンドと語彙に読み替えて行い、5 点目として「依拠する外部事実」のコードブロック 6 (`input_text` が 200) を打つ。コンテナ名は `dsv41-exl3-head`、語彙の確認は「V4.1 EXL3 の reasoning effort の語彙」
- **戻すとき**も、稼働中リクエストを確認して停止し、追跡差分があれば上と同じく退避・確認してから clean にする。その後、控えた commit へ `git checkout <旧 sha>` する (`b9c49e9` に戻す場合は公式パッチが無い)。checkout 先の公式パッチ・実行・mount を確認し、無い場合のみ既知のローカル 2 行を再適用してから起動する。`git checkout` が差分を消す前提にしない

### GLM-5.3-Flash EXL3

**他の 3 系統とは推論エンジンから違う。** vLLM ではなく TensorFold ([ashhart/TensorFold](https://github.com/ashhart/TensorFold) v0.6.0 に、レシピが 70 本のパッチを当てたもの) で配信する。レシピの v1.5 (`1576746`) で 2026-10-04 に確かめたのは次のとおりである。起動、生成、OpenCode (opencode 2.0.22、V2) からのツール呼び出し、`/v1/chat/completions` と `/v1/responses` の reasoning effort の語彙、`/v1/messages` が 404 を返すこと、`/v1/models` が `max_model_len` を返さないこと。**OpenCode からの利用を確認済みである** (→ 下の「使える API (GLM 系)」)。

**この構成には認証が無い。** レシピに API キーの設定項目が無く (`scripts/config.sh` と `start.sh` に `API_KEY` の文字列が無い)、ヘッダ無しの `/v1/models` が 200 を返す (2026-10-04 実測)。

値の出所はレシピの `scripts/config.sh` の既定値と起動ログである。「重み (本体)」「重み (ドラフタ)」「戻す用に残している重み」「コンテナイメージ」の 4 行は HF API と `docker image inspect` で確かめた。

| 項目 | 値 |
| --- | --- |
| レシピ | head の `~/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold` @ `1576746` (上流の v1.5、2026-10-03 リリース) |
| 推論エンジン | TensorFold v0.6.0 (イメージ内の `tensorfold --version` が `0.6.0`) + レシピの `patches/*.patch` 70 本。パッチはイメージに焼き込み済み |
| 量子化 | routed experts が EXL3 (→ 用語表) の 4 bpw。それ以外の BF16 の重みは起動時に 4 bit へ量子化する (`DENSE=q4`) |
| 重み (本体) | `Mia-AiLab/GLM-5.3-Flash-EXL3-4bpw-TensorFold` @ `078455ffe6472f9a52fbc1139f58b9db2881b25c` (`scripts/config.sh` がこの `MODEL_ID` に対してだけ `MODEL_REVISION` を固定する)。snapshot は 97 ファイル (うち safetensors 83 本) / 175.7 GB (163.6 GiB)。ライセンスは MIT (HF のモデルカード。イメージのラベルにある Apache-2.0 はレシピ側のライセンス)。両ノードの `~/.cache/huggingface/hub/` に置く。**HF の `main` は pin より先へ進んでいる** (2026-10-04 時点で `76c0b517…`)。`MODEL_REVISION` が動かない限り何もしない |
| 重み (ドラフタ) | `incoai/GLM-5.3-Flash-DFlash2` @ `bf582e4eacc1810f76656d1811693ff6c6737d2a` (`DFLASH2_REVISION`)、2.2 GiB。**本体とは別リポジトリなので、取得も配布も別に要る。** ライセンスは CC BY-NC-ND 4.0 (非商用) |
| 戻す用に残している重み | `Mia-AiLab/GLM-5.3-Flash-EXL3-TR3-4bpw` @ `9eaebb7c4e96d983dcd538e18624622ba5b820a8` (164 GiB、両ノード)。レシピ v1.2 が使っていたチェックポイントで、**HF から消えている** (API が 401 を返す。2026-10-03 確認)。消すと取り直せない (→「レシピを更新する (GLM 系)」の「戻すとき」) |
| API 上のモデル名 (`SERVED_NAME`) | `GLM-5.3-Flash-EXL3` (大文字を含む) |
| コンテキスト上限 (`CONTEXT`) | 1 リクエスト 1,048,576 トークン (チェックポイントのネイティブ値)。**`/v1/models` は `max_model_len` を返さない**ので、`/health` の `context_length` で見る (→「使える API (GLM 系)」)。`opencode.json` の `limit.context` は 500,000 で、サーバの約半分である (→「OpenCode」の `limit.context` の項) |
| 同時リクエスト上限 (`PARALLEL`) | 4 リクエスト。v1.5 から 8 まで指定できるが、2 台での既定は 4 のままである。4 本は 1 つの KV プールを共有し、プールの大きさは起動ごとに変わる (→ 下の「KV プールの大きさは起動時の空きで決まる」)。プールに入りきらないリクエストはエラーにならず待つ |
| 投機デコード | DFlash2 (別モデルのドラフタ) と copy drafts。`DRAFT_POLICY=fnc7:0.3`、`COPY_MAX=15`。チェックポイントの MTP ヘッドは読まない |
| KV キャッシュ (`KV`) | `fp8` |
| メモリの予算 | 起動時の `MemAvailable` から `MEMORY_RESERVE_GIB` を引いた量。予備は `PARALLEL=4` では 14.5 GiB である。5 本以上にすると 1 本ごとに約 0.95 GiB 増え、同時に検証窓 (`TF_GLM_MULTI_WINDOW`) が既定で 32 行から 64 行に広がるので、32 行を超えた分の約 1.28 GiB も乗る (5 本目の増分は計約 2.23 GiB)。このとき RoCE で送る all-gather の上限 (`TF_ROCE_MAX_KB`) も 512 KiB から 1024 KiB に上がる。KV プールの上積みは `KV_POOL_GIB` (12.5 GiB) まで。**vLLM の確保率に当たるキーは無い** |
| 画像・動画入力 | 使える (`VISION=1`。設定上の上限は 1 リクエストに画像 50 枚、動画 4 本)。画像 1 枚は 2026-10-04 に緑一色の 8x8 PNG で実測済み (画像ありは「緑」、同じ質問で画像なしは「赤色」 →「依拠する外部事実」のコードブロック 10)。**動画入力と画像・動画の枚数上限は未実測** |
| ツール呼び出し / reasoning | 使える。thinking は既定で ON (`THINKING=1`)。思考は `reasoning_content` に返る。上流の CHANGELOG によれば、v1.4 から前のターンの思考もプロンプトに残す (`TF_GLM_CLEAR_THINKING=1` で残さない描き方に戻る) |
| ノード間通信 | 512 KiB までの all-gather は RoCE の one-shot RDMA write (`COMM=roce`) で送り、それより大きいものは NCCL で送る。**RoCE は 2 本とも使う** (→ 下の「RoCE は 2 本とも使う」) |
| コンテナイメージ | `tensorfold-glm53:v0.6.0` (展開後 24.6 GB、Id `sha256:e97db95dd4b3f9a5ebd6ddeafb8d7d422dda729cc01b33d7f5c6ecfcf9cf2aaf`)。中身は `ghcr.io/miaai-lab/glm-5.3-flash-exl3-2x-dgx-sparks-tensorfold@sha256:ef83797d791fef96c4605e8d37367aca6de5aeac7bb672792cb682e2e55d4237` (`scripts/config.sh` の `IMAGE_DIGEST`、タグは `IMAGE_TAG` の `v0.6.0-9f73cca659a1`) で、ラベル `tf.patches` は `9f73cca659a1`。両ノードに配置済み。v1.2 のイメージ `tensorfold-glm53:v0.5.0` (ラベル `cb7c56f7f921`) も戻す用に両ノードに残してある |
| コンテナ名 | `glm53-flash-tf` (**head と worker で同名**)。restart policy は `no` |
| 上流既定からの差分 | `scripts/local.sh` の 1 行 `WORKER=skanehira@<worker の RoCE アドレス>` だけ (値は `.env.dspark` の `WORKER_HOST` と同じ)。WORKER がリンク上のアドレスなので `FABRIC_PEER` は要らない。`.env` は置いていない |
| CUDA 拡張のキャッシュ | 両ノードの `~/.cache/tensorfold-glm53/` (約 250 MiB)。ビルド結果はイメージのパッチのハッシュごとのディレクトリ (`9f73cca659a1/`、123 MiB) に分かれる。新しいイメージの初回の起動でビルドされ、以降は再利用される。最上位の `torch_extensions/` と `triton/` (計約 128 MiB、root 所有) はハッシュごとに分ける前の配置の残りで、現行のイメージは読まない (消し方は「残骸の片付け」) |
| サーバのログ | `stop.sh` が両ランクのログを gzip で保存してからコンテナを消す。置き場は各ノードの `~/.cache/tensorfold-glm53/logs/<日付>-<時刻>-rank<N>.log.gz` (head に rank 0、worker に rank 1) で、新しいものから 10 本を残す。start.sh も、前回の停止済みコンテナを消す前に同じように保存する |

#### 起動と判定 (GLM 系)

```bash
ssh spark-head
cd ~/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold
./start.sh                      # 両ランクの起動。準備が要れば scripts/prepare.sh を自動で流し、スモークテストまで行う
./start.sh restart              # 設定を変えた後の再起動 (下の注意を読む)
./stop.sh                       # 両ランクの停止 (ログを保存してからコンテナを消す)
docker logs -f glm53-flash-tf   # rank 0 のログ。rank 1 は worker で同じものを打つ
```

- **エージェントのシェル実行から打つときはログインシェルを通す。** `ssh -n spark-head 'bash -lc "cd ~/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold && setsid nohup ./start.sh > ~/glm53-tf-start.log 2>&1 < /dev/null &"'` の形で起動し、ログを読む。`hf` は `~/.local/bin` にあり、非ログインシェルの PATH には入っていない。`hf` が見えないと、prepare.sh は重みの取得をコンテナの中の python に回す。**この ssh は start.sh が終わるまで戻らないことがある** (2026-10-04 に 7 分戻らなかった) ので、バックグラウンドで打つ。終わりは `until ! ssh -n spark-head 'pgrep -f "^bash ./start.sh$" >/dev/null'; do sleep 30; done` で待ち (パターンを `^…$` で固定しているので待ちの ssh 自身には一致しない)、`tail -25 ~/glm53-tf-start.log` に `is now LIVE!` があれば成功、`ERROR` があれば失敗である
- **状態表示のサブコマンドは無い。** 状態は `docker ps` と `/health` で見る
- **`./start.sh restart` は prepare.sh を流してから止める。** 引数なしの `./start.sh` は、両ランクが動いていれば prepare.sh の前に `already running` と出して exit 0 する。準備が要る状態 (pin を動かした `git pull` の後など) で `restart` を打つと、配信中に prepare.sh の取得 (WiFi と dockerd) が走る
- **メモリの事前検査は警告だけで止まらない。** 両ノードの `MemAvailable` が 110 GiB 未満だと警告を出して進む。予算が足りなければ rank 0 が窓を拒否し、start.sh は収まる窓で 1 回だけ起動し直す。そのときログに `this start's memory budget holds a N-token window` が出るので、これが出たら合格扱いにしない
- **ポートの事前検査は止まる。** 8888 が使用中なら `port 8888 is already in use` で終了する
- **準備済みかどうかは start.sh が判定する。** 状態を `~/.local/state/glm53-tensorfold/prepared` に記録し、イメージ・重みの revision・パッチ・worker のどれかが変わっていれば prepare.sh を流す。`PREPARE=0` で飛ばせる

**起動できたかは 3 段で判定する。** どれも exit code で合否が出る。start.sh 自身もスモークテストを流すので、ログの `GLM-5.3-Flash-EXL3 is now LIVE!` も合格の条件に入れる。

```bash
curl -fs -o /dev/null http://spark-head.local:8888/health && echo health-ok   # 1. API が生きている
curl -s http://spark-head.local:8888/v1/models | python3 -c 'import json,sys; ids=[m["id"] for m in json.load(sys.stdin)["data"]]; print(ids); sys.exit(0 if "GLM-5.3-Flash-EXL3" in ids else 1)'   # 2a. 配信名
curl -s http://spark-head.local:8888/health | python3 -c 'import json,sys; c=json.load(sys.stdin)["context_length"]; print(c); sys.exit(0 if c==1048576 else 1)'   # 2b. 文脈長 (/v1/models は返さない)
curl -s http://spark-head.local:8888/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"GLM-5.3-Flash-EXL3","messages":[{"role":"user","content":"17*19 を計算して、答えの数値だけを出力してください。説明や単位は不要です。"}],"temperature":0,"max_tokens":2048,"chat_template_kwargs":{"enable_thinking":false}}' \
  | python3 -c 'import json,sys; c=json.load(sys.stdin)["choices"][0]["message"]["content"].strip(); print(repr(c)); sys.exit(0 if c=="323" else 1)'   # 3. 生成が通る
```

**起動の実測値 (2026-10-04、v1.5 の新しいイメージでの初回の起動)。** CUDA 拡張のビルドを含む。prepare.sh はイメージも重みも取り直さず、照合だけで終わった。初回の起動は 1 回で通った。後ろ 3 行は、検証の生成を 20 件ほどと OpenCode の 1 往復を流した後の値である。

| 項目 | 値 |
| --- | --- |
| 起動全体 (start.sh の開始から LIVE まで) | 約 7 分 (`Server answered after 422s`、サーバ側は `loaded in 417.9s`) |
| KV プール | 1,562,624 トークン (1 リクエストは最大 1,048,576) |
| GPU の確保 (head / worker) | 93,318 / 92,240 MiB |
| `MemAvailable` (head / worker) | 14.3 / 12.8 GiB |
| swap 使用 (head / worker) | 1.6 / 3.5 GiB |

#### KV プールの大きさは起動時の空きで決まる

**プールは起動のたびに変わる。** 各ランクは起動時に「予算」(その時点の `MemAvailable` − 14.5 GiB) と、重みと 1 リクエスト分の窓に要る「見積り」をログに出す。プールに回るのはその差 (上限 12.5 GiB) である。

| 起動 | rank 0 の予算 / 見積り | rank 1 の予算 / 見積り | プール |
| --- | --- | --- | --- |
| 2026-10-01 (レシピ v1.2) | 100.53 / 88.09 GiB | 98.53 / 86.29 GiB | 2,883,584 トークン |
| 2026-10-04 (レシピ v1.5) | 98.26 / 88.09 GiB | 92.37 / 86.29 GiB | 1,562,624 トークン |

2026-10-04 の起動では、worker の空きが起動時に 108 GiB しかなかった (start.sh が 110 GiB 未満の警告を出した)。そのため rank 1 の差は 6.1 GiB にとどまった。**プールは差の小さいランクに合わせて決まると見ている。** 根拠は上の 2 回の起動ログだけで、ソースでは確かめていない。プールが小さくても 1 リクエストの上限 1,048,576 は変わらないが、長い会話を同時に抱えられる量が減る。プールを上限近くまで戻したいときは、両ノードの空きが大きいとき (この推定では head 115 GiB・worker 113 GiB 以上) に起動し直す。

#### RoCE は 2 本とも使う

**起動ログの `Link:` 行は `RoCE rocep1s0f1,roceP2p1s0f1 / rocep1s0f1,roceP2p1s0f1` と出る** (2026-10-04)。レシピの `scripts/nodes.sh` の `rails()` は、リンクと同じサブネットにある port に加えて、名前の末尾 (`f1np1`) が同じ PCIe の双子を拾う。当方の 2 本目は別サブネットにあるが、この規則で足される。

**アドレスは変えない。** 2 本を同じサブネットに置くと、vLLM の 3 系統が `no usable RoCEv2 GID` で起動しなくなる (→「ネットワーク」)。上流は 2 本使うと prompt chunk の all-gather が約 1.8 倍速いと書いている。当方では prefill の速さを 1 本のときと比べていない。

#### GLM の reasoning effort の語彙

**検査はサーバが行い、深さはサーバの読み替えとテンプレートで決まる。** 表のセルの 200 / 400 は HTTP ステータスである。 サーバ (TensorFold の `server/request_options.py`) は 7 語を受理し、それ以外を 400 で弾く。受理した値はサーバの `coerce_effort` がテンプレートの語に読み替える。テンプレート (チェックポイントの `chat_template.jinja`) は `low` と `high` 以外をすべて `max` として描く。

| 値 | `/v1/chat/completions` (OpenCode の経路) | `/v1/responses` | 実際に効く深さ |
| --- | --- | --- | --- |
| `low` / `minimal` | 200 | 200 | `low` (`minimal` はサーバが `low` に読み替える) |
| `medium` / `high` | 200 | 200 | `high` (`medium` はサーバが `high` に読み替える) |
| `xhigh` / `max` | 200 | 200 | `max` (`xhigh` はテンプレートが `max` として描く) |
| `none` | 200 | 200 | thinking なし |
| 指定なし | — | — | `max` |
| 語彙外 (`bogus` など) | 400 | 400 | — |

- **400 の本文は受理語彙を名乗る**: `reasoning_effort must be none, minimal, low, medium, high, xhigh or max`。弾いているのは TensorFold のサーバで、vLLM のスキーマ検証ではない
- **「実際に効く深さ」の列はソースとテンプレートから読んだものである。** 応答の思考の量では確かめていない。テンプレートは新旧 2 つのチェックポイントでバイト一致する
- **`none` の扱いが vLLM 版と違う。** TensorFold は `none` を thinking の無効化として扱う
- **OpenCode は `opencode.json` で `max` を明示する。** テンプレート既定が変わっても推論が浅くならないようにしている
- 2026-10-04 に 8 値すべてを両経路で実測した。陽性対照は `bogus` (400)、陰性対照は `max` (200)

#### 使える API (GLM 系)

| API | 用途 | 状態 (2026-10-04) |
| --- | --- | --- |
| `/v1/chat/completions` | OpenCode | 使える。opencode 2.0.22 (V2) の `opencode run --standalone` で、ファイルを読ませる指示が Bash (`ls`) → Read のツール呼び出しを経て正答した |
| `/v1/responses` | Responses API | 使える。effort の 7 語がすべて 200 で通る |
| `/v1/messages` | Anthropic Messages API | **無い (404)** |
| `/health` | `stop.sh` と手動の状態確認 | `busy` / `requests_running` / `streams` / `pool_tokens` / `pool_free_tokens` / `context_length` などを返す |
| `/metrics` | — | `tensorfold:` と `tensorfold_health:` の系列だけを出す。**`vllm:` の系列は無い** |

**TensorFold の `/v1/models` は `id` / `object` / `owned_by` の 3 キーしか返さず、`max_model_len` は無い** (2026-10-04)。コンテキスト上限は `/health` の `context_length` で確認する。OpenCode は `opencode.json` の静的値を使う。

**この系統のサーバは配信していないモデル名で要求しても応答を返す** (2026-10-04 再確認)。クライアントが古いモデル名を送り続けても `model not found` にならず、GLM がそのまま答えるので気づきにくい。`/v1/models` の `owned_by` は `tensorfold` である (OpenCode 組み込みの vLLM 自動発見を使わない理由 →「OpenCode」)。

**手元の sparkDash (`cc44d35`) は GLM 配信中に LLM のメトリクスを表示できない。** `vllm:` の系列しか読まないためである。上流の `main` には TensorFold の `/health` を読む変更が入っている。

#### 導入手順 (GLM 系)

初回の導入と、イメージや重みの pin が動く更新とで同じ手順を使う。2026-10-04 にレシピ v1.2 から v1.5 への更新で踏んだ順序と、各段の完了判定である。**既存イメージで上限付きの取得ができる場合、8888 を止めずに進められるのは 1〜4 まで**で、5 からは配信が止まる。手元にイメージが無い初回は手順 5 の停止確認を先に行ってから取得する。**dockerd を通る `docker pull` / `docker load` と prepare.sh の取得は、配信を止めてから流す** (dockerd の側にはメモリの上限が掛からないため)。例外は手順 2 の `docker run --memory 2g` で、取得はコンテナの中で上限付きで走る (→「既知の制約」11)。コマンドはすべて head のレシピのディレクトリで打つ。

1. **レシピを用意する** — 初回は `git clone https://github.com/MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold ~/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold` のあと、`scripts/local.sh` に `WORKER=skanehira@<worker の RoCE アドレス>` の 1 行を書く。更新は「レシピを更新する (GLM 系)」の `git pull --ff-only`。**完了判定**: `bash -c 'source scripts/config.sh >/dev/null 2>&1; echo "$MODEL_ID@$MODEL_REVISION $IMAGE $IMAGE_TAG"; image_hash'` を打ち、`image_hash` が `IMAGE_TAG` の末尾と一致すること。一致していれば prepare.sh は pin した digest のイメージを使う
2. **本体の重みを head だけで取る (配信中、約 6 時間)** — `utility-spark-model-fetch` スキルの手順 1・2 に従う。head のホスト側 python には `huggingface_hub` が無いので、手元にある `tensorfold-glm53` のイメージの python で取る。`<イメージ>` は `docker images` に出る `tensorfold-glm53:*` のどれでもよい (更新のときは旧版。2026-10-04 は `v0.5.0` を使った)。`<MODEL_ID>` と `<MODEL_REVISION>` は手順 1 の完了判定の出力 (`<MODEL_ID>@<MODEL_REVISION>`) から取る。ssh を切っても止まらないように dockerd の管理するコンテナで流す (`systemd-run --user --scope` は使わない。ユーザーの linger が無効 (`Linger=no`) なので、最後のセッションが閉じると user manager ごと scope が止まりうる。systemd の仕様からの推定で、実際に止まるかは確かめていない)

   ```bash
   docker rm glm53-dl 2>/dev/null   # 前回のコンテナが残っていると同じ名前で作れない
   docker run -d --name glm53-dl --memory 2g --user 1000:1000 --network host \
     -v ~/.cache/huggingface:/hf -e HF_HOME=/hf -e HOME=/tmp -e HF_HUB_DISABLE_XET=1 \
     --entrypoint python <イメージ> -c \
     'from huggingface_hub import snapshot_download; print(snapshot_download("<MODEL_ID>", revision="<MODEL_REVISION>", max_workers=2))'
   docker wait glm53-dl              # 終わるまで戻らない。終了コードを出す (0 で成功)
   docker logs glm53-dl 2>&1 | tail -1   # snapshot のパスが出る
   docker rm glm53-dl
   ```

   - `docker wait` は数時間戻らないので、エージェントのシェル実行からは待たずに、`docker inspect -f '{{.State.Running}} {{.State.ExitCode}}' glm53-dl` を一定間隔で打って `false` になるのを待つ
   - 速度は約 8 MB/s で、進捗は `du -sb` の差分で見る
   - 途中で止めて (`docker stop glm53-dl`) 同じコマンドで再開すると、完了した blob は再利用される。**取得途中の blob は続きからではなく、新しい `.incomplete` を作って最初から取り直す** (2026-10-03 実測)。古い `.incomplete` は 3 のスキル手順 6 で消える
   - **手元に `tensorfold-glm53` のイメージが 1 つも無い初回は、この形が使えない。** 代わりにログインシェルの `hf` で取る。「長い処理を ssh から切り離す」の型で、`HF_HUB_DISABLE_XET=1 HF_MAX_WORKERS=2 hf download <MODEL_ID> --revision <MODEL_REVISION> --cache-dir ~/.cache/huggingface/hub` を head の `~/glm53-dl.sh` に引用済み heredoc で保存し (`set -euo pipefail` を先頭に書く)、`<名前>` を `glm53-dl` にする。メモリの上限は掛からないので、この形は手順 5 の停止確認後に流す。**この形は未実行である**
   - **完了判定**: 終了コードが 0 で、`verify_shards.py` が「必要 N / 揃い N / 欠落 0」で exit 0 を返すこと (N は index に載る shard 数。v1.5 の本体では 83)。`verify_shards.py` はスキル同梱のものを Mac から head の `/tmp/vs.py` へ scp して `python3 /tmp/vs.py models--<org>--<name>` で打つ (スキルの手順 5)。手順 3 の worker 検証の前に、head から worker の `/tmp/vs.py` へも scp する。初回と各ノードの再起動後は `/tmp` が空になるので、検証前に両ノードへ配り直す。`find <モデルのディレクトリ> -user root` が 0 件であること。**index が届く前の `verify_shards.py` は手元にある shard だけを必要分と数えるので、取得途中では欠落を検出できない**
3. **worker へ rsync する (配信中、約 8 分)** — スキルの手順 3〜6 に従う (所有権の確認、`rsync -a --delete --info=progress2 --no-inc-recursive`、ログの `denied` が 0、両ノードの `verify_shards.py` の一致、`.incomplete` の削除と再検証)。`-L` は付けない。付けると snapshot の symlink が実体になり、worker が重みを二重に持つ。**完了判定**: 加えて、prepare.sh と同じ照合が一致すること。照合は snapshot で `find -L . -type f -printf '%P %s\n' | LC_ALL=C sort` を両ノードで取って `cmp` する (v1.5 の本体で 97 行)。一致していれば prepare.sh は `Worker has …` と出してコピーを飛ばす
4. **ドラフタ** — `DFLASH2_REVISION` が動いていなければ何もしない。動いたら DFlash2 でも 2〜3 を行う (`<MODEL_ID>` を `DFLASH2_ID`、`<MODEL_REVISION>` を `DFLASH2_REVISION` の値にする。どちらも `bash -c 'source scripts/config.sh >/dev/null 2>&1; echo "$DFLASH2_ID@$DFLASH2_REVISION"'` で出る)
5. **配信中の系統を止める** — 「系統の切り替え」の手順 1〜3。GLM 系の配信中なら `/health` の `requests_running` が 0 であることを見てから `./stop.sh`
6. **イメージを head に取り、worker へ送る (約 25 分)** — head は GHCR から WiFi で取り、worker へは RoCE で送る。prepare.sh に任せると worker も WiFi で取る。**Mac からの ssh 1 本で前景で流すと、出力の無い転送中に Mac 側の ssh がタイムアウトする** (2026-10-04。head 上の転送はそのまま完走した)。次の引用済み heredoc で head の `~/glm53-image.sh` に保存し、「長い処理を ssh から切り離す」の型で `<ディレクトリ>` をレシピのディレクトリ、`<名前>` を `glm53-image` にして流す (`bash ~/glm53-image.sh` を実行する形)。`IMAGE` などはスクリプト内で `source` した後に展開される

   ```bash
   ssh spark-head 'cat > ~/glm53-image.sh' <<'SCRIPT'
   set -euo pipefail
   cd ~/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold
   source scripts/config.sh >/dev/null 2>&1
   docker pull "$GHCR_IMAGE@$IMAGE_DIGEST"
   docker tag "$GHCR_IMAGE@$IMAGE_DIGEST" "$IMAGE"
   docker save "$IMAGE" | ssh -o BatchMode=yes "$WORKER" docker load
   SCRIPT
   ```

   **完了判定**: ログの最後が `EXIT=0` で、両ノードの `docker image inspect -f '{{.Id}} {{index .Config.Labels "tf.patches"}}' tensorfold-glm53:v0.6.0` (タグは `scripts/config.sh` の `$IMAGE`) が同じ Id を返し、ラベルが 1 の `image_hash` と一致すること
7. **起動** — 「起動と判定 (GLM 系)」の形で `./start.sh` を打つ。prepare.sh が流れ、照合だけで終わる (ログに `already built with patches` / `identical on both Sparks` / `Worker has` が出る)。新しいイメージの初回は CUDA 拡張のビルドが入るので約 7 分かかる。**失敗したら** head のログを先に読む。worker 側の `RDMA write to rank 0 failed: transport retry counter exceeded` は、rank 0 が落ちた後の二次症状である
8. **判定** — 「起動と判定 (GLM 系)」の 3 段と、「GLM の reasoning effort の語彙」の陽性対照・陰性対照を両経路で流し、すべて期待どおりであること
9. **クライアント側と表示** — `opencode.json` の宣言はそのまま効く。sparkDash の `workerLabel` が配信名と違えば「sparkDash の `workerLabel` を直す」で直す

#### 導入の落とし穴 (GLM 系)

1. **`hf` が非ログインシェルの PATH に無い。** `ssh -n spark-head '…'` で直接 prepare.sh や start.sh を打つと、重みの取得が `hf` ではなくコンテナ内の python に回る。必ず `bash -lc` を通す
2. **`./start.sh restart` で更新を始めない。** prepare.sh が配信を止める前に走り、配信中に WiFi と dockerd を使う (→「起動と判定 (GLM 系)」)
3. **`scripts/local.sh` は無視されていない。** レシピは `.gitignore` を持たないので、`git status` に `?? scripts/local.sh` と出る。追跡ファイルではないので `git pull` は通る
4. **ドラフタの revision を上げると重みが変わる。** `dc77ff1c` から `bf582e4e` では `model.safetensors` の sha256 が変わっていた。pin が動いたら HF の tree API でファイルの差を見てから取る

#### レシピを更新する (GLM 系)

```bash
ssh spark-head
cd ~/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold
git fetch -q && git log --oneline HEAD..origin/main   # 先行分を読む
git diff HEAD..origin/main -- CHANGELOG.md scripts/config.sh   # イメージと重みの pin が動くかを見る
git pull --ff-only
```

- **`scripts/config.sh` の `IMAGE_TAG` / `IMAGE_DIGEST` / `MODEL_ID` / `MODEL_REVISION` / `DFLASH2_REVISION` が動いたら、「導入手順 (GLM 系)」の 2〜8 を流す。** pull しただけでは配信に影響しない。引数なしの `./start.sh` も、配信中なら何もせずに終わる
- **HF 側の `main` が pin より先へ進んでいても何もしない。** レシピが revision を固定しているので、`MODEL_REVISION` が動くまで配信には効かない
- **`patches/` だけが変わって新しいイメージが公開されていない場合、prepare.sh はイメージをローカルでビルドする。** 公開済みかは CHANGELOG.md の「Image」の行で見る
- **更新後の悪化確認**は「導入手順 (GLM 系)」の 8 で行う
- **戻すとき**は `./stop.sh` → `git checkout 1f3d909` → `./start.sh` と打つ。`1f3d909` は v1.2 で、TR3 の重みと `tensorfold-glm53:v0.5.0` を使う。どちらも両ノードに残してあるので、取り直しは起きない。TR3 は HF から消えているが、v1.2 の prepare.sh は取得に失敗しても手元の snapshot で続行する (ソースから読んだ挙動で、実行しては確かめていない)。**TR3 か v0.5.0 を消すと v1.2 へは戻せない。** 消してよいかは、v1.5 で困ることが無いと判断してから決める

## モデルの追加と切り替え

**同じレシピの中でモデルを 1 つ足すときは、サーバ設定・OpenCode の宣言・sparkDash の表示の 3 か所を整え、次の 5 段で進める。** 別系統のレシピを足す場合は、clone・設定・イメージ取得も要る。V4.1 EXL3 系は Engram の取得と pack、GLM 系は別リポジトリのドラフタの取得が要る (→ 各系統の導入手順)。

1. **重みを両ノードに配る** — HF キャッシュへ置くモデルは `utility-spark-model-fetch` スキルを使う
2. **サーバの設定を合わせる** — 対応するレシピのチェックポイント・revision・配信名を設定する。DeepSeek 系は `.env.dspark` の `DSPARK_MODEL_OFFICIAL` / `DSPARK_REVISION` / `SERVED_MODEL_NAME`、Qwen 系は `.env` の `MODEL_ID` / `SERVED_MODEL_NAME` (revision の選択は「重みの検証」)、V4.1 EXL3 系はモデル・Engram の固定 revision と `.env` の `SERVED_MODEL_NAME`、GLM 系は `scripts/config.sh` が解決する `MODEL_ID` / `MODEL_REVISION` / `SERVED_NAME` (ドラフタが変わるなら `DFLASH2_ID` / `DFLASH2_REVISION` も) を確認する。既存レシピが別モデルを受けるかは、そのレシピの起動前検査と設定で確認する
3. **`agents/bindings/opencode/opencode.json` の `provider.spark.models` に宣言を足す** — `options.reasoningEffort` / `limit` / `tool_call` を書く (値は「OpenCode」)。受理される effort は各系統の API で確かめ、他モデルの値を流用しない。`spark-served.ts` は宣言済みのモデルからしか選ばない。配信中モデルが宣言に無ければプラグインは何もしない (→「OpenCode」の例外 (c))。設定は symlink なので `drs` は要らない
4. **配信中の系統を止め、目的のモデルを起動して確認する** — 「系統の切り替え」の手順 1〜4。サーバの `/v1/models` の配信名、上限、実際の生成を確認する。GLM 系の上限は `/health` の `context_length` で見る
5. **sparkDash の `workerLabel` を直す** — 配信を切り替えたら表示を更新する (→「sparkDash の `workerLabel` を直す」)

**HF キャッシュに置く形の新しい open-weight を入れるときは `utility-spark-model-fetch` スキルを使う。** V4.1 EXL3 系はこの対象外で、レシピ直下に実ファイルで取り、worker へのコピーは `start.sh` の rsync が作る (→「導入手順 (V4.1 EXL3 系)」)。素直にレシピ同梱の `prepare-dspark-model-cache.sh` を使うと worker でも HuggingFace から再ダウンロードして同じ重みを 2 回落とすことになる。head で 1 回落として RoCE 経由で rsync すれば転送は 5〜8 分で済む。所有権の修正・シャードの検証・監視コマンドの落とし穴はスキル側に書いてある。

### 系統の切り替え

**系統を切り替えるときは、配信中の系統を止めてから目的の系統を起動する。** 停止と起動のコマンドは系統ごとに違う。どれも head の上で打つ。

| 系統 | 停止 | 起動 | 起動の判定 | `workerLabel` に入れる値 |
| --- | --- | --- | --- | --- |
| DeepSeek 系 (Vision-Exp 版) | `cd ~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark && ./stop-deepseek-v4-flash-dspark.sh` | `cd ~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark && ./start-deepseek-v4-flash-dspark.sh` | 「DeepSeek 系 (Vision-Exp / 0731)」の 2 段 | `deepseek-v4-flash-vision-exp` |
| DeepSeek 系 (0731 版) | `cd ~/dspark-0731 && ./stop-deepseek-v4-flash-dspark.sh` | `cd ~/dspark-0731 && ./start-deepseek-v4-flash-dspark.sh` | 同上 (smoke は `~/dspark-0731` 側を打つ) | `deepseek-v4-flash-0731` |
| Qwen 系 | `cd ~/Qwen3.8-Flash-Next-Dual-DGX-Sparks && ./stop.sh` | `cd ~/Qwen3.8-Flash-Next-Dual-DGX-Sparks && ./start.sh --launch` | 「起動と判定 (Qwen 系)」の 3 段 | `qwen3.8-flash-next` |
| V4.1 EXL3 系 | `cd ~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks && ./start.sh stop` (同じディレクトリの `./stop.sh` も同じ動作) | `cd ~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks && ./start.sh` (エージェントのシェル実行から打つ形は「起動と判定 (V4.1 EXL3 系)」) | 「起動と判定 (V4.1 EXL3 系)」の 3 段 | `DeepSeek-v4.1-Flash-EXL3` |
| GLM 系 | `cd ~/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold && ./stop.sh` | `cd ~/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold && ./start.sh` (エージェントのシェル実行から打つときは `bash -lc` を通す →「起動と判定 (GLM 系)」) | 「起動と判定 (GLM 系)」の 3 段 | `GLM-5.3-Flash-EXL3` |

手順は次の 5 段である。

1. **稼働中のリクエストを確かめる** — `curl -s http://spark-head.local:8888/metrics | grep -E '^vllm:num_requests_(running|waiting)\{'` が両方 0。GLM 系の配信中は `vllm:` の系列が無いので、`curl -s http://spark-head.local:8888/health` の `requests_running` が 0 であることを見る。
2. **配信中の系統を止める** — 表の「停止」
3. **止まったことを確かめる** — **停止コマンドの exit code は成否を表さない** (V4.1 EXL3 系の `stop` は worker への ssh が失敗しても「stopped.」と出して exit 0 で終わる)。両ノードで次が 0 行であることを見る (worker は「worker に入る」節の入れ子 ssh で同じものを打つ)

   ```bash
   docker ps --format '{{.Names}}' | grep -E 'vllm|dsv41|glm53'
   ```

   V4.1 EXL3 系を起動するなら、加えて両ノードの空きメモリが 111.5 GiB 以上であること。`awk '/MemAvailable/{g=$2/1048576; printf "%.1f GiB\n", g; exit !(g>=111.5)}' /proc/meminfo` が exit 0 なら合格である (`/proc/meminfo` は kB で出るので GiB に直して比べる)。GLM 系なら同じ式の閾値を 110 にする (GLM レシピの `start.sh` が警告を出す境目。下回っても止まらず、窓を縮めて起動し直す)
4. **目的の系統を起動して判定する** — 表の「起動」と「起動の判定」
5. **sparkDash の `workerLabel` を表の値に直す** — 次の小節。OpenCode は開いたままの TUI もプラグインの再取得で切り替え先のモデルへ移る

**OpenCode が送る effort は、DeepSeek 系が `high`、Qwen 系が `xhigh`、V4.1 EXL3 系と GLM 系が `max` である。** `/v1/chat/completions` は 4 系統ともこの値で 200 を実測済みである (→ 各系統の reasoning effort の語彙)。

**先に相手系統を停止する。** ポート 8888 を共有するうえ、起動側の事前検査が拒否する。Qwen 系は `REQUIRE_IDLE_GPU=true` がどちらかのノードで GPU を掴むプロセスを見つけた時点で止まる。V4.1 EXL3 系は、**どちらか一方のノードでも** `MemAvailable` が 111.5 GiB に届かなければ止まる (閾値は、レシピの `scripts/weight_budget.py` が safetensors の index から見積もる 1 ランク分の重み 99.5 GiB に、余裕 `DSV41_BOOT_MARGIN_GIB` の既定 12 GiB を足した値。見積りが取れないと警告だけ出して検査を飛ばす)。GLM 系のメモリ検査は警告だけで止まらない。代わりに 8888 が使用中なら `port 8888 is already in use` で止まる。**停止コマンドを取り違えると相手系統のコンテナは消えないので、「止めたつもり」で次の起動が拒否される。**

### sparkDash の `workerLabel` を直す

配信モデルを切り替えたら必ず打つ。**実機を見ずに表示するだけの手書き文字列なので、直さないと worker 行が古いモデル名のままになる。** ファイルは root 所有なのでコンテナ経由で書く。`~/sparkDash/config` は `/app/config` に bind mount されているので、編集はコンテナを作り直しても残る。

**ファイルを書き換えただけでは画面は変わらない。** sparkDash のサーバは `sparks.json` を起動時に読んでメモリに持つので (`~/sparkDash/server/sparks/SparkRegistry.js`)、書き換えた後に `docker restart sparkDash` で読み直させる。確認はファイルではなく API の応答で行う (2026-09-15 確認)。

下のコマンドの `DeepSeek-v4.1-Flash-EXL3` を、配信中の `SERVED_MODEL_NAME` に差し替えて使う。

```bash
ssh -n spark-head "docker exec sparkDash node -e \"const f='/app/config/sparks.json',fs=require('fs');const j=JSON.parse(fs.readFileSync(f));j.sparks.find(s=>s.role==='worker').workerLabel='DeepSeek-v4.1-Flash-EXL3';fs.writeFileSync(f,JSON.stringify(j,null,2))\""
ssh -n spark-head 'docker restart sparkDash'
ssh -n spark-head 'curl -s http://127.0.0.1:5555/api/sparks' | python3 -c 'import json,sys; d=json.load(sys.stdin); d=d.get("sparks",d) if isinstance(d,dict) else d; w=[s["workerLabel"] for s in d if s.get("role")=="worker"]; print(w); sys.exit(0 if w==["DeepSeek-v4.1-Flash-EXL3"] else 1)'   # exit 0 で合格。期待値も書き込んだ値に差し替える
```

OpenCode の設定変更は要らない。**OpenCode はプラグインが 30 秒ごとに引き直すので、開いたままの TUI も追従する。** 偽の `/v1/models` サーバで配信モデルを差し替えた実測 (2026-10-03) では 40 秒以内に切り替わり、それまでの 26 秒間は前のモデルのままだった (その間に送ったリクエストは前のモデル名で飛ぶはずだが、確かめていない)。

## Mac から使う

Spark のクライアントは OpenCode である。素の `opencode` を打つと Tailscale 側 (`http://spark-head:8888/v1`) に繋がり、プラグイン `spark-served.ts` が起動時と 30 秒ごとに `/v1/models` から配信中のモデルを選ぶ。コンテキスト上限は `opencode.json` の静的値を使う (→「OpenCode」)。

**本書の手順と実測は Mac のものである。Mac 以外の端末からの利用は未検証である。** OpenCode の本体と設定は通常の Linux と Android にも配られる (`nix/modules/home/packages.nix` / `packages-android.nix` と `opencode.nix`)。他の端末では `hms` による適用、その端末の Tailscale へのサインインと MagicDNS 名 `spark-head` の名前解決が要る。Linux と Android の Tailscale は dotfiles 管理外である。

### 新しいマシンで手で用意するもの

Nix (`drs`) では入らないものが 5 つある。

| もの | 用途 | 作り方 |
| --- | --- | --- |
| `~/.ssh/config` と鍵 2 本 | ssh エイリアス | 「接続する」節 |
| `known_hosts` の 3 エントリ | エージェントの非対話 ssh | 「接続する」節の `ssh-keyscan` (人が実行) |
| Tailscale へのサインイン | **OpenCode は自宅でも出先でも要る** (接続先が Tailscale 側に固定のため)。cask はアプリを置くだけで tailnet 参加は手作業 | アプリを開いてログイン。**`tailscale status` に `spark-head` の行が出れば合格**。cask だけで `tailscale` コマンドが入るかは確かめていない (この Mac の `/usr/local/bin/tailscale` はアプリ本体を `exec` する 2 行のシェルスクリプト)。コマンドが無ければ Tailscale アプリのメニューから CLI を導入するか、`/Applications/Tailscale.app/Contents/MacOS/Tailscale status` を打つ |
| 1Password へのサインイン | `ccds` のトークン取得。**無認証のいまは Spark 向け (OpenCode と下の `/tmp/spark.key`) には要らない**。認証を戻した後は Spark のキーの取得にも要る | `op signin` |
| `/tmp/spark.key` (head のみ) | `bench.py` を打つときだけ。無認証の現在も文字列自体は要る (中身は何でもよい) | 「API キーの流れ」節 |

`opencode` のバイナリ (`nix/pkgs/opencode.nix`) と設定 (`opencode.json` / `cli.json` / `spark-served.ts` の symlink) は Nix 経由で `drs` / `hms` が置く。Tailscale 本体は Mac の `nix/modules/darwin/homebrew.nix` の cask `tailscale-app` で入る。

### OpenCode

```bash
opencode                                   # 対話 TUI をカレントディレクトリで起動 (配信中のモデルをプラグインが選ぶ)
opencode run "README を要約して"            # headless で 1 回実行 (モデルの選び方は TUI と同じ)
opencode run --model spark/<配信名> "..."   # モデルを明示する (形式は provider/model#variant)
opencode --continue                        # 直前のセッションを続ける
opencode service status                    # 常駐サービスの状態 (stop / restart もある)
opencode --standalone                      # 常駐サービスを使わず、この起動専用のサーバで動く
```

**ラッパーは無い。素の `opencode` を打てば本クラスタに繋がる。** 本体は V2 (2.0.22) で、`nix/pkgs/opencode.nix` が npm 配布のビルド済みバイナリを展開して入れる (nixpkgs の `opencode` は V1 の 1.18 系なので使わない)。Spark 向けの設定は dotfiles の `agents/bindings/opencode/` にあり、`nix/modules/home/opencode.nix` が `~/.config/opencode/` へ配る。`~/.config/opencode/` には opencode 自身が書くファイルが同居するので、ディレクトリごとではなくファイル単位で配る。

| ファイル | 配り方 | 中身 |
| --- | --- | --- |
| `opencode.json` | symlink (live edit) | `provider.spark` (接続先・モデル宣言・モデルごとの `reasoningEffort` と `limit`)、`enabled_providers`、`permission`、`default_agent`、`autoupdate` |
| `plugins/spark-served.ts` | symlink (live edit) | 配信中のモデルの選択 |
| `cli.json` | symlink (TUI で設定を変えると切れる) | keybinds / theme |

押さえるべき点が 11 個ある。

- **接続先は Tailscale の MagicDNS 名 `http://spark-head:8888/v1` に固定してある。** 自宅 LAN の mDNS 名 (`spark-head.local`) は使わない。したがって OpenCode を使うマシンは自宅でも Tailscale にサインインしている必要がある。2026-10-03 に Tailscale 経由で `/health` が 200 を返し、生成が通ることを実測した。Tailscale 側の名前解決に mDNS 名と同種の遅延 (到達できない IPv6 を先に試す) が出るかは計測していない
- **接続先の URL は 2 か所にある。** `opencode.json` の `provider.spark.options.baseURL` と、プラグインの `BASE_URL` である。プラグインの setup が走る時点では設定の provider がまだ組み立てられておらず、`baseURL` を読めないため。**接続先を変えるときは 2 か所とも変える。** 一致は `spark-served_test.ts` が検査する。このテストは `deno test --allow-env --allow-run --allow-read --allow-write agents/` に含まれ、CI では回していないので、変えたら自分で流す
- **配信中のモデルはプラグイン `spark-served.ts` が選ぶ。** 起動時と 30 秒ごとに `<BASE_URL>/models` を引き、`opencode.json` に宣言したモデルのうち配信中のものだけを有効にして既定モデルに据える。配信していないモデルは無効になり、TUI の選択肢から消える。**起動前に止める配信前検査は無い。** 例外が 3 つある (`spark-served.ts` のソースから読んだ挙動)。(a) 常駐サービスの起動時にサーバに届かなければ全モデルが有効のまま動き、届くようになれば次の再取得 (30 秒以内) で絞り込む。(b) 稼働中に届かなくなったら直前の状態を保つ。401 などの失敗応答も届かないのと同じに扱う。(c) 宣言済みのモデルが 1 つも配信されていなければ何もしない。起動時なら全モデルが有効のまま、稼働中にそうなった場合に全モデル有効へ戻るかは V2 がモデル一覧を読み直すときの挙動次第で、確かめていない。起動時の 1 回だけでなく再取得するのは、常駐サービスが複数の起動をまたいで生き続けるためである
  - 実測 (2026-10-03): 「最近使ったモデル」に配信外の DeepSeek を入れた状態の TUI で、プラグインありは配信中の GLM を選び、プラグインを外した対照は DeepSeek を選んだ。偽の `/v1/models` サーバで配信モデルを DeepSeek → Qwen に替えると、開いたままの TUI が 40 秒以内に Qwen へ切り替わった (切り替え前の 26 秒間は DeepSeek のまま)。`opencode run` (`--model` 無し) でも GLM が選ばれた
- **選ばれたモデルは TUI の入力欄の下の表示 (`Plan · <モデル名>`) か `opencode run` の出力で確かめる。** **プラグインが効いているかは、宣言済みで配信していないモデルが選択肢から消えていることで判定する。** TUI の表示だけでは判定にならない。V2 はプラグインが無くても宣言順の先頭か「最近使ったモデル」を既定に採り、`opencode.json` の宣言順の先頭は `GLM-5.3-Flash-EXL3` なので、GLM 配信中はプラグインが無くても `Plan · GLM-5.3-Flash-EXL3` と表示されうる。選択肢は `opencode models` で一覧できる。2026-10-03 に 3 回打ち、3 回とも宣言 5 本のうち配信中の `spark/GLM-5.3-Flash-EXL3` の 1 行だけを返して exit 0 だった。これがプラグインの絞り込みを反映した結果だという点は、プラグインを外した対照を取っていないので未確認である。**常駐サービスの起動直後は空を返しうる**ので、配信名の 1 行が出るまで 2 秒間隔で最大 10 回打ち直し、10 回で出なければプラグインか配布の失敗として扱う。プラグインはログを出さない。宣言済みのモデルが配信中なのに 30 秒を過ぎても配信外のモデルが残るなら、`readlink -f ~/.config/opencode/plugins/spark-served.ts` が dotfiles 配下を返すかを見てから `opencode service restart` で読み込み直す
- **表示の `Plan` は `opencode.json` の `default_agent: "plan"` による。** 起動直後のエージェントを組み込みの `plan` にする設定で、`plan` はファイルを変更せず、実装を頼まれるとエージェントの切り替えを求める (v2.0.22 のバイナリ内のプロンプトから読んだもので、実行しては確かめていない)。編集を伴う作業は `build` エージェントへ切り替えて行う。V2 の既定キーバインドでは `shift+tab` (`agent.cycle`) が次のエージェントへ、`<leader>a` (`agent.list`) が一覧を開く (同じくバイナリ内の既定値表から読んだもの。確かめるなら TUI のコマンドパレットで `Agent cycle` を探す)
- **OpenCode 組み込みの vLLM 自動発見 (`opencode.provider.vllm`) は使っていない。** `/v1/models` の `owned_by` が `vllm` のモデルしか拾わず、provider ID も `vllm` に固定だからである (v2.0.22 のソースで確認)。GLM 系のサーバは `owned_by` に `tensorfold` を返す (2026-10-03 実測)
- **素の `opencode` は常駐サービスに繋ぐ。** TUI 自身はサーバを持たず、常駐の `opencode serve --service` (detached な子プロセスで、launchd などには登録しない) を起動して接続する。待ち受けは全インターフェースの 49374 番である (2026-10-04 に `lsof -nP -iTCP:49374 -sTCP:LISTEN` が `*:49374` を返した)。`~/.config/opencode/service.json` の `hostname` を、`nix/modules/home/opencode.nix` の activation `opencodeServiceConfig` が `drs` / `hms` のたびに `0.0.0.0` へ上書きするためで、外からの接続を防ぐのは同じファイルの `password` だけになる。TUI を閉じてもサービスは残る。操作は `opencode service status|stop|restart` で、`--standalone` を付けるとその起動専用のサーバで動く。次の 3 点は v2.0.22 のソースで確認したもので、実行しては確かめていない
  - サービスは最初に起動した TUI の環境変数を持ったまま生き続けるので、**後から起動した `opencode` に前置した環境変数は設定に効かない。** 接続先やモデルを環境変数で差し替える運用はできない
  - 設定ファイルとプラグインの変更はサービスが監視していて自動で読み直す。`opencode.json` と `spark-served.ts` の編集に再起動は要らない。編集が表示に反映されないときは `opencode service restart` で読み込み直す
  - OpenCode の版が変わると、TUI が古いサービスを置き換える
- **`opencode.json` は opencode 1.18 系の書式で書いてある。** V2 は読み込み時にメモリ上で V2 の書式へ直し、ファイルには書き戻さない (v2.0.22 のソースで確認)。Spark のために要る点は次の 5 つである
  - `enabled_providers: ["spark"]` — 無いと OpenCode Zen の無料モデルが選択肢に混ざり、既定に選ばれうる (2026-10-03 に、起動直後の一瞬だけ `Build · Fledge Alpha Free (OpenCode Zen)` が表示されたのを見ている)
  - 各モデルに `reasoning: true` を書かない — V2 には対応するフィールドが無く、警告ログ (`omitted unsupported legacy setting`) を出して捨てる (2026-10-03 実測)
  - `models` の宣言 (`reasoningEffort` / `limit` / `tool_call`) は要る。**配信しうるモデルを増やしたらここに足す** (足さないとプラグインが選べない →「モデルの追加と切り替え」3)。値の決め方は `limit.context` = `/v1/models` の `max_model_len` (TensorFold は返さないので、GLM 系は `/health` の `context_length`)、`limit.output` = 65536、`tool_call` は `true`、`options.reasoningEffort` はそのモデルで受理を確認済みの採用値である (現在は `qwen3.8-flash-next` = `xhigh` / `deepseek-v4-flash-vision-exp` = `high` / `deepseek-v4-flash-0731` = `high` / `DeepSeek-v4.1-Flash-EXL3` = `max` / `GLM-5.3-Flash-EXL3` = `max`)。`reasoningEffort` を省くと OpenCode は effort を送らず、テンプレート既定 (Qwen なら `xhigh`) が効く。明示してあるのは、既定が変わったときに黙って浅くならないようにするためである
  - **`limit.context` は人が書く静的値なので、サーバ側の `MAX_MODEL_LEN` を変えると取り残される** (`workerLabel` と同型の乖離経路)。**この乖離は現に起きている** — `deepseek-v4-flash-vision-exp` と `deepseek-v4-flash-0731` は 524,288 で、DeepSeek 系のサーバ上限 1,048,576 (「サービングの構成 (DeepSeek 系)」「0731 版で配信する」) の半分である。`GLM-5.3-Flash-EXL3` も 500,000 で、サーバの 1,048,576 の約半分である。Qwen (524,288) と V4.1 EXL3 (600,000) はサーバと一致している。害は早めに圧縮が走ることだけなので放置してもよいが、直すなら当該エントリを 1048576 にする
  - `autoupdate: false` — 本体は Nix 管理で store は書き換えられないため。V2 もグローバルの `opencode.json` を直接読んで更新を止める (v2.0.22 のソースで確認)。`provider.spark.npm` (`@ai-sdk/openai-compatible`) は V2 同梱の実装で解決され、実行時の npm install は起きない (同じくソースで確認)。初回起動に npm レジストリへの到達性は要らない
- **`cli.json` は TUI で設定を変えると symlink が切れる。** 起動しただけでは V2 は書き換えない (2026-10-03 に、V2 書式の `cli.json` を symlink で置いて TUI を 2 回起動し、symlink のままで中身も変わらないことを実測)。一方、旧い名前のキーバインドが入っていると起動時に書き換え、テーマなどを TUI で変えたときも書き換える。書き換えは一時ファイルを書いて rename で置き換えるので、symlink が実ファイルに化けて repo との同期が黙って切れる (旧い名前のキーバインドの場合は 2026-10-03 に実測、テーマ変更の場合は v2.0.22 のソースで確認)。**設定は repo 側を編集して変え、TUI では変えない。** 実ファイルが残る原因はもう 1 つある。`cli.json` を symlink で配る前の dotfiles を適用したマシンでは、activation が初回だけコピーした実ファイルがそのまま残っている。どちらの場合も、消す前に `diff ~/.config/opencode/cli.json agents/bindings/opencode/cli.json` (dotfiles で実行) で差を見て、残したい変更は repo 側へ取り込む。そのうえで実ファイルを消して `drs` / `hms` で張り直す。消さずに `drs` を打つと mac は `cli.json.hm-backup` へ退避して symlink を張るが、`cli.json.hm-backup` が既にあると `would be clobbered by backing up` で止まる (Linux の `hms` は退避の設定が無いので、実ファイルがあるだけで止まる → `CLAUDE.md`「配布方式の移行」)。**`drs` を打つ前に `test -e ~/.config/opencode/cli.json.hm-backup` で古い退避が無いかを見る** (2026-10-04 時点のこの Mac には無い)。あれば、`diff ~/.config/opencode/cli.json.hm-backup agents/bindings/opencode/cli.json` (dotfiles で実行) が何も出さないことを確かめてから消す。wezterm の Cmd+p は alt+p を送り、`cli.json` の `command.palette.show` (`alt+p,super+p`) に当たる
- **CLI のうち Spark の操作に関わる点。** トップレベルの `--model` は無い。`run` と `mini` にはあり、形式は `run` が `provider/model#variant`、`mini` が `provider/model` (`#variant` を取らない)。`run --dir` は無く、カレントディレクトリで動く (2026-10-03 に `opencode run --help` / `opencode mini --help` で確認)
- **live edit が効いているかは `readlink -f` で判定する** (→「依拠する外部事実」)。**単 hop の `readlink` では判らない。** `mkOutOfStoreSymlink` は複数段の symlink を作り (2026-10-03 の実測で 3 段)、1 段目は live でも `/nix/store/…-home-manager-files/…` を指すためである。`opencode.json` と `plugins/spark-served.ts` が dotfiles 配下に解決すれば、編集は常駐サービスの読み直しで次のリクエストから効く (読み直しはソースでの確認)

## 実測値

数値は条件が変わると簡単に 25% 動くので、表ごとに条件を書いてある。**閾値だけを覚えて条件を変えて測ると誤診する。**

**この節の値はすべて GPU クロック制限 (2,200 MHz) が有効な状態で採ってある。X925 の `scaling_max_freq` を下げたのは 2026-09-10 なので、それより前の日付の表はその前の値である** (前後で単一ストリームの所要時間に差が出ないことは確かめてあるが、この節の並列条件では取り直していない → 「既知の制約」4・5)。

### L1: サーバ単体 (2026-09-05)

`~/spark-bench/bench.py` でサーバを直叩きした値である。条件はプロンプト 6,000 トークン、`max_tokens` 256、`chat_template_kwargs={"thinking": true, "reasoning_effort": "low"}` (サーバ既定の `DEFAULT_THINKING=low` と同じ)、指示は「上記は無視して、TypeScript の関数を 1 つ書いてください。説明は不要でコードだけ返してください。」`c` は `--concurrency`。中央値と (最小〜最大)。

**`chat_template_kwargs` は `--extra-body` でしか渡せない。** `bench.py` はこのキーの既定を持たないので、下の再現コマンドから `--extra-body` を落とすと条件が変わる (思考が既定のまま走る)。**これはテンプレートに直接渡す第 4 の経路である。** 各 API の `reasoning_effort` (Chat Completions) / `output_config.effort` (Messages) / `reasoning.effort` (Responses) と違い、スキーマの Literal 検査を通らずにテンプレートへ届く。`bench.py` は `min_tokens` を `max_tokens` と同値にし `ignore_eos` を立てるので、生成長は常に 256 トークン固定である。

| 条件 | n | Vision-Exp |
| --- | --- | --- |
| c=1・decode (tok/s) | 5 | 40.77 (34.88〜62.80) |
| c=1・TTFT (秒) | 5 | 3.47 (3.20〜3.93) |
| c=4・decode (tok/s) | 8 (4 並列 × 2 回) | 21.95 (14.44〜34.88) |
| c=4・TTFT (秒) | 8 (4 並列 × 2 回) | 9.44 (4.93〜13.47) |

**判定 (Vision-Exp 版): c=1 の decode 中央値が 35 tok/s を下回る、または c=4 の TTFT 中央値が 15 秒を超えたら異常を疑う。** 0731 版の閾値は採っていないので、0731 配信中は下の「decode の分解 (2026-09-23)」の表と比べる。個別値ではなく中央値で見る (正常時でも最小値は 34.88 tok/s まで落ちる)。再現は次の 2 本で、結果は `~/spark-bench/results/<ラベル>-<日時>.json` に残る。

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

### decode の分解 (2026-09-23)

**decode tok/s は「1 ステップで確定するトークン数 ÷ 1 ステップの時間」で決まる。** DeepSeek 系で、1 ステップの時間は内容にも文脈長にもほぼ依らない。速度の差はほとんどが 1 ステップのトークン数、つまり投機デコードの受理率から来る。

**測り方。** 各リクエストの前後で `/metrics` を読み、`vllm:spec_decode_num_drafts_total` の増分を decode ステップ数として使う。1 ステップの時間 = (最終トークン時刻 − 初回トークン時刻) ÷ ステップ数、1 ステップのトークン数 = `vllm:generation_tokens_total` の増分 ÷ ステップ数である。**他のリクエストが重なるとステップ数に相手の分が混ざって分解が壊れる。** そこで 16 秒続けて無負荷になってから 1 本ずつ投げ、`generation_tokens_total` の増分が自分の `completion_tokens` と一致した回だけを採る (2026-09-23 は両チェックポイントとも 21 回中 21 回が一致)。スクリプトは使い捨てで、リポジトリには置いていない。

各条件 3 回の中央値。プロンプトはどれも末尾に指示を 1 つ付けたもので、フィラーは `bench.py` と同じ繰り返し文である。

| 条件 | Vision-Exp tok/s | Vision-Exp tok/step | Vision-Exp step (ms) | 0731 tok/s | 0731 tok/step | 0731 step (ms) |
| --- | --- | --- | --- | --- | --- | --- |
| 数の列挙、thinking off | 81.0 | 5.71 | 69.8 | 90.5 | 5.94 | 65.5 |
| コード、thinking off、短文 | 70.0 | 5.05 | 71.7 | 80.2 | 5.50 | 68.5 |
| コード、32K 文脈 | 66.6 | 4.86 | 72.9 | 80.0 | 5.56 | 69.4 |
| コード、100K 文脈 | 64.4 | 4.99 | 75.4 | 75.9 | 5.44 | 71.6 |
| 6K フィラー + コード指示、thinking `low`、256 トークン強制 (L1 と同条件) | 42.4 | 3.05 | 71.6 | 44.4 | 2.84 | 64.7 |
| 同じ入力で自然終了 | 44.8 | 3.17 | 70.5 | 46.1 | 2.98 | 64.4 |
| 日本語の散文、thinking off | 26.8 | 1.77 | 65.9 | 33.8 | 2.12 | 62.4 |

- **1 ステップの時間は短文から 100K まで +5% しか伸びない。** 長い文脈が decode を遅くしているわけではない
- **日本語の散文は受理率が低い** (Vision-Exp 0.13 / 0731 0.22)。上流が測った英語の散文は Vision-Exp で 0.25 前後である。ドラフタが日本語を苦手にしている可能性があるが、プロンプト 1 つからの推測である
- **1 ステップ約 70 ms は 2 台 TP=2 の固定費である。** 投機の全トークンが受理されても上限はおよそ 100 tok/s (Vision-Exp の k=6 で 7 トークン ÷ 70 ms)

**実負荷の単一ストリーム区間も同じ形に分解できる。** Vision-Exp 配信中に、他のリクエストが重ならなかった区間だけを外から 124 秒ぶん観測した値は、42.6 tok/s = 3.30 トークン ÷ 77 ms だった。位置別の受理率は 0.80 / 0.56 / 0.39 / 0.27 / 0.17 / 0.105 である。

### L3: OpenCode 込み (2026-09-05)

Vision-Exp 配信中に同一の TypeScript タスク (Read → Edit → Edit → Grep の 4 tool call) を 2 回実行し、`~/spark-bench/snap.py` で `/metrics` の前後差分を取った。OpenCode は opencode 1.18.18 で、V2 (2.0.22) では測り直していない。**effort は未指定でテンプレート既定が効いた条件なので、現行の明示的な設定と直接比較しない。** `snap.py` の起動方法・引数・出力先は記録していないため、再現には head 上の実物を読む必要がある。

| 項目 | 実測 (n=2) |
| --- | --- |
| 実時間 | 21〜30 秒 |
| ターン数 | 5 回 |
| 1 ターンのプロンプト | 14,998〜15,008 トークン |
| 受理率 | 0.66〜0.69 |
| prefix ヒット率 | 0.73〜0.90 |
| クライアント側の待ち | −3〜0 秒 |

クライアント側の待ちは実時間からサーバ内の queue + prefill + decode の合算を引いた値で、並列に動けば負になる。

### 遅いと感じたときに疑う順序

サーバを疑うのは最後である。上から順に見る。

1. **OpenCode の接続先とモデル設定** — Tailscale 側の `/health` が応答し、`opencode models` が配信名だけを返すかを見る。常駐サービスが古い設定を持つときは `opencode service restart` で読み直す
2. **プロンプトの長さ** — 指示・会話履歴・ツール結果が増えると prefill の所要時間も増える。サーバの入力トークン数と TTFT を比較し、クライアント側の入力量が変わっていないかを見る
3. **prefix cache のヒット率** — 機構自体は正常に動く (同一プロンプトを 2 回送れば 2 回目にヒットが立つ)。実負荷のヒット率はクライアントがプレフィックスをどれだけ安定させるかで決まる。**L3 の実測レンジは 0.73〜0.90 で、0.5 を切ったらクライアント側の変動を疑う**
4. **投機デコードの受理率** — decode 速度をほぼ決める。**L3 の実測レンジは 0.66〜0.69 で、0.4 を切ったら疑う。** この値は生成させる内容で動く (構造化された出力で高く、散文で低い)
5. **サーバ本体** — ここまで潰してから L1 のベンチを上のフラグで回す。**GPU クロックは 2,200 MHz に制限してあり、X925 の `scaling_max_freq` も下げてある** (→ 「既知の制約」4・5)。どちらも外しても速度はほぼ変わらないと実測済みなので、ここを最初に疑わない。切り分けのために外すなら、**外して測って戻すところまでを 1 セットで行う** (戻し忘れると温度だけが上がった状態が残り、サーバ側に履歴が無いので誰も気づけない → 制約 6)

3 と 4 の計算は `/metrics` から行う。**GLM 系 (TensorFold) は `vllm:` の系列を出さないので、下のコマンドは使えない** (出すのは `tensorfold:` と `tensorfold_health:` の系列)。GLM 系では `curl -s http://spark-head.local:8888/health` の累計値から、prefix ヒット率 ≒ `cached_tokens_total` ÷ `prompt_tokens_total`、受理率 ≒ `accepted_total` ÷ `drafted_total` で代わりに出せる (キーの意味はキー名から読んだもので、TensorFold のソースでは確かめていない)。**3 と 4 の実測レンジは vLLM の値なので、GLM 系の判定には使えない。****キー名は完全一致で拾う。** `prefix_cache` には `vllm:external_prefix_cache_*` が、`spec_decode_num_.*_total` には `vllm:spec_decode_num_accepted_tokens_per_pos_total` が別に存在し、緩い grep は別系列を合算して値を過大に出す。

```bash
curl -s http://spark-head.local:8888/metrics | grep -E '^vllm:(prefix_cache_(hits|queries)_total|spec_decode_num_(accepted_tokens|draft_tokens)_total|request_(prompt|generation)_tokens_sum|request_success_total)'
```

- prefix ヒット率 = `prefix_cache_hits_total` ÷ `prefix_cache_queries_total`
- 受理率 = `spec_decode_num_accepted_tokens_total` ÷ `spec_decode_num_draft_tokens_total`
- 1 リクエストの平均生成長 = `request_generation_tokens_sum` ÷ `request_success_total` の**全 `finished_reason` の合計** (`stop` / `length` / `abort` / `error` / `repetition` の 5 行に分かれて出るので足す。`length` が多ければ出力の打ち切りが起きている)

**本構成の律速は decode ではなく prefill である。** 実負荷での累計プロンプト対生成トークン比は 100:1 前後、1 リクエストの生成長は数百トークンにとどまる。decode を速くする施策は体感に効きにくい。**これらの counter は vLLM コンテナの再起動でリセットされるので、値は「現コンテナが起動してからの累計」として読む** (絶対値は窓の取り方で動く)。

## 障害時

**コンテナ名は系統で違う。** DeepSeek 系は `deepseek-v4-flash-vllm-dspark-1`、Qwen 系は `vllm-fn` (両ノードとも同名)、V4.1 EXL3 系は `dsv41-exl3-head` / `dsv41-exl3-worker`、GLM 系は `glm53-flash-tf` (両ノードとも同名) である。

| 症状 | 確認 | よくある原因 |
| --- | --- | --- |
| 応答しない | 下の待ち行列コマンド | コンテナは生きていて過負荷。同時リクエスト上限 (DeepSeek 系 6 / Qwen 系 8 / V4.1 EXL3 系 2 / GLM 系 4) を超えた分が待つので、待ち行列が 0 でなければ過負荷。**V4.1 EXL3 系は 2 本しか並ばないので、subagent を並列に投げると待ちやすい** |
| コンテナが無い | 両ノードで「系統の切り替え」の手順 3 のコマンド (4 系統すべてを拾う。表のセルに書くと `\|` のエスケープが混ざってそのまま打てないので、そちらをコピーする) | 停止コマンドで止めたまま、またはノードの再起動 (Qwen 系・V4.1 EXL3 系・GLM 系は再起動で上がらない。DeepSeek 系は上がる → 「既知の制約」8)。起動し直す |
| 起動に失敗する | `./logs-deepseek-v4-flash-dspark.sh` (Qwen 系は `docker logs vllm-fn`、V4.1 EXL3 系は `./start.sh logs` / `./start.sh logs worker` と、レシピの `logs/head.log` / `logs/worker.log` / `logs/overlay-verify.log`、GLM 系は `docker logs glm53-flash-tf`) | DeepSeek 系の `no usable RoCEv2 GID` は RoCE 2 本目の IP か MTU (Qwen 系は `IB_HCA` が 1 本なのでこの形では出ない)。Qwen 系は相手系統が GPU を掴んだままだと `REQUIRE_IDLE_GPU` で拒否される。V4.1 EXL3 系は `not enough free unified memory` (相手系統が動いている → 「系統の切り替え」の手順 3)、`FileNotFoundError: /models/config.json` (→「導入の落とし穴 (V4.1 EXL3 系)」4)、`logs/hang-*-pyspy.txt` (head のログが 420 秒止まると書かれる)。**V4.1 EXL3 系は失敗してもコンテナが残るので、`./start.sh stop` してから起動し直す。** GLM 系は `docker logs glm53-flash-tf` (start.sh も失敗時に両ランクの末尾を出す。停止済みのランクのログは `~/.cache/tensorfold-glm53/logs/` に残る)。worker 側の `transport retry counter exceeded` は rank 0 が落ちた後の二次症状なので、head 側から読む |
| Qwen 系がコンテナを作らずに `Checkpoint snapshot is incomplete` で止まる | `python3 files/resolve_snapshot.py <hub の repo ディレクトリ>` の exit code (0 以外) | シャードの欠落。`start.sh` が起動前に検査して止める (→「重みの検証」)。**コンテナが 1 つも作られないので `docker logs vllm-fn` は空振りする。`start.sh` の標準出力を見る。** 復旧は重みの再取得である。Qwen レシピ同梱の `./download.sh` (`--launch` を付けない素の `./start.sh` が内部で呼ぶのと同じもの) は **revision を受けないので、そのまま流すと配信 revision が動く** (→「重みの検証」)。revision を固定して取り直すなら、ログインシェルで `hf download nvidia/Qwen3.8-Flash-Next-NVFP4 --revision fab0aecb760cec45227f6656abcaafa11abca87a --cache-dir ~/.cache/huggingface/hub` を「長い処理を ssh から切り離す」の型で流し、worker へは `utility-spark-model-fetch` の手順 4 で送る (この形は未実行) |
| `model not found` が出る | `curl .../v1/models` で配信名を見る | セッション起動後にサーバ側で切り替えた。OpenCode はプラグインの再取得で 40 秒以内に追従する (→「sparkDash の `workerLabel` を直す」の末尾)。**GLM 系は配信していないモデル名でも応答を返すので、このエラーにならず GLM がそのまま答える** (→「GLM-5.3-Flash EXL3」の「使える API (GLM 系)」) |
| OpenCode が Spark に繋がらない | `tailscale status` に `spark-head` の行があるか (コマンドが無ければ「新しいマシンで手で用意するもの」の Tailscale の行)、`curl -fs -o /dev/null http://spark-head:8888/health` の exit code | OpenCode の接続先は Tailscale 側に固定なので、**自宅でも Tailscale にサインインしていないと届かない**。LAN 経路へ切り替える手段は無い (→「OpenCode」) |
| OpenCode の選択肢に配信していないモデルが残る・既定が配信外のモデルになる | `opencode models` が配信名の 1 行だけを返すか、`readlink -f ~/.config/opencode/plugins/spark-served.ts` が dotfiles 配下を返すか、`curl -s http://spark-head:8888/v1/models` の配信名が `opencode.json` の `models` にあるか | プラグインが動いていないか、`/v1/models` に届いていないか、配信中のモデルが `opencode.json` に宣言されていない。届かないときは、常駐サービスの起動時からなら全モデルが選べるまま (届けば 30 秒以内に絞り込む)、稼働中に届かなくなったなら直前の状態のまま残る。宣言されていないときはプラグインは何もしない (→「OpenCode」の例外 (a)〜(c))。プラグインはログを出さないので、効いているかは配信外の宣言済みモデルが `opencode models` の一覧から消えていることで見る (起動直後の空振りの扱いと、TUI の `Plan · <モデル名>` の表示だけでは判定にならない理由は「OpenCode」)。読み込まれていないようなら `opencode service restart` |
| OpenCode Zen のモデルが選択肢に出る | `opencode.json` の `enabled_providers` | `["spark"]` が無いと Zen の無料モデルが混ざり、既定に選ばれうる |
| 前置した環境変数が OpenCode に効かない | `opencode service status` | 素の `opencode` は常駐サービスに繋ぐので、サービスを起動した最初の TUI の環境変数が使われ続ける (v2.0.22 のソースで確認)。その起動専用のサーバで動かすなら `--standalone` を付ける (それで前置した環境変数が効くことは確かめていない) |
| `Unexpected reasoning effort <値>` の 400 | `opencode.json` の `options.reasoningEffort` | Qwen は `low` / `medium` / `xhigh` を受理し、語彙外をチャットテンプレートが弾く。V4.1 EXL3 は `medium` を vLLM が弾く。DeepSeek 系はスキーマ検証、GLM 系は TensorFold のサーバが検査する。各系統の reasoning effort の語彙を確認する |
| `Input should be 'low', 'medium', ...` の 400 | 送っている effort の値 | `/v1/messages` に `none` を渡した。スキーマが `none` を持たないため、テンプレートより手前で弾かれる。**OpenCode の経路 (`/v1/chat/completions`) では `none` が通る**という非対称がある (→「Qwen の reasoning effort の語彙」) |
| 起動待ちが長すぎる | head は `docker logs <コンテナ名>`、worker は「worker に入る」節のコマンドで同じものを打つ | 正常な所要は DeepSeek 系が約 7〜8 分、Qwen 系が約 13〜14 分、V4.1 EXL3 系がコンテナ起動から health まで約 8 分、GLM 系が約 5〜7 分 (いずれも実測。GLM 系は 2026-10-02 のビルド済みの起動 (レシピ v1.2) で 304 秒、2026-10-04 の新しいイメージの初回 (CUDA 拡張のビルド込み、v1.5) で 422 秒)。DeepSeek 系は 12 分、Qwen 系は 20 分を超えたら worker 側だけ落ちていることがあるので両ランクを見る。V4.1 EXL3 系は 15 分を超えたら `./start.sh logs worker` で worker 側を見る。V4.1 EXL3 系の `start.sh` は health を 1,500 秒待って諦め、そのときもコンテナは残る (→「起動に失敗する」の行)。GLM 系の `start.sh` は `WAIT_TIMEOUT` (既定 1,800 秒) で諦める |
| 推論中に CPU が熱い・ファンがうるさい | 「依拠する外部事実」の温度の行と、同節のコードブロック 3 | 正常。vLLM のスレッドが GPU / NCCL の完了をビジーポーリングで待ち、100% の使用率で回る (→ 「既知の制約」5)。計算しているわけではないので、`nvidia-smi` の GPU 使用率が高いこととは独立に CPU 側センサーが上がる。X925 の `scaling_max_freq` を下げる対処は既に入れてあり (制約 5)、それでも高いなら室温か吸気を疑う |
| 起動直後から空きメモリが少ない | `free -h` | DeepSeek 系と Qwen 系なら正常。確保率 0.835 の先取りで、残る量は DeepSeek 系 6〜8 GiB、Qwen 系の head は 1.3〜5.7 GiB。**V4.1 EXL3 系の head の 4.8 GiB は先取りではなく実際の余裕** (vision tower を含む重み 99.8 GiB + 固定の KV プール 2.5 GiB) で、配信中はこれ以上減らさない (→「既知の制約」11)。GLM 系は起動時の空きから 14.5 GiB を残して予算を組むので、無負荷で 12〜15 GiB 残る (2026-10-04 の実測で 14.3 / 12.8 GiB)。上流は 1M トークンの prompt で head の空きが約 4.5〜5.6 GiB まで下がると書いている (`scripts/config.sh` のコメントと CHANGELOG) |
| 配信中に応答が止まった (V4.1 EXL3 系) | `curl -fs -o /dev/null http://spark-head.local:8888/health`、待ち行列コマンド、両ノードの `docker ps` | 起動中の hang 検知 (420 秒) は配信中には働かない。health が返らない、または `num_requests_running` が動かないまま時間が経つなら、`./start.sh stop` → 「系統の切り替え」の手順 3 → `./start.sh`。片方のノードに ssh も通らない場合は「既知の制約」11 |
| 全体的に遅い | 「遅いと感じたときに疑う順序」を上から | クライアント側が大半 |
| ダッシュボードの worker が古いモデル | `curl -s http://spark-head.local:5555/api/sparks` の worker 行 | `workerLabel` は手書きの静的文字列で、実機とは無関係に表示される。ファイルを直しても `docker restart sparkDash` するまで画面は変わらない。直し方は→「sparkDash の `workerLabel` を直す」 |
| ssh 出力が途中で切れる | 打ったコマンド | 入れ子の `ssh` が標準入力を飲んでいる。内側に `-n` を付ける |
| `opencode` が `command not found` | `type opencode` がパスを返すか | Nix の `drs` / `hms` 未実行か、新しいシェルを開いていない |

待ち行列と稼働中リクエストは次で見る。

```bash
curl -s http://spark-head.local:8888/metrics | grep -E '^vllm:num_requests_(running|waiting)\{'
# GLM 系 (TensorFold) は vllm: の系列を出さないので、/health を読む
curl -s http://spark-head.local:8888/health | python3 -c 'import json,sys; h=json.load(sys.stdin); print("running", h["requests_running"], "streams", h["streams"])'
```

## ノードを作り直したときに手で戻すもの

**次のものは dotfiles にも上流にも無く、ノードを作り直すと失われる。** 再作成の材料が本書にあるものは参照先を書く。

| もの | 置き場 | 戻すときの材料 |
| --- | --- | --- |
| head から worker への鍵と `known_hosts` | head の `~/.ssh/id_ed25519` と、head の `known_hosts` の RoCE アドレスの行 | 鍵は作り直して worker に登録する。`known_hosts` は「接続する」と同じく人が登録する |
| クロック制限の unit 2 本 | 両ノードの `/etc/systemd/system/nv-{gpu,cpu}-clock-limit.service` | CPU 側は「既知の制約」5 に全文がある。GPU 側は `ExecStart` の中身 (`nvidia-smi --lock-gpu-clocks=0,2200`) だけが「既知の制約」4 にある |
| V4.1 EXL3 系の `/v1/responses` のローカルパッチ (公式が無い版のみ) | head の `~/dsv41-local/` と V4.1 EXL3 レシピの `start.sh` の 2 行 | 「既知の制約」12 に全文と足す位置がある。公式が揃う版では上流のパッチを使う |
| 各レシピの手元設定 | DeepSeek 系の `.env.dspark` (Vision-Exp 版と `~/dspark-0731` に 1 枚ずつ)、Qwen レシピの `.env`、V4.1 EXL3 レシピの `.env`、GLM レシピの `scripts/local.sh` | 各系統の表の「上流既定からの差分」の行。値に IP を含むものは「依拠する外部事実」の確認コマンドで引き直す |
| `~/dspark-0731` の worktree | head | 「0731 版で配信する」(`70a7cc4` に detached で作る) |
| `hf` CLI | head の `~/.local/bin/hf` (`~/.venvs/hf/bin/hf` への symlink、1.30.0) | 入れ方の記録は無い。venv に `huggingface_hub` を入れたものと見ている (推測) |
| `~/spark-bench` | head | 再作成手段が無い (→「既知の制約」9) |
| sparkDash | head の `~/sparkDash/` と、未追跡の `docker-compose.override.yml`、`.gitignore` 済みの `config/sparks.json` | clone は上流から取れる。上書きの中身はポーリング間隔 (→「既知の制約」6) と `workerLabel` (→「sparkDash の `workerLabel` を直す」) |
| RoCE の接続 | 両ノードの NetworkManager の接続 `roce` / `roce2` | 「ネットワーク」(別サブネット・MTU 9000) |
| Tailscale | head だけ | 「動いているもの」の MagicDNS 名 `spark-head` |

## 残骸の片付け

**消してよいものと、その条件である。** 取り直せないものを消すかは人が決める。

| 残骸 | 置き場 | 消してよい条件 | 消し方 |
| --- | --- | --- | --- |
| TR3 の重み (164 GiB) | 両ノードの `~/.cache/huggingface/hub/models--Mia-AiLab--GLM-5.3-Flash-EXL3-TR3-4bpw` | GLM レシピ v1.2 へ戻す必要が無いとユーザーが決めたとき。**HF から消えているので、消すと取り直せない** | 両ノードで `rm -rf` |
| `tensorfold-glm53:v0.5.0` (24.6 GB) | 両ノードの docker | TR3 と同じ (v1.2 へ戻すときに使う) | 両ノードで `docker rmi tensorfold-glm53:v0.5.0` |
| `~/.cache/glm53-tf-image` (11 GiB) | 両ノード | いつでも (v0.5.0 は読み込み済み) | `rm -rf ~/.cache/glm53-tf-image` |
| `~/.cache/dsv41-image` (9.1 GiB) | 両ノード | いつでも (V4.1 EXL3 系のイメージは読み込み済み) | `rm -rf ~/.cache/dsv41-image` |
| GLM 系の CUDA 拡張の旧配置 (`torch_extensions/` と `triton/`、約 128 MiB、root 所有) | 両ノードの `~/.cache/tensorfold-glm53/` 直下 | いつでも (現行のイメージは読まない) | root 所有なのでコンテナ経由で消す: `docker run --rm -v ~/.cache/tensorfold-glm53:/c --entrypoint rm tensorfold-glm53:v0.6.0 -rf /c/torch_extensions /c/triton` (この形は未実行) |
| GLM 系の古いイメージの CUDA 拡張 (`~/.cache/tensorfold-glm53/<パッチのハッシュ>/`、root 所有) | 両ノード | そのハッシュのイメージを消したとき | 上と同じくコンテナ経由 |
| 古い revision の HF キャッシュ | 両ノードの `~/.cache/huggingface/hub/models--*/snapshots/<旧 revision>` | その revision へ戻さないと決めたとき | `hf cache rm` (ログインシェルで。使い方は `hf cache --help`。当方では未実行) |
| 起動とダウンロードのログ | head のホームの `~/dsv41-start.log` / `~/glm53-tf-start.log` と、「長い処理を ssh から切り離す」で書いたログ | 読み終えたらいつでも (次の起動で上書きされる) | `rm` |
| GLM 系のサーバのログ | 各ノードの `~/.cache/tensorfold-glm53/logs/` | 手で消さなくてよい (`stop.sh` と start.sh が新しい 10 本だけを残す) | — |
| V4.1 EXL3 系の起動失敗のログ | V4.1 EXL3 レシピの `logs/` (`hang-*-pyspy.txt` を含む) | 原因を調べ終えたら | `rm` |
| 作業ファイル | head と worker の `/tmp` (`/tmp/vs.py` / `/tmp/qwen-manifest.json` / `/tmp/spark.key` など) | 手で消さなくてよい (再起動で消える) | — |
| 計測の結果 | head の `~/spark-bench/results/` | 消さない。過去の値と比べる元で、ハーネスごと再作成手段が無い (→「既知の制約」9) | — |

## 触らないもの

- **`~/.ssh/known_hosts`** — エージェントは書き換えない。登録が要るときは `ssh-keyscan` の 1 行をユーザーに依頼する
- **`drs` / `hms` の実行** — `drs` は Touch ID を、`hms` は sudo (`/etc/codex/config.toml` の symlink) を伴うので、どちらもエージェントは打たない。`git add` までをエージェントが行い、適用はユーザーに依頼する
- **`~/sparkDash/docker-compose.yml`** — 上流の追跡ファイル。上書きは `docker-compose.override.yml` に置く
- **`docker compose restart`** — vLLM には使わない。`stop` → `start`
- **`.env.dspark.bak` のような控え** — `.gitignore` が拾わずキーごと公開リポジトリに載る
- **head の `~/dsv41-local/` と公式が無い版の `start.sh` のローカル差分 2 行** — 公式パッチの本体・実行・mount が揃っていない版で消すと Responses API の `input_text` が 400 になる。更新時は差分を退避して公式を確認し、必要な場合だけ戻す。OpenCode の疎通では検出できない (→「既知の制約」12)
- **公開リポジトリ内のファイルへの IP 直書き** — 本書と `agents/bindings/opencode/` に書かない。OpenCode は Tailscale の MagicDNS 名を使う
- **公開リポジトリ内のファイルへの API キー直書き** — 認証を戻すときも `opencode.json` に平文で置かない。外部へ逃がす手段は「API キーの流れ」の手順 2 (`{file:~/…}` / `{env:…}` が V2 で解かれるかは未確認)
- **クロック制限の 2 unit** (`nv-gpu-clock-limit.service` / `nv-cpu-clock-limit.service`) — 切り分けで一時的に外すのは構わないが、外したままにしない。サーバ側に温度の履歴が無いので戻し忘れに誰も気づけない (→ 「既知の制約」4・5・6)
- **sparkDash のポート 5555** — 認証が無いので信頼できないネットワークへ出さない
- **ポート 8888** — 系統を問わず無認証なので外に出さない (→「API キーの流れ」)
- **`~/dspark-0731` の git の状態** — `70a7cc4` に detached で固定してある。`git pull` や `git checkout main` をすると Vision-Exp 専用の検査が入り、0731 版が起動しなくなる (→「0731 版で配信する」)

## 既知の制約

1. **Spark には passwordless sudo が無い。** `/etc/sudoers.d/` は README のみである。`nvidia-smi --lock-gpu-clocks`・`scaling_max_freq` への書き込み・systemd の操作など sudo が要る作業はエージェントからは実行できないので、コマンドを提示して人間に実行してもらう (パスワードは `skanehira` の Ubuntu ログインパスワードで、本書には保管しない)。Mac の Touch ID による sudo は Linux ノードには効かない。**コンテナ内で root が必要な作業は `docker run --entrypoint` で代替できる** (重みの所有権修正など)
2. **worker への直接 ssh は `known_hosts` の登録が前提である。** 未登録のマシンではエージェントから入れないので「worker に入る」節の head 経由を使う
3. **worker は Tailscale に参加していない** (`tailscaled` が未インストール)。出先から worker を見るには head を経由する
4. **GPU クロックを 2,200 MHz に制限している。** 両ノードの `/etc/systemd/system/nv-gpu-clock-limit.service` (手で配置した unit、enabled + active) が起動時に `nvidia-smi --lock-gpu-clocks=0,2200` を実行する。2026-09-05 の計測 (n=5、L1 とは別条件で結果ファイルは残っていない) では、解除しても decode +1.3% / 最悪 TTFT 約 +2% しか上がらず温度が 7 °C 以上上がった (制限あり 52〜58 °C / 制限なし 60〜65 °C) ので、制限は維持する
5. **X925 の `scaling_max_freq` を 2,808 MHz に下げてある。unit 名に反して、これはハードウェアのクロック上限を変えていない。** 両ノードの `/etc/systemd/system/nv-cpu-clock-limit.service` (手で配置した unit、`Type=oneshot` + `RemainAfterExit=yes`、enabled + active) が起動時に cpu5-9・cpu15-19 の `scaling_max_freq` へ `2808000` (kHz = 2,808 MHz。sysfs の周波数はすべて kHz) を書く。**dotfiles に控えが無いので下に全文を載せる** (制約 9 の `~/spark-bench` と同じく再作成手段が無い資産である)。

   - **効いていないもの (実測)**: 書き込みは受理されるが CPPC のレジスタに伝播しない。`max_perf` は cpu5 が 3900000、cpu19 が 4004000 のままで、負荷中に X925 のコアが走るとその実効クロック (`cpuinfo_avg_freq`) は 3,886,695〜3,898,425 に達する。

   - **`scaling_cur_freq` は `cppc_cpufreq` では要求値のエコーなので実効値と読んではいけない** (busy な A725 は要求値と実効値が一致するのに busy な X925 だけ 1.1 GHz 乖離する。この非対称がエコーであることの対照になる)。

   - **実際に起きていること (実測)**: 書き込みの前後で **vLLM の busy スレッドの載り先が X925 から A725 へ移った**。前は cpu15 が 70%・cpu18 が 78% と X925 が主だったのに対し、後は cpu0〜cpu4 のうち 3 本が 91〜100% で回る。**X925 が使われなくなったわけではない** — 連続負荷中に 8 回サンプルしたうち 1 回は cpu19 が 92% で busy になり、そのときの実効クロックは 3,882,785 だった。**どういう条件で X925 に載るかは特定していない。** **理由は「`scaling_max_freq` を下げたことでスケジューラの capacity の見立てが変わり X925 を選ばなくなった」と読んでいるが、確認していない (推測)。**

   - **推論中に CPU が熱くなるのは計算しているからではない。** vLLM のスレッド 3 本 (`VLLM::EngineCore` / `VLLM::Worker_TP` / `VLLM::Worker`) が 100% の使用率で回り続け、その間クロックが最大に張り付く。**実測から言えるのはここまでで、「ビジーポーリングで待っている」は推測である** — 同じ区間で GPU が 93% 動いており、スレッドが自発的にブロックする回数が 1 ステップあたり 2〜5 回しかないことから、CPU 時間の大半は実処理ではなく完了待ちのスピンだと読んでいる。スタックは追っていないので、待ち先が CUDA の同期か NCCL かは未確認である (1 decode ステップ 63 ms のうち GPU 使用率は 93%、スレッドが自発的にブロックするのは 1 ステップあたり 2〜5 回。取得手段は「依拠する外部事実」の該当行)。

   - **需要に追従する governor (`schedutil` / `ondemand` / `conservative`) に変えても効かない。** スピンするスレッドは使用率 100% に見えるので、どれも最大クロックを選ぶ。**唯一の例外は `powersave` で、これは最小クロックに固定するため温度は下がるが、直列処理まで 338 MHz に落ちるので速度への影響が別物になる。本書では試していない (未検証)。**

   - **2026-09-10 の計測 (Qwen3.8-Flash-Next 配信中、単一ストリーム・800 トークン、GPU 制限は両方の条件で有効、n = 制限前 3 / 制限後 2、結果ファイルは残していない) では速度低下は無く** (制限前 26.06〜26.80 秒 / 制限後 24.55〜26.02 秒)。**2 群のレンジはわずかに重ならず、制限後の方が速い。これは説明できていない** (n が 3 と 2 と少ない、prefix cache の状態が揃っていない、直前の熱状態が違う、のいずれもありうる)。**言えるのは「遅くなってはいない」までで、「速くなった」とは読まない。** 温度は **TS0P が 62.0 → 47.7〜49.5 °C、TSOC が 62.5 → 52.5〜53.6 °C に下がった** (センサー名は下の制約 6 とその読み方を参照)。

   - **速度が変わらないことは効果の判別に使えない** — 設定が効いていなくても速度は変わらないので、両方の仮説と整合してしまう。判別材料は温度と busy コアの載り先だけである。

   - **並列時 (Qwen は最大 8 リクエスト) は未計測である。**

   - **この設定は目的 (温度を下げる) を達しているが、意図した機構では動いていない。** 素直にクロックを縛りたいなら CPPC の `max_perf` を動かす手段を別に探す必要がある。

   - 解除は両ノードで `sudo systemctl disable --now nv-cpu-clock-limit.service` (`ExecStop` が `cpuinfo_max_freq` の値を `scaling_max_freq` へ書き戻す)、戻すのは `sudo systemctl enable --now nv-cpu-clock-limit.service`。worker には「worker に入る」節のコマンドで同じものを打つ (sudo が要るので実行は人間)

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

6. **温度センサーは ACPI の 7 つで、履歴はどこにも残っていない。** `/sys/class/thermal/thermal_zone{0..6}/temp` がミリ °C を返す。名前は起動ログ (`journalctl -b -q -o cat | grep 'Thermal Zone \['`) が登録順に出す。zone0 = `TSOC` (SoC 全体) / zone1 = `TS0E` / zone2 = `TS0P` / zone3 = `TS1E` / zone4 = `TS1P` / zone5 = `TGPU` / zone6 = `TUNC`。**`TS<n>E` / `TS<n>P` が効率コアと性能コアに対応するという読み方は本書の推測で、NVIDIA の公表資料では裏を取っていない** (X925 の制限で `TS0P` が 14.3 °C 下がった実測とは整合する)。トリップ点は全 zone とも 104.8 °C、`policy` は `step_wise` である。`TSOC` の 3 文字目は英字の O、`TS0P` / `TS0E` の 3 文字目は数字のゼロで、grep するとき紛らわしい。**サーバ側に残る履歴は無い。** sparkDash は CPU 温度も採るが (head の `~/sparkDash/server/collectors/SystemCollector.js` が hwmon の `acpitz` と thermal zone を読む)、履歴はブラウザのメモリ (`~/sparkDash/src/hooks/metricsStore.ts` の `HISTORY_MAX` = 1,800 サンプル。sparkDash の `docker-compose.override.yml` が `POLL_INTERVAL_CPU` を 15 秒にしているので約 7.5 時間分) にしか無く、ページを閉じれば消える。journald に出るのは起動時の 1 回だけ (7 zone 分 7 行)。`collectd` / `netdata` / prometheus exporter の類は両ノードとも動いていない (2026-09-10 実測)。**したがって過去に遡った統計は取れない。** 必要になったら記録の仕組みを先に用意する
7. **停止と再起動はユーザーの作業を止める。** 打つ前に稼働中リクエストが無いことを確認する (→「系統の切り替え」の手順 1)。OpenCode の実行中タスクが終わってから操作する
8. **推論サーバの自動復帰は系統で違う。** DeepSeek 系コンテナの restart policy は `unless-stopped` だが、**Qwen 系 `vllm-fn`、V4.1 EXL3 系 `dsv41-exl3-head` / `dsv41-exl3-worker`、GLM 系 `glm53-flash-tf` は両ノードとも `no` なので、ノードを再起動すると上がってこない** (Qwen 系は 2026-09-06、V4.1 EXL3 系は 2026-09-15、GLM 系は 2026-10-04 に実測)。手で Qwen 系は `./start.sh --launch`、V4.1 EXL3 系と GLM 系は `./start.sh` を打ち直す (重みの同期はマーカーで省略されるので速い)。sparkDash は `always`、`docker` と (head の) `tailscaled` は enabled、RoCE は NetworkManager の autoconnect、GPU と CPU のクロック制限は 2 つの unit がどちらも enabled である (→ 制約 4・5)。どの系統も停止スクリプトで止めた後はコンテナ自体が消えるので再起動しても復帰しない。**cold boot での復帰は未確認なので、電源断の後は `docker ps` で確かめる**
9. **`~/spark-bench` は再作成手段が無い。** dotfiles にも上流にも無い手書きのハーネスなので、head を作り直すと失われる
10. **4 系統の推論サーバは同時に起動できない。** ポート 8888 と GPU を共有し、Qwen 側は `REQUIRE_IDLE_GPU=true`、V4.1 EXL3 側はメモリの事前検査、GLM 側はポートの事前検査が明示的に拒否する。切り替えは必ず「相手を停止 → 起動」の順で行う (→「系統の切り替え」)
11. **V4.1 EXL3 系はメモリの余裕が薄い。** 配信中の head の `MemAvailable` は 5 GiB 前後である (画像入力を有効にした 2026-09-30 の実測で 4.8 GiB)。上流は `MAX_MODEL_LEN` 614,400 の構成で 601k トークンの prefill 中に 2.1 GiB まで下がったと書いている (当方の 600,000 では同じ入力は入らないが、長い prefill ほど下がる傾向は同じと見ている。未検証)。**上流の報告では、GB10 は統合メモリが尽きるとエラーではなくノードごと固まり、ハード再起動まで戻らなかった。** 当方では起きていないので、固まったときの兆候と復旧は未確認である。想定される兆候は、ssh も sparkDash も応答しないことと、worker だけが固まった場合に head の `/health` が応答しなくなることである。その場合は人が電源を入れ直す (sparkDash の Wake-on-LAN は電源断からの起動用で、固まったノードに効くかは未確認)。**配信中のノードで重い処理 (ダウンロード・ビルド・大きなファイルの展開) を流すときは上限を付ける。** 手段は 2 つあり、どちらでも上限が掛からない操作が 1 つある。

    - **数時間かかるものはコンテナで流す。** `docker run -d --memory <上限> …` で流すと dockerd が管理するので、ssh を切っても止まらない (GLM 系の重みの取得で 2026-10-03〜04 に使った →「導入手順 (GLM 系)」2)
    - **ssh を開いたまま終わるものは `systemd-run --user --scope -p MemoryMax=<上限>` で流す。** `ssh -n` 経由では `XDG_RUNTIME_DIR=/run/user/$(id -u)` を前置する (head では 2026-09-15 に効くことを確かめた。worker では未確認)。ユーザーの linger が無効 (`Linger=no`) なので、最後のセッションが閉じると user manager ごと scope が止まりうる (systemd の仕様からの推定で、確かめていない)
    - **dockerd を通る操作 (`docker pull` / `docker load`) はどちらの手段でも上限が掛からない。** 配信を止めてから流す

   **memguard (→ 用語表) は上流既定のまま無効にしている。** 上流によれば、有効にして唯一発動したときは無関係なホストのプロセスがメモリを取った場面で、原因ではない vLLM を kill しただけだった。代わりに両コンテナは `--oom-score-adj 1000` で起動されていて、カーネルの OOM killer が動けばデスクトップより先に vLLM が落ちる
12. **V4.1 EXL3 系の `/v1/responses` は tokenizer の content パーツ対応に依存する。** 配信イメージ `ghcr.io/miaai-lab/deepseek-v4.1-flash-exl3-2x-dgx-sparks:2.9bpw` が `FROM` で使うベース `vllm/vllm-openai:deepseekv41-flash-0909` (レシピの `Dockerfile` の `ARG BASE`) に入っている `vllm/tokenizers/deepseek_v41.py` の `_normalize_messages` は、メッセージの content パーツを `text` / `image_url` / `input_image` / `image_pil` しか受けない。Responses API が使う `input_text` は 400 になる (`DeepSeek V4.1 supports text and image content only; got 'input_text'`)。**上流 vLLM の `main` は既に `("text", "input_text", "output_text")` を受けるので、これはイメージが古いだけである。** `b9c49e9` では head の `~/dsv41-local/patch_responses_content_parts.py` がその 1 行を起動のたびに当て直す。2026-10-04 に確認した head の保存済み `origin/main` には公式の `overlay/patch_responses_content_types.py` と両ランクへの実行・配布・mount がある (fetch はしておらず、最新の上流との一致は未確認)。公式が揃う版では公式を使う (**OpenCode の経路はパッチが無くても動く**ので、Responses API を個別に確かめる)。

    - **公式が無い版のローカルパッチ本体は clone の外 (`~/dsv41-local/`) に置く。** レシピの `overlay/` に置くと `overlay_recipe_hash` (`Dockerfile` + `overlay/` + `files/` + `tests/` の hash) が動き、イメージの `dsv41.recipe.stamp` と食い違って**レジストリから約 9 GiB を pull し直す**。この分岐は `SKIP_BUILD` では止まらない。止めるキーとして `SKIP_PULL` / `BUILD` を控えてあるが、`SKIP_PULL` は「起動と判定 (V4.1 EXL3 系)」の前置で効くキーの一覧に無く、V4.1 EXL3 レシピの `start.sh` が受けるかは未確認である
    - **公式が無い版では、上流追跡ファイルの `start.sh` に 2 行のローカル差分を足す。未コミット差分は `git pull` / `git checkout` で維持されるか、競合する変更なら Git が拒否する。更新前に退避・clean 化し、更新先の公式対応を確認する (→「レシピを更新する (V4.1 EXL3 系)」)。** head 用スクリプトのパッチループに `         /opt/dsv41/patch_responses_content_parts.py \`、head コンテナの `docker run` の `-v` ブロックに `        -v "$HOME/dsv41-local/patch_responses_content_parts.py:/opt/dsv41/patch_responses_content_parts.py:ro" \` を足してある。足す位置は、前者がパッチループの `/opt/dsv41/patch_sm120_block64.py \` の行の直後、後者が `-v "$EXL3_OVERLAY_HOST:/opt/dsv41/exl3.py:ro" \` の行の直後である (`grep -n -e patch_sm120_block64.py -e 'exl3.py:ro' start.sh` で引く。2026-10-04 時点の差分の位置)。**worker 側には足していない** — トークナイズは head の API サーバでしか走らないため
    - **`b9c49e9` のパッチループは失敗を `WARN` で握り潰す。** そのためパッチ自身がアンカーの有無を検査して非 0 で終わるようにしてある。適用できたかは `docker logs dsv41-exl3-head` の `[dsv41-responses-parts]` の行で見る (レシピの `logs/` には出ない)。**判定の本体は「依拠する外部事実」の `input_text` の curl である**
    - **更新先は公式パッチを先に確認する。** `test -f overlay/patch_responses_content_types.py` と `grep -n -e RESPONSES_PATCH_HOST -e patch_responses_content_types.py start.sh` で本体と参照を確認する。`RESPONSES_PATCH_HOST` の既定が `$SCRIPT_DIR/overlay/patch_responses_content_types.py`、両ランクのパッチループに `/opt/dsv41/patch_responses_content_types.py`、worker への scp、worker mount `/tmp/patch_responses_content_types.py:/opt/dsv41/patch_responses_content_types.py:ro`、head mount `$RESPONSES_PATCH_HOST:/opt/dsv41/patch_responses_content_types.py:ro` が揃っていればローカル 2 行は再適用しない。保存済み `origin/main` での参照確認だけでは、更新後のイメージでパッチが走ることは未検証なので、起動後にログとコードブロック 6 の 200 を確認する
    - **イメージ自体が対応済みなら backport は不要になる。** ローカルパッチは対応済みの `MARK` があれば `already patched:` を出して exit 0、アンカーも `MARK` も無ければ FATAL で非 0 になる。FATAL だけを「対応済み」の判定に使わない。撤去を判断するのは、公式対応の確認と `input_text` の HTTP 200 が通った後である。退避ファイルや `~/dsv41-local/` は、旧版へ戻す可能性がある間は保持する
    - **DeepSeek 系 (Vision-Exp 版・0731 版) ではこの問題が出ない** (2026-09-23 に両版で `input_text` が 200 で通ることを実測)。このトークナイザは V4.1 EXL3 系だけが使い、DeepSeek 系は `--tokenizer-mode deepseek_v4` で別のものを通る。GLM 系 (TensorFold) も `input_text` を 200 で受ける (2026-10-04)。**Qwen 系は未確認である**
    - **更新・再 clone・checkout の後は、公式パッチの本体・実行・mount を確認し、公式が無い版だけローカル版を用意する。** 手順は「レシピを更新する (V4.1 EXL3 系)」と「導入手順 (V4.1 EXL3 系)」に組み込んである。合格判定は「依拠する外部事実」のコードブロック 6 が 200 を返すことである
    - **dotfiles に控えが無いので下に全文を載せる** (制約 5 の systemd unit と同じ扱い)。head を作り直し、公式が無い版を使う場合は、これを `~/dsv41-local/patch_responses_content_parts.py` に書き、実行ビットを立てる

    ```python
    #!/usr/bin/env python3
    """Accept Responses-API content parts in the DeepSeek V4.1 tokenizer.

    The image `vllm/vllm-openai:deepseekv41-flash-0909` ships a
    `_normalize_messages` that only accepts `text` for textual content parts, so a
    request whose message content is `[{"type": "input_text", ...}]` fails with

        DeepSeek V4.1 supports text and image content only; got 'input_text'

    That is the shape the OpenAI Responses API uses. vLLM main
    already widened the tuple to ("text", "input_text", "output_text"); this is a
    backport of that one line onto the pinned image.

    Upstream: vllm/tokenizers/deepseek_v41.py on vllm-project/vllm@main.

    Idempotent: re-running after the patch is a no-op. Exits non-zero when the
    anchor is missing, because start.sh's patch loop swallows failures with a WARN
    and a silent no-op would look exactly like a working server until the first
    Responses API request.
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

「確認日」の列は、その行の確認を実機で行った日である。2026-09-06 の行は、本書が全体を実機で確かめた日の記録だけを持ち、行ごとに別の日の記録が無いものである。確認した日の記録がどこにも無いものは「記録なし」と書く。作業前に変わっていないか確かめる。**いまはどのエンドポイントも無認証なので、確認コマンドにキーは要らない。**

| 事実 | 確認コマンド | 確認日 |
| --- | --- | --- |
| IP・インタフェース構成・MTU | `ssh -n spark-head 'ip -4 -o addr show; ip -o link show'` | 2026-09-06 |
| ドライバとカーネル | `ssh -n spark-head 'nvidia-smi --query-gpu=driver_version --format=csv,noheader; uname -r'` | 2026-09-06 |
| ディスクの空き | `ssh -n spark-head 'df -h /'` | 2026-10-04 |
| メモリの内訳 | `ssh -n spark-head 'grep -E "^Mem" /proc/meminfo; swapon --show; nvidia-smi --query-compute-apps=used_memory --format=csv,noheader'` | 「メモリの使われ方」の各列の日付 |
| DeepSeek 系のサービングの設定値 | head の DeepSeek 系レシピで `./validate-dspark-config.sh` を打ち、先頭 20 行だけを読む (解決値の後に vLLM コマンド全文が数 KB 続くので絞る。絞った形は「レシピを更新する (DeepSeek 系)」のコードブロックの `validate` の行) | 2026-09-23 |
| DeepSeek 系レシピの上流の先行コミット | `ssh -n spark-head 'cd ~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark && git fetch -q && git rev-list --count HEAD..origin/main && git log --oneline HEAD..origin/main'` | 2026-09-23 |
| 全モデルの重み | `ssh -n spark-head 'du -sh ~/.cache/huggingface/hub/models--* ~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks/{model,engram-src} ~/dsv41-engram'` (HF キャッシュの全モデルとレシピ直下の V4.1 EXL3 系を拾う。worker の V4.1 EXL3 系は `~/.cache/dsv41-flash-exl3/{model,engram-src}` と `~/dsv41-engram`) | 「重みの置き場所 (4 系統)」の各行の日付 |
| Qwen レシピの commit | `ssh -n spark-head 'cd ~/Qwen3.8-Flash-Next-Dual-DGX-Sparks && git log --oneline -1'`。上流の先行分は同じディレクトリで `git fetch -q && git log --oneline HEAD..origin/main` | 2026-09-09 |
| V4.1 EXL3 レシピの commit | `ssh -n spark-head 'cd ~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks && git log --oneline -1'` (2026-09-30 時点 `b9c49e9`)。上流が先行していたら `git log --stat HEAD..origin/main` で `Dockerfile` / `overlay/` / `files/` / `tests/` に変更があるかを見る (あればイメージの stamp がずれる →「導入の落とし穴 (V4.1 EXL3 系)」6) | 2026-09-30 |
| V4.1 EXL3 の重みがそろっているか | 下のコードブロック 5 (本体 49 ファイルのサイズを revision 固定の HF API と比べる。`OFF=1` にすると期待値を 1 本だけ 1 バイトずらす陽性対照になり、exit 1 を返す)。両ノードで exit 0、`OFF=1` で exit 1 を確認した。Engram の 2 本は「導入手順 (V4.1 EXL3 系)」の Engram のコードブロック末尾の `sha256sum -c` で照合し、`engram-src/` に `config.json` と `model.safetensors.index.json` があることも見る | 2026-09-15 |
| V4.1 EXL3 系の上流既定からの差分 | 下のコードブロック 4 | 2026-09-30 |
| GLM 系の上流既定からの差分 | レシピのディレクトリで `cat scripts/local.sh; ls .env 2>/dev/null; git status --short` (`local.sh` の行は worker のアドレスを出すので証跡として貼らない)。**`WORKER=` の 1 行だけで、`.env` が無く、`git status` が `?? scripts/local.sh` だけなら合格** | 2026-10-04 |
| GLM 系のイメージと clone のずれ | レシピのディレクトリで `docker image inspect -f '{{index .Config.Labels "tf.patches"}}' tensorfold-glm53:v0.6.0` と `bash -c 'source scripts/config.sh; image_hash'` を比べる。**一致すれば prepare.sh はイメージを取り直さない** (2026-10-04 は両方 `9f73cca659a1`) | 2026-10-04 |
| GLM レシピの commit | `ssh -n spark-head 'cd ~/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold && git log --oneline -1'` (2026-10-04 時点 `1576746`)。上流の先行分は同じディレクトリで `git fetch -q && git log --oneline --stat HEAD..origin/main` (2026-10-04 時点で `CHANGELOG.md` だけを変える 2 コミットが先行) | 2026-10-04 |
| TensorFold の API の形 | `curl -s http://spark-head.local:8888/v1/models` の各要素のキーが `id` / `object` / `owned_by` の 3 つで `max_model_len` が無いこと。`/v1/messages` への POST が 404 を返すこと (→「使える API (GLM 系)」) | 2026-10-04 |
| opencode の版 | Mac 側で `opencode --version` (`opencode v2.0.22`)。版が変わったら「OpenCode」節の「v2.0.22 のソースで確認」とした項を確かめ直す | 2026-10-04 |
| 画像入力が通るか | 下のコードブロック 10 (モデル名を配信名に差し替える) | 2026-10-04 (GLM 系で陽性・陰性の両対照。DeepSeek 系は 2026-09-23、V4.1 EXL3 系は 2026-09-30 に別の画像で実測) |
| HF 側の `main` が動いていないか | 下のコードブロック 7。**`fab0aecb` 以外を返すならキャッシュより先に進んでいる** (2026-09-09 時点は `fc694b54`。意味は → 「重みの検証」) | 2026-09-09 |
| Qwen 系の重みが完全か | `ssh -n spark-head 'cd ~/Qwen3.8-Flash-Next-Dual-DGX-Sparks && python3 files/resolve_snapshot.py ~/.cache/huggingface/hub/models--nvidia--Qwen3.8-Flash-Next-NVFP4; echo $?'` (0 で合格)。**陽性対照は存在しないディレクトリを渡して 2 が返ること。** head 1 ノードを manifest と突き合わせるなら「重みの検証」節の `verify-weights.py --revision`、両ノードなら同節の `--save-manifest` + `check-weights.sh --manifest` を使う (revision を省くと HF の `main` と比べて必ず 2 件不一致になる) | 2026-09-09 |
| 両ノードのイメージ | `ssh -n spark-head 'docker images --format "{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}"'` (worker は「worker に入る」節経由で同じもの) | 2026-09-06 (V4.1 EXL3 系は 2026-09-15、GLM 系は 2026-10-04) |
| worker 側の同じ確認 | 「worker に入る」節のコマンドの `<worker で実行するコマンド>` に上記を入れる | — |
| 稼働中のモデル名と上限 | `curl http://spark-head.local:8888/v1/models`。GLM 系は `max_model_len` を返さないので、上限は `curl -s http://spark-head.local:8888/health` の `context_length` で見る | 2026-09-06 (GLM 系は 2026-10-04) |
| 8888 が無認証のままか | `curl -s -o /dev/null -w "%{http_code}\n" http://spark-head.local:8888/v1/models` (200 なら無認証。対照に `/v1/nope` が 404 を返すことも見る) | 2026-09-06 (V4.1 EXL3 系は 2026-09-15、GLM 系は 2026-10-04) |
| 各種メトリクス | 「遅いと感じたときに疑う順序」の `curl` 1 本 (完全一致の grep)。GLM 系は `vllm:` の系列が無いので `/health` を読む (同節) | 2026-09-06 (GLM 系は 2026-10-04) |
| CPU のトポロジと governor | 下のコードブロック 8 (worker は「worker に入る」節経由)。**cpu5 / cpu15 が 3900000、cpu0 / cpu10 が 2808000 なら「ハードウェアと OS」表のコア割り当てどおり。** unit が書き込む対象コアがこの割り当てに依存するので、別ロットで番号が入れ替わっていないかをここで見る | 2026-09-10 |
| クロック制限の unit が有効か | `ssh -n spark-head 'systemctl is-active nv-gpu-clock-limit.service nv-cpu-clock-limit.service'` (worker は head 経由。両方 `active` で合格)。**どちらも `Type=oneshot` + `RemainAfterExit=yes` なので `active` のまま残る** (この 2 行が無い素の oneshot は実行後に `inactive` になり、この判定は使えない)。**`is-active` は unit が走ったことしか言わないので、実効値は下の 2 行で別に見る** | 2026-09-10 |
| GPU クロック制限が実際に効いているか | `ssh -n spark-head 'nvidia-smi --query-gpu=clocks.max.sm,clocks.applications.graphics --format=csv'` と、負荷中の `nvidia-smi --query-gpu=clocks.sm --format=csv,noheader`。**負荷中に 2200 MHz 前後を超えなければ効いている。** ロックは unit が `active` のままでも外部要因で解けうるので、`is-active` を実効性の証跡にしない | 2026-09-10 |
| X925 の `scaling_max_freq` が下げてあるか | `ssh -n spark-head 'for c in 5 19; do echo "$(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_max_freq) $(cat /sys/devices/system/cpu/cpu$c/cpufreq/cpuinfo_max_freq) $(cat /sys/devices/system/cpu/cpu$c/cpufreq/max_perf)"; done'` (worker は「worker に入る」節経由)。単位はすべて kHz。**`2808000 3900000 3900000`(cpu5) / `2808000 3900000 4004000`(cpu19) が現状で、意味は「policy は下げたがハードウェアには届いていない」。** 3 列目 (`max_perf`) が 2808000 になって初めて本当のクロック制限である。1 列目と 2 列目が同値なら unit が当たっていない。sudo は要らない | 2026-09-10 |
| X925 の実効クロック (**`scaling_cur_freq` は見ない**) | **`scaling_cur_freq` は `cppc_cpufreq` では要求値のエコーで、負荷と無関係に `scaling_max_freq` と同じ値を返すため検査に使えない** (これで「上限以下」を確認しても、原理的に不合格になりえない)。実効値は `cpuinfo_avg_freq` (直近区間の delivered performance) を **busy なコアに限って**読む。手順は下のコードブロック 3。**陰性対照は busy な A725 で、要求値 2808000 と実効値がほぼ一致する。** X925 が同時に 3.8〜3.9 GHz を返せば、エコーではなく実効値を見られている。**idle のコアに打つと値が動かないか `Resource temporarily unavailable` を返すので、busy 判定と必ず組で使う。** | 2026-09-10 |
| 推論中に CPU を使っているのが誰か (「既知の制約」5 の因果の根拠) | 4 値をそれぞれ別の手段で採る。**(a) decode 1 ステップの時間** = 推論 1 本の前後で `curl -s http://spark-head.local:8888/metrics` を取り、`vllm:iteration_tokens_total_count` の行の増分でその間の所要秒を割る (「実測値」節の「decode の分解 (2026-09-23)」はステップ数を別のカウンタ `vllm:spec_decode_num_drafts_total` で数え、時間も初回トークンからの区間で測るので、両者の値 (63 ms と約 70 ms) は直接比べない)。**(b) 同区間の GPU 使用率** = 負荷中に `ssh -n spark-head 'nvidia-smi --query-gpu=utilization.gpu,clocks.sm,power.draw --format=csv'`。**(c) スレッドごとの CPU 時間** = 負荷の前後で `/proc/<tid>/stat` の 14・15 列 (user / sys、単位は 10 ms) の増分を取る。**(d) 自発的にブロックした回数** = 同じ区間で `/proc/<tid>/status` の `voluntary_ctxt_switches` の増分を (a) のステップ数で割る。**tid は `ps -eLo tid,pcpu,comm` で `VLLM` を含むものを拾う** (`docker exec` は要らない。コンテナのスレッドもホストの `/proc` に見える)。2026-09-10 に (a) 63 ms / (b) 93% / (c) 3 本が 91〜99% / (d) 2〜5 回を実測。**スタックまでは追っていないので、スピンの出所が CUDA の同期待ちか NCCL かは未確認である** (コンテナに `py-spy` が無く、`perf` / `strace` は sudo が要る) | 2026-09-10 |
| CPU / SoC の温度 | `ssh -n spark-head 'for z in 0 1 2 3 4 5 6; do awk "{printf \"zone%s=%.1f \", $z, \$1/1000}" /sys/class/thermal/thermal_zone$z/temp; done; echo'` (worker は「worker に入る」節経由)。**zone の名前と読み方は「既知の制約」6。** 単位は °C。**履歴は残らないので、比較したいときは負荷の前後で自分で採る** | 2026-09-10 |
| 再起動後の復帰条件 | `ssh -n spark-head 'docker inspect <コンテナ名> --format "{{.HostConfig.RestartPolicy.Name}}"'` (DeepSeek 系は `deepseek-v4-flash-vllm-dspark-1`、Qwen 系は `vllm-fn`、V4.1 EXL3 系は `dsv41-exl3-head` (worker 側は `dsv41-exl3-worker`)、GLM 系は `glm53-flash-tf` (両ノードとも同名)) | 2026-09-06 (V4.1 EXL3 系は 2026-09-15、GLM 系は 2026-10-04) |
| `/v1/responses` が `input_text` を受けるか | 下のコードブロック 6。**200 で合格。** パッチ前は 400 を返すことを 2026-09-17 に実測してあり、それがこの検査の陰性対照である | 2026-09-17 |
| ローカル版の head のパッチが走ったか | 下のコードブロック 9。最後の行が `patched:` か `already patched:` なら適用済み、`FATAL` なら当たっていない (→「既知の制約」12)。公式版は公式スクリプトのログの目印で確認する。いずれも本体の判定はコードブロック 6 の HTTP 200。**レシピの `logs/` には出ない** — パッチはコンテナ内で走るので docker のログに入る | 2026-09-17 (ローカル版) |
| `start.sh` のパッチ経路 | `ssh -n spark-head 'cd ~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks && git diff --stat start.sh'` がローカル 2 行の有無を示す。空でも公式パッチの有無は別に確認する (→「既知の制約」12)。保存済み `origin/main` は公式本体と実行・配布・mount が揃う (fetch はしていない) | 2026-10-04 (参照のみ、公式版の起動は未検証) |
| Tailscale の参加状況 | Mac 側で `tailscale status` (`spark-head` の行があれば合格)。コマンドが無ければ `/Applications/Tailscale.app/Contents/MacOS/Tailscale status` (→「新しいマシンで手で用意するもの」) | 2026-10-03 |
| OpenCode の設定 | Mac 側で `python3 -c "import json;c=json.load(open('$HOME/.config/opencode/opencode.json'));print(c['enabled_providers'], c['provider']['spark']['options']['baseURL'])"`。`['spark'] http://spark-head:8888/v1` が出れば合格 | 2026-10-03 |
| OpenCode の接続先 URL の 2 か所が一致しているか | dotfiles で `deno test --allow-env --allow-run --allow-read --allow-write agents/`。`spark-served_test.ts` が `opencode.json` の `baseURL` とプラグインの `BASE_URL` を比べる | 2026-10-03 |
| OpenCode の設定が live edit か | Mac 側で `readlink -f ~/.config/opencode/opencode.json` と `readlink -f ~/.config/opencode/plugins/spark-served.ts`。**dotfiles 配下を返せば live、`/nix/store/…` で終われば store コピー。** **`-f` を落とすと判定が壊れる**: `mkOutOfStoreSymlink` は `~/.config/…` → `…-home-manager-files/…` → `…-hm_<名前>` → dotfiles の 3 段になるので、単 hop の `readlink` は live でも `/nix/store/…` を返し、常に「`drs` 待ち」と誤判定する (2026-10-03 に `opencode.json` で 3 段を実測) | 2026-10-03 |
| OpenCode の `cli.json` が symlink のままか | Mac 側で `test -L ~/.config/opencode/cli.json && readlink -f ~/.config/opencode/cli.json`。dotfiles 配下を返せば正常。何も出なければ実ファイルになっている。原因は TUI での設定変更か、symlink で配る前の dotfiles が初回にコピーした実ファイルの残りである (差の取り込みと張り直す手順は「OpenCode」) | 2026-10-03 |
| OpenCode が配信中のモデルを選んでいるか | Mac 側で `opencode models` が `spark/<配信名>` の 1 行だけを返して exit 0 になること (配信名は `/v1/models` と比べる)。**常駐サービスの起動直後は空を返しうる**ので、1 行が出るまで 2 秒間隔で最大 10 回打ち直し、10 回で出なければ失敗として扱う。プラグインを外した対照は取っていないので、1 行に絞られていることがプラグインの効果だという点は未確認である。既定に選ばれたモデルは TUI の入力欄の下の `Plan · <モデル名>` か `opencode run "1+1 は?"` の出力で見る (→「OpenCode」) | 2026-10-03 |
| OpenCode の接続先への疎通 | Mac 側で `curl -fs -o /dev/null http://spark-head:8888/health`。接続先が Tailscale 側なのでその経路を見る | 2026-10-03 |
| 配信中のモデルが受ける reasoning effort と既定値 | **経路ごとに 3 本打つ** (語彙が違う → 「Qwen の reasoning effort の語彙」)。**`/v1/responses` は下のコードブロック 6 に `"reasoning":{"effort":"<値>"}` を足した形で打つ**。OpenCode 側は `curl -s http://spark-head.local:8888/v1/chat/completions -H 'Content-Type: application/json' -d '{"model":"<配信名>","messages":[{"role":"user","content":"x"}],"reasoning_effort":"high","max_tokens":1}'`、`/v1/messages` は `curl -s http://spark-head.local:8888/v1/messages -H 'Content-Type: application/json' -H 'anthropic-version: 2023-06-01' -d '{"model":"<配信名>","messages":[{"role":"user","content":"x"}],"max_tokens":1,"output_config":{"effort":"high"}}'`。**語彙外の値を投げて 400 のエラー本文を読むのが陽性対照** (対応値を列挙する)。**陰性対照として受理される値でも打ち、200 が返ることを確かめる** (常に 400 を返す壊れた検出でないことの確認)。値は系統で変える。Qwen 系は陽性対照 `high` / 陰性対照 `xhigh`、V4.1 EXL3 系は陽性対照 `medium` / 陰性対照 `max` (`high` は受理されるので陽性対照にならない)、DeepSeek 系は陽性対照 `bogus` / 陰性対照 `high` (`medium` も受理されるので既存 2 系統の陽性対照は使えない)、GLM 系は陽性対照 `bogus` / 陰性対照 `max` (`/v1/messages` が無いので 2 経路だけ打つ)。**Qwen 系 (2026-09-06)・V4.1 EXL3 系 (2026-09-15)・DeepSeek 系 (2026-09-23) は全値で実測済み。GLM 系は `/v1/chat/completions` と `/v1/responses` で実測済みで、`/v1/messages` は持たない** | 系統ごとに行の中の日付 (GLM 系は 2026-10-04) |
| OpenCode の effort 設定 | Mac 側で `python3 -c "import json;print({k:v.get('options') for k,v in json.load(open('$HOME/.config/opencode/opencode.json'))['provider']['spark']['models'].items()})"`。先に `readlink -f` で実体が dotfiles に解決するか確認する。送信本文の値は未実測 | 2026-10-03 (設定値のみ) |
| DeepSeek 系の上流既定からの差分 | 下のコードブロック 1 (**キー行と RoCE 側の IP を持つ 4 行が出るので画面外に出さない**) | 2026-09-23 |
| Qwen 系の上流既定からの差分 | 下のコードブロック 2 | 2026-09-06 |
| L1 の再計測 | 「L1: サーバ単体 (2026-09-05)」の `bench.py` 2 本をそのまま打つ。**前提が 2 つある**: DeepSeek 系 (Vision-Exp) を配信中であることと、`/tmp/spark.key` を書き直してあること (無認証でも中身は何でもよいが、ファイルが無いと `bench.py` が exit する) | 2026-09-05 |

表に入らないもの。いずれも複数行にわたるか、表のセルでは `|` をエスケープしないと書けないパイプを含む。**表のセルにはパイプを含むコマンドを書かず、ここに番号を付けて置く** (エスケープした `\|` はコピーするとパイプにならない)。1 つのフェンスに 1 つの番号を振る。

```bash
# 1. .env.dspark と配布既定の差分
# 出力に VLLM_API_KEY と、IP を持つ 4 行 (MASTER_ADDR / VLLM_HOST_IP /
# WORKER_HOST / WORKER_VLLM_HOST_IP) が混じる。証跡として貼らない。
ssh -n spark-head 'cd ~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark && diff <(grep -E "^[A-Za-z0-9_]+=" .env.dspark.example | sort) <(grep -E "^[A-Za-z0-9_]+=" .env.dspark | sort)'
```

```bash
# 2. Qwen の .env と配布既定の差分。行の差は 6 か所出るが、うち IB_GID_INDEX は
# 値が両側とも 3 で末尾コメントだけが違う (表の「5 キー」は値が違うものの数)。
# 「書いていない上流キー」2 つは .env.sample 側にしか無い行として出る。
ssh -n spark-head 'cd ~/Qwen3.8-Flash-Next-Dual-DGX-Sparks && diff <(grep -E "^[A-Za-z0-9_]+=" .env.sample | sort) <(grep -E "^[A-Za-z0-9_]+=" .env | sort)'
```

```bash
# 3. 推論中に busy なコアと、そのコアの実効クロック (ノード上で実行)
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
# 4. V4.1 EXL3 レシピの .env と配布既定の差分 (キー名だけを出す。値に IP を含む行があるので値は出さない)
# 行頭の < は配布既定、> は当方の値。2026-09-30 時点は HF_HUB_ENABLE_HF_TRANSFER (> だけ) と LANGUAGE_MODEL_ONLY / LONG_PREFILL_TOKEN_THRESHOLD / MAX_NUM_BATCHED_TOKENS / WEIGHT_SYNC / WORKER_CX7_IB / WORKER_CX7_IF / WORKER_USER (< と > の両方) の 8 キーが出る
ssh -n spark-head 'cd ~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks && diff <(grep -E "^[A-Za-z0-9_]+=" .env.example | sort) <(grep -E "^[A-Za-z0-9_]+=" .env | sort) | grep -E "^[<>]" | sed -E "s/=.*//" | sort -u'
```

```bash
# 5. V4.1 EXL3 の本体の重みが revision 固定の HF API とサイズで一致するか (head で実行。worker は DIR を ~/.cache/dsv41-flash-exl3/model に)
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
# 6. /v1/responses が Responses API の content パーツ (input_text) を受けるか。
#    200 なら head のパッチが効いている。400 なら当たっていない (→「既知の制約」12)。
curl -s -o /dev/null -w '%{http_code}\n' -m 60 http://spark-head.local:8888/v1/responses \
  -H 'Content-Type: application/json' \
  -d '{"model":"DeepSeek-v4.1-Flash-EXL3","store":false,"stream":false,"max_output_tokens":24,
       "input":[{"type":"message","role":"user","content":[{"type":"input_text","text":"say OK"}]}]}'
```

```bash
# 7. HF 側の Qwen3.8-Flash-Next-NVFP4 の main が指す revision (Mac でも head でも打てる)
#    fab0aecb… 以外を返したらキャッシュより先に進んでいる (→「重みの検証」)
curl -s https://huggingface.co/api/models/nvidia/Qwen3.8-Flash-Next-NVFP4 | python3 -c 'import json,sys;print(json.load(sys.stdin)["sha"])'
```

```bash
# 8. CPU のトポロジと各コアの cpufreq (worker は「worker に入る」節経由で同じものを打つ)
ssh -n spark-head 'lscpu | grep -E "Model name|^CPU\(s\)"; for c in 0 5 10 15; do echo "cpu$c $(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_driver) $(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_governor) $(cat /sys/devices/system/cpu/cpu$c/cpufreq/cpuinfo_max_freq)"; done'
```

```bash
# 9. head のパッチ (patch_responses_content_parts.py) が起動時に走ったか。最後の 1 行を読む
#     patched: / already patched: なら適用済み、FATAL なら当たっていない (→「既知の制約」12)
ssh -n spark-head 'docker logs dsv41-exl3-head 2>&1 | grep "dsv41-responses-parts" | tail -1'
```

```bash
# 10. 画像入力が通るか。緑一色の 8x8 PNG を data URL で渡し、答えに「緑」が含まれれば exit 0
#     M を配信名に差し替える。陰性対照は画像を外して同じ質問を送ること (「緑」以外を答えて exit 1 になる)。
#     2026-10-04 に GLM 系で、画像ありが exit 0、画像なしが「赤色」で exit 1 だった。赤一色の画像は
#     画像なしでも「赤」と答えたので対照にならない
M=GLM-5.3-Flash-EXL3
B=iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEElEQVR4nGNgOMCAHQ0tCQDB1jAB4smq5AAAAABJRU5ErkJggg==
curl -s http://spark-head.local:8888/v1/chat/completions -H 'Content-Type: application/json' -d "{\"model\":\"$M\",\"max_tokens\":512,\"temperature\":0,\"chat_template_kwargs\":{\"enable_thinking\":false},\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"image_url\",\"image_url\":{\"url\":\"data:image/png;base64,$B\"}},{\"type\":\"text\",\"text\":\"この画像は何色ですか。色の名前を 1 語だけ日本語で答えてください。\"}]}]}" \
  | python3 -c 'import json,sys; c=json.load(sys.stdin)["choices"][0]["message"]["content"].strip(); print(repr(c)); sys.exit(0 if "緑" in c else 1)'
```
