# ゴール達成監査の詳細手順 (dev-impl Step 5.2)

`dev-impl/SKILL.md` の Step 5.2 (第三者監査の並列起動) から参照される実行コマンドの詳細。判定基準・gate 分岐は SKILL.md 本体にあるので、そちらを先に読んでから該当節だけをここで参照する。

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
docs_dir: docs/
approved_stamp: "<TODO.md 1 行目をそのまま>"
run_start_sha: ${START_SHA}
decisions_jsonl: ~/.claude/logs/dev-impl/${run_id}/decisions.jsonl
output_path: /tmp/review-spec-compliance-${run_id}.json
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
docs_dir: docs/
approved_stamp: "<TODO.md 1 行目をそのまま>"
run_start_sha: ${START_SHA}
decisions_jsonl: ~/.claude/logs/dev-impl/${run_id}/decisions.jsonl
output_path: /tmp/review-spec-compliance-${run_id}.json
holdout_enabled: false
docs は自分で全文 Read すること。G_E2E は実行しないこと (別 agent が担当)。
作業結果 (output_path のパス) は必ず最終メッセージで親に返すこと。`
})

// 2 体目: G_E2E 実機検証 (Web プロダクトのみ。従来どおり)
Agent({ subagent_type: "review-product-readiness", model: "opus", prompt: `<dev_server 情報 + DESIGN_DETAIL_APP.md の UX 設計>` })
```

`holdout_enabled` は現時点でデフォルト無効。TODO.md に書かれていないエッジケースを review-spec-compliance が能動的に生成・検証する PoC 機能で (review-spec-compliance.md 参照)、効果測定後に有効化を検討する。
