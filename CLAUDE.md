# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

dotfiles リポジトリ。macOS は **Nix (nix-darwin + Home Manager)** で宣言的管理を主軸とする。一部のツール (vim) は移行途中で `install.sh` ベースの symlink 方式が残存。Linux は将来対応予定。

## Installation

### 初回セットアップ (新マシン)

```bash
# 1. Nix 公式インストーラを実行
sh <(curl -L https://nixos.org/nix/install) --daemon

# 2. nix-darwin + Home Manager bootstrap
cd nix && bash ./install.sh
```

`install.sh` は内部で `sudo nix run nix-darwin -- switch --flake .#skanehira` を実行し、experimental features と Touch ID 設定込みでシステム全体を構築する。

### 設定変更を反映

```bash
drs   # alias: sudo darwin-rebuild switch --flake ~/dev/.../nix#skanehira
```

`drs` alias は `home.nix` 経由で zsh に注入される。手動で `darwin-rebuild` を叩くより楽。

### 一部ツール（vim）

```bash
# それぞれのディレクトリの install.sh を実行（symlink 方式、現時点で残存）
cd vim && ./install.sh
```

これらは将来 Nix 化予定。現在は混在状態。

## Directory Structure

### Nix 管理（中核）

- **nix/** — flake-based config（最も重要）
  - `flake.nix` — inputs, outputs, system 設定
  - `home.nix` / `darwin.nix` — エントリポイント (imports のみ)
  - `modules/home/` — Home Manager modules（CLI パッケージ、env、git、zsh、aliases、fzf、direnv 等）
  - `modules/darwin/` — nix-darwin modules（system、homebrew、overlays）
  - `install.sh` — bootstrap 用（一度限り）

### ツール別ディレクトリ（symlink 方式、移行途中）

- **vim/** — Neovim 設定 (Lua, lazy.nvim)

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

### 廃止済

- ~~`git/`~~ — `programs.git` (Home Manager) に完全移行、削除済
- ~~`zsh/install.sh`、`zsh/zprofile`~~ — `programs.zsh` に移行、削除済

## Nix モジュール構成（詳細）

```
nix/
├── flake.nix          ← inputs + darwinConfigurations
├── flake.lock
├── home.nix           ← imports modules/home/
├── darwin.nix         ← imports modules/darwin/
├── install.sh         ← 初回 bootstrap
└── modules/
    ├── home/
    │   ├── claude.nix    — Claude Code (bootstrap install + mkOutOfStoreSymlink で設定 live edit)
    │   ├── env.nix       — sessionVariables / sessionPath
    │   ├── git.nix       — programs.git (LFS, alias, difftastic)
    │   ├── packages.nix  — home.packages 群（CLI 50+）
    │   ├── zsh.nix       — programs.zsh (history, completion, prompt)
    │   ├── fzf.nix       — programs.fzf (default command/options, zsh integration)
    │   ├── direnv.nix    — programs.direnv + nix-direnv
    │   ├── karabiner.nix — goku で karabiner.edn → karabiner.json 自動生成
    │   ├── tmux.nix      — programs.tmux (prefix C-s, vi, plugins: resurrect + themepack, extraConfig 直書き)
    │   ├── wezterm.nix   — programs.wezterm (extraConfig は wezterm.lua を readFile)
    │   └── aliases.nix   — programs.zsh.shellAliases
    └── darwin/
        ├── homebrew.nix  — declarative brews / casks
        ├── overlays.nix  — neovim-nightly, vite-plus
        └── system.nix    — users, nix.settings, Touch ID, primaryUser
```

### 重要な設計判断

- **darwinConfigurations の key**: ホスト名ではなく `username = "skanehira"` を使用。複数マシンでも同じ設定が走る前提。
- **system 値**: `aarch64-darwin` 固定。将来 Linux/Intel Mac 対応時に `forAllSystems` パターンへ。
- **Homebrew**: GUI app (cask) と Nix で動かない formula (gnupg, ppsspp) のみ残す。`onActivation.cleanup = "none"` で宣言外を破壊しない。
- **Touch ID for sudo**: `security.pam.services.sudo_local.touchIdAuth + reattach` で tmux 内含めて指紋認証。

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

`pkgs.neovim`（nightly）を **`neovim-nightly-overlay`** 経由で取得。`flake.nix` の `inputs.neovim-nightly-overlay` 参照。アップデートは `nix flake update neovim-nightly-overlay`。

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

### 既存設定の変更（symlink 方式側、vim/tmux 等）

1. 該当ディレクトリのファイルを編集
2. すでに symlink 済みなので即反映（再 `install.sh` は不要）

### 新規ツール追加

**Nix で扱える場合（推奨）**：
- CLI: `modules/home/packages.nix` に追記
- 設定ファイル: `programs.<tool>` モジュールがあれば使う、無ければ `home.file.*` で配置
- macOS GUI app: `modules/darwin/homebrew.nix` の `casks` に追記

**Nix で扱えない場合**：
- ディレクトリ作成 → `install.sh` で symlink 配置（旧来方式）

### 重要事項

- Git は GPG 署名を使用（gnupg は brew、設定は `programs.git` で）
- Tmux プレフィックスは `Ctrl+s`（デフォルトの `Ctrl+b` ではない）
- モダン CLI を前提（lsd, fzf, direnv, bat, difftastic 等、すべて Nix）
- zsh 起動時間は ~0.10s に最適化済（compinit ハイブリッド）。新たに重い init を入れるときは startup time に注意
