---
name: utility-spark-model-fetch
description: DGX Spark 2 台クラスタ (spark-head / spark-worker) に open-weight モデルの重みを配布する。head で HuggingFace から 1 回だけ落とし、RoCE 経由で worker へ rsync することで、素直にやると 11 時間かかる配布を 5.5 時間に縮める。「Spark に新しいモデルを入れたい」「モデルをダウンロードして worker にも配って」「open-weight を試したい」「HF から重みを取ってきて」「両ノードに重みを置いて」などで必ず起動する。Spark と HuggingFace の両方が話に出たら、明示的に「配布して」と言われていなくてもこのスキルを参照する。モデルの起動・切り替え・ベンチマークは対象外。
argument-hint: <HF のモデル ID> [revision]
allowed-tools: Bash, AskUserQuestion
---

# Spark クラスタへのモデル配布

`spark-head` で HuggingFace から 1 回ダウンロードし、`spark-worker` へ `rsync` で複製する。

## なぜこの手順なのか

レシピ同梱の `prepare-dspark-model-cache.sh` は head での取得後、**worker でも HuggingFace から再ダウンロード**する。自宅の WiFi は 2.4 GHz で実効 8 MB/s しか出ないため、167 GB のモデルだと 2 回で 11 時間かかる。head で 1 回だけ落として RoCE (285〜605 MB/s) で複製すれば、2 回目の 5.5 時間が 5〜8 分になる。

| 工程 | 実測速度 | 167 GB の場合 |
| --- | --- | --- |
| HuggingFace からのダウンロード | 8.0〜8.7 MB/s | 約 5.5 時間 |
| head から worker への rsync | 285〜605 MB/s | 5〜8 分 |
| vLLM の起動 | — | 150〜390 秒 |

## 前提

環境の詳細は `~/.claude/rules/infra/dgx-spark.md` を読む。要点は次のとおり。

- head から worker へは `.env.dspark` の `WORKER_HOST` (RoCE 側アドレス) で ssh する。**LAN 側 (WiFi) は使わない**
- HF キャッシュは両ノードの `~/.cache/huggingface/hub/`
- **sudo は使えない。** root 権限が要る操作は docker 経由で行う
- レシピは head の `~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark`

## 手順

### 1. 事前確認

```bash
ssh spark-head 'df -h ~ | tail -1'
curl -s "https://huggingface.co/api/models/<モデル ID>" | python3 -c "
import json,sys; d=json.load(sys.stdin)
print('gated:', d.get('gated'), '/ private:', d.get('private'))"
```

`gated` が `False` 以外なら HF でライセンス同意が要る。head の `~/.cache/huggingface/token` が使われる。

**稼働中の vLLM は止めなくてよい。** ダウンロードはディスクと帯域しか使わない。止めるのは起動を切り替えるときだけ。

### 2. head でのみダウンロードする

`prepare-dspark-model-cache.sh` を使う場合は `.env.dspark` に `DSPARK_WORKER_HF_NFS=1` を設定する。ただし**これを設定しても worker 再帰に入ることがある**ので、開始後に確認する。

```bash
ssh spark-head 'ps -eo pid,etime,cmd | grep "[p]repare-dspark-model-cache"'
```

`ssh <WORKER_HOST> ... PREPARE_WORKER=0` という行が出たら worker が再ダウンロードを始めている。その ssh プロセスを `kill` し、worker 側のダウンロードコンテナも `docker stop` する。

`HF_DOWNLOAD_WORKERS` の既定は 1。8 に上げても速度は変わらない (律速はリンク側)。上げること自体に害はない。

**進捗の見方**: `du -sb` の差分を時間で割る。ログの `Fetching N files` は `\r` で上書きされるため `tr "\r" "\n"` を通す。

### 3. 所有権を直す (これを飛ばすと rsync が黙って失敗する)

ダウンロードはコンテナ内 (root) で走るため、成果物が root 所有になる。この状態で rsync すると**受信側が全ブロブで `Permission denied` を返すのに、送信側の進捗表示は 600 MB/s で流れて成功に見える**。1 バイトも書けていないので必ず先に直す。

```bash
D=models--<org>--<name>          # 例: models--deepseek-ai--DeepSeek-V4-Flash-0731
IMG=ghcr.io/anemll/dspark-vllm-gx10:0.1.1   # .env.dspark の DSPARK_VLLM_IMAGE
docker run --rm -v "$HOME/.cache/huggingface:/c" --entrypoint chown "$IMG" -R 1000:1000 "/c/hub/$D"
```

**両ノードで実行する。** 確認は `ls -ld ~/.cache/huggingface/hub/$D` で所有者が `skanehira` になること。

### 4. worker へ rsync する

```bash
W=$(grep -E "^WORKER_HOST=" ~/dspark-*/.env.dspark | cut -d= -f2 | tr -d '"')
SRC=~/.cache/huggingface/hub/$D
rsync -a --delete --info=progress2 --no-inc-recursive "$SRC" "$W:.cache/huggingface/hub/"
```

- 転送先は `"$W:.cache/..."` と書く。`~` を含めると展開されずリテラルのディレクトリができることがある
- `--delete` で中断分の残骸を掃除できる
- 長時間かかるので `nohup ... &` でログに落とす

### 5. 検証する

サイズ一致では不十分。`scripts/verify_shards.py` を両ノードで実行して突き合わせる。

```bash
scp scripts/verify_shards.py spark-head:/tmp/vs.py
ssh spark-head 'python3 /tmp/vs.py '"$D"'; ssh '"$W"' "python3 /tmp/vs.py '"$D"'"'
```

必要シャード数・揃い数・重み合計 GB・ファイル数が両ノードで一致すること。欠落があれば exit 1 を返す。

### 6. 残骸を消す

検証が通ってから、中断した回の `.incomplete` を消す。

```bash
find ~/.cache/huggingface/hub/$D -name "*.incomplete" -delete -print
```

削除後にもう一度検証を通す。

## 落とし穴

**監視コマンドの自己マッチ。** `pgrep -f prepare-dspark` は監視コマンド自身の文字列にマッチするため、完了を永久に検知しない。同じ理由で `pkill -f` は自分の ssh セッションを殺す。**PID を直接見る** (`while kill -0 $PID; do sleep 60; done`) こと。

**進捗表示を成功と勘違いしない。** rsync の `--info=progress2` は送信側の集計なので、受信側が全部失敗していても数字は伸びる。終了後に `grep -ci denied` でログを確認する。

**HF キャッシュは symlink 構造。** `snapshots/<rev>/<file>` が `blobs/<hash>` を指す。`du -sh` は実体を二重に数えないが、`du -shL` は辿る。検証は必ず `realpath` で実体を見る。

## 完了後

配布しただけでは使えない。起動と設定の切り替えは別作業で、`~/.claude/rules/infra/dgx-spark.md` の「起動と停止」「Mac から使う」に従う。レシピが対象モデルに対応していない場合は、対応していた頃のコミットで `git worktree` を作る手もある。
