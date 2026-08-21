# ゴール達成監査の詳細手順 (dev-impl Step 5.2)

`dev-impl/SKILL.md` の Step 5.2 (第三者監査の並列起動) から参照される実行コマンドの詳細。判定基準・gate 分岐は SKILL.md 本体にあるので、そちらを先に読んでから該当節だけをここで参照する。

下記テンプレートの必須フィールドは `hooks/agent-spawn-guard.ts` の `REQUIRED_FIELDS` が PreToolUse で機械検証しており、欠けた prompt での起動は deny される。**テンプレートのフィールドを増減したら hook 側も合わせて更新する**こと。

## 5.2: 監査 agent の並列起動

`PRODUCT_MODE=cli` かどうかで起動 agent 数が変わる。

**cli の場合 (review-spec-compliance が G_E2E も担当、review-product-readiness は起動しない)**:

```javascript
Agent({
  description: "受入基準と成果物全体の第三者監査 (G_E2E 含む)",
  subagent_type: "review-spec-compliance",
  model: "opus",
  prompt: `mode: post-impl
product_mode: cli
docs_dir: ${absRepoDir}/docs
approved_stamp: "<TODO.md 1 行目をそのまま>"
run_start_sha: ${START_SHA}
repo_dir: ${absRepoDir}
decisions_jsonl: ${absRunDir}/decisions.jsonl
output_path: ${absRunDir}/review-spec-compliance.json
holdout_enabled: false
docs は自分で全文 Read すること。product_mode: cli のため G_E2E も自動系ゴールとして自分で実行し goal_results に含めること (他 agent は起動しない)。
作業結果 (output_path のパス) は必ず最終メッセージで親に返すこと。`
})
```

**webapp / unknown の場合 (従来どおり 2 体並列)**:

```javascript
// 1 体目: 受入監査 (自動系ゴールの独立再実行 + 設計突合 + 改変検知)
Agent({
  description: "受入基準と成果物全体の第三者監査",
  subagent_type: "review-spec-compliance",
  model: "opus",
  prompt: `mode: post-impl
product_mode: webapp
docs_dir: ${absRepoDir}/docs
approved_stamp: "<TODO.md 1 行目をそのまま>"
run_start_sha: ${START_SHA}
repo_dir: ${absRepoDir}
decisions_jsonl: ${absRunDir}/decisions.jsonl
output_path: ${absRunDir}/review-spec-compliance.json
holdout_enabled: false
docs は自分で全文 Read すること。G_E2E は実行しないこと (別 agent が担当)。
作業結果 (output_path のパス) は必ず最終メッセージで親に返すこと。`
})

// 2 体目: G_E2E 実機検証 (Web プロダクトのみ)
Agent({
  description: "G_E2E の実機検証",
  subagent_type: "review-product-readiness",
  model: "opus",
  prompt: `phase_name: G_E2E (run 全体の受入)
phase_start_sha: ${START_SHA}
repo_dir: ${absRepoDir}
design_overview: |
  <DESIGN.md の「ゴール」セクション。G_E2E のシナリオを含む>
design_detail: |
  <DESIGN_DETAIL_APP.md の「UX 設計」セクション (画面遷移マップ / ナビゲーション仕様 / 共通 UI 仕様 / アクセシビリティ)>
dev_server:
  url: ${devServerUrl}
  start_command: ${devServerStartCommand}
snapshot_dir: ${absRunDir}/review-product-readiness-snapshots/
output_path: ${absRunDir}/review-product-readiness-goal-e2e.json

最終メッセージは output_path の絶対パス 1 行だけにせよ。findings 本文や要約を書くな。`
})
```

**パスはすべて絶対で渡す** (`absRepoDir` = `git rev-parse --show-toplevel`、`absRunDir` = `$HOME` 展開済みの `~/.claude/logs/dev-impl/<run_id>`)。subagent の Bash は呼び出しごとに cwd が親のものへ戻り、`~` もシェルを介さない受け渡しでは展開されないため、相対パスやチルダのままでは意図した場所を指さない。`agent-spawn-guard` の必須フィールド検査はキーの存在しか見ないので、**値の形式はこのテンプレート側でしか担保できない**。

`holdout_enabled` は現時点でデフォルト無効。TODO.md に書かれていないエッジケースを review-spec-compliance が能動的に生成・検証する PoC 機能で (review-spec-compliance.md 参照)、効果測定後に有効化を検討する。

## Step 5.3: 監査結果の findings 別の対処

上から順に評価する。

| findings (rule)                                                              | 対処                                                                                                                                            |
| ---------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `verification_tampered` (high)                                               | **即エスカレ停止 (P3、修正ループなし)**。受入基準の改変は実行者に直させる対象ではなく、人間の再承認 (dev-spec フェーズ 11) 事案                 |
| `goal_result_mismatch` (high)                                                | 監査 agent の実行結果を正とし、当該ゴールを unmet として未達対応ループへ (自己申告ログとの食い違い自体も JSONL に残す)                          |
| unmet ゴール / `unimplemented_api` / `schema_drift` / `infra_missing` (high) | Step 5.5 の未達対応ループへ (finding の `fix_proposal` / `evidence` を新フェーズの内容に使う)                                                   |
| `vacuous_verification` (high)                                                | **自動修正させない** (検証コマンドを実行者が「直す」のは骨抜きの温床)。当該ゴールを手動 pending に落とし、Step 6 サマリで人間確認要求として明示 |
| `holdout_test_failed` (high)                                                 | 監査 agent が TODO.md に無いエッジケースを生成して落としたもの。**未達対応ループへ回す** (`holdout_enabled` を有効にした run でのみ出る。実装の穴なので直せる) |
| medium / low のみ                                                            | JSONL 記録 + POST_MVP.md へ転記 (Step 5.6)。status `partial` 判定に反映                                                                         |
| agent エラー / JSON 解釈不能                                                 | `review_agent_failed` でエスカレ停止 (未検証をパス扱いにしない)                                                                                 |

## Step 5.4: 結果分岐

上から順に評価する。

| # | 状況                                                    | 対処                   |
| - | ------------------------------------------------------- | ---------------------- |
| 1 | `verification_tampered` (**severity: high**) が 1 件以上 | 即エスカレ停止 (5.3 の表。修正ループなし)。low/medium の同 rule は改変ではなく書式の揺れ等なので、`spec_compliance` に記録して次の行の判定へ進む |
| 2 | unmet ゴール、または**修正可能な** high findings (`unimplemented_api` / `schema_drift` / `infra_missing` / `goal_result_mismatch` / `holdout_test_failed`) が 1 件以上 | Step 5.5 の未達対応ループへ |
| 3 | 残る high が**修正対象外のものだけ** (`vacuous_verification`) で、ゴールは achieved か手動 pending | **Step 6 へ**。当該ゴールを手動 pending に落とし、`status` は `partial`。完了サマリに人間確認要求として明示する |
| 4 | 全ゴール achieved (or 手動 pending のみ) かつ high 0 件 | Step 6 へ (完了サマリ、`status` は 5.6 の判定に従う) |

## Step 5.6: status 判定

Step 6 の完了サマリに載せる `status` を決める。

| 状況                                            | status                              |
| ----------------------------------------------- | ----------------------------------- |
| 全ゴール達成 + UI/UX gap 全項目空 + 未検証 0 件 | `done`                              |
| 全ゴール達成だが UI/UX gap または未検証項目あり | `partial` (未仕上げ / 未検証が残る) |
| 自動ゴール未達ありで未達対応ループ実行中        | (Step 5 内ループ継続)               |
| 未達ゴールで goal_loop > 2                      | `escalated` (Step 5 で P3 停止)     |
