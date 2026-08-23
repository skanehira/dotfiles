# Claude Code Hooks

Custom hooks for Claude Code.

## Files

- `commit-msg-guard.ts` — コミット規約ゲート (PreToolUse Bash)
- `agent-spawn-guard.ts` — subagent 起動ゲート (PreToolUse Agent)
- `remind-rules.ts` — 実装系プロンプト検知時に CLAUDE.md ルールを再注入 (UserPromptSubmit)
- `archive-transcript.ts` — transcript のアーカイブ (SessionEnd / PreCompact)

## Usage

Hooks are configured in `../settings.json` and run automatically on the specified events.

### Commit Message Guard Hook

`git commit` の subject 行を rules/core/commit.md の `<emoji> <type>: <subject>` 形式で機械検証する (PreToolUse Bash)。

- 適用範囲: cwd が `$GHQ_ROOT/github.com/skanehira/` 配下の自リポジトリのみ (外部リポの別規約を誤 deny しない)
- 検証不能なケース (`--amend` / `-F` / メッセージ抽出不能) は allow
- 無効化: 環境変数 `COMMIT_GUARD=off`
- テスト: `deno test claude/hooks/commit-msg-guard_test.ts`

### Agent Spawn Guard Hook

subagent の起動を機械検証する (PreToolUse Agent)。Agent ツールの `model` は未指定だと agent 定義ではなく親のセッションモデルを継承するため、「指示文には model を書いたのに起動時に指定し忘れて意図しない単価で走る」事故を、指示ではなくコードで塞ぐ (旧構成のログ実測で「書かれているのに守られていない」ことを確認済み)。

検証する内容:

| 対象 | 判定 |
| --- | --- |
| `MANDATED_MODEL` の agent (dev-impl-implementer / review-impl / fix-lsp-warnings) | `model` が未指定なら deny し、規定値を提示する |

- 適用範囲: 全リポジトリ (対象 agent は `~/.claude/agents` の個人定義なので他人のリポジトリで誤検知しない)
- `model` は**未指定のときだけ** deny する。規定と違う値でも明示されていれば意図的な override として通す
- `MANDATED_MODEL` に無い agent (general-purpose / Explore 等) は検証対象外
- 無効化: 環境変数 `AGENT_SPAWN_GUARD=off`
- テスト: `deno test --allow-env claude/hooks/agent-spawn-guard_test.ts`
