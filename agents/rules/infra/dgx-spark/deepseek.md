---
# 常駐読み込みさせないためのマーカー (このパスにマッチするファイルは存在しない)。
# 本ファイルは必要になったときに Read で参照する。
paths:
  - "__read-on-demand-only__"
---

# DeepSeek 系 (DGX Spark)

- 種別: 環境リファレンス (系統別)
- 対象読者: 別セッション・別マシンで作業するエージェント (Claude Code / Codex / OpenCode)
- 最終確認: 2026-09-23 (認証の状態は 2026-09-06)
- 共通の前提 (接続・切り替え・障害時・既知の制約): `dgx-spark.md`

DeepSeek 系は、DSpark レシピで配信する Vision-Exp 版と 0731 版を指す。V4.1 EXL3 系と 1017 系は含まない。本文は Vision-Exp 版の話で、0731 版との違いは「0731 版で配信する」にまとめてある。

## 用語

| 名前 | 意味 | 定義箇所 | 生成者 | 消費者 |
| --- | --- | --- | --- | --- |
| Vision-Exp | `deepseek-ai/DeepSeek-V4-Flash-Vision-Exp` の略。画像入力が使える | 「構成」 | 上流のチェックポイント | vLLM |
| 0731 | `deepseek-ai/DeepSeek-V4-Flash-0731` の略。テキスト専用で、Vision-Exp よりドラフタの受理率が高く decode が速い | 「0731 版で配信する」 | 上流のチェックポイント | vLLM |
| `~/dspark-0731` | 0731 版を起動する作業ディレクトリ。レシピの git worktree で `70a7cc4` に detached で固定し、0731 用の `.env.dspark` を持つ | 「0731 版で配信する」 | 人 (`git worktree add`) | 人 / 起動スクリプト (worker 側の配布先も同じパス) |
| `.env.dspark` | レシピの設定を集約した 1 枚。git 管理外 (`.gitignore` 済み)。Vision-Exp 版と 0731 版に 1 枚ずつある。共通の手順 (worker に入る・RoCE) も `WORKER_HOST` と `NCCL_IB_HCA` をここから読む | head の `~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark/` と `~/dspark-0731/` | 人 (`.env.dspark.example` から複製) | 起動・停止・検証スクリプト |
| `stop` / `start` | `stop-deepseek-v4-flash-dspark.sh` / `start-deepseek-v4-flash-dspark.sh` の略記。他の 4 系統の `stop.sh` / `start.sh` とは別物。2 つの版は同じスクリプトを別の作業ディレクトリで打つ | 「起動と判定」 | 上流 | 人 |

## 構成

レシピの上流は [MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark](https://github.com/MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark) で、head の `~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark` に clone してある。下の表は Vision-Exp 版の値で、出所は「KV キャッシュ」「画像入力」「レシピの commit」「書いていない上流キー」の 4 行を除いて `.env.dspark` である。

| 項目 | 値 |
| --- | --- |
| チェックポイント (`DSPARK_MODEL_OFFICIAL` / `DSPARK_REVISION`) | `deepseek-ai/DeepSeek-V4-Flash-Vision-Exp` @ `86f746b36186f0e567729a5c06a8c918caba82a9`。起動スクリプトと `validate-dspark-config.sh` の上流既定 `DEFAULT_OFFICIAL_REVISION` と同値なので、行を消しても同じ revision になる |
| 配信名 (`SERVED_MODEL_NAME`) | `deepseek-v4-flash-vision-exp` |
| コンテキスト上限 (`MAX_MODEL_LEN`) | 1,048,576 トークン (ネイティブ。YaRN 不要)。OpenCode の `limit.context` は 524,288 でサーバの半分 (→ `dgx-spark.md`「OpenCode」) |
| 同時リクエスト上限 (`MAX_NUM_SEQS`) | 6 リクエスト。超過分はエラーにならずキューで待つ |
| 投機デコード (`MTP_NUM_TOKENS`) | DSpark、draft 6 トークン |
| メモリ確保率 (`GPU_MEMORY_UTILIZATION_TEXT`) | 0.835 (意味は `dgx-spark.md`「メモリの使われ方」)。`GPU_MEMORY_UTILIZATION` を書いても効かない。起動スクリプトが `GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION_TEXT:-0.835}"` と無条件に代入して捨てる |
| KV キャッシュ | `nvfp4_ds_mla` (`docker-compose.dspark.yml` が `--kv-cache-dtype` に直書き。`.env.dspark` にキーは無い) |
| 画像入力 (`LIMIT_MM_PER_PROMPT`) | 1 プロンプトあたり 8 枚 (compose の既定)。2026-09-23 に 8x8 の赤い PNG を data URL で `/v1/chat/completions` に渡し、「赤」と答えた。ViT とアライナは起動時の `hotfix-dsv4-vision-exp.py` が入れる。動画は配線されていない (重みに動画エンコーダが無く、GIF は静止画 1 枚になる)。増やすときは `LIMIT_MM_PER_PROMPT=image=N` と書く。`{"image":N}` は `source` で引用符が落ちて `{image:N}` になり、argparse の `json.loads` が弾く |
| 既定の reasoning (`DEFAULT_THINKING`) | `low` (取りうる値: `off` / `low` / `high` / `max`)。リクエスト単位の指定が優先し、OpenCode は `reasoningEffort` (`high`) を、`bench.py` は `chat_template_kwargs` を明示する。リクエストの語彙は別で、`off` は送れない (→「reasoning effort の語彙」) |
| 認証 (`VLLM_API_KEY`) | 空。compose がこのキーをコンテナに渡すしくみで、空なので無認証で上がる (2026-09-06 に確認。8888 の扱いは `dgx-spark.md`「動いているもの」)。認証を戻すときは 1Password の正本 `op://Personal/DGX Spark vLLM API Key/credential` の値を人が書き込み、`stop` → `start` する。Vision-Exp 版と 0731 版の `.env.dspark` の両方に入れる。クライアント側は `dgx-spark.md`「API キーの流れ」 |
| コンテナ | 名前は `deepseek-v4-flash-vllm-dspark-1` (2 つの版で同じ)。restart policy は `unless-stopped` |
| コンテナイメージ | `ghcr.io/anemll/dspark-vllm-gx10:0.1.1@sha256:a83948492cf13df455170fb42885f5ef4db54fefe0feff0f841ecbff464ac9d8` (DSpark ランタイムの配布元 Anemll) |
| レシピの commit | `97e8733` (2026-09-23 に `git pull --ff-only` で追従)。上流の先行分は変化が速いので数を書かず、「依拠する外部事実 (DeepSeek 系)」で見る |
| 重み (`du -sh`、2026-09-06) | head 158 GiB / worker 157 GiB (両ノードの `~/.cache/huggingface/hub/`) |
| 書いていない上流キー | 8 つ。すべて上流既定 `0` の opt-in で、書かないことが現行動作である (出所は `.env.dspark.example` と上流の CHANGELOG)。投機・注意機構の 6 つ (`DSPARK_ENABLE_ROPE_SWA_FIX` / `DSPARK_ENABLE_DSPARK_SWA_PREFIX` / `DSPARK_ENABLE_DSML_RECOVERY` / `DSPARK_ENABLE_MXFP4_INDEXER_CACHE` / `DSPARK_ENABLE_C128A_PREFILL_CACHE` / `DSPARK_ENABLE_ISSUE144_EFFORT_ALIGN`) は、上流が「有効化の前に実機の A/B を通せ」と書くので 1 つずつ測ってから採る。refusal-direction の実行時射影の 2 つ (`DSV4_ABLATE_LAMBDA` / `DSV4_ABLATE_LAYERS`) は `ABLITERATED=0` で無効で、有効化には HF の gated 規約への同意が要る。ほかにコメントアウトの形でだけ現れるキーが 2 つある (`DSPARK_ABLATE_SOURCE_FILE` / `NCCL_GIN_ENABLE`)。後者を `0` にすると NCCL の comm-init が約 2 分から 13 秒に縮む (上流計測、2026-09-05、帯域は不変) が、当方の起動は完走しているので入れていない |

### 上流既定からの差分

サイト固有の値 (IP・NCCL のデバイス名・API キー) を除くと、上流の配布既定から変えているのは次の 3 つである。取り方は「依拠する外部事実 (DeepSeek 系)」のコードブロック 1。

| キー | 値の意味 | 既定 | 現在 | 採用根拠 | 効果 |
| --- | --- | --- | --- | --- | --- |
| `DSPARK_MAX_INFLIGHT_PREFILLS` | 同時に走らせる prefill の件数 | 1 | 2 | 上流 issue #217 の A/B | 上流計測 (2 ノード TP=2・`LONG_PREFILL_TOKEN_THRESHOLD=1024`、cold boot 3 回の ABA)。4 並列 8K で公平性の開き 1.50〜1.57 倍 (既定 1.53 倍)、preemption は両条件 0、TTFT の開き 2.1〜2.4 倍 (既定 4.1 倍)。4 並列 32K のバーストでは開きが 3.0〜3.3 倍に広がる (既定 2.1 倍)。head の `docs/CLAUDE/ab-results-2026-09-03.md` の古い A/B は、上流が undercounting のスケジューラで走ったとして取り下げている。自環境では未計測 |
| `DSPARK_ENABLE_SP_INDEXER` | 0 = 無効 / 1 = 有効 | 0 | 1 | 上流の最終構成に追従 | 自環境では未計測 |
| `DSPARK_ENABLE_DEEPGEMM_SM121_ALIAS` | 0 = 無効 / 1 = 有効 | 0 | 1 | 上流の最終構成に追従 | 自環境では未計測 |

差分を取り直すときの正規表現の罠が 2 つある。`grep -E '^[A-Z_]+='` は数字を含む `DSPARK_ENABLE_DEEPGEMM_SM121_ALIAS` を落とす (90 行中 75 行しか拾わない) ので `^[A-Za-z0-9_]+=` を使う。キー行を伏せるための `grep -vi token` は `MTP_NUM_TOKENS` も巻き込む。

### メモリ

2026-09-23 に起動 15 分後の無負荷で、確保 101.1 / 101.1 GiB (`nvidia-smi` の 103,540 / 103,530 MiB)、`MemAvailable` 6.8 / 7.1 GiB だった (head / worker)。期待値 121.7 × 0.835 = 101.6 GiB の近傍で、確保率による先取りであって不足ではない。他系統との比較は `dgx-spark.md`「メモリの使われ方」にある。

swap 使用 (4.3 / 5.4 GiB) は直前に配信していた系統で動く。この値は Qwen 系を 44 時間配信した直後のもので、前の系統が押し出したページを含む。swap の量を系統の特性として読まない。

## 起動と判定

head で起動すると、`.env.dspark` を worker へ SSH で配り直して両ランクを立ち上げるので、worker でコマンドを打つ必要はない。head から worker へは、head で生成して worker に登録済みの鍵 `~/.ssh/id_ed25519` で `WORKER_HOST` (RoCE 側のアドレス) に入る。

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

- `start` は `/health` が通るまで待ち、`DeepSeek V4 Flash DSpark is running` を出して戻る。エージェントのシェル実行からは `dgx-spark.md`「長い処理を ssh から切り離す」の型で流す
- 12 分を超えても上がらなければ、worker 側だけ落ちていることがあるので両ランクを見る
- 設定を変えたら `docker compose restart` を使わず `stop` → `start` で作り直す。起動時にコンテナ内の vLLM へ多数のパッチを当てるので、restart では古いバイト列が残る
- `no usable RoCEv2 GID` で落ちたら RoCE 2 本目の IP か MTU を疑う (→ `dgx-spark.md`「ネットワーク」)

正常稼働の判定は 2 段で行う。

1. `curl -fs http://spark-head.local:8888/health` が exit 0 なら API は生きている
2. `./smoke-deepseek-v4-flash-dspark.sh` が exit 0 なら合格 (`set -euo pipefail` で書かれ、失敗時は exit 1 か 2)

## reasoning effort の語彙

3 経路とも弾くのはスキーマ (pydantic の Literal) で、Qwen 系のようなチャットテンプレートの `raise_exception` ではない。2026-09-23 に 3 経路で実測した。セルは HTTP ステータスである。

| 値 | `/v1/messages` | `/v1/chat/completions` (OpenCode) | `/v1/responses` |
| --- | --- | --- | --- |
| `low` / `medium` / `high` / `xhigh` / `max` | 200 | 200 | 200 |
| `none` / `minimal` | 400 (スキーマ) | 200 | 200 |
| `off` | 400 | 400 | 400 |
| 語彙外 (`bogus` など) | 400 | 400 | 400 |
| 指定なし | 200 (既定 `low`) | 200 (既定 `low`) | 200 (既定 `low`) |

- 確認は `dgx-spark.md`「依拠する外部事実」の reasoning effort の行の形で、モデル名を `deepseek-v4-flash-vision-exp`、陽性対照を `bogus`、陰性対照を `high` にする。`high` も `medium` も受理するので、他系統の陽性対照は流用できない
- 400 の本文が受理語彙を名乗る。`/v1/messages` は `Input should be 'low', 'medium', 'high', 'xhigh' or 'max'`、他の 2 経路は `Input should be 'none', 'minimal', 'low', 'medium', 'high', 'xhigh' or 'max'`。2 語ずれるのはスキーマが別クラスだからである (`AnthropicOutputConfig.effort` / `reasoning_effort` / `reasoning.effort`)
- `none` を `/v1/messages` だけが弾く非対称は Qwen 系・V4.1 EXL3 系と同じ構造である (→ `dgx-spark/qwen.md`「reasoning effort の語彙」)
- `off` はリクエストでは送れない。`DEFAULT_THINKING` はサーバ起動時の既定のキーで語彙が別である。混同すると 3 経路すべてで 400 になる
- OpenCode が送る `high` は 3 経路とも 200 を実測済み
- 実効的な深さは `low` / `high` / `max` の 3 段である。compose の起動チェーンが `vllm/tokenizers/deepseek_v4.py` にパッチを当て、`max` / `xhigh` を `max`、`high` を `high`、それ以外を `low` に落とす。ソースから読んだもので、出力の深さの差は測っていない。パッチは encoder のコピーと同じ条件分岐の中にあり、起動ログに `WARN: encoding_dsv4.py not found` が出た起動では当たっていない (`97e8733` の起動では 0 件)

## 使える API

3 経路すべてが通る (2026-09-23 に curl で実測)。OpenCode を通した疎通とツール呼び出しは未実測である。

| 経路 | 用途 | 実測 |
| --- | --- | --- |
| `/v1/chat/completions` | OpenCode | `smoke-deepseek-v4-flash-dspark.sh` が 6 並列で 6/6 成功 (exit 0)。画像入力も確認 |
| `/v1/messages` | Anthropic Messages API | `stop_reason: end_turn` で返る。このイメージの vLLM は Anthropic ルータをフラグ無しで持つ |
| `/v1/responses` | Responses API | `input_text` パーツが 200 で通る。V4.1 EXL3 系で要るサーバ側のパッチは要らない。`--tokenizer-mode deepseek_v4` で別のトークナイザを通るためである (→ `dgx-spark/v41-exl3.md`「既知の制約 (V4.1 EXL3 系)」) |

## レシピを更新する

`.env.dspark` は追跡外なので `git pull` では消えない。`git pull` は稼働中のコンテナが読まないファイルしか触らないので、他系統を配信したままでも打てる。更新するのは Vision-Exp 版の clone だけで、`~/dspark-0731` は更新しない (→「既知の制約 (DeepSeek 系)」1)。

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

- 最後の `diff` はキー名だけを出し、上流のキーの増加を見る。`<` 側が「書いていない上流キー」で、増えていたら「構成」の同名の行を直す。`>` 側は `VLLM_API_KEY` (空値で保持) だけが正しい
- `scripts/ci-validate.sh` は配信中に流さない。上流の CPU テスト一式を呼ぶので、`MemAvailable` が数 GiB の配信中のノードは固まるおそれがある (→ `dgx-spark.md`「既知の制約」の、配信中のノードで重い処理に上限を付ける項)。停止中に流す

更新後は次の 6 点で悪化していないことを確かめる。2 段判定は起動の可否しか見ないので足りない。2 と 3 は停止する前に取っておき、起動後と突き合わせる。

1. 起動の 2 段判定 (`/health` → smoke が exit 0)
2. `/v1/models` の `id` と `max_model_len` が `deepseek-v4-flash-vision-exp` / 1,048,576。`curl -s http://spark-head.local:8888/v1/models | python3 -c 'import json,sys; d={m["id"]:m.get("max_model_len") for m in json.load(sys.stdin)["data"]}; print(d); sys.exit(0 if d.get("deepseek-v4-flash-vision-exp")==1048576 else 1)'` が exit 0 で合格。`created` と `permission` は起動のたびに変わるので全文比較に使わない
3. reasoning effort の語彙 (→「reasoning effort の語彙」。3 経路とも打つ)
4. `docker inspect deepseek-v4-flash-vllm-dspark-1 --format '{{.HostConfig.RestartPolicy.Name}}'` が両ノードで `unless-stopped`
5. `/v1/responses` が `input_text` を 200 で受ける (「依拠する外部事実 (DeepSeek 系)」のコードブロック 2)
6. 画像入力が通る (`dgx-spark.md`「依拠する外部事実」の画像入力のコードブロックの `M` を `deepseek-v4-flash-vision-exp` にする)

次の 2 つは異常ではない。

- `./validate-dspark-config.sh` の `cudagraph capture size` は実効値ではない。`MAX_NUM_SEQS × (MTP_NUM_TOKENS + 1)` をそのまま出すが、compose は 8 の倍数へ切り上げて渡す (表示 6 × 7 = 42、実際は 48)。不合格の根拠にしない
- 起動ログの先頭の `WARN: serving an UNAUTHENTICATED API on 0.0.0.0:8888` は、`VLLM_API_KEY` が空の構成への警告で、起動は止まらない。この警告が消えたら、意図せず認証が付いたことを疑う (→ `dgx-spark.md`「API キーの流れ」)。`.env.dspark` の mode への `chmod 600` の警告は、秘密キーを 1 つも設定していないので出ない

戻すときは `git checkout <旧 sha>` (上のコードブロックが出した「戻し先」) してから `stop` → `start` する。detached HEAD になるので、復帰は `git checkout main`。重み・イメージ・`.env.dspark` は変わらないので戻せる。

## 0731 版で配信する

テキスト専用の 0731 を同じスクリプトで配信する。画像入力を手放す代わりに decode が速い。

起動は `~/dspark-0731` から行う。現行 `main` (`97e8733`) の起動スクリプトは Vision-Exp 専用で、`MTP_NUM_TOKENS` に「5 以上かつ 3 の倍数」を課し (Vision-Exp の `n_predict=3` に合わせた検査)、vision のホットフィックスを無条件に当てる。0731 は `n_predict=1` で k=5 が本来の形なので、`main` からは起動できない。`~/dspark-0731` は 0731 を配信していた当時の `70a7cc4` に detached で固定した worktree で、0731 用の `.env.dspark` (mode 600) を持つ。ノードを作り直したら同じ commit で作り直す。

| 項目 | 0731 版 | Vision-Exp 版との違い |
| --- | --- | --- |
| 作業ディレクトリ | head の `~/dspark-0731` @ `70a7cc4` | Vision-Exp 版は `~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark` @ `97e8733` |
| チェックポイント | `deepseek-ai/DeepSeek-V4-Flash-0731` @ `9e165c30e2704aec5d9d593cce3eebd58bbef1cb` | 別チェックポイント |
| 重み (`du -sh`) | head 156 GiB / worker 156 GiB。HF キャッシュの revision は両ノードで同一 (2026-09-23 確認) | — |
| 配信名 | `deepseek-v4-flash-0731` | 別名。`opencode.json` に宣言済み (`reasoningEffort` は `high`、`limit.context` は 524,288) |
| 投機デコード (`MTP_NUM_TOKENS`) | DSpark、draft 5 トークン | Vision-Exp 版は 6 |
| 画像入力 | 使えない | — |
| コンテナ名 | `deepseek-v4-flash-vllm-dspark-1` | 同じ。どちらが動いているかは `/v1/models` の配信名で見る |
| worker 側の配布先 | worker の `~/dspark-0731` (`WORKER_DIR` が空なので head と同じパス) | 別ディレクトリなので Vision-Exp 版の配布物を上書きしない |
| 同じもの | イメージ (同じ digest)、`MAX_MODEL_LEN` 1,048,576、`MAX_NUM_SEQS` 6、`GPU_MEMORY_UTILIZATION_TEXT` 0.835、チューニング 3 キー、`VLLM_API_KEY` 空、restart policy `unless-stopped` | — |
| cold start | health まで約 8.5 分 (2026-09-23 実測 507 秒) | Vision-Exp 版は約 7〜8 分 |

- 起動・停止・判定は同じスクリプトと 2 段判定を `~/dspark-0731` で打つ。2026-09-23 に smoke が 6/6 で通った
- reasoning effort の語彙は Vision-Exp 版と同じ (2026-09-23 に 3 経路で全値を実測)。`/v1/responses` は `input_text` をパッチ無しで 200 で受ける
- Vision-Exp 版へ戻すときは、`~/dspark-0731` で `stop` してから Vision-Exp 版の clone で `start` する (→ `dgx-spark.md`「系統の切り替え」)。重みと `.env.dspark` は版ごとに別で、イメージは読むだけなので、切り替えで書き換わるものは無い

### decode の比較

2026-09-23、無負荷、各条件 3 回の中央値で、0731 版は Vision-Exp 版より次の割合だけ速い。tok/s・tok/step・step 時間の絶対値と計測方法は `dgx-spark.md`「decode の分解 (2026-09-23)」にある。

| 条件 | 0731 の差 (%) |
| --- | --- |
| コード、thinking off、短文 | +15 |
| コード、32K 文脈 | +20 |
| コード、100K 文脈 | +18 |
| 日本語の散文、thinking off | +26 |
| 数の列挙、thinking off | +12 |
| 6K フィラー + コード指示、thinking `low`、256 トークン強制 | +5 |
| 同じ入力で自然終了 | +3 |

- thinking off の条件では 12〜26% 速い。1 ステップのトークン数が増え (コード 5.05 → 5.50、散文 1.77 → 2.12)、k が 6 から 5 に減って 1 ステップも 3〜7 ms 軽くなる
- thinking `low` の 2 条件では 3〜5% に縮む。1 ステップのトークン数はむしろ Vision-Exp 版が多く (3.05 対 2.84)、差は 1 ステップが軽いぶんだけである。推論を伴う実負荷での伸びは thinking off ほど大きくないと見込む (推測)
- 上流が同じ機材で記録した比較 (Vision-Exp 側が greedy で −15〜20%、temperature 0.6 で −20〜30%) は thinking off の条件と整合する

## 既知の制約 (DeepSeek 系)

1. **`~/dspark-0731` で `git pull` や `git checkout main` をしない。** Vision-Exp 専用の検査が入り、0731 版が起動しなくなる
2. **`~/dspark-0731` の launcher は `97e8733` の堅牢化を持たない。** 全 ssh の `BatchMode` と `ConnectTimeout`、stop のコンテナ名フィルタのアンカー化などが無いので、worker が途中で応答しなくなると起動がタイムアウトせずに止まり続けうる
3. **`.env.dspark` の控えを作ったら使い終わりに消す。** `.gitignore` が拾うのは `.env.dspark` だけなので、`.env.dspark.bak` のような名前はキー行ごと公開リポジトリの clone にステージされうる

## 依拠する外部事実 (DeepSeek 系)

| 事実 | 確認コマンド | 確認日 |
| --- | --- | --- |
| サービングの設定値 | Vision-Exp 版の clone で `./validate-dspark-config.sh` を打ち、先頭 20 行だけを読む (後に vLLM コマンド全文が数 KB 続く。絞った形は「レシピを更新する」のコードブロック) | 2026-09-23 |
| 上流の先行コミット | `ssh -n spark-head 'cd ~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark && git fetch -q && git rev-list --count HEAD..origin/main && git log --oneline HEAD..origin/main'` | 2026-09-23 |
| 上流既定からの差分 | 下のコードブロック 1 (キー行と RoCE 側の IP を持つ 4 行が出るので画面外に出さない) | 2026-09-23 |
| 配信名と上限 | 「レシピを更新する」の確認 2 | 2026-09-23 |
| reasoning effort の語彙 | `dgx-spark.md`「依拠する外部事実」の reasoning effort の行 (陽性対照 `bogus` / 陰性対照 `high`、3 経路) | 2026-09-23 |
| `/v1/responses` が `input_text` を受けるか | 下のコードブロック 2。200 で合格 (Vision-Exp 版・0731 版とも) | 2026-09-23 |

```bash
# 1. .env.dspark と配布既定の差分
# 出力に VLLM_API_KEY と、IP を持つ 4 行 (MASTER_ADDR / VLLM_HOST_IP /
# WORKER_HOST / WORKER_VLLM_HOST_IP) が混じる。証跡として貼らない。
ssh -n spark-head 'cd ~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark && diff <(grep -E "^[A-Za-z0-9_]+=" .env.dspark.example | sort) <(grep -E "^[A-Za-z0-9_]+=" .env.dspark | sort)'
```

```bash
# 2. /v1/responses が Responses API の content パーツ (input_text) を受けるか。200 で合格。
#    0731 版の配信中は model を deepseek-v4-flash-0731 にする。
curl -s -o /dev/null -w '%{http_code}\n' -m 60 http://spark-head.local:8888/v1/responses \
  -H 'Content-Type: application/json' \
  -d '{"model":"deepseek-v4-flash-vision-exp","store":false,"stream":false,"max_output_tokens":24,
       "input":[{"type":"message","role":"user","content":[{"type":"input_text","text":"say OK"}]}]}'
```
