# Claude Code Hooks

Custom hooks for Claude Code.

## Files

- `notify.ts` — Sends desktop notifications for Claude Code events
- `tdd-guard.ts` — TDD 強制ゲート (PreToolUse / PostToolUse / Stop / SubagentStop 兼用)
- `remind-rules.ts` — 実装系プロンプト検知時に CLAUDE.md ルールを再注入 (UserPromptSubmit)
- `archive-transcript.ts` — transcript のアーカイブ (SessionEnd / PreCompact)

## Usage

Hooks are configured in `../settings.json` and run automatically on the specified events.

### Notify Hook

Sends a desktop notification on:
- `Stop` event — Claude Code finishes a response
- `Notification` event — Claude Code needs user attention (e.g., permission prompt)

macOS only (uses `terminal-notifier`).

### TDD Guard Hook

TDD (RED → GREEN → REFACTOR) を tool call レベルで機械的に強制する。LLM の追加ターンは発生しない。

- `PreToolUse` (Edit/Write/NotebookEdit) — 実装ファイルへの編集を状態機械で判定。「失敗テスト未確認」なら deny
- `PreToolUse` (Bash) — `> / >> / tee / sed -i / patch / git apply` によるゲート対象ソースへの書き込みを deny し、Edit/Write ツールへ誘導 (ゲート迂回の封鎖)
- `PostToolUse` (Bash) — テストコマンド実行を検知して RED / GREEN をセッション状態に記録
- `Stop` / `SubagentStop` — 編集後にテスト未実行のまま停止しようとしたら block。テスト実行でフラグが消えるまで最大 2 回 (上限到達で諦めて通す)

状態ファイル: `~/.claude/tdd-guard/<session_id>.json`
除外: md / json / yaml / nix / *.config.* 等の宣言的ファイル (`classifyFile` 参照)
無効化: 環境変数 `TDD_GUARD=off`
テスト: `deno test claude/hooks/tdd-guard_test.ts`
