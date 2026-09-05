---
# 常駐読み込みさせないためのマーカー (このパスにマッチするファイルは存在しない)。
# 本ファイルは必要になったときに Read で参照する。
paths:
  - "__read-on-demand-only__"
---

# DGX Spark 2 台構成 (自宅のローカル LLM クラスタ)

- 種別: 環境リファレンス
- 対象読者: 別セッション・別マシンで作業する Claude
- 最終確認: 2026-09-06 (性能値のみ 2026-09-05。表ごとに計測日を書いてある)

自宅に NVIDIA DGX Spark (GB10) が 2 台あり、vLLM の TP=2 (tensor parallel、2 台に重みを分割する並列方式) で DeepSeek の LLM を常時サービングしている。Mac の Claude Code (`ccsp`) と OpenCode (`ocsp`) の両方からバックエンドとして使える。

**dotfiles リポジトリの所在は `~/dev/github.com/skanehira/dotfiles` である。** 本書でリポジトリ相対で書くパスはすべてここを基点とする。

## 用語・成果物一覧

「—」は該当なしを意味する。

| 名前 | 意味 | 定義箇所 | 生成者 | 消費者 |
| --- | --- | --- | --- | --- |
| head / worker | TP=2 の rank 0 / rank 1。head だけが HTTP API を持ち、worker は headless | `.env.dspark` の `WORKER_HOST` | 人 (初期構築) | 起動スクリプト |
| レシピ | 上流が配布する compose + シェルスクリプト一式 | head の `~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark/` | 上流 (`git clone`) | 人 |
| Vision-Exp | `deepseek-ai/DeepSeek-V4-Flash-Vision-Exp` の略。画像入力が使える。**現在の配信モデル** | 「サービングの構成」 | 上流のチェックポイント | vLLM |
| 0731 | `deepseek-ai/DeepSeek-V4-Flash-0731` の略。テキスト専用。重みは配置済みで待機 | 「モデルの追加と切り替え」 | 同上 | vLLM |
| RoCE | RDMA over Converged Ethernet。QSFP ポート上でノード間の NCCL 集団通信を運ぶ | `.env.dspark` の `NCCL_IB_HCA` | NetworkManager の接続 `roce` / `roce2` | vLLM (NCCL) |
| NCCL | NVIDIA Collective Communications Library。TP=2 のランク間通信を担う | 本表 | — | vLLM |
| DSpark | チェックポイント内蔵の投機デコード。draft 用の別モデルを持たない | vLLM の CLI フラグ `--speculative-config` | レシピの compose | vLLM |
| MTP | multi-token prediction。DSpark が 1 ステップで出す draft トークン数 (`MTP_NUM_TOKENS`) | `.env.dspark` | 人 | vLLM |
| `nvfp4_ds_mla` | MLA (multi-head latent attention) の KV キャッシュを 4bit で保持する形式 | vLLM の CLI フラグ `--kv-cache-dtype` | レシピの compose | vLLM |
| TTFT | time to first token。送信から最初のトークンが返るまでの時間。ほぼ prefill の所要時間 | 本表 | `~/spark-bench/bench.py` | 「L1」表 |
| 受理率 | 投機デコードが出した draft トークンのうち採用された割合。decode 速度をほぼ決める | 本表 | vLLM の `/metrics` | 「L2 / L3」表・「疑う順序」4 |
| L1 / L2 / L3 | 計測の層。L1 = サーバを直叩き (クライアント無し) / L2 = Claude Code 経由 / L3 = OpenCode 経由 | 本表 | `bench.py` (L1) / `snap.py` (L2・L3) | 「実測値」節 |
| `ccsp` | Claude Code を本クラスタに向けて**起動する**ところまで行う zsh 関数 | `zsh/functions/claude-deepseek.zsh` | dotfiles | 人 |
| `ccds` | 同じく DeepSeek 本家 API へ向ける zsh 関数。`ccsp` と環境変数 `ANTHROPIC_AUTH_TOKEN` を共有する (入る値は別) | 同上 | dotfiles | 人 |
| `CCSP_LAN_HOST` | `ccsp` の LAN 側ホスト名を上書きするシェル変数。`CCSP_LAN_HOST=<IP> ccsp` と前置きしても export しても効く | 同上 | 人 | `ccsp` |
| `ocsp` | OpenCode を本クラスタに向けて起動する zsh 関数。1Password も alias も使わない | `zsh/functions/opencode-spark.zsh` | dotfiles | 人 |
| `OCSP_MODEL` | `ocsp` が使うモデル名を保持するシェル変数。`ocsp model` が書き換える。**新しいシェルでは Vision-Exp に戻る** | 同上 | `ocsp model` | `ocsp` |
| `settings.deepseek-spark.json` | Claude Code 側のモデル名・コンテキスト上限・無効化プラグイン | `claude/settings.deepseek-spark.json` | dotfiles | `ccsp` が `--settings` で渡す |
| `opencode.json` | OpenCode の `provider.spark` (接続先とキーの読み出し先)。dotfiles 管理。`~/.config/opencode/` の他のファイル (`tui.json` / `skills/` / `node_modules`) は opencode 自身のもの | `opencode/opencode.json` | dotfiles (`nix/modules/home/opencode.nix` が symlink) | `opencode` 本体 / `ocsp status` |
| `spark-base-url` | Spark の baseURL の実値。opencode の `{file:…}` 置換が読む。**IP を含むので dotfiles には入れない** | Mac の `~/.config/opencode/spark-base-url` | 人 (`printf` で書き出す) | `opencode` 本体 / `ocsp` |
| `/tmp/spark.key` | vLLM の Bearer トークンを平文で置いた作業ファイル。**Mac と head に別々に要る。再起動で消える** | Mac と head の `/tmp/spark.key` | 人 (1Password から書き出す) | `opencode` (Mac) / `bench.py` (head) |
| `drs` | dotfiles の Nix 設定を Mac に適用する zsh alias | `nix/modules/home/zsh.nix` | dotfiles | 人 |
| `.env.dspark` | レシピの設定を集約した 1 枚。git 管理外 (`.gitignore` 済み)。**現行と `~/dspark-0731` に 1 枚ずつある** | 各レシピディレクトリ | 人 (`.env.dspark.example` から複製) | 起動・停止・検証スクリプト |
| `PROJECT_NAME` | `docker compose` のプロジェクト名。コンテナ名 `deepseek-v4-flash-vllm-dspark-1` の接頭辞になる | 起動スクリプトの既定値 (`.env.dspark` のキーではない) | 起動スクリプト | `docker compose` |
| `~/dspark-0731` | 0731 を配信できた頃のレシピを固定した git worktree (detached `70a7cc4`) | head の `~/dspark-0731/` | 人 (`git worktree add ~/dspark-0731 --detach 70a7cc4`) | 0731 用の起動スクリプト |
| `~/spark-bench` | 計測ハーネス一式 (主に `bench.py` / `snap.py` / `pc_probe.py` / `results/`)。**dotfiles 管理外で再作成手段が無い** | head の `~/spark-bench/` | 人 | 人 / Claude |
| `utility-spark-model-fetch` | 新しい重みを head で 1 回落として worker へ rsync するスキル。`scripts/verify_shards.py` を同梱する (head 上の同名ファイルは配布済みコピーで、正本はこちら) | `claude/skills/utility-spark-model-fetch/SKILL.md` | dotfiles | Claude |
| sparkDash | 監視・SSH 操作・Wake-on-LAN を持つ Web UI。**認証が無い** | head の `~/sparkDash/` | 上流 (`git clone`) | 人 (ブラウザ) |
| `workerLabel` | sparkDash が worker 行に表示するモデル名。**手書きの静的文字列で、実機を見ていない** | head の `~/sparkDash/config/sparks.json` | 人 | sparkDash の UI |
| `docker-compose.override.yml` | sparkDash のポーリング間隔などの上書き。未追跡 | head の `~/sparkDash/` | 人 | `docker compose` |
| `security-guidance` | Claude Code の公式プラグイン。Stop hook でレビュー用モデルを呼ぶ。`enabledPlugins` の完全キーは `security-guidance@claude-plugins-official` | `~/.claude/plugins/cache/claude-plugins-official/security-guidance/` | プラグイン marketplace | `settings.*.json` の `enabledPlugins` |
| 上流 | レシピの配布元 [MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark](https://github.com/MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark) | — | — | — |

## ハードウェアと OS

2 台とも同一構成である。

| 項目 | 値 |
| --- | --- |
| GPU | NVIDIA GB10 (CPU と共有する統合メモリ 128 GB。カタログ値で、`/proc/meminfo` は 121.7 GiB を返す) |
| OS | Ubuntu 24.04.4 LTS / aarch64 |
| カーネル | `6.17.0-1032-nvidia` |
| ドライバ | `580.173.02` |
| ディスク | 3.7 TB (使用 369 GB / 空き 3.2 TB。重み 2 モデル分を置いた状態) |

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

`ccsp` と `ocsp` はこの読み替えを自分で行う (`ccsp` は `/health` をプローブして LAN → Tailscale の順に選ぶ)。

### worker に入る

`known_hosts` に `spark-worker.local` の鍵があれば Mac から直接入れる。無いマシン (および鍵を足せない場面) では head の中から入る。head の `known_hosts` には RoCE 側アドレスの鍵が入っている。

```bash
ssh -n spark-head 'W=$(grep -E "^WORKER_HOST=" ~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark/.env.dspark | cut -d= -f2); ssh -n -o BatchMode=yes "$W" "<worker で実行するコマンド>"'
```

外側がシングルクォートなので `$W` は head 側で展開される。`WORKER_HOST` の値はクォートされていないので `cut -d= -f2` で足りる。

**入れ子の `ssh` には `-n` を付ける。** 付けずに外側をヒアドキュメントや `bash -s` で流し込むと、内側の ssh が残りのスクリプトを標準入力ごと飲み込み、以降のコマンドが実行されないまま正常終了する (出力が途中で切れていたらこれを疑う)。

### ネットワーク

| 用途 | netdev 名 | RDMA デバイス名 | 割り当て | MTU |
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
| vLLM | `http://spark-head.local:8888` | `http://spark-head:8888` | Bearer トークン |
| sparkDash | `http://spark-head.local:5555` | `http://spark-head:5555` | **なし** |

vLLM は `/health` と `/metrics` が無認証、`/v1/*` だけが Bearer を要求する。`/health` は `ccsp` / `ocsp` の到達判定が、`/metrics` は sparkDash と `~/spark-bench/snap.py` がポーリングして消費する。

sparkDash は head の `~/sparkDash` に clone した [MiaAI-Lab/sparkDash](https://github.com/MiaAI-Lab/sparkDash) である。同梱の `docker-compose.yml` は編集せず、上書きは未追跡の `docker-compose.override.yml` に置く (`git pull` との衝突を避けるため)。反映・停止・更新は `~/sparkDash` で `docker compose up -d` / `down` / `pull` を打つ。**認証が無く tailnet の全端末から SSH 操作と Wake-on-LAN が可能なので、ポート 5555 を信頼できないネットワークへ出さない。**

### API キーの流れ

vLLM の Bearer トークンの正本は 1Password の `op://Personal/DGX Spark vLLM API Key/credential` である。**サーバ側は `.env.dspark` の `VLLM_API_KEY` を見る。** クライアントへの届き方が 3 経路ある。

```
1Password ─(ccsp が op read)──> ANTHROPIC_AUTH_TOKEN ───┐
                                    └─(ccsp off で unset) │
1Password ─(人が書き出す)──> Mac の /tmp/spark.key ────┤ Authorization: Bearer
                              └(opencode.json の {file:…})│          ↓
1Password ─(人が書き出す)──> head の /tmp/spark.key ───┘        vLLM
                              └(bench.py --key-file)      (.env.dspark の
                                                           VLLM_API_KEY と照合)
```

- **Claude Code で使う分には手動の export は不要である。** `ccsp` が 1Password CLI (`op`) で読んで環境変数に入れる。事前に `op` へサインインしておく
- **OpenCode は Mac の `/tmp/spark.key` を読む。** OpenCode は Anthropic 互換経路を持たない (vLLM は `Authorization: Bearer` しか受け付けないが OpenCode の Anthropic プロバイダは `x-api-key` で送る) ため、OpenAI 互換プロバイダとして繋ぎ、キーをファイルから読ませる
- **`bench.py` は head の `/tmp/spark.key` を読む。** これは Mac のものとは別ファイルで、無ければ次で置く。`/tmp` は再起動で消えるので、両方とも「無くなっていたら書き直す」

```bash
op read 'op://Personal/DGX Spark vLLM API Key/credential' > /tmp/spark.key && chmod 600 /tmp/spark.key
op read 'op://Personal/DGX Spark vLLM API Key/credential' | ssh spark-head 'cat > /tmp/spark.key && chmod 600 /tmp/spark.key'
```

- **キーを変えるときは 1Password と `.env.dspark` を更新して `stop` → `start` で作り直す。`.env.dspark` は現行と `~/dspark-0731` に 1 枚ずつあり、両方が `VLLM_API_KEY` を持つ。** 片方だけ直すと、モデルを切り替えた瞬間に 401 になる
- **`.env.dspark` の控えを作ったら使い終わりに消す。** `.gitignore` が拾うのは `.env.dspark` そのものだけなので、`.env.dspark.bak` のような名前は追跡対象に入りうる。キー行ごと公開リポジトリの clone にステージされる

### サービングの構成

レシピ名は DSpark だが、載せているチェックポイントは Vision-Exp である。値の出所はすべて `.env.dspark` (最後の 2 行を除く)。

| 項目 | 値 |
| --- | --- |
| チェックポイント (`DSPARK_MODEL_OFFICIAL` / `DSPARK_REVISION`) | `deepseek-ai/DeepSeek-V4-Flash-Vision-Exp` @ `86f746b36186f0e567729a5c06a8c918caba82a9` |
| API 上のモデル名 (`SERVED_MODEL_NAME`) | `deepseek-v4-flash-vision-exp` |
| コンテキスト上限 (`MAX_MODEL_LEN`) | サーバ 1,048,576 トークン / Claude Code からは 524,288 (`settings.deepseek-spark.json` の `CLAUDE_CODE_MAX_CONTEXT_TOKENS`) |
| 同時リクエスト上限 (`MAX_NUM_SEQS`) | 6 リクエスト。超過分はエラーにならずキューで待つ |
| 投機デコード (`MTP_NUM_TOKENS`) | DSpark、draft 6 トークン |
| メモリ確保率 (`GPU_MEMORY_UTILIZATION_TEXT`) | 0.835 (意味は「メモリの使われ方」) |
| KV キャッシュ | `nvfp4_ds_mla` |
| 既定の reasoning (`DEFAULT_THINKING`) | `low` (取りうる値: `off` / `low` / `high` / `max`。リクエスト単位の指定が優先する) |
| コンテナイメージ | `ghcr.io/anemll/dspark-vllm-gx10:0.1.1@sha256:a83948492cf13df455170fb42885f5ef4db54fefe0feff0f841ecbff464ac9d8` (DSpark ランタイムの配布元 Anemll) |
| レシピの commit | `f5665e8`。上流 `main` はここから先行している (件数と中身は「依拠する外部事実」の確認コマンドで見る。速い変化があるので本書に数を書かない) |

重みは両ノードの `~/.cache/huggingface/hub/` に 2 モデル分ある。worker は NFS ではなくローカルコピーを持つ。

| チェックポイント | head | worker | 備考 |
| --- | --- | --- | --- |
| Vision-Exp | 158 GiB | 157 GiB | 配信中 |
| 0731 | 156 GiB | 156 GiB | 待機 |

### メモリの使われ方

GB10 は CPU と GPU が同じ物理メモリを共有する統合メモリ構成である。**`GPU_MEMORY_UTILIZATION_TEXT=0.835` は通常の GPU なら VRAM の 83.5% を指すが、ここではシステムメモリ全体の 83.5% を意味する。** 起動直後から 100 GiB 超が vLLM に確保されて `free` の残りが 6〜8 GiB になるが、これは設定どおりの先取りであって、リークでも不足でもない。

| 項目 | head | worker |
| --- | --- | --- |
| 物理メモリ合計 | 121.7 GiB | 121.7 GiB |
| vLLM の確保 | 101.4 GiB | 101.4 GiB |
| `MemAvailable` | 6.1 GiB | 7.5 GiB |
| swap 使用 | 3.9 GiB | 2.9 GiB |

期待値 121.7 × 0.835 = 101.6 GiB と実測 101.4 GiB が一致する。head の残りが worker より少ないのは、head だけがデスクトップセッション・sparkDash・tailscaled を抱えているためである。**メモリを空けたくなったらプロセスを探す前にこの値を疑う。**

## 起動と停止

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

**設定を変えたら `docker compose restart` を使わず、`stop` → `start` で作り直す。** 起動時にコンテナ内の vLLM へ多数のパッチを当てる構成なので、restart では古いバイト列が残る。

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

**新しい open-weight を入れるときは `utility-spark-model-fetch` スキルを使う。** 素直にレシピ同梱の `prepare-dspark-model-cache.sh` を使うと worker でも HuggingFace から再ダウンロードして同じ重みを 2 回落とすことになる。head で 1 回落として RoCE 経由で rsync すれば転送は 5〜8 分で済む。所有権の修正・シャードの検証・監視コマンドの落とし穴はスキル側に書いてある。

**0731 への切り替えは重みが両ノードに揃っているので再ダウンロード不要である。** 現行 `f5665e8` は Vision-Exp 固定 (MTP の値を 3 の倍数に強制し、vision 用 hotfix を無条件に当てる) なので、0731 が既定だった頃の `70a7cc4` を固定した worktree から起動する。

```bash
ssh spark-head
cd ~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark && ./stop-deepseek-v4-flash-dspark.sh
cd ~/dspark-0731 && ./start-deepseek-v4-flash-dspark.sh
```

`~/dspark-0731/.env.dspark` は独立した 1 枚で、現行との差は次の 5 キーである。

| キー | 現行 (Vision-Exp) | `~/dspark-0731` |
| --- | --- | --- |
| `DSPARK_MODEL_OFFICIAL` | `deepseek-ai/DeepSeek-V4-Flash-Vision-Exp` | `deepseek-ai/DeepSeek-V4-Flash-0731` |
| `DSPARK_REVISION` | `86f746b3…` | `9e165c30e2704aec5d9d593cce3eebd58bbef1cb` |
| `SERVED_MODEL_NAME` | `deepseek-v4-flash-vision-exp` | `deepseek-v4-flash-0731` |
| `MTP_NUM_TOKENS` | 6 | 5 |
| `HF_DOWNLOAD_WORKERS` | (コメントアウト) | 8 |

`PROJECT_NAME` は両者とも `deepseek-v4-flash` で衝突するので、**必ず現行を `stop` してから起動する**。

切り替えたら Mac 側で 3 か所を確認する (実際に編集が要るのは 1・3 の 2 つ)。

1. **`claude/settings.deepseek-spark.json` のモデル名 6 箇所を書き換える** (`env` の 5 キーと `fallbackModel`)。ここが実際の配信名と食い違うと `model not found` になる
2. **`~/.config/opencode/opencode.json` は編集不要。** 両モデルを既に宣言しているので `ocsp model 0731` で切り替える
3. **sparkDash の `workerLabel` を書き換える。** 実機を見ずに表示するだけの手書き文字列なので、直さないと worker 行が古いモデル名のままになる。ファイルは root 所有なのでコンテナ経由で書き、読み戻して確認する。`~/sparkDash/config` は `/app/config` に bind mount されているので、編集はコンテナを作り直しても残る

```bash
ssh -n spark-head "docker exec sparkDash node -e \"const f='/app/config/sparks.json',fs=require('fs');const j=JSON.parse(fs.readFileSync(f));j.sparks.find(s=>s.role==='worker').workerLabel='deepseek-v4-flash-0731';fs.writeFileSync(f,JSON.stringify(j,null,2))\""
ssh -n spark-head "docker exec sparkDash node -e \"console.log(JSON.parse(require('fs').readFileSync('/app/config/sparks.json')).sparks.map(s=>s.role+':'+s.workerLabel).join(' '))\""
```

**Vision-Exp へ戻すときは同じ 4 手順を逆向きに打つ**: `~/dspark-0731` で `stop` → 現行ディレクトリで `start` → settings のモデル名 6 箇所を `deepseek-v4-flash-vision-exp` へ → `workerLabel` を同名へ。

**0731 はテキスト専用である。** 切り替えると Claude Code からスクリーンショットを渡せなくなる。単一利用時の decode は 0731 が上だが (49.25 対 40.77 tok/s、「L1」表)、4 並列では差が消え、レシピの最適化が Vision-Exp に向いているため常用は Vision-Exp にしてある。

## Mac から使う

### 新しいマシンで手で用意するもの

Nix (`drs`) では入らないものが 5 つある。

| もの | 用途 | 作り方 |
| --- | --- | --- |
| `~/.ssh/config` と鍵 2 本 | ssh エイリアス | 「接続する」節 |
| `known_hosts` の 3 エントリ | Claude の非対話 ssh | 「接続する」節の `ssh-keyscan` (人が実行) |
| 1Password へのサインイン | `ccsp` のトークン取得 | `op signin` |
| `/tmp/spark.key` (Mac と head) | OpenCode と `bench.py` | 「API キーの流れ」節 |
| `~/.config/opencode/spark-base-url` | OpenCode の接続先 (IP を含むため管理外) | 「OpenCode (`ocsp`)」節 |

`ccsp` / `ocsp` の関数本体と `opencode` バイナリは Nix 経由なので、**`drs` を実行してから新しいシェルを開くまで存在しない** (既存シェルには旧定義が残る)。Tailscale 本体は `nix/modules/darwin/homebrew.nix` の cask `tailscale-app` で入る。

### Claude Code (`ccsp`)

```bash
ccsp                       # 到達する方を自動選択して claude を起動
ccsp lan                   # 自宅 LAN を強制 (プローブしない)
ccsp ts                    # Tailscale を強制
ccsp status                # 起動せずに接続先・モデル・両経路の到達性を表示
ccsp off                   # Anthropic に戻す
ccsp -h                    # usage を出して終了
ccsp lan -p "..." --allowedTools Read   # サブコマンドの後ろの引数は claude にそのまま渡る
```

実体は `zsh/functions/claude-deepseek.zsh` の `ccsp` と `claude/settings.deepseek-spark.json` である。前提は `op` にサインイン済みであることと、dotfiles が `$GHQ_ROOT/github.com/skanehira/dotfiles` (既定で `~/dev/...`) にあることである。`ccsp ts` は Mac が同じ tailnet に参加している必要がある。

押さえるべき点が 5 つある。

- **`ccsp` 自身が `claude` を起動する。** 続けて `claude` を打つ必要はない。同じシェルで打ち直せるよう alias も張るが、alias は子プロセスに継承されないので、**サブシェルやスクリプトからは `ccsp` 経由で起動する**
- **別のバックエンドから切り替えるときは、`claude` を終了してから `off` を打つ。** `ccds` と `ccsp` は `ANTHROPIC_AUTH_TOKEN` を共有するため、残っていると使い回されて 401 になる。401 が出たらまず残留トークンを疑う。`off` は環境変数を消すだけなので、進行中のリクエストは止まらない
- **`ANTHROPIC_BASE_URL` を settings JSON に書かない。** settings の `env` はシェルの export を無条件に上書きするため、JSON に書くと出先での切り替えが効かなくなる。接続先は `ccsp` が export する
- **`ccsp` は `NODE_OPTIONS` に `--dns-result-order=ipv4first` を足し、`off` で元に戻す。** mDNS 名は到達できない IPv6 を 2 つ返し、Node が毎回それを試してから IPv4 に落ちるため接続が 223 ms かかる (IPv4 強制なら約 12 ms)。これが「`hi` と打っただけで network retry」の原因だった。IP を直接使いたいときは `CCSP_LAN_HOST` に IP を入れる (公開リポジトリなので関数内には直書きしない)
- **2 つの設定ファイルで反映経路が違う。** `settings.deepseek-spark.json` は `ccsp` が dotfiles を直参照するので編集すれば次の起動から効く。`zsh/functions/*.zsh` は Nix store 経由で配られるので `drs` と新しいシェルが要る

`settings.deepseek-spark.json` は **`security-guidance` プラグインを無効にしている** (`enabledPlugins` のキーは完全名 `security-guidance@claude-plugins-official`)。このプラグインの Stop hook は自前の既定モデル名 `claude-opus-4-7` を `ANTHROPIC_BASE_URL` に投げるため、Spark 相手では 404 を受けて延々とリトライし、レビューを 1 件も出さないまま 1 セッションあたり約 231 秒を捨てる。`settings.deepseek.json` (DeepSeek 本家) も同じ理由で無効にしてある。

### OpenCode (`ocsp`)

```bash
ocsp                       # 対話 TUI をカレントディレクトリで起動
ocsp run "README を要約して" # headless で 1 回実行
ocsp model 0731            # モデルを切り替える (0731 / vision / 明示名)
ocsp status                # 接続先・モデル・サーバの配信中モデルを表示
ocsp -h                    # 使い方とモデル名の短縮表を出して終了
```

実体は `zsh/functions/opencode-spark.zsh` である。**`ccsp` と違って 1Password も alias も使わない**ので、解除操作 (`off` に相当するもの) が要らない。モデル選択だけはシェル変数 `OCSP_MODEL` に残り、新しいシェルでは Vision-Exp に戻る。接続先とキーは `~/.config/opencode/opencode.json` の `provider.spark` が持ち、OpenCode 本体が直接読む。

**設定は `opencode/opencode.json` として dotfiles にあり、`nix/modules/home/opencode.nix` が `mkOutOfStoreSymlink` で `~/.config/opencode/opencode.json` に貼る** (`claude/settings.json` と同じ live edit)。`~/.config/opencode/` には opencode 自身が書く `tui.json` / `skills/` / `node_modules` / `package.json` が同居するので、**symlink するのは `opencode.json` 1 枚だけ**である。

**IP はそこに書かない。** 接続先の実値は opencode の `{file:…}` 置換で `~/.config/opencode/spark-base-url` から読む。このファイルは dotfiles 管理外なので、新しいマシンでは自分で作る。`{file:…}` は `~` 起点のパスを受け付け、値は読んだ内容そのものなので**末尾に改行を入れない** (`printf` を使う)。

```bash
printf 'http://<spark-head の LAN IP>:8888/v1' > ~/.config/opencode/spark-base-url
chmod 600 ~/.config/opencode/spark-base-url
```

mDNS 名 (`http://spark-head.local:8888/v1`) を書いても動くが、接続あたり約 210 ms 遅くなる (実測 224 ms 対 7〜21 ms)。`ccsp` が `NODE_OPTIONS` で回避しているのと同じ IPv6 フォールバックで、opencode には相当する回避手段が無いため IP を使う。

このファイルか `/tmp/spark.key` が無いと `ocsp` は接続先を解決できず、どのファイルが読めないかを表示して止まる。`autoupdate` は `false` にしてある (本体は Nix 管理で、store は書き換えられないため)。

## 実測値

数値は条件が変わると簡単に 25% 動くので、表ごとに条件を書いてある。**閾値だけを覚えて条件を変えて測ると誤診する。**

### L1: サーバ単体 (2026-09-05)

`~/spark-bench/bench.py` でサーバを直叩きした値である。条件はプロンプト 6,000 トークン、`max_tokens` 256、`chat_template_kwargs={"thinking": true, "reasoning_effort": "low"}` (サーバ既定の `DEFAULT_THINKING=low` と同じ)、指示は「TypeScript の関数を 1 つ書く。説明は不要」。`c` は `--concurrency`。中央値と (最小〜最大)。

| 条件 | n | Vision-Exp | 0731 |
| --- | --- | --- | --- |
| c=1・decode (tok/s) | 5 | 40.77 (34.88〜62.80) | 49.25 (12.43〜53.50) |
| c=1・TTFT (秒) | 5 | 3.47 (3.20〜3.93) | 3.32 (3.25〜8.64) |
| c=4・decode (tok/s) | 8 (4 並列 × 2 回) | 21.95 (14.44〜34.88) | 21.20 (15.73〜28.96) |
| c=4・TTFT (秒) | 8 (4 並列 × 2 回) | 9.44 (4.93〜13.47) | 9.24 (5.02〜12.68) |

**判定: c=1 の decode 中央値が 35 tok/s を下回る、または c=4 の TTFT 中央値が 15 秒を超えたら異常を疑う。** 個別値ではなく中央値で見る (正常時でも最小値は 34.88 tok/s まで落ちる)。再現は次の 2 本で、結果は `~/spark-bench/results/<ラベル>-<日時>.json` に残る。

```bash
ssh -n spark-head 'python3 ~/spark-bench/bench.py --model deepseek-v4-flash-vision-exp \
  --key-file /tmp/spark.key --prompt-tokens 6000 --max-tokens 256 --concurrency 1 --n 5 \
  --instruction "上記は無視して、TypeScript の関数を 1 つ書いてください。説明は不要でコードだけ返してください。"'
ssh -n spark-head 'python3 ~/spark-bench/bench.py --model deepseek-v4-flash-vision-exp \
  --key-file /tmp/spark.key --prompt-tokens 6000 --max-tokens 256 --concurrency 4 --n 2 \
  --instruction "上記は無視して、TypeScript の関数を 1 つ書いてください。説明は不要でコードだけ返してください。"'
```

### L2 / L3: クライアント込み (2026-09-05)

同一の実タスク (TypeScript プロジェクトで Read → Edit → Edit → Grep の 4 tool call) を流し、`~/spark-bench/snap.py` で `/metrics` の前後差分を取った値である。列の意味は次のとおり。

- **サーバ内時間** = リクエストごとの queue + prefill + decode の**合算**。並列に走ればこの値は実時間を超える
- **クライアント側の待ち** = 実時間 − サーバ内時間。リクエストが重なると負になる (= クライアント側の待ちがほぼ無い)

**Vision-Exp。**

| 層 | 構成 | n | 実時間 (秒) | ターン | 1 ターンのプロンプト (トークン) | 受理率 | prefix ヒット率 | クライアント側の待ち (秒) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| L2 | Claude Code (通常設定) | 2 | 329〜484 | 5〜12 | 54,794〜55,866 | 0.43〜0.48 | 0.66〜0.73 | **231〜233** |
| L2 | Claude Code (グローバル設定なし) | 1 | 41 | 5 | 18,335 | 0.60 | 0.68 | −18 |
| L3 | OpenCode | 2 | 21〜30 | 5 | 14,998〜15,008 | 0.66〜0.69 | 0.73〜0.90 | −3〜0 |

「グローバル設定なし」は `~/.claude/CLAUDE.md` と `claude/rules/` を外した `CLAUDE_CONFIG_DIR` で起動した回である。

**0731** (同じタスク。受理率と prefix ヒット率は記録していない)。

| 層 | 構成 | n | 実時間 (秒) | ターン | 1 ターンのプロンプト (トークン) |
| --- | --- | --- | --- | --- | --- |
| L2 | Claude Code (プラグイン無効) | 2 | 116〜119 | 5〜6 | 55,082〜55,637 |
| L3 | OpenCode | 3 | 20〜29 | 5 | 14,996〜15,008 |

**同じサーバ・同じモデル・同じタスクで実時間が 10 倍以上違う。差はすべてクライアント側にある。**

- **Claude Code 通常設定の「クライアント側の待ち」231〜233 秒はほぼ全量が `security-guidance` の Stop hook である。** 無効化した回では 0 以下に落ちる。この値は 2 回の走行でほぼ一定だった
- **1 ターンのプロンプトが 55,000 対 15,000 トークンなのは、グローバル `CLAUDE.md` と `rules` が毎ターン載るためである。** prefill 律速の本環境ではこれがそのまま待ち時間になる
- **`--settings` に `hooks: {}` を書いてもプラグインの hook は止まらない** (stream-json に `hook_started` が出続ける)。止めるには `enabledPlugins` で当該プラグインを `false` にする
- 0731 では別途 **701 秒・20 ターン**の走行を 1 回観測しているが、これはモデルが同じ編集を往復した外れ値で、典型値ではない

### 遅いと感じたときに疑う順序

サーバを疑うのは最後である。上から順に見る。

1. **`security-guidance` が有効になっていないか** — 症状は「最後の応答が出てから 200 秒以上プロンプトが返らない」。`settings.deepseek-spark.json` の `enabledPlugins` を見る
2. **グローバル設定の prefill** — `claude/rules/core/*.md` の 10 ファイルと `core/references/loop-engineering.md` は frontmatter を持たないため毎ターン展開される (合計 45,201 バイト / 21,230 文字)。`backend/**` や `frontend/**` は `paths:` で対象言語に絞られ、`core/references/` の他の 7 ファイルは `__read-on-demand-only__` で除外されているのに、この 11 本だけ素通しになっている。**これは dotfiles 側の設計課題であって Spark の問題ではない**
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

| 症状 | 確認 | よくある原因 |
| --- | --- | --- |
| 応答しない | 下の待ち行列コマンド | コンテナは生きていて過負荷。`MAX_NUM_SEQS=6` を超えた分が待つので、待ち行列が 0 でなければ過負荷 |
| コンテナが無い | 両ノードで `docker ps --filter name=vllm-dspark` (コンテナ名は両ノードとも `deepseek-v4-flash-vllm-dspark-1`) | `stop` で止めたまま。`start` し直す |
| 起動に失敗する | `./logs-deepseek-v4-flash-dspark.sh` | `no usable RoCEv2 GID` は RoCE 2 本目の IP か MTU。`model not found` はクライアント側のモデル名 |
| 6 分を過ぎても上がらない | head は `docker logs deepseek-v4-flash-vllm-dspark-1`、worker は「worker に入る」節のコマンドで同じものを打つ | worker 側だけ落ちていることがある。両ランクを見る |
| 起動直後から空きメモリが 6 GiB | `free -h` | 正常。`GPU_MEMORY_UTILIZATION_TEXT=0.835` の先取り (「メモリの使われ方」) |
| `hi` と打っただけで network retry | `ccsp status` で LAN 到達を確認 | mDNS の IPv6 フォールバック。`NODE_OPTIONS` に `--dns-result-order=ipv4first` が入っているか見る |
| 応答後に 200 秒以上返らない | `settings.deepseek-spark.json` の `enabledPlugins` | `security-guidance` の Stop hook (→「遅いと感じたときに疑う順序」1) |
| 全体的に遅い | 「遅いと感じたときに疑う順序」を上から | クライアント側が大半 |
| ダッシュボードの worker が古いモデル | `~/sparkDash/config/sparks.json` | `workerLabel` は手書きの静的文字列。実機とは無関係に表示される |
| ssh 出力が途中で切れる | 打ったコマンド | 入れ子の `ssh` が標準入力を飲んでいる。内側に `-n` を付ける |

待ち行列と稼働中リクエストは次で見る。

```bash
curl -s http://spark-head.local:8888/metrics | grep -E '^vllm:num_requests_(running|waiting)\{'
```

## 触らないもの

- **`~/.ssh/known_hosts`** — Claude は書き換えない。登録が要るときは `ssh-keyscan` の 1 行をユーザーに依頼する
- **`~/sparkDash/docker-compose.yml`** — 上流の追跡ファイル。上書きは `docker-compose.override.yml` に置く
- **`docker compose restart`** — vLLM には使わない。`stop` → `start`
- **`.env.dspark.bak` のような控え** — `.gitignore` が拾わずキーごと公開リポジトリに載る
- **公開リポジトリ内のファイルへの IP 直書き** — 本書・`zsh/functions/*.zsh`・`opencode/opencode.json` のいずれにも書かない。IP は `CCSP_LAN_HOST` と `~/.config/opencode/spark-base-url` (どちらも dotfiles 管理外) で渡す
- **sparkDash のポート 5555** — 認証が無いので信頼できないネットワークへ出さない

## 既知の制約

1. **Spark には passwordless sudo が無い。** `/etc/sudoers.d/` は README のみである。`nvidia-smi --lock-gpu-clocks` や systemd の操作など sudo が要る作業は Claude からは実行できないので、コマンドを提示して人間に実行してもらう (パスワードは `skanehira` の Ubuntu ログインパスワードで、本書には保管しない)。Mac の Touch ID による sudo は Linux ノードには効かない。**コンテナ内で root が必要な作業は `docker run --entrypoint` で代替できる** (重みの所有権修正など)
2. **worker への直接 ssh は `known_hosts` の登録が前提である。** 未登録のマシンでは Claude から入れないので「worker に入る」節の head 経由を使う
3. **worker は Tailscale に参加していない** (`tailscaled` が未インストール)。出先から worker を見るには head を経由する
4. **GPU クロックを 2200 MHz に制限している。** 両ノードの `/etc/systemd/system/nv-gpu-clock-limit.service` (手で配置した unit、enabled + active) が起動時に `nvidia-smi --lock-gpu-clocks=0,2200` を実行する。2026-09-05 の計測 (n=5、L1 とは別条件で結果ファイルは残っていない) では、解除しても decode +1.3% / 最悪 TTFT 約 +2% しか上がらず温度が 7 °C 以上上がった (制限あり 52〜58 °C / 制限なし 60〜65 °C) ので、制限は維持する
5. **停止と再起動はユーザーの作業を止める。** 打つ前に `curl -s http://spark-head.local:8888/metrics | grep -E '^vllm:num_requests_running\{'` で稼働中リクエストの有無を確認し、Mac 側では先に `claude` を終了して `ccsp off` で退避する
6. **ノード再起動後は原則として自動復帰する。** vLLM コンテナの restart policy は `unless-stopped`、sparkDash は `always`、`docker` と (head の) `tailscaled` は enabled、RoCE は NetworkManager の autoconnect である。ただし `stop` スクリプトで止めた後は再起動しても上がらない。**cold boot での復帰は未確認なので、電源断の後は `./status-deepseek-v4-flash-dspark.sh` で確かめる**
7. **`~/spark-bench` は再作成手段が無い。** dotfiles にも上流にも無い手書きのハーネスなので、head を作り直すと失われる

## 依拠する外部事実

2026-09-06 に実機で確認した (「実測値」節の性能値のみ 2026-09-05)。作業前に変わっていないか確かめる。認証が要る確認は先にキーを取る。

```bash
KEY="$(op read 'op://Personal/DGX Spark vLLM API Key/credential')"
```

| 事実 | 確認コマンド |
| --- | --- |
| IP・インタフェース構成・MTU | `ssh -n spark-head 'ip -4 -o addr show; ip -o link show'` |
| ドライバとカーネル | `ssh -n spark-head 'nvidia-smi --query-gpu=driver_version --format=csv,noheader; uname -r'` |
| ディスクの空き | `ssh -n spark-head 'df -h /'` |
| メモリの内訳 | `ssh -n spark-head 'grep -E "^Mem" /proc/meminfo; swapon --show; nvidia-smi --query-compute-apps=used_memory --format=csv,noheader'` |
| サービングの設定値 | `ssh -n spark-head 'cd ~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark && ./validate-dspark-config.sh'` |
| 上流の先行コミット | `ssh -n spark-head 'cd ~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark && git fetch -q && git rev-list --count HEAD..origin/main && git log --oneline HEAD..origin/main'` |
| 両モデルの重み | `ssh -n spark-head 'du -sh ~/.cache/huggingface/hub/models--deepseek-ai--*'` |
| worker 側の同じ確認 | 「worker に入る」節のコマンドの `<worker で実行するコマンド>` に上記を入れる |
| 稼働中のモデル名と上限 | `curl -H "Authorization: Bearer $KEY" http://spark-head.local:8888/v1/models` |
| 各種メトリクス | 「遅いと感じたときに疑う順序」の `curl` 1 本 (完全一致の grep) |
| クロック制限の有効性 | `ssh -n spark-head 'systemctl is-active nv-gpu-clock-limit.service'` (worker は head 経由) |
| 再起動後の復帰条件 | `ssh -n spark-head 'docker inspect deepseek-v4-flash-vllm-dspark-1 --format "{{.HostConfig.RestartPolicy.Name}}"'` |
| Tailscale の参加状況 | Mac 側で `tailscale status` |
| OpenCode の設定 | Mac 側で `python3 -c "import json;print(list(json.load(open('$HOME/.config/opencode/opencode.json'))['provider']))"` |
| 上流既定からの差分 | 下のコードブロック 1 (キー行が出るので画面外に出さない) |
| 常時展開される rules | 下のコードブロック 2 |
| L1 の再計測 | 「L1」節の `bench.py` 2 本をそのまま打つ |

パイプを含むので表に入らないもの。

```bash
# 1. .env.dspark と配布既定の差分
ssh -n spark-head 'cd ~/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark && diff <(grep -E "^[A-Za-z0-9_]+=" .env.dspark.example | sort) <(grep -E "^[A-Za-z0-9_]+=" .env.dspark | sort)'

# 2. frontmatter を持たず毎ターン展開される rules (dotfiles で実行)
for f in claude/rules/core/*.md claude/rules/core/references/loop-engineering.md; do
  head -8 "$f" | grep -q __read-on-demand-only__ || echo "$f"
done
```
