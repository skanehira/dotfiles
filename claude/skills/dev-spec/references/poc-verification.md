# PoC 検証 (dev-spec フェーズ 5)

## 目的

FEASIBILITY.md に書かれた PoC 計画を**実際に実行して**、技術的実現可能性を機械検証する。「できるはず」という自己申告を、PoC コードの実行結果という観測可能な事実に置き換えてから設計書生成に進む。

## ワークフロー

### 1. PoC 計画の抽出

docs/FEASIBILITY.md を Read し、PoC 計画 (id / risk / blocker / スコープ / 成功基準) を抽出する。

- **blocker=true**: このフェーズでの検証が必須
- **blocker=false**: 任意。risk=high なら検証を推奨し、ユーザーに確認する
- **PoC 計画が 0 件**: 「PoC 検証: 対象なし (スキップ)」と表示して次フェーズへ

### 2. tech-investigation の並列 fan-out

対象の PoC 計画ごとに `tech-investigation` subagent を起動する。**互いに独立な調査なので、同一ターンで全件並列に起動する**こと。

```javascript
Task({
  description: "PoC: <id>",
  subagent_type: "tech-investigation",
  prompt: `
以下の PoC 計画を検証してください。

- marker: id=<id>, scope=<スコープ1行>, risk=<risk>, blocker=<blocker>
- context_paths: docs/FEASIBILITY.md (PoC 計画の全文と文脈を読むこと)
- output_path: /tmp/tech-investigation-<id>.json
- workspace_dir: /tmp/poc-<id>/

成功基準は FEASIBILITY.md の該当 PoC 計画に記載のものを使うこと。
`
})
```

### 3. 結果の反映

各 subagent の output_path から結果 JSON を Read し、FEASIBILITY.md に「## PoC 結果」セクションとして追記する。各項目に含めるもの:

```markdown
## PoC 結果

### <id> — verified | partial | fallback_needed
- 検証日: YYYY-MM-DD
- 観測した事実: (実行したコード・コマンドと出力の要点)
- 結論: 成功基準に対する判定
- fallback: (fallback_needed の場合のみ) 代替案
```

対応する PoC 計画には `**status**: resolved (verified)` のように解決状態を記す。

### 4. 失敗時の分岐 (Stop)

`fallback_needed` または `partial` の結果が出た場合、**勝手に設計を曲げず**、ユーザーに判断を仰ぐ:

```javascript
AskUserQuestion({
  questions: [{
    question: "PoC「<id>」で当初案が成立しないことが確認されました。\n\n観測した事実: <要点>\n\nどうしますか?",
    header: "PoC 失敗",
    options: [
      { label: "fallback 採用", description: "<tech-investigation が提示した代替案の要点>" },
      { label: "スコープ縮小", description: "この機能要素を今回のスコープから外す" },
      { label: "設計を再検討", description: "実現可能性検証 (フェーズ 4) に戻って前提から見直す" },
      { label: "中止", description: "設計ループを終了する" }
    ],
    multiSelect: false
  }]
})
```

ユーザーの決定を FEASIBILITY.md の該当 PoC 結果に「**採用した判断**: ...」として記録する。

### 5. ゲート判定

blocker=true の全 PoC 計画が「verified」または「ユーザーが fallback 採用 / スコープ縮小を決定」になったことを確認してから、次フェーズへ進む。未解決が残る場合はこのフェーズを完了扱いにしない。

## 後段との連動

- フェーズ 7 (analyzing-requirements) は、FEASIBILITY.md の PoC 結果を技術選定の根拠として DESIGN.md に反映し、未検証で残った `blocker=false` の PoC 計画のみ `POC_NEEDED` マーカーとして DESIGN_DETAIL.md に転記する
- 実装ループ (`/dev-impl`) は起動時に DESIGN_DETAIL.md の `blocker=true` マーカー残存をチェックし、見つけたら実装に入らず本フェーズへの差し戻しを案内する (安全網)
