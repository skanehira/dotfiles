# Claude Code Skills

プロダクト開発を支援するClaude Codeスキル集。

## ディレクトリ構成

```
skills/
├── ideation/                           # /ideation オーケストレーター
├── ideation-problem-definition/
├── ideation-competitor-analysis/
├── ideation-slc-ideation/
├── requirements/                       # /requirements オーケストレーター
├── requirements-user-story/
├── requirements-ui-sketch/
├── requirements-usecase-description/
├── requirements-feasibility-check/
├── requirements-ddd-modeling/
├── requirements-analyzing-requirements/
├── requirements-interview/
├── implementation-developing/
├── implementation-planning-tasks/
├── implementation-writing-tests/
├── workflow-ask/
├── workflow-commit-push/
├── workflow-impl/
├── workflow-review/
├── workflow-spec/
├── utility-codex/
├── utility-create-skill/
├── utility-creating-rules/
├── utility-fix-lsp-warnings/
├── utility-reviewing-skills/
└── README.md
```

> **命名規則**: `{フェーズ}-{スキル名}` の形式。Claude Codeはディレクトリ名をスキル識別子として使用するため、フラット構造でフェーズプレフィックスを付与。

## 開発フロー

```
┌──────────────────────────────────────────────────────────────────────┐
│                      アイデア・企画フェーズ                          │
├──────────────────────────────────────────────────────────────────────┤
│  1. problem-definition     ユーザーの問題を深掘り（JTBD）            │
│           ↓                                                          │
│  2. competitor-analysis    競合を調査し差別化ポイントを明確に        │
│           ↓                                                          │
│  3. slc-ideation          アイデアを壁打ちしてSLCで磨く              │
├──────────────────────────────────────────────────────────────────────┤
│                      要件・設計フェーズ                              │
├──────────────────────────────────────────────────────────────────────┤
│  4. user-story            ユーザーストーリーと優先順位付け           │
│           ↓                                                          │
│  5. ui-sketch             画面構成とワイヤーフレーム                 │
│           ↓                                                          │
│  6. usecase-description   詳細なユースケース記述（フロー・異常系）   │
│           ↓                                                          │
│  7. feasibility-check     技術リスクの検証とPoC計画                  │
│           ↓                                                          │
│  8. ddd-modeling          ドメインモデリング（用語集・モデル図）     │
│           ↓                                                          │
│  9. analyzing-requirements 技術設計書（DESIGN.md）の作成             │
│           ↓                                                          │
│ 10. interview             深掘りインタビューで仕様をブラッシュアップ │
├──────────────────────────────────────────────────────────────────────┤
│                      実装フェーズ                                    │
├──────────────────────────────────────────────────────────────────────┤
│ 11. planning-tasks        TODO.mdの作成                              │
│           ↓                                                          │
│ 12. developing            TDDで実装                                  │
└──────────────────────────────────────────────────────────────────────┘
```

## スキル一覧

### アイデア・企画フェーズ

| スキル                                                          | 説明                                                              | 入力                                          | 出力                   |
| --------------------------------------------------------------- | ----------------------------------------------------------------- | --------------------------------------------- | ---------------------- |
| [ideation-problem-definition](./ideation-problem-definition/)   | JTBD（Jobs To Be Done）とペイン・ゲイン分析でユーザーの問題を定義 | -                                             | PROBLEM_DEFINITION.md  |
| [ideation-competitor-analysis](./ideation-competitor-analysis/) | 直接競合・間接競合を分析し、差別化ポイントを明確化                | PROBLEM_DEFINITION.md                         | COMPETITOR_ANALYSIS.md |
| [ideation-slc-ideation](./ideation-slc-ideation/)               | SLC（Simple, Lovable, Complete）フレームワークでアイデアを壁打ち  | PROBLEM_DEFINITION.md, COMPETITOR_ANALYSIS.md | PRODUCT_SPEC.md        |

### 要件・設計フェーズ

| スキル                                                                        | 説明                                                       | 入力                                               | 出力                  |
| ----------------------------------------------------------------------------- | ---------------------------------------------------------- | -------------------------------------------------- | --------------------- |
| [requirements-user-story](./requirements-user-story/)                         | ユーザーストーリーを作成し、MoSCoW/ICEで優先順位付け       | PRODUCT_SPEC.md, PROBLEM_DEFINITION.md             | USER_STORIES.md       |
| [requirements-ui-sketch](./requirements-ui-sketch/)                           | 画面構成、ユーザーフロー、ASCIIワイヤーフレームを作成      | USER_STORIES.md, PRODUCT_SPEC.md                   | UI_SKETCH.md          |
| [requirements-usecase-description](./requirements-usecase-description/)       | 正常系・異常系・代替フロー、ビジネスルールを詳細化         | USER_STORIES.md                                    | USECASES.md           |
| [requirements-feasibility-check](./requirements-feasibility-check/)           | 技術リスクを評価し、PoC計画を作成                          | USECASES.md, PRODUCT_SPEC.md                       | FEASIBILITY.md        |
| [requirements-ddd-modeling](./requirements-ddd-modeling/)                     | ドメインエキスパートと対話し、用語集とドメインモデルを作成 | USECASES.md, FEASIBILITY.md, USER_STORIES.md       | GLOSSARY.md, MODEL.md |
| [requirements-analyzing-requirements](./requirements-analyzing-requirements/) | 技術設計書を作成                                           | USECASES.md, FEASIBILITY.md, GLOSSARY.md, MODEL.md | DESIGN.md             |

### 実装フェーズ

| スキル                                                            | 説明                                  | 出力           |
| ----------------------------------------------------------------- | ------------------------------------- | -------------- |
| [implementation-planning-tasks](./implementation-planning-tasks/) | 設計書からTDD準拠のタスクリストを作成 | TODO.md        |
| [implementation-developing](./implementation-developing/)         | TDD（RED→GREEN→REFACTOR）で実装       | コード         |
| [implementation-writing-tests](./implementation-writing-tests/)   | テストコードを作成                    | テストファイル |

### ワークフロースキル

| スキル                                              | 説明                                                                              |
| --------------------------------------------------- | --------------------------------------------------------------------------------- |
| [workflow-spec](./workflow-spec/)                   | DESIGN.md + TODO.mdを対話的に生成（analyzing-requirements + planning-tasks統合）  |
| [workflow-impl](./workflow-impl/)                   | TDD（RED→GREEN→REFACTOR）でフェーズ単位の実装                                     |
| [workflow-review](./workflow-review/)               | git差分を5観点でコードレビュー（TDD、品質、セキュリティ、アーキテクチャ、ルール） |
| [workflow-ask](./workflow-ask/)                     | インタビュー → 確認 → 実行の3段階タスク実行                                       |
| [requirements-interview](./requirements-interview/) | DESIGN.mdを深掘りインタビューして仕様追記                                         |
| [workflow-commit-push](./workflow-commit-push/)     | Conventional Commit形式でコミット＆プッシュ                                       |

### ユーティリティ

| スキル                                                  | 説明                                         |
| ------------------------------------------------------- | -------------------------------------------- |
| [utility-creating-rules](./utility-creating-rules/)     | .claude/rules/にルールファイルを作成         |
| [utility-reviewing-skills](./utility-reviewing-skills/) | スキルをベストプラクティスに基づいてレビュー |
| [utility-fix-lsp-warnings](./utility-fix-lsp-warnings/) | LSP警告を検出・修正                          |
| [utility-create-skill](./utility-create-skill/)         | スキル作成 + レビュー・自動修正              |
| [utility-codex](./utility-codex/)                       | Codex CLIでセカンドオピニオン取得            |

## 使い方

各スキルは `/スキル名` で起動できる。

```
/ideation-problem-definition    # 問題定義を開始
/requirements-user-story        # ユーザーストーリー作成を開始
/implementation-developing      # TDD開発を開始
/workflow-spec                  # 設計書+タスクリスト生成
/workflow-impl                  # TDD実装開始
/workflow-review                # コードレビュー
/workflow-commit-push           # コミット＆プッシュ
```

## フェーズスキル

開発フローのフェーズ全体を実行するオーケストレータースキル：

| スキル           | フェーズ       | 実行スキル                                                                                                                                                                             |
| ---------------- | -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/ideation`      | アイデア・企画 | ideation-problem-definition → ideation-competitor-analysis → ideation-slc-ideation                                                                                                     |
| `/requirements`  | 要件・設計     | requirements-user-story → requirements-ui-sketch → requirements-usecase-description → requirements-feasibility-check → requirements-ddd-modeling → requirements-analyzing-requirements |
| `/workflow-spec` | 設計+計画      | requirements-analyzing-requirements → requirements-interview → implementation-planning-tasks                                                                                           |

各スキル完了後に確認が入り、途中で終了することも可能。
既存ドキュメントがある場合は、スキップして途中から開始できる。

## 補足

- **必ずしも全スキルを使う必要はない** - プロジェクトの規模や状況に応じてスキップ可能
- **slc-ideationは壁打ち用** - アイデアの初期段階で仮説を検証するためのフレームワーク
- **feasibility-checkは技術リスクがある場合** - 不確実性が高い技術を使う場合に実施
- **各スキルはセルフレビュー機能を持つ** - 生成したドキュメントを自動でレビュー・修正
