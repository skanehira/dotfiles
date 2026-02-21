# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

dotfilesリポジトリ。macOSとLinux向けの開発環境設定を管理。各ツールは独自のディレクトリに設定ファイルとインストールスクリプトを持つモジュール構造。

## Installation

```bash
# 各ツールのインストーラーを個別に実行
cd git && ./install.sh
cd ../vim && ./install.sh
cd ../tmux && ./install.sh
cd ../zsh && ./install.sh
cd ../wezterm && ./install.sh
cd ../karabiner && ./install.sh  # macOS only
cd ../claude && ./install.sh
```

## Directory Structure

- **git/** - GPG署名、エイリアス、difftastic統合
- **vim/** - Neovim設定（Lua、lazy.nvim）
- **zsh/** - Zsh設定（エイリアス、関数、キーバインド）
- **tmux/** - tmux設定（プラットフォーム別）
- **wezterm/** - WezTermターミナル設定
- **karabiner/** - macOSキーボードリマッピング
- **claude/** - Claude Code設定（スキル、ルール、フック）

## Neovim Configuration

### Structure
- `vim/lua/plugins/` - lazy.nvimプラグイン設定
- `vim/lua/settings/` - 基本設定（options.lua, keymaps.lua, lsp.lua, autocmd.lua）
- `vim/lua/modules/` - カスタムモジュール（AI、markdown）
- `vim/after/lsp/` - LSP個別設定（denols, ts_ls, rust_analyzer, lua_ls, yamlls）

### Key Paths
- ghqリポジトリ: `$HOME/dev`
- Goバイナリ: `$HOME/go/bin`
- Denoバイナリ: `$HOME/.deno/bin`

## Claude Code Integration

### Development Workflow Skills

```
アイデア・企画 → 要件・設計 → 実装
```

詳細は `claude/skills/README.md` を参照。主要スキル：
- `/ideation` - ideation-problem-definition → ideation-competitor-analysis → ideation-slc-ideation
- `/requirements` - requirements-user-story → ... → requirements-analyzing-requirements
- `/implementation-developing` - TDD（RED→GREEN→REFACTOR）で実装

### Workflow Skills
- `/workflow-spec` - 設計書（DESIGN.md）とタスクリスト（TODO.md）を対話的に生成
- `/workflow-impl` - TDD（RED→GREEN→REFACTOR）で実装
- `/workflow-review` - コードレビュー（TDD、品質、セキュリティ、アーキテクチャ、ルール準拠）
- `/workflow-ask` - インタビュー→確認→実行の3段階タスク実行
- `/requirements-interview` - DESIGN.mdの深掘りインタビュー
- `/workflow-commit-push` - Conventional Commit形式でコミット＆プッシュ

### Hooks (settings.json)
- **Stop/Notification** - 完了時にmacOS通知を送信
- **PostToolUse** - Write/Edit後に自動フォーマット実行

### Rules (claude/rules/)
- `core/tdd.md` - TDD方法論（RED→GREEN→REFACTOR、Tidy Firstアプローチ）
- `core/commit.md` - Conventional Commit形式（emoji + type）
- `backend/go/`, `backend/rust/` - 言語別コーディング規約

### Installation
```bash
cd claude && ./install.sh
```
`~/.config/claude/`にシンボリックリンクを作成。

## Working with This Repository

### 設定変更時
1. 各ツールの設定は独自ディレクトリに自己完結
2. `install.sh`を実行してシンボリックリンクを更新
3. プラットフォーム固有コードはDarwin/Linuxを判定

### 新規ツール追加時
1. 新ディレクトリを作成
2. 設定ファイルを追加
3. `install.sh`スクリプトを作成（適切な場所にシンボリックリンク）

### 重要事項
- Gitは GPG署名を使用
- Tmuxプレフィックスは`Ctrl+s`（デフォルトの`Ctrl+b`ではない）
- モダンCLIツールを想定（lsd, delta, batなど）