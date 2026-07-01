---
name: requirements
description: 要件・設計フェーズを実行。requirements-user-story → requirements-ui-sketch → requirements-usecase-description → requirements-feasibility-check → requirements-ddd-modeling → requirements-analyzing-requirements を順次実行し、DESIGN.md (概要) と DESIGN_DETAIL.md (詳細) を生成。「設計フェーズを開始」「要件を整理したい」「/requirements」などで起動。
---

# 要件・設計フェーズ

## 概要

6つのスキルを順次実行し、プロダクトの要件と設計をまとめる。最終的に DESIGN.md (概要) と DESIGN_DETAIL.md (詳細) の 2 ファイルを生成する。

## 実行スキル

1. **requirements-user-story** → docs/USER_STORIES.md
2. **requirements-ui-sketch** → docs/UI_SKETCH.md
3. **requirements-usecase-description** → docs/USECASES.md
4. **requirements-feasibility-check** → docs/FEASIBILITY.md
5. **requirements-ddd-modeling** → docs/GLOSSARY.md, docs/MODEL.md
6. **requirements-analyzing-requirements** → docs/DESIGN.md, docs/DESIGN_DETAIL.md

## 前提条件

以下のファイルが存在することを推奨：
- docs/PRODUCT_SPEC.md（/ideation で生成）
- docs/PROBLEM_DEFINITION.md

## ワークフロー

### フェーズ0: 既存ドキュメントの確認

以下のファイルを確認し、開始ポイントを提案する。

```javascript
Read({ file_path: "docs/PRODUCT_SPEC.md" })
Read({ file_path: "docs/USER_STORIES.md" })
Read({ file_path: "docs/UI_SKETCH.md" })
Read({ file_path: "docs/USECASES.md" })
Read({ file_path: "docs/FEASIBILITY.md" })
Read({ file_path: "docs/GLOSSARY.md" })
Read({ file_path: "docs/DESIGN.md" })
```

存在するファイルがあれば、スキップするか確認：

```javascript
AskUserQuestion({
  questions: [{
    question: "既存のドキュメントがあります。どこから開始しますか？",
    header: "開始ポイント",
    options: [
      { label: "最初から", description: "user-storyから開始" },
      { label: "ui-sketchから", description: "USER_STORIES.mdを活用" },
      { label: "usecase-descriptionから", description: "UI_SKETCH.mdを活用" },
      { label: "feasibility-checkから", description: "USECASES.mdを活用" }
    ],
    multiSelect: false
  }]
})
```

**遷移条件**: 開始ポイントが決まったら該当ステップへ

### ステップ1: ユーザーストーリー

進捗を表示：

```
📍 要件・設計フェーズ [1/6]
   ├─ ▶ requirements-user-story（実行中）
   ├─ ○ requirements-ui-sketch
   ├─ ○ requirements-usecase-description
   ├─ ○ requirements-feasibility-check
   ├─ ○ requirements-ddd-modeling
   └─ ○ requirements-analyzing-requirements
```

`requirements-user-story` スキルを Skill ツールで実行する。

完了後、確認：

```javascript
AskUserQuestion({
  questions: [{
    question: "user-storyが完了しました。次に進みますか？",
    header: "次のステップ",
    options: [
      { label: "次へ進む", description: "ui-sketchを開始" },
      { label: "ここで終了", description: "後で続きを実行" }
    ],
    multiSelect: false
  }]
})
```

### ステップ2: UI設計

進捗を表示：

```
📍 要件・設計フェーズ [2/6]
   ├─ ✓ requirements-user-story（完了）
   ├─ ▶ requirements-ui-sketch（実行中）
   ├─ ○ requirements-usecase-description
   ├─ ○ requirements-feasibility-check
   ├─ ○ requirements-ddd-modeling
   └─ ○ requirements-analyzing-requirements
```

`requirements-ui-sketch` スキルを Skill ツールで実行する。

完了後、同様に確認。

### ステップ3: ユースケース記述

進捗を表示：

```
📍 要件・設計フェーズ [3/6]
   ├─ ✓ requirements-user-story（完了）
   ├─ ✓ requirements-ui-sketch（完了）
   ├─ ▶ requirements-usecase-description（実行中）
   ├─ ○ requirements-feasibility-check
   ├─ ○ requirements-ddd-modeling
   └─ ○ requirements-analyzing-requirements
```

`requirements-usecase-description` スキルを Skill ツールで実行する。

完了後、同様に確認。

### ステップ4: 技術検証

進捗を表示：

```
📍 要件・設計フェーズ [4/6]
   ├─ ✓ requirements-user-story（完了）
   ├─ ✓ requirements-ui-sketch（完了）
   ├─ ✓ requirements-usecase-description（完了）
   ├─ ▶ requirements-feasibility-check（実行中）
   ├─ ○ requirements-ddd-modeling
   └─ ○ requirements-analyzing-requirements
```

`requirements-feasibility-check` スキルを Skill ツールで実行する。

完了後、同様に確認。

### ステップ5: ドメインモデリング

進捗を表示：

```
📍 要件・設計フェーズ [5/6]
   ├─ ✓ requirements-user-story（完了）
   ├─ ✓ requirements-ui-sketch（完了）
   ├─ ✓ requirements-usecase-description（完了）
   ├─ ✓ requirements-feasibility-check（完了）
   ├─ ▶ requirements-ddd-modeling（実行中）
   └─ ○ requirements-analyzing-requirements
```

`requirements-ddd-modeling` スキルを Skill ツールで実行する。

完了後、同様に確認。

### ステップ6: 技術設計

進捗を表示：

```
📍 要件・設計フェーズ [6/6]
   ├─ ✓ requirements-user-story（完了）
   ├─ ✓ requirements-ui-sketch（完了）
   ├─ ✓ requirements-usecase-description（完了）
   ├─ ✓ requirements-feasibility-check（完了）
   ├─ ✓ requirements-ddd-modeling（完了）
   └─ ▶ requirements-analyzing-requirements（実行中）
```

`requirements-analyzing-requirements` スキルを Skill ツールで実行する。

### 完了

```
✅ 要件・設計フェーズ完了

生成されたドキュメント：
- docs/USER_STORIES.md
- docs/UI_SKETCH.md
- docs/USECASES.md
- docs/FEASIBILITY.md
- docs/GLOSSARY.md
- docs/MODEL.md
- docs/DESIGN.md          (概要設計)
- docs/DESIGN_DETAIL.md   (詳細設計)

次のステップ：
- /workflow-spec で深掘り + TODO.md 生成 → 実装方式選択 (autopilot 自律 / developing 対話 / 手動)
- 既に TODO.md がある場合は /workflow-autopilot で自律実装、または /implementation-developing で対話実装
```

## 完了条件

- [ ] 6つのスキルがすべて実行された（またはスキップ）
- [ ] DESIGN.md (概要) と DESIGN_DETAIL.md (詳細) が生成された

## 関連スキル

- **ideation**: 前フェーズ（アイデア・企画）
- **implementation**: 次フェーズ（実装）へ進む場合に使用
