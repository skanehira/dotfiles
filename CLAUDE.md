# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

dotfiles リポジトリ。macOS は **Nix (nix-darwin + Home Manager)**、Linux は **Home Manager standalone (非 NixOS)** で宣言的管理。設定ファイルは `home.file` × `mkOutOfStoreSymlink` で dotfiles 直接 symlink としてバインドし、live edit を維持する。

## Installation

### 初回セットアップ (macOS 新マシン)

```bash
# clone 先は ~/dev/github.com/skanehira/dotfiles 固定
# (mkOutOfStoreSymlink が claude.nix / neovim.nix でこの path を直参照するため)
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

mkdir -p ~/dev/github.com/skanehira
cd ~/dev/github.com/skanehira
git clone https://github.com/skanehira/dotfiles.git

cd dotfiles/nix
nix --extra-experimental-features 'nix-command flakes' \
  run home-manager/master -- switch --flake ".#skanehira"
```

aarch64 マシンは `.#skanehira` を `.#skanehira-aarch64` に置換 (flake output が `homeConfigurations` に 2 つ用意してある)。Linux 専用 bootstrap script は用意していない (上記コマンドを手で叩く)。

### 設定変更を反映

```bash
# macOS
drs   # alias: noglob sudo darwin-rebuild switch --flake ~/dev/.../nix#skanehira

# Linux (Home Manager standalone)
hms   # alias: noglob home-manager switch --flake ~/dev/.../nix#skanehira
```

両 alias は `aliases.nix` で OS 別に `lib.optionalAttrs` 分岐済。手動でフルコマンドを叩くより楽。

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
  - `flake.nix` — inputs, outputs (`darwinConfigurations.skanehira` + `homeConfigurations.{skanehira,skanehira-aarch64}`)
  - `home.nix` — クロスプラットフォーム共通の Home Manager base
  - `home-darwin.nix` — mac 用エントリ (home.nix + karabiner + `homeDirectory = /Users/...`)
  - `home-linux.nix` — Linux 用エントリ (home.nix + `homeDirectory = /home/...`)
  - `darwin.nix` — nix-darwin imports のみ
  - `modules/home/` — Home Manager modules（CLI パッケージ、env、git、zsh、aliases、fzf、direnv、tmux、wezterm、karabiner 等）
  - `modules/darwin/` — nix-darwin modules（system、homebrew）
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
- **claude/** — Claude Code 設定（`mkOutOfStoreSymlink` で dotfiles 直接 symlink、live edit 可能）
  - `CLAUDE.md` / `settings.json` / `agents/` / `hooks/` / `rules/` / `skills/` — 編集即反映、`drs` 不要
- **vim/** — Neovim 設定（`mkOutOfStoreSymlink` で dotfiles 直接 symlink、live edit 可能）
  - `init.lua` / `lua/` / `after/` — 編集即反映、`drs` 不要
  - `.luarc.json` — lua_ls の dotfiles 内 lua 編集用設定 (track 対象)

## Nix モジュール構成（詳細）

```
nix/
├── flake.nix              ← inputs + darwinConfigurations + homeConfigurations
├── flake.lock
├── home.nix               ← 共通 base (cross-platform module の imports)
├── home-darwin.nix        ← home.nix + karabiner + homeDirectory=/Users/...
├── home-linux.nix         ← home.nix + homeDirectory=/home/...
├── darwin.nix             ← imports modules/darwin/
├── install.sh             ← mac bootstrap
└── modules/
    ├── overlays.nix       ← nix-darwin 用 module (overlays-list.nix を nixpkgs.overlays に流す)
    ├── overlays-list.nix  ← overlay の素のリスト (HM standalone の pkgs= からも参照)
    ├── home/
    │   ├── aliases.nix   — programs.zsh.shellAliases (drs/hms を OS 別 lib.optionalAttrs)
    │   ├── claude.nix    — Claude Code (bootstrap install + mkOutOfStoreSymlink で設定 live edit)
    │   ├── direnv.nix    — programs.direnv + nix-direnv
    │   ├── env.nix       — sessionVariables / sessionPath
    │   ├── fzf.nix       — programs.fzf (default command/options, zsh integration)
    │   ├── git.nix       — programs.git (LFS, alias, difftastic)
    │   ├── karabiner.nix — goku で karabiner.edn → karabiner.json (mac only。home-darwin.nix からのみ import)
    │   ├── neovim.nix    — vim/{init.lua,lua,after} を mkOutOfStoreSymlink で live edit
    │   ├── packages.nix  — home.packages 群（CLI 50+、terminal-notifier は darwin only）
    │   ├── rustup.nix    — bootstrap-install (~/.cargo/bin/rustup 不在時のみ公式 installer 実行)
    │   ├── tmux.nix      — programs.tmux (prefix C-s, vi, plugins、xsel/pbcopy 分岐済)
    │   ├── wezterm.nix   — programs.wezterm (extraConfig は wezterm.lua を readFile)
    │   └── zsh.nix       — programs.zsh (history, completion, prompt、homebrew/linuxbrew 分岐済)
    └── darwin/
        ├── homebrew.nix  — declarative brews / casks
        └── system.nix    — users, nix.settings, Touch ID, primaryUser
```

### 重要な設計判断

- **darwinConfigurations / homeConfigurations の key**: ホスト名ではなく `username = "skanehira"` を使用。複数マシンでも同じ設定が走る前提。
- **system 値**: darwin は `aarch64-darwin` 固定 (Apple Silicon)。Linux は `homeConfigurations.skanehira` (x86_64-linux) と `skanehira-aarch64` (aarch64-linux) の 2 出力。
- **モジュール共有**: `home.nix` が cross-platform base、`home-darwin.nix` / `home-linux.nix` が OS 別 wrapper。共通 module は `modules/home/` 配下、mac 専用は `karabiner.nix` のみで `home-darwin.nix` からだけ import。`tmux.nix` / `zsh.nix` は内部で `lib.optionalString isDarwin/isLinux` 分岐済。
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

## Neovim Configuration

### Structure
- `vim/lua/plugins/` — lazy.nvim プラグイン設定
- `vim/lua/settings/` — 基本設定（options.lua, keymaps.lua, lsp.lua, autocmd.lua）
- `vim/lua/modules/` — カスタムモジュール（AI, markdown）
- `vim/after/lsp/` — LSP 個別設定 (denols, ts_ls, rust_analyzer, lua_ls, yamlls)

### Key Paths
- ghq リポジトリ: `$HOME/dev`
- Go バイナリ: `$HOME/go/bin`
- Deno バイナリ: `$HOME/.deno/bin`

### Neovim 本体

`pkgs.neovim` を nixpkgs-unstable の **stable release** から取得 (`cache.nixos.org` 経由でビルド済)。アップデートは `nix flake update nixpkgs`。

## Claude Code Integration

### Development Workflow Skills

```
アイデア・企画 → 要件・設計 → 実装
```

詳細は `claude/skills/README.md` を参照。主要スキル：
- `/ideation` — ideation-problem-definition → ideation-competitor-analysis → ideation-slc-ideation
- `/requirements` — requirements-user-story → ... → requirements-analyzing-requirements
- `/implementation-developing` — TDD（RED→GREEN→REFACTOR）で実装

### Workflow Skills
- `/workflow-spec` — 設計書 (DESIGN.md) とタスクリスト (TODO.md) を対話的に生成
- `/workflow-impl` — TDD で実装
- `/workflow-review` — コードレビュー
- `/workflow-ask` — インタビュー→確認→実行
- `/requirements-interview` — DESIGN.md 深掘り
- `/workflow-commit-push` — Conventional Commit 形式で commit + push

### Hooks (settings.json)
- **Stop/Notification** — 完了時に macOS 通知（`terminal-notifier` 使用、Nix 管理）
- **PostToolUse** — Write/Edit 後に自動フォーマット

### Rules (claude/rules/)
- `core/tdd.md` — TDD 方法論
- `core/commit.md` — Conventional Commit 形式
- `backend/go/`, `backend/rust/` — 言語別コーディング規約

### Installation

```bash
cd claude && ./install.sh
```

`~/.config/claude/` に symlink を作成。

## Working with This Repository

### 既存設定の変更（Nix 管理側）

1. `nix/modules/home/*.nix` または `nix/modules/darwin/*.nix` を編集
2. `git add` で staging（flake は tracked file しか見ない）
3. `drs` で適用（`sudo darwin-rebuild switch` を Touch ID 経由で）

### 新規ツール追加

- CLI: `modules/home/packages.nix` に追記
- 設定ファイル: `programs.<tool>` モジュールがあれば使う、無ければ `home.file.*` で配置
- macOS GUI app: `modules/darwin/homebrew.nix` の `casks` に追記
