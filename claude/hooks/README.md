# Claude Code Hooks

Custom hooks for Claude Code.

## Files

- `commit-msg-guard.ts` — コミット規約ゲート (PreToolUse Bash)
- `fix-round-guard.ts` — 修正ラウンド上限ゲート (PreToolUse Agent)

## Usage

Hooks are configured in `../settings.json` and run automatically on the specified events.

### Commit Message Guard Hook

`git commit` の subject 行を rules/core/commit.md の `<emoji> <type>: <subject>` 形式で機械検証する (PreToolUse Bash)。

- 適用範囲: cwd が `$GHQ_ROOT/github.com/skanehira/` 配下の自リポジトリのみ (外部リポの別規約を誤 deny しない)
- 検証不能なケース (`--amend` / `-F` / メッセージ抽出不能) は allow
- 無効化: 環境変数 `COMMIT_GUARD=off`
- テスト: `deno test claude/hooks/commit-msg-guard_test.ts`

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

## 機械ゲートを置いていない規律

以下は hook で強制せず、`~/.claude/CLAUDE.md` と `../skills/README.md` の記述による自律遵守に委ねている。

- **実装系ルールの遅延参照**: 着手前に `../rules/core/` の必要なものを Read する。プロンプトを検知してリマインドする仕組みは持たない
- **subagent 起動時の `model` 明示**: Agent ツールの `model` は未指定だと agent 定義の frontmatter ではなく親のセッションモデルを継承する。呼び出し時に必ず明示する
