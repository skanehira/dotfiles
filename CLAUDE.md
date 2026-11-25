# CLAUDE.md

このリポジトリで作業するエージェント (Claude Code / Codex / OpenCode) 向けの運用ガイド。

- 種別: プロジェクト運用ガイド
- 対象読者: このリポジトリで作業する Claude / Codex / OpenCode
- 最終確認: 2026-11-21。**本書の件数 (スキル 52 本・subagent 4 本・`enabledPlugins` 23 件で有効 20 本・`settings.json` の hooks 1 件・`packages-android.nix` 19 エントリ) は実環境に依存するので、疑わしいときは数え直す**

## Repository Overview

dotfiles リポジトリ。macOS は **Nix (nix-darwin + Home Manager)**、Linux は **Home Manager standalone (非 NixOS)** で宣言的管理。設定ファイルは `home.file` × `mkOutOfStoreSymlink` で dotfiles 直接 symlink としてバインドし、live edit を維持する。

## Installation

### 初回セットアップ (macOS 新マシン)

```bash
# clone 先は ~/dev/github.com/skanehira/dotfiles 固定
# (nix/home-core.nix の dotfilesRoot がこの path を literal で持ち、各 module の
#  mkOutOfStoreSymlink がそれを参照する。dotfilesRoot を経由せず同じ path を自前で
#  持つ箇所もある。literal は darwin/codex.nix の environment.etc・env.nix の NH_FLAKE・
#  bootstrap.sh・vim/after/lsp/nixd.lua、$GHQ_ROOT 経由は zsh/functions/claude-deepseek.zsh・
#  agents/bindings/claude/settings.json の statusLine)
mkdir -p ~/dev/github.com/skanehira
cd ~/dev/github.com/skanehira
git clone https://github.com/skanehira/dotfiles.git
cd dotfiles

# Nix install + nix-darwin 適用
bash ./bootstrap.sh
```

`bootstrap.sh` は (1) Nix 未導入時のみ公式 installer を実行し、(2) `nix-daemon` の socket が無ければ `launchctl load` し、(3) `nix/install.sh` 経由で `sudo nix run nix-darwin -- switch --flake .#skanehira` を回す。途中で Nix installer の y/n プロンプトと `sudo` (Touch ID / パスワード) が要求される。既存マシンでは Nix install を skip するので idempotent。

### 初回セットアップ (Linux 新マシン、非 NixOS)

```bash
# Nix インストール (multi-user; systemd 不在の container では --no-daemon に切り替える)
sh <(curl -L https://nixos.org/nix/install) --daemon

# experimental-features を nix.conf に永続化
# (`nix run home-manager/master` はネストした nix 呼び出しが走るため、
#  コマンドラインの --extra-experimental-features では伝播せず disabled エラーになる)
mkdir -p ~/.config/nix
echo 'experimental-features = nix-command flakes' > ~/.config/nix/nix.conf

mkdir -p ~/dev/github.com/skanehira
cd ~/dev/github.com/skanehira
git clone https://github.com/skanehira/dotfiles.git

cd dotfiles/nix
nix run home-manager/master -- switch --flake ".#skanehira"
```

aarch64 マシンは `.#skanehira` を `.#skanehira-aarch64` に置換する。Linux 専用 bootstrap script は用意していない (上記コマンドを手で叩く)。

activation 中に `modules/home/codex.nix` が `sudo` で `/etc/codex/config.toml` を `agents/bindings/codex/config.toml` へ symlink する (Home Manager standalone には `/etc` を宣言する option が無いため。`codex.nix` を import しない `-android` は対象外)。`sudo` が使えない環境では警告と手動コマンドが表示されるだけで activation は失敗しない。

`linuxUsers` に列挙したユーザーごとに 3 つの output が生える。用途で選ぶ。

| output | system | 入口 | 用途 |
| --- | --- | --- | --- |
| `.#<user>` | x86_64-linux | `home-linux.nix` | 通常の Linux (Ubuntu container / サーバー) |
| `.#<user>-aarch64` | aarch64-linux | `home-linux.nix` | 同上の arm 版 |
| `.#<user>-android` | aarch64-linux | `home-android.nix` | Android の Termux + proot-distro Debian |

ログインユーザーが `skanehira` でないマシン (CI / 検証箱など) では、`flake.nix` の `linuxUsers` にそのユーザー名を足してから `.#<ユーザー名>` を指定する。`ubuntu` は既に列挙済みなので、`.#ubuntu` がそのまま使える。`$USER` を動的に読む impure 方式は採らず、pure に列挙する。`nh` / `home-manager` は pure 評価で output を引くので、impure 方式では `hms` 等が壊れる。

### 初回セットアップ (Android / Galaxy Z Fold 8 Ultra)

Snapdragon 機は Android 標準の Linux ターミナル (AVF = Android Virtualization Framework) を起動できない。そのため Termux + proot-distro Debian を使う。手順とその根拠は `docs/android-dev-setup.md` にまとめてある。通常の Linux とは以下が違う。

- Nix は single-user (`--no-daemon`)。proot に systemd が無いため
- `~/.config/nix/nix.conf` に `sandbox = false` が要る。proot は user namespace を作れないため
- proot 内のユーザー名は `skanehira` にする (`linuxUsers` に既にあるので flake の変更が要らない)
- 適用は `.#skanehira-android`。フルセットではなく軽量プロファイルが当たる

### 設定変更を反映

```bash
# macOS
drs   # alias: noglob nh darwin switch ~/dev/.../nix -H skanehira

# Linux (Home Manager standalone)
hms   # alias: noglob nh home switch ~/dev/.../nix -c <configName>
```

両 alias は `zsh.nix` の `programs.zsh.shellAliases` で OS 別に `lib.optionalAttrs` 分岐済 (darwin=drs / linux=hms)。手動でフルコマンドを叩くより楽。

設定名は `nh` の `-H` (darwin) / `-c` (home) で**明示**する。`nh` 4.x は `<flake>#name` の `#name` を素の flake 属性として解決し (`darwinConfigurations` / `homeConfigurations` を前置しない) `#name` では引けないため。

`hms` の `-c` には **flake の attr 名そのもの** (`configName`) が入る。`flake.nix` の `mkLinuxHome` が output 名と同じ文字列を `extraSpecialArgs` で `zsh.nix` に渡し、`zsh.nix` がそれを alias に埋める。したがって aarch64 では `-c skanehira-aarch64`、Android では `-c skanehira-android` になる。ここに username を埋めると aarch64 機でも `-c skanehira` を渡すことになり、x86_64 用の config を掴んで失敗する。

### Linux 動作確認 (Ubuntu container、ad-hoc)

container 関連ファイルは repo に置かない (検証用途のみ)。下記を mac から直接叩く:

```bash
docker run --rm -it --platform linux/amd64 \
  -v ~/dev/github.com/skanehira/dotfiles:/dotfiles:ro \
  ubuntu:24.04 bash -c '
    set -e
    apt-get update -qq
    apt-get install -y -qq curl xz-utils sudo git ca-certificates locales
    locale-gen en_US.UTF-8
    useradd -ms /bin/bash skanehira
    echo "skanehira ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
    su - skanehira -c "
      curl -L https://nixos.org/nix/install | sh -s -- --no-daemon
      mkdir -p ~/.config/nix
      echo experimental-features = nix-command flakes > ~/.config/nix/nix.conf
      mkdir -p ~/dev/github.com/skanehira
      cp -r /dotfiles ~/dev/github.com/skanehira/dotfiles
      cd ~/dev/github.com/skanehira/dotfiles/nix
      ~/.nix-profile/bin/nix --extra-experimental-features \"nix-command flakes\" \
        run home-manager/master -- switch --flake .#skanehira
      exec zsh
    "
  '
```

aarch64 検証は `--platform linux/arm64` + flake target を `.#skanehira-aarch64` に変える。

## Directory Structure

### Nix 管理 (中核)

- **nix/** — flake-based config (最も重要)
  - `flake.nix` — inputs, outputs (`darwinConfigurations.skanehira` + `homeConfigurations` = `linuxUsers` × 3 プロファイル。現在は `skanehira` / `ubuntu` の 2 ユーザーで 6 output + `packages` + `formatter`)
  - `home-core.nix` — 全プロファイル共通の土台 (dotfilesRoot / stateVersion / programs.home-manager)。module の import は持たない
  - `home.nix` — フルセットのプロファイル (mac と通常 Linux が共有)
  - `home-darwin.nix` — mac 用エントリ (home.nix + mac 専用 4 module (karabiner / wezterm / mac-app-util-icons / comfyui) + `homeDirectory = /Users/...`)
  - `home-linux.nix` — 通常 Linux 用エントリ (home.nix + `homeDirectory = /home/...`)
  - `home-android.nix` — Android (Termux + proot) 用エントリ (home-core.nix + 軽量 module のみ)
  - `darwin.nix` — nix-darwin imports のみ
  - `modules/home/` — Home Manager modules (CLI パッケージ、env、git、gh、zsh、fzf、direnv、tmux、wezterm、karabiner 等)
  - `modules/darwin/` — nix-darwin modules (system、homebrew、codex、sleepctl)
  - `modules/overlays.nix` — nix-darwin 用 overlays モジュール (overlays-list.nix を消費)
  - `modules/overlays-list.nix` — overlay の素のリスト (mac/Linux 両側で共有)
  - `install.sh` — mac bootstrap 用 (一度限り)
  - `pkgs/` — nixpkgs 未収録、または nixpkgs 版が使えないツールの自前 derivation (tsp-server / gh-actions-language-server / kanary / opencode / claude-recall / nodejs-bin)

### Nix 補助

- **zsh/** — `zsh.nix` が 2 つの経路で取り込む zsh の設定
  - `zshrc` — bindkey 群 + 関数 source loop。`programs.zsh.initContent` が `builtins.readFile` で取り込む
  - `functions/*.zsh` — カスタム zsh 関数は macOS で 5 本、Linux で 4 本。`zsh.nix` の `home.file` が `~/.config/zsh/functions/` に 1 本ずつ置き、`zshrc` の source loop が読み込む。`ghq-fzf` / `gss` / `tmuxpopup` / `claude-deepseek` (`ccds`: DeepSeek 本家 API) と、mac 専用の `sleepctl`。OpenCode はラッパー関数を持たず、素の `opencode` が Spark に繋がる (接続先・運用は `agents/guidelines/infra/dgx-spark.md`)
- **karabiner/** — Karabiner-Elements 設定 (Goku DSL)
  - `karabiner.edn` — EDN で書いたルール、switch 時に goku が `~/.config/karabiner/karabiner.json` を生成
- **wezterm/** — WezTerm 設定 (`mkOutOfStoreSymlink` で dotfiles 直接 symlink、live edit 可能)
  - `wezterm.lua` — `programs.wezterm.extraConfig` は使わず直接 symlink する。Lua の編集体験 (lua_ls) を保ち、`drs` 無しで反映するため
- **tmux/** — tmux 設定 (`mkOutOfStoreSymlink` で dotfiles 直接 symlink、live edit 可能)
  - `tmux.conf` — 編集即反映、`prefix + r` で reload。`drs` 不要
  - プラグインの run-shell だけは nix store path 解決のため Nix 生成の `~/.config/tmux/plugins.conf` 経由
- **agents/** — AI エージェント共通のハーネス正本 (3 ランタイムが同じ実体を読む。配布は正本への symlink が基本で live edit 可能)
  - `AGENTS.md` / `guidelines/` / `skills/` の本文は正本への symlink なので編集即反映。`subagents/` の変更とスキルの追加・削除は、ランタイムによって `drs` / `hms` が要る (→「live edit の範囲」)
  - `hooks/` / `scripts/` / `knowledge-profile.md` と `bindings/claude/settings.json` / `keybindings.json` / `bindings/codex/AGENTS.md` / `config.toml` / `bindings/opencode/AGENTS.md` / `opencode.json` / `plugins/spark-served.ts` / `cli.json` も直 symlink。`bindings/claude/settings.deepseek.json` は配布せず、`ccds` が `$GHQ_ROOT` (ghq のルート。`nix/modules/home/env.nix` が `$HOME/dev` に設定する) 経由で直接読む
  - 配布先と構成は「AI エージェントのハーネス (agents/)」節を参照
- **agents/bindings/codex/** — Codex 固有の設定 (ハーネス本体は `agents/` 直下)
  - `config.toml` — git 管理する Codex 共通設定。Codex の system レイヤー `/etc/codex/config.toml` として dotfiles 直接 symlink され、CLI / ChatGPT.app 内 Codex を含む全クライアントに読まれる (live edit 可能)
  - `config.toml` に hooks は書いていない。このハーネスは機械ゲート (deny する hook) を 1 本も持たないので、移植すべきものが無い。Codex へ hook を配るときの置き場は「hooks (agents/hooks/)」節にある
  - `AGENTS.md` — Codex のグローバル指示。`~/.codex/AGENTS.md` へ symlink され、共通の正本 (`~/.claude/CLAUDE.md`) を読む指示と Claude 綴りの読み替え表を持つ
  - `~/.codex/config.toml` (user レイヤー) は dotfiles で管理しない。Codex 自身が書き込む可変状態で、書かれるものの例は `[projects.*]` trust / `/model` の選択 (`model` / `model_reasoning_effort`) / `notify` / `[plugins.*]` / `[marketplaces.*]` / `[hooks.state]` である。ここにあるキーは system レイヤー (`/etc/codex/config.toml`) の同名キーより優先され続ける。`[mcp_servers.*]` は両レイヤーに現れる。全マシン共通のサーバ (context7 / chrome-devtools) は `config.toml` で配り、マシン固有のものは Codex が user レイヤーに書く
  - `/etc/codex/config.toml` の確認: `readlink -f /etc/codex/config.toml` が dotfiles の `agents/bindings/codex/config.toml` に解決すること
  - **プラグインだけは宣言的に管理できない。** `config.toml` に `[marketplaces.*]` を書くと空ディレクトリを見に行って失敗し、`[plugins.*]` を書いても `not installed` のまま。`codex.nix` の activation が `codex plugin marketplace add` と `codex plugin add` を冪等に流す。Claude 形式の `.claude-plugin/marketplace.json` をそのまま読むので、リポジトリ側に Codex 用のマニフェストは要らない。対象は Claude 側にも入れている 6 本で、`agents/bindings/claude/settings.json` の `enabledPlugins` は 23 件を宣言し有効 (`true`) は 20 本なので、Codex へ配るのはその部分集合になる

    | `codex plugin add` に渡す名前 | marketplace の入手元 |
    | --- | --- |
    | `document-skills@anthropic-agent-skills` | `anthropics/skills` |
    | `frontend-design@claude-plugins-official` | `anthropics/claude-plugins-official` |
    | `ui-ux-pro-max@ui-ux-pro-max-skill` | `nextlevelbuilder/ui-ux-pro-max-skill` |
    | `compact-plus@compact-plus` | `u-ichi/compact-plus` |
    | `archify@misty-lantern` | **ローカル** `~/dev/github.com/skanehira/misty-lantern` |
    | `slide-plugin@slide-plugin` | **ローカル** `~/dev/github.com/skanehira/slide-plugin` |

    下 2 本はローカル clone が前提で、clone のあるマシンでしか入らない。clone が無いマシンでは、`codex.nix` は marketplace の登録を黙って飛ばす (`[ -d "$repo_path" ] || continue`)。続く `codex plugin add` は登録の無い marketplace を指すので失敗し、`codex plugin add … に失敗した` の警告を出す。activation の PATH は、HM が nix の基本ツールだけに絞る。そのため `installCodexPlugins` は、サブシェルの中で `home.path` の bin と Homebrew の bin を足してから `codex` を呼ぶ。**失敗しても activation は警告のみで止まらない**ので、`drs` / `hms` が通っても入ったとは限らない。次のコマンドで 6 本の状態を確かめる (`codex plugin list` の出力は 1 MB を超え、全体を目で探すのは無理がある)。落ちていたら `codex plugin marketplace add <入手元>` → `codex plugin add <名前>` の順で手で流す

    ```bash
    codex plugin list | rg '^(document-skills@anthropic-agent-skills|frontend-design@claude-plugins-official|ui-ux-pro-max@ui-ux-pro-max-skill|compact-plus@compact-plus|archify@misty-lantern|slide-plugin@slide-plugin) '
    # 6 行が出て、名前の次の状態の列がすべて installed, enabled なら合格
    ```
- **agents/bindings/opencode/** — OpenCode (V2) 固有の設定 (ハーネス本体は `agents/` 直下)。**OpenCode は DGX Spark 専用**である。ラッパー無しの素の `opencode` が Tailscale 経由で Spark に繋がり、配信中のモデルを既定に選ぶ。**自宅でも Tailscale へのサインインが前提**になる。mac は Tailscale のアプリを `nix/modules/darwin/homebrew.nix` の cask (`tailscale-app`) で入れるが、サインインは手作業である。Linux / Android の Tailscale は dotfiles の管理外である。繋がらないときは `agents/guidelines/infra/dgx-spark.md`「障害時」節の「OpenCode が Spark に繋がらない」の行を見る
  - `AGENTS.md` — OpenCode のグローバル指示。`~/.config/opencode/AGENTS.md` へ symlink され、共通の正本 (`~/.claude/CLAUDE.md`) を Read する指示と Claude 綴りの読み替え表を持つ。**OpenCode が自動で読むグローバル指示はこのファイルだけ**なので、Read 指示は飾りではない (→「配布先」節)
  - `opencode.json` — Spark の provider 定義 (接続先・モデル宣言・モデルごとの `reasoningEffort` と `limit`)。接続先は Tailscale の MagicDNS 名 `http://spark-head:8888/v1` に固定し、自宅 LAN の経路は使わない。`enabled_providers: ["spark"]` で Spark 以外の provider (OpenCode Zen の無料モデル) を選択肢から外す。V1 書式のまま書いてあり、V2 が読み込み時にメモリ上で正規化する。API キーは持たない (詳細は `agents/guidelines/infra/dgx-spark.md`)
  - `plugins/spark-served.ts` — 配信中のモデルだけを有効にして既定に据える V2 のローカルプラグイン。`~/.config/opencode/plugins/` へ symlink され、起動時と 30 秒ごとに `/v1/models` を引く。接続先 URL を `opencode.json` と 2 か所に持ち (setup の時点で設定の provider を読めないため)、一致は同じディレクトリの `spark-served_test.ts` が検査する。**選ぶのは `opencode.json` に宣言済みのモデルだけ**なので、Spark で配信するモデルを増やしたら `opencode.json` に宣言を足す (→ `agents/guidelines/infra/dgx-spark.md`「モデルの追加と切り替え」)
  - `cli.json` — TUI のキーバインドとテーマ (V2 書式)。`~/.config/opencode/cli.json` へ symlink される。**起動しただけでは V2 は書き換えない。TUI でテーマなどを変えると一時ファイルの rename で書き換えるので、symlink が実ファイルに化け、repo との同期が黙って切れる。設定は repo 側を編集して変え、TUI では変えない**。化けたら、まず `diff ~/.config/opencode/cli.json ~/dev/github.com/skanehira/dotfiles/agents/bindings/opencode/cli.json` で差分を見て、残したい変更を repo 側へ写す。それから実ファイルを消して `drs` / `hms` で張り直す
    - 実ファイルを消さずに適用したときの動きは OS で違う。mac の `drs` は、`nix/flake.nix` の `darwinConfigurations` ブロックで `home-manager.backupFileExtension = "hm-backup"` を設定している。そのため `Existing file … will be moved to '<path>.hm-backup'` を出して実ファイルを `cli.json.hm-backup` へ退避し、処理を続ける。このとき TUI で変えた値は `cli.json.hm-backup` 側に移るので、差分はそちらと取る
    - Linux の `hms` には退避の設定が無い (`mkLinuxHome` は `backupFileExtension` を渡していない)。退避せずに `Existing file … would be clobbered` で activation が止まるので、`hms -b hm-backup` で渡すか、先に手で退避する
    - `.hm-backup` が既にあると、次の退避は `Existing file '<path>.hm-backup' would be clobbered by backing up` で止まる。古い `.hm-backup` は、repo 側との差分を見たうえで退避するか消してからリトライする
  - グローバル指示の確認と同居物: `readlink -f ~/.config/opencode/AGENTS.md` が dotfiles の `agents/bindings/opencode/AGENTS.md` に解決すること。**`~/.config/opencode/` には dotfiles の symlink 以外のものが同居する**ので、ディレクトリごとではなくファイル単位で symlink する。同居するのは次のものである
    - 常駐サービスの設定 `service.json` (キーは `hostname` と `password`)。**`password` は `opencode service set` が生成した値を平文で持つので、表示も共有もしない**。repo に置けず、`opencode service set` が一時ファイルの rename で書き換えるので symlink でも配れない。そのため `opencode.nix` の activation `opencodeServiceConfig` が `drs` / `hms` のたびに既存ファイルを jq で読み、`hostname` だけを `0.0.0.0` に上書きする (`password` など他のキーは残す)。ファイルが無いか JSON として読めないときは警告を出し、`hostname` だけのファイルを作り直す。書き換えた値はサービスを `opencode service restart` するまで効かない
    - subagent の生成物 `agents/` (→「subagent の書式変換」節) と、ある場合は `skills/`
    - V1 のプラグイン SDK (`@opencode-ai/plugin` 1.18.18) を入れた `node_modules` / `package.json` / `package-lock.json` / `.gitignore`。V1 の時期に置かれたもので、dotfiles は管理しない
    - `drs` が退避した `*.hm-backup` (例: `cli.json.hm-backup`)。残っていると次の退避で `drs` が止まるので、上の `cli.json` の項のとおり差分を見たうえで消す
  - 本体は `nix/pkgs/opencode.nix` の自前 derivation (nixpkgs の `opencode` は V1)。npm の `@opencode/cli-<platform>` に入っている bun コンパイル済みの単一バイナリを展開するだけで、ローカルビルドは走らない。更新手順はファイル冒頭のコメントにある
  - 素の `opencode` は常駐サービス (`opencode serve --service`) を起動して接続し、TUI を閉じてもサービスは残る。**待ち受けは全インターフェースの 49374 番で、外からの接続を防ぐのは `service.json` のパスワードだけである** (`hostname` が `0.0.0.0` のため)。**`nix/pkgs/opencode.nix` の版を上げても、常駐サービスは古いバイナリのまま動き続ける**。版を上げたら、`drs` / `hms` の後に必ず `opencode service restart` する。切り替わったかは、`ps -axo command | rg '[o]pencode serve'` に出るストアパスと `readlink -f "$(command -v opencode)"` が一致することで確かめる。設定ファイルとプラグインの変更は、サービスが検知して読み直す実装がソースにある。変更が効いていないように見えたら、同じく `opencode service restart` する。止めるときは `opencode service stop`
- **vim/** — Neovim 設定 (`mkOutOfStoreSymlink` で dotfiles 直接 symlink、live edit 可能)
  - `init.lua` / `lua/` / `after/` — 編集即反映、`drs` 不要
  - `.luarc.json` — lua_ls の dotfiles 内 lua 編集用設定 (track 対象)
- **herdr/** — herdr (コーディングエージェント用のターミナル多重化) の設定
  - `config.toml` — `herdr.nix` が `~/.config/herdr/config.toml` へ mkOutOfStoreSymlink する
  - **herdr のプラグインは使っていない。** プラグインを宣言的に導入する手段が無い。herdr 0.9.3 の `herdr --default-config` に plugin の項目が無く、HM の `programs.herdr` も enable / package / settings の 3 オプションだけである。使うときは `herdr plugin install <owner>/<repo> --yes` を手で流し、`config.toml` の `type = "plugin_action"` でキーに割り当てる。導入状態は `~/.config/herdr/` 配下の herdr 所有ファイルにあり、Nix の管理外になる
  - Neovim 側の herdr 連携は `vim/lua/modules/ai/herdr.lua` (herdr コマンドの低レベルラッパー) が持つ
- **comfyui/** — ComfyUI (Qwen-Image-2.1 の GUI) 用の補助スクリプト (mac only)
  - ComfyUI 本体と venv (`~/.local/share/comfyui/{ComfyUI,venv}`) は `nix/modules/home/comfyui.nix` の activation `bootstrapComfyui` が commit を固定して導入する。nixpkgs の `comfyui` は `meta.platforms` が linux のみで、Qwen-Image-2.1 対応の v0.37.0 にも追いついていない。そのため `deno.nix` / `rustup.nix` と同じ bootstrap パターンを採る。起動は同モジュールが生成する `ComfyUI.app` (mac-app-util が `~/Applications/Home Manager Trampolines/` へ trampoline 化する) から行い、サーバが未起動ならこれが起こす。サーバは `nohup` で裏に起こすので `.app` やブラウザを閉じても残る。止めるときは起動中に `ComfyUI.app` をもう一度開き、ダイアログで「停止」を選ぶ (「ブラウザを開く」が既定)。生成画像は `~/Pictures/ComfyUI` に出る
  - **モデルの入手経路は 2 つあり、マシンによって使い分ける。** どちらも `~/.local/share/comfyui/models/{diffusion_models,text_encoders,vae}/` に置く点は同じ

    | 経路 | 対象 | 版 | 容量 | 手順 |
    | --- | --- | --- | --- | --- |
    | shard 結合 | **mflux で 28.9 GiB を取得済みのマシン (現在は Mac Studio のみ)** | bf16 | 30.2 GiB | `merge-weights.py` を 1 回実行 |
    | UI ダウンロード | それ以外のマシン | int8 | 15.0 GiB | ComfyUI でテンプレートを開き「すべてダウンロード」→ `~/Downloads` から手で移動 |

  - `merge-weights.py` — mflux が使う diffusers 形式の重み (`~/.cache/huggingface/hub/models--Qwen--Qwen-Image-2.1`、shard 分割) を ComfyUI が読む単一ファイル形式へ結合する。VAE だけはキー体系が違うので `Comfy-Org/Qwen-Image-2.1` から取得する。**ComfyUI の venv の python で 1 回だけ手で実行する** (`~/.local/share/comfyui/venv/bin/python comfyui/merge-weights.py`)。30 GiB の結合に数分かかるので activation では流さない。引数無しで冪等 (出力が既にあれば skip)、`--force` で作り直す。**HF キャッシュが無いマシンでは `HF キャッシュが無い` で止まる**ので、その場合は UI 経路を使う
  - **UI 経路では手で移動する作業が 1 回残る。** ComfyUI は不足モデルを列挙して「すべてダウンロード」ボタンを出す。ただし**ブラウザ版はブラウザのダウンロード (`~/Downloads`) になり `models/` には置かれない** (上流 issue [#13676](https://github.com/Comfy-Org/ComfyUI/issues/13676) が open)。公式テンプレートが指定するのは int8 版なので、bf16 を使うマシンではテンプレートのローダのファイル名を bf16 のものへ差し替える
  - mflux を併用するマシンは同じ重みを 2 形式で持つことになる (mflux 用 28.9 GiB + ComfyUI 用 30.2 GiB)。ComfyUI の `DiffusersLoader` は `DEPRECATED` かつ分割されていない `unet/` を探す実装なので diffusers 形式を直接読めず、symlink でも回避できない (shard ごとのヘッダを捨てて繋ぎ直すためバイト列が別物)
- **リポジトリ直下** — `AGENTS.md` (このリポジトリで作業する agent 向けの repo スコープ指示。グローバル指示の正本 `agents/AGENTS.md` とは別物) / `bootstrap.sh` (mac 初回セットアップの入口) / `README.md` / `LICENSE` / `.gitignore` / `.claude/settings.local.json` (このリポジトリでの作業用の権限設定。git 管理外で、除外しているのはリポジトリの `.gitignore` ではなくグローバルの `~/.config/git/ignore`) / `.github/workflows/nix-check.yml` (nix/** の push で flake check と fmt を回す CI)
- **docs/** — Nix 設定だけでは伝わらない環境固有の手順書
  - `android-dev-setup.md` — Galaxy Z Fold 8 Ultra を Termux + proot-distro Debian で開発端末にする手順と制約

## Nix モジュール構成 (詳細)

```text
nix/
├── flake.nix              ← inputs + darwinConfigurations + homeConfigurations + packages + formatter
├── flake.lock
├── home-core.nix          ← 全プロファイル共通の土台 (module の imports は持たない)
├── home.nix               ← フルセット (home-core.nix + 全 module の imports + nix-index-database。`,` で未導入 CLI を一時実行できる)
├── home-darwin.nix        ← home.nix + karabiner / wezterm / mac-app-util-icons / comfyui + homeDirectory=/Users/...
├── home-linux.nix         ← home.nix + homeDirectory=/home/...
├── home-android.nix       ← home-core.nix + 軽量 module + homeDirectory=/home/...
├── darwin.nix             ← imports modules/darwin/
├── install.sh             ← mac bootstrap
├── pkgs/                  ← 自前 derivation (tsp-server / gh-actions-language-server / kanary / opencode / claude-recall / nodejs-bin)
└── modules/
    ├── overlays.nix       ← nix-darwin 用 module (overlays-list.nix を nixpkgs.overlays に流す)
    ├── overlays-list.nix  ← overlay の素のリスト (HM standalone の pkgs= からも参照)
    ├── home/
    │   ├── claude.nix    ← Claude Code (bootstrap install + ハーネス正本と Claude 固有の設定を symlink)
    │   ├── comfyui.nix   ← ComfyUI を rev 固定で bootstrap + .app 生成 (mac only。home-darwin.nix からのみ import)
    │   ├── codex.nix     ← Codex 向けの symlink (~/.codex/AGENTS.md) + スキルの個別 symlink (linkAgentSkills。~/.agents/skills は OpenCode も読む) と subagent の TOML 変換 (syncCodexSubagents) + プラグイン導入 (activation)。Linux のみ /etc/codex/config.toml を sudo で symlink
    │   ├── deno.nix      ← bootstrap-install (~/.deno/bin/deno 不在時のみ公式 installer 実行)
    │   ├── direnv.nix    ← programs.direnv + nix-direnv
    │   ├── env.nix       ← sessionVariables / sessionPath
    │   ├── fzf.nix       ← programs.fzf (default command/options, zsh integration)
    │   ├── gh.nix        ← programs.gh (GitHub CLI)
    │   ├── git.nix       ← programs.git (LFS, alias, difftastic)
    │   ├── herdr.nix     ← herdr の config.toml を mkOutOfStoreSymlink で live edit (mac / 通常 Linux のみ。home-android.nix は import しない)
    │   ├── karabiner.nix ← goku で karabiner.edn → karabiner.json (mac only。home-darwin.nix からのみ import)
    │   ├── mac-app-util-icons.nix ← .app の trampoline アイコン調整 (mac only)
    │   ├── neovim.nix    ← vim/{init.lua,lua,after} を mkOutOfStoreSymlink で live edit
    │   ├── opencode.nix  ← OpenCode 向けの symlink (opencode.json / cli.json / plugins/spark-served.ts / ~/.config/opencode/AGENTS.md) + subagent の Markdown 変換 (syncOpencodeSubagents) + service.json の hostname 上書き (opencodeServiceConfig)
    │   ├── packages.nix  ← home.packages 群 (言語ランタイム / LSP / CLI を 13 カテゴリで宣言、約 100 件。vite-plus / nvtop / libreoffice-bin / scrcpy / android-tools / terminal-notifier / screen-capture-mcp-server / kanary の 8 件は darwin only)
    │   ├── packages-android.nix ← Android 用の明示リスト (19 エントリ。binary cache から取れる軽量なものと、ビルド済みバイナリを展開するだけの opencode)
    │   ├── rustup.nix    ← bootstrap-install (~/.cargo/bin/rustup 不在時のみ公式 installer 実行)
    │   ├── tmux.nix      ← tmux/tmux.conf を mkOutOfStoreSymlink で live edit。plugins.conf のみ Nix 生成 (resurrect + themepack)
    │   ├── vite-plus-bootstrap.nix ← bootstrap-install (~/.vite-plus/bin/vp 不在時のみ公式 installer 実行。Android のみ import)
    │   ├── wezterm.nix   ← wezterm/wezterm.lua を mkOutOfStoreSymlink で live edit (extraConfig は使わない)
    │   └── zsh.nix       ← programs.zsh (history, completion, prompt、homebrew/linuxbrew 分岐済) + shellAliases (drs/hms を OS 別 lib.optionalAttrs。hms の -c には configName が入る)
    └── darwin/
        ├── codex.nix     ← /etc/codex/config.toml を agents/bindings/codex/config.toml へ symlink (environment.etc)
        ├── homebrew.nix  ← declarative brews / casks
        ├── sleepctl.nix  ← 蓋閉じ監視デーモン (disablesleep 中に蓋を閉じたら pmset displaysleepnow を 1 回打つ)
        └── system.nix    ← users, nix.settings, 自動 GC (nix.gc: 日曜 3 時に 14 日より古い世代を削除) + nix.optimise, macOS defaults (キーリピート / trackpad), Touch ID, primaryUser
```

### 重要な設計判断

- **設定の key**: ホスト名は使わない。複数マシンで同じ設定が走る前提。`darwinConfigurations` の key は username (`skanehira`)、`homeConfigurations` の key は `configName` (username にプロファイル接尾辞を足したもの。`skanehira` / `skanehira-aarch64` / `skanehira-android`)。
- **system 値**: darwin は `aarch64-darwin` 固定 (Apple Silicon)。Linux は `skanehira` (x86_64-linux)、`skanehira-aarch64` (aarch64-linux)、`skanehira-android` (aarch64-linux) の 3 出力。
- **モジュール共有**: 「どのツールを入れるか」はプロファイル側の決定である。そのため module の import 一覧は `home.nix` (フルセット) と `home-android.nix` (軽量) がそれぞれ持ち、土台の `home-core.nix` は持たない。`home-darwin.nix` / `home-linux.nix` は `home.nix` に homeDirectory を足す wrapper。mac 専用 module は `karabiner.nix` / `wezterm.nix` / `mac-app-util-icons.nix` / `comfyui.nix` で `home-darwin.nix` からだけ import。`tmux.nix` / `zsh.nix` は内部で `lib.optionalString isDarwin/isLinux` 分岐済。
- **Android を別プロファイルにする理由**: proot は RAM が数 GB で、ストレージも Termux のアプリ内領域に載る。そのため binary cache に無いものをローカルビルドできない。フルセットは完走しないため、`packages-android.nix` に軽量なものを 19 エントリだけ明示列挙する。`programs.git` 等が足す分と HM 内部を含めると、`home.packages` は 34 件になる。規模の差は下表のとおり。neovim は nightly overlay ではなく nixpkgs の stable を使う。

  | プロファイル (aarch64-linux) | ローカルビルド (件) | fetch (件) | ダウンロード | 展開後 |
  | --- | --- | --- | --- | --- |
  | `skanehira-android` | 46 (全て HM の設定生成と wrapper。コンパイルなし) | 325 | 542.4 MiB | 1.9 GiB |
  | `skanehira-aarch64` (フルセット) | 693 (neovim nightly / terraform / herdr 等のコンパイルを含む) | 1545 | 3.5 GiB | 13.0 GiB |

  計測条件: mac (aarch64-darwin) から `nix build --dry-run` を両者連続実行した値で、計測日は「依拠する外部事実」にある。**この表は `opencode` を含まない。** Claude Code / Deno / Vite+ は activation 時に公式インストーラを走らせるので、この数値には含まれない。fetch 件数は実行マシンの nix store に既にある分を除いた値なので、まっさらな端末では増える。
- **overlays の共有**: `modules/overlays-list.nix` が overlay の素のリストを export する。nix-darwin は `modules/overlays.nix` 経由で、HM standalone は `flake.nix` の `import nixpkgs` 経由で、同じリストを参照する。
- **Homebrew**: mac だけで使う。管理するのは GUI app (cask) と、CLI のうち 2 種類だけである。(a) は cask の依存になるコア formula、(b) は nixpkgs 未収録のもの (例: `aqua`) で、それ以外の CLI ツールは Nix 管理。`brews` に明示宣言するのは次のものである。`ca-certificates` / `openssl@3` は保険で、cask 依存リンクが切れた時の巻き添え削除を防ぐ。`python@3.14` は cask `gcloud-cli` の依存で、`aqua` は nixpkgs 未収録の CLI である。`python@3.14` を宣言するのは、cleanup が cask の依存を最新の cask 定義から引くためである。`upgrade = false` なので、導入済みの `gcloud-cli` は古い python を使ったまま残る。定義だけが新しい python へ進むと、使用中の python が削除候補になり、`brew uninstall` に拒否されて `drs` が警告を出す。`gcloud-cli` を upgrade して使う python が変わったら、この宣言も書き換える。`onActivation.cleanup = "uninstall"` で宣言外は drs 時に自動撤去。
- **Touch ID for sudo**: `security.pam.services.sudo_local.touchIdAuth + reattach` で tmux 内含めて指紋認証 (mac only)。
- **CA 証明書のバンドル**: 信頼ストアは 1 つではなく、それぞれ更新手段が違う。認証局の事故 (例: 2026-10 の eMudhra 中間証明書の秘密鍵漏れ、CVE-2026-111943) では全部を確かめる。

  | 信頼ストア | 読むもの | 更新手段 |
  | --- | --- | --- |
  | `/etc/ssl/certs/ca-certificates.crt` (mac) | nix 製の curl / git / openssl | nix-darwin の `security.pki` が nixpkgs の `cacert` から生成する。個別のルートを外すときは `nix/modules/darwin/system.nix` の `security.pki.caCertificateBlacklist` に書いて `drs` |
  | `/etc/ssl/certs/ca-certificates.crt` (Linux / Android) | nix 製の curl / git / openssl、Linux 上の Go 製バイナリ、暫定の `NODE_OPTIONS=--use-openssl-ca` を使う Node 24.22.1 未満 | ディストリの `ca-certificates` パッケージ。`apt install --only-upgrade ca-certificates` を手で流す (HM standalone には `security.pki` が無い) |
  | Homebrew の `ca-certificates` | brew の `python@3.14` / `openssl@3` | `homebrew.nix` が `upgrade = false` なので `drs` では上がらない。`brew upgrade ca-certificates` を手で流す |
  | macOS の Keychain (SecTrust) | Safari、mac 上の Go 製バイナリなど OS の検証を使うアプリ | Apple が OS アップデートを介さずに失効を配る |
  | `/etc/ssl/cert.pem` (Apple 同梱) | Apple の `/usr/bin/curl` / `git` / `python3` / `openssl` など | macOS のアップデートでだけ更新される。失効は確認しないので、Keychain 側で遮断されてもこちらは通る |
  | ランタイムの内蔵ルート | Node (`NODE_OPTIONS` が無いとき)、deno、rustup、Claude Code、uv、pnpm | 各ランタイムの更新。Nix 管理のものは `nix flake update nixpkgs` (mac の Node だけは `nix/pkgs/nodejs-bin.nix` の version を書き換える)、自己更新のものは `deno upgrade` などを手で流す |

  Go の 1.26.10 / 1.27.3 以降は、問題の中間証明書を含むチェーンを OS を問わず拒否する。ただし効くのはその版でビルドしたバイナリだけである。

  `system.nix` の `caCertificateBlacklist` には `Comodo AAA Services root` の 1 件だけを書く。`cacert` の cert store に無い名前を書くと buildcatrust が失敗するので、NSS 3.131.1 で削除された emSign の 3 ルートは書かない。nix-darwin は commit `97fd0908` 以降 (nix-darwin #1876 とその修正) この 1 件を自身で外すので、`nix/flake.lock` の `nix-darwin` がそれ以降になったら消してよい。mac の Node は `nix/pkgs/nodejs-bin.nix` で 24.22.1 の公式版を使い、内蔵 CA で検証する。`env.nix` の `NODE_OPTIONS=--use-openssl-ca` は Linux の `nodejs_24` が 24.22.1 未満の間だけ設定される。mac ではこのフラグを設定しない。Claude Code がフラグを検出すると内蔵 CA を使わず `system` のみを選び、macOS 標準のシステムルートを読み込めずに認証が失敗するためである。適用前から開いているシェルには環境変数が残るので、mac で更新を適用した後は `unset NODE_OPTIONS` を実行してから Claude Code を起動する。activation の bootstrap curl (`deno.nix` / `rustup.nix` / `claude.nix` / `vite-plus-bootstrap.nix`) は、`NIX_SSL_CERT_FILE` で上表 1・2 行目のバンドルを明示する。明示しないと、更新されない root profile (`/nix/var/nix/profiles/default`) のバンドルを読むためである。

## sudo の扱い (重要)

このマシンでは `pam_tid` (Touch ID) + `pam_reattach` (tmux 対応) が `/etc/pam.d/sudo_local` に設定済み。

### `sudo -n` (`--non-interactive`) は使わない

`-n` フラグは対話入力を禁止する。この環境で新たな Touch ID 認証が必要な場面では、認証を開始できず「a password is required」で失敗する。資格情報キャッシュが有効な場合など、認証が不要なら成功することもある。認証が必要な操作も実行できるよう、`sudo` に `-n` は付けない。

```bash
# ❌ 新たな Touch ID 認証が必要な場合に失敗する
sudo -n darwin-rebuild switch ...

# ✅ 認証が必要な場合は Touch ID ダイアログで認証できる
sudo darwin-rebuild switch ...
```

スクリプトや Claude Code の Bash ツールから `sudo` を呼ぶときも同様。`-n` を付けなければ、認証が必要なときに、このマシンの PAM 設定が Touch ID ダイアログを表示できる。

## Nix daemon のトラブルシュート (macOS)

`drs` が下記で即落ちする場合、`nix-daemon` (launchd) が落ちている。

```text
error: cannot connect to socket at '/nix/var/nix/daemon-socket/socket': Connection refused
```

### 状態確認

```bash
# nix-daemon が launchctl にロードされているか (PID が出ていれば起動中)
sudo launchctl list | grep org.nixos.nix-daemon

# daemon 経由で nix store に疎通するか
nix store info
```

`sudo launchctl list` に `org.nixos.nix-daemon` の行が無い、または PID 列が `-` ならデーモンは未起動。

### 復旧手順

```bash
sudo launchctl load /Library/LaunchDaemons/org.nixos.nix-daemon.plist
```

ロード後、再度 `sudo launchctl list | grep nix-daemon` で PID が振られていれば OK。`drs` をリトライできる。

### 補足

- plist 本体は **nix-darwin の所有物**で、`activate-system` が `/Library/LaunchDaemons/org.nixos.nix-daemon.plist` へ配置する。`/run/current-system/Library/LaunchDaemons/` 配下の同名ファイルと `cmp` でバイト一致することで確認できる。よって `drs` を通せば内容は宣言どおりに戻る。
- 一度 `load` すれば再起動後も自動起動する想定。再発する場合は plist の `KeepAlive` が無効化されていないか、`nix-darwin` 側で `nix.enable = false` 相当の設定が混入していないか (`nix/modules/darwin/system.nix`) を確認する。

## Neovim Configuration

### Structure

- `vim/lua/plugins/` — lazy.nvim プラグイン設定
- `vim/lua/settings/` — 基本設定 (options.lua, keymaps.lua, lsp.lua, autocmd.lua, disable.lua)
- `vim/lua/modules/` — カスタムモジュール (AI, markdown)
- `vim/after/lsp/` — LSP 個別設定 (denols, rust_analyzer, lua_ls, nixd, tsc, version_ls, yamlls)

### Key Paths

- ghq リポジトリ: `$HOME/dev`
- Go バイナリ: `$HOME/go/bin`
- Deno バイナリ: `$HOME/.deno/bin`

### Neovim 本体

フルセット (mac / 通常 Linux) は `neovim-nightly-overlay` の **nightly ビルド**を使う。binary cache が無く更新時は手元でビルドする。アップデートは `nix flake update neovim-nightly-overlay`。

Android プロファイルだけは `pkgs.neovim` (nixpkgs-unstable の **stable release**、`cache.nixos.org` 経由でビルド済) を使う。proot で nightly をビルドできないため。こちらのアップデートは `nix flake update nixpkgs`。

## Claude Code を DeepSeek 本家 API で使う (`ccds`)

`zsh/functions/claude-deepseek.zsh` の `ccds` は、`agents/bindings/claude/settings.deepseek.json` を `--settings` で渡して `claude` を起動する。接続先は `https://api.deepseek.com/anthropic`、effort は `max` である。設定ファイルは `$GHQ_ROOT/github.com/skanehira/dotfiles` から直接読むため、編集は次の起動から効く。関数本体の編集は `drs` / `hms` と新しいシェルが要る。

```bash
ccds                     # DeepSeek 本家 API で Claude Code を起動
ccds -p "README を要約して"  # 引数をそのまま claude へ渡す
ccds off                 # Anthropic 用へ戻す
```

トークンが未設定のときは、1Password の `op://Personal/DeepSeek API Key/credential` から取得して `ANTHROPIC_AUTH_TOKEN` に export する (`op signin` 済みであること)。空でない値が既にあれば取得を飛ばすため、別の API のトークンを残したシェルでは先に解除する。設定ファイルが無い、またはキー取得が失敗した場合は起動せず終了する。

同じシェルで再起動できるよう `claude` の alias が残る。alias とトークンの変更は他の既存シェルに影響しない。export したトークンは子プロセスへ渡るが alias は渡らないため、子シェルからも `ccds` を使う。`ccds off` は `ANTHROPIC_AUTH_TOKEN` / `ANTHROPIC_BASE_URL` と alias を解除するが、実行中の Claude Code は停止しない。第 1 引数の `off` 以外は Claude Code に渡り、`off` の後ろの引数は使わない。

`settings.deepseek.json` は `security-guidance@claude-plugins-official` を無効にしている。Stop hook が DeepSeek 本家で配信していない Opus を要求するためである。

## AI エージェントのハーネス (agents/)

グローバル指示・ルール・スキル・subagent の正本は `agents/` に 1 セットだけ置き、**3 ランタイムが同じ実体を読む**。Claude Code は正本への symlink を読む。Codex と OpenCode も同じ symlink 先を読み、Claude 綴りの語彙を自分の語彙へ**読み替える** (`agents/bindings/codex/AGENTS.md` / `agents/bindings/opencode/AGENTS.md` の読み替え表)。例外は subagent だけで、Codex は TOML を、OpenCode は別スキーマの Markdown を要求するため、書式変換したものを配る。

```text
agents/
├── AGENTS.md            ← グローバル指示の正本 (`~/.claude/CLAUDE.md` へ symlink)
├── guidelines/          ← core/ backend/ frontend/ infra/ (起動時には自動で読まれない。グローバル指示が Read を指示する)
├── skills/              ← 52 本 (git 管理分。16 本は外部からの vendor で、wondelai/skills の 11 本、openai/skills の 2 本、ayghri/i-have-adhd・nanaism/yomiyasu・cloudflare/security-audit-skill の各 1 本。出典は `LICENSE-wondelai` / `LICENSE-yomiyasu` / `LICENSE-cloudflare`、openai の 2 本は各ディレクトリの `LICENSE.txt`、i-have-adhd は `SKILL.md` の frontmatter。配布除外は →「スキルの配布先の限定」節)
├── subagents/           ← 4 本 (Claude Code 形式が正本。Codex / OpenCode へは書式変換して配る)
├── hooks/               ← herdr-agent-state.sh のみ (herdr 本体の配布物。自作ゲートは無い)
├── scripts/             ← sync-subagents.ts (Codex / OpenCode への書式変換) / subagent-format.ts / mutate-check.ts ほか
├── knowledge-profile.md ← utility-doc-reading が読み書きする
└── bindings/            ← ランタイム固有
    ├── claude/          ← settings.json / keybindings.json / settings.deepseek.json
    ├── codex/           ← AGENTS.md (Codex のグローバル指示) / config.toml
    └── opencode/        ← AGENTS.md (OpenCode のグローバル指示) / opencode.json (Spark provider) / plugins/spark-served.ts (配信中モデルの選択) / cli.json (TUI 設定)
```

### 配布先

| 要素 | Claude Code | Codex | OpenCode | 方式 |
| --- | --- | --- | --- | --- |
| グローバル指示 | `~/.claude/CLAUDE.md` ← `agents/AGENTS.md` | `~/.codex/AGENTS.md` ← `agents/bindings/codex/AGENTS.md` | `~/.config/opencode/AGENTS.md` ← `agents/bindings/opencode/AGENTS.md` | symlink (live edit) |
| ルール | `~/.claude/guidelines/` ← `agents/guidelines/` | `~/.claude/guidelines/` を絶対パスで直接 Read | 同左 | symlink (live edit) |
| スキル | `~/.claude/skills/` ← `agents/skills/` | `~/.agents/skills/<name>` ← `agents/skills/<name>` (個別 symlink) | `~/.agents/skills/` (Codex と共有) と `~/.claude/skills/` の両方を読む | symlink (`~/.agents/skills` 側の追加・削除は `drs` / `hms`) |
| subagent | `~/.claude/agents/` ← `agents/subagents/` | `~/.codex/agents/*.toml` (書式変換) | `~/.config/opencode/agents/*.md` (書式変換) | symlink (Claude 以外は `drs` / `hms`) |
| `scripts/` | `~/.claude/scripts` ← `agents/scripts/` | 同じパスをそのまま実行する (同一実体) | 同左 | symlink (live edit) |
| `knowledge-profile.md` | `~/.claude/knowledge-profile.md` ← `agents/knowledge-profile.md` | 同じパスをそのまま読み書きする (同一実体) | 同左 | symlink (live edit) |
| `hooks/` | `~/.claude/hooks` ← `agents/hooks/` | **配布しない** (Codex の hook は `~/.codex/hooks.json` と `config.toml` とプラグイン。所在と件数は `agents/bindings/codex/AGENTS.md`「hooks は Codex には配られていない」節) | **配布しない** (シェル hooks を持たない) | symlink (live edit) |
| Claude 固有の設定 | `~/.claude/settings.json` / `keybindings.json` ← `agents/bindings/claude/` | 配布しない | 配布しない | symlink (live edit) |
| Codex 共通設定 | 読まない | `/etc/codex/config.toml` ← `agents/bindings/codex/config.toml` | 読まない | symlink (mac は `environment.etc`、Linux は activation `linkCodexSystemConfig`) |
| OpenCode 固有の設定 | 読まない | 読まない | `~/.config/opencode/{opencode.json,cli.json,plugins/spark-served.ts}` ← `agents/bindings/opencode/` | symlink (live edit) |

**Codex は skill root を 2 つ持つ。** `r0` = `~/.codex/skills` と `r1` = `~/.agents/skills` で、どちらも symlink のスキルフォルダを追跡する。共有に `r1` を使うのは、`~/.agents/skills` に他ツールが入れたスキル (例: `find-skills`。種類と本数はマシンによって違う) が同居するためである。ディレクトリごとの symlink は使えないので、1 スキルずつ張る。

**`~/.codex/skills` は配布先ではない。** ここに dotfiles 由来の実体があると、同名スキルが `r0` と `r1` に二重に列挙される。`.system` と plugin 由来のものは Codex の所有物で、他ツール (`wrangler login` 等) が入れたものはそのツールの所有物である。どちらも触らない。

**OpenCode は `~/.agents/skills` と `~/.claude/skills` の両方を読む。** OpenCode (V2) のスキル探索先は `~/.config/opencode/{skill,skills}` / `~/.claude/skills` / `~/.agents/skills` で、プロジェクトの `.opencode` / `.claude` / `.agents` の下も探す。どこでも symlink を追跡する。スキルの識別子は `SKILL.md` の親ディレクトリ名で、スキル置き場の直下にある `*.md` はファイル名になる。同じ識別子は 1 つにまとまるので、同じ実体が 2 経路から見えても二重には並ばない。`~/.claude/skills` 側だけを読まない設定は V2 に無い。そのため除外リスト `claude_only_skills` は OpenCode には効かない (→「スキルの配布先の限定」節)。Android は `~/.agents/skills` が埋まらないので、`~/.claude/skills` からだけ読む。

**OpenCode の一覧は、常駐サービスの起動直後に欠けて返る。** スキルの一覧 (`opencode api skill.list`) は 0 件のように返り、subagent の一覧 (`opencode debug agents`) は組み込みのエージェントだけを返すことがある。件数が落ち着くのを待っても判定できない。期待する名前が現れるまで 2 秒おきに最大 10 回繰り返し、10 回で現れなければ配布の失敗として扱う。手順は `agents/bindings/opencode/AGENTS.md` の確認コマンドにある。

- **スキル**: `jq -r '.data[].name'` に `dev-impl` が現れるかを見る。件数は `opencode api skill.list > /tmp/s.json && jq '.data | length' /tmp/s.json` で見る。出力は 700KB を超えるので、**パイプに直結せずファイルに落とす** (パイプだと途中で切れる)
- **subagent**: `opencode debug agents` は組み込みのエージェントも出すので、件数では判定できない。正本 `agents/subagents/*.md` の名前が全て id に揃うかを見る

**OpenCode が自動で読むグローバル指示は `~/.config/opencode/AGENTS.md` だけである。** V2 は `~/.claude/CLAUDE.md` へのフォールバックを持たない。したがって `agents/bindings/opencode/AGENTS.md` には、「共通の正本 `~/.claude/CLAUDE.md` を自分で Read せよ」と書いてある。Codex も同じで、自分の `~/.codex/AGENTS.md` しか自動では読まない。どちらも binding に Read 指示を書いておかないと、共通ハーネスが届かない。

### subagent の書式変換 (agents/scripts/sync-subagents.ts)

subagent は 3 者で唯一**書式変換が避けられない**要素である。Claude は Markdown + frontmatter、Codex は TOML、OpenCode は `description` / `mode` だけの別スキーマ Markdown を読む。`agents/scripts/sync-subagents.ts` が `agents/subagents/*.md` を各形式へ書き、変換元が消えた生成物は prune する。変換そのもの (frontmatter の parse と各形式の生成) は `agents/scripts/subagent-format.ts` が持つ。

`drs` / `hms` の activation `syncCodexSubagents` / `syncOpencodeSubagents` が呼ぶ (activation は `deno run` 経由)。手で流し直すときは次の 2 本 (shebang 付きで実行ビットが立っている)。第 3 引数が形式で、省略すると `codex` になる。

```bash
./agents/scripts/sync-subagents.ts agents/subagents ~/.codex/agents
./agents/scripts/sync-subagents.ts agents/subagents ~/.config/opencode/agents opencode
```

| 形式 | 出力 | 出すキー | prune の目印 |
| --- | --- | --- | --- |
| `codex` | `<name>.toml` | `name` / `description` / `developer_instructions` | 先頭が `# generated by ...` |
| `opencode` | `<name>.md` | `description` / `mode: subagent` | 先頭が `---` + `# generated by ...` |

- **prune の対象**: 上表の目印を持つファイルだけ。他ツールが置いたものは残る。出力ディレクトリを共有しても形式ごとに拡張子が違うので互いを消さない
- **OpenCode で `name` を出さない理由**: OpenCode は subagent 名をファイルパスから決める。正本の `name` をファイル名にするので、識別は保たれる。生成物が `opencode debug agents` に出るかの確かめ方は「配布先」節の「OpenCode の一覧」にある
- **OpenCode の description を double-quoted にする理由**: 正本の description にコロンを含むものがある (`dev-impl-implementer` の「`mode: implement` で新規実装」)。無引用の YAML プレーンスカラーだと 2 つ目のキーとして解釈されて壊れる
- **deno が無いとき**: 警告してスキップし activation は成功する (前回の生成物が残る)
- **失敗の見え方**: frontmatter の `name` / `description` 欠落、本文に `'''` を含む場合 (Codex のみ) は exit 1 で `drs` / `hms` ごと止まる

テストはこう回す。CI では回していないので、`agents/scripts/` か `agents/bindings/opencode/` (プラグインとそのテスト) を触ったら自分で実行する。

```bash
deno test --allow-env --allow-run --allow-read --allow-write agents/
```

dev-spec と dev-impl の skill に置いたスクリプトは、deno ではなく POSIX の sh と awk で書く。対象は `agents/skills/dev-spec/scripts/` (issue 作成・依存の段数) と `agents/skills/dev-impl/scripts/` (着手順・CI 待ちと merge・追加したコメント行の抽出) である。研修のプラグインで、deno の無い受講者の PC (macOS と Ubuntu) にも配るためである。触ったら、macOS の awk・GNU awk・dash と、docker の Ubuntu (dash と mawk) でテストを回す。`SH=dash` を付けると、テストが呼ぶスクリプトも dash で動く (付けないと macOS では `sh` = bash で動く)。テストは偽の gh (`tests/fake/gh` と、merge のテスト用の `tests/fake/gh-merge`) を使い、`gh` が偽物を指していなければ何もせずに止まる。

```bash
for t in agents/skills/dev-spec/scripts/tests/*_test.sh agents/skills/dev-impl/scripts/tests/*_test.sh; do
  sh "$t" </dev/null; SH=dash dash "$t" </dev/null
  mkdir -p /tmp/bsdawk && ln -sf /usr/bin/awk /tmp/bsdawk/awk && PATH=/tmp/bsdawk:$PATH sh "$t" </dev/null
done
docker run --rm -v "$PWD/agents/skills":/skills:ro ubuntu:24.04 sh -c 'apt-get update -qq && apt-get install -y -qq git >/dev/null && cd /tmp && for t in /skills/*/scripts/tests/*_test.sh; do sh "$t" </dev/null; done'
shellcheck -x -P SCRIPTDIR -s sh agents/skills/dev-spec/scripts/*.sh agents/skills/dev-spec/scripts/tests/*.sh agents/skills/dev-impl/scripts/*.sh agents/skills/dev-impl/scripts/tests/*.sh agents/skills/dev-impl/scripts/tests/fake/gh-merge
```

### スキルの配布先の限定 (`~/.agents/skills` への配布から除外)

スキルは既定で 3 ランタイムへ配られる (同じ実体への symlink)。`~/.agents/skills` へ配らないものは `nix/modules/home/codex.nix` の `claude_only_skills` に列挙する。変数名は「Claude Code だけに残す」だが、**実際に除外が効くのは Codex だけ**である。**このリストが除外の唯一の正**で、現在の宣言は 2 件。`agents/skills/` にある git 管理のスキル 52 本のうち除外は 1 本で、もう 1 件はスキルではなく未追跡の同期キャッシュ。

除外の効く先は `~/.agents/skills` なので Codex からは消える。**OpenCode からは消えない** (OpenCode は `~/.claude/skills` も読み、そこには残っているため)。OpenCode で除外する手段は V2 に無い。

| 名前 | 除外する理由 |
| --- | --- |
| `utility-session-profile` | Claude Code のセッションログ (`~/.claude/projects/` 配下の `*.jsonl`) しか読まない |
| `synced` | Claude Code が marketplace から同期するキャッシュ。直下に `SKILL.md` が無く Codex のスキルとして機能しない (→「live edit の範囲」の第三者書き込みの行)。OpenCode は `~/.claude/skills/synced/<uuid>/<name>/SKILL.md` の 10 本を個別のスキルとして読む |

- **除外の単位**: スキルのディレクトリ単位。`references/` や `scripts/` だけが取り残されることはない
- **反映**: activation `linkAgentSkills` が `drs` / `hms` で走る。`~/.agents/skills` の symlink が撤去され、Claude 側には残る
- **他ツールの同居**: `~/.agents/skills` に同名の実体があるときは symlink を張らず警告する (`ln -sfn` は既存ディレクトリの中にリンクを作ってしまうため)。手で退避してから再実行する
- **`SKILL.md` の frontmatter では宣言しない**: 配布は nix の activation が行うので、frontmatter に書いても読む側が無い

### live edit の範囲

**正本への symlink で配る本文は、`drs` / `hms` を待たずに反映される。** 例外は下表のスキルの追加・削除 (Codex) と subagent (Codex と OpenCode) の 2 行である。個別の symlink か書式変換を挟むので、`drs` / `hms` が要る。Claude Code はどちらも正本のディレクトリを直接参照する。

| 対象 | 反映 | 理由 |
| --- | --- | --- |
| `AGENTS.md` / `guidelines/` / `skills/` の本文 | 即反映 (3 ランタイムとも) | 正本への symlink |
| `hooks/` `scripts/` `knowledge-profile.md` | 即反映 | 正本への symlink (`knowledge-profile.md` は `utility-doc-reading` が書き込む) |
| `bindings/claude/settings.json` `keybindings.json` / `bindings/codex/AGENTS.md` `config.toml` / `bindings/opencode/AGENTS.md` `opencode.json` `cli.json` `plugins/spark-served.ts` | 即反映 | 正本への symlink。OpenCode の常駐サービスが変更を読み直すことと、`cli.json` が TUI で設定を変えると symlink でなくなることは、Directory Structure の `agents/bindings/opencode/` 項にある |
| スキルの追加・削除 | Claude と OpenCode は即反映 / **Codex は `drs` / `hms`** | `~/.claude/skills` がディレクトリごとの symlink で、OpenCode もここを読む。Codex は `~/.agents/skills/<name>` を 1 本ずつ張り直す activation (`linkAgentSkills`) が要る |
| subagent の本文・frontmatter の変更、追加・削除 | Claude は即反映 / **Codex と OpenCode は `drs` / `hms`** | Claude は `~/.claude/agents` がディレクトリごとの symlink。Codex は `~/.codex/agents/*.toml`、OpenCode は `~/.config/opencode/agents/*.md` の再変換・prune (`syncCodexSubagents` / `syncOpencodeSubagents`) が要る |
| `~/.claude/skills/` への第三者の書き込み | 即反映 (副作用あり) | 正本への symlink なので、他ツールが置いたディレクトリは dotfiles の `agents/skills/` (git 作業ツリー) に落ちる。**新たに増えたら sink を 2 つとも判断する**: commit するか (`.gitignore`) と `~/.agents/skills` へ配るか (`claude_only_skills`)。Claude Code の同期キャッシュ `synced` は両方で外してある |

### 開発ワークフローのスキル

```text
/dev-spec (設計ループ) → 承認ゲート (人間が起動) → /dev-impl (実装ループ)
```

どのスキルも人が手元で起動する。`agent-loop` に登録したリポジトリでは、`/dev-spec` が作った `ready` の子の issue を、次の見回りで `/dev-impl` が実装し始める。そのため承認ゲートは「issue の作成に同意する時点」になる (→「AI が issue を進める開発フロー (agent-loop)」)。

詳細は `agents/skills/README.md` を参照 (タスク規模別の入口・モデル方針を含む)。主要スキル:
- `/dev-spec` — 設計ループ (ユーザーストーリー → ... → PoC 検証 → `docs/design/DESIGN.md` 1 枚 + `docs/design/features/` → GitHub issue をユースケース単位の親子 2 階層で生成 → 人間が確認)
- `/dev-impl` — 実装ループ (`ready` ラベルの open issue を、依存を守ってスコアの高い順に自律実装、`model: opus`)
- `/dev-impl-quick` — 軽量実装ループ (docs 不要。依頼文をタスク分解して直営 TDD → review-impl → タスク単位コミット)
- `/workflow-review` (レビュー) / `/workflow-commit` (コミット) / `/workflow-create-pr` (PR 作成。`--draft` で Draft) / `/workflow-debate` (壁打ち)

### AI が issue を進める開発フロー (agent-loop)

機能追加とバグ修正は、人が issue を作り、設計を確認するだけで進む。整理・設計・実装・merge は、`agent-loop` が起動する Claude Code が行う。Deploy は人が行う。決定の台帳は `docs/DESIGN_NOTES.md` にある。

全体の構成は次のとおり。状態の正本は issue のラベルで、スキルはラベルだけを読み書きする。Project のボードは人が見るためのもので、Actions がラベルに合わせて動かす。

```text
[このマシン] agent-loop を入れた mac 1 台
│
├─ launchd (local.agent-loop) が 30 分おきに agents/scripts/agent-loop.ts を動かす (LLM を使わない)
│    1. ~/.config/agent-loop/repos.yaml のリポジトリごとに、gh で仕事を探す
│         triage: 状態のラベルが無い issue           → /dev-triage
│         design: needs-design で設計 PR が無い issue → /dev-feat-spec
│         impl  : ready か in-progress の issue       → /dev-impl
│                 (動いている Claude Code が担当の印を持つ issue は数えない)
│    2. 種類ごとに 1 つだけ起動する (前回と入力が同じなら起動しない。6 時間経てば 1 回だけ起動し直す)
│         claude --bg --worktree <名前> --model opus --permission-mode bypassPermissions "/dev-…"
│    3. 終わった run を片付ける
│         done             → 会話と worktree を消す (worktree に未保存の作業があれば残す)
│         それ以外か、needs-human の印がある → 残す (claude attach <id> で開ける)
│         残した run の PR がすべて merge か close されたら → worktree だけを消す (会話は残す)
│    4. done 以外の終わり方と、見回りの中断を通知センターに出す (terminal-notifier)
│
└─ Claude Code のバックグラウンド run (<clone>/.claude/worktrees/<名前> で動く)
     /dev-triage    採点して ## 優先度 を書き、状態のラベルを付ける
     /dev-feat-spec 設計 PR か修正方針を出す
     /dev-impl      実装して PR を merge し、issue を close する (worktree で最大 3 並列)
     人の判断が要るときは needs-human を付け、コメントに claude attach <id> を載せる
          │
          │ gh でラベル・コメント・PR を読み書きする
          ▼
[GitHub] 対象のリポジトリ
│
├─ issue のラベル (状態の正本)
│    なし (未整理) ── /dev-triage ──┬─▶ tracking     (親。子が全部閉じたら /dev-impl が close)
│                                   ├─▶ needs-human  (人が答え、コメントに書かれた状態へ戻す)
│                                   └─▶ needs-design
│    needs-design ── /dev-feat-spec ──▶ design-review (判断が要るものは needs-human)
│    design-review ── 人が設計 PR を merge (Actions が ready を付ける)
│                     か、修正方針を読んで人が ready を付ける ──▶ ready
│    ready ── /dev-impl ──▶ in-progress ──▶ close
│
├─ Actions (/dev-project-setup が置く)
│    issue-state-sync.yml : ラベルに合わせて Project の Status を動かす。close で「完了」
│    design-approved.yml  : Design-for: #N の設計 PR が merge されたら、その issue に ready を付ける
│
└─ Project (非公開のボード。issue だけを載せる。人が状況を見るためのもの)

[人]
  issue を作る / needs-human に答える / 設計 PR を merge する / Deploy する
  見る: 通知、claude agents、claude attach <id>、issue のコメント、Project のボード
  急ぐときや agent-loop の外で使うときは、スキルを手元で起動する (下の「手元で起動する」)
```

| 状態のラベル | 次に動くもの | 状態の定義の正本 |
| --- | --- | --- |
| なし (未整理) | `/dev-triage` | `agents/skills/dev-triage/references/issue-states.md` |
| `needs-design` | `/dev-feat-spec` | 同上 |
| `design-review` / `needs-human` | 人 | 同上 |
| `ready` / `in-progress` | `/dev-impl` | 同上 |

- **リポジトリの準備**: `/dev-project-setup` がラベル・Project・Actions 2 本・`AGENTS.md` の運用の節を用意する。優先度などの定義は dev-triage の references にあり、プロジェクト固有の定義があるときだけ `docs/ISSUE_TRIAGE.md` を置く
- **agent-loop の動き**: launchd のユーザー用エージェント (`local.agent-loop`) が 30 分おきに `agents/scripts/agent-loop.ts` を動かす (急ぐときは、人がスキルを手元で起動する)。スクリプトは LLM を使わず、`~/.config/agent-loop/repos.yaml` の各リポジトリで仕事を探し、種類ごとに `claude --bg --worktree <名前> --model opus --permission-mode bypassPermissions "/dev-triage"` のように起動する。同じリポジトリの同じ種類は同時に 1 つだけで、前回の run と入力が同じなら起動しない (6 時間経てば 1 回だけ起動し直す)。仕組みの詳細はスクリプトの冒頭にある
- **対象のリポジトリの追加**: `~/.config/agent-loop/repos.yaml` に足す (書式は `agents/scripts/agent-loop.repos.example.yaml`)。このファイルは dotfiles の外にあり、git 管理しない (業務のリポジトリの名前が入るため)。clone は Claude Code の trust を受け入れ済みであること
- **知らせ**: run が `done` 以外 (`blocked` / `failed` / `stopped` / `error`) で終わったときと、見回りが中断・停止したときは、mac の通知センターに通知が出る (`terminal-notifier`)。run の通知の本文に、その run の会話を開くコマンド (`claude attach <id>`) が載る。通知が出ないときは、システム設定 → 通知 で terminal-notifier を許可する (通知を出せなかったことは、見回りのログに残る)
- **見る**: `claude agents` (一覧)、`claude attach <名前>` (動いている画面)、`claude logs <名前>`。見回りのログは `~/.local/state/agent-loop/agent-loop.log` と `~/Library/Logs/agent-loop.log`、状態は `~/.local/state/agent-loop/state.json`
- **入れる・止める**: agent-loop は動かすマシンを 1 台に限るので、nix では配らない。入れるのは `./agents/scripts/agent-loop-install.sh` (plist を書いて読み込む。何度実行してもよい)、外すのは `./agents/scripts/agent-loop-install.sh --uninstall`。一時的に止めるのは `launchctl bootout gui/$(id -u)/local.agent-loop`、再開は `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.agent-loop.plist`。動いているセッションは `claude stop <id>`。1 つのリポジトリだけ外すときは `repos.yaml` から消す
- **手元で起動する**: スキルは agent-loop に依存しないので、対象のリポジトリの clone で人が 1 つずつ起動できる。agent-loop は定期的に起動する役を代わるだけで、ラベルと Actions (`/dev-project-setup` が置く) があれば、agent-loop に登録していないリポジトリでも同じ流れで進む
  - `/dev-triage [issue 番号]` / `/dev-feat-spec [issue 番号]` / `/dev-impl [issue 番号]`: 次の見回りを待たずに進めたいとき。番号を渡すと、その issue だけを扱う (`/dev-impl` は未完了の依存先も含める)
  - `/dev-feat-spec <PR 番号>`: 設計 PR への指摘を伝えて直させる。人が手元で起動するときだけ使い、agent-loop は起動しない
  - `/dev-spec`: 新規プロダクトや大きい機能を、ユーザーストーリーから対話で設計して issue に落とす。agent-loop は起動しない。作った子の issue には `ready` が付くので、agent-loop に登録したリポジトリでは次の見回り (30 分以内) で `/dev-impl` が実装を始める。issue を読んでから実装させたいときは、それまで agent-loop を止めておく
  - `/dev-impl` は、手元と agent-loop で同時に動かしてよい: `/dev-impl` は着手した issue に担当の印 (clone の共通の git ディレクトリの `dev-impl-claims/<番号>`。Claude Code のプロセスの pid とセッション ID) を残し、merge で消す。駐車しても消さない。agent-loop と別の `/dev-impl` は、印の持ち主の Claude Code が動いている issue を拾わない (`agents/skills/dev-impl/SKILL.md` Step 1「担当の印」)。Claude Code の外から `/dev-impl` を動かすと印を書けないので、そのときは agent-loop を一時的に止める (上の「入れる・止める」)
  - `/dev-triage` と `/dev-feat-spec` は同時に動かさない: agent-loop は、これらについては自分が起動した run しか見ない。手元と agent-loop で同時に動かすと、同じ issue を取り合う。手元で起動する前に `claude agents` で同じリポジトリの run が動いていないかを確かめ、動かしている間は agent-loop を一時的に止める
- **手で 1 回動かす**: `./agents/scripts/agent-loop.ts --dry-run` で、起動せずに判定だけを見られる
- **残った会話と worktree**: `agent-loop` は、次の 2 つのときに会話と worktree を残し、`<名前> は <状態> で終わった。会話と worktree を残す (claude attach <id>)` をログに書く。1 つは run が `done` 以外 (`blocked` / `failed` / `stopped`) で終わったときである。`blocked` は人の返事を待って止まった状態で、最終報告での質問のほか、subagent の Bash の権限確認でも起きる。もう 1 つは、run が `needs-human` のコメントに `claude attach <id>` を載せたとき (`~/.claude/jobs/<id>/needs-human` の印がある) である。`done` でも、worktree に未保存の作業がある (追跡中のファイルの変更・push していない HEAD・中に残った worktree) と残す。残した run は状態の `kept` に記録し、見回りのたびに、その run の PR がすべて merge か close されたかを確かめる。そうなっていて worktree に未保存の作業が無ければ、worktree と `worktree-<名前>` のブランチを消し、`<名前> の PR がすべて merge か close されたので、worktree を消した` をログに書く。会話は消さない。run の PR は、Claude Code がジョブのディレクトリに書く `~/.claude/jobs/<id>/state.json` の `children` から、対象のリポジトリのものだけを読む。これは会話に出てきた PR のリンクも含むので、関係の無い open の PR があると消すのが遅れる。PR を 1 つも作らずに止まった run と、この記録を読めない run は残したままにする (公式に安定した形ではないので、読めなければ消さない)。読み終えたら、`claude rm <id>` で消す。worktree が残るときは、`git -C <clone> worktree remove --force <clone>/.claude/worktrees/<名前>` と `git -C <clone> branch -D worktree-<名前>` で片付けてから、もう一度 `claude rm <id>` する (`claude rm` は、フックが作った worktree を消さずに `kept` と出して終わるため)。止まった impl の run の中に残った `issue-<N>` の worktree は、次の `/dev-impl` が、担当の印の持ち主の Claude Code が動いていないことを確かめてから、未コミットの差分ごと引き継ぐ (`agents/skills/dev-impl/SKILL.md` Step 1)

### hooks (agents/hooks/)

**deny する自作 hook は 1 本も無い。** `agents/hooks/` に置いてあるのは herdr 本体が配布する `herdr-agent-state.sh` の 1 本だけで、これは deny するゲートではなく herdr へセッション状態を渡すスクリプトである。

hook 以外の機械的な強制は 1 つだけ残っている。`agents/subagents/dev-impl-implementer.md` の `tools` から `Agent` を除いて**葉性を構造的に強制**している (subagent には親の hooks が届かず、指示文では違反を検出できないため)。

| ファイル | 起動元 | 役割 |
| --- | --- | --- |
| `herdr-agent-state.sh` | Claude Code の `settings.json` の SessionStart (`~/.claude/hooks/` 経由) | herdr にセッション状態を渡す。herdr 本体が配布するファイル。`settings.json` 側の登録は mac の絶対パス (`bash '/Users/skanehira/.claude/hooks/herdr-agent-state.sh' session`) で書かれ、OS の条件が無い。そのため Linux でも SessionStart で起動されるが、そのパスにファイルが無く bash が失敗する |

`~/.claude/hooks` の symlink はこの 1 本のためだけにある。ディレクトリごと消すと herdr の SessionStart が絶対パスで参照できなくなる。

**deny する自作ゲートは 3 ランタイムのどれにも配っていない。**自分で書いた hook として Claude Code に配っているのは上表の herdr 連携 1 本だけである。Codex は移植すべきものが無く、OpenCode はそもそもシェル hooks を持たない (根拠は `agents/bindings/opencode/AGENTS.md`「hooks は OpenCode では動かない」節)。

**プラグイン由来の hook はこれとは別にある。** compact-plus が Claude Code に 6 件 (1.0.4 の場合。UserPromptSubmit 2 / PreCompact 2 / PostCompact 1 / SessionStart 1)、Codex に 7 件 (1.3.2 の場合。SessionStart が 2 件になる) を登録する (Claude 側は `agents/bindings/claude/settings.json` の `enabledPlugins`、Codex 側は `codex.nix` の activation が入れる)。どちらもコンパクション補助で deny するゲートではないが、「hook が 1 件も無い」わけではない。

hook を追加したくなったときの置き場は次のとおり。

| ランタイム | 置き場 |
| --- | --- |
| Claude Code | スクリプトを `agents/hooks/` に置き、`agents/bindings/claude/settings.json` の `hooks` に `$GHQ_ROOT` 経由の絶対パスで登録する。`~/.claude/hooks` の symlink は経由しない (`GHQ_ROOT` は `nix/modules/home/env.nix` が `$HOME/dev` に設定する) |
| Codex | `agents/bindings/codex/config.toml`。レイヤーごとの発火差は `agents/bindings/codex/AGENTS.md` の「hooks を追加するときの置き場」節にある |
| OpenCode | **置けない**。シェル hooks を持たず、JS プラグイン API はコマンドに stdin を渡さず stdout も解釈しないので deny するゲートにならない |

`settings.json` の `hooks` に登録しているのは上表の herdr 連携 1 件だけである。`settings.json` は正本への symlink なので、外部ツールが `~/.claude/settings.json` へ hook を書き込むと、その変更は dotfiles の git 作業ツリーに差分として現れる。見覚えのない登録が増えていたら、commit する前に書き込んだツールを特定して残すかを決める。

#### 機械ゲートを置いていない規律

以下は hook で強制せず、記述による自律遵守に委ねている。**破っても止まらないことを承知したうえでの設計判断**であり、設計思想は `agents/guidelines/core/references/loop-engineering.md` にある。

| 規律 | 正本 | 破られたときに何が起きるか | 事後に気づく手段 |
| --- | --- | --- | --- |
| コミット規約 (`<emoji> <type>: <subject>`) | `agents/guidelines/core/commit.md` | 形式の揃わないコミットが履歴に残る。push 前なら `git commit --amend` で直せる | `git log -1 --pretty=%s` を型と照合する (commit.md が手順として規定) |
| dev-impl の修正ラウンド上限 (1 周) | `agents/skills/dev-impl/SKILL.md` | 収束しない issue に時間とトークンが溶ける。**実測で 22 issue 中 6 件が 3 周目以降に入り、超過分だけで 5.7h を消費したことがある** | issue の完了コメントに残る「レビュー: N 周」。規定どおりなら N は最大 2 (r1 と fix 後の r2) なので、3 以上なら上限超過 |
| 実装系ルールの遅延参照 | `agents/AGENTS.md`「実装時」 | TDD やテスト方針を知らないまま実装が進む | **無い**。リマインドも事後検出もしない |
| コードコメントを基本的に書かない規範と、実装後に追加コメント行を抽出して判定する自己点検 | `agents/guidelines/core/implementation.md`「コードコメント」 | コードの言い換え・変更履歴・タスク ID がコメントに残り、人と AI の読み手の文脈を占める | dev-impl では親が `agents/skills/dev-impl/scripts/added-comments.sh` の出力を implementer の報告と照合し、`review-impl` の検査項目 3 が、例外の 5 種に当たらないコメントを `medium` / `code-quality` で指摘する。dev-impl の外では **無い** |
| E2E の中で確かめるもの・確かめないもの (文言・書式・計算結果・API の応答・DB の値は下の段のテストで確かめ、流れの途中を API の直接呼び出しで済ませない) | `agents/guidelines/core/testing.md`「E2E で確かめること」 | 文言や計算を変えるたびに遅い E2E が落ちる。画面を通らない判定では、画面が送る要求と API のつなぎ目が確かめられないまま通る | `review-impl` の検査項目 4 が、画面を通らない判定を `high` / `e2e`、下の段で確かめるべきものの比較を `medium` / `test-quality` で指摘する |
| subagent 起動時の `model` 明示 | `agents/guidelines/core/orchestration.md` | 未指定だと agent 定義の frontmatter ではなく親のセッションモデルを継承する。検証器が実行器より弱くなりうる | **無い**。セッションのログを人が読むしかない |
| utility-doc-audit の起動経路 (ユーザー起動と `/workflow-design-notes` の落とし込みのみ) | `agents/skills/utility-doc-audit/SKILL.md` | 普段の作業で監査が自発起動し、観点サブエージェントの fan-out 分のトークンを消費する | **無い**。`disable-model-invocation` を使わない判断のため、SKILL.md の description と本文の記述が唯一の抑止 |
| dev-spec で UI スケッチを最初に作るとき、frontend-design を Skill ツールで起動すること (既存のスケッチに画面を足す・直すときは起動しない) | `agents/skills/dev-spec/references/ui-sketch.md` の手順 5.3「frontend-design の起動のしかた」 | 記憶にあるデザインの知識で作り込み、ジェネリックな見た目のスケッチが実装の手本になる | `UI_SKETCH.html` の痕跡の行 `<!-- frontend-design: ... -->` と、ui-sketch.md 手順 8 のレビュー観点 8 (方針の見た目が全画面に出ているか)。痕跡の行は起動しなくても書けるので、起動したことの証明にはならない |
| dev-spec の UI スケッチを、ユーザーに渡す前に自分で撮影・操作して確かめ、別のコンテキストの批評を通すこと | `agents/skills/dev-spec/references/ui-sketch.md` の手順 5.4・5.5 と `sketch-critique.md` | 描画結果を誰も見ないままユーザーに渡り、押しても動かないキー・見出しの無い列・崩れた画面が、ユーザーの指摘として 1 件ずつ返ってくる | 撮影だけは `agents/skills/dev-spec/scripts/sketch-shots.sh` の終了コードで分かる (ui-sketch.md 手順 8 が完了の印の前に実行する)。操作のスクリプトと批評を実行したかは、**無い**。セッションのログを人が読むしかない |
| OpenCode が共通の正本を Read すること | `agents/bindings/opencode/AGENTS.md` | OpenCode は `~/.claude/CLAUDE.md` を自動では読まない (→「配布先」節) ため、指示を守らないと**エラーも警告も出さずに共通ハーネス無しで走る** | **無い**。セッションのログを人が読むしかない |

### subagents (agents/subagents/)

正本は Claude Code 形式 (Markdown + frontmatter) で、`~/.claude/agents/` へは symlink で配る。Codex と OpenCode へは `agents/scripts/sync-subagents.ts` が書式変換して置く (→「subagent の書式変換」節。反映のタイミングは「live edit の範囲」)。生成物は git 管理しない。

| 配布先 | 形式 |
| --- | --- |
| `~/.claude/agents/*.md` | 正本と同じ形式 |
| `~/.codex/agents/*.toml` | `name` / `description` / `developer_instructions` の 3 キー |
| `~/.config/opencode/agents/*.md` | frontmatter は `description` / `mode: subagent` の 2 キー。本文が prompt になる |

**落とすキーが 3 つある。**

- **`tools`**: Codex に対応キーが無い。OpenCode は真偽値マップ (`{Read: true}`) で正本のカンマ区切り文字列と形式が違う。制限が要るなら本文に禁止事項として書く
- **`model`**: Codex は実モデル名、OpenCode は `provider/model-id` を要求し、どちらも alias が使えない。世代交代に追従できるよう生成物には書かない (Codex で固定するなら `agents/bindings/codex/config.toml` の `[agents] default_subagent_model` に 1 箇所だけ書く。現状は未設定で、どちらの subagent も親のモデルを継承する)
- **`context: fork`**: 相当する概念がどちらにも無い

加えて **`name` は OpenCode 側でだけ落ちる**。OpenCode は subagent 名をファイルパスから決めるため、正本の `name` をファイル名にすれば識別は保たれる。

読み替えの正本は `agents/bindings/codex/AGENTS.md` と `agents/bindings/opencode/AGENTS.md` の「3 者で表現できない subagent の属性」節。

### 配布

`drs` (mac) / `hms` (Linux) が `nix/modules/home/{claude,codex,opencode}.nix` を適用する。専用のインストールスクリプトは無い。`claude.nix` は Claude Code 向けの symlink を持つ。`codex.nix` は Codex 向けの symlink と activation (`linkAgentSkills` / `syncCodexSubagents` / `installCodexPlugins`、Linux では加えて `linkCodexSystemConfig`) を持つ。`opencode.nix` は OpenCode 向けの symlink と activation (`syncOpencodeSubagents` / `opencodeServiceConfig`) を持つ。

Android (`home-android.nix`) は `codex.nix` を import しないので Codex 向けだけが行われない。`opencode.nix` は import するため、Android でも OpenCode のグローバル指示と subagent は配られ、`service.json` の `hostname` も `0.0.0.0` に上書きされる。ただし `linkAgentSkills` が走らないので `~/.agents/skills` は埋まらず、OpenCode は `~/.claude/skills` からだけスキルを読む (→「配布先」節)。

**配布の確認**:

`readlink -f` は実ディレクトリでもそのパスを exit 0 で返すので、**symlink で配られているかの判定には使えない**。`test -L` で symlink であることを先に確かめる。`~/.claude/rules` は配布先ではない。ここにファイルがあると Claude Code が起動時に中身を読むので、無いことも確かめる。

```bash
# 1. 配布先が symlink であること (実ディレクトリのまま残っていたら移行が終わっていない)
for p in ~/.claude/CLAUDE.md ~/.claude/guidelines ~/.claude/skills ~/.claude/agents \
         ~/.claude/hooks ~/.claude/scripts ~/.claude/knowledge-profile.md \
         ~/.claude/settings.json ~/.claude/keybindings.json \
         ~/.codex/AGENTS.md ~/.agents/skills/dev-impl /etc/codex/config.toml \
         ~/.config/opencode/AGENTS.md ~/.config/opencode/opencode.json \
         ~/.config/opencode/cli.json ~/.config/opencode/plugins/spark-served.ts; do
  [ -L "$p" ] && printf 'OK   %s -> %s\n' "$p" "$(readlink -f "$p")" || printf 'NG   %s (symlink ではない)\n' "$p"
done   # 全行が OK で、解決先が dotfiles 配下であること
[ -e ~/.claude/rules ] && echo 'NG   ~/.claude/rules が残っている (Claude Code が起動時に中身を読む)'   # 何も出ないこと

# 2. subagent の生成物 (期待値は正本 agents/subagents/*.md の名前から取る)
expected=$(cd ~/dev/github.com/skanehira/dotfiles/agents/subagents && ls *.md | sed 's/\.md$//' | sort)
for d in ~/.codex/agents ~/.config/opencode/agents; do
  actual=$(rg -l '^# generated by agents/scripts/sync-subagents\.ts' "$d" 2>/dev/null | sed -E 's#.*/##; s/\.(toml|md)$//' | sort)
  if [ "$actual" = "$expected" ]; then echo "OK   $d"; else echo "NG   $d"; diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual"); fi
done   # 2 行とも OK であること。NG の diff は < が生成されていない subagent、> が正本から消えたのに残っている生成物

# 3. 除外とバージョン
ls ~/.agents/skills | grep -cE '^(utility-session-profile|synced)$' || :   # 0 (Codex への配布から除外)
# codex のプラグインは下の「プラグインは別枠」の手順で 6 本だけ確かめる (codex plugin list の全体は 1 MB を超える)
opencode --version                                # opencode v2.0.22 (nix/pkgs/opencode.nix の version)。CLI の版しか見ないので、常駐サービスの版は Directory Structure の `agents/bindings/opencode/` 項の ps と readlink の比較で確かめる
```

**Android は Codex 向けを除いて判定する。** `codex.nix` を import しないので、1 の `~/.codex/AGENTS.md` / `~/.agents/skills/dev-impl` / `/etc/codex/config.toml` の 3 行と、2 の `~/.codex/agents` の行は NG になるのが正しく、`codex plugin list` も `codex` 自体が無い。それ以外の行がすべて OK なら合格である。

**プラグインは別枠で、`installed` にならないことがある。** 確かめるコマンドと、落ちていたときに手で流す手順は Directory Structure の `agents/bindings/codex/` 項にある。

### ランタイムを 1 つ外すとき

追加より撤去のほうが漏れやすい。OpenCode を例に、**触る 10 箇所**を挙げる (Codex を外す場合もほぼ同型で、加えて `/etc/codex/config.toml` の `environment.etc` と activation 4 本が要る)。

| 種別 | 対象 |
| --- | --- |
| モジュールの import | `nix/home.nix` / `nix/home-android.nix` の `./modules/home/opencode.nix` |
| モジュール本体 | `nix/modules/home/opencode.nix` (symlink 4 本 + `syncOpencodeSubagents` + `opencodeServiceConfig`) |
| パッケージ | `nix/pkgs/opencode.nix` と、それを呼ぶ `nix/modules/home/packages.nix` / `packages-android.nix` のエントリ |
| binding | `agents/bindings/opencode/` 一式 (プラグインとそのテストを含む) |
| Neovim | `vim/lua/modules/ai/init.lua` の `TOOL_CONFIG` / コマンド / キーマップ、`comments.lua` の `TOOLS` |
| wezterm | `wezterm/wezterm.lua` の専用キーバインド |

表の 10 箇所を外したら、最後に `rg -il opencode` で残りを掃く。`agents/scripts/sync-subagents.ts` / `subagent-format.ts` の `opencode` 形式 (とそのテスト) を残すかは、そこで判断する。

**binding の削除とモジュールの削除は同じコミットに入れる。** 分けると `home.file` や activation の参照先が消えた状態で評価が走り `drs` が失敗する。

**`drs` / `hms` は生成物を片付けない。** activation ごと消えるので `~/.config/opencode/agents/*.md` は prune されず残る。**手で消す**: `rm -rf ~/.config/opencode/agents`。`~/.config/opencode/service.json` も `hostname` が `0.0.0.0` のまま残るので、OpenCode を使わないなら同じく消す。常駐サービス (`opencode serve --service`) が動いていれば、パッケージを外す前に `opencode service stop` で止める。HM が張った symlink 4 本は activation が撤去するが、過去に退避された `*.hm-backup` や `*.bak` は残るので同様に判断する。

### 解消しない非対称

- **ツールの引数の形**は 3 者で揃えていない。スキル・ルール・subagent の本文はツールの呼び出し例 (引数つき) を載せず、何を聞くか・何を起動するかの意図だけを書くので、引数は各ランタイムが自分のツールのスキーマで組み立てる。Codex と OpenCode のツールスキーマを実測する手段が無く、推測で例を書くと誤った例を配ることになるため。本文に残るツール名は binding の読み替え表で読む。スキルの frontmatter の `allowed-tools` は Claude 綴りのまま残り (扱いは `agents/bindings/{codex,opencode}/AGENTS.md` の「読み替えで吸収できないもの」節)、subagent の `tools` は書式変換で生成物から落ちる (扱いは同じ 2 ファイルの「3 者で表現できない subagent の属性」節)
- **選択式の質問の形**も揃わない。Codex の `request_user_input` は 2〜3 択の単一選択である。両 binding とも OpenCode の `question` にも同じ線を引き、4 択以上や複数選択の質問は、選択肢を番号付きでメッセージに並べて番号で答えてもらうと書いてある
- **guidelines の読み込み**は 3 者とも、グローバル指示の「Read せよ」に頼る。guidelines は Claude Code が起動時に自動で読む `~/.claude/rules` ではなく `~/.claude/guidelines` に置くので、Claude Code でも自動では読まれない。例外は、グローバル指示が `@` で取り込む 3 本 (`collaboration.md` / `orchestration.md` / `documentation.md`) である。Claude Code はこの 3 本を起動時に展開し、Codex と OpenCode は binding の Read 指示で読む。Read 指示を守るかはモデル任せで、3 者で「同じルールが同じタイミングで効く」ことまでは保証していない
- **共通の正本の自動読み込み**は Claude Code だけが持つ (Codex と OpenCode が読むものは「配布先」節)。共通の正本は binding 内の Read 指示で届ける。指示を守るかはモデル任せで、Claude Code の自動展開のような機械的な保証は無い

## 依拠する外部事実

本文の件数・実測値と、本文が前提にする事実は、確認した時点のものである。現在の配置や件数を判断するときは、次の確認元と方法で調べ直す。以下は確認方法の一覧であり、全マシンで同じ状態であることを保証しない。

| 確認するもの | 確認元 | 確認方法 |
| --- | --- | --- |
| Nix のプロファイル・OS 別の import | `nix/flake.nix` / `home-darwin.nix` / `home-linux.nix` / `home-android.nix` | 各 output の system と module の import 一覧を読む |
| ハーネスの symlink と subagent の生成 | `nix/modules/home/claude.nix` / `codex.nix` / `opencode.nix`、`agents/scripts/sync-subagents.ts` | 「配布の確認」のコマンドで symlink の解決先と生成物を確認する。変換結果は正本の本文と生成物の本文を照合する |
| スキル・subagent の本数と配布除外 | `agents/skills/` / `agents/subagents/`、`codex.nix` の `claude_only_skills` | 下のコードブロックで git 管理分を数え、「スキルの配布先の限定」と実際の配布先を照合する |
| Claude のプラグイン・hook の件数 | `agents/bindings/claude/settings.json` | 下のコードブロックで件数だけを出す。プラグインの実際の導入状態は設定上の有効件数と分け、Codex 側は専用の 6 本を確認する既載のコマンドを使う |
| Nix の CI と agent 関連の手動テスト | `.github/workflows/nix-check.yml`、`agents/scripts/` と `agents/bindings/opencode/` のテスト | CI の対象パスと実行コマンドを読む。agent 関連は「subagent の書式変換」の `deno test` を手で実行する |
| subagent のモデル指定・継承とゲートの有無 | `agents/scripts/subagent-format.ts`、`agents/bindings/codex/config.toml`、各 binding の `AGENTS.md`、各スキル・ルール | 生成するキーとランタイム側の設定を確認する。検出手段の有無は「機械ゲートを置いていない規律」と規定元を照合し、ログから未確認の順序を実施済みとしない |
| sudo の認証方式 | `nix/modules/darwin/system.nix`、`/etc/pam.d/sudo_local`、導入済みの `man sudo` | Touch ID / reattach の設定と `-n` の説明を読む。資格情報キャッシュの有無で挙動が変わるため、非対話指定を認証全体の無効化と解釈しない |

git 管理分の件数と、設定上のプラグイン・hook 件数はリポジトリ直下で次のように確認する。認証ファイル・履歴・キャッシュは読まない。

```bash
python3 - <<'PY'
import json, subprocess
from pathlib import Path

files = subprocess.check_output(["git", "ls-files", "-z"], text=True).split("\0")
print("skills:", sum(p.startswith("agents/skills/") and p.endswith("/SKILL.md") for p in files))
print("subagents:", sum(p.startswith("agents/subagents/") and p.endswith(".md") for p in files))
settings = json.loads(Path("agents/bindings/claude/settings.json").read_text())
plugins = settings.get("enabledPlugins", {})
print("plugins:", len(plugins), "enabled:", sum(v is True for v in plugins.values()))
print("hooks:", sum(len(group.get("hooks", [])) for groups in settings.get("hooks", {}).values() for group in groups))
PY
```

本文が依拠する個別の事実と、その確認日は次のとおりである。確認日が「未確認」の行は、本文がその前提で書かれているが、まだ確かめていない。

| 事実 | 確認日 | 確認方法 |
| --- | --- | --- |
| 「Android を別プロファイルにする理由」の表の規模 (ローカルビルド・fetch の件数と容量) | 2026-09-06 | mac (aarch64-darwin) から `nix build --dry-run` を両プロファイル連続で実行する。2026-09-19 に `opencode` を両プロファイルへ足した後は測り直していない |
| このマシンの Codex の user レイヤーには `model` / `model_reasoning_effort` / `notify` があり、`config.toml` に置いた同名の 3 キーは効いていない | 2026-10-03 | `~/.codex/config.toml` に同名のキーがあるかを見る |
| ローカル clone の無いマシンでは、`archify` / `slide-plugin` の `codex plugin add` が失敗して警告を出す | 未確認 | `codex.nix` のループから推論したもの。clone の無いマシンで `drs` / `hms` の出力を見る |
| OpenCode の常駐サービスは全インターフェースの 49374 番で待ち受ける | 2026-10-04 | `lsof -nP -iTCP:49374 -sTCP:LISTEN` が `*:49374` を返す |
| OpenCode の常駐サービスは、設定ファイルとプラグインの変更を読み直して反映する | 未確認 | 読み直す実装は opencode v2.0.22 のソースにある。反映そのものと、読み直しを外から観測する手段は確かめていない |
| `~/.config/opencode/` の V1 のプラグイン SDK (`node_modules` など) は、2026-09-07 に置かれたまま更新されていない | 2026-10-03 | ファイルの更新日時を見る |
| herdr のプラグインを宣言的に導入する手段は無い | 2026-10-03 | herdr 0.9.3 の `herdr --default-config` と、HM の `programs.herdr` のオプション一覧を見る |
| ComfyUI のブラウザ版の「すべてダウンロード」は `~/Downloads` に落ち、`models/` には置かれない | 2026-09-22 | 実際にダウンロードして確かめた。上流 issue [#13676](https://github.com/Comfy-Org/ComfyUI/issues/13676) が open のままかを見る |
| macOS の Keychain (SecTrust) は eMudhra の中間証明書を `certificate is revoked` として拒否する | 2026-10-22 (macOS 26.6.2) | OS の検証を使うクライアントで eMudhra の検証用ホストに接続する |
| `/etc/ssl/cert.pem` を使う Apple 同梱のツールは、eMudhra の検証用ホストに接続できる (失効を確認しない) | 2026-10-22 | Apple の `/usr/bin/curl` で eMudhra の検証用ホストに接続し、200 が返ることを見る |
| Codex の skill root は `r0` = `~/.codex/skills` と `r1` = `~/.agents/skills` の 2 つ | 2026-09-19 (Codex 0.154) | セッションログの `### Skill roots` を見る |
| Codex は symlink のスキルフォルダを追跡する | 2026-09-19 | 公式ドキュメントの「symlinked skill folders を追跡する」の記述 |
| Codex は同名スキルをマージせず、`r0` と `r1` に二重に列挙する | 未確認 | 根拠は 2 つの root が独立に列挙されることだけ。同名スキルを両方に置いて一覧を見る |
| OpenCode は同じ識別子のスキルを 1 つにまとめる | 2026-10-03 | opencode v2.0.22 のソースを読み、実環境のスキル置き場を `opencode api skill.list` で列挙して重複 0 件を確かめた |
| OpenCode V2 は `~/.claude/CLAUDE.md` へフォールバックしない | 2026-10-03 | opencode v2.0.22 の `packages/core/src/config/plugin/instruction.ts` を読む |
| OpenCode は subagent 名をファイルパスから決める | 2026-10-03 | opencode v2.0.22 の `packages/core/src/config/plugin/agent.ts` を読み、生成物 4 本が `opencode debug agents` に出ることを確かめた |
| Linux で herdr の SessionStart が失敗したとき、Claude Code がその失敗を表示するか | 未確認 | Linux で Claude Code を起動して見る |
| Codex の `request_user_input` は 2〜3 択の単一選択である | 未確認 | 根拠は codex 0.159.2 のバイナリに含まれる文字列で、公式のスキーマでは確かめていない |
| OpenCode の `question` の選択肢の数と、複数選択の可否 | 未確認 | OpenCode の `question` ツールのスキーマを見る |

## Working with This Repository

### 既存設定の変更 (Nix 管理側)

1. `nix/modules/home/*.nix` または `nix/modules/darwin/*.nix` を編集
2. `nix fmt` で整形する (`nix/**` への push で CI が `nix fmt -- --ci` と `nix flake check --all-systems --no-build` を回すので、崩れたまま push すると master で fail する)
3. `git add` で staging (flake は tracked file しか見ない)
4. `drs` (mac) / `hms` (Linux) で適用 (`nh` が darwin-rebuild / home-manager を起動。mac は Touch ID 経由の sudo)

### 新規ツール追加

- CLI: `modules/home/packages.nix` に追記。Android でも使うなら `modules/home/packages-android.nix` にも足す (別リストなので自動では入らない)
- 設定ファイル: `programs.<tool>` モジュールがあれば使う、無ければ `home.file.*` で配置
- macOS GUI app: `modules/darwin/homebrew.nix` の `casks` に追記
