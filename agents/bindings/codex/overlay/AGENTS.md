## Codex での基本方針

- ユーザーが明示しない限り、日本語で回答する。
- 返答は簡潔かつ具体的にする。
- コード変更前に関連ファイルを読み、既存の設計・命名・運用パターンに合わせる。
- 検索には `rg` / `rg --files` を優先する。
- auth files、tokens、caches、logs、histories に含まれる秘密情報を露出・commit・要約しない。
- Codex / OpenAI product behavior の正確性が重要な場合は、公式 OpenAI ドキュメントで確認する。
- `~/.codex/auth.json`、sqlite state、logs、history、caches、`[projects.*]` trust state はローカルマシンに留める。
- `~/dev/github.com/skanehira/dotfiles` で作業する場合、このリポジトリの構成・セットアップ・Nix 運用・sudo の扱い・作業手順は `~/dev/github.com/skanehira/dotfiles/CLAUDE.md` を参照する。

## Codex に配られているもの

この文書自体が生成物である。共通の正本 (`dotfiles/agents/AGENTS.md`) に Codex 向けの overlay
(`dotfiles/agents/bindings/codex/overlay/AGENTS.md`) をマージしたものが `~/.codex/AGENTS.md` に置かれる。
**上に書かれている共通ルールはこのファイルに含まれているので、他のファイルを読みに行く必要はない。**

| 要素 | 配布先 | 正本 | 反映のタイミング |
| --- | --- | --- | --- |
| このグローバル指示 | `~/.codex/AGENTS.md` | `agents/AGENTS.md` + `agents/bindings/codex/overlay/AGENTS.md` | `drs` / `hms` が要る (生成物) |
| スキル | `~/.codex/skills/<name>` (Codex の skill root `r0`) | `agents/skills/` | `drs` / `hms` が要る (生成物) |
| subagent | `~/.codex/agents/*.toml` | `agents/subagents/*.md` を変換したもの | `drs` / `hms` が要る (生成物) |
| ルール | `~/.claude/rules/` を絶対パスで直接 Read する | `agents/rules/` | `drs` / `hms` が要る (生成物) |
| MCP | `/etc/codex/config.toml` の `[mcp_servers.*]` | `agents/bindings/codex/config.toml` | 即反映 (symlink)。全マシン共通のサーバだけを system レイヤーに置き、マシン固有のものは Codex 自身が `~/.codex/config.toml` (user レイヤー) に書く |

**hooks はこの表に無い。** Codex には 1 本も配られていない (→「hooks は Codex には配られていない」節)。

`~/.agents/skills/` は使わない。ここは他ツールが入れたスキルの領域で、Codex と OpenCode の
両方が探索するためランタイム別の生成物を置けない。

配布されているか自分で確かめる:

```bash
ls ~/.codex/skills                     # スキルが実ディレクトリで並ぶ
ls ~/.codex/agents                     # subagent の .toml がある
readlink -f /etc/codex/config.toml     # dotfiles の agents/bindings/codex/config.toml に解決する
```

生成物には `.harness-manifest.json` が同居し、`drs` / `hms` のたびに上書きされる。**手で編集しない。**
手で流し直すときは `agents/scripts/build-harness.ts` を直接叩く (使い方は引数なしで実行すると出る)。

## 3 者で表現できない subagent の属性

生成器 (`dotfiles/agents/scripts/build-harness.ts`) が TOML に出すのは `name` / `description` / `developer_instructions` の 3 キーだけである。正本の frontmatter にある以下は Codex 側に届かない。

- **`tools` (ツールの許可リスト)**: 表現手段が無い。制限が要るなら本文 (= `developer_instructions`) に禁止事項として書く
- **`model`**: 生成物に書かないので、subagent は**親のモデルを継承する**。固定したいときは `dotfiles/agents/bindings/codex/config.toml` に `[agents] default_subagent_model` を 1 箇所書く (現状は未設定)
- **`context: fork`**: 相当概念が無い

## Claude Code 由来の記述の読み替え

スキル・subagent・ルールの本文はまだ Claude Code 向けの語彙で書かれている。以下の記述が出てきたら Codex 上では次のように読み替える。

- **`AskUserQuestion` ツール**: `request_user_input` ツールでユーザーに確認する。ただし**非対話実行 (`codex exec`) では使えない**ので、その場合は上記「エスカレーション」の自律モード規定に従い、前提と選択の根拠を出力に明示して前進する
- **`Skill` ツールでの相互呼び出し**: 対応する Codex スキル (`$name`) を実行する。呼び出し先が `slide-plugin:*` / `document-skills:*` のような Claude 専用プラグインのスキルで Codex に存在しない場合は、その旨を伝えて代替手段を提案する
- **`Agent` ツールでの subagent 起動**: `spawn_agent` に `~/.codex/agents/*.toml` の名前を指定して起動する。スキルが渡す `model` / `subagent_type` は生成物に表現手段が無く落ちるので、**親のモデルを継承する**。定義が無い名前 (`Explore` / `general-purpose` 等の Claude 組み込み) を指している場合は、組み込みの `explorer` / `worker` で代替するか、同一セッション内で逐次実行して**その旨を作業報告に明記する**
- **`TodoWrite` / `TaskCreate` / `TaskUpdate` によるタスク管理**: `update_plan` ツールで置き換える。粒度と更新のタイミング (1 件ずつ着手 → 完了) は本文の指示に従う
- **`WebSearch`**: Codex の web search をそのまま使う (`/etc/codex/config.toml` で `web_search = "live"` を設定済み)
- **`WebFetch`**: 相当するツールが無い。`curl` で取得する
- **`run_in_background` での Bash 起動**: Codex のバックグラウンド実行で置き換える。同期実行を指示している箇所 (`run_in_background: false`) は素直に同期で回す
- **`plan mode`**: Codex の Plan mode で置き換える
- **`chrome-devtools` の MCP ツール** (`mcp__chrome-devtools__*` / `chrome-devtools:*` の記法): 同じ MCP サーバが `dotfiles/agents/bindings/codex/config.toml` で配られているので、ツール名の綴りだけ Codex の記法に読み替えて使う
- **`~/.claude/rules/...` / `~/.claude/scripts/...` への参照**: 同一マシン上のファイルなのでそのまま Read / 実行して参照する
- **`~/.claude/agents/...` への参照**: Codex 側の実体は `~/.codex/agents/*.toml` である
- **`allowed-tools` / `model` / `argument-hint` などの frontmatter**: `name` / `description` / `metadata.short-description` 以外は挙動に効かないものとして扱う。制約として書かれている内容は本文と同じ重みで自分で守る

ここに無い Claude 固有の記述に出会ったら、勝手に読み替えず**その旨を報告して指示を仰ぐ**。

## hooks は Codex には配られていない

**Codex 側の hooks は 0 本である。** ハーネスの自作 hook は `fix-round-guard` (dev-impl の修正ラウンド上限) 1 本だけで、これは Claude Code の Agent ツール入力に依存するため移植していない。dev-impl 系のスキルを Codex で回すときは、ラウンド上限を自律遵守する。

したがって Codex 上では、上記「評価関数」が採点者として挙げる 4 者のうち hooks が居ない。残るのはユーザー / レビュー subagent / プロジェクトの CI である。

## hooks を追加するときの置き場

必ず `dotfiles/agents/bindings/codex/config.toml` に書く。Codex の hooks は Claude Code と同じ wire format (`tool_name` / `tool_input.command` / `hookSpecificOutput.permissionDecision`) を採るのでスクリプトは共有できる。`~/.codex/hooks.json` (user レイヤー) に置いたものは `/hooks` で承認するまで**無言でスキップ**され、警告も出ない。system レイヤー (`/etc/codex/config.toml`) に置いたものは信頼ゲートを通らずに発火する。`command` はシェル経由で解釈されるので `$GHQ_ROOT` が展開でき、mac と Linux で dotfiles の絶対パスが違う問題を環境変数経由で回避できる。
