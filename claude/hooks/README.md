# Claude Code Hooks

Custom hooks for Claude Code.

## Files

- `commit-msg-guard.ts` — コミット規約ゲート (PreToolUse Bash)
- `agent-spawn-guard.ts` — subagent 起動ゲート (PreToolUse Agent)
- `fix-round-guard.ts` — 修正ラウンド上限ゲート (PreToolUse Agent)
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
- テスト: `deno test --allow-env --allow-run --allow-read claude/hooks/agent-spawn-guard_test.ts` (hook 本体を subprocess で起動する I/O 層のテストを含むため `--allow-run` が要る)

### Fix Round Guard Hook

dev-impl の修正ラウンド上限を機械検証する (PreToolUse Agent)。`skills/dev-impl/SKILL.md` 2.3 は「修正は最大 2 ラウンド (固定)」と規定しているが、オーケストレーター自身が「r3・規定超過」と書きながら 3 周目を起動した実測がある (セッション e6b5eb50: 22 issue 中 6 件が r3 以上に入り、規定超過分だけで 5.7h を消費)。指示文の規定は破られるので起動そのものを止める。

検証する内容:

| 対象 | 判定 |
| --- | --- |
| `dev-impl-implementer` を `mode: fix` で起動し、`findings_path` が `review-<issue>-r<ラウンド>.json` を指す | ラウンドが 3 以上なら deny し、規定の分岐 (high 残存 → 駐車 / medium のみ → `PENDING_REVIEW.html`) を提示する |

- **状態を持たない**。ラウンド数は `findings_path` から読む (実測で `mode: fix` の起動 29/29 がこの形式のパスを渡している)。スキルの再実行は新しい SCRATCH で r1 から採番し直すため、それがそのままカウンタのリセットになる
- `mode: implement` / 他の agent / ラウンドを読み取れない起動 (検収差し戻しなど) は allow
- deny されるのは**同一 run 内で 2 ラウンドを超えて継続する場合だけ**。スキルを再実行して再開する経路は Step 0 が新しい SCRATCH を作り r1 から採番し直すため deny されない。同一 run 内で意図的に続けたいときは `FIX_ROUND_GUARD=off` で解除する (deny メッセージにも案内がある)
- 無効化: 環境変数 `FIX_ROUND_GUARD=off`
- テスト: `deno test --allow-env --allow-run --allow-read claude/hooks/fix-round-guard_test.ts`
