# Codex グローバル指示

## Claude グローバル指示の適用

- リポジトリやタスクの内容によらず、すべてのセッションで必ず @/Users/skanehira/.claude/CLAUDE.md を参照し、その内容 (全タスク共通のルール、自律モード時の優先順位、オーケストレーションとモデル階層等) に従う。

## 基本方針

- ユーザーが明示しない限り、日本語で回答する。
- 返答は簡潔かつ具体的にする。
- コード変更前に関連ファイルを読み、既存の設計・命名・運用パターンに合わせる。
- 検索には `rg` / `rg --files` を優先する。
- auth files、tokens、caches、logs、histories に含まれる秘密情報を露出・commit・要約しない。

## dotfilesリポジトリ

- `/Users/skanehira/dev/github.com/skanehira/dotfiles` で作業する場合、このリポジトリの構成、セットアップ、Nix運用、sudoの扱い、作業手順は @/Users/skanehira/dev/github.com/skanehira/dotfiles/CLAUDE.md を参照する。

## Codex / OpenAI

- Codex / OpenAI product behavior の正確性が重要な場合は、公式OpenAIドキュメントで確認する。
- `~/.codex/auth.json`、sqlite state、logs、history、caches、`[projects.*]` trust state はローカルマシンに留める。

## Claude Code 由来スキルの読み替え

`~/.codex/skills/` には `dotfiles/claude/skills/` から symlink された Claude Code 向けスキルが含まれる。スキル本文に以下の Claude 固有の記述が出てきた場合は、Codex 上では次のように読み替える。

- **`AskUserQuestion` ツール**: Q1 / Q2 のようにナンバリングし、選択肢を A / B / C で示した平文の質問に置き換えてユーザーに確認する
- **`Agent` ツールでの subagent 起動** (`review-tdd` / `architecture-guard` 等の名前が出てくる箇所): `dotfiles/claude/agents/<name>.md` を読み、その役割を同一セッション内で順に実行する。並列 fan-out や fresh context での独立監査は再現できないため、逐次実行になる旨を作業報告に明記する
- **`Skill` ツールでの相互呼び出し**: 対応する Codex スキル (`$name`) を実行する。呼び出し先が `slide-plugin:*` / `example-skills:*` のような Claude 専用プラグインのスキルで Codex に存在しない場合は、その旨を伝えて代替手段を提案する
- **hooks 前提の記述** (`tdd-guard` / `commit-msg-guard` 等による機械強制): Codex には同等の hook 機構がないため、`~/.claude/rules/core/tdd.md` / `commit.md` を読み、その内容を自分の判断で遵守する
- **`chrome-devtools` MCP**: `codex/config.base.toml` で設定済みの `chrome-devtools` MCP サーバをそのまま使う (Claude 側と同一パッケージ)
- **`~/.claude/rules/...` / `~/.claude/agents/...` への参照**: 同一マシン上のファイルなのでそのまま Read して参照する
