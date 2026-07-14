# dev-impl 進捗ログ仕様

書式・スキーマ・書き込みコマンドのリファレンス。dev-impl 実行開始時に Read する。


### 1 行テキストログ (リアルタイム監視)

`~/.claude/logs/dev-impl.log` に追記:

```bash
LOG="$HOME/.claude/logs/dev-impl.log"
mkdir -p "$(dirname "$LOG")"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] <message>" >> "$LOG"
```

メッセージには「フェーズ名 + ステップ名 + 結果」を含める (例: `phase-3 / architecture-guard / violations=2 (loop 1/3)`)。

### 構造化 JSONL ログ (事後振り返り)

dev-impl 起動時に `run_id = $(date '+%Y%m%d-%H%M%S')` を発行し、`~/.claude/logs/dev-impl/${run_id}/decisions.jsonl` に追記する。終了時にこの JSONL から HTML レポート (後述 Step 7) を生成する。

各エントリのスキーマ:

```json
{
  "timestamp": "2026-06-30T10:00:00+09:00",
  "phase": "phase-3",
  "step": "architecture-guard",
  "event_type": "start|done|p1_fix|p2_fix|p3_escalate|poc_pending|goal_check|goal_unmet|phase_added|review_low|verification_skipped|spec_compliance|design_decision|open_question",
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

`event_type: review_low` の場合 (Step 4.2 参照)、`severity` は常に `info` (fatal ではない軽微な指摘のため)。`context` には `phaseFindings` を severity: low/medium に絞った上で dimension ごとにまとめて入れる:

```json
"context": {
  "findings_by_dimension": {
    "tdd": [{ "file": "...", "line": 12, "severity": "low", "message": "..." }],
    "quality": [],
    "architecture": [],
    "rules": [{ "file": "...", "line": 5, "severity": "medium", "message": "..." }],
    "product_readiness": [],
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

`event_type: verification_skipped` で review-adversarial をスキップした場合 (Step 4.2d のスキップ述語参照)、`context` には判定に使った値をそのまま入れる:

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

`event_type: open_question` の場合 (Step 4.2a 以降のどのステップからでも記録可)、`severity` は常に `warn`。エスカレ条件には該当しないが選択に確信が持てず、ユーザの事後確認が必要なときに記録する (CLAUDE.md「自律モード時の優先順位」に従い、暫定処理を明記してループは止めずに前進する):

```json
"context": {
  "question": "エンジニアに確認・判断してほしいことの 1 行記述",
  "background": "なぜ自己解決できなかったか / どう暫定処理したか",
  "suggested_action": "確認後にユーザがすべきこと (例: 値の見直し・仕様の追記)",
  "affected_files": ["src/foo.ts"]
}
```

同一の判断・質問を後続フェーズで踏襲するだけの場合は再記録しない (初回のみ)。

書き込みは `jq -nc --arg ... '{...}' >> $JSONL` で 1 行 1 エントリの append-only。`context` は event_type に応じて中身が変わる (`start` / `done` ではほぼ空でも良い)。

両ログとも各ステップの「開始 / 完了 / 動的修正 / エスカレ」発生時に同期して書き込む。1 行ログ = summary のみ、JSONL = summary + context を構造化。

## 範例: typical な実行ログ

```
[2026-06-30 10:00:00] dev-impl start (docs/DESIGN.md + DESIGN_DETAIL_APP.md + DESIGN_DETAIL_INFRA.md + TODO.md)
[2026-06-30 10:00:01] phase-1 / start
[2026-06-30 10:01:23] phase-1 / implement (main) / done
[2026-06-30 10:01:30] phase-1 / architecture-guard / violations=0
[2026-06-30 10:01:31] phase-1 / fix-lsp-warnings / skipped (not a neovim plugin)
[2026-06-30 10:02:45] phase-1 / review (dims: tdd) / pass
[2026-06-30 10:02:48] phase-1 / test-gate / green
[2026-06-30 10:02:50] phase-1 / commit / done
[2026-06-30 10:02:51] phase-2 / start
[2026-06-30 10:05:12] phase-2 / implement (main) / done
[2026-06-30 10:05:20] phase-2 / design_decision / retry デフォルト 3 回を採用 (設計に記述なし)
[2026-06-30 10:05:25] phase-2 / architecture-guard / violations=2 (loop 1/3)
[2026-06-30 10:06:40] phase-2 / fix (main) / done
[2026-06-30 10:06:50] phase-2 / architecture-guard / violations=0
[2026-06-30 10:08:00] phase-2 / review (dims: tdd) / pass
[2026-06-30 10:08:03] phase-2 / test-gate / green
[2026-06-30 10:08:05] phase-2 / commit / done
...
[2026-06-30 10:30:00] all phases done (5/5). P1=1, P2=0
```
