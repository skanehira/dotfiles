# Codex グローバル指示

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
