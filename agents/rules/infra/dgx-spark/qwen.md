---
# 常駐読み込みさせないためのマーカー (このパスにマッチするファイルは存在しない)。
# 本ファイルは必要になったときに Read で参照する。
paths:
  - "__read-on-demand-only__"
---

# Qwen 系 (DGX Spark)

- 種別: 環境リファレンス (系統別)
- 対象読者: 別セッション・別マシンで作業するエージェント (Claude Code / Codex / OpenCode)
- 最終確認: 2026-09-09 (実機)。「起動と判定」の 2・3 段目の判定の形は 2026-10-04 に書いたもので、Qwen 配信中には流していない
- 共通の前提 (接続・切り替え・障害時・既知の制約): `agents/rules/infra/dgx-spark.md`

Qwen3.8-Flash-Next を vLLM の TP=2 で配信する系統である。**他の 4 系統とは別リポジトリ・別イメージ・別スクリプト名なので、取り違えると停止スクリプトが効かない。** 配置・起動・OpenCode からの疎通は 2026-09-06 に確かめた (OpenCode は opencode 1.18.18。V2 では未確認)。**この構成には認証が無い** (→「認証」)。

## 用語

| 名前 | 意味 | 定義箇所 | 生成者 | 消費者 |
| --- | --- | --- | --- | --- |
| Qwen3.8-Flash-Next | `nvidia/Qwen3.8-Flash-Next-NVFP4` の略 | 「構成」 | 上流のチェックポイント | vLLM |
| Qwen レシピ | Qwen3.8-Flash-Next を TP=2 で配信するレシピ | head の `~/Qwen3.8-Flash-Next-Dual-DGX-Sparks/` | 上流 (`git clone`) | 人 |
| `vllm-fn` | Qwen レシピのコンテナ名。**head と worker で同名** | Qwen レシピの `start.sh` | `start.sh` | `docker` |
| `resolve_snapshot.py` / `check-weights.sh` / `verify-weights.py` | Qwen レシピ**限定**の重み検証ツール 3 種。**`utility-spark-model-fetch` 同梱の `verify_shards.py` とは別実装で、配布中はスキル側、起動前はレシピ側を使う** | 「重みの検証」 | 上流 (`git clone`) | `start.sh` (1 つ目) / `check-weights.sh` (3 つ目) / 人 |

## 構成

値の出所はレシピの `.env` である。実機の値は、レシピ・重み・画像入力・既定の reasoning・コンテナ名・restart policy の行とイメージの Id・サイズ。「`.env` に書いていない上流キー」の行だけは `.env.sample` と上流の CHANGELOG から取った。

| 項目 | 値 |
| --- | --- |
| レシピ | head の `~/Qwen3.8-Flash-Next-Dual-DGX-Sparks` @ `0b62e12`。上流は [MiaAI-Lab/Qwen3.8-Flash-Next-Dual-DGX-Sparks](https://github.com/MiaAI-Lab/Qwen3.8-Flash-Next-Dual-DGX-Sparks) |
| チェックポイント (`MODEL_ID`) | `nvidia/Qwen3.8-Flash-Next-NVFP4`。**revision を固定するキーは `.env` に無く**、起動前に `files/resolve_snapshot.py` が snapshot を選ぶ (→「重みの検証」)。当方の `refs/main` は `fab0aecb760cec45227f6656abcaafa11abca87a` (以下 `fab0aecb`) で、snapshot もこれ 1 つだけ |
| 重み | 124 GiB / safetensors 11 本 (`du -sh`、2026-09-06)。**両ノードに配置済み**。`.env` のコメントの 133G は 10 進 GB 表記で食い違いではない (HF の manifest 132.7 GB、vLLM の起動ログ 123.57 GiB) |
| API 上のモデル名 (`SERVED_MODEL_NAME`) | `qwen3.8-flash-next` |
| 画像入力 | 使える (2026-09-06。8x8 の赤い PNG を data URL で渡して「赤」と回答) |
| コンテキスト上限 (`MAX_MODEL_LEN`) | 524,288 トークン。**ネイティブは 262,144 で、`YARN_ENABLE=true` + `YARN_FACTOR=2.0` で伸ばしている** (→「YaRN」) |
| 同時リクエスト上限 (`MAX_NUM_SEQS`) | 8 リクエスト |
| 投機デコード (`MTP_NUM_SPECULATIVE_TOKENS`) | MTP、draft 3 トークン |
| KV キャッシュ (`KV_CACHE_DTYPE`) | `fp8` |
| メモリ確保率 (`GPU_MEMORY_UTILIZATION`) | 0.835 (DeepSeek 系と同値だがキー名が違う。意味は `dgx-spark.md`「メモリの使われ方」) |
| 既定の reasoning | `xhigh` (`.env` にキーが無く、チャットテンプレートの既定が効く)。**使えるのは `low` / `medium` / `xhigh` だけ** (→「reasoning effort の語彙」) |
| コンテナイメージ | `vllm/vllm-openai:qwen38-flash-next` (Id `sha256:d464f3b466fa9c45ddbff8a812e80564503b6879a9fd95c1a47514f3f0df5a4a`、20.6 GB (`docker images` の 10 進表示)、arm64)。**両ノードに配置済み** |
| コンテナ名 / restart policy | `vllm-fn` (両ノード同名。`start.sh` が付ける) / `no` (2026-09-06 実測)。ノードを再起動すると上がらないので `./start.sh --launch` を打ち直す |
| 追加の vLLM 引数 (`EXTRA_VLLM_ARGS`) | 未設定 (コメントアウト)。認証を付けるならここ (→「認証」) |
| 起動前の GPU ガード (`REQUIRE_IDLE_GPU`) | `true` (上流既定。取りうる値: `true` / `false`)。どちらかのノードで GPU を掴むプロセスがあれば起動を拒否する |
| 上流既定からの差分 | **値を変えたキーは 5 つ。** サイト固有の `IFACE` = `enp1s0f1np1` / `IB_HCA` = `=rocep1s0f1` (先頭の `=` は「完全一致で 1 デバイスだけ」を表す上流の記法で、typo ではない) と、常用長に合わせた `MAX_MODEL_LEN` 262144 → 524288 / `YARN_ENABLE` false → true / `YARN_FACTOR` 4.0 → 2.0 (→「YaRN」)。`HEAD_IP` / `WORKER_IP` は配布既定のまま実機と一致する (実値は `dgx-spark.md`「依拠する外部事実」の IP の行で引く)。確認は「依拠する外部事実 (Qwen 系)」のコードブロック 1 |
| `.env` に**書いていない**上流キー | 2 つ。どちらも未設定が現行動作。**`ABLIT`** (未設定 = 0): 1 は**別チェックポイント `drowzeys/keys-Qwen3.8-Flash-Next-NVFP4-dual-ablit-house-qsa-L3-47` への乗り換え**で、full snapshot の取り直しになる。HF での規約同意、`HF_TOKEN` (`.env` か環境変数。この 2 キーだけは環境が `.env` に優先する)、124 GiB 級の取得と worker への配布が要る (→ `utility-spark-model-fetch`)。**`MAMBA_SSM_CACHE_DTYPE`** (未設定 = チェックポイントの float32): `bfloat16` で再帰状態の dtype が半分になる。上流の「集約 decode スループット +8.5%」は単 Spark TP=1 の計測で、**2 ノード TP=2 では未計測**と上流が書いている。採用は `.env` に 1 行足して停止 → 起動、戻すのは行を消して同じ再起動 (13〜14 分止まる → `dgx-spark.md`「既知の制約」の「停止と再起動はユーザーの作業を止める」)。**`.env.sample` の既定は `ABLIT=0` / `MAMBA_SSM_CACHE_DTYPE=bfloat16` なので、`.env` を作り直すと後者が黙って有効になる** |

**メモリ。** 確保は head 100.7 / worker 100.8 GiB (期待値 121.7 × 0.835 = 101.6 GiB)、`MemAvailable` は head 1.3〜5.7 / worker 5.6〜10.1 GiB、swap 使用は 5.0 / 4.1 GiB である (2026-09-09 の再起動後の無負荷。head の `MemAvailable` は 2026-09-06 の高負荷時 1.3〜1.7 GiB から再起動直後 5.7 GiB までの幅)。**head の空きが少ないのは確保率 0.835 の先取りで、不足ではない。** メモリを空けたくなったらプロセスを探す前にこの値を疑う (他系統との比較は `dgx-spark.md`「メモリの使われ方」)。

## 起動と判定

他の系統から切り替えるときは、先に `dgx-spark.md`「系統の切り替え」で配信中の系統を止める。どちらも head の上で打つ。

```bash
cd ~/Qwen3.8-Flash-Next-Dual-DGX-Sparks && ./start.sh --launch   # 起動
cd ~/Qwen3.8-Flash-Next-Dual-DGX-Sparks && ./stop.sh             # 停止
```

- **`--launch` を付ける。** 引数なしの `./start.sh` は HF からのダウンロードと worker への rsync から始める。`--launch` はどちらも飛ばすが、**head のシャード完全性の検査は必ず通り、欠落があればコンテナを作らずに止まる** (→「重みの検証」)
- **`./start.sh --launch` は `/health` が 200 になるまで待って戻る。** 成功で `vLLM is ready and serving on port 8888!`、コンテナが途中で落ちると `Container vllm-fn exited unexpectedly` を出して止まる。約 13〜14 分かかるので、エージェントのシェル実行からは `dgx-spark.md`「長い処理を ssh から切り離す」の型で流す
- **20 分を過ぎても上がらなければ worker 側だけ落ちていることがある。** 両ノードで `docker logs vllm-fn` を見る (worker は `dgx-spark.md`「worker に入る」の入れ子 ssh)
- 起動の失敗で多いのは、相手系統が GPU を掴んだままで `REQUIRE_IDLE_GPU` に拒否されることである。`IB_HCA` が 1 本なので、DeepSeek 系の `no usable RoCEv2 GID` はこの形では出ない

**起動の実測値。判定には実測の約 13〜14 分を使う。** 上流 README (2026-09-05 時点) の約 11 分 (NCCL 約 40 秒、重みロード 458 秒、engine init 92 秒、graph capture 約 7 秒) は別のチェックポイントの値である。列の括弧内はレシピの commit。

| 項目 | 2026-09-06 (`c2325b2`) | 2026-09-09 (`0b62e12`) |
| --- | --- | --- |
| 重みロード (本体) | head 423 秒 / worker 463 秒 (11 シャード) | head 452 秒 (tqdm の `[07:32]`。同じログの `Loading weights took` は 455.41 秒。worker は未取得) |
| 重みロード (MTP ドラフタ) | head 75 秒 / worker 52 秒 | head 84 秒 (worker は未取得) |
| モデルロード合計 (`Model loading took`) | 未取得 | head 578 秒 / worker 491 秒 (各ノードの確保 64.55 GiB を含む。本体 + ドラフタとは待機分だけずれる) |
| engine init (profile + KV 確保 + warmup) | 163 秒 | 122 秒 |
| CUDA graph capture | 16 秒 (head 0.39 GiB / worker 0.77 GiB) | 14 秒 (head 0.24 GiB / worker 0.30 GiB) |
| コンテナ起動から `/health` 200 まで | 823 秒 (13.7 分) | 794 秒 (13.2 分) |
| KV キャッシュ | head 35.35 GiB / worker 33.42 GiB、合計 3,809,995 トークン | head 35.55 GiB / worker 33.2 GiB、合計 4,214,141 トークン |
| 同時実行できる 524,288 トークンの文脈 | 7.27 本 (トークン数 ÷ 524,288) | 8.04 本 (vLLM の起動ログ) |

**KV プールのトークン数は固定値として扱わない。** KV のバイト数がほぼ同じ (68.77 / 68.75 GiB) なのに、トークン数は 10.6% 増えた。`.env` も起動引数も同一 (「構成」の値と `MAX_NUM_BATCHED_TOKENS` 8,192) で、原因 (上流パッチによる KV レイアウトの変化か、hybrid のブロック配置の揺れか) は特定していない。

**起動できたかは 3 段で判定する。** 3 段とも exit code で合否が出る。

```bash
curl -fs -o /dev/null http://spark-head.local:8888/health && echo health-ok  # 1. API が生きている
curl -s http://spark-head.local:8888/v1/models | python3 -c 'import json,sys; d={m["id"]:m.get("max_model_len") for m in json.load(sys.stdin)["data"]}; print(d); sys.exit(0 if d.get("qwen3.8-flash-next")==524288 else 1)'   # 2. 配信名と上限
curl -s http://spark-head.local:8888/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.8-flash-next","messages":[{"role":"user","content":"17*19 を計算して、答えの数値だけを出力してください。説明や単位は不要です。"}],"temperature":0,"reasoning_effort":"low","max_tokens":4096}' \
  | python3 -c 'import json,sys; c=json.load(sys.stdin)["choices"][0]["message"]["content"].strip(); print(repr(c)); sys.exit(0 if "323" in c else 1)'   # 3. 生成が通る
```

- **2・3 段目の判定の形は Qwen 配信中に流していない** (2026-10-04 に書いた形)。3 段目は思考を `low` にして答えを短くし、本文に `323` が含まれるかを見る
- **Qwen レシピには DeepSeek 系の `smoke-…sh` に相当するスクリプトが無い**ので、3 段目は OpenCode と同じ `/v1/chat/completions` で生成を通して代用する。クライアント越しに見るなら `opencode run "1+1 は?"`
- Bearer が要らないのは無認証だからである。curl は LAN 側を見る (出先では `dgx-spark.md`「出先 (Tailscale) からのコマンドの読み替え」)

## reasoning effort の語彙

**受理される値はエンドポイントで違い、両経路で使えるのは `low` / `medium` / `xhigh` の 3 つである。** 2026-09-06 に両経路で全値を実測した (セルは HTTP ステータス)。`/v1/responses` は未実測。

| 値 | `/v1/messages` | `/v1/chat/completions` (OpenCode) | 弾く層 |
| --- | --- | --- | --- |
| `low` / `medium` / `xhigh` | 200 | 200 | — |
| `none` | **400** | 200 | `/v1/messages` のスキーマ |
| `high` / `max` | 400 | 400 | チャットテンプレート |
| 指定なし | 200 (既定 `xhigh`) | 200 (既定 `xhigh`) | — |

- **チャットテンプレート**は `xhigh` / `medium` / `low` 以外で `raise_exception` する (本文 `Unexpected reasoning effort high. Supported types are xhigh (default), medium, and low.`)。Anthropic ルータは `output_config.effort` を `reasoning_effort` に写して同じテンプレートへ渡すだけなので、両経路に効く
- **`none` の非対称**: vLLM は `reasoning_effort != "none"` を `enable_thinking` に導出し、テンプレートは `enable_thinking` が偽なら effort を見ないので、`/v1/chat/completions` では通る。`/v1/messages` は `AnthropicOutputConfig.effort` の Literal (`low` / `medium` / `high` / `xhigh` / `max`) に `none` が無く、スキーマ検証で先に弾く (本文 `Input should be 'low', 'medium', 'high', 'xhigh' or 'max'`)
- **値の実体は system への 1 文の指示である。** `xhigh` と `low` だけが文を足し、`medium` は何も足さない。長さや打ち切りは変えない

OpenCode は `opencode.json` の `xhigh` を送る (→ `dgx-spark.md`「OpenCode」)。確認コマンドは `dgx-spark.md`「依拠する外部事実」の reasoning effort の行で、Qwen 系の陽性対照は `high` (400 で対応値を列挙する)、陰性対照は `xhigh` (200) である。

## 使える API

- `/v1/chat/completions` (OpenCode の経路): 2026-09-06 に opencode 1.18.18 で実測した。V2 からは試していない
- `/v1/messages`: 使える。このイメージの `vllm/entrypoints/generate/api_router.py` が `register_anthropic_api_router(app)` を無条件に呼ぶ
- `/v1/responses`: **未試行**。`input_text` の content パーツを受けるかも確かめていない。確かめるなら次を打つ (この形は未実行。200 で合格)

```bash
curl -s -o /dev/null -w '%{http_code}\n' -m 60 http://spark-head.local:8888/v1/responses \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.8-flash-next","store":false,"stream":false,"max_output_tokens":24,
       "input":[{"type":"message","role":"user","content":[{"type":"input_text","text":"say OK"}]}]}'
```

## レシピを更新する

**`.env` は追跡外なので `git pull` では消えない。**

```bash
ssh spark-head
cd ~/Qwen3.8-Flash-Next-Dual-DGX-Sparks
git fetch -q && git log --oneline HEAD..origin/main    # 先行分を読む
OLD=$(git rev-parse --short HEAD); echo "戻し先: $OLD"  # 戻すときに使うので控える
git pull --ff-only
diff <(grep -E '^[A-Za-z0-9_]+=' .env.sample | sort) <(grep -E '^[A-Za-z0-9_]+=' .env | sort)
```

最後の `diff` は**上流にキーが増えていないか**を見る。出力に IP を含む行があるので証跡として貼らない。増えていたら「構成」の「`.env` に書いていない上流キー」の行を更新する。

**更新後は次の 4 点で悪化していないことを確かめる** (3 段判定は起動の可否しか見ない)。**2 と 3 は停止後には採れないので、先に採ってから停止し、起動 (`dgx-spark.md`「系統の切り替え」の手順 2〜4) の後に 1〜4 を照合する。**

1. 起動の 3 段判定
2. `/v1/models` の `id` と `max_model_len` が更新前と一致すること。**`created` と `permission` は起動のたびに変わるので全文比較に使わない** (常に不一致になり検出器として働かない)
3. reasoning effort の語彙が変わっていないこと (**2 経路とも打つ**)
4. `docker inspect vllm-fn --format '{{.HostConfig.RestartPolicy.Name}}'` が `no` のままであること

KV プールのトークン数は起動ごとに動くので、不合格の根拠にしない (→「起動と判定」)。

**戻すとき**は `git checkout <旧 sha>` (上で控えた「戻し先」) をしてから停止 → 起動する。detached HEAD になるので、復帰は `git checkout main`。重み・イメージ・`.env` は変わらないので戻せる。

## 重みの検証

`0b62e12` のレシピは検証手段を 3 つ持つ。**いずれも Qwen レシピ限定で、他の 4 系統には無い。** パスはレシピディレクトリからの相対で、実行も同ディレクトリで行う。

| 道具 | 対象 | 見るもの | exit code |
| --- | --- | --- | --- |
| `python3 files/resolve_snapshot.py <hub の repo ディレクトリ>` | head | `model.safetensors.index.json` が名指すシャードが揃っているかだけ。`refs/main` の snapshot が完全ならそれを、でなければ最新の完全な snapshot を、それも無ければ `refs/main` を返す。**`start.sh` が起動前に必ず通す門** | 0 = 完全 / 1 = 欠落あり / 2 = snapshot が無い |
| `./check-weights.sh` (引数なし) | **両ノード** | presence と size (124 GiB / 11 シャード) を数秒で。manifest は取らない。**配信中に打てるのはこれまで** | 0 |
| `./check-weights.sh --dry-run` / `--verify` | **両ノード** | `--dry-run` は manifest を取って presence と size を照合する (hashing と worker への scp はしない)。`--verify` は worker へ検証器と manifest を scp して全シャードの SHA-256 を照合し、両ノードで 124 GiB ずつ読む。**`--verify` は停止中に打つ** | — |
| `python3 verify-weights.py` | **1 ノード** | HF の manifest との照合の本体 (`check-weights.sh` が各ノードで呼ぶ)。`--repo <ID>` / `--revision <sha>` (照合先) / `--manifest <ファイル>` (保存済み manifest。HF へ問い合わせない) / `--dry-run` (内容ハッシュを飛ばす) | 0 = 全一致 / 1 = 問題あり / 2 = manifest かディレクトリを解決できない |

**manifest と照合するモード (`--dry-run` / `--verify`) は、revision を指定しないと必ず失敗する。腐敗ではない** (2026-09-09 実測)。manifest は HF の `@main` から取るが、キャッシュは取得当時の `fab0aecb` (「構成」のチェックポイントの行) に固定されている。HF の `main` は `fc694b54` へ進んでおり、中身が違う `config.json` と `README.md` の 2 件だけが size 不一致になる (全 25 ファイルのうち、safetensors 11 本を含む 23 件は一致)。

```bash
# head だけを見る
ssh -n spark-head 'cd ~/Qwen3.8-Flash-Next-Dual-DGX-Sparks && python3 verify-weights.py \
  --repo nvidia/Qwen3.8-Flash-Next-NVFP4 \
  --revision fab0aecb760cec45227f6656abcaafa11abca87a --dry-run'
# 25/25 一致で exit 0 (2026-09-09 実測)。--dry-run なので size まで。内容ハッシュまで見るなら外す
```

**両ノードを見るときは manifest を先に固定する。** `check-weights.sh` は `--revision` を受けないので、固定した manifest を渡す (スクリプトのヘッダにある順路。**当方では未実行**)。

```bash
ssh -n spark-head 'cd ~/Qwen3.8-Flash-Next-Dual-DGX-Sparks && \
  python3 verify-weights.py --repo nvidia/Qwen3.8-Flash-Next-NVFP4 \
    --revision fab0aecb760cec45227f6656abcaafa11abca87a \
    --save-manifest /tmp/qwen-manifest.json --fetch-only && \
  ./check-weights.sh --manifest /tmp/qwen-manifest.json'
```

**新しい revision へ上げるかは別の判断である。** `fc694b54` の `config.json` は MTP の routed experts を `FP8_PB_WO` と名乗り、`hf_quant_config.json` の `FP8_BLOCK_SCALES` と食い違う。`0b62e12` の `start.sh` はこれを別名として受理するが、**当方の `fab0aecb` は両方とも `FP8_BLOCK_SCALES` なので、この修正は効いていない** (2026-09-09 実測)。**欠落を埋めるつもりで revision を指定せずに再取得すると、`refs/main` が `fc694b54` へ動き、次の起動から配信 revision が黙って変わる。**

### シャードの欠落で起動が止まったとき

**症状は、コンテナを作らずに `Checkpoint snapshot is incomplete` で止まることである。** `python3 files/resolve_snapshot.py <hub の repo ディレクトリ>` が 0 以外を返す。**コンテナが作られないので `docker logs vllm-fn` は空振りする。`start.sh` の標準出力を見る。**

復旧は重みの再取得である。**同梱の `./download.sh` (`--launch` 無しの `./start.sh` が内部で呼ぶもの) は revision を受けないので、そのまま流すと配信 revision が動く。** 固定して取り直すなら、ログインシェルで次を `dgx-spark.md`「長い処理を ssh から切り離す」の型で流し、worker へは `utility-spark-model-fetch` の手順 4 で送る (この形は未実行)。

```bash
hf download nvidia/Qwen3.8-Flash-Next-NVFP4 --revision fab0aecb760cec45227f6656abcaafa11abca87a --cache-dir ~/.cache/huggingface/hub
```

## YaRN

**ネイティブは 262,144 で、それを超える分は rope スケーリングによる拡張である。**

| 項目 | 値 |
| --- | --- |
| ネイティブ長 (`config.json` の `text_config.max_position_embeddings`) | 262,144 トークン |
| `YARN_FACTOR` | 2.0 (262,144 × 2.0 = 524,288) |
| 出荷時の `config.json` の `text_config.rope_parameters.rope_type` | `default` (YaRN は無効。`start.sh` が `--hf-overrides` で `yarn` に差し替える) |

**係数は常用する長さに合わせる。** Qwen 公式のモデルカードは、主要な実装の YaRN は静的 (入力長によらず係数が一定) で短い入力の性能に影響しうるので、`rope_parameters` は長文脈が要るときだけ変え、常用が 524,288 トークンなら `factor` は 2.0 がよいと書いている。**係数 4.0 (1M) は常用 500k には過剰である。**

**このキットでの YaRN は検証されていない。** 上流の CHANGELOG によれば、2026-09-05 まで `--hf-overrides` の出力先が誤っていて YaRN は無効 (silent no-op) だった。それ以前の「1M で動いた」報告は、スケーリングなしの rope で 1M を流したものである。修正後に品質を測った報告は上流にもコミュニティにも無い。**長文脈の回答を信用する前に自分で確かめる。**

**262,144 に戻すなら YaRN も切る。** `start.sh` は `MAX_MODEL_LEN` が 262,144 以下のとき `YARN_ENABLE` を強制的に false にする (ネイティブ以下では品質を落とすだけのため)。`0b62e12` では `start.sh:153-156` だが、**行番号は上流の更新でずれるので `grep -n 262144 start.sh` で引き直す。**

## 認証

**このレシピは vLLM に `--api-key` を渡さないので、Qwen 配信中はポート 8888 が無認証になる。** `.env` にも `.env.sample` にも API キーのキーが無く (`grep -nE "API_KEY" .env` は 1 行も返さず exit 1)、`docker inspect vllm-fn` の実引数にも `--api-key` は無い。**Bearer 無しでも出まかせの Bearer でも `/v1/*` が通ることを実測した** (同じ日に、存在しないパスが 404 を返すことも確かめた)。DeepSeek 系も `VLLM_API_KEY` を空にしてあるので、いま切り替えても認証の有無は変わらない (→ `dgx-spark.md`「API キーの流れ」)。

**sparkDash (ポート 5555) と同じく、ポート 8888 も信頼できないネットワークへ出さない。**

認証を付けたい場合は `.env` の `EXTRA_VLLM_ARGS="--api-key <値>"` で渡せる (未検証)。**その場合はクライアント側も直す。** サーバだけ直すと OpenCode は起動して最初の生成で失敗するので、`dgx-spark.md`「API キーの流れ」の番号付き手順 2〜5 を同じく適用する。

**無認証の OpenCode には 1Password は要らない。**

## 依拠する外部事実 (Qwen 系)

「確認日」は、その行を実機で確かめた日である。作業前に変わっていないか確かめる。

| 事実 | 確認コマンド | 確認日 |
| --- | --- | --- |
| Qwen レシピの commit | `ssh -n spark-head 'cd ~/Qwen3.8-Flash-Next-Dual-DGX-Sparks && git log --oneline -1'` (`0b62e12`)。上流の先行分は同じディレクトリで `git fetch -q && git log --oneline HEAD..origin/main` | 2026-09-09 |
| 重みが完全か | `ssh -n spark-head 'cd ~/Qwen3.8-Flash-Next-Dual-DGX-Sparks && python3 files/resolve_snapshot.py ~/.cache/huggingface/hub/models--nvidia--Qwen3.8-Flash-Next-NVFP4; echo $?'` が 0。**陽性対照は存在しないディレクトリを渡して 2 が返ること。** manifest との照合は「重みの検証」の `verify-weights.py --revision` (head) か `check-weights.sh --manifest` (両ノード) で行う (revision を省くと必ず 2 件不一致) | 2026-09-09 |
| HF 側の `main` が動いていないか | 下のコードブロック 2。**`fab0aecb` 以外を返すならキャッシュより先に進んでいる** (2026-09-09 時点は `fc694b54`) | 2026-09-09 |
| 上流既定からの差分 | 下のコードブロック 1 | 2026-09-06 |

```bash
# 1. Qwen の .env と配布既定の差分。出力に IP を含む行があるので証跡として貼らない。
# 行の差は 6 か所出るが、うち IB_GID_INDEX は値が両側とも 3 で末尾コメントだけが違う
# (「構成」の「5 つ」は値が違うものの数)。「書いていない上流キー」2 つは .env.sample 側にしか無い行として出る。
ssh -n spark-head 'cd ~/Qwen3.8-Flash-Next-Dual-DGX-Sparks && diff <(grep -E "^[A-Za-z0-9_]+=" .env.sample | sort) <(grep -E "^[A-Za-z0-9_]+=" .env | sort)'
```

```bash
# 2. HF 側の Qwen3.8-Flash-Next-NVFP4 の main が指す revision (Mac でも head でも打てる)
#    fab0aecb… 以外を返したらキャッシュより先に進んでいる (→「重みの検証」)
curl -s https://huggingface.co/api/models/nvidia/Qwen3.8-Flash-Next-NVFP4 | python3 -c 'import json,sys;print(json.load(sys.stdin)["sha"])'
```
