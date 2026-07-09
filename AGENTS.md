# AGENTS.md

## 基本方針

- このリポジトリの構成、セットアップ、Nix運用、sudoの扱い、作業手順は @CLAUDE.md を参照する。
- 作業前に関連ファイルを読み、既存の設計・命名・運用パターンに合わせる。
- 検索には `rg` / `rg --files` を優先する。
- ユーザーの未関連変更は戻さない。特に `claude/` 配下の既存変更は、明示されない限りユーザー所有として扱う。

## Codex設定

- `codex/config.base.toml` はgit管理するCodex設定のベース。
- `~/.codex/config.toml` はHome Manager activationで生成され、既存のローカル `[projects.*]` trust state を保持する。
- project trust、`auth.json`、sqlite state、logs、history、cacheはgit管理しない。
- `codex/AGENTS.md` は `~/.codex/AGENTS.md` にsymlinkされるグローバルCodex指示。
