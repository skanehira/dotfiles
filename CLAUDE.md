# CLAUDE.md

このリポジトリで作業するエージェント (Claude Code / Codex / OpenCode) 向けの運用ガイド。

- 種別: プロジェクト運用ガイド
- 対象読者: このリポジトリで作業する Claude / Codex / OpenCode
- 最終確認: 2026-10-04。**本書の件数 (スキル 45 本・subagent 4 本・`enabledPlugins` 22 件で有効 19 本・`settings.json` の hooks 1 件・`packages-android.nix` 19 エントリ) は実環境に依存するので、疑わしいときは数え直す**

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

ログインユーザーが `skanehira` でないマシン (CI / 検証箱など) では、`flake.nix` の `linuxUsers` にそのユーザー名を足してから `.#<ユーザー名>` を指定する (`ubuntu` は既に列挙済みなので `.#ubuntu` がそのまま使える)。`$USER` を動的に読む impure 方式は `nh` / `home-manager` が pure 評価で output を引くため `hms` 等で壊れる。よって pure に列挙する。

### 初回セットアップ (Android / Galaxy Z Fold 8 Ultra)

Snapdragon 機は Android 標準の Linux ターミナル (AVF = Android Virtualization Framework) を起動できないので、Termux + proot-distro Debian を使う。手順とその根拠は `docs/android-dev-setup.md` にまとめてある。通常の Linux とは以下が違う。

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
  - `pkgs/` — nixpkgs 未収録ツールの自前 derivation (tsp-server / gh-actions-language-server / kanary / opencode / claude-recall)

### Nix 補助

- **zsh/** — `zsh.nix` が 2 つの経路で取り込む zsh の設定
  - `zshrc` — bindkey 群 + 関数 source loop。`programs.zsh.initContent` が `builtins.readFile` で取り込む
  - `functions/*.zsh` — カスタム zsh 関数は macOS で 5 本、Linux で 4 本。`zsh.nix` の `home.file` が `~/.config/zsh/functions/` に 1 本ずつ置き、`zshrc` の source loop が読み込む。`ghq-fzf` / `gss` / `tmuxpopup` / `claude-deepseek` (`ccds`: DeepSeek 本家 API) と、mac 専用の `sleepctl`。OpenCode はラッパー関数を持たず、素の `opencode` が Spark に繋がる (接続先・運用は `agents/rules/infra/dgx-spark.md`)
- **karabiner/** — Karabiner-Elements 設定 (Goku DSL)
  - `karabiner.edn` — EDN で書いたルール、switch 時に goku が `~/.config/karabiner/karabiner.json` を生成
- **wezterm/** — WezTerm 設定 (`mkOutOfStoreSymlink` で dotfiles 直接 symlink、live edit 可能)
  - `wezterm.lua` — `programs.wezterm.extraConfig` は使わず直接 symlink する。Lua の編集体験 (lua_ls) を保ち、`drs` 無しで反映するため
- **tmux/** — tmux 設定 (`mkOutOfStoreSymlink` で dotfiles 直接 symlink、live edit 可能)
  - `tmux.conf` — 編集即反映、`prefix + r` で reload。`drs` 不要
  - プラグインの run-shell だけは nix store path 解決のため Nix 生成の `~/.config/tmux/plugins.conf` 経由
- **agents/** — AI エージェント共通のハーネス正本 (3 ランタイムが同じ実体を読む。配布は正本への symlink が基本で live edit 可能)
  - `AGENTS.md` / `rules/` / `skills/` の本文は正本への symlink なので編集即反映。`subagents/` は Claude Code にだけ symlink で配り、Codex と OpenCode は本文の変更も `drs` / `hms` による再変換が要る。スキルの追加・削除時も Codex では `drs` / `hms` が要る (→「live edit の範囲」)
  - `hooks/` / `scripts/` / `knowledge-profile.md` と `bindings/claude/settings.json` / `keybindings.json` / `bindings/codex/AGENTS.md` / `config.toml` / `bindings/opencode/AGENTS.md` / `opencode.json` / `plugins/spark-served.ts` / `cli.json` も直 symlink。`bindings/claude/settings.deepseek.json` は配布せず、`ccds` が `$GHQ_ROOT` (ghq のルート。`nix/modules/home/env.nix` が `$HOME/dev` に設定する) 経由で直接読む
  - 配布先と構成は「AI エージェントのハーネス (agents/)」節を参照
- **agents/bindings/codex/** — Codex 固有の設定 (ハーネス本体は `agents/` 直下)
  - `config.toml` — git 管理する Codex 共通設定。Codex の system レイヤー `/etc/codex/config.toml` として dotfiles 直接 symlink され、CLI / ChatGPT.app 内 Codex を含む全クライアントに読まれる (live edit 可能)
  - `config.toml` に hooks は書いていない。このハーネスは機械ゲート (deny する hook) を 1 本も持たないので移植すべきものが無い。将来 Codex へ hook を配るときの置き場とレイヤーごとの発火差は `agents/bindings/codex/AGENTS.md` の「hooks を追加するときの置き場」節にある
  - `AGENTS.md` — Codex のグローバル指示。`~/.codex/AGENTS.md` へ symlink され、共通の正本 (`~/.claude/CLAUDE.md`) を読む指示と Claude 綴りの読み替え表を持つ
  - `~/.codex/config.toml` (user レイヤー) は dotfiles で管理しない。Codex 自身が書き込む可変状態で、書かれるものの例は `[projects.*]` trust / `/model` の選択 (`model` / `model_reasoning_effort`) / `notify` / `[plugins.*]` / `[marketplaces.*]` / `[hooks.state]` である。ここにあるキーは system レイヤー (`/etc/codex/config.toml`) の同名キーより優先され続ける。2026-10-03 のこのマシンでは user レイヤーに `model` / `model_reasoning_effort` / `notify` があり、`config.toml` に置いた同名の 3 キーは効いていない。`[mcp_servers.*]` は両レイヤーに現れる。全マシン共通のサーバ (context7 / chrome-devtools) は `config.toml` で配り、マシン固有のものは Codex が user レイヤーに書く
  - 旧方式 (Home Manager が `~/.codex/config.toml` を生成) を使っていたマシンでは、`drs` / `hms` 後に 1 回だけ `~/.codex/config.toml` から重複するキーを手で削除する。残さないと `/etc` 側の値が遮蔽される
  - `/etc/codex/config.toml` の確認: `readlink -f /etc/codex/config.toml` が dotfiles の `agents/bindings/codex/config.toml` に解決すること
  - **プラグインだけは宣言的に管理できない。** `config.toml` に `[marketplaces.*]` を書くと空ディレクトリを見に行って失敗し、`[plugins.*]` を書いても `not installed` のまま。`codex.nix` の activation が `codex plugin marketplace add` と `codex plugin add` を冪等に流す。Claude 形式の `.claude-plugin/marketplace.json` をそのまま読むので、リポジトリ側に Codex 用のマニフェストは要らない。対象は Claude 側にも入れている 6 本で、`agents/bindings/claude/settings.json` の `enabledPlugins` は 22 件を宣言し有効 (`true`) は 19 本なので、Codex へ配るのはその部分集合になる

    | `codex plugin add` に渡す名前 | marketplace の入手元 |
    | --- | --- |
    | `document-skills@anthropic-agent-skills` | `anthropics/skills` |
    | `frontend-design@claude-plugins-official` | `anthropics/claude-plugins-official` |
    | `ui-ux-pro-max@ui-ux-pro-max-skill` | `nextlevelbuilder/ui-ux-pro-max-skill` |
    | `compact-plus@compact-plus` | `u-ichi/compact-plus` |
    | `archify@misty-lantern` | **ローカル** `~/dev/github.com/skanehira/misty-lantern` |
    | `slide-plugin@slide-plugin` | **ローカル** `~/dev/github.com/skanehira/slide-plugin` |

    下 2 本はローカル clone が前提である。clone が無いマシンでは、`codex.nix` は marketplace の登録を黙って飛ばし (`[ -d "$repo_path" ] || continue`)、続く `codex plugin add` は登録の無い marketplace を指すので失敗し、`codex plugin add … に失敗した` の警告を出す (`codex.nix` のループからの推論で、clone の無いマシンでは確かめていない)。activation の PATH は HM が nix の基本ツールだけに絞るので、`installCodexPlugins` はサブシェルの中で `home.path` の bin と Homebrew の bin を足してから `codex` を呼ぶ。2026-10-03 のこのマシンでは 6 本とも `installed, enabled` だった。**失敗しても activation は警告のみで止まらない**ので、次のコマンドで 6 本の状態を確かめる (`codex plugin list` の出力は 1 MB を超え、全体を目で探すのは無理がある)。落ちていたら `codex plugin marketplace add <入手元>` → `codex plugin add <名前>` の順で手で流す

    ```bash
    codex plugin list | rg '^(document-skills@anthropic-agent-skills|frontend-design@claude-plugins-official|ui-ux-pro-max@ui-ux-pro-max-skill|compact-plus@compact-plus|archify@misty-lantern|slide-plugin@slide-plugin) '
    # 6 行が出て、名前の次の状態の列がすべて installed, enabled なら合格
    ```
- **agents/bindings/opencode/** — OpenCode (V2) 固有の設定 (ハーネス本体は `agents/` 直下)。**OpenCode は DGX Spark 専用**で、ラッパー無しの素の `opencode` が Tailscale 経由で Spark に繋がり、配信中のモデルを既定に選ぶ。**自宅でも Tailscale へのサインインが前提**になる。mac は Tailscale のアプリを `nix/modules/darwin/homebrew.nix` の cask (`tailscale-app`) で入れるがサインインは手作業で、Linux / Android の Tailscale は dotfiles の管理外である。繋がらないときは `agents/rules/infra/dgx-spark.md`「障害時」節の「OpenCode が Spark に繋がらない」の行を見る
  - `AGENTS.md` — OpenCode のグローバル指示。`~/.config/opencode/AGENTS.md` へ symlink され、共通の正本 (`~/.claude/CLAUDE.md`) を Read する指示と Claude 綴りの読み替え表を持つ。**OpenCode が自動で読むグローバル指示はこのファイルだけ**なので、Read 指示は飾りではない (→「配布先」節)
  - `opencode.json` — Spark の provider 定義 (接続先・モデル宣言・モデルごとの `reasoningEffort` と `limit`)。接続先は Tailscale の MagicDNS 名 `http://spark-head:8888/v1` に固定し、自宅 LAN の経路は使わない。`enabled_providers: ["spark"]` で Spark 以外の provider (OpenCode Zen の無料モデル) を選択肢から外す。V1 書式のまま書いてあり、V2 が読み込み時にメモリ上で正規化する。API キーは持たない (詳細は `agents/rules/infra/dgx-spark.md`)
  - `plugins/spark-served.ts` — 配信中のモデルだけを有効にして既定に据える V2 のローカルプラグイン。`~/.config/opencode/plugins/` へ symlink され、起動時と 30 秒ごとに `/v1/models` を引く。接続先 URL を `opencode.json` と 2 か所に持ち (setup の時点で設定の provider を読めないため)、一致は同じディレクトリの `spark-served_test.ts` が検査する。**選ぶのは `opencode.json` に宣言済みのモデルだけ**なので、Spark で配信するモデルを増やしたら `opencode.json` に宣言を足す (→ `agents/rules/infra/dgx-spark.md`「モデルの追加と切り替え」)
  - `cli.json` — TUI のキーバインドとテーマ (V2 書式)。`~/.config/opencode/cli.json` へ symlink される。**起動しただけでは V2 は書き換えないが、TUI でテーマなどを変えると一時ファイルの rename で書き換えるので symlink が実ファイルに化け、repo との同期が黙って切れる。設定は repo 側を編集して変え、TUI では変えない**。化けたら、まず `diff ~/.config/opencode/cli.json ~/dev/github.com/skanehira/dotfiles/agents/bindings/opencode/cli.json` で差分を見て残したい変更を repo 側へ写し、それから実ファイルを消して `drs` / `hms` で張り直す。消さずに `drs` すると mac は `cli.json.hm-backup` へ退避して進む。このとき TUI で変えた値は `cli.json.hm-backup` 側に移るので、差分はそちらと取る。`.hm-backup` が既にあると次の退避で止まる (Linux の `hms` は退避せずに止まる。→「配布方式の移行 (生成方式 → symlink)」節)
  - グローバル指示の確認と同居物: `readlink -f ~/.config/opencode/AGENTS.md` が dotfiles の `agents/bindings/opencode/AGENTS.md` に解決すること。**`~/.config/opencode/` には dotfiles の symlink 以外のものが同居する**ので、ディレクトリごとではなくファイル単位で symlink する。同居するのは次のものである
    - 常駐サービスの設定 `service.json` (キーは `hostname` と `password`)。**`password` は `opencode service set` が生成した値を平文で持つので、表示も共有もしない**。repo に置けず、`opencode service set` が一時ファイルの rename で書き換えるので symlink でも配れない。そのため `opencode.nix` の activation `opencodeServiceConfig` が `drs` / `hms` のたびに既存ファイルを jq で読み、`hostname` だけを `0.0.0.0` に上書きする (`password` など他のキーは残す)。ファイルが無いか JSON として読めないときは警告を出し、`hostname` だけのファイルを作り直す。書き換えた値はサービスを `opencode service restart` するまで効かない
    - subagent の生成物 `agents/` (→「subagent の書式変換」節) と、ある場合は `skills/`
    - V1 のプラグイン SDK (`@opencode-ai/plugin` 1.18.18) を入れた `node_modules` / `package.json` / `package-lock.json` / `.gitignore`。2026-09-07 (V1 の時期) に置かれたまま更新されていない
    - `drs` が退避した `*.hm-backup` (例: `cli.json.hm-backup`)。2026-10-03 のこのマシンには `cli.json.hm-backup` があり、中身は repo の `cli.json` と一致した。残っていると次に `cli.json` が実ファイルに化けたときの `drs` が止まるので、差分を見たうえで消す
  - 本体は `nix/pkgs/opencode.nix` の自前 derivation (nixpkgs の `opencode` は V1)。npm の `@opencode/cli-<platform>` に入っている bun コンパイル済みの単一バイナリを展開するだけで、ローカルビルドは走らない。更新手順はファイル冒頭のコメントにある
  - 素の `opencode` は常駐サービス (`opencode serve --service`) を起動して接続し、TUI を閉じてもサービスは残る。**待ち受けは全インターフェースの 49374 番で、外からの接続を防ぐのは `service.json` のパスワードだけである** (`hostname` が `0.0.0.0` のため。2026-10-04 のこのマシンで `lsof -nP -iTCP:49374 -sTCP:LISTEN` が `*:49374` を返した)。**`nix/pkgs/opencode.nix` の版を上げても、常駐サービスは古いバイナリのまま動き続ける**ので、版を上げたら `drs` / `hms` の後に必ず `opencode service restart` する。切り替わったかは、`ps -axo command | rg '[o]pencode serve'` に出るストアパスと `readlink -f "$(command -v opencode)"` が一致することで確かめる (2026-10-03 のこのマシンでは両方が `opencode-2.0.22` のストアパスだった)。設定ファイルとプラグインの変更はサービスが検知して読み直す実装がソースにあるが、反映を実際に確かめてはおらず、読み直しを外から観測する手段も確かめていない。変更が効いていないように見えたら同じく `opencode service restart` する。止めるときは `opencode service stop`
- **vim/** — Neovim 設定 (`mkOutOfStoreSymlink` で dotfiles 直接 symlink、live edit 可能)
  - `init.lua` / `lua/` / `after/` — 編集即反映、`drs` 不要
  - `.luarc.json` — lua_ls の dotfiles 内 lua 編集用設定 (track 対象)
- **herdr/** — herdr (コーディングエージェント用のターミナル多重化) の設定
  - `config.toml` — `herdr.nix` が `~/.config/herdr/config.toml` へ mkOutOfStoreSymlink する
  - **herdr のプラグインは使っていない。** プラグインは宣言的に導入する手段が無い (herdr 0.9.3 の `herdr --default-config` に plugin の項目が無く、HM の `programs.herdr` も enable / package / settings の 3 オプションだけ。2026-10-03 確認)。使うときは `herdr plugin install <owner>/<repo> --yes` を手で流し、`config.toml` の `type = "plugin_action"` でキーに割り当てる。導入状態は `~/.config/herdr/` 配下の herdr 所有ファイルにあり、Nix の管理外になる
  - Neovim 側の herdr 連携は `vim/lua/modules/ai/herdr.lua` (herdr コマンドの低レベルラッパー) が持つ
- **comfyui/** — ComfyUI (Qwen-Image-2.1 の GUI) 用の補助スクリプト (mac only)
  - ComfyUI 本体と venv (`~/.local/share/comfyui/{ComfyUI,venv}`) は `nix/modules/home/comfyui.nix` の activation `bootstrapComfyui` が commit を固定して導入する。nixpkgs の `comfyui` は `meta.platforms` が linux のみで、かつ Qwen-Image-2.1 対応の v0.37.0 に追いついていないため、`deno.nix` / `rustup.nix` と同じ bootstrap パターンを採る。起動は同モジュールが生成する `ComfyUI.app` (mac-app-util が `~/Applications/Home Manager Trampolines/` へ trampoline 化する) から行い、サーバが未起動ならこれが起こす。サーバは `nohup` で裏に起こすので `.app` やブラウザを閉じても残る。止めるときは起動中に `ComfyUI.app` をもう一度開き、ダイアログで「停止」を選ぶ (「ブラウザを開く」が既定)。生成画像は `~/Pictures/ComfyUI` に出る
  - **モデルの入手経路は 2 つあり、マシンによって使い分ける。** どちらも `~/.local/share/comfyui/models/{diffusion_models,text_encoders,vae}/` に置く点は同じ

    | 経路 | 対象 | 版 | 容量 | 手順 |
    | --- | --- | --- | --- | --- |
    | shard 結合 | **mflux で 28.9 GiB を取得済みのマシン (現在は Mac Studio のみ)** | bf16 | 30.2 GiB | `merge-weights.py` を 1 回実行 |
    | UI ダウンロード | それ以外のマシン | int8 | 15.0 GiB | ComfyUI でテンプレートを開き「すべてダウンロード」→ `~/Downloads` から手で移動 |

  - `merge-weights.py` — mflux が使う diffusers 形式の重み (`~/.cache/huggingface/hub/models--Qwen--Qwen-Image-2.1`、shard 分割) を ComfyUI が読む単一ファイル形式へ結合する。VAE だけはキー体系が違うので `Comfy-Org/Qwen-Image-2.1` から取得する。**ComfyUI の venv の python で 1 回だけ手で実行する** (`~/.local/share/comfyui/venv/bin/python comfyui/merge-weights.py`)。30 GiB の結合に数分かかるので activation では流さない。引数無しで冪等 (出力が既にあれば skip)、`--force` で作り直す。**HF キャッシュが無いマシンでは `HF キャッシュが無い` で止まる**ので、その場合は UI 経路を使う
  - **UI 経路では手で移動する作業が 1 回残る。** ComfyUI は不足モデルを列挙して「すべてダウンロード」ボタンを出すが、**ブラウザ版はブラウザのダウンロード (`~/Downloads`) になり `models/` には置かれない** (実測。上流 issue [#13676](https://github.com/Comfy-Org/ComfyUI/issues/13676) が open)。公式テンプレートが指定するのは int8 版なので、bf16 を使うマシンではテンプレートのローダのファイル名を bf16 のものへ差し替える
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
├── pkgs/                  ← 自前 derivation (tsp-server / gh-actions-language-server / kanary / opencode / claude-recall)
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
- **モジュール共有**: `home-core.nix` が全プロファイル共通の土台 (dotfilesRoot / stateVersion / programs.home-manager) で、module の import は持たない。「どのツールを入れるか」はプロファイル側の決定なので、`home.nix` (フルセット) と `home-android.nix` (軽量) がそれぞれ import 一覧を持つ。`home-darwin.nix` / `home-linux.nix` は `home.nix` に homeDirectory を足す wrapper。mac 専用 module は `karabiner.nix` / `wezterm.nix` / `mac-app-util-icons.nix` / `comfyui.nix` で `home-darwin.nix` からだけ import。`tmux.nix` / `zsh.nix` は内部で `lib.optionalString isDarwin/isLinux` 分岐済。
- **Android を別プロファイルにする理由**: proot は RAM が数 GB でストレージも Termux のアプリ内領域に載り、binary cache に無いものをローカルビルドできない。フルセットは完走しないため、`packages-android.nix` に軽量なものを 19 エントリだけ明示列挙する (`programs.git` 等が足す分と HM 内部を含めて `home.packages` は 34 件)。規模の差は下表のとおり。neovim は nightly overlay ではなく nixpkgs の stable を使う。

  | プロファイル (aarch64-linux) | ローカルビルド (件) | fetch (件) | ダウンロード | 展開後 |
  | --- | --- | --- | --- | --- |
  | `skanehira-android` | 46 (全て HM の設定生成と wrapper。コンパイルなし) | 325 | 542.4 MiB | 1.9 GiB |
  | `skanehira-aarch64` (フルセット) | 693 (neovim nightly / terraform / herdr 等のコンパイルを含む) | 1545 | 3.5 GiB | 13.0 GiB |

  計測条件: 2026-09-06、mac (aarch64-darwin) から `nix build --dry-run` を両者連続実行。Claude Code / Deno / Vite+ は activation 時に公式インストーラを走らせるので、この数値には含まれない。fetch 件数は実行マシンの nix store に既にある分を除いた値なので、まっさらな端末では増える。**2026-09-19 に `opencode` を両プロファイルへ足した分は測り直していない**ので、この表は opencode 抜きの値である。
- **overlays の共有**: `modules/overlays-list.nix` が overlay の素のリストを export し、nix-darwin (`modules/overlays.nix` 経由) と HM standalone (`flake.nix` の `import nixpkgs` 経由) の両方から参照される。
- **Homebrew**: GUI app (cask) と CLI のうち (a) cask の依存になるコア formula、(b) nixpkgs 未収録 (例: `aqua`) のみ管理 (mac only)。それ以外の CLI ツールは Nix 管理。`brews` には `ca-certificates` / `openssl@3` を保険として (cask 依存リンクが切れた時の巻き添え削除を防止)、`python@3.14` を cask `gcloud-cli` の依存として、`aqua` を nixpkgs 未収録の CLI として明示宣言。`python@3.14` を宣言するのは、cleanup が cask の依存を最新の cask 定義から引くためである。定義だけが新しい python へ進むと (`upgrade = false` なので導入済みの `gcloud-cli` は古い python を使ったまま)、使用中の python が削除候補になり、`brew uninstall` に拒否されて `drs` が警告を出す。`gcloud-cli` を upgrade して使う python が変わったら、この宣言も書き換える。`onActivation.cleanup = "uninstall"` で宣言外は drs 時に自動撤去。
- **Touch ID for sudo**: `security.pam.services.sudo_local.touchIdAuth + reattach` で tmux 内含めて指紋認証 (mac only)。

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
- `vim/after/lsp/` — LSP 個別設定 (denols, rust_analyzer, lua_ls, nixd, tsgo, version_ls, yamlls)

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
├── rules/               ← core/ backend/ frontend/ infra/
├── skills/              ← 45 本 (git 管理分。12 本は外部からの vendor で、wondelai/skills の 11 本と nanaism/yomiyasu の 1 本。出典は `LICENSE-wondelai` / `LICENSE-yomiyasu`。配布除外は →「スキルの配布先の限定」節)
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
| ルール | `~/.claude/rules/` ← `agents/rules/` | `~/.claude/rules/` を絶対パスで直接 Read | 同左 | symlink (live edit) |
| スキル | `~/.claude/skills/` ← `agents/skills/` | `~/.agents/skills/<name>` ← `agents/skills/<name>` (個別 symlink) | `~/.agents/skills/` (Codex と共有) と `~/.claude/skills/` の両方を読む | symlink (`~/.agents/skills` 側の追加・削除は `drs` / `hms`) |
| subagent | `~/.claude/agents/` ← `agents/subagents/` | `~/.codex/agents/*.toml` (書式変換) | `~/.config/opencode/agents/*.md` (書式変換) | symlink (Claude 以外は `drs` / `hms`) |
| `scripts/` | `~/.claude/scripts` ← `agents/scripts/` | 同じパスをそのまま実行する (同一実体) | 同左 | symlink (live edit) |
| `knowledge-profile.md` | `~/.claude/knowledge-profile.md` ← `agents/knowledge-profile.md` | 同じパスをそのまま読み書きする (同一実体) | 同左 | symlink (live edit) |
| `hooks/` | `~/.claude/hooks` ← `agents/hooks/` | **配布しない** (Codex の hook は `~/.codex/hooks.json` と `config.toml` とプラグイン。所在と件数は `agents/bindings/codex/AGENTS.md`「hooks は Codex には配られていない」節) | **配布しない** (シェル hooks を持たない) | symlink (live edit) |
| Claude 固有の設定 | `~/.claude/settings.json` / `keybindings.json` ← `agents/bindings/claude/` | 配布しない | 配布しない | symlink (live edit) |
| Codex 共通設定 | 読まない | `/etc/codex/config.toml` ← `agents/bindings/codex/config.toml` | 読まない | symlink (mac は `environment.etc`、Linux は activation `linkCodexSystemConfig`) |
| OpenCode 固有の設定 | 読まない | 読まない | `~/.config/opencode/{opencode.json,cli.json,plugins/spark-served.ts}` ← `agents/bindings/opencode/` | symlink (live edit) |

**Codex は skill root を 2 つ持つ。** 実セッションログの `### Skill roots` で `r0` = `~/.codex/skills` / `r1` = `~/.agents/skills` を確認しており (Codex 0.154)、公式ドキュメントは「symlinked skill folders を追跡する」と明記している。共有に `r1` を使うのは、`~/.agents/skills` に他ツールが入れたスキル (例: `find-skills`。種類と本数はマシンによって違う) が同居するため。ディレクトリごとの symlink は使えないので 1 スキルずつ張る。

**`~/.codex/skills` は配布先ではない。** ここに dotfiles 由来の実体が残っていると同名スキルが `r0` と `r1` に二重に列挙される (Codex は同名スキルをマージしない。**未実測の推測で、根拠は 2 つの root が独立に列挙されることだけ**)。移行時に消す (→「配布方式の移行 (生成方式 → symlink)」節)。`.system` と plugin 由来のものは Codex の所有物なので触らない。

**OpenCode は `~/.agents/skills` と `~/.claude/skills` の両方を読む。** OpenCode (V2) のスキル探索先は `~/.config/opencode/{skill,skills}` / `~/.claude/skills` / `~/.agents/skills` (とプロジェクトの `.opencode` / `.claude` / `.agents` の下) で、symlink を追跡する。スキルの識別子は `SKILL.md` の親ディレクトリ名 (スキル置き場の直下にある `*.md` はファイル名) で、同じ識別子は 1 つにまとまるので、同じ実体が 2 経路から見えても二重には並ばない (opencode v2.0.22 のソースと、実環境のスキル置き場を `opencode api skill.list` で列挙して重複 0 件を 2026-10-03 に確認)。`~/.claude/skills` 側だけを読まない設定は V2 に無い。そのため除外リスト `claude_only_skills` は OpenCode には効かない (→「スキルの配布先の限定」節)。列挙は `opencode api skill.list > /tmp/s.json && jq '.data | length' /tmp/s.json` で見る。出力は 700KB を超えるので**パイプに直結せずファイルに落とす** (パイプだと途中で切れる)。**常駐サービスの起動直後は一覧が欠けて返る** (0 件のように) ので、件数が落ち着くのを待つのではなく、`jq -r '.data[].name'` に `dev-impl` が現れるまで 2 秒おきに最大 10 回繰り返す。10 回で現れなければ配布の失敗として扱う (手順は `agents/bindings/opencode/AGENTS.md` の確認コマンド)。2026-10-03 のこのマシンでは 61 件で、内訳は OpenCode の組み込み 2・git 管理のスキル 43・`synced` の下 10・`README.md` 1・`~/.agents/skills` に他ツールが入れたもの 5 である。この計測は yomiyasu の追加前のもので、git 管理のスキルが 45 本になった現在は測り直していない。Android は `~/.agents/skills` が埋まらないので `~/.claude/skills` からだけ読む。

**OpenCode が自動で読むグローバル指示は `~/.config/opencode/AGENTS.md` だけである。** V2 は `~/.claude/CLAUDE.md` へのフォールバックを持たない (opencode v2.0.22 の `packages/core/src/config/plugin/instruction.ts`、2026-10-03 に確認)。したがって `agents/bindings/opencode/AGENTS.md` には「共通の正本 `~/.claude/CLAUDE.md` を自分で Read せよ」と書いてある。Codex の binding と同じ構造で、Read 指示を書いておかないと共通ハーネスが届かない。

### subagent の書式変換 (agents/scripts/sync-subagents.ts)

subagent は 3 者で唯一**書式変換が避けられない**要素である (Claude は Markdown + frontmatter、Codex は TOML、OpenCode は `description` / `mode` だけの別スキーマ Markdown)。`agents/scripts/sync-subagents.ts` が `agents/subagents/*.md` を各形式へ書き、変換元が消えた生成物は prune する。変換そのもの (frontmatter の parse と各形式の生成) は `agents/scripts/subagent-format.ts` が持つ。

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
- **OpenCode で `name` を出さない理由**: OpenCode は subagent 名をファイルパスから決める (opencode v2.0.22 の `packages/core/src/config/plugin/agent.ts`。生成物 4 本が `opencode debug agents` に出ることを 2026-10-03 に確認。このコマンドも常駐サービスの起動直後は組み込みのエージェントだけを返すことがあり、組み込みも出力に含まれるので件数では判定できない。`dev-impl-implementer` / `fix-lsp-warnings` / `review-impl` / `tech-investigation` の 4 本の id が揃うまで 2 秒おきに最大 10 回繰り返し、揃わなければ配布の失敗として扱う)。正本の `name` をファイル名にするので識別は保たれる
- **OpenCode の description を double-quoted にする理由**: 正本の description にコロンを含むものがある (`dev-impl-implementer` の「`mode: implement` で新規実装」)。無引用の YAML プレーンスカラーだと 2 つ目のキーとして解釈されて壊れる
- **deno が無いとき**: 警告してスキップし activation は成功する (前回の生成物が残る)
- **失敗の見え方**: frontmatter の `name` / `description` 欠落、本文に `'''` を含む場合 (Codex のみ) は exit 1 で `drs` / `hms` ごと止まる

テストはこう回す。CI では回していないので、`agents/scripts/` か `agents/bindings/opencode/` (プラグインとそのテスト) を触ったら自分で実行する。

```bash
deno test --allow-env --allow-run --allow-read --allow-write agents/
```

### スキルの配布先の限定 (`~/.agents/skills` への配布から除外)

スキルは既定で 3 ランタイムへ配られる (同じ実体への symlink)。`~/.agents/skills` へ配らないものは `nix/modules/home/codex.nix` の `claude_only_skills` に列挙する。変数名は「Claude Code だけに残す」だが、**実際に除外が効くのは Codex だけ**である。**このリストが除外の唯一の正**で、現在の宣言は 2 件。`agents/skills/` にある git 管理のスキル 45 本のうち除外は 1 本で、もう 1 件はスキルではなく未追跡の同期キャッシュ。

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

**正本への symlink で配る本文は、`drs` / `hms` を待たずに反映される。** subagent の本文は Codex / OpenCode 向けに書式変換しているため、変更後に `drs` / `hms` が要る。スキルの追加・削除も Codex 向けの個別 symlink の更新が要る。Claude Code はどちらも正本のディレクトリを直接参照する。

| 対象 | 反映 | 理由 |
| --- | --- | --- |
| `AGENTS.md` / `rules/` / `skills/` の本文 | 即反映 (3 ランタイムとも) | 正本への symlink |
| `hooks/` `scripts/` `knowledge-profile.md` | 即反映 | 正本への symlink (`knowledge-profile.md` は `utility-doc-reading` が書き込む) |
| `bindings/claude/settings.json` `keybindings.json` / `bindings/codex/AGENTS.md` `config.toml` / `bindings/opencode/AGENTS.md` `opencode.json` `cli.json` `plugins/spark-served.ts` | 即反映 | 正本への symlink。OpenCode の常駐サービスが設定とプラグインの変更を検知して読み直す実装はソースにあるが、反映を実際に確かめてはおらず、読み直しを外から観測する手段も確かめていない (変更が効いていないように見えたら `opencode service restart`)。`cli.json` は TUI で設定を変えると symlink が切れる (→ Directory Structure の `agents/bindings/opencode/` 項) |
| スキルの追加・削除 | Claude と OpenCode は即反映 / **Codex は `drs` / `hms`** | `~/.claude/skills` がディレクトリごとの symlink で、OpenCode もここを読む。Codex は `~/.agents/skills/<name>` を 1 本ずつ張り直す activation (`linkAgentSkills`) が要る |
| subagent の本文・frontmatter の変更、追加・削除 | Claude は即反映 / **Codex と OpenCode は `drs` / `hms`** | Claude は `~/.claude/agents` がディレクトリごとの symlink。Codex は `~/.codex/agents/*.toml`、OpenCode は `~/.config/opencode/agents/*.md` の再変換・prune (`syncCodexSubagents` / `syncOpencodeSubagents`) が要る |
| `~/.claude/skills/` への第三者の書き込み | 即反映 (副作用あり) | 正本への symlink なので、他ツールが置いたディレクトリは dotfiles の `agents/skills/` (git 作業ツリー) に落ちる。**新たに増えたら sink を 2 つとも判断する**: commit するか (`.gitignore`) と `~/.agents/skills` へ配るか (`claude_only_skills`)。Claude Code の同期キャッシュ `synced` は両方で外してある |

### 開発ワークフローのスキル

```text
/dev-spec (設計ループ) → 承認ゲート (人間が起動) → /dev-impl (実装ループ)
```

詳細は `agents/skills/README.md` を参照 (タスク規模別の入口・モデル方針を含む)。主要スキル:
- `/dev-spec` — 設計ループ (ユーザーストーリー → ... → PoC 検証 → `docs/design/DESIGN.md` 1 枚 + `docs/design/features/` → GitHub issue をユースケース単位の親子 2 階層で生成 → 人間が確認)
- `/dev-impl` — 実装ループ (`ready` ラベルの open issue を依存順に自律実装、`model: opus`)
- `/dev-impl-quick` — 軽量実装ループ (docs 不要。依頼文をタスク分解して直営 TDD → review-impl → タスク単位コミット)
- `/workflow-review` (レビュー) / `/workflow-commit` (コミット) / `/workflow-create-draft-pr` (Draft PR) / `/workflow-debate` (壁打ち)

### hooks (agents/hooks/)

**deny する自作 hook は 1 本も無い。** `agents/hooks/` に置いてあるのは herdr 本体が配布する `herdr-agent-state.sh` の 1 本だけで、これは deny するゲートではなく herdr へセッション状態を渡すスクリプトである。

hook 以外の機械的な強制は 1 つだけ残っている。`agents/subagents/dev-impl-implementer.md` の `tools` から `Agent` を除いて**葉性を構造的に強制**している (subagent には親の hooks が届かず、指示文では違反を検出できないため)。

| ファイル | 起動元 | 役割 |
| --- | --- | --- |
| `herdr-agent-state.sh` | Claude Code の `settings.json` の SessionStart (`~/.claude/hooks/` 経由) | herdr にセッション状態を渡す。herdr 本体が配布するファイル。`settings.json` 側の登録が mac の絶対パス (`bash '/Users/skanehira/.claude/hooks/herdr-agent-state.sh' session`) で書かれているので、Linux でも SessionStart で起動はされる (登録に OS の条件が無いため) が、そのパスにファイルが無く bash が失敗する。Claude Code がこの失敗を表示するかは確かめていない |

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

以下は hook で強制せず、記述による自律遵守に委ねている。**破っても止まらないことを承知したうえでの設計判断**であり、設計思想は `agents/rules/core/references/loop-engineering.md` にある。

| 規律 | 正本 | 破られたときに何が起きるか | 事後に気づく手段 |
| --- | --- | --- | --- |
| コミット規約 (`<emoji> <type>: <subject>`) | `agents/rules/core/commit.md` | 形式の揃わないコミットが履歴に残る。push 前なら `git commit --amend` で直せる | `git log -1 --pretty=%s` を型と照合する (commit.md が手順として規定) |
| dev-impl の修正ラウンド上限 (1 周) | `agents/skills/dev-impl/SKILL.md` | 収束しない issue に時間とトークンが溶ける。**実測で 22 issue 中 6 件が 3 周目以降に入り、超過分だけで 5.7h を消費したことがある** | issue の完了コメントに残る「レビュー: N 周」。規定どおりなら N は最大 2 (r1 と fix 後の r2) なので、3 以上なら上限超過 |
| 実装系ルールの遅延参照 | `agents/AGENTS.md`「実装時」 | TDD やテスト方針を知らないまま実装が進む | **無い**。リマインドも事後検出もしない |
| subagent 起動時の `model` 明示 | `agents/rules/core/orchestration.md` | 未指定だと agent 定義の frontmatter ではなく親のセッションモデルを継承する。検証器が実行器より弱くなりうる | **無い**。セッションのログを人が読むしかない |
| utility-doc-audit の起動経路 (ユーザー起動と `/workflow-design-notes` の落とし込みのみ) | `agents/skills/utility-doc-audit/SKILL.md` | 普段の作業で監査が自発起動し、観点サブエージェントの fan-out 分のトークンを消費する | **無い**。`disable-model-invocation` を使わない判断のため、SKILL.md の description と本文の記述が唯一の抑止 |
| OpenCode が共通の正本を Read すること | `agents/bindings/opencode/AGENTS.md` | OpenCode は `~/.claude/CLAUDE.md` を自動では読まないため、指示を守らないと**エラーも警告も出さずに共通ハーネス無しで走る** | **無い**。セッションのログを人が読むしかない |

### subagents (agents/subagents/)

正本は Claude Code 形式 (Markdown + frontmatter) で、`~/.claude/agents/` へは symlink で配る。Codex と OpenCode へは `agents/scripts/sync-subagents.ts` が書式変換して置く (→「subagent の書式変換」節)。生成物は git 管理しない。

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

`drs` (mac) / `hms` (Linux) が `nix/modules/home/{claude,codex,opencode}.nix` を適用する。専用のインストールスクリプトは無い。`claude.nix` が Claude Code 向けの symlink を、`codex.nix` が Codex 向けの symlink と activation (`linkAgentSkills` / `syncCodexSubagents` / `installCodexPlugins`、Linux では加えて `linkCodexSystemConfig`) を、`opencode.nix` が OpenCode 向けの symlink と activation (`syncOpencodeSubagents` / `opencodeServiceConfig`) を持つ。

Android (`home-android.nix`) は `codex.nix` を import しないので Codex 向けだけが行われない。`opencode.nix` は import するため、Android でも OpenCode のグローバル指示と subagent は配られ、`service.json` の `hostname` も `0.0.0.0` に上書きされる。ただし `linkAgentSkills` が走らないので `~/.agents/skills` は埋まらず、OpenCode は `~/.claude/skills` からだけスキルを読む (→「配布先」節)。

**配布の確認**:

`readlink -f` は実ディレクトリでもそのパスを exit 0 で返すので、**移行済みかどうかの判定には使えない**。`test -L` で symlink であることを先に確かめる。

```bash
# 1. 配布先が symlink であること (実ディレクトリのまま残っていたら移行が終わっていない)
for p in ~/.claude/CLAUDE.md ~/.claude/rules ~/.claude/skills ~/.claude/agents \
         ~/.claude/hooks ~/.claude/scripts ~/.claude/knowledge-profile.md \
         ~/.claude/settings.json ~/.claude/keybindings.json \
         ~/.codex/AGENTS.md ~/.agents/skills/dev-impl /etc/codex/config.toml \
         ~/.config/opencode/AGENTS.md ~/.config/opencode/opencode.json \
         ~/.config/opencode/cli.json ~/.config/opencode/plugins/spark-served.ts; do
  [ -L "$p" ] && printf 'OK   %s -> %s\n' "$p" "$(readlink -f "$p")" || printf 'NG   %s (symlink ではない)\n' "$p"
done   # 16 行すべて OK で、解決先が dotfiles 配下であること

# 2. 生成物と除外
ls ~/.codex/agents                                # subagent 4 本の .toml がある
ls ~/.config/opencode/agents                      # subagent 4 本の .md がある
ls ~/.agents/skills | grep -cE '^(utility-session-profile|synced)$' || :   # 0 (Codex への配布から除外)
# codex のプラグインは下の「プラグインは別枠」の手順で 6 本だけ確かめる (codex plugin list の全体は 1 MB を超える)
opencode --version                                # opencode v2.0.22 (nix/pkgs/opencode.nix の version)。CLI の版しか見ないので、常駐サービスの版は Directory Structure の `agents/bindings/opencode/` 項の ps と readlink の比較で確かめる
```

**Android は 13 行で判定する。** `codex.nix` を import しないので `~/.codex/AGENTS.md` / `~/.agents/skills/dev-impl` / `/etc/codex/config.toml` の 3 行は NG になるのが正しく、`codex plugin list` も `codex` 自体が無い。残る 13 行が OK なら合格である。

**プラグインは別枠で、`installed` にならないことがある。** activation は失敗しても警告だけで止まらないので、`drs` / `hms` が通っても入ったとは限らない。6 本の名前で絞るコマンドは Directory Structure の `agents/bindings/codex/` 項にあり、2026-10-03 のこのマシンでは 6 本とも `installed, enabled` だった。落ちていたら `codex plugin marketplace add <入手元>` → `codex plugin add <名前>` を手で流す (入手元は同じ項の表)。ローカル clone の 2 本は clone のあるマシンでしか入らない。

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

### 配布方式の移行 (生成方式 → symlink)

**生成方式**とは、生成器 `build-harness.ts` (リポジトリには残っていない) が正本の語彙をランタイムごとに置き換えたコピーを配布先に書き、書いたパスを配布先の各ディレクトリの `.harness-manifest.json` に記録する配布方式である。この節の作業が要るのは、その manifest や生成物が残っているマシンと、`~/.config/opencode/cli.json` が symlink ではなくコピーで置かれた実ファイルのままのマシンだけである (`cli.json` のコピーは manifest に載らない)。

生成方式やコピーで置いた実体が残っていると、消すべき理由が 2 通りある。**混同すると手順を誤る。**

| 配布先 | 残っていると起きること | 消す理由 |
| --- | --- | --- |
| `~/.claude/{CLAUDE.md,rules,skills,agents}` / `~/.codex/AGENTS.md` / `~/.config/opencode/AGENTS.md` (以上は生成方式) / `~/.config/opencode/cli.json` (生成方式ではなくコピー) | HM が同じパスに symlink を張れず `checkLinkTargets` が衝突を報告する | **HM との衝突回避**。ディレクトリが空になりきらないと symlink が張れない |
| `~/.codex/{skills,agents}` / `~/.agents/rules` / `~/.config/opencode/skills` | 現在の配布先ではないので HM は何も言わない。`~/.codex/skills` に残ると同名スキルが 2 つの root から二重に列挙される (Codex は同名スキルをマージしない)。`~/.config/opencode/skills` に残ると、OpenCode は同名スキルを 1 つにまとめるので二重には並ばないが、古い実体と正本のどちらが採られるかは確認していない | **二重列挙と古い実体の混入の回避**。ディレクトリ自体は残ってよい |

衝突したときの挙動は **OS で違う**。

| OS (適用コマンド) | 退避の設定 | 衝突したとき |
| --- | --- | --- |
| mac (`drs`) | `home-manager.backupFileExtension = "hm-backup"` を `nix/flake.nix` の `darwinConfigurations` ブロックで設定済み | `Existing file … will be moved to '<path>.hm-backup'` を出して**退避**し、処理は続く (2026-10-03 にこのマシンにあった例: `~/.claude/skills.hm-backup` / `~/.config/opencode/cli.json.hm-backup`) |
| Linux (`hms`) | **設定が無い** (`mkLinuxHome` には `backupFileExtension` を渡していない) | 退避されず `Existing file … would be clobbered` で activation が止まる。`hms -b hm-backup` で渡すか、先に手で退避する |

退避されてもディレクトリは丸ごと移るので、放置すると `~/.claude/skills.hm-backup` のような大きな残骸が残る。**同居物を巻き込まないため、消すのは各ディレクトリの `.harness-manifest.json` に載っているパスだけ**にする。

**`~/.config/opencode/cli.json` は先に差分を見る。** 実ファイルの `cli.json` は TUI で変えた設定を持っていることがあり、下の掃除で消すと失われる。mac で先に `drs` を流した場合は、実ファイルが `cli.json.hm-backup` へ退避済みで、TUI で変えた値もそちらにある。残したい変更は repo 側の `agents/bindings/opencode/cli.json` へ写してから、掃除に進む。

```bash
# 実ファイルのときだけ差分を出す (symlink なら何も出ない)
[ -L ~/.config/opencode/cli.json ] || [ ! -e ~/.config/opencode/cli.json ] || \
  diff ~/.config/opencode/cli.json ~/dev/github.com/skanehira/dotfiles/agents/bindings/opencode/cli.json
# drs が退避した backup があれば、それとも差分を取る
[ ! -e ~/.config/opencode/cli.json.hm-backup ] || \
  diff ~/.config/opencode/cli.json.hm-backup ~/dev/github.com/skanehira/dotfiles/agents/bindings/opencode/cli.json
```

```bash
# 共通の掃除関数。manifest に載っているパスと、それが空にした親だけを消す
prune_manifest() {
  m="$1"
  [ -L "$m" ] && return 0                          # 既に symlink なら移行済み
  [ -f "$m/.harness-manifest.json" ] || return 0   # manifest が無ければ対象外
  paths=$(jq -r '.paths[]' "$m/.harness-manifest.json") || {
    echo "manifest が読めない (手で確認する): $m" >&2; return 1; }
  [ -n "$paths" ] || { echo "manifest が空 (手で確認する): $m" >&2; return 1; }
  printf '%s\n' "$paths" | while read -r p; do
    [ -n "$p" ] && rm -rf "$m/$p"                  # 空文字だと $m ごと消えるので弾く
  done
  # manifest はファイル単位なので、載っていた top-level の配下だけ空の親を掃除する
  printf '%s\n' "$paths" | cut -d/ -f1 | sort -u | while read -r d; do
    [ -n "$d" ] && [ -d "$m/$d" ] && find "$m/$d" -type d -empty -delete
  done
  rm -f "$m/.harness-manifest.json"
}

# HM が symlink を張る 3 つ。空になったディレクトリ自身も消す (残すと衝突する)
for m in ~/.claude/rules ~/.claude/skills ~/.claude/agents; do
  prune_manifest "$m" && rmdir "$m" 2>/dev/null || :   # 同居物があれば rmdir は失敗して残る
done

# 二重列挙と古い実体の混入を避けるための掃除。ディレクトリ自身は Codex / OpenCode の所有物なので残す
for m in ~/.codex/skills ~/.codex/agents ~/.config/opencode/skills ~/.config/opencode/agents; do
  prune_manifest "$m" || :
done

rm -f ~/.claude/CLAUDE.md ~/.codex/AGENTS.md ~/.config/opencode/AGENTS.md
[ -L ~/.config/opencode/cli.json ] || rm -f ~/.config/opencode/cli.json   # 上の差分を写し終えている前提
rm -rf ~/.agents/rules/codex ~/.agents/rules/opencode   # 旧生成器の出力先。現在は両者とも ~/.claude/rules を直接読む
rmdir ~/.agents/rules 2>/dev/null || :

# 適用は人間が実行する (上の削除は sudo 不要)
drs                  # mac。Touch ID 経由の sudo が要る
hms -b hm-backup     # Linux。退避設定が無いので -b が要る。sudo は /etc/codex/config.toml の symlink 用
```

manifest の `paths` は**ファイル単位**の相対パスなので、削除しただけでは入れ物のディレクトリが残る (`~/.claude/skills/dev-spec/references` のような空の殻)。`find` が manifest に載っていた top-level の配下だけを掃除し、最後の `rmdir` がディレクトリ自身を消して HM が symlink を張れる状態にする。`find` の起点を `$m` にすると同居物 (`~/.codex/skills/.system` など) の空ディレクトリまで消すので top-level に絞り、`rmdir` は同居物があれば失敗して何もしない。

manifest がそもそも無いマシン (生成方式を経ていない新規マシン) では `prune_manifest` が全て skip する。そのうえ `cli.json` も symlink か不在なら、この作業自体が不要になる。`.hm-backup` が既にある状態で `drs` / `hms` を再実行すると `Existing file '<path>.hm-backup' would be clobbered by backing up` で止まるので、その場合は古い `.hm-backup` を退避または削除してからリトライする。

**完了の判定は「配布」節の「配布の確認」のコマンドで行う** (`drs` / `hms` が通っただけでは足りない)。あわせて旧配布先に dotfiles 由来のものが残っていないことを次で確かめ、`~/.claude/*.hm-backup` と `~/.config/opencode/*.hm-backup` を残すか消すかを決めるまでが完了条件。`.hm-backup` を残すと、同じパスが次に退避されるときの `drs` が止まる。判定は 3 段で行う。生成方式の実体の消し残しは `readlink -f` が自分自身のパスを返すので解決先では見分けられず、manifest が残っていないことで判定する。dotfiles への symlink の残りは、単なる `ls` では第三者が入れたものと区別できないので解決先で判定する。旧生成器の出力先 `~/.agents/rules` は上の `rm -rf` と `rmdir` で消えるので、存在しないことで判定する。

```bash
# 1. manifest が残っていない (prune_manifest は最後に manifest を消すので、残っていれば掃除が終わっていない)
for m in ~/.claude/rules ~/.claude/skills ~/.claude/agents \
         ~/.codex/skills ~/.codex/agents ~/.config/opencode/skills ~/.config/opencode/agents; do
  [ -f "$m/.harness-manifest.json" ] && echo "NG manifest が残っている: $m"
done
# 2. 旧配布先に dotfiles への symlink が残っていない。find はディレクトリが無くても止まらず、zsh でも bash でも同じに動く
find ~/.codex/skills ~/.config/opencode/skills -mindepth 1 -maxdepth 1 2>/dev/null | while read -r d; do
  case "$(readlink -f "$d")" in */dotfiles/agents/skills/*) echo "NG $d" ;; esac
done
# 3. 旧生成器の出力先 ~/.agents/rules が残っていない
[ -e ~/.agents/rules ] && echo "NG ~/.agents/rules が残っている"
# 1 行も出なければ合格 (他ツールが入れたものは解決先が違うので出ない)
```

生成方式へ戻すときは `277086e` (配布方式の切り替え) 以降のコミットを `git revert` して `drs` / `hms` を流す。`.hm-backup` は revert しても残るので手で片付ける。

`~/.agents/skills` の他ツール由来スキル (例: `find-skills`。dotfiles への symlink ではない実ディレクトリ)、`~/.codex/skills` の同居物 (`.system` と、plugin や他ツール (`wrangler login` 等) が入れたもの)、`~/.config/opencode/` の同居物のうち `service.json` と V1 のプラグイン SDK の 4 つ (`node_modules` / `package.json` / `package-lock.json` / `.gitignore`) は触らない。同じディレクトリの `agents/` と `skills/` は上の `prune_manifest` が、`*.hm-backup` は上の完了条件が扱う (同居物の一覧は Directory Structure の `agents/bindings/opencode/` 項の「グローバル指示の確認と同居物」)。

`~/.claude/skills` はディレクトリごと symlink するため、manifest 外の同居エントリは HM の退避で `~/.claude/skills.hm-backup` へ移る。生かしたいものがあれば手で戻す (ただし戻すと第三者のデータが dotfiles の git 作業ツリーに入る)。

### 解消しない非対称

- **ツールの引数の形**は 3 者で揃えていない。スキル・ルール・subagent の本文はツールの呼び出し例 (引数つき) を載せず、何を聞くか・何を起動するかの意図だけを書くので、引数は各ランタイムが自分のツールのスキーマで組み立てる。Codex と OpenCode のツールスキーマを実測する手段が無く、推測で例を書くと誤った例を配ることになるため。本文に残るツール名は binding の読み替え表で読む。スキルの frontmatter の `allowed-tools` は Claude 綴りのまま残り (扱いは `agents/bindings/{codex,opencode}/AGENTS.md` の「読み替えで吸収できないもの」節)、subagent の `tools` は書式変換で生成物から落ちる (扱いは同じ 2 ファイルの「3 者で表現できない subagent の属性」節)
- **選択式の質問の形**も揃わない。Codex の `request_user_input` は 2〜3 択の単一選択で (codex 0.159.2 のバイナリに含まれる文字列が根拠で、公式のスキーマは未確認)、OpenCode の `question` は選択肢の数と複数選択の可否を確かめていない。両 binding とも同じ線を引き、4 択以上や複数選択の質問は、選択肢を番号付きでメッセージに並べて番号で答えてもらうと書いてある
- **rules の自動展開**は Claude Code 固有。`paths:` frontmatter による条件付きロードも Claude Code だけの機構で、Codex と OpenCode はグローバル指示から「Read せよ」と指示された分しかコンテキストに入らない。3 者で「同じルールが同じタイミングで効く」ことまでは保証していない
- **共通の正本の自動読み込み**は Claude Code だけが持つ。Codex と OpenCode は自分の AGENTS.md (`~/.codex/AGENTS.md` / `~/.config/opencode/AGENTS.md`) しか自動では読まず、`~/.claude/CLAUDE.md` へのフォールバックも無い。共通の正本は binding 内の Read 指示で届ける。指示を守るかはモデル任せで、Claude Code の自動展開のような機械的な保証は無い

## 依拠する外部事実

本文の日付付きの件数・実測値は、その確認日の記録である。現在の配置や件数を判断するときは、次の確認元と方法で調べ直す。以下は確認方法の一覧であり、全マシンで同じ状態であることを保証しない。

| 確認するもの | 確認元 | 確認方法 |
| --- | --- | --- |
| Nix のプロファイル・OS 別の import | `nix/flake.nix` / `home-darwin.nix` / `home-linux.nix` / `home-android.nix` | 各 output の system と module の import 一覧を読む |
| ハーネスの symlink と subagent の生成 | `nix/modules/home/claude.nix` / `codex.nix` / `opencode.nix`、`agents/scripts/sync-subagents.ts` | 「配布の確認」のコマンドで symlink の解決先と生成物を確認する。変換結果は正本の本文と生成物の本文を照合する |
| スキル・subagent の本数と配布除外 | `agents/skills/` / `agents/subagents/`、`codex.nix` の `claude_only_skills` | 下のコードブロックで git 管理分を数え、「スキルの配布先の限定」と実際の配布先を照合する |
| Claude のプラグイン・hook の件数 | `agents/bindings/claude/settings.json` | 下のコードブロックで件数だけを出す。プラグインの実際の導入状態は設定上の有効件数と分け、Codex 側は専用の 6 本を確認する既載のコマンドを使う |
| Nix の CI と agent 関連の手動テスト | `.github/workflows/nix-check.yml`、`agents/scripts/` と `agents/bindings/opencode/` のテスト | CI の対象パスと実行コマンドを読む。agent 関連は「subagent の書式変換」の `deno test` を手で実行する |
| subagent のモデル指定・継承とゲートの有無 | `agents/scripts/subagent-format.ts`、`agents/bindings/codex/config.toml`、各 binding の `AGENTS.md`、各スキル・ルール | 生成するキーとランタイム側の設定を確認する。検出手段の有無は「機械検証が無い規律」と規定元を照合し、ログから未確認の順序を実施済みとしない |
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
