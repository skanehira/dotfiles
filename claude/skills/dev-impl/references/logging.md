# dev-impl 進捗ログ仕様

書式・スキーマ・書き込みコマンドのリファレンス。dev-impl 実行開始時に Read する。


## 1 行テキストログ (リアルタイム監視)

`~/.claude/logs/dev-impl.log` に追記:

```bash
LOG="$HOME/.claude/logs/dev-impl.log"
mkdir -p "$(dirname "$LOG")"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] <message>" >> "$LOG"
```

メッセージには「フェーズ名 + ステップ名 + 結果」を含める (例: `phase-3 / architecture-guard / violations=2 (loop 1/3)`)。

## 構造化 JSONL ログ (事後振り返り)

dev-impl 起動時に `run_id = $(date '+%Y%m%d-%H%M%S')` を発行し、`~/.claude/logs/dev-impl/${run_id}/decisions.jsonl` に追記する。終了時にこの JSONL から HTML レポート (SKILL.md の Step 7) を生成する。

各エントリのスキーマ:

```json
{
  "timestamp": "2026-06-30T10:00:00+09:00",
  "phase": "phase-3",
  "step": "architecture-guard",
  "event_type": "start|done|p1_fix|p2_fix|p3_escalate|poc_pending|goal_check|goal_unmet|phase_added|review_low|verification_skipped|spec_compliance|design_decision|open_question|spawn|fix_dispatch|run_facts_updated|impl_dispatch|impl_report|impl_done",
  "severity": "info|warn|error",
  "summary": "1 行サマリ (テキストログにも残る内容)",
  "context": {
    "violations": [...],
    "diff_before": "...",
    "diff_after": "...",
    "rationale": "なぜこの修正を選んだか",
    "affected_files": ["src/foo.ts"],
    "related_design_section": "DESIGN_DETAIL_APP.md#api-設計"
  }
}
```

`event_type: review_low` の場合 (Step 4.2d 参照)、`severity` は常に `info` (fatal ではない軽微な指摘のため)。`context` には**各検査 agent の結果 JSON (`output_path`) の findings** を severity: low/medium に絞った上で dimension ごとにまとめ、加えて結果 JSON のパス一覧 (`result_paths`) を入れる。**転記は `jq` で結果 JSON から直接行い、main のコンテキストを経由させない** (Step 4.2d の射影は `{severity, rule, file, line}` までで、`message` は main が読まないため):

```json
"context": {
  "findings_by_dimension": {
    "tdd": [{ "file": "...", "line": 12, "severity": "low", "message": "..." }],
    "quality": [],
    "architecture": [],
    "adversarial": []
  }
}
```

`event_type: spec_compliance` の場合 (Step 5.3 参照)、`context` には review-spec-compliance の結果を入れる:

```json
"context": {
  "mode": "post-impl",
  "goal_results": [{ "id": "G1", "status": "achieved", "exit_code": 0, "evidence": "..." }],
  "findings": [{ "rule": "unimplemented_api", "severity": "high", "file": "...", "message": "..." }]
}
```

`event_type: goal_check` の判定主体は review-spec-compliance (自動系) / review-product-readiness (G_E2E) であり、メインループは集約して記録するだけ (Step 5.2〜5.3)。

`event_type: verification_skipped` で review-adversarial をスキップした場合 (Step 4.2c のスキップ述語参照)、`context` には判定に使った値をそのまま入れる:

```json
"context": {
  "target": "review-adversarial",
  "changed_files": ["docs/TODO.md"],
  "changed_lines": 6,
  "criteria_result": { "test_changed": false, "lines_le_20": true, "ci_config_changed": false, "final_phase": false }
}
```

`event_type: design_decision` の場合 (Step 4.2a 参照)、`severity` は常に `info`。設計文書 (DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md / TODO.md) が沈黙またはあいまいな実装の細部 (デフォルト値・パス/命名形式・ログ/エラーフォーマット・機能の適用範囲・ライブラリ API の選択等) を自分で選んだときに記録する (設計と矛盾する変更である deviation_signals とは区別する。判定基準は SKILL.md Step 4.2a を参照):

```json
"context": {
  "decision": "採用した選択の 1 行記述",
  "spec_gap": "silent|ambiguous",
  "alternatives": [{ "option": "棄却した代替案", "rejected_because": "棄却理由" }],
  "rationale": "なぜこの選択にしたか",
  "affected_files": ["src/foo.ts"],
  "related_design_section": "DESIGN_DETAIL_APP.md#api-設計"
}
```

`alternatives` は代替案を検討した場合のみ配列を入れ、検討していなければ `[]`。`related_design_section` は最も近い節が無ければ `null`。

`event_type: open_question` の場合 (Step 4.2a 以降のどのステップからでも記録可)、`severity` は常に `warn`。エスカレ条件には該当しないが選択に確信が持てず、ユーザの事後確認が必要なときに記録する (CLAUDE.md「エスカレーション」の自律モードに従い、暫定処理を明記してループは止めずに前進する):

```json
"context": {
  "question": "エンジニアに確認・判断してほしいことの 1 行記述",
  "background": "なぜ自己解決できなかったか / どう暫定処理したか",
  "suggested_action": "確認後にユーザがすべきこと (例: 値の見直し・仕様の追記)",
  "affected_files": ["src/foo.ts"]
}
```

同一の判断・質問を後続フェーズで踏襲するだけの場合は再記録しない (初回のみ)。

## subagent 起動と issue 完了の event_type (Step 4)

1 フェーズは最小構成でも implementer 1 + architecture-guard 1 + review 1〜4 の subagent を起動する。全 spawn を記録して事後にフェーズ単価と突合できるようにする (上限は SKILL.md Step 3 の `phase_spawns` / `run_spawns`)。

| event_type | severity | 記録タイミング | context |
| --- | --- | --- | --- |
| `impl_report` | info | implementer から報告を受領した時 | 報告要約 JSON + `report_path`。**全文を転記する場合は `jq` で `report_path` から直接 JSONL へ流し込み、main のコンテキストには載せない** |
| `impl_done` | info | **1 issue の完了時** (SKILL.md 4.2e のコミット後。**issue 完了はこのイベントだけ**で表す。`done` はステップ単位の完了に使い、issue 完了には使わない) | `phase` / `summary` / `commit_sha` / `review_outputs` (main が確認した検査結果 JSON のパス配列、監査証跡) / `phase_fix_round` (このフェーズで回した修正ラウンド数、0〜3) / `phase_spawns` |
| `gating_decided` | info | フェーズの初回検査 fan-out の直前 (SKILL.md 4.2c。**フェーズごとに 1 件だけ**) | `phase` / `gating_set` (このフェーズで起動しうる観点名の配列。再 fan-out はこの部分集合しか起動できない) / `adversarial_mode` (`full` / `weakening_only` / `skipped`) / `basis` (`{uiPhase, test_diff, consumable, is_last_issue}` の真偽値。判定根拠) |
| `spawn` | info | Agent ツールで subagent を起動した直後 (**例外なく全て**) | `phase` / `agent` (`dev-impl-implementer` / `architecture-guard` / `review-*` / `fix-lsp-warnings`) / `model` (`opus` / `sonnet` / `haiku`) / `mode` (implementer は `implement` / `fix`、review-adversarial は `full` / `weakening_only`) / `phase_spawns` (このフェーズの累計、起動後の値) / `run_spawns` (run 全体の累計) |
| `fix_dispatch` | warn | 修正ラウンド (SKILL.md 4.2d) で `mode: fix` の implementer を起動した時 | `phase` / `phase_fix_round` (このラウンドの番号、1〜3) / `findings_paths` (渡した結果 JSON のパス配列) / `fatal_summary` (`{severity, rule, file, line}` の射影配列。**findings の本文は入れない**) |
| `run_facts_updated` | info | RUN_FACTS.md への追記後 (SKILL.md 4.2e のコミット後) | `phase` / `sections` (更新した節名の配列: `commands` / `artifacts` / `design_decisions` / `pitfalls`) / `bytes` (更新後のファイルサイズ。4KB 上限の監視用) |

`spawn` を全件記録するのは、`phase_spawns` の上限判定を「記憶」ではなくログから復元できる状態に保つため (compaction をまたいでもカウンタが失われない)。`gating_decided` も同じ理由で必ず記録する — 再 fan-out で起動してよい観点の集合はこのエントリが唯一のソースであり、記録が無ければ「記憶」で判断することになって仕様外の観点が起動する (実測で review-quality が規定外に 3 フェーズで起動していた)。

`event_type: start` (run 開始時の 1 件) の `context` には **`repo_root` (`git rev-parse --show-toplevel` の絶対パス)** と `start_sha` を必ず入れる。`~/.claude/logs/dev-impl/` は全プロジェクト共通のディレクトリなので、これが無いと SKILL.md Step 0 の「同一プロジェクトで未完了の run があるか」を機械判定できない。

書き込みは `jq -nc --arg ... '{...}' >> $JSONL` で 1 行 1 エントリの append-only。`context` は event_type に応じて中身が変わる (`done` ではほぼ空でも良い)。

両ログとも各ステップの「開始 / 完了 / 動的修正 / エスカレ」発生時に同期して書き込む。1 行ログ = summary のみ、JSONL = summary + context を構造化。

## 範例: typical な実行ログ

```
[2026-06-30 10:00:00] dev-impl start (repo=/Users/x/dev/foo, docs/DESIGN.md + DESIGN_DETAIL_APP.md + DESIGN_DETAIL_INFRA.md + TODO.md)
[2026-06-30 10:00:01] phase-1 / start (RUN_FACTS.md 新規作成、gate コマンド検証 green)
[2026-06-30 10:00:05] phase-1 / spawn dev-impl-implementer (opus, mode=implement) [1/24]
[2026-06-30 10:03:10] phase-1 / impl_report (status=done, files=2, tests 12 passed)
[2026-06-30 10:03:12] phase-1 / fix-lsp-warnings / skipped (not a neovim plugin)
[2026-06-30 10:03:15] phase-1 / spawn architecture-guard (haiku) + review-tdd (opus) [3/24]
[2026-06-30 10:05:40] phase-1 / 検査 / guard violations=0, review (dims: tdd) fatal=0
[2026-06-30 10:05:55] phase-1 / test-gate / green
[2026-06-30 10:06:00] phase-1 / commit + run_facts_updated + impl_done
[2026-06-30 10:06:01] phase-2 / start
[2026-06-30 10:06:05] phase-2 / spawn dev-impl-implementer (opus, mode=implement) [1/24]
[2026-06-30 10:09:12] phase-2 / impl_report (status=done, files=3, tests 18 passed)
[2026-06-30 10:09:14] phase-2 / design_decision / retry デフォルト 3 回を採用 (設計に記述なし)
[2026-06-30 10:09:20] phase-2 / spawn architecture-guard (haiku) + review-tdd (opus) [3/24]
[2026-06-30 10:11:25] phase-2 / 検査 / guard violations=2 (fatal)
[2026-06-30 10:11:30] phase-2 / fix_dispatch (round 1/3) → spawn dev-impl-implementer (opus, mode=fix) [4/24]
[2026-06-30 10:13:40] phase-2 / impl_report (status=done, mode=fix)
[2026-06-30 10:13:45] phase-2 / spawn architecture-guard (haiku) + review-tdd (opus) [6/24]
[2026-06-30 10:15:50] phase-2 / 検査 / guard violations=0, review fatal=0
[2026-06-30 10:16:03] phase-2 / test-gate / green
[2026-06-30 10:16:05] phase-2 / commit + run_facts_updated + impl_done
...
[2026-06-30 10:45:00] all phases done (5/5). P1=1, P2=0, run_spawns=22
```

