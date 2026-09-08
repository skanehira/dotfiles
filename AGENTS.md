# AGENTS.md

このリポジトリで作業する agent 向けの指示。**グローバル指示の正本は `agents/AGENTS.md`** で、これとは別物。

## 基本方針

- このリポジトリの構成、セットアップ、Nix運用、sudoの扱い、作業手順は @CLAUDE.md を参照する。
- 作業前に関連ファイルを読み、既存の設計・命名・運用パターンに合わせる。
- 検索には `rg` / `rg --files` を優先する。
- ユーザーの未関連変更は戻さない。特に `agents/` 配下の既存変更は、明示されない限りユーザー所有として扱う。

## ハーネス (agents/) を編集するとき

- グローバル指示・ルール・スキル・subagent は**ランタイムごとにコンパイルして配る**。編集しても `drs` / `hms` (または `agents/scripts/build-harness.ts` の手動実行) まで反映されない。
- 本文はランタイム中立の語彙で書く。ツール名やパスを直接書かず `{{@ask-user}}` のようなプレースホルダを使う。対応表は `agents/vocabulary.json`。
- **frontmatter にはプレースホルダを書かない。** `allowed-tools` に並ぶツール名は Claude Code のパーミッション宣言で、置き換えると壊れる。
- ランタイム固有の記述は `agents/bindings/<runtime>/overlay/` に**節単位**で置く。見出しが一致する節を差し替える仕組みなので、**overlay で見出しの文言を変えない**。最初の見出しより前に本文を書くと生成器が例外で止まる。
- **Claude 向けの overlay は置かない。** base をそのまま出すことで「語彙置換が可逆であること」を byte 比較で検証できる。

詳細は @CLAUDE.md の「AI エージェントのハーネス (agents/)」節を参照。

## Codex設定

- `agents/bindings/codex/config.toml` はgit管理するCodex共通設定。`/etc/codex/config.toml` (systemレイヤー) にsymlinkされて全クライアント (CLI / ChatGPT.app内Codex) に読まれる。
- `~/.codex/config.toml` (userレイヤー) はCodex自身が書く可変状態 (`[projects.*]` trust、`[notice]`、`/model` の選択、`notify`、`[mcp_servers.*]`) で、dotfilesでは管理しない。ここにあるキーはsystemレイヤーの同名キーより優先される。
- `auth.json`、sqlite state、logs、history、cacheはgit管理しない。
- `~/.codex/AGENTS.md` は生成物。正本は `agents/AGENTS.md` + `agents/bindings/codex/overlay/AGENTS.md` で、手で編集しない。
