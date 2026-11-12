---
# 常駐読み込みさせないためのマーカー (このパスにマッチするファイルは存在しない)。
# 本ファイルは必要になったときに Read で参照する。
paths:
  - "__read-on-demand-only__"
---

# DGX Spark 2 台構成 (自宅のローカル LLM クラスタ)

- 種別: 環境リファレンス (共通)
- 対象読者: 別セッション・別マシンで作業するエージェント (Claude Code / Codex / OpenCode)
- 最終確認: 2026-10-30 (系統ファイルの一覧と、比較表の 1017 系の値)。2026-10-12 (sparkDash に関わる記述)。2026-10-09 (比較表の GLM 系の値)。2026-10-04 (監査で指摘を受けた各節)。2026-10-03 (OpenCode V2 2.0.22 の挙動)。`opencode.json` の書式の記述は dotfiles の commit `9d3d262f` (2026-10-16) の V2 書式に合わせてあり、この書式での OpenCode の挙動は実測していない
- 系統ごとの記述の確認日は各系統ファイルの冒頭にある。値ごとの確認日は表のセルか本文と「依拠する外部事実」にある。OpenCode を通した疎通・速度の値のうち 2026-10-03 より前の日付のものは opencode 1.18.18 (V1) で取ったもので、V2 では測り直していない

自宅に NVIDIA DGX Spark (GB10) が 2 台あり、TP=2 (tensor parallel、2 台に重みを分割する並列方式) でローカル LLM を常時サービングしている。推論エンジンは GLM 系と 1017 系が TensorFold、他の 3 系統は vLLM である。Mac の OpenCode (素の `opencode`) からバックエンドとして使える。

レシピは 5 系統ある。ポート 8888 と GPU を共有するので、同時には 1 つしか配信できない。どれを配信しているかは本書に書かない (切り替えが頻繁なので、書いた時点で古くなる)。

| 系統 | ファイル | head のディレクトリ | コンテナ名 | 配信名 (`/v1/models` の `id`) |
| --- | --- | --- | --- | --- |
| DeepSeek 系 (Vision-Exp 版 / 0731 版) | `dgx-spark/deepseek.md` | `~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark` (0731 版は `~/dspark-0731`) | `deepseek-v4-flash-vllm-dspark-1` | `deepseek-v4-flash-vision-exp` / `deepseek-v4-flash-0731` |
| Qwen 系 (Qwen3.8-Flash-Next) | `dgx-spark/qwen.md` | `~/Qwen3.8-Flash-Next-Dual-DGX-Sparks` | `vllm-fn` (両ノード同名) | `qwen3.8-flash-next` |
| V4.1 EXL3 系 (DeepSeek-V4.1-Flash EXL3 2.9bpw) | `dgx-spark/v41-exl3.md` | `~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks` | `dsv41-exl3-head` / `dsv41-exl3-worker` | `DeepSeek-v4.1-Flash-EXL3` |
| GLM 系 (GLM-5.3-Flash EXL3 4bpw、TensorFold) | `dgx-spark/glm.md` | `~/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold` | `glm53-flash-tf` (両ノード同名) | `GLM-5.3-Flash-EXL3` |
| 1017 系 (DeepSeek-V4.1-Flash-1017 EXL3 2.9bpw、TensorFold の Zig エンジン) | `dgx-spark/1017.md` | `~/DeepSeek-v4.1-Flash-1017-2x-DGX-Sparks` | `dsv41-1017-exl3-tf` (両ノード同名) | `DeepSeek-V4.1-Flash-1017` |

ファイルのパスは `agents/rules/infra/` からの相対である。作業では、このファイルと配信中の系統のファイルの 2 本を読む。配信中の系統は `ssh -n spark-head 'docker ps --format "{{.Names}}" | grep -E "vllm|dsv41|glm53"'` が返すコンテナ名を上の表と照らして決める。`--filter name=vllm` だけでは `dsv41-exl3-head`・`glm53-flash-tf`・`dsv41-1017-exl3-tf` を拾わない。`dsv41` は V4.1 EXL3 系と 1017 系の両方に当たるので、名前の残りで見分ける。DeepSeek 系の Vision-Exp 版と 0731 版はコンテナ名が同じなので `/v1/models` の配信名で見分ける。GLM 系の通常版と Ablit は配信名も同じである (見分け方は `dgx-spark/glm.md`「通常版と Ablit の切り替え」)。

dotfiles リポジトリの所在は `~/dev/github.com/skanehira/dotfiles` で、本書のリポジトリ相対のパスはここを基点とする。本書の表で「—」は該当なしを意味する。

## 用語・成果物一覧

系統をまたぐ用語だけを置く。1 系統だけの用語は各系統ファイルの「用語」にある。「定義箇所」は本書の節名か、実機・dotfiles 上のファイルパスである。

| 名前 | 意味 | 定義箇所 | 生成者 | 消費者 |
| --- | --- | --- | --- | --- |
| 系統 | レシピの系統。同時には配信できない | 冒頭の表 | — | 人 |
| head / worker | TP=2 の rank 0 / rank 1。head だけが HTTP API を持つ | 「ネットワーク」 | 人 (初期構築) | 起動スクリプト |
| レシピ | 上流が配布する compose / シェルスクリプト一式 | 冒頭の表 | 上流 (`git clone`) | 人 |
| 上流 | レシピの配布元。GitHub の `MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark` (DeepSeek 系)、`MiaAI-Lab/Qwen3.8-Flash-Next-Dual-DGX-Sparks` (Qwen 系)、`MiaAI-Lab/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks` (V4.1 EXL3 系)、`MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold` (GLM 系)、`MiaAI-Lab/DeepSeek-v4.1-Flash-1017-2x-DGX-Sparks` (1017 系) | — | — | — |
| RoCE | RDMA over Converged Ethernet。QSFP ポート上でノード間の NCCL 通信を運ぶ | 「ネットワーク」 | NetworkManager の接続 `roce` / `roce2` | vLLM / TensorFold |
| NCCL | NVIDIA Collective Communications Library。TP=2 のランク間通信 | 本表 | — | vLLM |
| DSpark | チェックポイント内蔵の投機デコード (別のドラフタを持たない)。DeepSeek 系・V4.1 EXL3 系・1017 系が使う | 各系統ファイル「構成」。vLLM の 2 系統 (DeepSeek 系・V4.1 EXL3 系) では vLLM の CLI フラグ `--speculative-config` で渡る | 各レシピ | vLLM / TensorFold |
| MTP | 1 ステップで出す draft トークン数。キー名は DeepSeek 系 `MTP_NUM_TOKENS` / Qwen 系 `MTP_NUM_SPECULATIVE_TOKENS` / V4.1 EXL3 系 `DSPARK_TOKENS` | 各系統ファイル「構成」 | 人 | vLLM |
| `nvfp4_ds_mla` / `fp8_ds_mla` | MLA の KV キャッシュを 4bit / 8bit で持つ形式。前者は DeepSeek 系、後者は V4.1 EXL3 系 | vLLM の `--kv-cache-dtype` | compose / vLLM | vLLM |
| EXL3 | ExLlamaV3 の量子化形式。テンソルごとにビット数が違うので平均が 2.9 bpw のような端数になる。vLLM 本家は非対応 (V4.1 EXL3 レシピが後付け)、GLM・1017 レシピは TensorFold の対応を使う | 各系統ファイル「構成」 | 上流 | vLLM / TensorFold |
| TensorFold | GLM 系と 1017 系の推論エンジン (GitHub の `ashhart/TensorFold`)。GLM 版は v0.6.0 の Python エンジン、1017 版は BertholomusAI の fork の Zig エンジン `tensorfold-native` で、パッチは各系統ファイル。どちらも OpenAI 互換 API と `/v1/messages` を持ち、`vllm:` のメトリクスを持たない | `dgx-spark/glm.md` / `dgx-spark/1017.md` | 上流 | 両レシピの `start.sh` |
| Engram | DeepSeek-V4.1 の n-gram 埋め込み表。量子化せず、元チェックポイントの shard 47/48 からファイルで読む。V4.1 EXL3 系と 1017 系で sha256 が違い、使い回せない | `dgx-spark/v41-exl3.md` / `dgx-spark/1017.md` | 上流 | vLLM / TensorFold |
| memguard | V4.1 EXL3 と 1017 のレシピが別々に持つ `scripts/memguard.sh`。配信中に `MemAvailable` が閾値を下回ったノードのコンテナを kill する。V4.1 EXL3 版は無効、1017 版は既定で有効 | 「既知の制約」11 | `start.sh` | — |
| `start.sh` / `stop.sh` | Qwen・V4.1 EXL3・GLM・1017 の 4 レシピが同名で別々に持つ起動・停止スクリプト。DeepSeek 系は別名 | 「系統の切り替え」 | 上流 | 人 |
| `.env` | Qwen レシピと V4.1 EXL3 レシピが別々に持つ設定。DeepSeek 系の `.env.dspark` とは別物 | 各系統ファイル「構成」 | 人 | 各レシピ |
| `prepare.sh` | GLM と 1017 のレシピが別々に持つ準備スクリプト (`scripts/prepare.sh`)。取得と worker への配布を行い、`start.sh` が必要と判定すると自動で流す (`PREPARE=0` で飛ばす) | 各系統ファイル「起動と判定」 | 上流 | `start.sh` |
| `scripts/local.sh` | GLM と 1017 のレシピが別々に持つ手元設定。`.gitignore` に無く未追跡として出る | 各系統ファイル「構成」 | 人 (`scripts/local.sh.example` から) | `scripts/config.sh` |
| TTFT | time to first token。ほぼ prefill の所要時間 | 本表 | `bench.py` | 「実測値」 |
| 受理率 | 投機デコードの draft のうち採用された割合。decode 速度をほぼ決める | 「遅いと感じたときに疑う順序」 | `/metrics` か `/health` | 「実測値」 |
| L1 / L3 | 計測の層。L1 = サーバ直叩き / L3 = OpenCode 経由 (opencode 1.18.18) | 「実測値」 | `bench.py` / `snap.py` | 「実測値」 |
| `~/spark-bench` | 計測ハーネス。`bench.py` (L1)・`snap.py` (L3)・`results/`。`pc_probe.py` は役割を記録していない。再作成手段が無い | head の `~/spark-bench/` | 人 | 人 / エージェント |
| `/tmp/spark.key` | `bench.py` 専用の Bearer トークンの作業ファイル (head のみ、再起動で消える) | 「API キーの流れ」 | 人 | `bench.py` |
| `nv-gpu-clock-limit.service` / `nv-cpu-clock-limit.service` | 両ノードに手で置いた systemd unit。GPU を 2,200 MHz にロックする / X925 の `scaling_max_freq` を下げる。dotfiles に控えが無い | 「既知の制約」4・5 | 人 | systemd |
| `utility-spark-model-fetch` | 重みを head で 1 回落として worker へ rsync するスキル。`scripts/verify_shards.py` を同梱する | `agents/skills/utility-spark-model-fetch/SKILL.md` | dotfiles | エージェント |
| sparkDash | 監視・SSH 操作・Wake-on-LAN・電源断・設定変更を持つ Web UI (v2.32.0)。認証なしで全インターフェースで待ち受ける。イメージ `sparkdash-sparkdash:latest`、上書き `docker-compose.override.yml`、worker の表示名の手書き値 `workerLabel` (空に保つ) を伴う | 「動いているもの」 | 上流、イメージは人 (Mac でビルド) | 人 |
| `opencode` | OpenCode V2 (2.0.22)。素の `opencode` で本クラスタに繋がり、常駐サービス (`opencode serve --service`) を起動して接続する | `nix/pkgs/opencode.nix` | dotfiles | 人 |
| `opencode.json` | OpenCode の設定 (V2 書式)。接続先・モデルの宣言・`reasoningEffort` と `limit`・provider の利用方針。キーは持たない | `agents/bindings/opencode/opencode.json` | dotfiles | `opencode` |
| `spark-served.ts` | 配信中のモデルだけを有効にして既定に据える OpenCode のプラグイン | `agents/bindings/opencode/plugins/spark-served.ts` | dotfiles | `opencode` 本体 (`~/.config/opencode/plugins/` 直下の `*.ts` を自動で読む。`opencode.json` への登録は要らない) |
| `cli.json` | OpenCode の TUI 設定 (keybinds / theme) | `agents/bindings/opencode/cli.json` | dotfiles | `opencode` |
| `reasoningEffort` | OpenCode が `/v1/chat/completions` の `reasoning_effort` として送る値。モデルごとに静的 | 「系統の切り替え」の effort の表 | dotfiles | `opencode` |
| `ccds` | Claude Code を DeepSeek 本家 API へ向けて起動する zsh 関数。`agents/bindings/claude/settings.deepseek.json` (接続先・モデル名 5 キー・`CLAUDE_CODE_EFFORT_LEVEL` = `max`・`fallbackModel`) を `--settings` で渡す (詳細は dotfiles の `CLAUDE.md`) | `zsh/functions/claude-deepseek.zsh` | dotfiles | 人 |
| `drs` / `hms` | Nix 設定を適用する zsh alias (Mac / Linux) | `nix/modules/home/zsh.nix` | dotfiles | 人 |

## ハードウェアと OS

2 台とも同一構成である。

| 項目 | 値 |
| --- | --- |
| GPU | NVIDIA GB10 (CPU と共有する統合メモリ 128 GB。カタログ値で、`/proc/meminfo` は 121.7 GiB) |
| CPU | 20 コアの big.LITTLE。性能コア Cortex-X925 ×10 (cpu5-9・cpu15-19、`cpuinfo_max_freq` 3,900 MHz)、効率コア Cortex-A725 ×10 (cpu0-4・cpu10-14、2,808 MHz)。cpufreq は 1 コア 1 policy、driver は `cppc_cpufreq`、governor は全コア `performance`。X925 の `scaling_max_freq` は 2,808 MHz に下げてあるが、ハードウェアの上限は変わっていない (→「既知の制約」5)。2026-09-10 に両ノードで実測 |
| OS | Ubuntu 24.04.4 LTS / aarch64 |
| カーネル | `6.17.0-1032-nvidia` |
| ドライバ | `580.173.02` |
| ディスク | 3.7 TiB。head は使用 2.1 TiB / 空き 1.5 TiB、worker は使用 1.8 TiB / 空き 1.7 TiB (`df -h /`、2026-10-22)。差の一部は 1017 系の本体 197 GiB を head だけが持つことによる。残りの内訳は確かめていない |

## 接続する

自宅 LAN では `ssh spark-head` / `ssh spark-worker` が使える。`~/.ssh/config` は dotfiles 管理外の実ファイルなので、別マシンでは次を自分で書く。鍵 `~/.ssh/spark-head` / `~/.ssh/spark-worker` は既存機からコピーするか、新規生成して `ssh-copy-id` で登録する。

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

`Host spark-head` は `Hostname spark-head.local` に解決されるので、`ssh skanehira@spark-head` と書いても LAN の mDNS 名に化ける。出先で Tailscale の MagicDNS 名を使うときは `spark-head-ts` を経由する。HTTP (`http://spark-head:8888`) は ssh_config を通らないので影響を受けない。

新しいマシンでは `known_hosts` の登録が要る。ホスト鍵の受理には TTY での対話が要り、エージェントの非対話のシェル実行からは `Host key verification failed` で落ちる。ユーザーに次を依頼する (`known_hosts` はエージェントが書き換えない)。

```bash
ssh-keyscan spark-head.local spark-worker.local spark-head >> ~/.ssh/known_hosts
```

### 出先 (Tailscale) からのコマンドの読み替え

本書のコマンドは自宅 LAN 前提である。tailnet には head しか居ないので、worker には head 経由でしか届かない。出先では次の 2 つを読み替える。

| LAN での書き方 | 出先での書き方 |
| --- | --- |
| `ssh spark-head` | `ssh spark-head-ts` |
| `http://spark-head.local:8888` | `http://spark-head:8888` |

読み替えるのは `ssh` と手打ちの `curl` だけである。OpenCode は自宅でも出先でも Tailscale 側に繋ぐので読み替えは要らないが、自宅でも Tailscale へのサインインが要る。

`ssh spark-head-ts` を使う前に `~/.ssh/config` に 3 ブロック目があるかを確かめる。この Mac には 1・2 ブロック目しか無く、`ssh -G spark-head-ts` が `hostname spark-head-ts` を返す (2026-09-09)。無ければ上の雛形の 3 ブロック目を追記する。

### worker に入る

`known_hosts` に `spark-worker.local` の鍵があれば Mac から直接入れる。無いマシンでは head の中から入る (head の `known_hosts` には RoCE 側アドレスの鍵がある)。worker のアドレスは DeepSeek 系レシピの設定ファイル `.env.dspark` の `WORKER_HOST` から引く (どの系統を配信中でも使える)。

```bash
ssh -n spark-head 'W=$(grep -E "^WORKER_HOST=" ~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark/.env.dspark | cut -d= -f2); ssh -n -o BatchMode=yes "$W" "<worker で実行するコマンド>"'
```

外側がシングルクォートなので `$W` は head 側で展開される。`WORKER_HOST` の値はクォートされていないので `cut -d= -f2` で足りる。

入れ子の `ssh` には `-n` を付ける。付けずに外側をヒアドキュメントや `bash -s` で流し込むと、内側の ssh が残りのスクリプトを標準入力ごと飲み込み、以降のコマンドが実行されないまま正常終了する (出力が途中で切れていたらこれを疑う)。

### 長い処理を ssh から切り離す

数分を超える処理 (起動・ダウンロード・イメージの転送) をエージェントのシェル実行から流すときは、head 上で切り離し、終わりの印をログに書かせて待つ。1 回のコマンド実行には時間上限があり (Claude Code の Bash ツールは 600 秒)、ssh ごと切れると処理も止まりうる。Mac からの ssh 1 本で長い前景処理を流すと、出力が無い間に Mac 側の ssh がタイムアウトする (2026-10-04 に GLM のイメージ転送で実測。head 上の処理は続いていた)。

実行するコマンドは head 上の `~/<名前>.sh` に保存する。変数を使う処理は引用済みの heredoc (`cat > ~/<名前>.sh <<'SCRIPT'` … `SCRIPT`) で保存し、先頭に `set -euo pipefail` を書く。`<名前>` は処理ごとに分け、同じ名前の処理を同時に走らせない。

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

- `bash -lc`: ログインシェルを通す。`hf` は `~/.local/bin` にあり、非ログインシェルの PATH に無い
- 起動の ssh が戻らないことがある (2026-10-04 に GLM の `start.sh` で 7 分戻らなかった)。起動の ssh もバックグラウンドで打ち、待ちは別の ssh で行う
- 終わりの印は終了コードを保存してから書く。起動前にログを空にするので、前回の `EXIT=0` を拾わない。印が出ない場合は完了扱いにせず、プロセス状態を確かめる
- 終わりの印で待つので `pgrep -f` の自己マッチが起きない。`pgrep -f <パターン>` は待ちの ssh 自身にも一致するので、`^…$` で固定しないと永久に成立する (固定した例は `dgx-spark/v41-exl3.md`「起動と判定」)
- メモリの上限は掛からない。配信中のノードでは「既知の制約」11 の手段を使い、使えなければ停止後に流す
- 2026-10-06 に GLM 系の Ablit 導入で 4 回使い (時刻指定の取得 5 時間 45 分、worker への rsync、イメージの転送、`start.sh`)、4 回とも `EXIT=0` で終わった。時刻を指定して始めるときは、スクリプトの先頭で `sleep $(( $(TZ=Asia/Tokyo date -d '<日時>' +%s) - $(date +%s) ))` を挟む

### ネットワーク

| 用途 | netdev 名 | RDMA デバイス名 | 割り当て | MTU (バイト) |
| --- | --- | --- | --- | --- |
| LAN (WiFi) | `wlP9s9` | — | 両ノード。mDNS 名 `spark-head.local` / `spark-worker.local` | 1500 |
| RoCE 1 本目 | `enp1s0f1np1` | `rocep1s0f1` | 専用の /24。head が `.1`、worker が `.2` | 9000 |
| RoCE 2 本目 | `enP2p1s0f1np1` | `roceP2p1s0f1` | 別の /24。head が `.1`、worker が `.2` | 9000 |
| Tailscale | `tailscale0` | — | head のみ。MagicDNS 名 `spark-head` | 1280 |

具体的な IP アドレスは本書に書かない。このリポジトリは公開されており、アドレスを認証の無いサービス (sparkDash) の説明と並べる利点が無いためである。必要になったら「依拠する外部事実」の引き方で調べる。日常の操作は名前と `.env.dspark` の `WORKER_HOST` で足りる。

RoCE が 2 本あるのは GB10 の仕様で、QSFP ポートが 2 つの仮想 NIC (各 PCIe Gen5 x4) として見える。2 本は別サブネットに置き、MTU 9000 にする。片方に IP が無い、または同一サブネットに置くと vLLM が `no usable RoCEv2 GID` で起動に失敗する。IP と MTU は NetworkManager の接続 `roce` / `roce2` (autoconnect 有効) で永続化してあり、再起動後も残る。使い方はレシピで違う (DeepSeek 系は `.env.dspark` の `NCCL_IB_HCA` に `rocep1s0f1,roceP2p1s0f1` と両方を並べ、Qwen 系は `.env` の `IB_HCA` に 1 本だけ書く。GLM 系は `dgx-spark/glm.md`「RoCE は 2 本とも使う」)。

LAN は 2.4 GHz の WiFi (両ノードとも freq 2437) で、リンク速度は 230〜290 Mbit/s と出る (`iw dev wlP9s9 link`、2026-09-15)。それでも HuggingFace からのダウンロードは合計で約 8 MB/s しか出ず (156〜158 GiB のモデルに約 5.5 時間)、2 本を同時に流すと分け合う。律速が WiFi か自宅の回線かは切り分けていない。ノード間のコピーは RoCE を使えば 260〜605 MB/s 出る。

## 動いているもの

| サービス | 自宅 LAN | 出先 (Tailscale) | 認証 |
| --- | --- | --- | --- |
| 推論サーバ (5 系統のどれでも) | `http://spark-head.local:8888` | `http://spark-head:8888` | なし |
| sparkDash | `http://spark-head.local:5555` | `http://spark-head:5555` | なし (画面に Open access の警告が出る) |

ポート 8888 はどの系統でも無認証である。したがって 8888 を信頼できないネットワークへ出さない。sparkDash のポート 5555 と同じ扱いにする。系統ごとの無認証の理由と、Responses API・Anthropic Messages API の可否は次のとおり。

| 系統 | 無認証の理由 (確認日) | `/v1/responses` | `/v1/messages` |
| --- | --- | --- | --- |
| DeepSeek 系 | `.env.dspark` の `VLLM_API_KEY` を空にしてある (compose がこの値をコンテナに渡す) (2026-09-06) | 素で通る (2026-09-23) | 通る (2026-09-23) |
| Qwen 系 | レシピが vLLM に `--api-key` を渡さない。ヘッダ無しでも出まかせの Bearer でも `/v1/models` が 200、存在しないパスは 404 (2026-09-06) | 未試行 | 通る (2026-09-06) |
| V4.1 EXL3 系 | `.env` の `VLLM_API_KEY` がコメントアウトのまま。起動ログの `auth` 行が `none (VLLM_API_KEY empty)` (2026-09-15) | サーバ側にパッチが要る (→ `dgx-spark/v41-exl3.md`「既知の制約 (V4.1 EXL3 系)」) | 通る (2026-09-15) |
| GLM 系 | TensorFold に API キーの設定項目が無い。ヘッダ無しの `/v1/models` が 200 (2026-10-04) | 素で通る (2026-10-02) | レシピ v1.9 から通る (→ `dgx-spark/glm.md`「使える API」) |
| 1017 系 | レシピの `API_KEY` が既定の `0` のまま。`start.sh` の完了表示が `open: no key` (2026-10-22) | 素で通る (2026-10-22) | 通る (2026-10-30) |

`/health` は手動の到達判定とレシピの起動・停止が、`/v1/models` は `spark-served.ts` (起動時と 30 秒ごと) が、`/metrics` は sparkDash と `~/spark-bench/snap.py` が使う。OpenCode が生成に使う経路は `/v1/chat/completions` である。

sparkDash は head の `~/sparkDash` に clone した GitHub の `MiaAI-Lab/sparkDash` で、タグ `v2.32.0` に detached で固定してある。同梱の `docker-compose.yml` は編集せず、上書きは未追跡の `docker-compose.override.yml` に置く (タグの切り替えとの衝突を避けるため)。反映は `~/sparkDash` で `docker compose up -d --no-build`、停止は `docker compose down` である。

v2 は既定で `127.0.0.1` にしか bind しないので、override に `BIND_HOST=0.0.0.0` を書いてある。トークン (`SPARKDASH_TOKEN`) で認証を掛けられるが、付けないと決めた (2026-10-12)。そのため自宅 LAN と tailnet の全端末から、設定変更・SSH 操作・Wake-on-LAN・電源断ができる。ポート 5555 を信頼できないネットワークへ出さない。状態は `curl -s http://spark-head:5555/api/health` の `authMode` で見る (現状は `open-remote`、トークンを付けると `bearer`)。

override はポーリング間隔を GPU と CPU が 5 秒、ネットワークと帯域が 15 秒、ストレージと liveness が 30 秒に固定し、既定 (2 秒前後) より worker への SSH ログインと `nvidia-smi` の起動を減らしている (既定間隔での実測値は head の override のコメント)。GPU と CPU が 5 秒なのは、Fleet energy が 2 秒ごとに集計し、読みが 10 秒以内のノードだけを数えるためである (`server/energy/FleetEnergyRuntime.js` の `MAX_POWER_TELEMETRY_AGE_MS`)。2026-10-12 に `curl -s http://spark-head:5555/api/fleet-energy` の `coverage24hMs` の増分で測ると、両ノードがそろって集計された時間は 15 秒間隔で 28 秒中 10.0 秒 (約 36%)、5 秒間隔で 62 秒中 62.0 秒だった。worker の負荷は上がらなかった (15 秒間隔で loadavg 0.11・5 分間の PAM セッション開始 2 回、5 秒間隔で 0.05・1 回)。v2 は SSH の接続を 60 秒保持して使い回す (`SSH_CONTROL_PERSIST_SECONDS`)。

### sparkDash を更新する

head ではビルドしない。head のホストには node と npm が無く、`docker compose up --build` は dockerd の中で `npm ci` とフロントエンドのビルドを上限無しに走らせる。配信中の head は空きが 7 GiB 前後しかなく、尽きるとノードごと固まるおそれがある (→「既知の制約」11)。そこで Mac (arm64) でビルドして `docker load` する。上流の GHCR (`ghcr.io/miaai-lab/sparkdash`) の workflow は v2.32.0 より後に入ったので v2.32.0 のイメージは無い (2026-10-12 に `docker manifest inspect` が `denied`)。次の更新では先に `docker manifest inspect ghcr.io/miaai-lab/sparkdash:<タグ>` を打つ。解決すればビルドは要らないが、版合わせは要る。

版合わせ: head の checkout とイメージのビルド元は同じコミットに揃える。compose は `./server`・`./src/shared`・`showcasePrompts.ts` を bind mount し、イメージの `node_modules` で `node --watch server/index.js` を走らせるので、ずれるとサーバのコードと依存の版が食い違う。

配信中の `docker load` は「既知の制約」11 の例外とする。イメージは 279 MB で、同制約が想定する 20 GB 級より 2 桁小さい。2026-10-12 に GLM 配信中に読み込み、head の `MemAvailable` は 6.85 GiB から 6.76 GiB に動いただけだった。

```bash
# 1. head で戻す材料を取る。config/ には root 所有の鍵 .secrets-key が入るので、コンテナ経由で固めて 600 にする
ssh -n spark-head 'docker tag sparkdash-sparkdash:latest sparkdash-sparkdash:<旧版>'
ssh -n spark-head 'mkdir -p ~/sparkDash-backup-<旧版> && chmod 700 ~/sparkDash-backup-<旧版> && docker exec sparkDash tar czf - -C /app config > ~/sparkDash-backup-<旧版>/config.tgz && chmod 600 ~/sparkDash-backup-<旧版>/config.tgz && cp ~/sparkDash/docker-compose.override.yml ~/sparkDash-backup-<旧版>/'
ssh -n spark-head 'git -C ~/sparkDash fetch -q --tags && git -C ~/sparkDash rev-parse "<タグ>^{commit}"'

# 2. Mac でビルドして head へ読み込む。<作業ディレクトリ> は一時領域に取る
git clone -q --branch <タグ> --depth 1 https://github.com/MiaAI-Lab/sparkDash.git <作業ディレクトリ>
git -C <作業ディレクトリ> rev-parse HEAD   # 1 の最後の行と一致すること
docker build --platform linux/arm64 -t sparkdash-sparkdash:<タグ> <作業ディレクトリ>
docker save sparkdash-sparkdash:<タグ> | ssh spark-head 'docker load'

# 3. head を切り替える
ssh -n spark-head 'cd ~/sparkDash && git checkout -q --detach <タグ> && mkdir -p dist && docker tag sparkdash-sparkdash:<タグ> sparkdash-sparkdash:latest'
ssh -n spark-head 'cd ~/sparkDash && docker compose config | grep BIND_HOST'   # 0.0.0.0 であること (override が効いていないと 127.0.0.1)
ssh -n spark-head 'cd ~/sparkDash && docker compose up -d --no-build'
```

- `--no-build`: compose の `build:` が head でビルドを始めないようにする
- `mkdir -p dist`: compose はホストの `./dist` を bind mount し、無いと docker が root 所有の空ディレクトリを作る。サーバはイメージ内の `dist-baked` を使うが、所有者を揃えておく
- 完了判定: `/api/health` が `"authMode":"open-remote"` を返し、`docker logs sparkDash` に `bind=0.0.0.0 auth=open-remote` と worker の `reachable again` が出る (起動直後の `unreachable (no liveness)` は数秒で戻る)。`curl -s http://spark-head:5555/api/sparks/spark-head/metrics` の `metrics.llm` に配信中のモデルが出る。`authMode` が `required-missing` で起動を拒んだら上流がトークン無しの既定を変えているので (v2.32.0 の既定は `SPARKDASH_ALLOW_OPEN_REMOTE=1`。上流の `docs/REMOTE-ACCESS.md` は拒む前提で README とずれている)、override に `SPARKDASH_ALLOW_OPEN_REMOTE=1` を足す
- 戻すとき: 次を head で打つ。`config/` は root 所有なので、手元の旧版のイメージで展開する (別のイメージを指定すると配信中に `docker pull` が走る)。新しい版が足した状態ファイル (`gpu-history.json` など) は残るが旧版は読まない。v2 は起動時に `sparks.json` を正規化して書き戻すので、`config/` を戻さずに旧版を起動しない

  ```bash
  cd ~/sparkDash && docker compose down && git checkout -q --detach <旧コミット>
  docker run --rm -v ~/sparkDash/config:/c -v ~/sparkDash-backup-<旧版>:/b --entrypoint sh sparkdash-sparkdash:<旧版> -c 'tar xzf /b/config.tgz -C /c --strip-components=1'
  docker tag sparkdash-sparkdash:<旧版> sparkdash-sparkdash:latest
  cp ~/sparkDash-backup-<旧版>/docker-compose.override.yml ~/sparkDash/
  docker compose up -d --no-build
  ```

2026-10-12 に 1.8.6 (`cc44d35`) から v2.32.0 (`230cdde`) へ上げた。1.8.6 へ戻す材料は「残骸の片付け」の表にある。

### API キーの流れ

現在は OpenCode もプラグインも API キーを使わず、`/v1/models` の照会にも Authorization ヘッダを付けない。無認証のいま 1Password が要るのは `ccds` だけである。Spark のキーの正本は `op://Personal/DGX Spark vLLM API Key/credential` である。

認証ありに戻すときは、サーバと OpenCode の両方を直す。サーバだけ直しても OpenCode は起動する。プラグインは 401 を「届かない」と同じに扱って直前の状態を保つので、常駐サービス起動時なら全モデルが選べるまま、稼働中なら直前の絞り込みのまま動き、最初の生成で失敗する (ソースから読んだ挙動で未実測)。クライアントだけ直しても無認証のサーバは Bearer を無視して 200 を返すので、両側を確かめる。

1. サーバ側。値は 1Password の正本から取り、人が書き込む。どのファイルも公開リポジトリの clone の中にあるが追跡外である

   | 系統 | 書く場所と反映 | 認証付きの起動 |
   | --- | --- | --- |
   | DeepSeek 系 | `.env.dspark` の `VLLM_API_KEY`。Vision-Exp 版 (`~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark`) と 0731 版 (`~/dspark-0731`) に 1 枚ずつあるので両方に入れ、停止 → 起動 | — |
   | Qwen 系 | `.env` の `EXTRA_VLLM_ARGS="--api-key <値>"` (→ `dgx-spark/qwen.md`「認証」) | 未検証 |
   | V4.1 EXL3 系 | `.env` の `VLLM_API_KEY` (コメントアウトされた行) に値を入れて停止 → 起動 | 未検証 |
   | GLM 系 | レシピに設定項目が無い。認証付きにする手段は確かめていない | — |
   | 1017 系 | `API_KEY=1 ./start.sh restart`。キーはレシピが `~/.local/state/dsv41-tensorfold/api-key` (mode 600) に生成し、コンテナに読み取り専用で渡す。1Password の値を使うなら先にこのファイルへ書く (既存のファイルは上書きしない実装) | 未検証 |

2. クライアント側。認証用の改修は未実装・未検証である
   - (a) `opencode.json` の `providers.spark.settings` にキーを足す。V2 書式でのキー名と、値を `{file:~/…}` / `{env:…}` で外部へ逃がす記法が解かれるかは確かめていない (記法は opencode 1.18.18 で使えた)
   - (b) `spark-served.ts` の `fetchServedModels` に `Authorization: Bearer <キー>` を付ける。付けないとプラグインは 401 を「届かない」と扱い、絞り込みが効かなくなる
   - 制約は 3 つある。プラグインは provider の設定を読めない (setup の時点で組み立てられていない)。公開リポジトリなのでソースに直書きできない。環境変数は常駐サービスに後から届かない ((a) の `{env:…}` にも掛かる)。候補は、リポジトリ外のキーファイルをプラグインと (a) の両方が読む形 (パス・書き出す人・権限は未設計) と、キーを export したシェルで `opencode service restart` する形 (環境を引き継ぐかは確かめていない) である
3. OpenCode の設定とプラグインは symlink なので live edit で反映する (常駐サービスが監視して読み直す。v2.0.22 のソースで確認、反映は未実測)。symlink が dotfiles に解決するかは `readlink -f` で見る
4. サーバ側が効いたことを確かめる。`curl -s -o /dev/null -w '%{http_code}\n' http://spark-head.local:8888/v1/models` が 401 を返すこと。200 のままならサーバ側が直っていない (「依拠する外部事実」の 200 判定の陽性対照でもある)
5. OpenCode が通ることを確かめる。`opencode models | rg '^spark/'` が配信名の 1 行だけを返し (Zen の `opencode/` の行も並ぶが判定には使わない。起動直後の打ち直しは「OpenCode」)、`opencode run "1+1 は?"` が答えを返すこと。プラグインが 401 を受けている間は、常駐サービスの起動時からなら全モデルが一覧に残る (ソースから読んだ挙動)

`bench.py` は無認証でもキー文字列を要求する。`--key-file` か環境変数 `SPARK_KEY` (head 上の `bench.py` が読む) のどちらも無いと起動時に exit し、渡した値はそのまま `Authorization: Bearer` に載る。いまは任意の文字列で足り、1Password は要らない。`/tmp` は再起動で消えるので、打つときに書き直す (2026-09-06 時点では存在しなかった)。

```bash
# 無認証のいま (中身は何でもよい)
echo dummy | ssh spark-head 'cat > /tmp/spark.key && chmod 600 /tmp/spark.key'
# 認証を戻した後
op read 'op://Personal/DGX Spark vLLM API Key/credential' | ssh spark-head 'cat > /tmp/spark.key && chmod 600 /tmp/spark.key'
```

### 重みの置き場所

DeepSeek 系・Qwen 系・GLM 系の重みは両ノードの `~/.cache/huggingface/hub/` にあり、worker はローカルコピーを持つ。V4.1 EXL3 系は HF キャッシュを使わず、レシピのディレクトリに実ファイルで置く (worker も実ファイル)。1017 系は本体を head の HF キャッシュにだけ置き、worker は NFS で読む (Engram と rank 1 の重みファイルは worker のディスクに持つ)。値は `du -sh` の実測である。

| チェックポイント | head | worker | 備考 |
| --- | --- | --- | --- |
| Vision-Exp | 158 GiB | 157 GiB | DeepSeek 系 (2026-09-06) |
| DeepSeek-V4-Flash-0731 | 156 GiB | 156 GiB | DeepSeek 系の 0731 版。revision は両ノード同一 (2026-09-23) |
| Qwen3.8-Flash-Next | 124 GiB | 124 GiB | Qwen 系 (2026-09-06) |
| DeepSeek-V4.1-Flash EXL3 | 197 GiB (EXL3) + 190 GiB (Engram) + 95 GiB (pack = Engram の rank 別の書き出し) | 同じ | V4.1 EXL3 系 (2026-09-15)。ほかにイメージの blob 9.1 GiB が残る (→ `dgx-spark/v41-exl3.md`) |
| GLM-5.3-Flash EXL3 (Ablit) | 164 GiB | 同じ | GLM 系 (2026-10-06)。`ABLIT=1` で配信するもの |
| GLM-5.3-Flash EXL3 (通常版) | 164 GiB + DFlash2 (別リポジトリのドラフタ) 2.2 GiB | 同じ | GLM 系 (2026-10-04)。ほかに v1.2 へ戻す用の TR3 164 GiB とイメージの blob 11 GiB がある (→ `dgx-spark/glm.md`) |
| DeepSeek-V4.1-Flash-1017 | 197 GiB (本体) + 190 GiB (Engram) + 100 GiB (rank 0 の重みファイルと kit) | 190 GiB (Engram) + 99 GiB (rank 1 の重みファイル) | 1017 系 (2026-10-22)。置き場所は `dgx-spark/1017.md` |

配信の候補は Vision-Exp、0731、Qwen3.8-Flash-Next、DeepSeek-V4.1-Flash EXL3、GLM-5.3-Flash EXL3、DeepSeek-V4.1-Flash-1017 の 6 つで、どれか 1 つだけが動く。

### メモリの使われ方

GB10 は CPU と GPU が同じ物理メモリを共有する。DeepSeek 系と Qwen 系のメモリ確保率 0.835 (キーは DeepSeek 系が `GPU_MEMORY_UTILIZATION_TEXT`、Qwen 系が `GPU_MEMORY_UTILIZATION`) は、通常の GPU なら VRAM の 83.5% だが、ここではシステムメモリ全体の 83.5% を意味する。起動直後から 100 GiB 超が確保されて `free` の残りが数 GiB になるが、設定どおりの先取りであって、リークでも不足でもない。期待値 121.7 × 0.835 = 101.6 GiB の近傍に収まる (DeepSeek 系 101.1 GiB / Qwen 系 100.7 GiB)。

他の 3 系統は確保率を持たない。V4.1 EXL3 系は重み (99.8 GiB。vision tower を含む) と KV プール (`KV_CACHE_MEMORY_BYTES` で固定した 2.5 GiB) を確保する。GLM 系は起動時の空きから 14.5 GiB の予備を残して予算を決める。1017 系は重み約 99 GiB を載せると残りが数 GiB になり、配信中に `MemAvailable` を床より上に保つ仕組みはエンジン側に無い (上流 README の「Memory and safety」)。V4.1 EXL3 系と 1017 系の残りは実際の余裕の少なさなので「既知の制約」11 に従う。配信中に重い処理を流すときは、どの系統でも同制約の上限付きで行う。

| 項目 | DeepSeek 系 head / worker | Qwen 系 head / worker | V4.1 EXL3 系 head / worker | GLM 系 head / worker | 1017 系 head / worker |
| --- | --- | --- | --- | --- | --- |
| 物理メモリ合計 | 121.7 / 121.7 GiB | 121.7 / 121.7 GiB | 121.7 / 121.7 GiB | 121.7 / 121.7 GiB | 121.7 / 121.7 GiB |
| 推論サーバの確保 | 101.1 / 101.1 GiB (`nvidia-smi` 103,540 / 103,530 MiB) | 100.7 / 100.8 GiB | 104.4 / 104.4 GiB (`nvidia-smi` 106,907 MiB) | 89.6 / 88.5 GiB (`nvidia-smi` 91,754 / 90,600 MiB) | 105.9 / 104.5 GiB (`nvidia-smi` 108,433 / 107,016 MiB) |
| `MemAvailable` | 6.8 / 7.1 GiB | 1.3〜5.7 / 5.6〜10.1 GiB | 4.8 / 5.9 GiB | 16.9 / 13.7 GiB | 6.3 / 7.7 GiB |
| swap 使用 | 4.3 / 5.4 GiB | 5.0 / 4.1 GiB | 4 / 7 GiB | 2.7 / 3.7 GiB | 1.6 / 0.6 GiB |
| 採った条件 | 2026-09-23、起動 15 分後の無負荷 | 2026-09-09 の再起動後の無負荷 (`MemAvailable` は 2026-09-06 の高負荷時からの幅) | 2026-09-30、画像入力を有効にして smoke と画像 2 件の後 | 2026-10-09、レシピ v1.10 (Ablit) で生成 10 件ほどの後 | 2026-10-22、生成 20 件ほどの後 |

- DeepSeek 系の swap は 44 時間 Qwen 系を配信した直後の値で、前の系統が押し出したページを含む。swap の量を系統の特性として読まない
- head の残りが worker より少ないのは、head だけがデスクトップセッション・sparkDash・tailscaled を抱えているためである
- Qwen 配信中の head の空きは負荷と稼働時間で 1.3〜5.7 GiB を動く (2026-09-06 の高負荷時 1.3〜1.7 GiB / 2026-09-09 の再起動直後 5.7 GiB)。これも先取りであって不足ではない。メモリを空けたくなったら、プロセスを探す前にこの値を疑う

## モデルの追加と切り替え

同じレシピの中でモデルを 1 つ足すときは、サーバ設定と OpenCode の宣言の 2 か所を整え、次の 4 段で進める。sparkDash の表示は配信名に追従するので触らない。別系統のレシピを足すときは clone・設定・イメージ取得も要る (V4.1 EXL3 系は Engram の取得と pack、GLM 系は別リポジトリのドラフタ、1017 系は Engram の取得と NFS の用意。→ 各系統ファイル「導入手順」)。

1. 重みを両ノードに配る。HF キャッシュへ置くモデルは `utility-spark-model-fetch` を使う
2. サーバの設定を合わせる。チェックポイント・revision・配信名のキーは系統で違う (DeepSeek 系は `.env.dspark` の `DSPARK_MODEL_OFFICIAL` / `DSPARK_REVISION` / `SERVED_MODEL_NAME`、Qwen 系は `.env` の `MODEL_ID` / `SERVED_MODEL_NAME`、V4.1 EXL3 系はモデル・Engram の固定 revision と `.env` の `SERVED_MODEL_NAME`、GLM 系は `scripts/config.sh` が解決する `MODEL_ID` / `MODEL_REVISION` / `SERVED_NAME` とドラフタの `DFLASH2_ID` / `DFLASH2_REVISION`、1017 系は同じく `MODEL_ID` / `MODEL_REVISION` / `ENGRAM_ID` / `ENGRAM_REVISION` / `SERVED_NAME`)。既存レシピが別モデルを受けるかは、そのレシピの起動前検査と設定で確かめる
3. `agents/bindings/opencode/opencode.json` の `providers.spark.models` に宣言を足す。`settings.reasoningEffort` / `limit` / `capabilities.tools` を書く (値の決め方は「OpenCode」)。受理される effort は各系統の API で確かめ、他モデルの値を流用しない。設定は symlink なので `drs` は要らない
4. 配信中の系統を止め、目的のモデルを起動して確かめる。「系統の切り替え」の手順 1〜4 で、`/v1/models` の配信名・上限と実際の生成を見る (GLM 系の上限は `/health` の `context_length`)

HF キャッシュに置く形の新しい open-weight は `utility-spark-model-fetch` で入れる。レシピ同梱の取得スクリプト (DeepSeek 系の `prepare-dspark-model-cache.sh` など) をそのまま使うと worker でも HuggingFace から落とし、同じ重みを 2 回取る。head で 1 回落として RoCE 経由で rsync すれば転送は 5〜8 分で済む。所有権の修正・シャードの検証・監視コマンドの落とし穴はスキル側にある。V4.1 EXL3 系と 1017 系は対象外で、手順は各系統ファイル「導入手順」にある。

### 系統の切り替え

系統を切り替えるときは、配信中の系統を止めてから目的の系統を起動する。どれも head の上で打つ。

| 系統 | 停止 | 起動 | 起動の判定 | 配信名 |
| --- | --- | --- | --- | --- |
| DeepSeek 系 (Vision-Exp 版) | `cd ~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark && ./stop-deepseek-v4-flash-dspark.sh` | `cd ~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark && ./start-deepseek-v4-flash-dspark.sh` | `dgx-spark/deepseek.md`「起動と判定」の 2 段 | `deepseek-v4-flash-vision-exp` |
| DeepSeek 系 (0731 版) | `cd ~/dspark-0731 && ./stop-deepseek-v4-flash-dspark.sh` | `cd ~/dspark-0731 && ./start-deepseek-v4-flash-dspark.sh` | 同上 (smoke は `~/dspark-0731` 側を打つ) | `deepseek-v4-flash-0731` |
| Qwen 系 | `cd ~/Qwen3.8-Flash-Next-Dual-DGX-Sparks && ./stop.sh` | `cd ~/Qwen3.8-Flash-Next-Dual-DGX-Sparks && ./start.sh --launch` | `dgx-spark/qwen.md`「起動と判定」の 3 段 | `qwen3.8-flash-next` |
| V4.1 EXL3 系 | `cd ~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks && ./start.sh stop` (`./stop.sh` も同じ動作) | `cd ~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks && ./start.sh` | `dgx-spark/v41-exl3.md`「起動と判定」の 3 段 | `DeepSeek-v4.1-Flash-EXL3` |
| GLM 系 | `cd ~/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold && ./stop.sh` | `cd ~/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold && ./start.sh` | `dgx-spark/glm.md`「起動と判定」の 3 段 | `GLM-5.3-Flash-EXL3` |
| 1017 系 | `cd ~/DeepSeek-v4.1-Flash-1017-2x-DGX-Sparks && ./stop.sh` | `cd ~/DeepSeek-v4.1-Flash-1017-2x-DGX-Sparks && ./start.sh` | `dgx-spark/1017.md`「起動と判定」の 3 段 | `DeepSeek-V4.1-Flash-1017` |

起動は数分かかるので、エージェントのシェル実行からは「長い処理を ssh から切り離す」の型で流す。V4.1 EXL3 系・GLM 系・1017 系をエージェントから打つ形 (ログインシェルを通すこと、環境変数の前置) は各系統ファイル「起動と判定」にある。

手順は次の 4 段である。

1. 稼働中のリクエストを確かめる。vLLM の 3 系統は `curl -s http://spark-head.local:8888/metrics | grep -E '^vllm:num_requests_(running|waiting)\{'` が両方 0。GLM 系は `/health` の `requests_running` が 0、1017 系は `/health` の `live.connections` と `live.waiting` が 0 (コマンドは「障害時」の末尾)
2. 配信中の系統を止める。表の「停止」
3. 止まったことを確かめる。停止コマンドの exit code を判定に使わない (V4.1 EXL3 系の `stop` は worker への ssh が失敗しても `stopped.` と出して exit 0 で終わる。1017 系の `stop.sh` は止められなかったノードがあると exit 1 を返すが、判定は他と揃える)。両ノードで次が 0 行であることを見る (worker は「worker に入る」の入れ子 ssh)

   ```bash
   docker ps --format '{{.Names}}' | grep -E 'vllm|dsv41|glm53'
   ```

   V4.1 EXL3 系・GLM 系・1017 系を起動するなら、両ノードの空きメモリも下の表の閾値と比べる。次は閾値 111.5 GiB の例で、exit 0 なら合格である (`/proc/meminfo` は kB で出るので GiB に直す)

   ```bash
   awk '/MemAvailable/{g=$2/1048576; printf "%.1f GiB\n", g; exit !(g>=111.5)}' /proc/meminfo
   ```

4. 目的の系統を起動して判定する。表の「起動」と「起動の判定」

先に相手系統を停止する。ポート 8888 を共有するうえ、起動側の事前検査が拒否する。停止コマンドを取り違えると相手系統のコンテナは消えないので、「止めたつもり」で次の起動が拒否される。

| 系統 | 起動前の検査 (拒否のメッセージ) | 空きメモリの閾値 (GiB) | 同時リクエスト上限 (本) | restart policy |
| --- | --- | --- | --- | --- |
| DeepSeek 系 | — | — | 6 | `unless-stopped` |
| Qwen 系 | `REQUIRE_IDLE_GPU=true` が、どちらかのノードで GPU を掴むプロセスを見つけた時点で止まる | — | 8 | `no` |
| V4.1 EXL3 系 | どちらか一方のノードでも `MemAvailable` が閾値に届かなければ止まる (`not enough free unified memory`)。閾値はレシピの `scripts/weight_budget.py` が見積もる 1 ランク分の重み 99.5 GiB に余裕 `DSV41_BOOT_MARGIN_GIB` (既定 12 GiB) を足した値で、見積りが取れないと警告だけ出して検査を飛ばす | 111.5 | 2 | `no` |
| GLM 系 | メモリは警告だけで止まらない (窓を縮めて起動し直す)。8888 が使用中なら止まる (`port 8888 is already in use`) | 110 (警告の境目) | 4 | `no` |
| 1017 系 | どちらか一方のノードでも `MemAvailable` が閾値に届かないか (`only … GiB memory available`)、8888 が使用中なら止まる | 112 | 4 | `no` |

同時リクエスト上限を超えた分はエラーにならずに待つ。V4.1 EXL3 系は 2 本しか並ばないので、subagent を並列に投げると待ちやすい。restart policy の意味は「既知の制約」8 にある。

クライアント側と表示の変更は要らない。OpenCode はプラグインが 30 秒ごとに `/v1/models` を引き直すので、開いたままの TUI も追従する。偽の `/v1/models` サーバで配信モデルを差し替えた実測 (2026-10-03) では 40 秒以内に切り替わり、それまでの 26 秒間は前のモデルのままだった (その間のリクエストは前のモデル名で飛ぶはずだが、確かめていない)。sparkDash も head の配信名を読んで表示する。

OpenCode が送る reasoning effort と、受理を確かめる対照の値は次のとおり。`/v1/chat/completions` は 5 系統とも「送る値」で 200 を実測済みである。語彙の全体は各系統ファイル「reasoning effort の語彙」にある。

| 系統 | 送る値 | 陽性対照 (400 になる値) | 陰性対照 (200 になる値) | 弾く層 | 実測した経路 (日付) |
| --- | --- | --- | --- | --- | --- |
| DeepSeek 系 | `high` | `bogus` (`high` も `medium` も受理するので他系統の値は使えない) | `high` | スキーマ (pydantic の Literal) | 3 経路 (2026-09-23) |
| Qwen 系 | `xhigh` | `high` | `xhigh` | チャットテンプレート | `/v1/messages`・`/v1/chat/completions` (2026-09-06)。`/v1/responses` は未実測 |
| V4.1 EXL3 系 | `max` | `medium` (`high` は受理される) | `max` | vLLM の検査 | `/v1/messages`・`/v1/chat/completions` (2026-09-15)、`/v1/responses` (2026-09-17) |
| GLM 系 | `max` | `bogus` | `max` | TensorFold のサーバ | `/v1/chat/completions`・`/v1/responses` (2026-10-04)、`/v1/messages` (2026-10-09) |
| 1017 系 | `max` | `bogus` | `max` | TensorFold のサーバ | `/v1/chat/completions` (2026-10-22、2026-10-30 に再確認) |

vLLM の 3 系統では、`none` が `/v1/chat/completions` と `/v1/responses` で通り、`/v1/messages` でだけスキーマに弾かれる (`AnthropicOutputConfig.effort` の Literal が `none` を持たない。仕組みは `dgx-spark/qwen.md`「reasoning effort の語彙」)。TensorFold の 2 系統は `none` を thinking の無効化として受ける。

### sparkDash の worker の表示名

worker の表示名は head の配信モデル名から導かれるので、切り替えのたびに直す必要は無い。sparkDash v2.32.0 は 2 か所に worker のモデル名を出す。

| 表示 | 何を出すか (優先順) |
| --- | --- |
| Overview の worker カード | head が配信中のモデル名 → 手書きの `workerLabel` → 導出名 (`workerDerivedLabel`) |
| worker のページの見出しのタグ | 手書きの `workerLabel` → 導出名 |

導出名は、worker の `workerHeadId` が指す head が配信中のモデル名である (`server/sparks/SparkMonitor.js` の `workerDerivedLabel`)。手書きの `workerLabel` (head の `~/sparkDash/config/sparks.json`) が残っていると worker のページで導出名より優先され、切り替え後に古い名前が出るので、空 (`null`) にしてある (2026-10-12)。同日に GLM 配信中に `workerDerivedLabel` が `GLM-5.3-Flash-EXL3` を返すことを確かめた。別の系統へ切り替えたときに追従するかはコードからの推論で、実際の切り替えでは確かめていない。

確認と戻し方は次のとおり。`PATCH` は動いているサーバへそのまま効き、`docker restart` は要らない。worker の監視が作り直されるので、数秒だけ worker が `online: false` になる。

```bash
# workerLabel が null で、workerDerivedLabel が /v1/models の配信名と同じなら合格
curl -s http://spark-head:5555/api/sparks/spark-worker/metrics | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("workerLabel"), d.get("workerDerivedLabel"))'
# 手書きの値を消す
curl -s -X PATCH -H 'Content-Type: application/json' -d '{"workerLabel":null}' http://spark-head:5555/api/sparks/spark-worker
```

## Mac から使う

Spark のクライアントは OpenCode である。素の `opencode` を打つと Tailscale 側 (`http://spark-head:8888/v1`) に繋がり、プラグイン `spark-served.ts` が配信中のモデルを選ぶ。コンテキスト上限は `opencode.json` の静的値を使う。

本書の手順と実測は Mac のものである。Mac 以外の端末からの利用は未検証である。OpenCode の本体と設定は通常の Linux と Android にも配られる (`nix/modules/home/packages.nix` / `packages-android.nix` と `opencode.nix`)。他の端末では `hms` による適用、Tailscale へのサインインと MagicDNS 名 `spark-head` の名前解決が要る。Linux と Android の Tailscale は dotfiles 管理外である。

### 新しいマシンで手で用意するもの

Nix (`drs`) では入らないものが 5 つある。

| もの | 用途 | 作り方 |
| --- | --- | --- |
| `~/.ssh/config` と鍵 2 本 | ssh エイリアス | 「接続する」 |
| `known_hosts` の 3 エントリ | エージェントの非対話 ssh | 「接続する」の `ssh-keyscan` (人が実行) |
| Tailscale へのサインイン | OpenCode は自宅でも出先でも要る (接続先が Tailscale 側に固定)。cask はアプリを置くだけで tailnet 参加は手作業 | アプリを開いてログイン。`tailscale status` に `spark-head` の行が出れば合格。cask だけで `tailscale` コマンドが入るかは確かめていない (この Mac の `/usr/local/bin/tailscale` はアプリ本体を `exec` する 2 行のシェルスクリプト)。無ければアプリのメニューから CLI を導入するか、`/Applications/Tailscale.app/Contents/MacOS/Tailscale status` を打つ |
| 1Password へのサインイン | `ccds` のトークン取得。無認証のいまは Spark 向けには要らず、認証を戻した後は Spark のキーにも要る | `op signin` |
| `/tmp/spark.key` (head のみ) | `bench.py` を打つときだけ。無認証の現在も文字列自体は要る | 「API キーの流れ」 |

`opencode` のバイナリ (`nix/pkgs/opencode.nix`) と設定の symlink は `drs` / `hms` が置く。Tailscale 本体は Mac の `nix/modules/darwin/homebrew.nix` の cask `tailscale-app` で入る。

### OpenCode

```bash
opencode                                   # 対話 TUI をカレントディレクトリで起動 (配信中のモデルをプラグインが選ぶ)
opencode run "README を要約して"            # headless で 1 回実行 (モデルの選び方は TUI と同じ)
opencode run --model spark/<配信名> "..."   # モデルを明示する (形式は provider/model#variant)
opencode --continue                        # 直前のセッションを続ける
opencode service status                    # 常駐サービスの状態 (stop / restart もある)
opencode --standalone                      # 常駐サービスを使わず、この起動専用のサーバで動く
```

ラッパーは無い。本体は V2 (2.0.22) で、`nix/pkgs/opencode.nix` が npm 配布のビルド済みバイナリを展開して入れる (nixpkgs の `opencode` は V1 の 1.18 系)。設定は `agents/bindings/opencode/` にあり、`nix/modules/home/opencode.nix` が `~/.config/opencode/` へファイル単位で symlink する。`opencode.json` (V2 書式。`providers` の `spark` に接続先とモデル宣言、`opencode` に OpenCode Zen の無料モデル 2 件の `limit` 上書き、ほかに `policies`・`permissions`・`default_agent`・`update`) と `plugins/spark-served.ts` は live edit で効く。`cli.json` (keybinds / theme) は TUI で設定を変えると symlink が切れる。同居するのは V1 用のプラグイン SDK (`node_modules` / `package.json` / `package-lock.json` / `.gitignore`。更新されておらず、`spark-served.ts` は import しない。V2 本体が読むかは確かめていない)、dotfiles への symlink の `AGENTS.md`、`sync-subagents.ts` の生成物 `agents/` である。

接続とモデルの選択:

- 接続先は Tailscale の MagicDNS 名 `http://spark-head:8888/v1` に固定してある。mDNS 名は使わないので、自宅でも Tailscale へのサインインが要る。2026-10-03 に Tailscale 経由で `/health` が 200 を返し、生成が通ることを実測した。mDNS 名と同種の名前解決の遅延 (到達できない IPv6 を先に試す) が出るかは計測していない
- 接続先の URL は `opencode.json` の `providers.spark.settings.baseURL` とプラグインの `BASE_URL` の 2 か所にある。プラグインの setup の時点では provider が組み立てられておらず `baseURL` を読めないためである。変えるときは 2 か所とも変える。一致は `spark-served_test.ts` が検査する (`deno test --allow-env --allow-run --allow-read --allow-write agents/` に含まれ、CI では回らないので自分で流す)
- プラグインは起動時と 30 秒ごとに `<BASE_URL>/models` を引き、宣言したモデルのうち配信中のものだけを有効にして既定に据える。配信していないモデルは TUI の選択肢から消える。起動前に止める検査は無い。再取得するのは常駐サービスが複数の起動をまたいで生き続けるためである。例外が 3 つある (ソースから読んだ挙動)
  - (a) 常駐サービスの起動時にサーバに届かなければ全モデルが有効のまま動き、届けば次の再取得 (30 秒以内) で絞り込む
  - (b) 稼働中に届かなくなったら直前の状態を保つ。401 などの失敗応答も届かないのと同じに扱う
  - (c) 宣言済みのモデルが 1 つも配信されていなければ何もしない。稼働中にそうなった場合に全モデル有効へ戻るかは確かめていない
  - 実測 (2026-10-03、V1 書式の設定): 「最近使ったモデル」に配信外の DeepSeek を入れた TUI で、プラグインありは配信中の GLM を選び、外した対照は DeepSeek を選んだ。偽の `/v1/models` サーバで DeepSeek → Qwen に替えると、開いたままの TUI が 40 秒以内に切り替わった。`opencode run` (`--model` 無し) でも GLM が選ばれた
- 判定のしかた: プラグインが効いているかは、宣言済みで配信していないモデルが `opencode models` の一覧から消えていることで見る。TUI の入力欄の下の `Plan · <モデル名>` だけでは判定にならない (V2 はプラグインが無くても宣言順の先頭か「最近使ったモデル」を既定に採り、宣言順の先頭は `GLM-5.3-Flash-EXL3` である)。2026-10-03 に `opencode models` を 3 回打ち、3 回とも当時の宣言 5 本のうち配信中の `spark/GLM-5.3-Flash-EXL3` の 1 行だけを返して exit 0 だった (プラグインを外した対照は取っておらず、絞り込みの効果だという点は未確認)。常駐サービスの起動直後は空を返しうるので、配信名の 1 行が出るまで 2 秒間隔で最大 10 回打ち直し、出なければプラグインか配布の失敗として扱う。プラグインはログを出さない。30 秒を過ぎても配信外のモデルが残るなら、`readlink -f ~/.config/opencode/plugins/spark-served.ts` が dotfiles 配下を返すかを見てから `opencode service restart` で読み込み直す
- 組み込みの vLLM 自動発見 (`opencode.provider.vllm`) は使わない。`owned_by` が `vllm` のモデルしか拾わず、provider ID も `vllm` に固定だからである (v2.0.22 のソースで確認)。TensorFold は `owned_by` に `tensorfold` を返す (GLM 系で 2026-10-03 実測)

常駐サービスとエージェント:

- 素の `opencode` は常駐の `opencode serve --service` (detached な子プロセス、launchd などには登録しない) を起動して接続し、TUI を閉じてもサービスは残る。待ち受けは全インターフェースの 49374 番である (2026-10-04 に `lsof -nP -iTCP:49374 -sTCP:LISTEN` が `*:49374` を返した)。`nix/modules/home/opencode.nix` の activation `opencodeServiceConfig` が `drs` / `hms` のたびに `~/.config/opencode/service.json` の `hostname` を `0.0.0.0` へ上書きするためで、外からの接続を防ぐのは同じファイルの `password` だけになる。次の 3 点は v2.0.22 のソースで確認したもので、実行しては確かめていない
  - サービスは最初に起動した TUI の環境変数を持ち続けるので、後から起動した `opencode` に前置した環境変数は効かない。接続先やモデルを環境変数で差し替える運用はできない
  - 設定ファイルとプラグインの変更はサービスが監視して自動で読み直す。反映されないときは `opencode service restart`
  - OpenCode の版が変わると、TUI が古いサービスを置き換える
- 表示の `Plan` は `default_agent: "plan"` による。`plan` はファイルを変更せず、実装を頼まれるとエージェントの切り替えを求める (v2.0.22 のバイナリ内のプロンプトから読んだもので、実行しては確かめていない)。編集を伴う作業は `build` へ切り替える。既定キーバインドは `shift+tab` (`agent.cycle`) と `<leader>a` (`agent.list`) である (バイナリ内の既定値表から読んだもの。確かめるならコマンドパレットで `Agent cycle` を探す)

`opencode.json` の書き方:

- `policies` は provider の利用をいったん全部 deny し、`spark` と `opencode` (OpenCode Zen) だけを allow する。したがって Zen の無料モデル `glm-5.3-flash-free` / `deepseek-v4.1-flash-free` も選択肢に入る。この 2 件は `limit.context` を 1,000,000 に上書きしてある (2026-10-17 に 100 万トークン級のプロンプトを受理した実績による)。Zen のモデルが既定に選ばれうる。V1 書式で provider を絞っていなかった 2026-10-03 に、起動直後の一瞬だけ `Build · Fledge Alpha Free (OpenCode Zen)` が既定として表示された。V2 書式の現在の設定で既定に選ばれるかは確かめていない
- `permissions` の `{ "action": "*", "resource": "*", "effect": "allow" }` は、OpenCode のツール実行をすべて確認なしで自動承認する (V1 の `permission: allow` と同じ意味と読んでいる。V2 書式での挙動は確かめていない)
- 各モデルに `reasoning: true` を書かない。V2 には対応するフィールドが無く、警告ログ (`omitted unsupported legacy setting`) を出して捨てる (2026-10-03 実測)
- `providers.spark.models` には配信しうるモデルを全部宣言する (プラグインは宣言済みのモデルからしか選ばず、配信中のモデルが宣言に無ければ例外 (c) のとおり何もしない)。値は、`limit.context` = `/v1/models` の `max_model_len` (GLM 系は `/health` の `context_length`)、`limit.output` = 65536、`capabilities.tools` = `true`、`settings.reasoningEffort` = そのモデルで受理を確認済みの値 (「系統の切り替え」の effort の表) である。`reasoningEffort` を省くと effort を送らずテンプレート既定が効くので、既定が変わっても黙って浅くならないよう明示する
- `limit.context` は人が書く静的値なので、サーバ側の上限を変えると取り残される。DeepSeek 系の 2 つ (`deepseek-v4-flash-vision-exp` / `deepseek-v4-flash-0731`) は 524,288 でサーバの 1,048,576 の半分、`GLM-5.3-Flash-EXL3` は 500,000 で約半分に取り残されている。害は早めに圧縮が走ることだけで、直すなら 1048576 にする。`qwen3.8-flash-next` (524,288) と `DeepSeek-v4.1-Flash-EXL3` (600,000) はサーバと一致する。`DeepSeek-V4.1-Flash-1017` の 400,000 はサーバの 1,048,576 より意図して小さくしてあり、揃えない (理由は `dgx-spark/1017.md`)
- `update: "disable"` は本体の自動更新を止める (本体は Nix 管理で store を書き換えられないため)。V1 書式の `autoupdate: false` を V2 がグローバルの `opencode.json` から読んで更新を止めることは v2.0.22 のソースで確認したが、`update` キーでの動作は確かめていない
- `providers.spark.package` (`aisdk:@ai-sdk/openai-compatible`) は V2 同梱の実装で解決され、実行時の npm install は起きないと見ている。V1 書式の `npm` キーについてソースで確認したもので、現在の書き方では確かめていない

`cli.json` とその他:

- `cli.json` は起動しただけでは書き換わらない (2026-10-03 に symlink で置いて TUI を 2 回起動し、symlink のまま中身も変わらないことを実測)。旧い名前のキーバインドが入っているとき (2026-10-03 に実測) と、テーマなどを TUI で変えたとき (v2.0.22 のソースで確認) は一時ファイルの rename で書き換えるので、symlink が実ファイルに化けて repo との同期が黙って切れる。設定は repo 側を編集して変え、TUI では変えない。`cli.json` を symlink で配る前の dotfiles が初回にコピーした実ファイルが残っていることもある
  - 直し方: dotfiles で `diff ~/.config/opencode/cli.json agents/bindings/opencode/cli.json` を見て残したい変更を repo 側へ取り込み、実ファイルを消して `drs` / `hms` で張り直す
  - 消さずに `drs` を打つと mac は `cli.json.hm-backup` へ退避するが、それが既にあると `would be clobbered by backing up` で止まる。Linux の `hms` は退避の設定が無いので、実ファイルがあるだけで止まる (→ dotfiles の `CLAUDE.md`「配布方式の移行」)
  - `drs` の前に `test -e ~/.config/opencode/cli.json.hm-backup` で古い退避を見る (2026-10-04 時点のこの Mac には無い)。あれば `diff ~/.config/opencode/cli.json.hm-backup agents/bindings/opencode/cli.json` (dotfiles で実行) が何も出さないことを確かめてから消す
  - wezterm の Cmd+p は alt+p を送り、`cli.json` の `command.palette.show` (`alt+p,super+p`) に当たる
- CLI: トップレベルの `--model` は無い。`run` と `mini` にはあり、形式は `run` が `provider/model#variant`、`mini` が `provider/model` (`#variant` を取らない)。`run --dir` は無く、カレントディレクトリで動く (2026-10-03 に `--help` で確認)
- live edit が効いているかは `readlink -f` で判定する。単 hop の `readlink` では判らない (理由は「依拠する外部事実」の該当行)。`opencode.json` と `plugins/spark-served.ts` が dotfiles 配下に解決すれば、編集は常駐サービスの読み直しで次のリクエストから効く (読み直しはソースでの確認)

## 実測値

数値は条件が変わると簡単に 25% 動くので、表ごとに条件を書いてある。閾値だけを覚えて条件を変えて測ると誤診する。

この節の値はすべて GPU クロック制限 (2,200 MHz) が有効な状態で採った。X925 の `scaling_max_freq` を下げたのは 2026-09-10 なので、それより前の表はその前の値である (前後で単一ストリームの所要時間に差が出ないことは確かめたが、この節の並列条件では取り直していない →「既知の制約」4・5)。

### L1: サーバ単体 (2026-09-05)

`~/spark-bench/bench.py` で DeepSeek 系 (Vision-Exp) のサーバを直叩きした値である。条件はプロンプト 6,000 トークン、`max_tokens` 256、`chat_template_kwargs={"thinking": true, "reasoning_effort": "low"}` (サーバ既定の `DEFAULT_THINKING=low` と同じ)、指示は下のコマンドの `--instruction`。`c` は `--concurrency`。値は中央値と (最小〜最大)。

`chat_template_kwargs` は `--extra-body` でしか渡せず、`bench.py` はこのキーの既定を持たないので、`--extra-body` を落とすと思考が既定のまま走る。これはテンプレートに直接渡す第 4 の経路で、各 API の `reasoning_effort` (Chat Completions) / `output_config.effort` (Messages) / `reasoning.effort` (Responses) と違い、スキーマの Literal 検査を通らない。`bench.py` は `min_tokens` を `max_tokens` と同値にし `ignore_eos` を立てるので、生成長は常に 256 トークンである。

| 条件 | n | Vision-Exp |
| --- | --- | --- |
| c=1・decode (tok/s) | 5 | 40.77 (34.88〜62.80) |
| c=1・TTFT (秒) | 5 | 3.47 (3.20〜3.93) |
| c=4・decode (tok/s) | 8 (4 並列 × 2 回) | 21.95 (14.44〜34.88) |
| c=4・TTFT (秒) | 8 (4 並列 × 2 回) | 9.44 (4.93〜13.47) |

判定 (Vision-Exp 版): c=1 の decode 中央値が 35 tok/s を下回る、または c=4 の TTFT 中央値が 15 秒を超えたら異常を疑う。0731 版の閾値は採っていないので、0731 配信中は「decode の分解 (2026-09-23)」の表と比べる。個別値ではなく中央値で見る (正常時でも最小値は 34.88 tok/s まで落ちる)。再現は次の 2 本で、結果は `~/spark-bench/results/<ラベル>-<日時>.json` に残る。

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

decode tok/s は「1 ステップで確定するトークン数 ÷ 1 ステップの時間」で決まる。DeepSeek 系では 1 ステップの時間は内容にも文脈長にもほぼ依らず、速度の差はほとんどが 1 ステップのトークン数、つまり受理率から来る。

測り方: 各リクエストの前後で `/metrics` を読み、`vllm:spec_decode_num_drafts_total` の増分を decode ステップ数とする。1 ステップの時間 = (最終トークン時刻 − 初回トークン時刻) ÷ ステップ数、1 ステップのトークン数 = `vllm:generation_tokens_total` の増分 ÷ ステップ数。他のリクエストが重なると分解が壊れるので、16 秒続けて無負荷になってから 1 本ずつ投げ、`generation_tokens_total` の増分が自分の `completion_tokens` と一致した回だけを採った (両チェックポイントとも 21 回中 21 回が一致)。スクリプトは使い捨てで、リポジトリには置いていない。値は各条件 3 回の中央値で、プロンプトは末尾に指示を 1 つ付けたもの、フィラーは `bench.py` と同じ繰り返し文である。

| 条件 | Vision-Exp tok/s | Vision-Exp tok/step | Vision-Exp step (ms) | 0731 tok/s | 0731 tok/step | 0731 step (ms) |
| --- | --- | --- | --- | --- | --- | --- |
| 数の列挙、thinking off | 81.0 | 5.71 | 69.8 | 90.5 | 5.94 | 65.5 |
| コード、thinking off、短文 | 70.0 | 5.05 | 71.7 | 80.2 | 5.50 | 68.5 |
| コード、32K 文脈 | 66.6 | 4.86 | 72.9 | 80.0 | 5.56 | 69.4 |
| コード、100K 文脈 | 64.4 | 4.99 | 75.4 | 75.9 | 5.44 | 71.6 |
| 6K フィラー + コード指示、thinking `low`、256 トークン強制 (L1 と同条件) | 42.4 | 3.05 | 71.6 | 44.4 | 2.84 | 64.7 |
| 同じ入力で自然終了 | 44.8 | 3.17 | 70.5 | 46.1 | 2.98 | 64.4 |
| 日本語の散文、thinking off | 26.8 | 1.77 | 65.9 | 33.8 | 2.12 | 62.4 |

- 1 ステップの時間は短文から 100K まで +5% しか伸びない。長い文脈が decode を遅くしているわけではない
- 日本語の散文は受理率が低い (Vision-Exp 0.13 / 0731 0.22)。上流が測った英語の散文は Vision-Exp で 0.25 前後である。ドラフタが日本語を苦手にしている可能性があるが、プロンプト 1 つからの推測である
- 1 ステップ約 70 ms は 2 台 TP=2 の固定費である。投機の全トークンが受理されても上限はおよそ 100 tok/s (Vision-Exp の k=6 で 7 トークン ÷ 70 ms)
- 実負荷の単一ストリーム区間も同じ形に分解できる。Vision-Exp 配信中に他のリクエストが重ならなかった区間を外から 124 秒ぶん観測すると、42.6 tok/s = 3.30 トークン ÷ 77 ms で、位置別の受理率は 0.80 / 0.56 / 0.39 / 0.27 / 0.17 / 0.105 だった

### L3: OpenCode 込み (2026-09-05)

Vision-Exp 配信中に同一の TypeScript タスク (Read → Edit → Edit → Grep の 4 tool call) を 2 回実行し、`~/spark-bench/snap.py` で `/metrics` の前後差分を取った。OpenCode は opencode 1.18.18 で、V2 では測り直していない。effort は未指定でテンプレート既定が効いた条件なので、現行の明示的な設定と直接比較しない。`snap.py` の起動方法・引数・出力先は記録していないので、再現には head 上の実物を読む。

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

1. OpenCode の接続先とモデル設定。Tailscale 側の `/health` が応答し、`opencode models | rg '^spark/'` が配信名の 1 行だけを返すかを見る。常駐サービスが古い設定を持つときは `opencode service restart`
2. プロンプトの長さ。指示・会話履歴・ツール結果が増えると prefill も増える。サーバの入力トークン数と TTFT を比べ、クライアント側の入力量が変わっていないかを見る
3. prefix cache のヒット率。機構は正常に動く (同一プロンプトを 2 回送れば 2 回目にヒットが立つ)。実負荷のヒット率はクライアントがプレフィックスをどれだけ安定させるかで決まる。L3 の実測レンジは 0.73〜0.90 で、0.5 を切ったらクライアント側の変動を疑う
4. 投機デコードの受理率。L3 の実測レンジは 0.66〜0.69 で、0.4 を切ったら疑う。生成させる内容で動く (構造化された出力で高く、散文で低い)
5. サーバ本体。ここまで潰してから L1 のベンチを上のフラグで回す。GPU クロックの制限と X925 の `scaling_max_freq` の引き下げ (→「既知の制約」4・5) は、外しても速度がほぼ変わらないと実測済みなので最初に疑わない。切り分けで外すなら、外して測って戻すまでを 1 セットで行う (戻し忘れると温度だけが上がった状態が残り、サーバ側に履歴が無いので誰も気づけない →「既知の制約」6)

3 と 4 の実測レンジは vLLM の値なので、TensorFold の 2 系統の判定には使えない。値の取り方はエンジンで違う。

| エンジン | prefix ヒット率 | 受理率 |
| --- | --- | --- |
| vLLM (DeepSeek 系・Qwen 系・V4.1 EXL3 系) | `/metrics` の `prefix_cache_hits_total` ÷ `prefix_cache_queries_total` | `/metrics` の `spec_decode_num_accepted_tokens_total` ÷ `spec_decode_num_draft_tokens_total` |
| GLM 系 | `/health` の `cached_tokens_total` ÷ `prompt_tokens_total` | `/health` の `accepted_total` ÷ `drafted_total` (キーの意味はキー名から読んだもので、ソースでは確かめていない) |
| 1017 系 | `/metrics` の `tensorfold:prefix_cache_hits_total` ÷ `tensorfold:prefix_cache_queries_total` (系列名から組んだ式で、値を出して確かめてはいない) | `/metrics` の `tensorfold:mtp_accepted_total` ÷ `tensorfold:mtp_drafted_total` |

vLLM の値は次の 1 本で取る。キー名は完全一致で拾う。`prefix_cache` には `vllm:external_prefix_cache_*` が、`spec_decode_num_.*_total` には `vllm:spec_decode_num_accepted_tokens_per_pos_total` が別に存在し、緩い grep は別系列を合算して値を過大に出す。

```bash
curl -s http://spark-head.local:8888/metrics | grep -E '^vllm:(prefix_cache_(hits|queries)_total|spec_decode_num_(accepted_tokens|draft_tokens)_total|request_(prompt|generation)_tokens_sum|request_success_total)'
```

1 リクエストの平均生成長 = `request_generation_tokens_sum` ÷ `request_success_total` の全 `finished_reason` の合計 (`stop` / `length` / `abort` / `error` / `repetition` の 5 行に分かれて出るので足す。`length` が多ければ出力の打ち切りが起きている)。

本構成の律速は decode ではなく prefill である。実負荷での累計プロンプト対生成トークン比は 100:1 前後、1 リクエストの生成長は数百トークンにとどまるので、decode を速くする施策は体感に効きにくい。counter はコンテナの再起動でリセットされるので、「現コンテナが起動してからの累計」として読む。

## 障害時

コンテナ名は系統で違う (冒頭の表)。系統ごとのログと起動の所要は次のとおり。worker のログは「worker に入る」の入れ子 ssh で同じものを打つ。

| 系統 | ログ | 正常な起動の所要 | 両ランクを疑う目安 / 諦めるまで |
| --- | --- | --- | --- |
| DeepSeek 系 | `./logs-deepseek-v4-flash-dspark.sh` | 約 7〜8 分 | 12 分を超えたら worker 側だけ落ちていることがある |
| Qwen 系 | `docker logs vllm-fn` | 約 13〜14 分 | 20 分を超えたら両ランクを見る |
| V4.1 EXL3 系 | `./start.sh logs` / `./start.sh logs worker` とレシピの `logs/` | コンテナ起動から health まで約 8 分 | 15 分を超えたら worker 側を見る。`start.sh` は health を 1,500 秒待って諦め、コンテナは残る |
| GLM 系 | `docker logs glm53-flash-tf` (停止済みのランクは `~/.cache/tensorfold-glm53/logs/`) | 約 5〜7 分 (版ごとの実測は `dgx-spark/glm.md`) | `start.sh` は `WAIT_TIMEOUT` (既定 1,800 秒) で諦める |
| 1017 系 | `docker logs dsv41-1017-exl3-tf` (停止済みのランクは `~/.cache/dsv41-tensorfold/logs/`) | 準備済みならサーバの読み込み約 40 秒 (2026-10-22) | `start.sh` は `WAIT_TIMEOUT` (既定 2,400 秒) で諦める |

| 症状 | 確認 | よくある原因 |
| --- | --- | --- |
| 応答しない | 下の待ち行列コマンド | コンテナは生きていて過負荷。同時リクエスト上限 (「系統の切り替え」の表) を超えた分が待つ |
| コンテナが無い | 両ノードで「系統の切り替え」の手順 3 のコマンド (5 系統すべてを拾う) | 停止コマンドで止めたまま、またはノードの再起動 (DeepSeek 系以外は上がらない →「既知の制約」8)。起動し直す |
| 起動に失敗する | 上の表のログ | 相手系統が動いている (拒否のメッセージは「系統の切り替え」の事前検査の表)。`no usable RoCEv2 GID` は RoCE 2 本目の IP か MTU (→「ネットワーク」)。系統ごとのエラー文と対処は各系統ファイル (「起動と判定」「導入の落とし穴」「障害時 (<系統>)」など)。V4.1 EXL3 系は失敗してもコンテナが残るので `./start.sh stop` してから起動し直す。GLM 系の worker 側の `transport retry counter exceeded` は rank 0 が落ちた後の二次症状なので head 側から読む。1017 系が配信中に落ちたら memguard の kill を疑い、`~/.cache/dsv41-tensorfold/logs/memguard.log` を読む |
| 起動待ちが長すぎる | head は `docker logs <コンテナ名>`、worker は「worker に入る」で同じもの | 上の表の目安を超えたら両ランクを見る |
| `model not found` が出る | `curl .../v1/models` で配信名を見る | セッション起動後にサーバ側で切り替えた。OpenCode はプラグインの再取得で 40 秒以内に追従する。GLM 系は配信していないモデル名でも応答を返すので、このエラーにならず GLM がそのまま答える (→ `dgx-spark/glm.md`「使える API」) |
| OpenCode が Spark に繋がらない | `tailscale status` に `spark-head` の行があるか (コマンドが無ければ「新しいマシンで手で用意するもの」)、`curl -fs -o /dev/null http://spark-head:8888/health` の exit code | 接続先は Tailscale 側に固定なので、自宅でも Tailscale にサインインしていないと届かない。LAN 経路へ切り替える手段は無い |
| OpenCode の選択肢に配信していないモデルが残る・既定が配信外のモデルになる | `opencode models`、`readlink -f ~/.config/opencode/plugins/spark-served.ts`、`curl -s http://spark-head:8888/v1/models` の配信名が `providers.spark.models` にあるか | プラグインが動いていないか、`/v1/models` に届いていないか、配信中のモデルが宣言されていない (例外 (a)〜(c) と判定のしかたは「OpenCode」)。読み込まれていないようなら `opencode service restart` |
| OpenCode Zen のモデルが選択肢に出る | `opencode.json` の `policies` | `policies` が `opencode` provider を allow しているので、Zen の無料モデル 2 件が出るのは現在の設定どおりである |
| 前置した環境変数が OpenCode に効かない | `opencode service status` | 常駐サービスを起動した最初の TUI の環境変数が使われ続ける (v2.0.22 のソースで確認)。その起動専用のサーバで動かすなら `--standalone` を付ける (それで効くことは確かめていない) |
| reasoning effort の 400 (`Unexpected reasoning effort <値>` など) | `opencode.json` の `settings.reasoningEffort` と、送っている値 | 系統の語彙外の値を送った。「系統の切り替え」の effort の表と各系統ファイル「reasoning effort の語彙」を見る |
| `Input should be 'low', 'medium', ...` の 400 | 送っている effort の値 | vLLM の系統の `/v1/messages` に `none` を渡した。スキーマが `none` を持たないので、テンプレートより手前で弾かれる。OpenCode の経路 (`/v1/chat/completions`) では `none` が通る |
| 推論中に CPU が熱い・ファンがうるさい | 「依拠する外部事実」の温度の行と、コードブロック 1 | 正常。vLLM のスレッドが 100% の使用率で回り、GPU 使用率とは独立に CPU 側センサーが上がる (→「既知の制約」5)。X925 の `scaling_max_freq` を下げる対処は入れてあり、それでも高いなら室温か吸気を疑う |
| 起動直後から空きメモリが少ない | `free -h` | DeepSeek 系と Qwen 系なら確保率 0.835 の先取りで正常 (残りは DeepSeek 系 6〜8 GiB、Qwen 系の head 1.3〜5.7 GiB)。V4.1 EXL3 系と 1017 系の head の残り (4.8 GiB / 6〜7 GiB) は実際の余裕で、配信中はこれ以上減らさない (→「既知の制約」11)。GLM 系は無負荷で 12〜15 GiB 残る。値は「メモリの使われ方」 |
| 全体的に遅い | 「遅いと感じたときに疑う順序」を上から | クライアント側が大半 |
| ダッシュボードの worker が古いモデル | 「sparkDash の worker の表示名」の確認コマンド | 手書きの `workerLabel` が worker のページで導出名より優先されている。同節の `PATCH` で `null` に戻す |
| ダッシュボードが開けない | `curl -s http://spark-head:5555/api/health` の `authMode` と、`ssh -n spark-head 'docker inspect sparkDash --format "{{range .Config.Env}}{{println .}}{{end}}"'` に出る `BIND_HOST` の行 | override の `BIND_HOST=0.0.0.0` が効いていない。v2 の既定は `127.0.0.1` で、head 以外からは繋がらない |
| ssh 出力が途中で切れる | 打ったコマンド | 入れ子の `ssh` が標準入力を飲んでいる。内側に `-n` を付ける |
| `opencode` が `command not found` | `type opencode` がパスを返すか | `drs` / `hms` 未実行か、新しいシェルを開いていない |

1 系統だけで起きる障害は各系統ファイルにある (Qwen 系の `Checkpoint snapshot is incomplete` は `dgx-spark/qwen.md`「重みの検証」、V4.1 EXL3 系の配信中の停止は `dgx-spark/v41-exl3.md`「障害時 (V4.1 EXL3 系)」、GLM 系の画像入力だけの `CUBLAS_STATUS_INTERNAL_ERROR` は `dgx-spark/glm.md`「障害時 (GLM 系)」)。

待ち行列と稼働中リクエストは次で見る。

```bash
curl -s http://spark-head.local:8888/metrics | grep -E '^vllm:num_requests_(running|waiting)\{'
# GLM 系 (TensorFold) は vllm: の系列を出さないので、/health を読む
curl -s http://spark-head.local:8888/health | python3 -c 'import json,sys; h=json.load(sys.stdin); print("running", h["requests_running"], "streams", h["streams"])'
# 1017 系 (TensorFold の Zig エンジン) は /health の live を読む
curl -s http://spark-head.local:8888/health | python3 -c 'import json,sys; l=json.load(sys.stdin)["live"]; print("running", l["connections"], "waiting", l["waiting"])'
```

## ノードを作り直したときに手で戻すもの

次のものは dotfiles にも上流にも無く、ノードを作り直すと失われる。1 系統だけのもの (DeepSeek 系の `~/dspark-0731` の worktree、V4.1 EXL3 系の `/v1/responses` のローカルパッチ、1017 系の head の NFS サーバ) は各系統ファイルにある。

| もの | 置き場 | 戻すときの材料 |
| --- | --- | --- |
| head から worker への鍵と `known_hosts` | head の `~/.ssh/id_ed25519` と、head の `known_hosts` の RoCE アドレスの行 | 鍵は作り直して worker に登録する。`known_hosts` は人が登録する |
| クロック制限の unit 2 本 | 両ノードの `/etc/systemd/system/nv-{gpu,cpu}-clock-limit.service` | CPU 側は「既知の制約」5 に全文がある。GPU 側は `ExecStart` の中身 (`nvidia-smi --lock-gpu-clocks=0,2200`) だけが「既知の制約」4 にある |
| 各レシピの手元設定 | DeepSeek 系の `.env.dspark` (Vision-Exp 版と `~/dspark-0731` に 1 枚ずつ)、Qwen レシピと V4.1 EXL3 レシピの `.env`、GLM レシピと 1017 レシピの `scripts/local.sh` | 各系統ファイル「構成」の上流既定からの差分。値に IP を含むものは各系統ファイル「依拠する外部事実」の確認コマンドで引き直す |
| `hf` CLI | head の `~/.local/bin/hf` (`~/.venvs/hf/bin/hf` への symlink、1.30.0) | 入れ方の記録は無い。venv に `huggingface_hub` を入れたものと見ている (推測) |
| `~/spark-bench` | head | 再作成手段が無い (→「既知の制約」9) |
| sparkDash | head の `~/sparkDash/` と、未追跡の `docker-compose.override.yml`、`.gitignore` 済みの `config/` の状態ファイル (`sparks.json`・暗号化した秘密 `sparks-secrets.json` とその鍵 `.secrets-key`・ベンチと電力量の履歴) | clone は上流から取れ、イメージは「sparkDash を更新する」で作り直せる。上書きの中身は `BIND_HOST=0.0.0.0` とポーリング間隔 (→「動いているもの」) と worker 用の鍵の mount `/home/skanehira/.ssh/id_ed25519:/root/.ssh/id_ed25519:ro`。`workerLabel` は空にする |
| RoCE の接続 | 両ノードの NetworkManager の接続 `roce` / `roce2` | 「ネットワーク」(別サブネット・MTU 9000) |
| Tailscale | head だけ | MagicDNS 名 `spark-head` |

## 残骸の片付け

消してよいものと、その条件である。取り直せないものを消すかは人が決める。1 系統だけの残骸 (GLM 系の TR3 の重みと旧イメージと CUDA 拡張、V4.1 EXL3 系と GLM 系のイメージの blob 置き場、1017 系の旧イメージと取得途中のファイル、V4.1 EXL3 系の起動失敗のログ) は各系統ファイルにある。

| 残骸 | 置き場 | 消してよい条件 | 消し方 |
| --- | --- | --- | --- |
| 古い revision の HF キャッシュ | 両ノードの `~/.cache/huggingface/hub/models--*/snapshots/<旧 revision>` | その revision へ戻さないと決めたとき | `hf cache rm` (ログインシェルで。使い方は `hf cache --help`。当方では未実行) |
| 起動とダウンロードのログ | head のホームの `~/dsv41-start.log` / `~/glm53-tf-start.log` / `~/dsv41-1017-start.log` と、「長い処理を ssh から切り離す」で書いたログとスクリプト (2026-10-06 の Ablit 導入の `~/glm53-ablit-fetch.{sh,log}` / `~/glm53-ablit-rsync.{sh,log}` / `~/glm53-image.{sh,log}`、2026-10-20 の 1017 系の `~/dsv41-1017-fetch.{sh,log}` と `~/.local/state/dsv41-1017-fetch/`) | 読み終えたらいつでも (次の起動で上書きされる) | `rm` |
| GLM 系と 1017 系のサーバのログ | 各ノードの `~/.cache/tensorfold-glm53/logs/` と `~/.cache/dsv41-tensorfold/logs/` | 手で消さなくてよい (`stop.sh` と `start.sh` が新しい 10 本だけを残す) | — |
| sparkDash の旧版のイメージ `sparkdash-sparkdash:1.8.6-cc44d35` と退避物 `~/sparkDash-backup-1.8.6/` (`config.tgz` は `.secrets-key` を含む) | head | v2.32.0 で困らないとユーザーが決めたとき (1.8.6 へ戻す材料。「sparkDash を更新する」の「戻すとき」) | `docker rmi sparkdash-sparkdash:1.8.6-cc44d35` と `rm -rf ~/sparkDash-backup-1.8.6` |
| 作業ファイル | head と worker の `/tmp` (`/tmp/vs.py` / `/tmp/qwen-manifest.json` / `/tmp/spark.key` など) | 手で消さなくてよい (再起動で消える) | — |
| 計測の結果 | head の `~/spark-bench/results/` | 消さない。過去の値と比べる元で、ハーネスごと再作成手段が無い (→「既知の制約」9) | — |

## 触らないもの

- `~/.ssh/known_hosts`: エージェントは書き換えない。登録が要るときは `ssh-keyscan` の 1 行をユーザーに依頼する
- `drs` / `hms` の実行: `drs` は Touch ID を、`hms` は sudo (`/etc/codex/config.toml` の symlink) を伴うので、エージェントは打たない。`git add` までをエージェントが行い、適用はユーザーに依頼する
- `~/sparkDash/docker-compose.yml`: 上流の追跡ファイル。上書きは `docker-compose.override.yml` に置く
- head での sparkDash のビルド (`docker compose up --build` や、`--no-build` 抜きの `docker compose up`): 配信中の head のメモリを上限無しに使う。Mac でビルドして読み込む
- sparkDash の `config/.secrets-key`: 消すと `sparks-secrets.json` に暗号化して入れた秘密が読めなくなる。退避した tar も同じ鍵を含むので 600 のまま置く
- 公開リポジトリ内のファイルへの IP 直書き: 本書と `agents/bindings/opencode/` に書かない。OpenCode は Tailscale の MagicDNS 名を使う
- 公開リポジトリ内のファイルへの API キー直書き: 認証を戻すときも `opencode.json` に平文で置かない。外部へ逃がす手段は「API キーの流れ」の手順 2 (V2 で解かれるかは未確認)
- 公開リポジトリの clone の中に置くキー入りの控え: `.gitignore` は `.env.dspark` などの決まった名前しか拾わないので、`.env.dspark.bak` のような控えはキー行ごと追跡対象に入りうる。作ったら使い終わりに消す
- クロック制限の 2 unit (`nv-gpu-clock-limit.service` / `nv-cpu-clock-limit.service`): 切り分けで一時的に外すのは構わないが、外したままにしない。サーバ側に温度の履歴が無いので戻し忘れに誰も気づけない (→「既知の制約」4・5・6)
- sparkDash のポート 5555: 認証が無いので信頼できないネットワークへ出さない
- ポート 8888: 系統を問わず無認証なので外に出さない (→「動いているもの」)

1 系統だけの「触らないもの」(DeepSeek 系の `docker compose restart` と `~/dspark-0731` の git の状態、V4.1 EXL3 系の `~/dsv41-local/` と `start.sh` のローカル差分) は各系統ファイルにある。

## 既知の制約

1. Spark には passwordless sudo が無い。`/etc/sudoers.d/` は README のみである。`nvidia-smi --lock-gpu-clocks`・`scaling_max_freq` への書き込み・systemd の操作など sudo が要る作業はエージェントからは実行できないので、コマンドを提示して人間に実行してもらう (パスワードは `skanehira` の Ubuntu ログインパスワードで、本書には保管しない)。Mac の Touch ID による sudo は Linux ノードには効かない。コンテナ内で root が必要な作業 (重みの所有権修正など) は `docker run --entrypoint` で代替できる
2. worker への直接 ssh は `known_hosts` の登録が前提である。未登録のマシンではエージェントから入れないので「worker に入る」の head 経由を使う
3. worker は Tailscale に参加していない (`tailscaled` が未インストール)。出先から worker を見るには head を経由する
4. GPU クロックを 2,200 MHz に制限している。両ノードの `/etc/systemd/system/nv-gpu-clock-limit.service` (手で配置、enabled + active) が起動時に `nvidia-smi --lock-gpu-clocks=0,2200` を実行する。2026-09-05 の計測 (n=5、L1 とは別条件で結果ファイルは残っていない) では、解除しても decode +1.3% / 最悪 TTFT 約 +2% しか上がらず、温度が 7 °C 以上上がった (制限あり 52〜58 °C / 制限なし 60〜65 °C) ので、制限は維持する
5. X925 の `scaling_max_freq` を 2,808 MHz に下げてある。unit 名に反して、これはハードウェアのクロック上限を変えていない。両ノードの `/etc/systemd/system/nv-cpu-clock-limit.service` (手で配置、`Type=oneshot` + `RemainAfterExit=yes`、enabled + active) が起動時に cpu5-9・cpu15-19 の `scaling_max_freq` へ `2808000` (kHz。sysfs の周波数はすべて kHz) を書く。dotfiles に控えが無いので下に全文を載せる (制約 9 と同じく再作成手段が無い資産である)
   - 効いていないもの (実測): 書き込みは受理されるが CPPC のレジスタに伝播しない。`max_perf` は cpu5 が 3900000、cpu19 が 4004000 のままで、負荷中に X925 が走ると実効クロック (`cpuinfo_avg_freq`) は 3,886,695〜3,898,425 に達する
   - 判別に使えない指標: `scaling_cur_freq` は `cppc_cpufreq` では要求値のエコーなので実効値と読まない (busy な A725 は要求値と実効値が一致するのに busy な X925 だけ 1.1 GHz 乖離する。この非対称がエコーである対照になる)。速度が変わらないことも判別に使えない (設定が効いていなくても速度は変わらない)。判別材料は温度と busy コアの載り先だけである
   - 実際に起きたこと (実測): 書き込みの前後で vLLM の busy スレッドの載り先が X925 から A725 へ移った。前は cpu15 が 70%・cpu18 が 78% と X925 が主で、後は cpu0〜cpu4 のうち 3 本が 91〜100% で回る。X925 も使われ続けており、連続負荷中に 8 回サンプルしたうち 1 回は cpu19 が 92% で busy、実効クロック 3,882,785 だった。どういう条件で X925 に載るかは特定していない。「`scaling_max_freq` を下げたことでスケジューラの capacity の見立てが変わった」と読んでいるが、推測である
   - 熱くなる理由: vLLM のスレッド 3 本 (`VLLM::EngineCore` / `VLLM::Worker_TP` / `VLLM::Worker`) が 100% の使用率で回り続け、その間クロックが最大に張り付く。ここまでが実測である。1 decode ステップ 63 ms のうち GPU 使用率は 93%、スレッドが自発的にブロックするのは 1 ステップあたり 2〜5 回なので、CPU 時間の大半は完了待ちのスピンだと読んでいる (推測)。待ち先が CUDA の同期か NCCL かは未確認である
   - governor: `schedutil` / `ondemand` / `conservative` はスピンを使用率 100% と見て最大クロックを選ぶので効かない。`powersave` は最小クロックに固定するので温度は下がるが、直列処理まで 338 MHz に落ちる (未検証)
   - 速度と温度の実測 (2026-09-10、Qwen3.8-Flash-Next 配信中、単一ストリーム・800 トークン、GPU 制限は両条件で有効、n = 制限前 3 / 制限後 2、結果ファイルは残していない): 速度低下は無かった (制限前 26.06〜26.80 秒 / 制限後 24.55〜26.02 秒)。2 群のレンジはわずかに重ならず制限後が速いが、説明できていない (n が少ない、prefix cache の状態や直前の熱状態が揃っていない)。言えるのは「遅くなってはいない」までである。温度は TS0P が 62.0 → 47.7〜49.5 °C、TSOC が 62.5 → 52.5〜53.6 °C に下がった (センサー名は制約 6)。並列時 (Qwen は最大 8 リクエスト) は未計測である
   - 評価: 目的 (温度を下げる) は達しているが、意図した機構では動いていない。素直にクロックを縛るなら CPPC の `max_perf` を動かす手段を別に探す
   - 解除と復帰: 両ノードで `sudo systemctl disable --now nv-cpu-clock-limit.service` で解除する (`ExecStop` が `cpuinfo_max_freq` の値を `scaling_max_freq` へ書き戻す)。戻すのは `sudo systemctl enable --now nv-cpu-clock-limit.service`。worker には「worker に入る」のコマンドで同じものを打つ (sudo が要るので実行は人間)

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

6. 温度センサーは ACPI の 7 つで、その履歴はどこにも残っていない。`/sys/class/thermal/thermal_zone{0..6}/temp` がミリ °C を返す。名前は起動ログ (`journalctl -b -q -o cat | grep 'Thermal Zone \['`) が登録順に出し、zone0 = `TSOC` (SoC 全体) / zone1 = `TS0E` / zone2 = `TS0P` / zone3 = `TS1E` / zone4 = `TS1P` / zone5 = `TGPU` / zone6 = `TUNC` である。`TS<n>E` / `TS<n>P` を効率コアと性能コアに対応させる読み方は推測で、NVIDIA の資料では裏を取っていない (X925 の制限で `TS0P` が 14.3 °C 下がった実測とは整合する)。トリップ点は全 zone とも 104.8 °C、`policy` は `step_wise`。`TSOC` の 3 文字目は英字の O、`TS0P` / `TS0E` の 3 文字目は数字のゼロで、grep するとき紛らわしい
   - sparkDash は CPU 温度も採るが (`~/sparkDash/server/collectors/SystemCollector.js` が hwmon の `acpitz` と thermal zone を読む)、履歴はブラウザのメモリにしか無く、ページを閉じれば消える。長さは 8 時間 (`VITE_HISTORY_HOURS` の既定) と 14,400 サンプル × WebSocket の送信間隔の短いほうで (`~/sparkDash/src/hooks/metricsStore.ts`)、送信間隔はいま 1 秒なので約 4 時間になる (コードからの計算で、実測していない)
   - サーバ側に残るのは GPU の使用率・温度・電力だけで、8 時間分を `config/gpu-history.json` に 5 分ごとに書く (`/api/sparks/<id>/gpu-history` で引ける)。journald に出るのは起動時の 1 回だけ (7 zone 分 7 行)。`collectd` / `netdata` / prometheus exporter の類は両ノードとも動いていない (2026-09-10)
   - したがって過去に遡った統計は取れない。必要になったら記録の仕組みを先に用意する
7. 停止と再起動はユーザーの作業を止める。打つ前に稼働中リクエストが無いことを確かめる (→「系統の切り替え」の手順 1)。OpenCode の実行中タスクが終わってから操作する
8. 推論サーバの自動復帰は系統で違う。restart policy は DeepSeek 系だけが `unless-stopped` で、他の 4 系統は両ノードとも `no` なので、ノードを再起動すると上がってこない (一覧は「系統の切り替え」の表。再起動で確かめたのは Qwen 系 2026-09-06、V4.1 EXL3 系 2026-09-15、GLM 系 2026-10-04。1017 系は 2026-10-22 に restart policy を見ただけで、再起動では確かめていない)。手で Qwen 系は `./start.sh --launch`、他の 3 系統は `./start.sh` を打ち直す (重みの同期はマーカーで省略されるので速い)。どの系統も停止スクリプトで止めた後はコンテナ自体が消えるので、再起動しても復帰しない。sparkDash は `always`、`docker` と (head の) `tailscaled` は enabled、RoCE は NetworkManager の autoconnect、クロック制限の 2 unit は enabled である (→ 制約 4・5)。cold boot での復帰は未確認なので、電源断の後は `docker ps` で確かめる
9. `~/spark-bench` は再作成手段が無い。dotfiles にも上流にも無い手書きのハーネスなので、head を作り直すと失われる
10. 5 系統の推論サーバは同時に起動できない。ポート 8888 と GPU を共有し、Qwen 側の `REQUIRE_IDLE_GPU=true`、V4.1 EXL3 側のメモリの事前検査、GLM 側のポートの事前検査、1017 側のメモリとポートの事前検査が明示的に拒否する。切り替えは必ず「相手を停止 → 起動」の順で行う (→「系統の切り替え」)
11. V4.1 EXL3 系と 1017 系はメモリの余裕が薄い。1017 系の配信中の head の `MemAvailable` は読み込み直後で 6〜7 GiB (2026-10-22 の実測で 6.3 GiB)、V4.1 EXL3 系はさらに薄く 5 GiB 前後 (画像入力を有効にした 2026-09-30 の実測で 4.8 GiB) である。長い prefill ほど空きが下がる (系統ごとの上流の報告は各系統ファイル)
    - 上流の報告では、GB10 は統合メモリが尽きるとエラーではなくノードごと固まり、ハード再起動まで戻らなかった。当方では起きていないので、兆候と復旧は未確認である。想定される兆候は、ssh も sparkDash も応答しないことと、worker だけが固まった場合に head の `/health` が応答しなくなることである。その場合は人が電源を入れ直す (sparkDash の Wake-on-LAN は電源断からの起動用で、固まったノードに効くかは未確認)
    - 配信中のノードで重い処理 (ダウンロード・ビルド・大きなファイルの展開) を流すときは上限を付ける。この掛け方は両系統に同じく当てはまり、他の系統の配信中にも使う。手段は 2 つあり、どちらでも上限が掛からない操作が 1 つある
      - 数時間かかるものはコンテナで流す。`docker run -d --memory <上限> …` で流すと dockerd が管理するので、ssh を切っても止まらない (GLM 系の重みの取得で 2026-10-03〜04 に使った)
      - ssh を開いたまま終わるものは `systemd-run --user --scope -p MemoryMax=<上限>` で流す。`ssh -n` 経由では `XDG_RUNTIME_DIR=/run/user/$(id -u)` を前置する (head では 2026-09-15 に効くことを確かめた。worker では未確認)。ユーザーの linger が無効 (`Linger=no`) なので、最後のセッションが閉じると user manager ごと scope が止まりうる (systemd の仕様からの推定で、確かめていない)
      - dockerd を通る操作 (`docker pull` / `docker load`) はどちらの手段でも上限が掛からない。配信を止めてから流す (例外は「sparkDash を更新する」の 279 MB のイメージ)
    - memguard の扱いは系統で違う。V4.1 EXL3 系は上流既定のまま無効にしていて、1017 系は既定で有効である (理由と OOM killer の設定は `dgx-spark/v41-exl3.md`「既知の制約 (V4.1 EXL3 系)」、閾値は `dgx-spark/1017.md`「構成」)

V4.1 EXL3 系の `/v1/responses` が tokenizer の content パーツ対応に依存する制約は、`dgx-spark/v41-exl3.md`「既知の制約 (V4.1 EXL3 系)」にある。

## 依拠する外部事実

「確認日」の列は、その行の確認を実機で行った日である。2026-09-06 の行は、本書が全体を実機で確かめた日の記録だけを持ち、行ごとに別の日の記録が無いものである。確認した日の記録がどこにも無いものは「記録なし」と書く。作業前に変わっていないか確かめる。いまはどのエンドポイントも無認証なので、確認コマンドにキーは要らない。1 系統だけの事実 (レシピの commit、上流既定からの差分、重みの検証、パッチの適用など) は各系統ファイルの「依拠する外部事実 (<系統>)」にある。

| 事実 | 確認コマンドと期待値 | 確認日 |
| --- | --- | --- |
| IP・インタフェース構成・MTU | `ssh -n spark-head 'ip -4 -o addr show; ip -o link show'` | 2026-09-06 |
| ドライバとカーネル | `ssh -n spark-head 'nvidia-smi --query-gpu=driver_version --format=csv,noheader; uname -r'` | 2026-09-06 |
| ディスクの空き | `ssh -n spark-head 'df -h /'` | 2026-10-22 |
| メモリの内訳 | `ssh -n spark-head 'grep -E "^Mem" /proc/meminfo; swapon --show; nvidia-smi --query-compute-apps=used_memory --format=csv,noheader'` | 「メモリの使われ方」の各列の日付 |
| 全モデルの重み | `ssh -n spark-head 'du -sh ~/.cache/huggingface/hub/models--* ~/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks/{model,engram-src} ~/dsv41-engram ~/.cache/huggingface/tensorfold-dsv41'` (worker の V4.1 EXL3 系は `~/.cache/dsv41-flash-exl3/{model,engram-src}` と `~/dsv41-engram`、1017 系は `~/.cache/dsv41-tensorfold/`) | 「重みの置き場所」の各行の日付 |
| 両ノードのイメージ | `ssh -n spark-head 'docker images --format "{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}"'` | 2026-09-06 (V4.1 EXL3 系は 2026-09-15、GLM 系は 2026-10-04) |
| worker 側の同じ確認 | 「worker に入る」のコマンドの `<worker で実行するコマンド>` に上記を入れる | — |
| 稼働中のモデル名と上限 | `curl http://spark-head.local:8888/v1/models`。GLM 系は `max_model_len` を返さないので `curl -s http://spark-head.local:8888/health` の `context_length` で見る | 2026-09-06 (GLM 系は 2026-10-04、1017 系は 2026-10-30) |
| 8888 が無認証のままか | `curl -s -o /dev/null -w "%{http_code}\n" http://spark-head.local:8888/v1/models` が 200 なら無認証。対照に `/v1/nope` が 404 を返すことも見る。陽性対照は認証を戻した後の 401 (「API キーの流れ」の手順 4) | 2026-09-06 (V4.1 EXL3 系は 2026-09-15、GLM 系は 2026-10-04) |
| 各種メトリクス | 「遅いと感じたときに疑う順序」の `curl` 1 本 (完全一致の grep)。TensorFold の 2 系統は同節の表の取り方 | 2026-09-06 (GLM 系は 2026-10-04) |
| 画像入力が通るか | 下のコードブロック 3 (モデル名を配信名に差し替える) | 2026-10-04 (GLM 系で陽性・陰性の両対照。DeepSeek 系は 2026-09-23、V4.1 EXL3 系は 2026-09-30 に別の画像で実測) |
| 配信中のモデルが受ける reasoning effort | `/v1/chat/completions` は `curl -s http://spark-head.local:8888/v1/chat/completions -H 'Content-Type: application/json' -d '{"model":"<配信名>","messages":[{"role":"user","content":"x"}],"reasoning_effort":"high","max_tokens":1}'`、`/v1/messages` は `curl -s http://spark-head.local:8888/v1/messages -H 'Content-Type: application/json' -H 'anthropic-version: 2023-06-01' -d '{"model":"<配信名>","messages":[{"role":"user","content":"x"}],"max_tokens":1,"output_config":{"effort":"high"}}'`、`/v1/responses` は `dgx-spark/v41-exl3.md`「依拠する外部事実 (V4.1 EXL3 系)」の `input_text` の curl のモデル名を配信名に替えて `"reasoning":{"effort":"<値>"}` を足す。語彙外の値で 400 になりエラー本文が受理語彙を名乗るのが陽性対照、受理される値で 200 が返るのが陰性対照 (常に 400 を返す壊れた検出でないことの確認)。値は「系統の切り替え」の effort の表 | 同表の日付 |
| CPU のトポロジと governor | 下のコードブロック 2 (worker は「worker に入る」経由)。cpu5 / cpu15 が 3900000、cpu0 / cpu10 が 2808000 なら「ハードウェアと OS」のコア割り当てどおり (unit の対象コアがこれに依存するので、別ロットで番号が入れ替わっていないかを見る) | 2026-09-10 |
| クロック制限の unit が有効か | `ssh -n spark-head 'systemctl is-active nv-gpu-clock-limit.service nv-cpu-clock-limit.service'` (worker は head 経由) が両方 `active`。`Type=oneshot` + `RemainAfterExit=yes` なので `active` のまま残る (この 2 行が無い素の oneshot は実行後 `inactive` になり、この判定は使えない)。`is-active` は unit が走ったことしか言わないので、実効値は次の 2 行で見る | 2026-09-10 |
| GPU クロック制限が実際に効いているか | `ssh -n spark-head 'nvidia-smi --query-gpu=clocks.max.sm,clocks.applications.graphics --format=csv'` と、負荷中の `nvidia-smi --query-gpu=clocks.sm --format=csv,noheader` が 2200 MHz 前後を超えないこと。ロックは unit が `active` のままでも外部要因で解けうるので、`is-active` を証跡にしない | 2026-09-10 |
| X925 の `scaling_max_freq` が下げてあるか | `ssh -n spark-head 'for c in 5 19; do echo "$(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_max_freq) $(cat /sys/devices/system/cpu/cpu$c/cpufreq/cpuinfo_max_freq) $(cat /sys/devices/system/cpu/cpu$c/cpufreq/max_perf)"; done'` (kHz、sudo 不要)。現状は `2808000 3900000 3900000` (cpu5) / `2808000 3900000 4004000` (cpu19) で、policy は下げたがハードウェアに届いていない状態 (意味は「既知の制約」5)。3 列目が 2808000 になって初めて本当の制限である。1 列目と 2 列目が同値なら unit が当たっていない | 2026-09-10 |
| X925 の実効クロック | `scaling_cur_freq` は要求値のエコーで、検査に使うと原理的に不合格になりえないので見ない。下のコードブロック 1 で busy なコアの `cpuinfo_avg_freq` を読む。陰性対照は busy な A725 で、要求値 2808000 と実効値がほぼ一致する。X925 が同時に 3.8〜3.9 GHz を返せば実効値を見られている。idle のコアは値が動かないか `Resource temporarily unavailable` を返すので、busy 判定と必ず組で使う | 2026-09-10 |
| 推論中に CPU を使っているのが誰か (「既知の制約」5 の根拠) | (a) 推論 1 本の前後で `/metrics` を取り、`vllm:iteration_tokens_total_count` の増分で所要秒を割る (「decode の分解 (2026-09-23)」とはカウンタと区間が違うので 63 ms と約 70 ms は直接比べない)。(b) 負荷中に `ssh -n spark-head 'nvidia-smi --query-gpu=utilization.gpu,clocks.sm,power.draw --format=csv'`。(c) 負荷の前後で `/proc/<tid>/stat` の 14・15 列 (user / sys、10 ms 単位) の増分。(d) 同区間の `/proc/<tid>/status` の `voluntary_ctxt_switches` の増分を (a) のステップ数で割る。tid は `ps -eLo tid,pcpu,comm` で `VLLM` を含むもの (`docker exec` は要らない)。値は (a) 63 ms / (b) 93% / (c) 3 本が 91〜99% / (d) 2〜5 回。スタックは追っていない (コンテナに `py-spy` が無く、`perf` / `strace` は sudo が要る) | 2026-09-10 |
| CPU / SoC の温度 | `ssh -n spark-head 'for z in 0 1 2 3 4 5 6; do awk "{printf \"zone%s=%.1f \", $z, \$1/1000}" /sys/class/thermal/thermal_zone$z/temp; done; echo'` (°C。読み方は「既知の制約」6)。履歴は残らないので、比べたいときは負荷の前後で自分で採る | 2026-09-10 |
| 再起動後の復帰条件 | `ssh -n spark-head 'docker inspect <コンテナ名> --format "{{.HostConfig.RestartPolicy.Name}}"'` (コンテナ名は冒頭の表。V4.1 EXL3 系の worker 側は `dsv41-exl3-worker`) | 2026-09-06 (V4.1 EXL3 系は 2026-09-15、GLM 系は 2026-10-04、1017 系は 2026-10-22) |
| opencode の版 | Mac 側で `opencode --version` が `opencode v2.0.22`。版が変わったら「OpenCode」の「v2.0.22 のソースで確認」とした項を確かめ直す | 2026-10-04 |
| Tailscale の参加状況 | Mac 側で `tailscale status` に `spark-head` の行がある (コマンドが無ければ `/Applications/Tailscale.app/Contents/MacOS/Tailscale status`) | 2026-10-03 |
| OpenCode の設定 | Mac 側で `python3 -c "import json;c=json.load(open('$HOME/.config/opencode/opencode.json'));print(c['policies'], c['providers']['spark']['settings']['baseURL'])"`。`spark` と `opencode` を allow する `policies` と `http://spark-head:8888/v1` が出れば合格 | 2026-10-30 |
| OpenCode の接続先 URL の 2 か所が一致しているか | dotfiles で `deno test --allow-env --allow-run --allow-read --allow-write agents/`。`spark-served_test.ts` が `providers.spark.settings.baseURL` とプラグインの `BASE_URL` を比べる | 2026-10-03 |
| OpenCode の設定が live edit か | Mac 側で `readlink -f ~/.config/opencode/opencode.json` と `readlink -f ~/.config/opencode/plugins/spark-served.ts`。dotfiles 配下を返せば live、`/nix/store/…` で終われば store コピー。`-f` を落とすと判定が壊れる。`mkOutOfStoreSymlink` は `~/.config/…` → `/nix/store/…-home-manager-files/…` → `…-hm_<名前>` → dotfiles の 3 段になるので、単 hop の `readlink` は live でも `/nix/store/…` を返し、常に「`drs` 待ち」と誤判定する (2026-10-03 に `opencode.json` で 3 段を実測) | 2026-10-03 |
| OpenCode の `cli.json` が symlink のままか | Mac 側で `test -L ~/.config/opencode/cli.json && readlink -f ~/.config/opencode/cli.json` が dotfiles 配下を返す。何も出なければ実ファイルになっている (直し方は「OpenCode」) | 2026-10-03 |
| OpenCode が配信中のモデルを選んでいるか | Mac 側で `opencode models` の `spark/` の行が `spark/<配信名>` の 1 行だけであること (配信名は `/v1/models` と比べる。打ち直しの規則と対照の欠如は「OpenCode」)。現在の `policies` は Zen を allow するので、`opencode/` で始まる Zen のモデルも一覧に並ぶ (2026-10-30 に 1017 系の配信中に確認) | 2026-10-30 |
| OpenCode の接続先への疎通 | Mac 側で `curl -fs -o /dev/null http://spark-head:8888/health` が exit 0 (Tailscale 側の経路を見る) | 2026-10-03 |
| OpenCode の effort 設定 | Mac 側で `python3 -c "import json;print({k:v.get('settings') for k,v in json.load(open('$HOME/.config/opencode/opencode.json'))['providers']['spark']['models'].items()})"`。先に `readlink -f` で実体が dotfiles に解決するか確かめる。送信本文の値は未実測 | 2026-10-30 |
| sparkDash の版と待ち受け | `ssh -n spark-head 'git -C ~/sparkDash describe --tags'` が `v2.32.0`、`curl -s http://spark-head:5555/api/health` の `authMode` が `open-remote` | 2026-10-12 |
| sparkDash の worker の表示名 | 「sparkDash の worker の表示名」の確認コマンドが `None` と配信名を出す | 2026-10-12 |
| L1 の再計測 | 「L1: サーバ単体 (2026-09-05)」の `bench.py` 2 本。前提は DeepSeek 系 (Vision-Exp) を配信中であることと、`/tmp/spark.key` を書き直してあること (無認証でも中身は何でもよいが、無いと `bench.py` が exit する) | 2026-09-05 |

表に入らないものは番号を付けてここに置く。いずれも複数行にわたるか、表のセルでは `|` をエスケープしないと書けないパイプを含む (エスケープした `\|` はコピーするとパイプにならない)。1 つのフェンスに 1 つの番号を振る。

```bash
# 1. 推論中に busy なコアと、そのコアの実効クロック (ノード上で実行)
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
# 2. CPU のトポロジと各コアの cpufreq (worker は「worker に入る」経由で同じものを打つ)
ssh -n spark-head 'lscpu | grep -E "Model name|^CPU\(s\)"; for c in 0 5 10 15; do echo "cpu$c $(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_driver) $(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_governor) $(cat /sys/devices/system/cpu/cpu$c/cpufreq/cpuinfo_max_freq)"; done'
```

```bash
# 3. 画像入力が通るか。緑一色の 8x8 PNG を data URL で渡し、答えに「緑」が含まれれば exit 0
#    M を配信名に差し替える。陰性対照は画像を外して同じ質問を送ること (「緑」以外を答えて exit 1 になる)。
#    2026-10-04 に GLM 系で、画像ありが exit 0、画像なしが「赤色」で exit 1 だった。赤一色の画像は
#    画像なしでも「赤」と答えたので対照にならない
M=GLM-5.3-Flash-EXL3
B=iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEElEQVR4nGNgOMCAHQ0tCQDB1jAB4smq5AAAAABJRU5ErkJggg==
curl -s http://spark-head.local:8888/v1/chat/completions -H 'Content-Type: application/json' -d "{\"model\":\"$M\",\"max_tokens\":512,\"temperature\":0,\"chat_template_kwargs\":{\"enable_thinking\":false},\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"image_url\",\"image_url\":{\"url\":\"data:image/png;base64,$B\"}},{\"type\":\"text\",\"text\":\"この画像は何色ですか。色の名前を 1 語だけ日本語で答えてください。\"}]}]}" \
  | python3 -c 'import json,sys; c=json.load(sys.stdin)["choices"][0]["message"]["content"].strip(); print(repr(c)); sys.exit(0 if "緑" in c else 1)'
```
