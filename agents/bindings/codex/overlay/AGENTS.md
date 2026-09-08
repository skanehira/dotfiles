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
| ルール | `~/.agents/rules/codex/` を絶対パスで直接 Read する | `agents/rules/` | `drs` / `hms` が要る (生成物) |
| MCP | `/etc/codex/config.toml` の `[mcp_servers.*]` | `agents/bindings/codex/config.toml` | 即反映 (symlink)。全マシン共通のサーバだけを system レイヤーに置き、マシン固有のものは Codex 自身が `~/.codex/config.toml` (user レイヤー) に書く |

**hooks はこの表に無い。** このハーネスが自分で書いた hook は 1 本も配っていない (→「hooks は Codex には配られていない」節)。

`~/.agents/skills/` は使わない。ここは他ツールが入れたスキルの領域で、Codex と OpenCode の
両方が探索するためランタイム別の生成物を置けない。

配布されているか自分で確かめる:

```bash
ls ~/.codex/skills/.harness-manifest.json  # 生成でしか作られない (ls だけだと他ツールのスキルと区別できない)
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

## 読み替えが要らなくなったもの / まだ要るもの

ハーネスは配布時に語彙を Codex のものへ展開している。本文に出てくる
`request_user_input` / `update_plan` / `spawn_agent` / `explorer` / `worker` や
`~/.agents/rules/codex/...` は**すでに Codex の語彙**なので、読み替えずそのまま使う。

置換で吸収できないものだけが残る。

- **呼び出し例の引数の形は Claude Code のもの**。ツール名は展開済みだが、
  `request_user_input({ questions: [...] })` のような例に出てくる引数の構造は
  Claude Code のスキーマのまま。**自分のツールのスキーマに合わせて読み替える**
- **`request_user_input` は非対話実行 (`codex exec`) では使えない**。その場合は上記
  「エスカレーション」の自律モード規定に従い、前提と選択の根拠を出力に明示して前進する
- **`spawn_agent` に渡す `model` / `subagent_type`** は subagent の生成物に表現手段が
  無く落ちるので、**親のモデルを継承する**。定義が無い名前を指している場合は組み込みの
  `explorer` / `worker` で代替するか、同一セッション内で逐次実行して報告に明記する
- **スキルの相互呼び出し**で `slide-plugin:*` / `document-skills:*` のような Claude 専用
  プラグインのスキルが指定されている場合は、その旨を伝えて代替手段を提案する
- **`chrome-devtools` の MCP ツール**: サーバ名は 3 者共通だがツール名の記法が違う
  (`mcp__chrome-devtools__*` / `chrome-devtools:*` は Claude の記法)。綴りだけ Codex の
  記法に読み替える。サーバ自体は `agents/bindings/codex/config.toml` で配られている
- **`{{@scripts-root}}`** は 3 者で共有している。Claude Code 用のパスに見えても同一
  マシン上のファイルなのでそのまま実行する
- **`allowed-tools` / `model` / `argument-hint` などの frontmatter**: `name` /
  `description` / `metadata.short-description` 以外は挙動に効かないものとして扱う。
  制約として書かれている内容は本文と同じ重みで自分で守る
- **`/model` コマンドと `Fable` / `Mythos` の tier 名**: Claude Code 固有。セッションモデルの切り替え手段と世代名は自分のランタイムのものに読み替える
- **`ScheduleWakeup`**: Codex に相当機能が無い。バックグラウンドタスクの追跡は自分から
  状態を取りに行く運用で代替する

ここに無い Claude 固有の記述に出会ったら、勝手に読み替えず**その旨を報告して指示を仰ぐ**。

## hooks は Codex には配られていない

**このハーネスが自分で書いた hook は 0 本である。** そもそも機械ゲートを 1 本も持っていない (Claude Code 向けにも無い) ので、移植すべきものが無い。**ただし Codex 環境に hook が 1 件も無いという意味ではない。** `~/.codex/hooks.json` (user レイヤー) に herdr 連携の SessionStart hook が 1 件、`nix/modules/home/codex.nix` の activation が入れる compact-plus プラグイン由来が 7 件登録されている (承認状態は `~/.codex/config.toml` の `[hooks.state]` に残る)。いずれもこのハーネスが書いたゲートではない。dev-impl 系のスキルを Codex で回すときは、修正ラウンド上限を自律遵守する。

## hooks を追加するときの置き場

必ず `dotfiles/agents/bindings/codex/config.toml` に書く。Codex の hooks は Claude Code と同じ wire format (`tool_name` / `tool_input.command` / `hookSpecificOutput.permissionDecision`) を採るのでスクリプトは共有できる。`~/.codex/hooks.json` (user レイヤー) に置いたものは `/hooks` で承認するまで**無言でスキップ**され、警告も出ない。system レイヤー (`/etc/codex/config.toml`) に置いたものは信頼ゲートを通らずに発火する。`command` はシェル経由で解釈されるので `$GHQ_ROOT` が展開でき、mac と Linux で dotfiles の絶対パスが違う問題を環境変数経由で回避できる。
