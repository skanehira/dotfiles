# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

- 種別: プロジェクト運用ガイド

## Repository Overview

dotfiles リポジトリ。macOS は **Nix (nix-darwin + Home Manager)**、Linux は **Home Manager standalone (非 NixOS)** で宣言的管理。設定ファイルは `home.file` × `mkOutOfStoreSymlink` で dotfiles 直接 symlink としてバインドし、live edit を維持する。

## Installation

### 初回セットアップ (macOS 新マシン)

```bash
# clone 先は ~/dev/github.com/skanehira/dotfiles 固定
# (claude.nix / neovim.nix の mkOutOfStoreSymlink と darwin/codex.nix の environment.etc がこの path を直参照するため)
mkdir -p ~/dev/github.com/skanehira
cd ~/dev/github.com/skanehira
git clone https://github.com/skanehira/dotfiles.git
cd dotfiles

# Nix install + nix-darwin 適用
bash ./bootstrap.sh
```

`bootstrap.sh` は (1) Nix 未導入時のみ公式 installer を実行し、(2) `nix/install.sh` 経由で `sudo nix run nix-darwin -- switch --flake .#skanehira` を回す。途中で Nix installer の y/n プロンプトと `sudo` (Touch ID / パスワード) が要求される。既存マシンでは Nix install を skip するので idempotent。

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

activation 中に `modules/home/codex.nix` が `sudo` で `/etc/codex/config.toml` を `codex/config.toml` へ symlink する (Home Manager standalone には `/etc` を宣言する option が無いため。`codex.nix` を import しない `-android` は対象外)。`sudo` が使えない環境では警告と手動コマンドが表示されるだけで activation は失敗しない。

`linuxUsers` に列挙したユーザーごとに 3 つの output が生える。用途で選ぶ。

| output | system | 入口 | 用途 |
| --- | --- | --- | --- |
| `.#<user>` | x86_64-linux | `home-linux.nix` | 通常の Linux (Ubuntu container / サーバー) |
| `.#<user>-aarch64` | aarch64-linux | `home-linux.nix` | 同上の arm 版 |
| `.#<user>-android` | aarch64-linux | `home-android.nix` | Android の Termux + proot-distro Debian |

ログインユーザーが `skanehira` でないマシン (CI / 検証箱など) では、`flake.nix` の `linuxUsers` にそのユーザー名を足してから `.#<ユーザー名>` を指定する (例: ubuntu なら `.#ubuntu`)。`$USER` を動的に読む impure 方式は `nh` / `home-manager` が pure 評価で output を引くため `hms` 等で壊れる。よって pure に列挙する。

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

### Nix 管理（中核）

- **nix/** — flake-based config（最も重要）
  - `flake.nix` — inputs, outputs (`darwinConfigurations.skanehira` + `homeConfigurations.{skanehira,skanehira-aarch64,skanehira-android}`)
  - `home-core.nix` — 全プロファイル共通の土台 (dotfilesRoot / stateVersion / programs.home-manager)。module の import は持たない
  - `home.nix` — フルセットのプロファイル (mac と通常 Linux が共有)
  - `home-darwin.nix` — mac 用エントリ (home.nix + karabiner + `homeDirectory = /Users/...`)
  - `home-linux.nix` — 通常 Linux 用エントリ (home.nix + `homeDirectory = /home/...`)
  - `home-android.nix` — Android (Termux + proot) 用エントリ (home-core.nix + 軽量 module のみ)
  - `darwin.nix` — nix-darwin imports のみ
  - `modules/home/` — Home Manager modules（CLI パッケージ、env、git、gh、zsh、fzf、direnv、tmux、wezterm、karabiner 等）
  - `modules/darwin/` — nix-darwin modules（system、homebrew、codex）
  - `modules/overlays.nix` — nix-darwin 用 overlays モジュール (overlays-list.nix を消費)
  - `modules/overlays-list.nix` — overlay の素のリスト (mac/Linux 両側で共有)
  - `install.sh` — mac bootstrap 用（一度限り）

### Nix 補助

- **zsh/** — `programs.zsh.initContent` から `builtins.readFile` で取り込まれる残置ファイル
  - `zshrc` — bindkey 群 + 関数 source loop
  - `functions/{ghq-fzf,gss,tmuxpopup}.zsh` — カスタム zsh 関数
- **karabiner/** — Karabiner-Elements 設定 (Goku DSL)
  - `karabiner.edn` — EDN で書いたルール、switch 時に goku が `~/.config/karabiner/karabiner.json` を生成
- **wezterm/** — WezTerm 設定（`programs.wezterm.extraConfig` から `builtins.readFile` で取り込み）
  - `wezterm.lua` — Lua の編集体験 (lua_ls) を保つため別ファイルとして残置
- **tmux/** — tmux 設定（`mkOutOfStoreSymlink` で dotfiles 直接 symlink、live edit 可能）
  - `tmux.conf` — 編集即反映、`prefix + r` で reload。`drs` 不要
  - プラグインの run-shell だけは nix store path 解決のため Nix 生成の `~/.config/tmux/plugins.conf` 経由
- **agents/** — AI エージェント共通のハーネス正本（`mkOutOfStoreSymlink` で dotfiles 直接 symlink、live edit 可能）
  - `AGENTS.md` / `skills/` / `rules/` / `hooks/` / `scripts/` / `bindings/` / `knowledge-profile.md` — 編集即反映、`drs` 不要
  - `subagents/` だけは例外。Claude Code へは symlink なので即反映だが、Codex と OpenCode へは書式変換を挟むので `drs` / `hms` が要る
  - 配布先と構成は「AI エージェントのハーネス (agents/)」節を参照
- **codex/** — Codex 設定（`/etc/codex/config.toml` へ dotfiles 直接 symlink、live edit 可能）
  - `config.toml` — git 管理する Codex 共通設定。Codex の system レイヤー `/etc/codex/config.toml` として、CLI / ChatGPT.app 内 Codex を含む全クライアントに読まれる
  - `config.toml` の `[[hooks.PreToolUse]]` は `agents/hooks/commit-msg-guard.ts` を Codex 側でも起動する。Codex の hooks は Claude Code と同じ wire format (`tool_name` / `tool_input.command` / `hookSpecificOutput.permissionDecision`) なので、hook スクリプトを両ランタイムで共有できる。**system レイヤーに置いた hooks は信頼ゲートを通らず発火する**のに対し、`~/.codex/hooks.json` (user レイヤー) に置いたものは `/hooks` で承認するまで**無言でスキップ**される (実測。承認を促すメッセージも出ない)。したがって dotfiles で配る hooks は必ず `codex/config.toml` に書く
  - hook の `command` はシェル経由で解釈されるため `$GHQ_ROOT` が展開できる。mac と Linux で dotfiles の絶対パスが違うので、パスは環境変数経由で書く
  - `AGENTS.md` — `~/.codex/AGENTS.md` に symlink するグローバル Codex 指示
  - `~/.codex/config.toml` (user レイヤー) は dotfiles で管理しない。Codex 自身が `[projects.*]` trust / `[notice]` / `/model` の選択 / `notify` / `[mcp_servers.*]` / `[plugins.*]` を書き込む可変状態で、ここにあるキーは system レイヤー (`/etc/codex/config.toml`) の同名キーより優先され続ける
  - 旧方式 (Home Manager が `~/.codex/config.toml` を生成) を使っていたマシンでは、`drs` / `hms` 後に 1 回だけ `~/.codex/config.toml` から `codex/config.toml` と重複するキーを手で削除する。残さないと `/etc` 側の値が遮蔽される
  - 配布の確認: `readlink -f /etc/codex/config.toml` が dotfiles の `codex/config.toml` に解決すること
- **vim/** — Neovim 設定（`mkOutOfStoreSymlink` で dotfiles 直接 symlink、live edit 可能）
  - `init.lua` / `lua/` / `after/` — 編集即反映、`drs` 不要
  - `.luarc.json` — lua_ls の dotfiles 内 lua 編集用設定 (track 対象)
- **docs/** — Nix 設定だけでは伝わらない環境固有の手順書
  - `android-dev-setup.md` — Galaxy Z Fold 8 Ultra を Termux + proot-distro Debian で開発端末にする手順と制約

## Nix モジュール構成（詳細）

```
nix/
├── flake.nix              ← inputs + darwinConfigurations + homeConfigurations
├── flake.lock
├── home-core.nix          ← 全プロファイル共通の土台 (module の imports は持たない)
├── home.nix               ← フルセット (home-core.nix + 全 module の imports)
├── home-darwin.nix        ← home.nix + karabiner + homeDirectory=/Users/...
├── home-linux.nix         ← home.nix + homeDirectory=/home/...
├── home-android.nix       ← home-core.nix + 軽量 module + homeDirectory=/home/...
├── darwin.nix             ← imports modules/darwin/
├── install.sh             ← mac bootstrap
└── modules/
    ├── overlays.nix       ← nix-darwin 用 module (overlays-list.nix を nixpkgs.overlays に流す)
    ├── overlays-list.nix  ← overlay の素のリスト (HM standalone の pkgs= からも参照)
    ├── home/
    │   ├── claude.nix    — Claude Code (bootstrap install + agents/ を ~/.claude/* へ mkOutOfStoreSymlink)
    │   ├── codex.nix     — Codex (`~/.codex/AGENTS.md` symlink + agents/skills を ~/.agents/skills へ個別 symlink。Linux のみ /etc/codex/config.toml を sudo で symlink)
    │   ├── deno.nix      — bootstrap-install (~/.deno/bin/deno 不在時のみ公式 installer 実行)
    │   ├── direnv.nix    — programs.direnv + nix-direnv
    │   ├── env.nix       — sessionVariables / sessionPath
    │   ├── fzf.nix       — programs.fzf (default command/options, zsh integration)
    │   ├── gh.nix        — programs.gh (GitHub CLI)
    │   ├── git.nix       — programs.git (LFS, alias, difftastic)
    │   ├── herdr.nix     — herdr の config.toml を mkOutOfStoreSymlink で live edit
    │   ├── karabiner.nix — goku で karabiner.edn → karabiner.json (mac only。home-darwin.nix からのみ import)
    │   ├── mac-app-util-icons.nix — .app の trampoline アイコン調整 (mac only)
    │   ├── neovim.nix    — vim/{init.lua,lua,after} を mkOutOfStoreSymlink で live edit
    │   ├── opencode.nix  — OpenCode (opencode.json / tui.json / AGENTS.md を mkOutOfStoreSymlink + sync-subagents.ts で ~/.config/opencode/agents を生成)
    │   ├── packages.nix  — home.packages 群（CLI 50+、nvtop / libreoffice-bin / terminal-notifier は darwin only）
    │   ├── packages-android.nix — Android 用の明示リスト (19 エントリ。binary cache から取れる軽量なものだけ)
    │   ├── rustup.nix    — bootstrap-install (~/.cargo/bin/rustup 不在時のみ公式 installer 実行)
    │   ├── tmux.nix      — tmux/tmux.conf を mkOutOfStoreSymlink で live edit。plugins.conf のみ Nix 生成 (resurrect + themepack)
    │   ├── vite-plus-bootstrap.nix — bootstrap-install (~/.vite-plus/bin/vp 不在時のみ公式 installer 実行。Android のみ import)
    │   ├── wezterm.nix   — programs.wezterm (extraConfig は wezterm.lua を readFile)
    │   └── zsh.nix       — programs.zsh (history, completion, prompt、homebrew/linuxbrew 分岐済) + shellAliases (drs/hms を OS 別 lib.optionalAttrs。hms の -c には configName が入る)
    └── darwin/
        ├── codex.nix     — /etc/codex/config.toml を codex/config.toml へ symlink (environment.etc)
        ├── homebrew.nix  — declarative brews / casks
        ├── sleepctl.nix  — 蓋閉じ監視デーモン (disablesleep 中に蓋を閉じたら pmset displaysleepnow を 1 回打つ)
        └── system.nix    — users, nix.settings, Touch ID, primaryUser
```

### 重要な設計判断

- **設定の key**: ホスト名は使わない。複数マシンで同じ設定が走る前提。`darwinConfigurations` の key は username (`skanehira`)、`homeConfigurations` の key は `configName` (username にプロファイル接尾辞を足したもの。`skanehira` / `skanehira-aarch64` / `skanehira-android`)。
- **system 値**: darwin は `aarch64-darwin` 固定 (Apple Silicon)。Linux は `skanehira` (x86_64-linux)、`skanehira-aarch64` (aarch64-linux)、`skanehira-android` (aarch64-linux) の 3 出力。
- **モジュール共有**: `home-core.nix` が全プロファイル共通の土台 (dotfilesRoot / stateVersion / programs.home-manager) で、module の import は持たない。「どのツールを入れるか」はプロファイル側の決定なので、`home.nix` (フルセット) と `home-android.nix` (軽量) がそれぞれ import 一覧を持つ。`home-darwin.nix` / `home-linux.nix` は `home.nix` に homeDirectory を足す wrapper。mac 専用 module は `karabiner.nix` / `wezterm.nix` / `mac-app-util-icons.nix` で `home-darwin.nix` からだけ import。`tmux.nix` / `zsh.nix` は内部で `lib.optionalString isDarwin/isLinux` 分岐済。
- **Android を別プロファイルにする理由**: proot は RAM が数 GB でストレージも Termux のアプリ内領域に載り、binary cache に無いものをローカルビルドできない。フルセットは完走しないため、`packages-android.nix` に軽量なものを 19 エントリだけ明示列挙する (`programs.git` 等が足す分と HM 内部を含めて `home.packages` は 34 件)。規模の差は下表のとおり。neovim は nightly overlay ではなく nixpkgs の stable を使う。

  | プロファイル (aarch64-linux) | ローカルビルド | fetch 件数 | ダウンロード | 展開後 |
  | --- | --- | --- | --- | --- |
  | `skanehira-android` | 46 件 (全て HM の設定生成と wrapper。コンパイルなし) | 325 | 542.4 MiB | 1.9 GiB |
  | `skanehira-aarch64` (フルセット) | 693 件 (neovim nightly / terraform / herdr 等のコンパイルを含む) | 1545 | 3.5 GiB | 13.0 GiB |

  計測条件: 2026-09-06、mac (aarch64-darwin) から `nix build --dry-run` を両者連続実行。Claude Code / Deno / Vite+ は activation 時に公式インストーラを走らせるので、この数値には含まれない。fetch 件数は実行マシンの nix store に既にある分を除いた値なので、まっさらな端末では増える。
- **overlays の共有**: `modules/overlays-list.nix` が overlay の素のリストを export し、nix-darwin (`modules/overlays.nix` 経由) と HM standalone (`flake.nix` の `import nixpkgs` 経由) の両方から参照される。
- **Homebrew**: GUI app (cask) と CLI のうち (a) cask の依存になるコア formula、(b) nixpkgs 未収録 (例: `aqua`) のみ管理 (mac only)。それ以外の CLI ツールは Nix 管理。`brews` には `ca-certificates` / `openssl@3` / `sqlite` を保険として明示宣言 (cask 依存リンクが切れた時の巻き添え削除を防止)。`onActivation.cleanup = "uninstall"` で宣言外は drs 時に自動撤去。
- **Touch ID for sudo**: `security.pam.services.sudo_local.touchIdAuth + reattach` で tmux 内含めて指紋認証 (mac only)。

## sudo の扱い（重要）

このマシンでは `pam_tid` (Touch ID) + `pam_reattach` (tmux 対応) が `/etc/pam.d/sudo_local` に設定済み。

### ⚠️ `sudo -n` (`--non-interactive`) は使わない

`-n` フラグは PAM 認証を**完全にスキップ**する。Touch ID プロンプトすら出ない。代わりに「a password is required」エラーで即終了する。

```bash
# ❌ Touch ID が呼ばれず失敗する
sudo -n darwin-rebuild switch ...

# ✅ Touch ID ダイアログが出て指紋で通せる（TTY なし環境でも OK）
sudo darwin-rebuild switch ...
```

スクリプトや Claude Code の Bash ツールから `sudo` を呼ぶときも同様。`-n` を付けないことで PAM が GUI 認証ダイアログを発火させ、ユーザの指紋で認証できる。

## Nix daemon のトラブルシュート (macOS)

`drs` が下記で即落ちする場合、`nix-daemon` (launchd) が落ちている。

```
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

- plist 本体は Determinate Systems の Nix installer が `/Library/LaunchDaemons/org.nixos.nix-daemon.plist` に配置している。`darwin-rebuild` ではなく Nix installer の所有物。
- 一度 `load` すれば再起動後も自動起動する想定。再発する場合は plist の `KeepAlive` が無効化されていないか、`nix-darwin` 側で `nix.enable = false` 相当の設定が混入していないか (`nix/modules/darwin/system.nix`) を確認する。
- `/Library/LaunchDaemons/systems.determinate.nix-installer.nix-hook.plist` は別物 (Determinate の post-install hook)。混同しない。

## Neovim Configuration

### Structure
- `vim/lua/plugins/` — lazy.nvim プラグイン設定
- `vim/lua/settings/` — 基本設定（options.lua, keymaps.lua, lsp.lua, autocmd.lua）
- `vim/lua/modules/` — カスタムモジュール（AI, markdown）
- `vim/after/lsp/` — LSP 個別設定 (denols, rust_analyzer, lua_ls, nixd, version_ls, yamlls)

### Key Paths
- ghq リポジトリ: `$HOME/dev`
- Go バイナリ: `$HOME/go/bin`
- Deno バイナリ: `$HOME/.deno/bin`

### Neovim 本体

フルセット (mac / 通常 Linux) は `neovim-nightly-overlay` の **nightly ビルド**を使う。binary cache が無く更新時は手元でビルドする。アップデートは `nix flake update neovim-nightly-overlay`。

Android プロファイルだけは `pkgs.neovim` (nixpkgs-unstable の **stable release**、`cache.nixos.org` 経由でビルド済) を使う。proot で nightly をビルドできないため。こちらのアップデートは `nix flake update nixpkgs`。

## AI エージェントのハーネス (agents/)

プロンプト・スキル・ルール・hooks・subagent の正本は `agents/` に置き、Claude Code / Codex / OpenCode の 3 者へ配る。ランタイム固有の名前 (`~/.claude/CLAUDE.md` 等) は Nix module 側で与える。

```
agents/
├── AGENTS.md            ← グローバル指示。~/.claude/CLAUDE.md と ~/.config/opencode/AGENTS.md へ symlink
├── skills/              ← ~/.agents/skills/<name> へ個別 symlink (Codex と OpenCode が直読み)。Claude Code へは ~/.claude/skills をディレクトリごと symlink
├── rules/               ← core/ backend/ frontend/ infra/
├── hooks/               ← commit-msg-guard.ts / fix-round-guard.ts
├── subagents/           ← Claude Code へは symlink、Codex と OpenCode へは変換して配る 4 本
├── scripts/             ← agent / skill から ~/.claude/scripts/<name> の形で呼ぶ + statusLine + 配布用の変換スクリプト
├── knowledge-profile.md ← ~/.claude/knowledge-profile.md へ symlink (utility-doc-reading が読み書きする)
└── bindings/            ← ランタイム固有の設定ファイル
    ├── claude/          ← settings.json / keybindings.json / settings.{deepseek,spark}.json (後 2 者は zsh/functions/claude-deepseek.zsh が --settings で読む)
    └── opencode/        ← opencode.json / tui.json
```

**Codex 向けだけは `codex/` に残してある。** `config.toml` は `/etc/codex/config.toml` の system レイヤーとして配るため `nix/modules/darwin/codex.nix` が絶対パスを直参照する。`codex/AGENTS.md` も Codex 専用の別正本で、`~/.codex/AGENTS.md` へはこちらが symlink される (Claude Code と OpenCode が受け取る `agents/AGENTS.md` とは中身が違う)。**グローバル指示だけは 3 者で 1 枚に統一できていない。**

### 開発ワークフローのスキル

```
/dev-spec (設計ループ) → 承認ゲート (人間が起動) → /dev-impl (実装ループ)
```

詳細は `agents/skills/README.md` を参照 (タスク規模別の入口・モデル方針を含む)。主要スキル：
- `/dev-spec` — 設計ループ (ユーザーストーリー → ... → PoC 検証 → DESIGN/DETAIL → TODO 生成 → 承認ゲート。手順は references/ に集約、クイックモード・部分実行可)
- `/dev-impl` — 実装ループ (TODO 全フェーズを自律実装、`model: opus`。中小タスクはスキルを使わず plan mode / 直接依頼 + 直営 TDD)
- `/workflow-review` (レビュー) / `/workflow-commit` (コミット) / `/workflow-create-draft-pr` (Draft PR) / `/workflow-debate` (壁打ち)

### hooks (agents/hooks/)

deny する機械ゲートは 2 本で、ほかに herdr 連携用のスクリプトが 1 本ある。詳細と「機械ゲートを置いていない規律」は `agents/hooks/README.md` にある。

2 本のゲートは `settings.json` / `codex/config.toml` に書いた `$GHQ_ROOT` 経由の絶対パスを `deno run` で叩くので、`~/.claude/hooks` の symlink は経由しない (`GHQ_ROOT` は `nix/modules/home/env.nix` が `$HOME/dev` に設定する)。`~/.claude/hooks` が要るのは herdr の 1 本だけである。

| hook | 起動元 | 役割 |
| --- | --- | --- |
| `commit-msg-guard.ts` | Claude Code の `settings.json` と Codex の `codex/config.toml` | `git commit` の subject を Conventional Commit 形式で機械検証する |
| `fix-round-guard.ts` | Claude Code の `settings.json` のみ (Agent ツール入力に依存するため Codex へは移植しない) | dev-impl の修正ラウンド上限 (2 周) を強制する |
| `herdr-agent-state.sh` | Claude Code の `settings.json` の SessionStart (`~/.claude/hooks/` 経由) | herdr にセッション状態を渡す。herdr 本体が配布するファイルで mac の絶対パスが埋まっており、Linux では発火しない |

### subagents (agents/subagents/)

正本は Claude Code 形式 (Markdown + frontmatter)。3 者で唯一**書式変換が避けられない**要素で、`agents/scripts/sync-subagents.ts` が activation 時に変換する。生成物は git 管理しない。変換は `deno.nix` の bootstrap 後に走り、deno が無ければ警告して生成をスキップする (`~/.codex/agents` が空のときはまずこれを疑う)。生成物の先頭には `# generated by agents/scripts/sync-subagents.ts` の 1 行が入り、正本から消えた subagent の撤去はこの行を持つファイルだけを対象にする。配布先は人が自分の agent を 置く場所でもあるため、拡張子だけで消すと手書きを巻き込む。

| 配布先 | 形式 | 経路 |
| --- | --- | --- |
| `~/.claude/agents/` | 正本そのもの | `claude.nix` の symlink |
| `~/.codex/agents/*.toml` | `name` / `description` / `developer_instructions` の 3 キー | `codex.nix` が `sync-subagents.ts ... codex` を実行 |
| `~/.config/opencode/agents/*.md` | `description` + `mode: subagent` の frontmatter | `opencode.nix` が `sync-subagents.ts ... opencode` を実行 |

**落とすキーが 3 つある。** `tools` は Codex に対応キーが無く、OpenCode は真偽値マップで意味が反転する。`model` は Codex では実モデル名が要り alias が使えないため、世代交代に追従できるよう生成物には書かない (固定するなら `codex/config.toml` の `[agents] default_subagent_model` に 1 箇所だけ書く。現状は未設定で、Codex 側の subagent は親のモデルを継承する)。`context: fork` に相当する概念はどちらにも無い。

### rules (agents/rules/)

- `core/` — tdd.md / commit.md / design.md / testing.md / implementation.md / verification.md / orchestration.md ほか
- `backend/` `frontend/` — 言語・フレームワーク別コーディング規約
- `infra/dgx-spark.md` — 自宅の DGX Spark 2 台クラスタの環境リファレンス

配布先は `~/.claude/rules` の 1 本だけ。Codex と OpenCode はグローバル指示の記述に従ってこの絶対パスを直接 Read する。

### 配布

`drs` (mac) / `hms` (Linux) が `nix/modules/home/{claude,codex,opencode}.nix` を適用して symlink を張る。専用のインストールスクリプトは無い。

## Working with This Repository

### 既存設定の変更（Nix 管理側）

1. `nix/modules/home/*.nix` または `nix/modules/darwin/*.nix` を編集
2. `git add` で staging（flake は tracked file しか見ない）
3. `drs` (mac) / `hms` (Linux) で適用（`nh` が darwin-rebuild / home-manager を起動。mac は Touch ID 経由の sudo）

### 新規ツール追加

- CLI: `modules/home/packages.nix` に追記。Android でも使うなら `modules/home/packages-android.nix` にも足す (別リストなので自動では入らない)
- 設定ファイル: `programs.<tool>` モジュールがあれば使う、無ければ `home.file.*` で配置
- macOS GUI app: `modules/darwin/homebrew.nix` の `casks` に追記
