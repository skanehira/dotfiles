# Claude Code Hooks

deny する自作ゲートは `fix-round-guard.ts` の 1 本だけで、起動元は Claude Code の `../bindings/claude/settings.json` の `hooks` のみ。Agent ツールの入力に依存するため Codex へは移植しておらず、`../bindings/codex/config.toml` に hooks は無い。OpenCode はシェル hooks を持たないので対象外。

ディレクトリにはこのほか `herdr-agent-state.sh` (SessionStart で herdr にセッション状態を渡す) がある。herdr 本体が配布するファイルで、自作ゲートではないので本書の対象外。

## fix-round-guard.ts

dev-impl の修正ラウンド上限を機械検証する (PreToolUse Agent)。`skills/dev-impl/SKILL.md` 2.3 は「修正は最大 2 ラウンド (固定)」と規定しているが、オーケストレーター自身が「r3・規定超過」と書きながら 3 周目を起動した実測がある (セッション e6b5eb50: 22 issue 中 6 件が r3 以上に入り、規定超過分だけで 5.7h を消費)。指示文の規定は破られるので起動そのものを止める。

検証する内容:

| 対象 | 判定 |
| --- | --- |
| `dev-impl-implementer` を `mode: fix` で起動し、`findings_path` が `review-<issue>-r<ラウンド>.json` を指す | ラウンドが 3 以上なら deny し、規定の分岐 (high 残存 → 駐車 / medium のみ → `PENDING_REVIEW.html`) を提示する |

- **状態を持たない**。ラウンド数は `findings_path` から読む (実測で `mode: fix` の起動 29/29 がこの形式のパスを渡している)。スキルの再実行は新しい SCRATCH で r1 から採番し直すため、それがそのままカウンタのリセットになる
- `mode: implement` / 他の agent / ラウンドを読み取れない起動 (検収差し戻しなど) は allow
- deny されるのは**同一 run 内で 2 ラウンドを超えて継続する場合だけ**。スキルを再実行して再開する経路は Step 0 が新しい SCRATCH を作り r1 から採番し直すため deny されない。同一 run 内で意図的に続けたいときは `FIX_ROUND_GUARD=off` で解除する (deny メッセージにも案内がある)
- 無効化: 環境変数 `FIX_ROUND_GUARD=off`
- テスト: `deno test --allow-env --allow-run --allow-read agents/hooks/fix-round-guard_test.ts`

## 機械ゲートを置いていない規律

以下は hook で強制せず、`~/.claude/CLAUDE.md` / `../rules/core/` / `../skills/README.md` の記述による自律遵守に委ねている。

- **コミット規約**: `../rules/core/commit.md` の `<emoji> <type>: <subject>` 形式。3 ランタイムとも自律遵守する
- **実装系ルールの遅延参照**: 着手前に `../rules/core/` の必要なものを Read する。プロンプトを検知してリマインドする仕組みは持たない
- **subagent 起動時の `model` 明示**: Agent ツールの `model` は未指定だと agent 定義の frontmatter ではなく親のセッションモデルを継承する。呼び出し時に必ず明示する
