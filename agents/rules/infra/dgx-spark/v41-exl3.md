---
# 常駐読み込みさせないためのマーカー (このパスにマッチするファイルは存在しない)。
# 本ファイルは必要になったときに Read で参照する。
paths:
  - "__read-on-demand-only__"
---

# DeepSeek-V4.1-Flash EXL3 / V4.1 EXL3 系 (DGX Spark)

- 種別: 環境リファレンス (系統別)
- 対象読者: 別セッション・別マシンで作業するエージェント (Claude Code / Codex / OpenCode)
- 最終確認: 2026-10-04 (レシピの更新手順と公式パッチの参照)。構成・起動・effort の語彙は 2026-09-15、`/v1/responses` は 2026-09-17、画像入力は 2026-09-30
- 共通の前提 (接続・切り替え・障害時・既知の制約): `agents/rules/infra/dgx-spark.md`

`deepseek-ai/DeepSeek-V4.1-Flash` を EXL3 2.9 bpw に量子化したチェックポイントを、EXL3 を後付けした vLLM の TP=2 で配信する。他の系統とは別リポジトリ・別イメージ・別スクリプトである。2026-09-15 に起動の 3 段判定、OpenCode (opencode 1.18.18) からの生成、effort の語彙を確かめ、2026-09-17 に `/v1/responses` の生成とツール呼び出しを確かめた (head のパッチが前提 →「既知の制約 (V4.1 EXL3 系)」1)。V2 の OpenCode からは試していない。

## 用語

Engram・EXL3・memguard・DSpark・`fp8_ds_mla`・`.env`・`start.sh` は複数の系統にまたがるので `dgx-spark.md`「用語・成果物一覧」にある。

| 名前 | 意味 | 定義箇所 | 生成者 | 消費者 |
| --- | --- | --- | --- | --- |
| DeepSeek-V4.1-Flash EXL3 | `Mia-AiLab/DeepSeek-V4.1-Flash-EXL3-2.9bpw` の略。配信名は `DeepSeek-v4.1-Flash-EXL3`。量子化しない vision tower を持ち、画像入力が使える | 「構成」 | 上流のチェックポイント | vLLM |
| V4.1 EXL3 レシピ | この系統のレシピ。起動・停止・pack は `start.sh` のサブコマンド | head の `~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks/` | 上流 (`git clone`) | 人 |
| `dsv41-exl3-head` / `dsv41-exl3-worker` | コンテナ名。head と worker で名前が違う | レシピの `start.sh` | `start.sh` | `docker` |
| stamp (`dsv41.recipe.stamp`) | レシピの入力ファイル群のハッシュ。イメージのラベルとずれると起動時にビルドが走る (→「導入の落とし穴」6) | `start.sh` の `overlay_recipe_hash` | `start.sh` | `start.sh` の起動前判定 |
| slim dir | Engram の読み込みに要るファイルだけを集めたディレクトリ (→「構成」の Engram の流れ) | head の `~/.cache/vllm-dsv41-flash-exl3/engram-src/` | `scripts/prepare_engram_src.py` | pack / head のコンテナ / worker への rsync |
| pack | Engram を rank ごとの行ファイル `engram-l{1,14}-r<rank>of2.bin` に書き出す操作 | 両ノードの `~/dsv41-engram/` | `./start.sh pack` | vLLM (`/engram-packed`) |
| `~/.cache/dsv41-image` | イメージを手で取ったときの blob 置き場。消してよい (→「残骸」) | 両ノード | 「イメージを手で取る」 | なし (再読み込みのときだけ) |
| `patch_responses_content_types.py` / `patch_responses_content_parts.py` | `/v1/responses` の `input_text` パーツを tokenizer に受けさせるパッチ。前者は上流公式、後者は `b9c49e9` 用のローカル backport で、どちらか 1 つを使う | 公式はレシピの `overlay/`、ローカルは head の `~/dsv41-local/` | 上流 / 人 (全文は「既知の制約 (V4.1 EXL3 系)」1) | `start.sh` のパッチループ経由でコンテナ |

## 構成

値の出所はレシピの `.env` と起動ログの `config:` 行である。レシピ・量子化・重み・pack・既定の reasoning・イメージ・コンテナ名・上流既定からの差分の行は HF API・`files/` 配下・`docker inspect`・`.env.example` との差分から取った。認証・ディスク・メモリの行は出所を行の中に書く。

| 項目 | 値 |
| --- | --- |
| レシピ | head の `~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks` @ `b9c49e9` |
| 量子化 | EXL3 の平均 2.9 bpw。routed experts は 3 bit (層 18〜22 だけ 2 bit)、shared experts は 5 bit / 4 bit、attention は 5 bit (レシピの `files/exl3_k_map.json`) |
| 重み (本体) | `Mia-AiLab/DeepSeek-V4.1-Flash-EXL3-2.9bpw` @ `64ba41b6c916a587db06eae2e19b7845f7be6e6b`。49 ファイル / safetensors 39 本 / 196.2 GiB。head はレシピ直下の `model/`、worker は `~/.cache/dsv41-flash-exl3/model/` (HF キャッシュは使わない)。HF の org 表記 `Mia-AiLab` と GitHub の `MiaAI-Lab` は綴りが違う (どちらも実在する) |
| 重み (Engram) | `deepseek-ai/DeepSeek-V4.1-Flash` @ `dba1be0a40aa45a94ad051997016db3960a90277` の shard 47 / 48 (各 94.6 GiB) と `model.safetensors.index.json` と `config.json`。head はレシピ直下の `engram-src/`、worker は `~/.cache/dsv41-flash-exl3/engram-src/`。1017 系の Engram とは sha256 が違い、使い回せない |
| pack | head が rank 0、worker が rank 1 の 2 本ずつを、自分の Engram コピーから `~/dsv41-engram/` に作る (1 本 47.2 GiB、root 所有)。コンテナに `/engram-packed` として mount される |
| ディスク (`du -sh`、2026-09-15) | 197 GiB (EXL3) + 190 GiB (Engram) + 95 GiB (pack)、両ノードで同じ。ほかにイメージの blob 9.1 GiB が両ノードの `~/.cache/dsv41-image/` にある |
| 配信名 (`SERVED_MODEL_NAME`) | `DeepSeek-v4.1-Flash-EXL3` (大文字を含む) |
| コンテキスト上限 (`MAX_MODEL_LEN`) | 600,000 トークン。OpenCode の `limit.context` も 600,000 で一致 |
| 同時リクエスト上限 (`MAX_NUM_SEQS`) | 2 リクエスト (5 系統で最少。超過分はキューで待つ) |
| 投機デコード (`SPEC_METHOD` / `DSPARK_TOKENS`) | DSpark (draft はチェックポイント内の `mtp.*`)、draft 3 トークン |
| KV キャッシュ | vLLM が `fp8_ds_mla` を自分で選ぶ (`--kv-cache-dtype` は渡さない)。プールは `KV_CACHE_MEMORY_BYTES` で 2.5 GiB に固定 |
| `GPU_MEM_UTIL` | 0.88。予算ではなく、vLLM が起動時に空きメモリと比べる検査値 |
| メモリ (head / worker。2026-09-30、画像入力を有効にして smoke と画像 2 件を流した後) | 推論サーバの確保 104.4 / 104.4 GiB (`nvidia-smi` の 106,907 MiB)、`MemAvailable` 4.8 / 5.9 GiB、swap 4 / 7 GiB。確保率ではなく重み (起動ログで 99.8 GiB、vision tower を含む) と固定の KV プールを確保するので、`121.7 × 0.835` の式は当てはまらない。残りは先取りではなく実際の余裕 (→「既知の制約 (V4.1 EXL3 系)」2) |
| 画像入力 | 使える (`LANGUAGE_MODEL_ONLY=0`、`LIMIT_MM={"image":100}`)。条件は下の「画像入力」 |
| 既定の reasoning | thinking ON。effort を送らないときは `high` (レシピの `files/chat_template.jinja` の `reasoning_effort` の既定値) |
| 認証 | なし。`.env` の `VLLM_API_KEY` がコメントアウトのままで、起動ログの `auth` 行が `none (VLLM_API_KEY empty)` (2026-09-15)。付けるときは同じ行に値 (正本は `op://Personal/DGX Spark vLLM API Key/credential`) を入れて停止 → 起動する (未検証)。クライアント側は `dgx-spark.md`「API キーの流れ」 |
| コンテナイメージ | `ghcr.io/miaai-lab/deepseek-v4.1-flash-exl3-2x-dgx-sparks:2.9bpw` (Id `sha256:4cdba4e946da2d19bf5b5a20c6d3a1a4bf421fa4d6db5082f271a986168176cb`、展開後 22.5 GB (`docker images` の 10 進表示)、arm64、ラベル `dsv41.recipe.stamp` = `8c01a8543ff7e7b222ae1cd46b8be5051838dc7a7b075b4e647f3785c0429584`)。両ノードに配置済み |
| コンテナ名 | `dsv41-exl3-head` / `dsv41-exl3-worker`。restart policy は両方 `no` で、ノードを再起動すると上がらない (2026-09-15 実測) |
| 上流既定からの差分 | 手元の `.env.example` (`b9c49e9`) に対して 7 キーと 1 行。下の「上流既定からの差分」 |

**画像入力。** `MAX_NUM_BATCHED_TOKENS` は 1536 以上が必須である。1024 のままだと重みロードの数分後に `compute_mm_encoder_budget` の `ValueError` で起動が止まる (画像 1 枚の 1,025 トークンが 1 チャンクに収まる必要がある。上流 README)。上流が「`MAX_NUM_BATCHED_TOKENS` との差を 256 以上空ける」と規定するので、`LONG_PREFILL_TOKEN_THRESHOLD` は 1280 にしてある。

- 実測 (2026-09-30): 左半分が青・右半分が黄の 64x32 PNG を data URL で `/v1/chat/completions` に渡すと「左: 青、右: 黄色」と答えた (prompt 239 トークン)。陰性対照の画像なしでは「左: 赤、右: 青」と外れた (prompt 35 トークン)
- GB10 では画像内の双方向 attention が無効になる (レシピの `patch_sm120_block64.py` が sliding window を 128 に固定する)。上流は OCR と複数画像の取り違えへの影響を測れなかったとしている。当方も合否判定しか確かめておらず、元のチェックポイントとの品質比較は無い

**上流既定からの差分。** 確かめ方は「依拠する外部事実 (V4.1 EXL3 系)」のコードブロック 1。

- `WORKER_USER=skanehira` (上流は作者のユーザー名)
- `WORKER_CX7_IF=enp1s0f1np1` / `WORKER_CX7_IB=rocep1s0f1` (上流の作者機は worker が `f0`、当方は両ノードとも `f1`)
- `WEIGHT_SYNC=rsync` (上流既定は `nfs`)
- 画像入力の `LANGUAGE_MODEL_ONLY=0` / `MAX_NUM_BATCHED_TOKENS=1536` / `LONG_PREFILL_TOKEN_THRESHOLD=1280`。上流 `8404ac7` の `.env.example` は 3 キーとも当方と同じ値、2026-10-04 時点の上流 `main` (`6f7d159`) は `LONG_PREFILL_TOKEN_THRESHOLD` だけがコメントアウトされている
- 1 行 `HF_HUB_ENABLE_HF_TRANSFER=0` (head に `hf_transfer` が無い)

**`WEIGHT_SYNC=rsync` の理由。** 上流既定の NFS では worker が head の export を RoCE (上流は CX7 = ConnectX-7 と呼ぶ) 越しに読み、head が配信中の単一障害点になる。pack した Engram はどちらでもローカル NVMe から読むので、配信中の速度は変わらない見込みである (未計測)。上流は rsync を fallback 扱いにしており、検証の厚みは NFS 経路より薄い。

**Engram の流れ。** `start.sh` は起動と pack のたびに、head の `engram-src/` から slim dir (`~/.cache/vllm-dsv41-flash-exl3/engram-src/`) を作り直す。shard 2 本はハードリンク、`config.json` はコピー、index は Engram のキーだけに書き直す。head の pack とコンテナ (`/engram-src`) は slim dir を読み、worker へは slim dir を rsync して `~/.cache/dsv41-flash-exl3/engram-src/` にし、worker の pack とコンテナがそれを読む。rsync は、シャードのサイズと mtime から作ったマーカー (`.dsv41-engram-synced`) が一致すると省略される。

## 起動と判定

```bash
ssh spark-head
cd ~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks
./start.sh            # 起動 (GPU 自己検査 → 重みの同期確認 → 両ランク起動 → health 待ち → warmup)
./start.sh status     # 両ランクのコンテナ状態と health
./start.sh logs       # head のログを追う (worker は ./start.sh logs worker)
./start.sh stop       # 両ランク停止 (./stop.sh も同じ)。成否は下の「停止の判定」で確かめる
./start.sh pack       # Engram を pack し直す (重みを差し替えたときだけ)
```

- **重みが無いと自動でダウンロードを始める** (`AUTO_DOWNLOAD=1`)。revision は固定されない (→「導入手順」2)
- **GPU 自己検査**は、head の使い捨てコンテナで EXL3 のカーネルと Engram の逆量子化を合成データで確かめる段である。結果は `logs/overlay-verify.log` に出て、不合格ならコンテナを作らずに止まる
- **起動に失敗してもコンテナは消えない。** `start.sh` は `logs/head.log` / `logs/worker.log` (head のログが 420 秒止まったときは `logs/hang-{head,worker}-pyspy.txt` も) を書いて止まる。コンテナがメモリを掴んだまま残るので、原因を見たら `./start.sh stop` → 停止の判定 → 起動し直す。health 待ちは 1,500 秒で打ち切られる
- **前置で上書きできるキーは限られる。** `.env` の読み込み前に退避して書き戻すのは `DSPARK_TOKENS` / `SPEC_METHOD` / `MAX_MODEL_LEN` / `MAX_NUM_SEQS` / `MAX_NUM_BATCHED_TOKENS` / `GPU_MEM_UTIL` / `LANGUAGE_MODEL_ONLY` / `IMAGE` / `ENFORCE_EAGER` と EXL3 のカーネル設定だけである。他のキー (`WEIGHT_SYNC` / `WORKER_*` / `KV_CACHE_MEMORY_BYTES` / `SERVED_MODEL_NAME` など) は `.env` の値が勝つので `.env` を編集する。`.env` に無い `FORCE_SYNC=1` (worker への rsync を強制) / `SKIP_SYNC=1` (worker への同期を省く) / `BUILD=1` (ローカルでビルド) / `SKIP_BUILD=1` (stamp が違ってもビルドしない) / `SKIP_SHIP=1` (worker へイメージを送らない) は前置で効く

**起動前の検査。** どちらか一方のノードでも `MemAvailable` が 111.5 GiB に届かなければ起動を拒む。閾値はレシピの `scripts/weight_budget.py` が safetensors の index から見積もる 1 ランク分の重み 99.5 GiB に、`DSV41_BOOT_MARGIN_GIB` の既定 12 GiB を足した値で、見積りが取れないと警告だけ出して検査を飛ばす。起動前に両ノードで次が exit 0 になることを見る (`/proc/meminfo` の kB を GiB に直して比べる)。

```bash
awk '/MemAvailable/{g=$2/1048576; printf "%.1f GiB\n", g; exit !(g>=111.5)}' /proc/meminfo
```

**停止の判定。** `./start.sh stop` は worker への ssh が失敗しても「stopped.」と出して exit 0 で終わる。exit code を使わず、`dgx-spark.md`「系統の切り替え」の手順 3 で両ノードのコンテナが消えたことを見る。

**エージェントのシェル実行から起動するときは、ssh を切り離してログを残す。** 起動全体は 8〜10 分かかり、1 回のコマンド実行の上限 (Claude Code の Bash ツールは 600 秒) を越えうる。ssh ごと切れると warmup が走らないまま中断する。

```bash
ssh -n spark-head 'cd ~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks && setsid nohup ./start.sh > ~/dsv41-start.log 2>&1 < /dev/null & echo started'
# 終わるまで待つ (バックグラウンドで流す)。`^bash ./start.sh$` に固定しているので、この ssh のコマンド文字列には一致しない
until ! ssh -n spark-head 'pgrep -f "^bash ./start.sh$" >/dev/null'; do sleep 30; done
ssh -n spark-head 'tail -25 ~/dsv41-start.log'   # 「DeepSeek-V4.1-Flash EXL3 is UP」が出ていれば起動は完了。出ていなければ上の失敗時の手順
```

パターンを `^…$` で固定しないと、`pgrep -f` が待ちの ssh 自身に一致して条件が永久に成立しない。

**起動できたかは 3 段で判定する。** どれも exit code で合否が出る。

```bash
curl -fs -o /dev/null http://spark-head.local:8888/health && echo health-ok   # 1. API が生きている
curl -s http://spark-head.local:8888/v1/models | python3 -c 'import json,sys; d={m["id"]:m.get("max_model_len") for m in json.load(sys.stdin)["data"]}; print(d); sys.exit(0 if d.get("DeepSeek-v4.1-Flash-EXL3")==600000 else 1)'   # 2. 配信名と上限
ssh -n spark-head 'cd ~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks && bash tests/test_smoke.sh'   # 3. exit 0 で「smoke OK: 17*19 -> 323」
```

加えて pack が使われていることを見る。head で `docker inspect dsv41-exl3-head --format '{{range .Mounts}}{{.Destination}} {{end}}'`、worker で `dgx-spark.md`「worker に入る」の入れ子 ssh から `docker inspect dsv41-exl3-worker` を同じ形で打ち、両方に `/engram-packed` が出れば合格である。各ノードには自分のコンテナしか無いので、1 ノードで 2 つの名前を打つと片方は必ずエラーになる。

**起動の実測値 (2026-09-15、pack 済み・重みの同期済み)。**

| 項目 | 値 |
| --- | --- |
| コンテナ起動から `/health` 200 まで | 470 秒 |
| 重みロード | 本体 191.75 秒 + draft 32.27 秒 (`Loading weights took` が 2 行)。`Model loading took 98.86 GiB memory and 270.5 seconds`。合計との差 46 秒の内訳は取っていない |
| `MemAvailable` (head / worker) | 起動前 116.1 / 114.9 GiB → 重みロード後 16 / 16 GiB → health 通過時 6.0 / 7.2 GiB。画像入力を有効にした 2026-09-30 は `Model loading took` が 99.8 GiB (0.9 GiB 増)、起動ログ末尾の `memory` 行が 5.1 / 6.0 GiB |
| pack の所要 | 1 本 (47.2 GiB) 約 90 秒、両ノードで計 4 本。`FORCE_SYNC=1` でも、変わったのが `config.json` だけなら rsync は 1 分以内 |
| 単一リクエストの decode | コード生成 400 トークン (thinking OFF、temperature 0) で約 36 tok/s、TTFT 0.60 秒。上流の散文での値は 31.6 tok/s |

**起動ログの `boot shape warmup incomplete` は致命的ではない。** warmup リクエストは 14/14 通っており、sampler のカーネル 1 通り (top-p だけの組み合わせ) が事前コンパイルされなかったという意味である。その組み合わせを初めて使うリクエストで 1 回だけ JIT の待ちが入りうる。

## 障害時 (V4.1 EXL3 系)

`dgx-spark.md`「障害時」の表のうち、この系統だけの確認と原因である。待ち行列は vLLM の `num_requests_(running|waiting)` で見る (コマンドは同節)。

| 症状 | 確認 | よくある原因 |
| --- | --- | --- |
| 応答しない | 待ち行列 | 同時リクエスト上限が 2 なので、subagent を並列に投げると待ちやすい |
| 起動に失敗する | `./start.sh logs` / `./start.sh logs worker`、レシピの `logs/` の `head.log` / `worker.log` / `overlay-verify.log` / `hang-*-pyspy.txt` | `not enough free unified memory` は相手系統が動いている (→「起動と判定」の起動前の検査)。`FileNotFoundError: /models/config.json` は「導入の落とし穴」4。コンテナが残るので `./start.sh stop` してから起動し直す |
| 起動待ちが長い | 同上 | 正常は約 8 分。15 分を超えたら worker 側のログを見る |
| 配信中に応答が止まった | `curl -fs -o /dev/null http://spark-head.local:8888/health`、待ち行列、両ノードの `docker ps` | hang 検知 (420 秒) は起動中にしか働かない。health が返らないか `num_requests_running` が動かないまま時間が経つなら、`./start.sh stop` → 停止の判定 → `./start.sh`。ssh も通らないノードがあれば「既知の制約 (V4.1 EXL3 系)」2 |
| `/v1/responses` が `input_text` で 400 | コードブロック 3・4 | head のパッチが当たっていない (→「既知の制約 (V4.1 EXL3 系)」1) |

## reasoning effort の語彙

`/v1/messages` と `/v1/chat/completions` は 2026-09-15、`/v1/responses` は 2026-09-17 に全値を実測した。セルは HTTP ステータスである。

| 値 | `/v1/messages` | `/v1/chat/completions` (OpenCode) | `/v1/responses` |
| --- | --- | --- | --- |
| `low` / `high` / `xhigh` / `max` | 200 | 200 | 200 |
| `medium` | 400 | 400 | 400 |
| `none` | 400 (スキーマ) | 200 | 200 |
| 指定なし | 200 | 200 | 200 |

- **OpenCode は `opencode.json` で `max` を送る**
- **`medium` の 400 の本文は語彙を名乗る**: `DeepSeek V4.1 reasoning_effort must be low, high, xhigh, max, or an integer within [1, 100] in chat_template_kwargs`。弾くのは vLLM 側の検査で、Qwen 系のようなチャットテンプレートの `raise_exception` ではない。レシピの `files/chat_template.jinja` のコメントは `xhigh` を挙げていないが、実測で受理されるので実測に従う
- **`none` の非対称は Qwen 系と同じ構造である** (→ `dgx-spark/qwen.md`「reasoning effort の語彙」)。弾くのは `/v1/messages` のスキーマだけ
- **確認コマンド**は `dgx-spark.md`「依拠する外部事実」の reasoning effort の行の形で、モデル名を `DeepSeek-v4.1-Flash-EXL3` にする。陽性対照は `medium` (400 の本文を読む)、陰性対照は `max` (200)。`high` は受理されるので陽性対照にならない。`/v1/responses` はコードブロック 3 に `"reasoning":{"effort":"<値>"}` を足して打つ

## 使える API

| API | 用途 | 状態 |
| --- | --- | --- |
| `/v1/messages` | Anthropic Messages API | 使える (2026-09-15 に生成を確認) |
| `/v1/chat/completions` | OpenCode | 使える (2026-09-15、opencode 1.18.18。V2 では試していない) |
| `/v1/responses` | Responses API | head のパッチを当てれば使える (2026-09-17、生成とツール呼び出しを確認 →「既知の制約 (V4.1 EXL3 系)」1)。パッチが無いと `input_text` で 400 |

## 導入手順

レシピを入れ直すときの順序と各段の完了判定である。どれも head で打つ (7 は worker でも)。重みはレシピ直下に実ファイルで取るので `utility-spark-model-fetch` スキルの対象外で、worker へのコピーは `start.sh` の rsync が作る。

- 配信中に進められるのは 1〜5 までで、6 から 8888 が止まる
- 2・3 の取得と 4 のコピーは `dgx-spark.md`「既知の制約」のメモリの余裕が薄い系統の項に従い、上限付きで行う。掛けられなければ 5・6 を先に行う
- `docker pull` / `docker load` は 6 の停止確認後に流す (dockerd を通る操作には上限が掛からない)

1. **clone と `.env`** — `git clone https://github.com/MiaAI-Lab/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks ~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks` → `cp .env.example .env` → 「構成」の上流既定からの差分を入れる。必ず入れるのは `WORKER_USER` / `WORKER_CX7_IF` / `WORKER_CX7_IB` / `WEIGHT_SYNC` の 4 キーと `HF_HUB_ENABLE_HF_TRANSFER=0` の 1 行である。画像入力の 3 キーは clone した `.env.example` と値が違うものだけを足す (`b9c49e9` なら 3 キー、`8404ac7` なら 0 キー、2026-10-04 時点の `main` (`6f7d159`) なら `LONG_PREFILL_TOKEN_THRESHOLD=1280` の 1 キー)。
   **完了判定**: コードブロック 1 の出力が入れたキーと `HF_HUB_ENABLE_HF_TRANSFER` に一致する (`b9c49e9` なら同ブロックのコメントの 8 キー。上流が足したキーも出るので「レシピを更新する」と同じく扱う。`b9c49e9` 以外の clone では確かめていない)。worker の RoCE アドレスを `W=$(grep -E "^WORKER_HOST=" ~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark/.env.dspark | cut -d= -f2)` で引き、`ip route get "$W"` が `dev enp1s0f1np1` を通り、両ノードの `/sys/class/infiniband/rocep1s0f1/ports/1/gid_attrs/types/3` が `RoCE v2` を返す
2. **本体の重み (約 7 時間)** — `mkdir -p model engram-src` (落とし穴 1) の後に取る。`download.sh` と `start.sh` の自動取得は revision を固定しないので、固定するなら次を手で打つ。head の `~/dsv41-dl.sh` に引用済み heredoc で保存し (先頭に `set -euo pipefail`)、`dgx-spark.md`「長い処理を ssh から切り離す」の型で流す (`<ディレクトリ>` はレシピのディレクトリ、`<名前>` は `dsv41-dl`)。この形は未実行である (当方は `download.sh` で取り、取得時点の `main` が同じ revision だったことを照合した)

   ```bash
   HF_HUB_DISABLE_XET=1 HF_MAX_WORKERS=2 hf download Mia-AiLab/DeepSeek-V4.1-Flash-EXL3-2.9bpw --revision 64ba41b6c916a587db06eae2e19b7845f7be6e6b --local-dir model --max-workers 2
   ```

   進捗は `du -sb model` の差分で見る (8 MB/s 前後)。`HF_HUB_DISABLE_XET=1` はメモリを守るため (落とし穴 2)。この型は上限を掛けないので、配信中なら上限付きコンテナで取る。
   **完了判定**: ログの最後が `EXIT=0` で、コードブロック 2 が exit 0
3. **Engram** — 下の「Engram の取得」で shard 2 本と index と `config.json` を取る (落とし穴 3・4)。
   **完了判定**: 末尾の `sha256sum -c` が 2 本とも `OK`
4. **worker への事前コピー** (任意。8888 を止める時間を縮めたいとき) — head のレシピのディレクトリで `W=$(grep -E "^WORKER_HOST=" ~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark/.env.dspark | cut -d= -f2) && rsync -a --partial model/ "$W":.cache/dsv41-flash-exl3/model/` を打つ。エージェントのシェル実行では呼び出しをまたいで変数が残らないので、`W` は同じ呼び出しの中で引き直す。Engram は 8 で `start.sh` が送る。
   **完了判定**: worker でコードブロック 2 を `DIR=~/.cache/dsv41-flash-exl3/model` にして exit 0、rsync の出力に `denied` が 0 件
5. **止める準備** — `dgx-spark.md`「系統の切り替え」の手順 1
6. **配信中の系統を止める** — 同節の手順 2・3。両ノードの停止と、「起動と判定」の起動前の検査の空きメモリを確かめてから進む
7. **イメージ** — 両ノードで `docker pull ghcr.io/miaai-lab/deepseek-v4.1-flash-exl3-2x-dgx-sparks:2.9bpw`。取り切れなければ「イメージを手で取る」(落とし穴 5)。
   **完了判定**: 両ノードの `docker image inspect <イメージ> --format '{{index .Config.Labels "dsv41.recipe.stamp"}}'` が落とし穴 6 のコマンドの値と一致する
8. **pack** — `./start.sh pack` (worker への同期も行う)。
   **完了判定**: head の `ls -la ~/dsv41-engram` に `engram-l{1,14}-r0of2.bin`、worker に `engram-l{1,14}-r1of2.bin` があり、各 47.2 GiB
9. **head のパッチ** — 「既知の制約 (V4.1 EXL3 系)」1 の手順で公式パッチの本体・実行ループ・mount を確認し、無い版だけローカル版と 2 行を用意する。`/v1/responses` を使わないなら飛ばしてよい (OpenCode には要らない)。
   **完了判定**: 本体・実行・mount の 3 点が揃っていること。実行の合否は起動後のコードブロック 3 の 200 で見る
10. **起動と判定** — 「起動と判定」。
    **完了判定**: 3 段と `/engram-packed`。`/v1/responses` を使うならコードブロック 3 が 200
11. **クライアント側** — `opencode.json` のモデル宣言と effort (`max`) を確認する。設定は symlink なので `drs` は要らない。sparkDash の表示は配信名に追従するので触らない (→ `dgx-spark.md`「sparkDash の worker の表示名」)

**Engram の取得 (手順 3)。** HF の resolve URL は Range 指定に 206 を返すので、`curl -C -` で途中から再開できる。サイズを先に見るのは、取り終えたファイルに `-C -` を打つと範囲外の要求になるためである。2 本で約 190 GiB、6 時間を超えるので、head 上のファイル (例: `~/dsv41-engram-dl.sh`) に保存し、切り離して `bash ~/dsv41-engram-dl.sh` として流す。末尾の `sha256sum -c` の 2 行 (`OK`) をログで読む。

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

**イメージを手で取る (手順 7 で `docker pull` が取り切れないとき)。** blob を 1 本ずつ再開可能に取り、`docker save` 形式にまとめて読み込む。2026-09-15 に使ったスクリプトを短くした形で、この形のままでは流していない。約 25 分かかるので、ファイルに保存して切り離して流す。停止確認後に流し、最後の `docker load` も両ノードの配信を止めた状態で打つ。

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

もう 1 ノードへは `~/.cache/dsv41-image/` を RoCE で rsync し、最後の `tar … | docker load` だけを打つ。読み込み後の `~/.cache/dsv41-image/` (9.1 GiB) は、イメージを消したときに読み込み直す用で、消してよい。

## 導入の落とし穴

上流 README を素直に流すと、この環境では次の 6 か所で止まる。「導入手順」はこれを避ける順序になっている。

1. **`download.sh` は `model/` が無いと何も出さずに exit 1 で終わる。** シャード数の数え方が `set -o pipefail` 下で `find` の失敗を拾うためである。先に `mkdir -p model engram-src` する
2. **xet (huggingface_hub 1.x の既定の転送) は受信データをメモリに溜める。** Qwen 配信中の head で並列 8 のまま流すと、書き込みが 0 MB/s のまま `MemAvailable` が 1 GiB を切った。本体 (1 ファイル 6 GiB 前後) は `HF_HUB_DISABLE_XET=1` + `HF_MAX_WORKERS=2` の HTTP ストリーム書き込みで安全に取れる (8 MB/s で約 7 時間)。配信中のノードでは上限を掛ける
3. **Engram の shard 47 / 48 (各 94.6 GiB) は、huggingface_hub が xet 以外での取得を拒否する** (`The file is too large to be downloaded using the regular download method`)。「Engram の取得」の curl で取る
4. **Engram 側に元チェックポイントの `config.json` が要る。** `download.sh` は取らないが、`pack_engram.py` と起動時の Engram ローダーが `text_config.engram_layer_ids` を読む。無いと pack が `FileNotFoundError: /models/config.json` で落ちる (`/models` は pack のコンテナに mount した slim dir)。`engram-src/` に置けば head 側には届くが、rsync のマーカーはシャードのサイズと mtime しか見ないので worker 側には届かない。`FORCE_SYNC=1 ./start.sh pack` にする
5. **GHCR のイメージは `docker pull` で取り切れないことがある。** 4.81 GiB などの大きいレイヤーが `unexpected EOF` で切れ、dockerd がリトライのたびに最初から取り直すので終わらない (1 時間で 149 回リトライした)。「イメージを手で取る」で取る。この docker は OCI layout の `index.json` だけの tar を読まない (`invalid archive: does not contain a manifest.json`) ので、`docker save` 形式の `manifest.json` が要る
6. **イメージの stamp が clone と一致しないと、起動時にビルドが始まる。** `start.sh` は `Dockerfile` と `overlay/` `files/` `tests/` のハッシュをラベル `dsv41.recipe.stamp` と比べる。上流がこの 4 つを変えたら公開イメージの pull し直しかビルドが要る (README や `start.sh` だけの変更ではずれない)。clone 側の値はレシピのディレクトリで次を打って出す

   ```bash
   { printf "%s\n" Dockerfile; find overlay files tests -type f ! -path "*/__pycache__/*" ! -name "*.pyc" ! -name "*.so"; } | LC_ALL=C sort | xargs -d "\n" -r sha256sum | sha256sum
   ```

**pack のファイルは root 所有である。** passwordless sudo が無いので、消すときはイメージ経由で消す (`docker run --rm -v ~/dsv41-engram:/e --entrypoint rm ghcr.io/miaai-lab/deepseek-v4.1-flash-exl3-2x-dgx-sparks:2.9bpw -f /e/engram-l1-r0of2.bin /e/engram-l14-r0of2.bin`。worker は `r1`)。作り直すだけなら `./start.sh pack` が上書きする。

## レシピを更新する

**未コミットの `start.sh` の 2 行は `git pull` / `git checkout` で消えない。** 差分が維持されるか、上流変更と重なると Git が拒否する。更新前に差分を clone 外へ退避し、追跡版を clean にしてから fast-forward する。退避した差分は無条件に適用せず、更新先の公式パッチを確認して判断する。

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
# 差分が制約 1 の既知の 2 行だけであることを head 上で確認する。
# 他の差分が含まれる場合は中断し、既存変更を維持する。
if test -s "$BACKUP"; then git apply --check --reverse "$BACKUP"; fi
# 停止前に /v1/models の配信名・上限と reasoning effort の語彙を控える。
# 稼働中リクエストを確認し、「系統の切り替え」の手順 1〜3 で停止する。
# 停止確認後、退避が確認できた start.sh だけを追跡版へ戻す。
git restore --source=HEAD --worktree -- start.sh
git diff --quiet -- start.sh || exit 1
git pull --ff-only
# 公式パッチ本体と start.sh の呼出・配布・mount を確認する (制約 1)。
if test -f overlay/patch_responses_content_types.py; then
  grep -n -e RESPONSES_PATCH_HOST -e patch_responses_content_types.py start.sh
else
  echo "official-patch-absent: 制約 1 のローカル版を用意する"
fi
```

- **公式パッチが揃っていれば 2 行を足さない。** 揃っているかの基準は「既知の制約 (V4.1 EXL3 系)」1 の 5 項目である。公式がある版へ退避ファイルを丸ごと `git apply` しない
- **`Dockerfile` / `overlay/` / `files/` / `tests/` が変わっていたら**、停止を確認してから両ノードで公開イメージを pull し直し、落とし穴 6 の値とラベルの一致を確かめてから起動する
- **`.env.example` にキーが増えていないか**をコードブロック 1 で見る。増えていたら「構成」の上流既定からの差分と、コードブロック 1 のコメントの期待キーを更新する。`.env` は追跡外なので `git pull` では消えない
- **戻すとき**も、稼働中リクエストを確認して停止し、追跡差分を上と同じく退避してから、控えた commit へ `git checkout <旧 sha>` する (`b9c49e9` には公式パッチが無い)。checkout 先に公式パッチが無い場合だけローカル 2 行を再適用して起動する

**更新後は次の 5 点で悪化していないことを確かめる。** 3 段判定は起動の可否しか見ない。2 と 3 は停止前に採っておき、起動後に 1〜5 を照合する。

1. 起動の 3 段判定
2. `/v1/models` の `id` と `max_model_len` が更新前と一致する。`created` と `permission` は起動のたびに変わるので全文比較に使わない (常に不一致になり検出器として働かない)
3. reasoning effort の語彙が変わっていない (経路ごとに打つ)
4. `docker inspect dsv41-exl3-head --format '{{.HostConfig.RestartPolicy.Name}}'` が `no` のまま
5. コードブロック 3 で `input_text` が 200

## 残骸

| 残骸 | 置き場 | 消してよい条件 | 消し方 |
| --- | --- | --- | --- |
| `~/.cache/dsv41-image` (9.1 GiB) | 両ノード | いつでも (イメージは読み込み済み) | `rm -rf ~/.cache/dsv41-image` |
| 起動失敗のログ | レシピの `logs/` (`hang-*-pyspy.txt` を含む) | 原因を調べ終えたら | `rm` |
| 切り離して起動したときのログ | head の `~/dsv41-start.log` | 読み終えたら (次の起動で上書きされる) | `rm` |

## ノードを作り直したときに手で戻すもの

| もの | 置き場 | 戻すときの材料 |
| --- | --- | --- |
| `/v1/responses` のローカルパッチ (公式が無い版のみ) | head の `~/dsv41-local/` と、レシピの `start.sh` の 2 行 | 「既知の制約 (V4.1 EXL3 系)」1 に全文と足す位置がある |
| レシピの `.env` | head のレシピのディレクトリ | 「構成」の上流既定からの差分と「導入手順」1 |

## 既知の制約 (V4.1 EXL3 系)

1. **`/v1/responses` は tokenizer の content パーツ対応に依存する。** 配信イメージが `FROM` で使うベース `vllm/vllm-openai:deepseekv41-flash-0909` (レシピの `Dockerfile` の `ARG BASE`) にある `vllm/tokenizers/deepseek_v41.py` の `_normalize_messages` は、content パーツを `text` / `image_url` / `input_image` / `image_pil` しか受けない。Responses API が使う `input_text` は 400 になる (`DeepSeek V4.1 supports text and image content only; got 'input_text'`)。上流 vLLM の `main` は既に `("text", "input_text", "output_text")` を受けるので、イメージが古いだけである。OpenCode の経路はパッチが無くても動くので、Responses API は個別に確かめる。

    - **版による違い**: `b9c49e9` には公式パッチが無く、head の `~/dsv41-local/patch_responses_content_parts.py` がその 1 行を起動のたびに当てる。2026-10-04 に見た head の保存済み `origin/main` (fetch はしていない) には公式の `overlay/patch_responses_content_types.py` と両ランクへの実行・配布・mount がある。公式が揃う版では公式を使う
    - **公式が揃っているかの基準**: `test -f overlay/patch_responses_content_types.py` と `grep -n -e RESPONSES_PATCH_HOST -e patch_responses_content_types.py start.sh` で、次の 5 つを確かめる。(a) `RESPONSES_PATCH_HOST` の既定が `$SCRIPT_DIR/overlay/patch_responses_content_types.py`、(b) 両ランクのパッチループに `/opt/dsv41/patch_responses_content_types.py`、(c) worker への scp、(d) worker の mount `/tmp/patch_responses_content_types.py:/opt/dsv41/patch_responses_content_types.py:ro`、(e) head の mount `$RESPONSES_PATCH_HOST:/opt/dsv41/patch_responses_content_types.py:ro`。参照を見ただけで、公式版で起動したことは無い (未検証)。起動後にログとコードブロック 3 の 200 を確認する
    - **ローカル版の本体は clone の外 (`~/dsv41-local/`) に置く。** レシピの `overlay/` に置くと `overlay_recipe_hash` (`Dockerfile` + `overlay/` + `files/` + `tests/` の hash) が動き、stamp と食い違ってレジストリから約 9 GiB を pull し直す。この分岐は `SKIP_BUILD` では止まらない。止めるキーとして `SKIP_PULL` / `BUILD` を控えてあるが、`SKIP_PULL` は前置で効くキーの一覧に無く、`start.sh` が受けるかは未確認である
    - **ローカル版で `start.sh` に足す 2 行**: 位置は `grep -n -e patch_sm120_block64.py -e 'exl3.py:ro' start.sh` で引く (2026-10-04 時点の差分の位置)。worker 側には足さない (トークナイズは head の API サーバでしか走らない)。更新は「レシピを更新する」の退避手順で行う
      - head 用スクリプトのパッチループの `/opt/dsv41/patch_sm120_block64.py \` の行の直後に `         /opt/dsv41/patch_responses_content_parts.py \`
      - head コンテナの `docker run` の `-v` ブロックの `-v "$EXL3_OVERLAY_HOST:/opt/dsv41/exl3.py:ro" \` の行の直後に `        -v "$HOME/dsv41-local/patch_responses_content_parts.py:/opt/dsv41/patch_responses_content_parts.py:ro" \`
    - **適用の確かめ方**: `b9c49e9` のパッチループは失敗を `WARN` で握り潰すので、パッチ自身がアンカーを検査して非 0 で終わる。適用は `docker logs dsv41-exl3-head` の `[dsv41-responses-parts]` の行で見る (レシピの `logs/` には出ない。コードブロック 4)。判定の本体はコードブロック 3 の HTTP 200 である
    - **撤去の判断**: イメージが対応済みなら backport は不要になる。ローカル版は `MARK` があれば `already patched:` で exit 0、アンカーも `MARK` も無ければ `FATAL` で非 0 になるので、`FATAL` だけを「対応済み」の根拠にしない。撤去は公式対応の確認と `input_text` の 200 が通った後に判断する。退避ファイルと `~/dsv41-local/` は、旧版へ戻す可能性がある間は保持する
    - **消さない**: 公式が無い版で `~/dsv41-local/` と 2 行を消すと `input_text` が 400 になり、OpenCode の疎通では検出できない
    - **他の系統では出ない**: このトークナイザは V4.1 EXL3 系だけが使う。DeepSeek 系 (Vision-Exp 版・0731 版) は `--tokenizer-mode deepseek_v4` で別のものを通り、2026-09-23 に両版で 200。GLM 系 (TensorFold) も 200 (2026-10-04)。Qwen 系は未確認
    - **全文**: dotfiles に控えが無いので載せる。公式が無い版を使うときは、これを `~/dsv41-local/patch_responses_content_parts.py` に書き、実行ビットを立てる

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

2. **メモリの余裕は 5 系統で最も薄い。** 配信中の head の `MemAvailable` は 5 GiB 前後である (2026-09-30 の実測で 4.8 GiB)。上流は `MAX_MODEL_LEN` 614,400 の構成で 601k トークンの prefill 中に 2.1 GiB まで下がったと書いている。当方の 600,000 では同じ入力は入らないが、長い prefill ほど下がる傾向は同じと見ている (未検証)。メモリが尽きたときにノードごと固まるおそれと、配信中に重い処理を流すときの上限の掛け方は `dgx-spark.md`「既知の制約」のメモリの余裕が薄い系統の項に従う。

    - **memguard は上流既定のまま無効にしている** (`.env` の `DSV41_MEM_GUARD=0`)。有効にすると 1 秒ごとに `MemAvailable` を見て、2 回続けて `DSV41_MEM_GUARD_GIB` (既定 1.5 GiB) を下回ったノードのコンテナを kill する。上流によれば、唯一発動したのは無関係なホストのプロセスがメモリを取った場面で、原因ではない vLLM を kill しただけだった
    - **代わりに両コンテナは `--oom-score-adj 1000` で起動される。** カーネルの OOM killer が動けば、デスクトップより先に vLLM が落ちる
    - **起動前のメモリ検査 (111.5 GiB) は memguard とは別物である** (→「起動と判定」)

## 依拠する外部事実 (V4.1 EXL3 系)

`dgx-spark.md`「依拠する外部事実」のうち、この系統だけの行である。複数の系統をまとめて確かめる行 (重みの容量・イメージ・restart policy・8888 の無認証・画像入力・effort の確認コマンドの形) は同節にある。

| 事実 | 確認コマンド | 確認日 |
| --- | --- | --- |
| レシピの commit | `ssh -n spark-head 'cd ~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks && git log --oneline -1'` (2026-09-30 時点 `b9c49e9`)。上流が先行していたら `git log --stat HEAD..origin/main` で `Dockerfile` / `overlay/` / `files/` / `tests/` の変更を見る (あれば stamp がずれる) | 2026-09-30 |
| 本体の重みがそろっているか | コードブロック 2 が両ノードで exit 0、`OFF=1` (陽性対照) で exit 1。Engram は「Engram の取得」末尾の `sha256sum -c` で照合し、`engram-src/` に `config.json` と `model.safetensors.index.json` があることも見る | 2026-09-15 |
| 上流既定からの差分 | コードブロック 1 | 2026-09-30 |
| reasoning effort の語彙 | 陽性対照 `medium` が 400、陰性対照 `max` が 200 (→「reasoning effort の語彙」) | 2026-09-15 (`/v1/responses` は 2026-09-17) |
| `/v1/responses` が `input_text` を受けるか | コードブロック 3 が 200 で合格。パッチ前に 400 を返したこと (2026-09-17 実測) が陰性対照 | 2026-09-17 |
| ローカル版のパッチが走ったか | コードブロック 4 の最後の行が `patched:` か `already patched:` なら適用済み、`FATAL` なら当たっていない。公式版は公式スクリプトのログの目印で見る。どちらも判定の本体はコードブロック 3 | 2026-09-17 (ローカル版) |
| `start.sh` のパッチ経路 | `ssh -n spark-head 'cd ~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks && git diff --stat start.sh'` がローカル 2 行の有無を示す。空でも公式パッチの有無は別に見る (→「既知の制約 (V4.1 EXL3 系)」1) | 2026-10-04 (参照のみ) |

表のセルにはパイプを含むコマンドを書かず、ここに番号を付けて置く (エスケープした `\|` はコピーするとパイプにならない)。

```bash
# 1. V4.1 EXL3 レシピの .env と配布既定の差分 (キー名だけを出す。値に IP を含む行があるので値は出さない)
# 行頭の < は配布既定、> は当方の値。2026-09-30 時点は HF_HUB_ENABLE_HF_TRANSFER (> だけ) と LANGUAGE_MODEL_ONLY / LONG_PREFILL_TOKEN_THRESHOLD / MAX_NUM_BATCHED_TOKENS / WEIGHT_SYNC / WORKER_CX7_IB / WORKER_CX7_IF / WORKER_USER (< と > の両方) の 8 キーが出る
ssh -n spark-head 'cd ~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks && diff <(grep -E "^[A-Za-z0-9_]+=" .env.example | sort) <(grep -E "^[A-Za-z0-9_]+=" .env | sort) | grep -E "^[<>]" | sed -E "s/=.*//" | sort -u'
```

```bash
# 2. V4.1 EXL3 の本体の重みが revision 固定の HF API とサイズで一致するか (head で実行。worker は DIR を ~/.cache/dsv41-flash-exl3/model に)
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
# 3. /v1/responses が Responses API の content パーツ (input_text) を受けるか。
#    200 なら head のパッチが効いている。400 なら当たっていない (→「既知の制約 (V4.1 EXL3 系)」1)。
curl -s -o /dev/null -w '%{http_code}\n' -m 60 http://spark-head.local:8888/v1/responses \
  -H 'Content-Type: application/json' \
  -d '{"model":"DeepSeek-v4.1-Flash-EXL3","store":false,"stream":false,"max_output_tokens":24,
       "input":[{"type":"message","role":"user","content":[{"type":"input_text","text":"say OK"}]}]}'
```

```bash
# 4. head のパッチ (patch_responses_content_parts.py) が起動時に走ったか。最後の 1 行を読む
#    patched: / already patched: なら適用済み、FATAL なら当たっていない (→「既知の制約 (V4.1 EXL3 系)」1)
ssh -n spark-head 'docker logs dsv41-exl3-head 2>&1 | grep "dsv41-responses-parts" | tail -1'
```
