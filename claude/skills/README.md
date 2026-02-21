# Claude Code Skills

プロダクト開発を支援するClaude Codeスキル集。

## 開発フロー

```
┌────────────────────────────────────────────────────────────────────┐
│                      アイデア・企画フェーズ                        │
├────────────────────────────────────────────────────────────────────┤
│  1. problem-definition     ユーザーの問題を深掘り（JTBD）          │
│           ↓                                                        │
│  2. competitor-analysis    競合を調査し差別化ポイントを明確に      │
│           ↓                                                        │
│  3. slc-ideation          アイデアを壁打ちしてSLCで磨く            │
├────────────────────────────────────────────────────────────────────┤
│                      要件・設計フェーズ                            │
├────────────────────────────────────────────────────────────────────┤
│  4. user-story            ユーザーストーリーと優先順位付け         │
│           ↓                                                        │
│  5. ui-sketch             画面構成とワイヤーフレーム               │
│           ↓                                                        │
│  6. usecase-description   詳細なユースケース記述（フロー・異常系） │
│           ↓                                                        │
│  7. feasibility-check     技術リスクの検証とPoC計画                │
│           ↓                                                        │
│  8. ddd-modeling          ドメインモデリング（用語集・モデル図）   │
│           ↓                                                        │
│  9. analyzing-requirements 技術設計書（DESIGN.md）の作成           │
├────────────────────────────────────────────────────────────────────┤
│                      実装フェーズ                                  │
├────────────────────────────────────────────────────────────────────┤
│ 10. planning-tasks        TODO.mdの作成                            │
│           ↓                                                        │
│ 11. developing            TDDで実装                                │
└────────────────────────────────────────────────────────────────────┘
```

## スキル一覧

### アイデア・企画フェーズ

| スキル                                        | 説明                                                              | 入力                                          | 出力                   |
| --------------------------------------------- | ----------------------------------------------------------------- | --------------------------------------------- | ---------------------- |
| [problem-definition](./problem-definition/)   | JTBD（Jobs To Be Done）とペイン・ゲイン分析でユーザーの問題を定義 | -                                             | PROBLEM_DEFINITION.md  |
| [competitor-analysis](./competitor-analysis/) | 直接競合・間接競合を分析し、差別化ポイントを明確化                | PROBLEM_DEFINITION.md                         | COMPETITOR_ANALYSIS.md |
| [slc-ideation](./slc-ideation/)               | SLC（Simple, Lovable, Complete）フレームワークでアイデアを壁打ち  | PROBLEM_DEFINITION.md, COMPETITOR_ANALYSIS.md | PRODUCT_SPEC.md        |

### 要件・設計フェーズ

| スキル                                              | 説明                                                       | 入力                                               | 出力                  |
| --------------------------------------------------- | ---------------------------------------------------------- | -------------------------------------------------- | --------------------- |
| [user-story](./user-story/)                         | ユーザーストーリーを作成し、MoSCoW/ICEで優先順位付け       | PRODUCT_SPEC.md, PROBLEM_DEFINITION.md             | USER_STORIES.md       |
| [ui-sketch](./ui-sketch/)                           | 画面構成、ユーザーフロー、ASCIIワイヤーフレームを作成      | USER_STORIES.md, PRODUCT_SPEC.md                   | UI_SKETCH.md          |
| [usecase-description](./usecase-description/)       | 正常系・異常系・代替フロー、ビジネスルールを詳細化         | USER_STORIES.md                                    | USECASES.md           |
| [feasibility-check](./feasibility-check/)           | 技術リスクを評価し、PoC計画を作成                          | USECASES.md, PRODUCT_SPEC.md                       | FEASIBILITY.md        |
| [ddd-modeling](./ddd-modeling/)                     | ドメインエキスパートと対話し、用語集とドメインモデルを作成 | USECASES.md, FEASIBILITY.md, USER_STORIES.md       | GLOSSARY.md, MODEL.md |
| [analyzing-requirements](./analyzing-requirements/) | 技術設計書を作成                                           | USECASES.md, FEASIBILITY.md, GLOSSARY.md, MODEL.md | DESIGN.md             |

### 実装フェーズ

| スキル                              | 説明                                  | 出力           |
| ----------------------------------- | ------------------------------------- | -------------- |
| [planning-tasks](./planning-tasks/) | 設計書からTDD準拠のタスクリストを作成 | TODO.md        |
| [developing](./developing/)         | TDD（RED→GREEN→REFACTOR）で実装       | コード         |
| [writing-tests](./writing-tests/)   | テストコードを作成                    | テストファイル |

### ワークフロースキル

| スキル                        | 説明                                                                              |
| ----------------------------- | --------------------------------------------------------------------------------- |
| [spec](./spec/)               | DESIGN.md + TODO.mdを対話的に生成（analyzing-requirements + planning-tasks統合）  |
| [impl](./impl/)               | TDD（RED→GREEN→REFACTOR）でフェーズ単位の実装                                     |
| [review](./review/)           | git差分を5観点でコードレビュー（TDD、品質、セキュリティ、アーキテクチャ、ルール） |
| [ask](./ask/)                 | インタビュー → 確認 → 実行の3段階タスク実行                                       |
| [interview](./interview/)     | DESIGN.mdを深掘りインタビューして仕様追記                                         |
| [commit-push](./commit-push/) | Conventional Commit形式でコミット＆プッシュ                                       |

### ユーティリティ

| スキル                                  | 説明                                         |
| --------------------------------------- | -------------------------------------------- |
| [creating-rules](./creating-rules/)     | .claude/rules/にルールファイルを作成         |
| [reviewing-skills](./reviewing-skills/) | スキルをベストプラクティスに基づいてレビュー |
| [fix-lsp-warnings](./fix-lsp-warnings/) | LSP警告を検出・修正                          |
| [create-skill](./create-skill/)         | スキル作成 + レビュー・自動修正              |
| [codex](./codex/)                       | Codex CLIでセカンドオピニオン取得            |

## 使い方

各スキルは `/スキル名` で起動できる。

```
/problem-definition    # 問題定義を開始
/user-story           # ユーザーストーリー作成を開始
/developing           # TDD開発を開始
/spec                 # 設計書+タスクリスト生成
/impl                 # TDD実装開始
/review               # コードレビュー
/commit-push          # コミット＆プッシュ
```

## フェーズスキル

開発フローのフェーズ全体を実行するスキル：

| スキル          | フェーズ       | 実行スキル                                                                                               |
| --------------- | -------------- | -------------------------------------------------------------------------------------------------------- |
| `/ideation`     | アイデア・企画 | problem-definition → competitor-analysis → slc-ideation                                                  |
| `/requirements` | 要件・設計     | user-story → ui-sketch → usecase-description → feasibility-check → ddd-modeling → analyzing-requirements |
| `/spec`         | 設計+計画      | analyzing-requirements → interview → planning-tasks                                                      |

各スキル完了後に確認が入り、途中で終了することも可能。
既存ドキュメントがある場合は、スキップして途中から開始できる。

## 補足

- **必ずしも全スキルを使う必要はない** - プロジェクトの規模や状況に応じてスキップ可能
- **slc-ideationは壁打ち用** - アイデアの初期段階で仮説を検証するためのフレームワーク
- **feasibility-checkは技術リスクがある場合** - 不確実性が高い技術を使う場合に実施
- **各スキルはセルフレビュー機能を持つ** - 生成したドキュメントを自動でレビュー・修正
