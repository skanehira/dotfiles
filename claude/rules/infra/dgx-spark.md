---
# 常駐読み込みさせないためのマーカー (このパスにマッチするファイルは存在しない)。
# 本ファイルは必要になったときに Read で参照する。
paths:
  - "__read-on-demand-only__"
---

# DGX Spark 2 台構成 (自宅のローカル LLM クラスタ)

- 種別: 環境リファレンス
- 対象読者: 別セッション・別マシンで作業する Claude
- 最終確認: 2026-09-05

自宅に NVIDIA DGX Spark (GB10) が 2 台あり、vLLM の TP=2 (tensor parallel、2 台に重みを分割する並列方式) で DeepSeek の LLM を常時サービングしている。Mac の Claude Code からバックエンドとして使える。

**dotfiles リポジトリの所在は `~/dev/github.com/skanehira/dotfiles` である。** 本書でリポジトリ相対で書くパスはすべてここを基点とする。

## 用語・成果物一覧

| 名前 | 意味 | 定義箇所 | 生成者 | 消費者 |
| --- | --- | --- | --- | --- |
| head / worker | TP=2 の rank 0 / rank 1。head だけが HTTP API を持ち、worker は headless | `.env.dspark` の `WORKER_HOST` | 人 (初期構築) | 起動スクリプト |
| RoCE | RDMA over Converged Ethernet。QSFP ポート上でノード間の NCCL 集団通信を運ぶ | `.env.dspark` の `NCCL_IB_HCA` | NetworkManager の接続 `roce` / `roce2` | vLLM (NCCL) |
| DSpark | チェックポイント内蔵の投機デコード。draft 用の別モデルを持たない | vLLM の CLI フラグ `--speculative-config` | レシピの compose | vLLM |
| `nvfp4_ds_mla` | MLA (multi-head latent attention) の KV キャッシュを 4bit で保持する形式 | vLLM の CLI フラグ `--kv-cache-dtype` | レシピの compose | vLLM |
| TTFT | time to first token。送信から最初のトークンが返るまでの時間。ほぼ prefill の所要時間 | 本表 | 計測スクリプト | 「実測値」節 |
| `ccsp` | Claude Code のバックエンドを本クラスタへ向ける zsh 関数 | `zsh/functions/claude-deepseek.zsh` | dotfiles | 人 |
| `ccds` | 同じく DeepSeek 本家 API へ向ける zsh 関数。`ccsp` と認証トークンを共有する | 同上 | dotfiles | 人 |
| `drs` / `hms` | dotfiles の Nix 設定を適用する zsh alias (mac が `drs`、Linux が `hms`) | `nix/modules/home/zsh.nix` | dotfiles | 人 |
| `.env.dspark` | レシピの設定を集約した 1 枚。git 管理外 (`.gitignore` 済み) | head の `~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark/` | 人 (`.env.dspark.example` から複製) | 起動・停止・検証スクリプト |
| `docker-compose.override.yml` | sparkDash のポーリング間隔などの上書き。未追跡 | head の `~/sparkDash/` | 人 | `docker compose` |
| `settings.deepseek-spark.json` | Claude Code 側のモデル名とコンテキスト上限 | `claude/settings.deepseek-spark.json` | dotfiles | `ccsp` が `--settings` で渡す |
| 上流 | レシピの配布元 [MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark](https://github.com/MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark) | — | — | — |

## ハードウェアと OS

2 台とも同一構成である。

| 項目 | 値 |
| --- | --- |
| GPU | NVIDIA GB10 (CPU と共有する統合メモリ 128 GB。カタログ値で、`free` は 121 GiB を返す) |
| OS | Ubuntu 24.04.4 LTS / aarch64 |
| カーネル | `6.17.0-1032-nvidia` |
| ドライバ | `580.173.02` |
| ディスク | 3.7 TB (空き 3.3 TB) |

## 接続する

自宅 LAN では SSH エイリアスが使える。

```bash
ssh spark-head
ssh spark-worker
```

`~/.ssh/config` は **dotfiles 管理外の実ファイル**なので、別マシンでは次を自分で書く。鍵 `~/.ssh/spark-head` / `~/.ssh/spark-worker` も既存機からコピーするか、新規生成して `ssh-copy-id` で登録する。

```
Host spark-head
	User skanehira
	Hostname spark-head.local
	IdentityFile ~/.ssh/spark-head
Host spark-worker
	User skanehira
	Hostname spark-worker.local
	IdentityFile ~/.ssh/spark-worker
```

**この 2 つは自宅 LAN 専用である。** `.local` は mDNS 名で、Tailscale 越しには解決しない。出先からは次を使う。

```bash
ssh -i ~/.ssh/spark-head skanehira@spark-head              # head (Tailscale の MagicDNS 名)
ssh -J skanehira@spark-head -i ~/.ssh/spark-worker \
    skanehira@spark-worker.local                           # worker は head を踏み台にする
```

踏み台越しでは**最終ホップの名前解決を head が行う**ため、Mac から引けない `.local` 名をそのまま宛先に書ける。逆に worker の IP を直接宛先にすると Mac の `known_hosts` に無く `Host key verification failed` になる。

### ネットワーク

| 用途 | netdev 名 | RDMA デバイス名 | 割り当て | MTU |
| --- | --- | --- | --- | --- |
| LAN (WiFi) | `wlP9s9` | — | 両ノード。mDNS 名 `spark-head.local` / `spark-worker.local` | 1500 |
| RoCE 1 本目 | `enp1s0f1np1` | `rocep1s0f1` | 専用の /24。head が `.1`、worker が `.2` | 9000 |
| RoCE 2 本目 | `enP2p1s0f1np1` | `roceP2p1s0f1` | 別の /24。head が `.1`、worker が `.2` | 9000 |
| Tailscale | `tailscale0` | — | head のみ。MagicDNS 名 `spark-head` | — |

**具体的な IP アドレスは本書に書かない。** このリポジトリは公開されており、アドレスを認証の無いサービス (後述の sparkDash) の説明と並べる利点が無いためである。必要になったら「依拠する外部事実」節の引き方で調べる。日常の操作はすべて名前 (`spark-head` / `spark-worker.local`) で足りる。

**RoCE が 2 本あるのは GB10 の仕様である。** QSFP ポートが 2 つの仮想 NIC (各 PCIe Gen5 x4) として見えるため、`.env.dspark` の `NCCL_IB_HCA` に `rocep1s0f1,roceP2p1s0f1` と両方を並べる。**2 本は別サブネットに置き、MTU 9000 にする。** 片方に IP が無い、または同一サブネットに置くと vLLM が `no usable RoCEv2 GID` で起動に失敗する。IP と MTU は NetworkManager の接続 `roce` / `roce2` (autoconnect 有効) で永続化してあり、再起動後も残る。

LAN は WiFi である。有線ではないので、巨大なプロンプトの転送は電波状況の影響を受ける。

## 動いているもの

| サービス | 自宅 LAN | 出先 (Tailscale) | 認証 |
| --- | --- | --- | --- |
| vLLM | `http://spark-head.local:8888` | `http://spark-head:8888` | Bearer トークン |
| sparkDash | `http://spark-head.local:5555` | `http://spark-head:5555` | **なし** |

vLLM は `/health` と `/metrics` が無認証、`/v1/*` だけが Bearer を要求する。`/health` は `ccsp` の到達判定が、`/metrics` は sparkDash がポーリングして消費する。

### API キーの流れ

正本は 1Password の `op://Personal/DGX Spark vLLM API Key/credential` である。head の `.env.dspark` の `VLLM_API_KEY` に同じ値が入っており、**サーバ側はこちらを見る**。

```
1Password ──(ccsp が op read)──> ANTHROPIC_AUTH_TOKEN ──(Authorization: Bearer)──> vLLM
                                        └─(ccsp off で unset)
```

- **Mac から Claude Code で使う分には手動の export は不要である。** `ccsp` が 1Password CLI (`op`) で読んで環境変数に入れる。事前に `op` へサインインしておく
- **手で `curl` を叩くときだけ自分で読む。** 作業ファイルに書き出したら使い終わりに必ず削除する
- **キーを変えるときは 1Password と `.env.dspark` の両方を更新し、`stop` → `start` で作り直す。** 片方だけ変えると 401 になる
- **`.env.dspark` の控えを作ったら使い終わりに消す。** `.gitignore` が拾うのは `.env.dspark` そのものだけなので、`.env.dspark.bak` のような名前は追跡対象に入りうる。キー行ごと公開リポジトリの clone にステージされる

sparkDash は head の `~/sparkDash` に clone した [MiaAI-Lab/sparkDash](https://github.com/MiaAI-Lab/sparkDash) で、監視に加えて SSH 操作と Wake-on-LAN の機能を持つ Web UI である。同梱の `docker-compose.yml` は編集せず、上書きは未追跡の `docker-compose.override.yml` に置く (`git pull` との衝突を避けるため)。反映・停止・更新は `~/sparkDash` で `docker compose up -d` / `down` / `pull` を打つ。**認証が無く tailnet (Tailscale ネットワーク) の全端末から SSH 操作と Wake-on-LAN が可能なので、ポート 5555 を信頼できないネットワークへ出さない。**

### サービングの構成

レシピ名は DSpark だが、載せているチェックポイントは Vision-Exp である。

| 項目 | 値 |
| --- | --- |
| チェックポイント | `deepseek-ai/DeepSeek-V4-Flash-Vision-Exp` @ `86f746b36186f0e567729a5c06a8c918caba82a9` |
| API 上のモデル名 | `deepseek-v4-flash-vision-exp` |
| コンテキスト上限 | サーバ 1,048,576 トークン / Claude Code からは 524,288 (`settings.deepseek-spark.json` の `CLAUDE_CODE_MAX_CONTEXT_TOKENS`) |
| 同時リクエスト上限 | 6 リクエスト (`MAX_NUM_SEQS`)。超過分はエラーにならずキューで待つ |
| 投機デコード | DSpark、draft 6 トークン (`MTP_NUM_TOKENS`) |
| KV キャッシュ | `nvfp4_ds_mla` |
| 既定の reasoning | `DEFAULT_THINKING=low` (取りうる値: `off` / `low` / `high` / `max`。リクエスト単位の指定が優先する) |
| コンテナイメージ | `ghcr.io/anemll/dspark-vllm-gx10:0.1.1@sha256:a83948492cf13df455170fb42885f5ef4db54fefe0feff0f841ecbff464ac9d8` (DSpark ランタイムの配布元 Anemll) |

重みは両ノードの `~/.cache/huggingface/hub/` に 157 GiB 前後ある (`du -h` で head 158G / worker 157G)。worker は NFS ではなくローカルコピーを持つ。

## 起動と停止

head の `~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark` が上流レシピの clone である。**head で起動すると `.env.dspark` を worker へ SSH で配り直して両ランクを立ち上げるので、worker で直接コマンドを打つ必要はない。** head から worker へは `~/.ssh/id_ed25519` で `.env.dspark` の `WORKER_HOST` (RoCE 側のアドレス) に入る。

```bash
ssh spark-head
cd ~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark
./validate-dspark-config.sh            # 起動せずに解決値だけ確認する
./start-deepseek-v4-flash-dspark.sh    # 両ランク起動。約 3 分
./smoke-deepseek-v4-flash-dspark.sh    # 疎通確認
./status-deepseek-v4-flash-dspark.sh
./logs-deepseek-v4-flash-dspark.sh
./stop-deepseek-v4-flash-dspark.sh
```

**設定を変えたら `docker compose restart` を使わず、`stop` → `start` で作り直す。** 起動時にコンテナ内の vLLM へ多数のパッチを当てる構成なので、restart では古いバイト列が残る。

正常稼働の判定は 2 段で行う。

```bash
curl -fs http://spark-head.local:8888/health     # exit 0 なら API は生きている
./smoke-deepseek-v4-flash-dspark.sh              # 実際に生成が通る
```

`.env.dspark` の既定値は `.env.dspark.example` にある。上流の配布既定から変更しているのは次の 3 つで、いずれも 0 が無効・1 が有効である。

| キー | 値 | 採用根拠 | 自環境での効果 |
| --- | --- | --- | --- |
| `DSPARK_MAX_INFLIGHT_PREFILLS` | 2 | 上流の A/B (`docs/CLAUDE/ab-results-2026-09-03.md`) | 4 並列時の TTFT のばらつきが 11.9 秒 → 7.7 秒。単一利用時の初動は 4.9 秒 → 7.2 秒に悪化。集約スループットは有意差なし |
| `DSPARK_ENABLE_SP_INDEXER` | 1 | 上流の最終構成に追従 | 自環境では未計測 |
| `DSPARK_ENABLE_DEEPGEMM_SM121_ALIAS` | 1 | 上流の最終構成に追従 | 自環境では未計測 |

## Mac から Claude Code で使う

```bash
ccsp        # 到達する方を自動選択 (LAN → Tailscale の順に /health をプローブ)
ccsp lan    # 自宅 LAN を強制
ccsp ts     # Tailscale を強制
ccsp off    # Anthropic に戻す
claude      # ccsp が張った alias 経由で起動する
```

実体は `zsh/functions/claude-deepseek.zsh` の `ccsp` と `claude/settings.deepseek-spark.json` である。前提は 2 つで、`op` にサインイン済みであることと、dotfiles が `$GHQ_ROOT/github.com/skanehira/dotfiles` (既定で `~/dev/...`) にあることである。`ccsp ts` は Mac が同じ tailnet に参加している必要がある。

押さえるべき点が 4 つある。

- **別のバックエンドから切り替えるときは先に `off` を打つ。** `ccds` と `ccsp` は `ANTHROPIC_AUTH_TOKEN` を共有するため、残っていると使い回されて 401 になる。401 が出たらまず残留トークンを疑う
- **`ANTHROPIC_BASE_URL` を settings JSON に書かない。** settings の `env` はシェルの export を無条件に上書きするため、JSON に書くと出先での切り替えが効かなくなる。接続先は `ccsp` が export する
- **`claude` は `ccsp` を打ったシェルで起動する。** export は子プロセスへ継承されるが alias は継承されない。サブシェルから素の `claude` を打つと `--settings` が効かず、本体の設定にあるモデル名を vLLM へ送って `model not found` になる
- **2 つの設定ファイルで反映経路が違う。** `settings.deepseek-spark.json` は `ccsp` が dotfiles を直参照するので編集すれば次の `claude` 起動から効く。`zsh/functions/*.zsh` は Nix store 経由で配られるので `drs` を実行し、さらに新しいシェルを開く (既存シェルには旧定義が残る)

## 実測値

2026-09-05 に計測。GPU クロック 2200 MHz 制限あり、リクエストで reasoning を off にして出力トークン数を固定した条件である。

| 条件 | 値 |
| --- | --- |
| 単一ストリームの decode | 61.7 tok/s (範囲 61.5〜62.1、n=5) |
| 4 並列・6,276 トークンのプロンプト、集約 | 13.8 tok/s (範囲 12.8〜14.9、n=6) |
| 同、各ストリームの TTFT | 7.1 / 8.9 / 13.9 / 14.8 秒 |
| クロック制限を外したときの差 | decode +1.3% (n=5)、最悪 TTFT 約 +2%。集約は範囲が重なり有意差なし (n=6) |
| GPU 温度 | 制限あり 52〜58 °C / 制限なし 60〜65 °C |

単一 decode が 55 tok/s を下回る、または 4 並列の最悪 TTFT が 20 秒を超えたら異常を疑う。再現手順は「依拠する外部事実」の計測行にある。

**この構成の律速は decode ではなく prefill である。** 実負荷での累計プロンプト対生成トークン比は 75:1 で、4 並列時の TTFT が階段状に並ぶのは prefill が 2 本ずつしか重ならないため (性能ノブ表の `DSPARK_MAX_INFLIGHT_PREFILLS=2` による)。decode を速くする施策は体感に効きにくい。

投機デコードの受理率は実負荷 (reasoning on) で 33%、6 draft 中 2.0 トークンである。リクエストで reasoning を off にすると 59% まで上がる。reasoning の設定は現状変更しない方針である。

## 障害時

| 症状 | 確認 | よくある原因 |
| --- | --- | --- |
| 応答しない | `curl -fs http://spark-head.local:8888/health` | コンテナは生きていて過負荷。`/metrics` の `num_requests_waiting` を見る |
| コンテナが無い | 両ノードで `docker ps --filter name=vllm-dspark` | `stop` で止めたまま。`start` し直す |
| 起動に失敗する | `./logs-deepseek-v4-flash-dspark.sh` | `no usable RoCEv2 GID` は RoCE 2 本目の IP か MTU。`model not found` はクライアント側のモデル名 |
| 3 分を過ぎても上がらない | 両ノードの `docker logs` | worker 側だけ落ちていることがある。両ランクを見る |

## 既知の制約

1. **Spark には passwordless sudo が無い。** `/etc/sudoers.d/` は README のみである。`nvidia-smi --lock-gpu-clocks` や systemd の操作など sudo が要る作業は Claude からは実行できないので、コマンドを提示して人間に実行してもらう (パスワードは `skanehira` の Ubuntu ログインパスワードで、本書には保管しない)。Mac の Touch ID による sudo は Linux ノードには効かない
2. **worker は Tailscale に参加していない。** `tailscaled` は head だけで有効である。出先から worker を見るには「接続する」節の踏み台コマンドを使う
3. **GPU クロックを 2200 MHz に制限している。** 両ノードの `/etc/systemd/system/nv-gpu-clock-limit.service` (手で配置した unit、enabled + active) が起動時に `nvidia-smi --lock-gpu-clocks=0,2200` を実行する。解除しても実効性能は「実測値」節のとおり 1〜2% しか上がらず温度が 7 °C 以上上がるので、制限は維持する
4. **停止と再起動はユーザーの作業を止める。** 打つ前に `curl -s http://spark-head.local:8888/metrics | grep vllm:num_requests_running` で稼働中リクエストの有無を確認し、Mac 側では先に `ccsp off` で退避する
5. **ノード再起動後は原則として自動復帰する。** vLLM コンテナの restart policy は `unless-stopped`、sparkDash は `always`、`docker` と (head の) `tailscaled` は enabled、RoCE は NetworkManager の autoconnect である。ただし `stop` スクリプトで止めた後は再起動しても上がらない。**cold boot での復帰は未確認なので、電源断の後は `./status-deepseek-v4-flash-dspark.sh` で確かめる**

## 依拠する外部事実

いずれも 2026-09-05 に実機で確認した。作業前に変わっていないか確かめる。認証が要る確認は先にキーを取る。

```bash
KEY="$(op read 'op://Personal/DGX Spark vLLM API Key/credential')"
```

| 事実 | 確認コマンド |
| --- | --- |
| IP・インタフェース構成・MTU | `ssh spark-head 'ip -4 -o addr show; ip link show enP2p1s0f1np1'` |
| ドライバとカーネル | `ssh spark-head 'nvidia-smi --query-gpu=driver_version --format=csv,noheader; uname -r'` |
| ディスクの空き | `ssh spark-head 'df -h /'` |
| サービングの設定値 | `ssh spark-head 'cd ~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark && ./validate-dspark-config.sh'` |
| 稼働中のモデル名と上限 | `curl -H "Authorization: Bearer $KEY" http://spark-head.local:8888/v1/models` |
| プロンプト対生成トークン比 | `curl -s http://spark-head.local:8888/metrics \| grep -E 'request_(prompt\|generation)_tokens_sum'` |
| 投機デコードの受理率 | `curl -s http://spark-head.local:8888/metrics \| grep spec_decode_num_.*_total` |
| クロック制限の有効性 | `for h in spark-head spark-worker; do ssh $h 'systemctl is-active nv-gpu-clock-limit.service'; done` |
| 再起動後の復帰条件 | `ssh spark-head 'docker inspect deepseek-v4-flash-vllm-dspark-1 --format "{{.HostConfig.RestartPolicy.Name}}"'` |
| Tailscale の参加状況 | Mac 側で `tailscale status` |
| スループットの再計測 | 単一 decode は `/v1/chat/completions` に `chat_template_kwargs={"thinking":false}` で固定プロンプトを 5 回。4 並列は 6,300 トークン前後のプロンプトを一意の salt つきで 4 本同時に投げ、TTFT と集約 tok/s を採る |
