---
name: requirements
description: 要件・設計フェーズのオーケストレーター。ユーザーストーリー → UI スケッチ → ユースケース記述 → 実現可能性検証 → DDD モデリング → 概要/詳細設計 (DESIGN.md / DESIGN_DETAIL.md) → 深掘りインタビューを対話的に実行する。「設計フェーズを開始」「要件を整理したい」「ユーザーストーリーを書きたい」「UI を整理したい」「ユースケースを詳細化したい」「技術的に実現できるか確認したい」「ドメインモデルを作成」「DESIGN.md を深掘りしたい」などで起動。該当フェーズからの部分実行も可能。
---

# 要件・設計フェーズ

## 概要

6 つのフェーズ (+ 任意の深掘りインタビュー) を順次実行し、プロダクトの要件と設計をまとめる。最終的に DESIGN.md (概要) と DESIGN_DETAIL.md (詳細) の 2 ファイルを生成する。

各フェーズの手順書は `references/` にある。**フェーズを開始するときに該当ファイルを Read し、その手順に従う**:

| # | フェーズ                  | 手順書                                 | 出力                                  |
| - | ------------------------- | -------------------------------------- | ------------------------------------- |
| 1 | ユーザーストーリー        | `references/user-story.md`             | docs/USER_STORIES.md                  |
| 2 | UI スケッチ               | `references/ui-sketch.md`              | docs/UI_SKETCH.md                     |
| 3 | ユースケース記述          | `references/usecase-description.md`    | docs/USECASES.md                      |
| 4 | 実現可能性検証            | `references/feasibility-check.md`      | docs/FEASIBILITY.md                   |
| 5 | DDD モデリング            | `references/ddd-modeling.md`           | docs/GLOSSARY.md, docs/MODEL.md       |
| 6 | 概要/詳細設計             | `references/analyzing-requirements.md` | docs/DESIGN.md, docs/DESIGN_DETAIL.md |
| 7 | 深掘りインタビュー (任意) | `references/interview.md`              | DESIGN.md / DESIGN_DETAIL.md 更新     |

## 部分実行

ユーザーの依頼が特定フェーズだけを指す場合 (例: 「ユースケースを詳細化したい」「DESIGN.md を深掘りしたい」) は、全フェーズを回さず該当フェーズの手順書だけを Read して実行する。

## ワークフロー (全フェーズ実行時)

### フェーズ0: 既存ドキュメントの確認

docs/ 配下の既存成果物 (USER_STORIES.md / UI_SKETCH.md / USECASES.md / FEASIBILITY.md / GLOSSARY.md / DESIGN.md) を確認し、存在するものがあれば開始ポイントを AskUserQuestion で確認する:

```javascript
AskUserQuestion({
  questions: [{
    question: "既存のドキュメントがあります。どこから開始しますか？",
    header: "開始ポイント",
    options: [
      { label: "最初から", description: "フェーズ1 (ユーザーストーリー) から開始" },
      { label: "続きから (推奨)", description: "最後に生成されたドキュメントの次のフェーズから" }
    ],
    multiSelect: false
  }]
})
```

### 各フェーズの進め方

1. 進捗を表示する:

```
📍 要件・設計フェーズ [n/6]
   ├─ ✓ user-story（完了）
   ├─ ▶ ui-sketch（実行中）
   └─ ○ ...
```

2. `references/<フェーズ>.md` を Read し、手順に従って実行する
3. フェーズ完了後、AskUserQuestion で「次へ進む / ここで終了」を確認する

### 完了

```
✅ 要件・設計フェーズ完了

生成されたドキュメント：
- docs/USER_STORIES.md / UI_SKETCH.md / USECASES.md / FEASIBILITY.md
- docs/GLOSSARY.md / MODEL.md
- docs/DESIGN.md          (概要設計)
- docs/DESIGN_DETAIL.md   (詳細設計)

次のステップ：
- /workflow-spec で深掘り + TODO.md 生成 → 実装方式選択 (autopilot 自律 / developing 対話 / 手動)
- 既に TODO.md がある場合は /workflow-autopilot で自律実装、または /implementation-developing で対話実装
```

## 完了条件

- [ ] 対象フェーズがすべて実行された（またはスキップ）
- [ ] 全フェーズ実行時: DESIGN.md (概要) と DESIGN_DETAIL.md (詳細) が生成された

## 関連スキル

- **workflow-spec**: 設計承認後の計画フェーズ (深掘り + TODO.md 生成)。本スキルの references/analyzing-requirements.md / interview.md を共用する
