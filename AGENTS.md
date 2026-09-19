# AGENTS.md

このリポジトリで作業する agent 向けの指示。**グローバル指示の正本は `agents/AGENTS.md`** で、これとは別物。

## 基本方針

- このリポジトリの構成、セットアップ、Nix運用、sudoの扱い、作業手順は @CLAUDE.md を参照する。
- 作業前に関連ファイルを読み、既存の設計・命名・運用パターンに合わせる。
- 検索には `rg` / `rg --files` を優先する。
- ユーザーの未関連変更は戻さない。特に `agents/` 配下の既存変更は、明示されない限りユーザー所有として扱う。

## ハーネス (agents/) を編集するとき

- 配布は symlink が基本。グローバル指示 (`~/.claude/CLAUDE.md`) / ルール (`~/.claude/rules`) / スキル (`~/.claude/skills`) / subagent (`~/.claude/agents`) は正本 `agents/` への symlink なので、**本文の編集は即反映**される。
- 例外は 2 つ。どちらも `drs` / `hms` が要る。
  - **スキルの追加・削除**: Codex 向けに `~/.agents/skills/<name>` へ個別 symlink を張り直すため (`nix/modules/home/codex.nix` の activation `linkAgentSkills`)
  - **subagent の変更・追加**: Codex は TOML しか読めないので `agents/scripts/sync-subagents.ts` が `~/.codex/agents/*.toml` へ書式変換する (activation `syncCodexSubagents`)
- 本文の語彙は **Claude 綴りで確定済み**。ツール名やパスをそのまま書く (プレースホルダは使わない)。Codex は同じ実体を読み、`agents/bindings/codex/AGENTS.md` の読み替え表に従って解釈する。
- **frontmatter にはツール名を書き換えない。** `allowed-tools` に並ぶツール名は Claude Code のパーミッション宣言で、置き換えると壊れる。
- 配布先の限定は `SKILL.md` の frontmatter では宣言しない。Codex へ配らないスキルは `nix/modules/home/codex.nix` の `claude_only_skills` に列挙する。
- Claude 固有で Codex に存在しない記述 (ツール名・コマンド・機能) を本文に足したら、`agents/bindings/codex/AGENTS.md` の「Claude 綴りの読み替え」表にも 1 行足す。

詳細は @CLAUDE.md の「AI エージェントのハーネス (agents/)」節を参照。

## Codex設定

- `agents/bindings/codex/config.toml` はgit管理するCodex共通設定。`/etc/codex/config.toml` (systemレイヤー) にsymlinkされて全クライアント (CLI / ChatGPT.app内Codex) に読まれる。
- `~/.codex/config.toml` (userレイヤー) はCodex自身が書く可変状態 (`[projects.*]` trust、`[notice]`、`/model` の選択、`notify`、`[mcp_servers.*]`) で、dotfilesでは管理しない。ここにあるキーはsystemレイヤーの同名キーより優先される。
- `auth.json`、sqlite state、logs、history、cacheはgit管理しない。
- `~/.codex/AGENTS.md` は `agents/bindings/codex/AGENTS.md` への symlink (live edit)。Codex 側の規約 (共通の正本の参照と Claude 綴りの読み替え) を書くのはこのファイル。
