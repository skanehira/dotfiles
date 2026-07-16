# Claude Code Hooks

Custom hooks for Claude Code.

## Files

- `tdd-guard.ts` — TDD 強制ゲート (PreToolUse / PostToolUse / Stop / SubagentStop 兼用)
- `commit-msg-guard.ts` — コミット規約ゲート (PreToolUse Bash)
- `remind-rules.ts` — 実装系プロンプト検知時に CLAUDE.md ルールを再注入 (UserPromptSubmit)
- `archive-transcript.ts` — transcript のアーカイブ (SessionEnd / PreCompact)

## Usage

Hooks are configured in `../settings.json` and run automatically on the specified events.

### TDD Guard Hook

TDD (RED → GREEN → REFACTOR) を tool call レベルで機械的に強制する。LLM の追加ターンは発生しない。

- `PreToolUse` (Edit/Write/NotebookEdit) — 実装ファイルへの編集を状態機械で判定。「失敗テスト未確認」なら deny
- `PreToolUse` (Bash) — `> / >> / tee / sed -i / patch / git apply` によるゲート対象ソースへの書き込みを deny し、Edit/Write ツールへ誘導 (ゲート迂回の封鎖)
- `PostToolUse` (Bash) — テストコマンド実行を検知して RED / GREEN をセッション状態に記録
- `PostToolUse` (Task/Agent) — サブエージェント委譲時は state が委譲先自身の session_id に書かれ親に反映されないため、報告本文の `TDD_GUARD: green` / `TDD_GUARD: red` マーカー (1 行、両方あれば red 優先) を検知して親のセッション状態に反映
- `Stop` / `SubagentStop` — 編集後にテスト未実行のまま停止しようとしたら block。テスト実行でフラグが消えるまで最大 2 回 (上限到達で諦めて通す)

状態ファイル: `~/.claude/tdd-guard/<session_id>.json`
除外: md / json / yaml / nix / *.config.* 等の宣言的ファイル (`classifyFile` 参照)
無効化: 環境変数 `TDD_GUARD=off`
テスト: `deno test claude/hooks/tdd-guard_test.ts`

### Commit Message Guard Hook

`git commit` の subject 行を rules/core/commit.md の `<emoji> <type>: <subject>` 形式で機械検証する (PreToolUse Bash)。

- 適用範囲: cwd が `$GHQ_ROOT/github.com/skanehira/` 配下の自リポジトリのみ (外部リポの別規約を誤 deny しない)
- 検証不能なケース (`--amend` / `-F` / メッセージ抽出不能) は allow
- 無効化: 環境変数 `COMMIT_GUARD=off`
- テスト: `deno test claude/hooks/commit-msg-guard_test.ts`
