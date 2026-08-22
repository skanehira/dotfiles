# dev-impl 進捗ログ仕様

書式・スキーマ・書き込みコマンドのリファレンス。dev-impl 実行開始時に Read する。


## 目次

- [1 行テキストログ (リアルタイム監視)](#1-行テキストログ-リアルタイム監視)
- [構造化 JSONL ログ (事後振り返り)](#構造化-jsonl-ログ-事後振り返り)
- [subagent 起動と issue 完了の event_type (Step 4)](#subagent-起動と-issue-完了の-event_type-step-4)
- [範例: typical な実行ログ](#範例-typical-な実行ログ)

## 1 行テキストログ (リアルタイム監視)

`~/.claude/logs/dev-impl.log` に追記:

```bash
LOG="$HOME/.claude/logs/dev-impl.log"
mkdir -p "$(dirname "$LOG")"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] <message>" >> "$LOG"
```

メッセージには「フェーズ名 + ステップ名 + 結果」を含める (例: `phase-3 / architecture-guard / violations=2 (loop 1/3)`)。

## 構造化 JSONL ログ (事後振り返り)

run_id の発行・引き継ぎは run-bootstrap.md の `## run スコープ変数と env.sh の生成` が正 (再入では引き継ぐ)。dev-impl 起動時に `run_id = $(date '+%Y%m%d-%H%M%S')` を発行し、`~/.claude/logs/dev-impl/${run_id}/decisions.jsonl` に追記する。終了時にこの JSONL から HTML レポート (SKILL.md の Step 7) を生成する。

各エントリのスキーマ:

```json
{
  "timestamp": "2026-06-30T10:00:00+09:00",
  "phase": "phase-3",
  "step": "architecture-guard",
  "event_type": "start|run_done|done|p1_fix|p2_fix|p3_escalate|poc_pending|goal_check|phase_added|review_low|verification_skipped|spec_compliance|design_decision|open_question|spec_lookup|self_review|gating_decided|spawn|fix_dispatch|run_facts_updated|impl_report|impl_done|working_tree_polluted",
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

`event_type: review_low` の場合 (Step 4.2d 参照)、`severity` は常に `info` (fatal ではない軽微な指摘のため)。`context` には**各検査 agent の結果 JSON (`output_path`) の findings** を severity: low/medium に絞った上で dimension ごとにまとめる。キーは各 agent が返す `dimension` の値 (`tdd` / `quality` / `product_readiness` / `adversarial`) をそのまま使う。architecture-guard は `dimension` を返さないので `architecture` を割り当てる。**転記は `jq` で結果 JSON から直接行い、main のコンテキストを経由させない** (Step 4.2d の射影は `{severity, rule, file, line}` までで、`message` は main が読まないため):

```json
"context": {
  "findings_by_dimension": {
    "tdd": [{ "file": "...", "line": 12, "severity": "low", "message": "..." }],
    "quality": [],
    "product_readiness": [],
    "adversarial": [],
    "architecture": []
  }
}
```

`event_type: spec_compliance` の場合 (Step 5.3 参照)、`context` には review-spec-compliance の結果を入れる:

```json
"context": {
  "mode": "post-impl",
  "goal_loop": 0,
  "goal_results": [{ "id": "G1", "status": "achieved", "exit_code": 0,
                     "description": "...", "verification": "<実行した検証コマンド>",
                     "actual_output": "<失敗時の出力。成功時は null>", "evidence": "..." }],
  "findings": [{ "rule": "unimplemented_api", "severity": "high", "file": "...", "message": "..." }]
}
```

`event_type: goal_check` の判定主体は review-spec-compliance (自動系) / review-product-readiness (G_E2E) であり、メインループは集約して記録するだけ (Step 5.2〜5.3)。

**`goal_loop` はこのイベントにしか載らない。** Step 0 の再入復元は「当該 run の `goal_check` のうち `context.goal_loop` の最大値」を現在値として採る。**書き忘れると再入のたびに 0 に戻り、上限 2 周が実質無効になる** (`goal_loop` を進めるのは Step 5.5 だが、記録の器は判定側の `goal_check` に置く — 5.5 に入らず 5.4 で終わる周回でも周回数を残すため)。

**`goal_results` の `description` / `verification` / `actual_output` は HTML レポート (report-template.md のセクション 6) が描画するフィールドである。** 綴りを変えると検証コマンドと失敗ログの欄が黙って空になるので、両者を同時に直す。

`event_type: verification_skipped` で review-adversarial をスキップした場合 (Step 4.2c のスキップ述語参照)、`context` には判定に使った値をそのまま入れる:

```json
"context": {
  "target": "review-adversarial",
  "source": "adversarial_skip",
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
| `p2_fix` | warn | P2 動的修正で詳細設計を書き換えた時 (SKILL.md 4.6) | `section` (更新したセクション名) / `what` (何をどう変えたか 1 行) / `why` (実装から判明した事実) / `commit_sha` (設計変更のコミット) / `p2_fixes_total` (この時点の通算)。**P2 は回数で停止しない**ので、このエントリが「承認済みの設計が実装に合わせてどう書き換わったか」をユーザーが後から追える唯一の記録になる。Step 6 の完了サマリと HTML レポートのセクション 4 がこれを読む |
| `p1_fix` | info | P1 動的修正で TODO.md を書き換えた時 (SKILL.md 4.6) | `section` / `what` / `commit_sha` / `p1_fixes_in_phase` |
| `gating_decided` | info | フェーズの初回検査 fan-out の直前 (SKILL.md 4.2c。**フェーズごとに 1 件だけ**) | `phase` / `gating_set` (このフェーズで起動しうる **review-\* の観点名**の配列。`architecture-guard` は gating 対象外で常に実行するので含めない。再 fan-out はこの部分集合しか起動できない) / `adversarial_mode` (`full` / `weakening_only` / `skipped`) / `basis` (判定根拠の真偽値: `{test_changed: $TEST_FILE_CHANGED か $TEST_CONTENT_CHANGED が非空, consumable: $CONSUMABLE_CHANGED が非空, auth: $AUTH_CHANGED が非空, ui_phase: uiPhase, final_phase: 自分以外に open issue が無い}`)。**`verification_skipped` の `criteria_result` と共通するキー (`test_changed` / `final_phase`) は同名で揃える**が、両者はキー集合そのものは異なる (`basis` は gating の判定根拠、`criteria_result` は skip 述語の判定結果) |
| `spawn` | info | **Agent ツールで起動する直前** (**例外なく全て**。起動後に書く規定だと、待ちに入る直前の・前進を生まないログ 1 行だけが構造的に落ちる。実測で再 fan-out の記録が phase-5 は 7 回中 0 件だった。SKILL.md 4.2c の事前ブロックで他の必須処理とまとめて書く) | `phase` (フェーズ外の起動 — Step 1.5 の tech-investigation と Step 5.2 の監査 agent — は `"run"` を入れる。null にしない: 4.2e 手順 4 の突合が phase で絞るため) / `agent` (`dev-impl-implementer` / `architecture-guard` / `review-*` / `fix-lsp-warnings` / `tech-investigation`。後ろ 2 つは結果 JSON を出さないので 4.2e 手順 4 の突合対象外) / `model` (`opus` / `fable` / `sonnet` / `haiku`。`fable` は修正ラウンド 2 以降の implementer = SKILL.md「修正ラウンドのモデル昇格」) / `mode` (implementer は `implement` / `fix`、review-adversarial は `full` / `weakening_only`) / `round` (fan-out / 修正ラウンドの番号。初回 fan-out は 0) / `phase_spawns` (このフェーズの累計、**起動前に書くので「これから起動する 1 件を含めた値」**) / `run_spawns` (run 全体の累計、同上) |
| `fix_dispatch` | warn | 修正ラウンド (SKILL.md 4.2d) で `mode: fix` の implementer を起動した時 | `phase` / `phase_fix_round` (このラウンドの番号、1〜3) / `findings_paths` (渡した結果 JSON のパス配列) / `fatal_summary` (`{severity, rule, file, line}` の射影配列。**findings の本文は入れない**) |
| `self_review` | info | implementer 報告の一括転記時 (Step 4.2e 手順 6) | `checklist_applied` / `tests_revised` / `notes`。実装者が `rules/core/testing.md` のセルフレビューチェックリストを自分のテストへ適用した結果。HTML レポートには出さず、事後の振り返りで人が読むために残す |
| `spec_lookup` | info | 同上 | `path` (PHASE_CONTEXT の抜粋で足りず implementer が自分で Read した設計書のパスと節)。抜粋精度を事後に確認するために残す |
| `verification_skipped` | warn | 検証を実行しなかった / できなかった時 (記録箇所は下表) | **`source` を必ず入れる** (context の形が発生源ごとに違うため、Step 5.6 の集約はこれで分岐する)。値と形は下表 |
| `run_facts_updated` | info | RUN_FACTS.md への追記後 (SKILL.md 4.2e のコミット後) | `phase` / `sections` (更新した節名の配列: `commands` / `artifacts` / `design_decisions` / `pitfalls`) / `bytes` (更新後のファイルサイズ。4KB 上限の監視用) |
| `working_tree_polluted` | warn | 検査 fan-out の後に作業ツリーが非クリーンだった時 (SKILL.md 4.2d 手順 8) | `phase` / `round` / `files` (`git status --porcelain` の出力) / `restored` (`git restore` で戻せたか) / `rerun` (検査をやり直したか。汚染を検出したラウンドは fatal の有無に関わらずやり直す) / `occurrence` (このフェーズで何回目か。2 回目はエスカレ停止) |
| `phase_added` | warn | run の途中でフェーズと issue が増えた時 (SKILL.md 4.6「新フェーズの issue 化」手順 4) | `phase` / `issue_number` / `parent_number` (紐付けた親。フラット構成なら省略) / `origin` (`p1` / `p2` / `goal_unmet`) / `run_spawns_budget` (同手順 3 で再計算した値) |
| `p3_escalate` | error | エスカレ停止時 (SKILL.md「エスカレ停止時の挙動」) | `reason` (停止条件リストの値) / `phase` / `issue` (対象が無ければ `null`) / `label` (`in-progress` / `needs-human` / `none`) / `last_success_sha` / 停止理由ごとの詳細。**Step 0 手順 4 の再開分岐が読む唯一の駐車マーカー**なので、`reason` と `issue` は必ず入れる |
| `run_done` | info | **run の完了時 (Step 6 の完了サマリ出力時) に 1 件だけ**。Step 0 の再入判定はこのイベントの有無だけを見る | `status` (`done` / `partial`) / `phases_completed` / `goal_summary`。**`done` (ステップ単位の完了) と混同しない** — 再入判定のセンチネルは `run_done` であって `done` ではない |


`verification_skipped` の `source` は記録箇所と 1 対 1 に対応させる:

| `source` | 記録する箇所 | context の形 |
| --- | --- | --- |
| `adversarial_skip` | 4.2c: スキップ述語を満たして review-adversarial を起動しなかった | `{target, source, changed_files, changed_lines, criteria_result}` |
| `mode_degraded` | 4.2c: `mode: weakening_only` で起動しレンズ A/C が未実行 | `{target, source, lenses, mode}` |
| `implementer` | 4.2e 手順 6: implementer 報告の `verification_skipped` を転記 | 報告の要素に `source` を足したもの |
| `test_gate_timeout` | 4.2e: `full_test_command` が Bash の 600 秒上限で打ち切られた | `{target, source, command, elapsed_sec}` |
| `dev_server_missing` | 4.2c / Step 5.2: dev_server を推定できず review-product-readiness / G_E2E を skip | `{target, source}` |
| `lsp_fix_failed` | 4.2b: fix-lsp-warnings が失敗し警告を残したまま継続 | `{target, source, remaining}` |
| `manual_pending` | Step 5: 手動確認が必要なゴールを自動判定できずに残した | `{target, source, goal_id}` |
| `dod_no_automated` | 4.2e: issue の `## DoD` から取り出せた自動コマンドが 0 件だった (手動系だけか、抽出の空振りかを区別できない) | `{target, source, issue, dod_cmds}` |
| `dev_server_unavailable` | 4.2c / Step 5.2: review-product-readiness が dev サーバを起動できず実機検査が成立しなかった | `{target, source, phase}` |
| `no_layer_convention` | 4.2c: architecture-guard がレイヤ構造を見つけられず Clean Arch 検査を skip した (意図的な素通りだが、境界を検査していない run であることを残す) | `{target, source, phase}` |
| `exemptions_unadjudicated` | 4.2c: 自己免除が 1 件以上あるのに review-tdd / review-adversarial のどちらも起動せず、誰も裁定しなかった | `{target, source, phase, claims}` |

同一 `phase` に `gating_decided` が複数ある場合 (中断・再入や 4.2d 手順 5 の例外による追記) は**最新の 1 件を採る**。

`spawn` を全件記録するのは、`phase_spawns` / `run_spawns` の上限判定を「記憶」ではなくログから復元できる状態に保つため (compaction をまたいでもカウンタが失われない)。**記録は起動の前に書く** — 後に書く規定では落ちることが実測で繰り返し確認されている。フェーズを閉じる直前 (4.2e 手順 4) に成果物の本数と突合して不足を補記する二段構えにする。`gating_decided` も同じ理由で必ず記録する — 再 fan-out で起動してよい観点の集合はこのエントリが唯一のソースであり、記録が無ければ「記憶」で判断することになって仕様外の観点が起動する (実測で review-quality が規定外に 3 フェーズで起動していた)。

`event_type: start` (run 開始時の 1 件。再入した run では再入のたびに 1 件) の `context` には **`repo_root` (`git rev-parse --show-toplevel` の絶対パス)** と `start_sha` を必ず入れる。`~/.claude/logs/dev-impl/` は全プロジェクト共通のディレクトリなので、これが無いと SKILL.md Step 0 の「同一プロジェクトで未完了の run があるか」を機械判定できない。

**あわせて `run_spawns_budget` (SKILL.md Step 1 で確定した `run_spawns` の上限) を入れる。** フェーズ単位の `start` (再入時の書き直しを含む) には **`phase_spawns_budget`** (既定 33) と **`phase_fix_budget`** (既定 3) も入れる。いずれも再入時は引き上げ後の値を書き、復元は記録値の最大を採る。 この値と `phase_added` の同名フィールドだけが予算の記録先で、再入時の復元は両者に記録された値の**最大**を採る (予算は上方向にしか動かないため一意に決まる)。記録が無いと、compaction や再入をまたいだ時点で上限を「記憶」で判断することになる。

**`event_type: start` はフェーズ開始時にも 1 件書く** (`phase` に短縮識別子、`step: "start"`)。この場合の `context` には **`phase_start_sha` (SKILL.md 4.1 で取った `git rev-parse HEAD`) と `issue` (issue 番号) を必ず入れる**。`phase_start_sha` は、中断したフェーズの提示 (`git log <SHA>..HEAD`)・破棄 (`git reset --hard <SHA>`)・検査 agent への基準点の受け渡し のすべての起点で、**再入時にこれを復元できないと Step 0 の「続きとして取り込む / 捨てる」分岐が成立しない**。run 単位の `start` とはどちらも `phase` の値で区別する (run 単位は `"run"`)。

**`run_spawns` / `phase_spawns` の復元は `spawn` イベントの件数を数える方式に統一する** (`context.run_spawns` の最大値を採る方式と併用しない)。件数方式なら、フィールドを書き損ねた行があっても実態に近い値が出るうえ、4.2e 手順 4 の突合と同じ数え方になる。`context` のフィールドはリアルタイム監視と事後分析のために残すが、復元の正はあくまで件数である。

書き込みは `jq -nc --arg ... '{...}' >> $JSONL` で 1 行 1 エントリの append-only。`context` は event_type に応じて中身が変わる (`done` ではほぼ空でも良い)。

**implementer 報告由来の転記 (`design_decision` / `open_question` / `verification_skipped` / `spec_lookup` / `self_review`) だけは 1 回の実行で全件をまとめて append する** (コマンドは [phase-execution.md](./phase-execution.md) の `## 4.2e: implementer 報告の JSONL 一括転記`)。実測でこのうち design_decision と open_question だけで JSONL の過半を占めており、1 件ずつ書くと main の往復がフェーズあたり 30 回近く増える。`spawn` / `fix_dispatch` / エスカレ系はリアルタイム監視の価値があるので発生時に 1 件ずつ書く。

両ログとも各ステップの「開始 / 完了 / 動的修正 / エスカレ」発生時に同期して書き込む。1 行ログ = summary のみ、JSONL = summary + context を構造化。

## 範例: typical な実行ログ

```
[2026-06-30 10:00:00] dev-impl start (repo=/Users/x/dev/foo, docs/DESIGN.md + DESIGN_DETAIL_APP.md + DESIGN_DETAIL_INFRA.md + TODO.md)
[2026-06-30 10:00:01] phase-1 / start (RUN_FACTS.md 新規作成、gate コマンド検証 green)
[2026-06-30 10:00:05] phase-1 / spawn dev-impl-implementer (opus, mode=implement) [1/33]
[2026-06-30 10:03:10] phase-1 / impl_report (status=done, files=2, tests 12 passed)
[2026-06-30 10:03:12] phase-1 / fix-lsp-warnings / skipped (not a neovim plugin)
[2026-06-30 10:03:15] phase-1 / spawn architecture-guard (haiku) + review-tdd (opus) [3/33]
[2026-06-30 10:05:40] phase-1 / 検査 / guard violations=0, review (dims: tdd) fatal=0
[2026-06-30 10:05:55] phase-1 / test-gate / green
[2026-06-30 10:06:00] phase-1 / commit + run_facts_updated + impl_done
[2026-06-30 10:06:01] phase-2 / start
[2026-06-30 10:06:05] phase-2 / spawn dev-impl-implementer (opus, mode=implement) [1/33]
[2026-06-30 10:09:12] phase-2 / impl_report (status=done, files=3, tests 18 passed)
[2026-06-30 10:09:14] phase-2 / design_decision / retry デフォルト 3 回を採用 (設計に記述なし)
[2026-06-30 10:09:20] phase-2 / spawn architecture-guard (haiku) + review-tdd (opus) [3/33]
[2026-06-30 10:11:25] phase-2 / 検査 / guard violations=2 (fatal)
[2026-06-30 10:11:30] phase-2 / fix_dispatch (round 1/3) → spawn dev-impl-implementer (opus, mode=fix) [4/33]
[2026-06-30 10:13:40] phase-2 / impl_report (status=done, mode=fix)
[2026-06-30 10:13:45] phase-2 / spawn architecture-guard (haiku) + review-tdd (opus) [6/33]
[2026-06-30 10:15:50] phase-2 / 検査 / guard violations=0, review fatal=0
[2026-06-30 10:16:03] phase-2 / test-gate / green
[2026-06-30 10:16:05] phase-2 / commit + run_facts_updated + impl_done
...
[2026-06-30 10:45:00] all phases done (5/5). P1=1, P2=0, run_spawns=22
```

