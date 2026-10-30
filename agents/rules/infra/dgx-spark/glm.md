---
# 常駐読み込みさせないためのマーカー (このパスにマッチするファイルは存在しない)。
# 本ファイルは必要になったときに Read で参照する。
paths:
  - "__read-on-demand-only__"
---

# GLM 系 (DGX Spark)

- 種別: 環境リファレンス (系統別)
- 対象読者: 別セッション・別マシンで作業するエージェント (Claude Code / Codex / OpenCode)
- 最終確認: 2026-10-09 (レシピ v1.10 と Ablit)。sparkDash の記述は 2026-10-12、画像入力の障害の行は 2026-10-10
- 共通の前提 (接続・切り替え・障害時・既知の制約): `agents/rules/infra/dgx-spark.md`

GLM-5.3-Flash の EXL3 4 bpw 量子化版を、vLLM ではなく TensorFold (Python エンジン v0.6.0 にレシピのパッチ 96 本を当てたもの) の TP=2 で配信する系統である。1017 系も TensorFold を使うが、エンジンは Zig 版の別物である (→ `dgx-spark/1017.md`)。配信している重みは Ablit (`scripts/local.sh` の `ABLIT=1`) で、通常版も両ノードに残してあり、起動し直せば切り替えられる (→「通常版と Ablit の切り替え」)。

## 用語

| 名前 | 意味 | 定義箇所 | 生成者 | 消費者 |
| --- | --- | --- | --- | --- |
| GLM-5.3-Flash EXL3 | GLM-5.3-Flash を EXL3 4 bpw に量子化したチェックポイント `Mia-AiLab/GLM-5.3-Flash-EXL3-4bpw-TensorFold`。Ablit と区別するとき「通常版」と呼ぶ。配信名は `GLM-5.3-Flash-EXL3` | 「構成」 | 上流のチェックポイント | TensorFold |
| Ablit | 通常版の `o_proj` 30 本を、拒否を外した重みに差し替えたチェックポイント。HF で gated。配信名は通常版と同じ | 「構成」 | 上流のチェックポイント | TensorFold (`ABLIT=1`) |
| `ABLIT` / `HF_TOKEN` | `ABLIT=1` で Ablit を配信し thinking の既定を off にする設定と、gated の取得に要るトークン (`ABLIT=1` のとき必須) | `scripts/config.sh` | 人 (`scripts/local.sh` か環境変数) | `start.sh` / `scripts/prepare.sh` |
| GLM レシピ | 本系統のレシピ | head の `~/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold/` | 上流 (`git clone`) | 人 |
| `glm53-flash-tf` | コンテナ名 (**head と worker で同名**) | `scripts/config.sh` の `CONTAINER_NAME` | `start.sh` | `docker` |
| DFlash2 | 投機デコードの**別モデルのドラフタ**。本体と別に取って配る | `scripts/config.sh` の `DRAFTER` / `DFLASH2_ID` / `DFLASH2_REVISION` | 上流のチェックポイント | TensorFold |
| TR3 | レシピ v1.2 のチェックポイント。HF から消えていて取り直せない | 「構成」の「戻す用に残している重み」 | 上流 (取り直せない) | レシピ v1.2 (`1f3d909`) |
| `tf.patches` | イメージのラベルに入るパッチのハッシュ。`scripts/config.sh` の `image_hash` と一致すれば prepare.sh はイメージを取り直さない。CUDA 拡張のキャッシュもこの単位で分かれる | イメージのラベル | 上流のイメージ | prepare.sh / 人 |
| 準備済みの状態 | prepare.sh の完了記録。イメージ・重みの revision・パッチ・worker のどれかが変わると start.sh が prepare.sh を流し直す。`model=` で配信中の重みが分かる | head の `~/.local/state/glm53-tensorfold/prepared` | `scripts/prepare.sh` | `start.sh` / 人 |
| `~/.cache/glm53-tf-image` | v1.2 のイメージ `v0.5.0` を手で取ったときの blob 置き場 (11 GiB)。現行の手順では作らない | 両ノード | 人 (v1.2 の導入時) | なし |

`TensorFold`・`prepare.sh`・`scripts/local.sh` は 1017 系と同名で持つので、`dgx-spark.md`「用語・成果物一覧」にある。

## 構成

2026-10-09 にレシピ v1.10 (`7d42f90`) と Ablit で、起動と生成、3 経路 (`/v1/chat/completions` / `/v1/responses` / `/v1/messages`) の effort の陽性・陰性対照、`/v1/models` が `max_model_len` を返さないこと、サンプリングあり (`temperature` 1、`top_p` 0.95、thinking off) の 512 トークンが 42.1 tok/s で出ることを確かめた。OpenCode (opencode 2.0.22、V2) の `opencode run` の応答と、thinking の既定が off でも `max` を送ると思考が返ることは 2026-10-06 に v1.7.1 で、ツール呼び出しは 2026-10-04 に v1.5 と通常版で確かめた。どちらも v1.10 では打ち直していない。

**この構成には認証が無い。** レシピに API キーの設定項目が無く (`scripts/config.sh` と `start.sh` に `API_KEY` の文字列が無い)、ヘッダ無しの `/v1/models` が 200 を返す (2026-10-04 実測)。認証付きにする手段は確かめていない。ポート 8888 を信頼できないネットワークへ出さない (→ `dgx-spark.md`「動いているもの」)。

値の出所は `scripts/config.sh` の既定値と起動ログで、重みの 4 行とイメージの行は HF API と `docker image inspect` で確かめた。

| 項目 | 値 |
| --- | --- |
| レシピ | head の `~/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold` @ `7d42f90` (上流の v1.10、2026-10-08 リリース。Ablit の対応は v1.7 から)。上流は [MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold](https://github.com/MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold) |
| 推論エンジン | TensorFold v0.6.0 ([ashhart/TensorFold](https://github.com/ashhart/TensorFold)、イメージ内の `tensorfold --version` が `0.6.0`) + レシピの `patches/*.patch` 96 本。パッチはイメージに焼き込み済み。`NUCLEUS_UNION=1` が既定 (v1.9 から)。サンプリング時の nucleus を両ランクの候補を合わせて検査する設定で、上流は同じ draw になると書いている |
| 量子化 | routed experts が EXL3 の 4 bpw。それ以外の BF16 の重みは起動時に 4 bit へ量子化する (`DENSE=q4`) |
| 重み (Ablit) | `Mia-AiLab/GLM-5.3-Flash-EXL3-4bpw-TensorFold-Ablit` @ `57edefd2f5d9b371c8345883304d5af68b52fa24` (`ABLIT=1` のときの `MODEL_ID` と `MODEL_REVISION`)。snapshot は 100 ファイル (うち safetensors 83 本) / 175.7 GB (164 GiB)。両ノードの `~/.cache/huggingface/hub/models--Mia-AiLab--GLM-5.3-Flash-EXL3-4bpw-TensorFold-Ablit` (`du -sh` で 164 GiB、2026-10-06)。通常版との差は層 15〜43 と MTP 層 45 の `self_attn.o_proj` 30 本だけで (他のテンソルはバイト一致)、元の重みに対する変化量は 4.2〜18.7% (中央値 11.5%。モデルカードの値)。MIT。**HF で gated** で、取得には規約に同意したアカウントのトークンが要る (同意前は 403)。**通常版との品質・速度の比較は上流にも当方にも無い** |
| 重み (通常版) | `Mia-AiLab/GLM-5.3-Flash-EXL3-4bpw-TensorFold` @ `078455ffe6472f9a52fbc1139f58b9db2881b25c` (`ABLIT=0` のときの `MODEL_ID` と `MODEL_REVISION`)。snapshot は 97 ファイル (うち safetensors 83 本) / 175.7 GB (163.6 GiB)。両ノードの `~/.cache/huggingface/hub/models--Mia-AiLab--GLM-5.3-Flash-EXL3-4bpw-TensorFold` (`du -sh` で 164 GiB、2026-10-04)。MIT (HF のモデルカード。イメージのラベルにある Apache-2.0 はレシピ側のライセンス)。**HF の `main` は pin より先へ進んでいる** (2026-10-04 時点で `76c0b517…`)。`MODEL_REVISION` が動かない限り何もしない |
| 重み (ドラフタ) | `incoai/GLM-5.3-Flash-DFlash2` @ `bf582e4eacc1810f76656d1811693ff6c6737d2a` (`DFLASH2_REVISION`)、2.2 GiB。両ノードの `models--incoai--GLM-5.3-Flash-DFlash2`。**本体とは別リポジトリなので、取得も配布も別に要る。** CC BY-NC-ND 4.0 (非商用) |
| 戻す用に残している重み | TR3: `Mia-AiLab/GLM-5.3-Flash-EXL3-TR3-4bpw` @ `9eaebb7c4e96d983dcd538e18624622ba5b820a8` (164 GiB、両ノードの `models--Mia-AiLab--GLM-5.3-Flash-EXL3-TR3-4bpw`)。**HF から消えている** (API が 401 を返す。2026-10-03 確認)。消すと取り直せない (→「レシピを更新する」の v1.2 へ戻すとき) |
| モデルを差し替えるときに見るキー | `scripts/config.sh` が解決する `MODEL_ID` / `MODEL_REVISION` / `SERVED_NAME`。ドラフタが変わるなら `DFLASH2_ID` / `DFLASH2_REVISION` も |
| API 上のモデル名 (`SERVED_NAME`) | `GLM-5.3-Flash-EXL3` (大文字を含む) |
| コンテキスト上限 (`CONTEXT`) | 1 リクエスト 1,048,576 トークン (チェックポイントのネイティブ値)。**`/v1/models` は `max_model_len` を返さない**ので、`/health` の `context_length` で見る。`opencode.json` の `limit.context` は 500,000 で、サーバの約半分である (害は早めに圧縮が走ることだけ →`dgx-spark.md`「OpenCode」) |
| 同時リクエスト上限 (`PARALLEL`) | 4 リクエスト。v1.5 から 8 まで指定できるが、2 台での既定は 4 のまま。4 本は 1 つの KV プールを共有し、プールの大きさは起動ごとに変わる (→「KV プールの大きさは起動時の空きで決まる」)。プールに入りきらないリクエストはエラーにならず待つ |
| 投機デコード | DFlash2 (別モデルのドラフタ) と copy drafts。`DRAFT_POLICY=fnc7:0.3`、`COPY_MAX=15`。チェックポイントの MTP ヘッドは読まない |
| KV キャッシュ (`KV`) | `fp8` |
| メモリの予算 | 起動時の `MemAvailable` から `MEMORY_RESERVE_GIB` を引いた量。予備は `PARALLEL=4` で 14.5 GiB。5 本以上では 1 本ごとに約 0.95 GiB 増え、同時に検証窓 (`TF_GLM_MULTI_WINDOW`) が既定で 32 行から 64 行に広がるので、その分の約 1.28 GiB も乗る (5 本目の増分は計約 2.23 GiB)。このとき RoCE で送る all-gather の上限 (`TF_ROCE_MAX_KB`) も 512 KiB から 1024 KiB に上がる。KV プールの上積みは `KV_POOL_GIB` (12.5 GiB) まで。**vLLM の確保率に当たるキーは無い** |
| 画像・動画入力 | 使える (`VISION=1`。設定上の上限は 1 リクエストに画像 50 枚、動画 4 本)。画像 1 枚は 2026-10-04 に緑一色の 8x8 PNG で実測した。画像ありは「緑」、陰性対照の画像なしは「赤色」だった (`dgx-spark.md`「依拠する外部事実」のコードブロック 3)。**動画入力と枚数上限は未実測** |
| ツール呼び出し / reasoning | 使える。thinking の既定は Ablit で off (`ABLIT=1` が `THINKING` の既定を `0` にする。上流は Ablit を thinking off で使うと最良と書いている)、通常版で on。リクエストが effort を送ればそちらが効く。OpenCode は `max` を送るので、どちらの重みでも思考する (ユーザー判断、2026-10-05)。思考は `reasoning_content` に返る。上流の CHANGELOG によれば、v1.4 から前のターンの思考もプロンプトに残す (`TF_GLM_CLEAR_THINKING=1` で残さない) |
| ノード間通信 | 512 KiB までの all-gather は RoCE の one-shot RDMA write (`COMM=roce`)、それより大きいものは NCCL で送る。**RoCE は 2 本とも使う** (→「RoCE は 2 本とも使う」) |
| コンテナイメージ | `tensorfold-glm53:v0.6.0` (展開後 24.6 GB、Id `sha256:a24e8b6fdb176eea051b8508e1109e82cc8d5cd3159f4f1591567bf0fb32c939`)。中身は `ghcr.io/miaai-lab/glm-5.3-flash-exl3-2x-dgx-sparks-tensorfold@sha256:bc34d7d63f978cf601f42863b284bc95a567c50c10e9adb0866a635be568bf5f` (`scripts/config.sh` の `IMAGE_DIGEST`、タグは `IMAGE_TAG` の `v0.6.0-a1897d591f70`) で、ラベル `tf.patches` は `a1897d591f70`。両ノードに置いてある。通常版と Ablit は同じイメージで動く。ほかに残っているのは、v1.2 へ戻す用の `tensorfold-glm53:v0.5.0` (ラベル `cb7c56f7f921`) だけで、v1.5・v1.7・v1.7.1 のイメージは両ノードから消した (ユーザー判断)。**1017 系の重みの取得もこのイメージの python を使う** (→ `dgx-spark/1017.md`) |
| コンテナ名 | `glm53-flash-tf` (**head と worker で同名**)。restart policy は `no` で、ノードを再起動すると上がらない (2026-10-04 実測。→ `dgx-spark.md`「既知の制約」の自動復帰の項) |
| 上流既定からの差分 | `scripts/local.sh` の 3 行だけ。`WORKER=skanehira@<worker の RoCE アドレス>` (値は DeepSeek 系の `.env.dspark` の `WORKER_HOST` と同じ)、`ABLIT=1`、`HF_TOKEN=$(cat ~/.cache/huggingface/token)`。WORKER がリンク上のアドレスなので `FABRIC_PEER` は要らない。`.env` は置いていない |
| CUDA 拡張のキャッシュ | 両ノードの `~/.cache/tensorfold-glm53/` (head で 389 MiB、2026-10-09。ログを含む)。ビルド結果は `tf.patches` のハッシュごとのディレクトリ (現行は `a1897d591f70/`) に分かれ、新しいイメージの初回の起動でビルドされて以降は再利用される。最上位の `torch_extensions/` と `triton/` (計約 128 MiB、root 所有) は旧配置の残りで、現行のイメージは読まない (→「残骸の片付け (GLM 系)」) |
| サーバのログ | `stop.sh` が両ランクのログを gzip で保存してからコンテナを消す。置き場は各ノードの `~/.cache/tensorfold-glm53/logs/<日付>-<時刻>-rank<N>.log.gz` (head に rank 0、worker に rank 1) で、新しいものから 10 本を残す。start.sh も、前回の停止済みコンテナを消す前に同じように保存する |

## 起動と判定

```bash
ssh spark-head
cd ~/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold
./start.sh                      # 両ランクの起動。準備が要れば scripts/prepare.sh を自動で流し、スモークテストまで行う
./start.sh restart              # 設定を変えた後の再起動 (下の注意を読む)
./stop.sh                       # 両ランクの停止 (ログを保存してからコンテナを消す)
docker logs -f glm53-flash-tf   # rank 0 のログ。rank 1 は worker で同じものを打つ
```

- **エージェントのシェル実行から打つときはログインシェルを通す。** `ssh -n spark-head 'bash -lc "cd ~/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold && setsid nohup ./start.sh > ~/glm53-tf-start.log 2>&1 < /dev/null &"'` の形で起動し、ログを読む (理由は「導入の落とし穴」1)。**この ssh は start.sh が終わるまで戻らないことがある** (2026-10-04 に 7 分戻らなかった) ので、バックグラウンドで打つ。終わりは `until ! ssh -n spark-head 'pgrep -f "^bash ./start.sh$" >/dev/null'; do sleep 30; done` で待つ (パターンを `^…$` で固定しているので待ちの ssh 自身には一致しない)。`tail -25 ~/glm53-tf-start.log` に `is now LIVE!` があれば成功、`ERROR` があれば失敗である
- **状態表示のサブコマンドは無い。** 状態は `docker ps` と `/health` で見る
- **`./start.sh restart` は prepare.sh を流してから止める。** 引数なしの `./start.sh` は、両ランクが動いていれば prepare.sh の前に `already running` と出して exit 0 する。準備が要る状態 (pin を動かした `git pull` の後など) で `restart` を打つと、配信中に prepare.sh の取得 (WiFi と dockerd) が走る
- **メモリの事前検査は警告だけで止まらない。** 両ノードの `MemAvailable` が 110 GiB 未満だと警告を出して進む。予算が足りなければ rank 0 が窓を拒否し、start.sh は収まる窓で 1 回だけ起動し直す。そのときログに `this start's memory budget holds a N-token window` が出るので、これが出たら合格扱いにしない
- **ポートの事前検査は止まる。** 8888 が使用中なら `port 8888 is already in use` で終了する
- **スモークテストは同じ文字を繰り返すだけの応答を失敗として扱う** (v1.9 から)。モデルが崩れて `!!!!` のような応答を返すと起動が失敗し、ランクは動いたまま残り、エラーは README の Ablit の節を指す。通常版で起動し直すなら「通常版と Ablit の切り替え」の `ABLIT=0` を使う。2026-10-09 の Ablit での起動は `OK: 'OK'` で通った
- **準備済みかどうかは start.sh が判定する** (→「用語」の準備済みの状態)。`PREPARE=0` で prepare.sh を飛ばせる

**起動できたかは 3 段で判定する。** どれも exit code で合否が出る。start.sh 自身もスモークテストを流すので、ログの `GLM-5.3-Flash-EXL3 is now LIVE!` も合格の条件に入れる。

```bash
curl -fs -o /dev/null http://spark-head.local:8888/health && echo health-ok   # 1. API が生きている
curl -s http://spark-head.local:8888/v1/models | python3 -c 'import json,sys; ids=[m["id"] for m in json.load(sys.stdin)["data"]]; print(ids); sys.exit(0 if "GLM-5.3-Flash-EXL3" in ids else 1)'   # 2a. 配信名
curl -s http://spark-head.local:8888/health | python3 -c 'import json,sys; c=json.load(sys.stdin)["context_length"]; print(c); sys.exit(0 if c==1048576 else 1)'   # 2b. 文脈長 (/v1/models は返さない)
curl -s http://spark-head.local:8888/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"GLM-5.3-Flash-EXL3","messages":[{"role":"user","content":"17*19 を計算して、答えの数値だけを出力してください。説明や単位は不要です。"}],"temperature":0,"max_tokens":2048,"chat_template_kwargs":{"enable_thinking":false}}' \
  | python3 -c 'import json,sys; c=json.load(sys.stdin)["choices"][0]["message"]["content"].strip(); print(repr(c)); sys.exit(0 if c=="323" else 1)'   # 3. 生成が通る
```

**どちらの重みで動いているかは API では分からない** (配信名が同じため)。head の準備済みの状態の `model=` か、起動ログの `Rank 0 here: tensorfold serve` の行にある snapshot のパスで見る。

```bash
ssh -n spark-head 'grep -o "model=[^ ]*" ~/.local/state/glm53-tensorfold/prepared'   # Ablit なら …-TensorFold-Ablit@57edefd2…
```

**起動の実測値 (2026-10-09、v1.10 の新しいイメージと Ablit での初回の起動)。** CUDA 拡張のビルドを含む。prepare.sh は照合だけで終わり、ログに `already built with patches a1897d591f70`、`identical on both Sparks`、`Worker has … Ablit @ 57edefd2` が出た。初回の起動は 1 回で通った。2 本目の rail の疎通確認は `used` と出た (→「RoCE は 2 本とも使う」)。メモリの 4 行は、判定の生成を 10 件ほど流した後の値である。

| 項目 | 値 |
| --- | --- |
| 起動全体 (start.sh の開始から LIVE まで) | 約 7.5 分 (`Server answered after 452s`、サーバ側は `loaded in 449.6s`) |
| KV プール | 1,419,264 トークン (1 リクエストは最大 1,048,576) |
| GPU の確保 (head / worker) | 91,754 / 90,600 MiB (89.6 / 88.5 GiB) |
| `MemAvailable` (head / worker) | 16.9 / 13.7 GiB |
| swap 使用 (head / worker) | 2.7 / 3.7 GiB |

**起動の正常な所要は約 5〜7 分である。** 実測は 2026-10-02 のビルド済みの起動 (v1.2) で 304 秒、新しいイメージの初回 (CUDA 拡張のビルド込み) は 2026-10-04 (v1.5) で 422 秒、2026-10-06 (v1.7 と v1.7.1、Ablit) で 425 秒と 437 秒、2026-10-09 (v1.10、Ablit) で 452 秒だった。start.sh は `WAIT_TIMEOUT` (既定 1,800 秒) で諦める。

**無負荷で 12〜15 GiB 残る** (2026-10-04 の実測で head / worker が 14.3 / 12.8 GiB。2026-10-09 は上の表の 16.9 / 13.7 GiB)。起動時の空きから 14.5 GiB を残して予算を組むためで、先取りではない。上流は 1M トークンの prompt で head の空きが約 4.5〜5.6 GiB まで下がると書いている (`scripts/config.sh` のコメントと CHANGELOG)。

## reasoning effort の語彙

**検査はサーバが行い、深さはサーバの読み替えとテンプレートで決まる。** サーバ (TensorFold の `server/request_options.py`) は 7 語を受理し、それ以外を 400 で弾く。受理した値はサーバの `coerce_effort` がテンプレートの語に読み替え、テンプレート (チェックポイントの `chat_template.jinja`) は `low` と `high` 以外をすべて `max` として描く。表の 200 / 400 は HTTP ステータスである。

| 値 | `/v1/chat/completions` (OpenCode の経路) | `/v1/responses` | 実際に効く深さ |
| --- | --- | --- | --- |
| `low` / `minimal` | 200 | 200 | `low` (`minimal` はサーバが `low` に読み替える) |
| `medium` / `high` | 200 | 200 | `high` (`medium` はサーバが `high` に読み替える) |
| `xhigh` / `max` | 200 | 200 | `max` (`xhigh` はテンプレートが `max` として描く) |
| `none` | 200 | 200 | thinking なし |
| 指定なし | — | — | 通常版は `max`、Ablit は thinking なし (`THINKING` の既定が重みで変わる) |
| 語彙外 (`bogus` など) | 400 | 400 | — |

- **400 の本文は受理語彙を名乗る**: `reasoning_effort must be none, minimal, low, medium, high, xhigh or max`。弾いているのは TensorFold のサーバで、vLLM のスキーマ検証ではない
- **「実際に効く深さ」の列はソースとテンプレートから読んだもので、応答の思考の量では確かめていない。** テンプレートは新旧 2 つのチェックポイントでバイト一致する
- **`none` の扱いが vLLM 版と違う。** TensorFold は `none` を thinking の無効化として扱う
- **OpenCode は `opencode.json` で `max` を明示する。** テンプレート既定が変わっても推論が浅くならないようにしている
- **対照は陽性 `bogus` (400) / 陰性 `max` (200) で、3 経路とも打つ。** 2026-10-04 に通常版で 8 値すべてを `/v1/chat/completions` と `/v1/responses` で実測した。2026-10-06 (v1.7.1) と 2026-10-09 (v1.10) に Ablit で `bogus` / `max` / `none` を両経路で打ち直し、どちらも 400 / 200 / 200 だった
- **Ablit で「指定なし」と `max` の差を実測した** (2026-10-06、「2+3 は?」、`temperature` 0)。指定なしは `reasoning_content` が 0 文字、`max` は 462 文字だった。2026-10-09 (v1.10) の `max` も 462 文字だった
- **`/v1/messages` の effort は `output_config.effort` で渡す** (レシピのパッチ `0084-anthropic-messages.patch`)。2026-10-09 に Ablit で、`bogus` が 400 (`unsupported output_config.effort`)、`none` / `low` / `max` が 200 を返した
- **`/v1/messages` では effort だけでは thinking が入らない。** Ablit に `output_config.effort: max` だけを送ると thinking ブロックは返らない。`thinking: {"type": "enabled", "budget_tokens": …}` を足すと、`/v1/chat/completions` の `max` と同じ 462 文字の思考が返る (2026-10-09、「2+3 は?」、`temperature` 0)

## 使える API

| API | 用途 | 状態 |
| --- | --- | --- |
| `/v1/chat/completions` | OpenCode | 使える。opencode 2.0.22 (V2) の `opencode run --standalone` で、ファイルを読ませる指示が Bash (`ls`) → Read のツール呼び出しを経て正答した (2026-10-04、v1.5) |
| `/v1/responses` | Responses API | 使える。effort の 7 語がすべて 200 で通り、content パーツの `input_text` も 200 で受ける (2026-10-04、v1.5)。V4.1 EXL3 系と違いパッチは要らない |
| `/v1/messages` | Anthropic Messages API | 使える (レシピ v1.9 のパッチ `0084` から。v1.8 までは 404)。`17*19` に `323` を `stop_reason: end_turn` で返した (2026-10-09、v1.10) |
| `/health` | `stop.sh` と手動の状態確認 | `busy` / `requests_running` / `streams` / `pool_tokens` / `pool_free_tokens` / `context_length` / 累計のカウンタなどを返す |
| `/metrics` | — | `tensorfold:` と `tensorfold_health:` の系列だけを出す。**`vllm:` の系列は無い** (2026-10-09 も 0 行) |

**`/v1/models` は `id` / `object` / `owned_by` の 3 キーしか返さない** (上限の見方は「構成」のコンテキスト上限の行)。`owned_by` は `tensorfold` なので、OpenCode 組み込みの vLLM 自動発見には拾われない (→ `dgx-spark.md`「OpenCode」)。

**配信していないモデル名で要求しても応答を返す** (2026-10-04 再確認)。クライアントが古いモデル名を送り続けても `model not found` にならず、GLM がそのまま答えるので気づきにくい。

**`vllm:` の系列が無いので、待ち行列と受理率は `/health` から読む。** `dgx-spark.md`「系統の切り替え」の手順 1 では `requests_running` が 0 であることを見る。

```bash
curl -s http://spark-head.local:8888/health | python3 -c 'import json,sys; h=json.load(sys.stdin); print("running", h["requests_running"], "streams", h["streams"])'
```

`/health` の累計値から、prefix ヒット率 ≒ `cached_tokens_total` ÷ `prompt_tokens_total`、受理率 ≒ `accepted_total` ÷ `drafted_total` で出せる。キーの意味はキー名から読んだもので、TensorFold のソースでは確かめていない。`dgx-spark.md`「遅いと感じたときに疑う順序」の 3 と 4 の実測レンジは vLLM の値なので、GLM 系の判定には使えない。

**sparkDash (v2.32.0) は GLM 配信中も LLM のメトリクスを表示する。** 応答から TensorFold を見分けて読む。2026-10-12 に `curl -s http://spark-head:5555/api/sparks/spark-head/metrics` の `metrics.llm` が `backend: tensorfold`・配信名・`contextLength` 1,048,576・decode と prefill の tok/s を返すことを確かめた。

## 導入手順

初回の導入と、イメージや重みの pin が動く更新とで同じ手順を使う (2026-10-04・06・09 の更新で踏んだ)。重みとドラフタの pin が動かなかった v1.10 への更新は 2〜4 を飛ばし、停止から LIVE まで約 13 分 (手順 6 は約 5 分) だった。

**8888 を止めずに進められるのは 1〜4 までで、5 からは配信が止まる。** 1〜4 を配信中に流せるのは、既存イメージで上限付きの取得ができる場合に限る。手元にイメージが無い初回は、手順 5 の停止確認を先に行ってから取得する。**dockerd を通る `docker pull` / `docker load` と prepare.sh の取得は、配信を止めてから流す** (dockerd の側にはメモリの上限が掛からない)。例外は手順 2 の `docker run --memory 2g` で、取得はコンテナの中で上限付きで走る (→ `dgx-spark.md`「既知の制約」11)。コマンドはすべて head のレシピのディレクトリで打つ。

数時間かかる段は `dgx-spark.md`「長い処理を ssh から切り離す」の型で流す。2026-10-06 の Ablit 導入ではこの型を 4 回 (時刻指定の取得 5 時間 45 分、worker への rsync、イメージの転送、start.sh) 使い、4 回とも `EXIT=0` で終わった。

1. **レシピを用意する** — 初回は `git clone https://github.com/MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold ~/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold` のあと、`scripts/local.sh` に `WORKER=skanehira@<worker の RoCE アドレス>`・`ABLIT=1`・`HF_TOKEN=$(cat ~/.cache/huggingface/token)` の 3 行を書く (通常版だけを使うなら後ろ 2 行は要らない)。更新は「レシピを更新する」の `git pull --ff-only`。**完了判定**: `bash -c 'source scripts/config.sh >/dev/null 2>&1; echo "$MODEL_ID@$MODEL_REVISION $IMAGE $IMAGE_TAG"; image_hash'` を打ち、`image_hash` が `IMAGE_TAG` の末尾と一致すること。一致していれば prepare.sh は pin した digest のイメージを使う
2. **本体の重みを head だけで取る (配信中、約 6 時間)** — `utility-spark-model-fetch` スキルの手順 1・2 に従う。head のホスト側 python には `huggingface_hub` が無いので、手元にある `tensorfold-glm53` のイメージの python で取る。`<イメージ>` は `docker images` に出る `tensorfold-glm53:*` のどれでもよい (更新のときは旧版。旧イメージは取得が終わるまで消さない)。**Ablit は gated なので、先に HF のモデルページで規約に同意する。** 同意済みかは head で `curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $(cat ~/.cache/huggingface/token)" https://huggingface.co/<MODEL_ID>/resolve/<MODEL_REVISION>/config.json` が 200 を返すことで見る (同意前は 403)。コンテナは `~/.cache/huggingface` を `/hf` に mount するので、トークンファイルがそのまま使われる。`<MODEL_ID>` と `<MODEL_REVISION>` は手順 1 の完了判定の出力から取る。ssh を切っても止まらないように dockerd の管理するコンテナで流す (`systemd-run --user --scope` は使わない。linger が無効 (`Linger=no`) なので、最後のセッションが閉じると scope が止まりうる。systemd の仕様からの推定で未確認)

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
   - **手元に `tensorfold-glm53` のイメージが 1 つも無い初回は、この形が使えない。** 代わりにログインシェルの `hf` で取る。`HF_HUB_DISABLE_XET=1 HF_MAX_WORKERS=2 hf download <MODEL_ID> --revision <MODEL_REVISION> --cache-dir ~/.cache/huggingface/hub` を head の `~/glm53-dl.sh` に引用済み heredoc で保存し (先頭に `set -euo pipefail`)、`<名前>` を `glm53-dl` にして切り離す。メモリの上限は掛からないので、手順 5 の停止確認後に流す。**この形は未実行である**
   - **完了判定**: 終了コードが 0 で、`verify_shards.py` が「必要 N / 揃い N / 欠落 0」で exit 0 を返すこと (N は index に載る shard 数。通常版と Ablit はどちらも 83)。`verify_shards.py` はスキル同梱のものを Mac から head の `/tmp/vs.py` へ scp して `python3 /tmp/vs.py models--<org>--<name>` で打つ (スキルの手順 5)。手順 3 の前に head から worker の `/tmp/vs.py` へも scp する。初回と各ノードの再起動後は `/tmp` が空になるので両ノードへ配り直す。`find <モデルのディレクトリ> -user root` が 0 件であること。**index が届く前の `verify_shards.py` は手元にある shard だけを必要分と数えるので、取得途中では欠落を検出できない**
3. **worker へ rsync する (配信中、約 8 分)** — スキルの手順 3〜6 に従う (所有権の確認、`rsync -a --delete --info=progress2 --no-inc-recursive`、ログの `denied` が 0、両ノードの `verify_shards.py` の一致、`.incomplete` の削除と再検証)。`-L` は付けない。付けると snapshot の symlink が実体になり、worker が重みを二重に持つ。**完了判定**: 加えて、prepare.sh と同じ照合が一致すること。照合は snapshot で `find -L . -type f -printf '%P %s\n' | LC_ALL=C sort` を両ノードで取って `cmp` する (v1.5 の本体で 97 行)。一致していれば prepare.sh は `Worker has …` と出してコピーを飛ばす
4. **ドラフタ** — `DFLASH2_REVISION` が動いていなければ何もしない。動いたら DFlash2 でも 2〜3 を行う (`<MODEL_ID>` を `DFLASH2_ID`、`<MODEL_REVISION>` を `DFLASH2_REVISION` の値にする。どちらも `bash -c 'source scripts/config.sh >/dev/null 2>&1; echo "$DFLASH2_ID@$DFLASH2_REVISION"'` で出る)
5. **配信中の系統を止める** — `dgx-spark.md`「系統の切り替え」の手順 1〜3。GLM 系の配信中なら `/health` の `requests_running` が 0 であることを見てから `./stop.sh`
6. **イメージを head に取り、worker へ送る (約 25 分)** — head は GHCR から WiFi で取り、worker へは RoCE で送る。prepare.sh に任せると worker も WiFi で取る。**Mac からの ssh 1 本で前景で流すと、出力の無い転送中に Mac 側の ssh がタイムアウトする** (2026-10-04。head 上の転送は完走した)。次の引用済み heredoc で head の `~/glm53-image.sh` に保存し、`dgx-spark.md`「長い処理を ssh から切り離す」の型で `<ディレクトリ>` をレシピのディレクトリ、`<名前>` を `glm53-image` にして流す。`IMAGE` などはスクリプト内で `source` した後に展開される

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
7. **起動** — 「起動と判定」の形で `./start.sh` を打つ。prepare.sh が流れ、照合だけで終わる (ログに `already built with patches` / `identical on both Sparks` / `Worker has` が出る)。新しいイメージの初回は CUDA 拡張のビルドが入るので約 7 分かかる。**失敗したら** head のログを先に読む。worker 側の `RDMA write to rank 0 failed: transport retry counter exceeded` は、rank 0 が落ちた後の二次症状である
8. **判定** — 「起動と判定」の 3 段と、「reasoning effort の語彙」の陽性対照・陰性対照を 3 経路で流し、すべて期待どおりであること
9. **クライアント側** — `opencode.json` の宣言はそのまま効く。sparkDash の表示は配信名に追従するので触らない (→ `dgx-spark.md`「sparkDash の worker の表示名」)

## 導入の落とし穴

1. **`hf` が非ログインシェルの PATH に無い** (`~/.local/bin` にある)。`ssh -n spark-head '…'` で直接 prepare.sh や start.sh を打つと、重みの取得が `hf` ではなくコンテナ内の python に回る。必ず `bash -lc` を通す
2. **`./start.sh restart` で更新を始めない。** prepare.sh が配信を止める前に走り、配信中に WiFi と dockerd を使う (→「起動と判定」)
3. **`scripts/local.sh` は無視されていない。** レシピは `.gitignore` を持たないので、`git status` に `?? scripts/local.sh` と出る。追跡ファイルではないので `git pull` は通る。`git add` でステージされうるので、`HF_TOKEN` の値は `local.sh` に平文で書かず、`$(cat ~/.cache/huggingface/token)` で読ませる
4. **ドラフタの revision を上げると重みが変わる。** `dc77ff1c` から `bf582e4e` では `model.safetensors` の sha256 が変わっていた。pin が動いたら HF の tree API でファイルの差を見てから取る
5. **Ablit は規約に同意するまで 403 を返す。** トークンが正しくても、そのアカウントがモデルページで同意していなければ取れない。fine-grained トークンなら「public gated repos の read」も要る。prepare.sh は 401 / 403 を取得の前に名指しして止まる
6. **`HF_TOKEN` は環境変数でないと start.sh が止まる。** `ABLIT=1` の検査 (`need_hf_token`) は環境変数を見るので、`~/.cache/huggingface/token` があるだけでは `The Ablit weights … are gated` で止まる。`scripts/local.sh` に `HF_TOKEN=$(cat ~/.cache/huggingface/token)` と書けば、平文の複製を作らずに済む
7. **新しいイメージを `docker tag` するとタグが移る。** タグ `tensorfold-glm53:v0.6.0` は TensorFold の版だけで決まるので、パッチが変わってもタグ名は同じである。旧イメージはタグを失って Id だけで残り、`docker images` の `tensorfold-glm53` の行には出ない。旧イメージは `docker images -a --filter dangling=true` で見つかり、`docker image inspect -f '{{index .Config.Labels "tf.patches"}}' <Id>` でどの版かを確かめてから `docker rmi <Id>` で消す。そのハッシュの CUDA 拡張のキャッシュも一緒に消す (→「残骸の片付け (GLM 系)」)

## レシピを更新する

```bash
ssh spark-head
cd ~/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold
git fetch -q && git log --oneline HEAD..origin/main   # 先行分を読む
git diff HEAD..origin/main -- CHANGELOG.md scripts/config.sh   # イメージと重みの pin が動くかを見る
git pull --ff-only
```

- **`scripts/config.sh` の `IMAGE_TAG` / `IMAGE_DIGEST` / `MODEL_ID` / `MODEL_REVISION` / `DFLASH2_REVISION` が動いたら、「導入手順」の 2〜8 を流す。** pull しただけでは配信に影響しない。引数なしの `./start.sh` も、配信中なら何もせずに終わる
- **HF 側の `main` が pin より先へ進んでいても何もしない。** レシピが revision を固定しているので、`MODEL_REVISION` が動くまで配信には効かない
- **`patches/` だけが変わって新しいイメージが公開されていない場合、prepare.sh はイメージをローカルでビルドする。** 公開済みかは CHANGELOG.md の「Image」の行で見る
- **更新後の悪化確認**は「導入手順」の 8 で行う
- **重みだけを通常版へ戻すとき**は「通常版と Ablit の切り替え」の `ABLIT=0` で足りる。レシピとイメージは今の版のまま動く
- **v1.10 より前、v1.2 より後のレシピへ戻すとき**は、そのイメージを取り直すことになる (v1.5・v1.7・v1.7.1 のイメージは消してある)。`git checkout <コミット>` のあと「導入手順」の 5〜8 を流す (prepare.sh がイメージを取り直すかは版による)
- **v1.2 へ戻すとき**は `./stop.sh` → `git checkout 1f3d909` → `./start.sh` と打つ。`1f3d909` は v1.2 で、TR3 の重みと `tensorfold-glm53:v0.5.0` を使う。どちらも両ノードに残してあるので、取り直しは起きない。TR3 は HF から消えているが、v1.2 の prepare.sh は取得に失敗しても手元の snapshot で続行する (ソースから読んだ挙動で、実行しては確かめていない)。**TR3 か v0.5.0 を消すと v1.2 へは戻せない。** 消してよいかは、現行の版で困ることが無いと判断してから決める

## 通常版と Ablit の切り替え

**切り替えはサーバ側だけで済み、OpenCode の設定は変えない。** 配信名が同じなので、`opencode.json` の宣言とプラグインの選択はどちらの重みにも当たる。両方の重みが両ノードにあり同じイメージで動くので、取得も CUDA 拡張のビルドも起きない。head のレシピのディレクトリで、エージェントのシェル実行からは「起動と判定」の `bash -lc` の形で打つ。

```bash
./stop.sh && ABLIT=0 ./start.sh   # 通常版
./stop.sh && ABLIT=1 ./start.sh   # Ablit (scripts/local.sh の既定)
```

- **環境変数は `scripts/local.sh` より優先する** (`scripts/config.sh` の冒頭のコメントと実装)。ファイルを書き換えずに一時的に切り替えられる。`ABLIT=0` で起動したままにしておくと、次に素の `./start.sh` を打ったときに Ablit へ戻る
- **重みが変わるので prepare.sh が流れる** (準備済みの状態の `model=` が変わるため)。照合だけで終わり、起動はビルド済みの 2 回目以降と同じく約 5〜7 分と見ている。Ablit で起動するときだけ HF への到達確認が走る
- **thinking の既定も一緒に切り替わる** (Ablit で off、通常版で on)。OpenCode は `max` を送るので、OpenCode からの挙動は変わらない
- **この往復は未実行である** (2026-10-06 時点)。設定とソースから組み立てた手順なので、初回は「起動と判定」の 3 段と `model=` の確認で確かめる

## KV プールの大きさは起動時の空きで決まる

**プールは起動のたびに変わる。** 各ランクは起動時に「予算」(その時点の `MemAvailable` − 14.5 GiB) と、重みと 1 リクエスト分の窓に要る「見積り」をログに出す。プールに回るのはその差 (上限 12.5 GiB) である。

| 起動 | rank 0 の予算 / 見積り | rank 1 の予算 / 見積り | プール |
| --- | --- | --- | --- |
| 2026-10-01 (レシピ v1.2) | 100.53 / 88.09 GiB | 98.53 / 86.29 GiB | 2,883,584 トークン |
| 2026-10-04 (レシピ v1.5) | 98.26 / 88.09 GiB | 92.37 / 86.29 GiB | 1,562,624 トークン |
| 2026-10-06 (レシピ v1.7、Ablit) | 96.96 / 88.09 GiB | 92.92 / 86.29 GiB | 1,650,688 トークン |
| 2026-10-06 (レシピ v1.7.1、Ablit) | 96.98 / 88.09 GiB | 91.62 / 86.29 GiB | 1,443,840 トークン |
| 2026-10-09 (レシピ v1.10、Ablit) | 96.26 / 88.09 GiB | 91.48 / 86.29 GiB | 1,419,264 トークン |

2026-10-04 以降の起動では worker の空きが 106〜108 GiB しかなく (start.sh が 110 GiB 未満の警告を出した)、rank 1 の差は 5.2〜6.6 GiB にとどまった。**プールは差の小さいランクに合わせて決まると見ている** (根拠は上の 5 回の起動ログだけで、ソースでは確かめていない)。見積りは通常版と Ablit で同じである (重みの形が同じため)。プールが小さくても 1 リクエストの上限 1,048,576 は変わらないが、長い会話を同時に抱えられる量が減る。上限近くまで戻したいときは、両ノードの空きが大きいとき (この推定では head 115 GiB・worker 113 GiB 以上) に起動し直す。

## RoCE は 2 本とも使う

**起動ログの `Link:` 行は `RoCE rocep1s0f1,roceP2p1s0f1 / rocep1s0f1,roceP2p1s0f1` と出る** (2026-10-04)。レシピの `scripts/nodes.sh` の `rails()` は、リンクと同じサブネットの port に加えて、名前の末尾 (`f1np1`) が同じ PCIe の双子を拾う。当方の 2 本目は別サブネットにあるが、この規則で足される。

**2 本目を使う前に start.sh が疎通を確かめる** (`probe_rails`、v1.10 から)。head と worker の同じ位置の rail どうしで、互いの rail のアドレスへ MTU いっぱいの断片化禁止 ping を打つ。通らなかった rail は `second rail … does not reach the peer: NOT used` の WARN を出して外し、1 本で起動する。**この WARN が出ても起動は成功する**ので、ログで見落とさない。2026-10-09 の起動では `Rail roceP2p1s0f1 <-> roceP2p1s0f1: … reaches the peer (MTU 9000): used` と出て、`Link:` 行は `2 rail(s)` だった。

**アドレスは変えない。** 2 本を同じサブネットに置くと、vLLM の 3 系統が `no usable RoCEv2 GID` で起動しなくなる (→ `dgx-spark.md`「ネットワーク」)。上流は 2 本使うと prompt chunk の all-gather が約 1.8 倍速いと書いている。当方では prefill の速さを 1 本のときと比べていない。

## 障害時 (GLM 系)

共通の症状 (応答しない・コンテナが無い・起動に失敗する・起動待ちが長い) は `dgx-spark.md`「障害時」にある。GLM 系では、起動の失敗は `docker logs glm53-flash-tf` で読む (start.sh も失敗時に両ランクの末尾を出し、停止済みのランクのログは `~/.cache/tensorfold-glm53/logs/` に残る)。

| 症状 | 確認 | よくある原因 |
| --- | --- | --- |
| 画像入力だけが `CUBLAS_STATUS_INTERNAL_ERROR` で失敗する (テキストの生成は通る) | head の `docker logs glm53-flash-tf` で、エラーのトレースが `tensorfold/vision/glm.py` を通っているか。worker のカーネルログ (`journalctl -k`) に `NV_ERR_NO_MEMORY` があるか。worker の `MemAvailable` と `ps -o pid,rss,etimes -C polkitd` | 2026-10-10 に 1 回起きた。worker の polkitd が 35 日の稼働で RSS 5.2 GB (ほかに swap 3.1 GB) まで育ち、配信中の `MemAvailable` が 6.7 GiB (起動直後は 13.7 GiB) まで減っていた。最初のエラーの直前に worker のカーネルが `NV_ERR_NO_MEMORY` を 3 回記録していた (時刻が一致するだけで、因果は未確認)。worker で `sudo systemctl restart polkit` (sudo は人が打つ →`dgx-spark.md`「既知の制約」の sudo の項) を打ち、`./stop.sh` →`dgx-spark.md`「系統の切り替え」の手順 3 → `./start.sh` で復旧した。復旧の判定は `dgx-spark.md`「依拠する外部事実」のコードブロック 3 (画像入力) で行う。テキストの生成は障害中も通るので判定にならない。polkit とコンテナの再起動のどちらが効いたかは切り分けておらず、polkitd が育つ原因も調べていない |

## 残骸の片付け (GLM 系)

取り直せないものを消すかは人が決める。

| 残骸 | 置き場 | 消してよい条件 | 消し方 |
| --- | --- | --- | --- |
| TR3 の重み (164 GiB) | 両ノードの `~/.cache/huggingface/hub/models--Mia-AiLab--GLM-5.3-Flash-EXL3-TR3-4bpw` | レシピ v1.2 へ戻す必要が無いとユーザーが決めたとき。**HF から消えているので、消すと取り直せない** | 両ノードで `rm -rf` |
| `tensorfold-glm53:v0.5.0` (24.6 GB) | 両ノードの docker | TR3 と同じ (v1.2 へ戻すときに使う) | 両ノードで `docker rmi tensorfold-glm53:v0.5.0` |
| `~/.cache/glm53-tf-image` (11 GiB) | 両ノード | いつでも (v0.5.0 は読み込み済み) | `rm -rf ~/.cache/glm53-tf-image` |
| CUDA 拡張の旧配置 (`torch_extensions/` と `triton/`、約 128 MiB、root 所有) | 両ノードの `~/.cache/tensorfold-glm53/` 直下 | いつでも (現行のイメージは読まない) | root 所有なのでコンテナ経由で消す: `docker run --rm -v ~/.cache/tensorfold-glm53:/c --entrypoint rm tensorfold-glm53:v0.6.0 -rf /c/torch_extensions /c/triton` (この形は未実行) |
| タグを失った旧イメージ (新しいイメージを `docker tag` すると生じる →「導入の落とし穴」7。2026-10-09 時点で該当なし) | 両ノードの docker | その版へ戻す必要が無いとユーザーが決めたとき | `docker images -a --filter dangling=true` で Id を見つけ、`tf.patches` のラベルで版を確かめてから、両ノードで `docker rmi <Id>` |
| 古いイメージの CUDA 拡張 (`~/.cache/tensorfold-glm53/<パッチのハッシュ>/`、root 所有。2026-10-09 時点で該当なし) | 両ノード | そのハッシュのイメージを消したとき | 上と同じくコンテナ経由。2026-10-09 に `1692d2df78d2/` をこの形で消した: `docker run --rm -v ~/.cache/tensorfold-glm53:/c --entrypoint rm tensorfold-glm53:v0.6.0 -rf /c/<ハッシュ>` |
| 起動と導入のログ | head の `~/glm53-tf-start.log`、2026-10-06 の Ablit 導入の `~/glm53-ablit-fetch.{sh,log}` / `~/glm53-ablit-rsync.{sh,log}` / `~/glm53-image.{sh,log}` | 読み終えたらいつでも (次の起動で上書きされる) | `rm` |

## 依拠する外部事実 (GLM 系)

作業前に変わっていないか確かめる。確認コマンドにキーは要らない (無認証のため)。

| 事実 | 確認コマンド | 確認日 |
| --- | --- | --- |
| GLM レシピの commit | `ssh -n spark-head 'cd ~/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold && git log --oneline -1'` (2026-10-09 時点 `7d42f90`、v1.10)。上流の先行分は同じディレクトリで `git fetch -q && git log --oneline --stat HEAD..origin/main` (2026-10-09 時点で先行なし) | 2026-10-09 |
| 上流既定からの差分 | レシピのディレクトリで `cat scripts/local.sh; ls .env 2>/dev/null; git status --short` (`local.sh` の行は worker のアドレスを出すので証跡として貼らない)。**`WORKER=`・`ABLIT=1`・`HF_TOKEN=$(cat ~/.cache/huggingface/token)` の 3 行だけで、`.env` が無く、`git status` が `?? scripts/local.sh` だけなら合格** | 2026-10-06 |
| イメージと clone のずれ | レシピのディレクトリで `docker image inspect -f '{{index .Config.Labels "tf.patches"}}' tensorfold-glm53:v0.6.0` と `bash -c 'source scripts/config.sh; image_hash'` を比べる。**一致すれば prepare.sh はイメージを取り直さない** (2026-10-09 は両方 `a1897d591f70`) | 2026-10-09 |
| どちらの重みで配信しているか | 「起動と判定」の `model=` の grep (Ablit なら `…-TensorFold-Ablit@57edefd2…`) | 2026-10-09 |
| TensorFold の API の形 | `curl -s http://spark-head.local:8888/v1/models` の各要素のキーが `id` / `object` / `owned_by` の 3 つで `max_model_len` が無いこと。上限は `curl -s http://spark-head.local:8888/health` の `context_length` (1048576)。`/v1/messages` への POST が 200 で生成を返すこと (陰性対照として存在しないパスは 404 を返す →「使える API」) | 2026-10-09 |
| 受ける reasoning effort | 陽性対照 `bogus` (400、本文が受理語彙を名乗る) / 陰性対照 `max` (200) を 3 経路で打つ。`/v1/chat/completions` は `reasoning_effort`、`/v1/responses` は `"reasoning":{"effort":"<値>"}`、`/v1/messages` は `output_config.effort`。打ち方の雛形は `dgx-spark.md`「依拠する外部事実」の effort の行 | 2026-10-09 (8 値の全数は 2026-10-04、通常版) |
| 画像入力が通るか | `dgx-spark.md`「依拠する外部事実」のコードブロック 3 (画像入力)。`M=GLM-5.3-Flash-EXL3` で画像ありが exit 0、陰性対照の画像なしが「赤色」で exit 1 | 2026-10-04 |
| 再起動後の復帰条件 | `ssh -n spark-head 'docker inspect glm53-flash-tf --format "{{.HostConfig.RestartPolicy.Name}}"'` が `no` (worker も同名) | 2026-10-04 |
| 8888 が無認証のままか | `curl -s -o /dev/null -w "%{http_code}\n" http://spark-head.local:8888/v1/models` が 200 (対照に `/v1/nope` が 404) | 2026-10-04 |
