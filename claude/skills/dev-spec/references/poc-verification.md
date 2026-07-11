# PoC 検証 (dev-spec フェーズ 5)

## 目的

FEASIBILITY.md に書かれた PoC 計画を**実際に実行して**、技術的実現可能性を機械検証する。「できるはず」という自己申告を、PoC コードの実行結果という観測可能な事実に置き換えてから設計書生成に進む。

## POC_STATUS 行 (機械判定用の状態書式)

各 PoC 計画は直下に必ず 1 行、次の書式の status 行を持つ (フェーズ 4 が `status=unresolved` で書き、本フェーズが更新する)。フィールドの順序は固定:

```
<!-- POC_STATUS: id=<id>, blocker=<true|false>, status=<unresolved|verified|fallback_adopted|scope_reduced>, confidence=<0.0-1.0> -->
```

- `status=unresolved`: 未検証 (フェーズ 4 直後の初期値。confidence は省略)
- `status=verified`: 検証済み、当初案で進める
- `status=fallback_adopted`: 当初案不成立、ユーザーが fallback 採用を決定
- `status=scope_reduced`: ユーザーがスコープ縮小を決定

フェーズ 7 のゲートはこの行を `rg 'POC_STATUS:.*blocker=true.*status=unresolved'` で判定する。**本文の説明ではなくこの行が唯一の判定ソース**なので、更新漏れ = ゲートが閉じたままになる (安全側)。

## ワークフロー

### 1. 対象の抽出

docs/FEASIBILITY.md を Read し、`status=unresolved` の POC_STATUS 行を抽出する。

- **blocker=true**: このフェーズでの検証が必須
- **blocker=false**: 任意。risk=high なら検証を推奨し、ユーザーに確認する
- **対象 0 件**: 「PoC 検証: 対象なし (スキップ)」と表示して次フェーズへ

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

### 3. 結果の分類と反映

各 subagent の output_path から結果 JSON を Read し、次の表で分類する。**agent の失敗や低確信をパス扱いにしない** (未検証は未検証のまま人間に回す):

| 結果 | 扱い |
| --- | --- |
| `result: verified` かつ `confidence >= 0.7` | 自動で解決。POC_STATUS を `status=verified, confidence=<値>` に更新 |
| `result: verified` かつ `confidence < 0.7` | **自動解決しない** (ドキュメント確認のみ等、実行結果の裏付けが弱い)。ステップ 4 の人間判断へ |
| `result: partial` / `fallback_needed` | ステップ 4 の人間判断へ |
| stdout が `INVALID_MARKER` / `NO_CONTEXT_DOCS` / `INVESTIGATION_FAILED`、または JSON が読めない・agent が応答しない | **その計画は未検証のまま** (status は unresolved を維持)。ステップ 4 の人間判断へ (選択肢に「再試行」を含める) |

解決した計画は FEASIBILITY.md に「## PoC 結果」セクションとして追記する:

```markdown
## PoC 結果

### <id> — verified (confidence 0.85)
- 検証日: YYYY-MM-DD
- 観測した事実: (実行したコード・コマンドと出力の要点)
- 結論: 成功基準に対する判定
- fallback: (採用した場合のみ) 代替案と採用理由
```

### 4. 人間判断 (Stop)

自動解決できなかった計画ごとに、**勝手に設計を曲げず**ユーザーに判断を仰ぐ:

```javascript
AskUserQuestion({
  questions: [{
    question: "PoC「<id>」が自動解決できませんでした。\n\n理由: <verified だが confidence 0.6 / fallback_needed / agent 失敗 など>\n観測した事実: <要点>\n\nどうしますか?",
    header: "PoC 判断",
    options: [
      { label: "この結果で採用", description: "verified 扱いにする (POC_STATUS を verified に更新)" },
      { label: "fallback 採用", description: "<tech-investigation が提示した代替案の要点>" },
      { label: "スコープ縮小", description: "この機能要素を今回のスコープから外す" },
      { label: "再試行 / 再検討", description: "PoC を追加指示付きで再実行する、またはフェーズ 4 に戻って前提から見直す" }
    ],
    multiSelect: false
  }]
})
```

ユーザーの決定に従って POC_STATUS を更新し、「PoC 結果」に「**採用した判断**: ...」として記録する。「再試行」の場合は status を unresolved のまま残してステップ 2 に戻る。

### 5. ゲート判定 (機械)

フェーズ完了前に必ず実行する:

```bash
rg -n 'POC_STATUS:.*blocker=true.*status=unresolved' docs/FEASIBILITY.md
```

0 件になるまでこのフェーズを完了扱いにしない (1 件以上残っていればステップ 2 または 4 に戻る)。

## 後段との連動

- フェーズ 7 (analyzing-requirements) は、FEASIBILITY.md の PoC 結果を技術選定の根拠として DESIGN.md に反映し、未検証で残った `blocker=false` の PoC 計画のみ `POC_NEEDED` マーカーとして DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md の該当側に転記する
- 実装ループ (`/dev-impl`) は起動時に DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md の `blocker=true` マーカー残存をチェックし、見つけたら実装に入らず本フェーズへの差し戻しを案内する (安全網)
