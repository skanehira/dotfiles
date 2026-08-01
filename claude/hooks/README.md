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

subagent の起動を機械検証する (PreToolUse Agent)。dev-impl 実行 7 セッションのログ実測で「指示文としては書かれているのに守られていない」ことが確認された 2 点を、指示ではなくコードで塞ぐ。

検証する内容:

| 対象 | 判定 | 実測された欠陥 |
| --- | --- | --- |
| `MANDATED_MODEL` の agent (architecture-guard / review-*) | `model` が未指定なら deny し、規定値を提示する | architecture-guard の 22 spawn が model 未指定で親の opus を継承 ($2.40/spawn。haiku 指定時は $0.16/spawn) |
| `review-spec-compliance` | `mode: post-impl` / `mode: pre-approval` を判別し、mode 別の必須フィールドが揃っていなければ deny | 15 spawn すべてで `product_mode` / `approved_stamp` / `run_start_sha` / `decisions_jsonl` / `holdout_enabled` が欠落 (完全な spawn は 0/15、コンテキスト規模とは無相関 r=-0.01) |

- 適用範囲: 全リポジトリ (対象 agent は `~/.claude/agents` の個人定義なので他人のリポジトリで誤検知しない)
- `model` は**未指定のときだけ** deny する。規定と違う値でも明示されていれば意図的な override として通す
- `MANDATED_MODEL` に無い agent (general-purpose / Explore 等) は検証対象外
- 無効化: 環境変数 `AGENT_SPAWN_GUARD=off`
- 必須フィールドは**キーの存在だけでなく値が空でないこと**まで確認する。また本 hook 自身の deny 文 (不足フィールド名を列挙する) を prompt に貼り戻す迂回を防ぐため、`[agent-spawn-guard]` で始まる行は検証前に除去する
- テスト: `deno test --allow-env --allow-run --allow-read claude/hooks/agent-spawn-guard_test.ts` (hook 本体を subprocess で起動する I/O 層のテストを含むため `--allow-run` が要る)

必須フィールドの正本は `skills/dev-impl/references/goal-audit.md` の `## 5.2: 監査 agent の並列起動`。テンプレートを変更したら `REQUIRED_FIELDS` も合わせて更新する。
