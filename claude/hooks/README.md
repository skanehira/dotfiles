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

TDD (RED → GREEN → REFACTOR) を tool call レベルで機械的に強制する。hook 自体は非 LLM の状態機械で完結し、テスト要否判定・テスト品質レビューは専任 subagent (`tdd-judge` / `review-tdd`) に委譲する。hook はその subagent の入出力を機械検証するだけで、subagent の主張を無条件には信用しない。

- `PreToolUse` (Edit/Write/NotebookEdit) — 実装ファイルへの編集を状態機械で判定。「失敗テスト未確認」なら deny (下記 tdd-judge による免除リストと厳密一致すれば allow)
- `PreToolUse` (Bash) — `> / >> / tee / sed -i / patch / git apply` によるゲート対象ソースへの書き込みを deny し、Edit/Write ツールへ誘導 (ゲート迂回の封鎖)
- `PostToolUse` (Bash) — テストコマンド実行を検知して RED / GREEN をセッション状態に記録
- `PostToolUse` (Task/Agent、`subagent_type: "tdd-judge"`) — deny された編集がテスト不要 (振る舞いを変えない) と判定された場合、指示文の sentinel ブロック (判定対象) と subagent の verdict JSON を index で対応付け、`trivial` の編集内容だけを `pendingExemptions` に保存する。次の pre-edit で実編集内容と厳密一致した場合のみ消し込んで allow する (判定基準は sentinel の中身だけで、周辺の自由文の主張は信用しない)
- `PostToolUse` (Task/Agent、`subagent_type: "review-tdd"`) — セッション内でテストファイルの新規追加、または前回レビュー以降の差分が 20 行を超えたらレビューゲートが arm される。stdout (= review-tdd.md の契約で findings JSON への絶対パス) をそのまま Read し、`ok: true` (high/medium findings ゼロ) のときだけゲートを解除する (マーカー自己申告方式ではない)
- `PostToolUse` (Task/Agent、それ以外) — サブエージェント委譲時は state が委譲先自身の session_id に書かれ親に反映されないため、報告本文の `TDD_GUARD: green` / `TDD_GUARD: red` マーカー (1 行、両方あれば red 優先) を検知して親のセッション状態に反映
- `Stop` / `SubagentStop` — 編集後にテスト未実行のまま停止しようとしたら block。レビューゲートが arm されたまま停止しようとした場合も block。いずれもフラグが消えるまで最大 2 回 (上限到達で諦めて通す)

状態ファイル: `~/.claude/tdd-guard/<session_id>.json`
除外: md / json / yaml / nix / *.config.* 等の宣言的ファイル (`classifyFile` 参照)
無効化: 環境変数 `TDD_GUARD=off` (全ゲート)、`TDD_GUARD_JUDGE=off` (tdd-judge による免除機構のみ)
テスト: `deno test claude/hooks/tdd-guard_test.ts`

### Commit Message Guard Hook

`git commit` の subject 行を rules/core/commit.md の `<emoji> <type>: <subject>` 形式で機械検証する (PreToolUse Bash)。

- 適用範囲: cwd が `$GHQ_ROOT/github.com/skanehira/` 配下の自リポジトリのみ (外部リポの別規約を誤 deny しない)
- 検証不能なケース (`--amend` / `-F` / メッセージ抽出不能) は allow
- 無効化: 環境変数 `COMMIT_GUARD=off`
- テスト: `deno test claude/hooks/commit-msg-guard_test.ts`
