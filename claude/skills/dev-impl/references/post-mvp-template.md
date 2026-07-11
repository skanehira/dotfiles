# POST_MVP.md「UI/UX gap」セクション テンプレート (dev-impl Step 5.6)

```markdown
## UI/UX gap (dev-impl ${run_id} 時点)

### 未実装画面
- <DESIGN にあるが実装されていない画面>

### 未実装ナビ経路
- <DESIGN_DETAIL_APP.md UX 設計のナビ仕様に対して、実機で到達できない画面>
  (review-product-readiness の `nav_unreachable` finding を反映)

### frontend-design 未適用フラグ
- 適用済 / 未適用 (未適用なら理由を記載)

### a11y 未対応項目
- <review-product-readiness や手動チェックで残った a11y 違反>

### 視覚的回帰参照
- スナップショット: /tmp/review-product-readiness-snapshots/<phase>/
```

各項目は **dev-impl が自動でログ / review 結果から収集して埋める** (decisions.jsonl / review-product-readiness の findings / G_E2E 判定結果から)。

