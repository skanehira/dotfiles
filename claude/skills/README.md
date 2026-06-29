# Claude Code Skills

プロダクト開発を支援するClaude Codeスキル集。

## ディレクトリ構成

```
skills/
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
├── workflow-autopilot/                 # 自律実装オーケストレーター
├── workflow-commit/
├── workflow-create-draft-pr/
├── workflow-debate/
├── workflow-review/
├── workflow-spec/
├── demo-site-builder/
├── slide-generating/
├── vercel-composition-patterns/
├── vercel-react-best-practices/
├── utility-codex/
├── utility-create-skill/
├── utility-creating-rules/
├── utility-drawio/
├── utility-fix-lsp-warnings/
├── utility-reviewing-skills/
└── README.md
```

> **命名規則**: `{プレフィックス}-{スキル名}` の形式。Claude Code はディレクトリ名をスキル識別子として使用するため、フラット構造でプレフィックスを付与。
>
> **プレフィックスの意味**:
> - `requirements-*` — 要件・設計フェーズの個別スキル (building block)
> - `implementation-*` — 実装フェーズの個別スキル
> - `workflow-*` — 対話的オーケストレーター / エントリポイント
> - `utility-*` — 単発のユーティリティ

## 開発フロー

```
┌──────────────────────────────────────────────────────────────────────────┐
│                      要件・設計フェーズ                                  │
├──────────────────────────────────────────────────────────────────────────┤
│  1. user-story            ユーザーストーリーと優先順位付け               │
│           ↓                                                              │
│  2. ui-sketch             画面構成とワイヤーフレーム                     │
│           ↓                                                              │
│  3. usecase-description   詳細なユースケース記述（フロー・異常系）       │
│           ↓                                                              │
│  4. feasibility-check     技術リスクの検証とPoC計画                      │
│           ↓                                                              │
│  5. ddd-modeling          ドメインモデリング（用語集・モデル図）         │
│           ↓                                                              │
│  6. analyzing-requirements DESIGN.md (概要) + DESIGN_DETAIL.md (詳細)    │
│           ↓                                                              │
│  7. interview             深掘りインタビュー (両ファイル更新)            │
├──────────────────────────────────────────────────────────────────────────┤
│                      実装フェーズ                                        │
├──────────────────────────────────────────────────────────────────────────┤
│  8. planning-tasks        TODO.md の作成 (DESIGN_DETAIL.md から)         │
│           ↓                                                              │
│  9a. autopilot            TODO 全フェーズ自律消化 (機械型)               │
│           or                                                             │
│  9b. developing           TDD でフェーズ単位の対話実装                   │
│           ↓                                                              │
│ 10. commit                Conventional Commit でコミット                 │
└──────────────────────────────────────────────────────────────────────────┘
```

## スキル一覧

### 要件・設計フェーズ

| スキル                                                                        | 説明                                                       | 入力                                               | 出力                  |
| ----------------------------------------------------------------------------- | ---------------------------------------------------------- | -------------------------------------------------- | --------------------- |
| [requirements-user-story](./requirements-user-story/)                         | ユーザーストーリーを作成し、MoSCoW/ICE で優先順位付け      | -                                                  | USER_STORIES.md       |
| [requirements-ui-sketch](./requirements-ui-sketch/)                           | 画面構成、ユーザーフロー、ASCII ワイヤーフレームを作成     | USER_STORIES.md                                    | UI_SKETCH.md          |
| [requirements-usecase-description](./requirements-usecase-description/)       | 正常系・異常系・代替フロー、ビジネスルールを詳細化         | USER_STORIES.md                                    | USECASES.md           |
| [requirements-feasibility-check](./requirements-feasibility-check/)           | 技術リスクを評価し、PoC 計画を作成                         | USECASES.md                                        | FEASIBILITY.md        |
| [requirements-ddd-modeling](./requirements-ddd-modeling/)                     | ドメインエキスパートと対話し、用語集とドメインモデルを作成 | USECASES.md, FEASIBILITY.md, USER_STORIES.md       | GLOSSARY.md, MODEL.md |
| [requirements-analyzing-requirements](./requirements-analyzing-requirements/) | 技術設計書を作成 (概要 + 詳細の 2 ファイル)                | USECASES.md, FEASIBILITY.md, GLOSSARY.md, MODEL.md | DESIGN.md, DESIGN_DETAIL.md |
| [requirements-interview](./requirements-interview/)                           | DESIGN.md / DESIGN_DETAIL.md を深掘りして射程に応じ追記    | DESIGN.md, DESIGN_DETAIL.md                        | DESIGN.md, DESIGN_DETAIL.md (更新) |

### 実装フェーズ

| スキル                                                            | 説明                                                                             | 入力                              | 出力           |
| ----------------------------------------------------------------- | -------------------------------------------------------------------------------- | --------------------------------- | -------------- |
| [implementation-planning-tasks](./implementation-planning-tasks/) | 詳細設計書から TDD 準拠のタスクリストを作成 (DESIGN_DETAIL.md 不在時は対話的に DESIGN.md から抽出フォールバック) | DESIGN_DETAIL.md (+ DESIGN.md)    | TODO.md        |
| [implementation-developing](./implementation-developing/)         | TDD (RED→GREEN→REFACTOR) でフェーズ単位の実装。docs/TODO.md があるとフェーズ管理 | TODO.md                           | コード         |
| [implementation-writing-tests](./implementation-writing-tests/)   | テストコードを作成 (Go/Rust/React+TS の references あり)                         | -                                 | テストファイル |

### ワークフロースキル

`workflow-*` は対話的オーケストレーター / エントリポイントで、必要に応じて他スキルを内部で呼ぶ。

| スキル                                                  | 説明                                                                                                                                   |
| ------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| [workflow-spec](./workflow-spec/)                       | DESIGN.md (概要) + DESIGN_DETAIL.md (詳細) + TODO.md を対話的に生成 (analyzing-requirements + interview + planning-tasks 統合)、完了後 autopilot / developing / 終了を選択 |
| [workflow-autopilot](./workflow-autopilot/)             | TODO.md 全フェーズを自律実装。各フェーズで developing → architecture-guard (3回まで自動修正) → fix-lsp-warnings (Lua/Neovim 専用) → review (3回まで self-fix) → commit。設計乖離は P1/P2 で動的修正、P3 で停止 |
| [workflow-review](./workflow-review/)                   | git 差分を 5 観点でコードレビュー (TDD・品質・セキュリティ・アーキテクチャ・ルール)                                                    |
| [workflow-commit](./workflow-commit/)                   | Conventional Commit 形式でコミット (push はユーザが手動)                                                                               |
| [workflow-create-draft-pr](./workflow-create-draft-pr/) | ローカルのコミット履歴と差分から Draft PR を作成 (`.github/` のテンプレートを自動検出、無ければ本文を生成)                             |
| [workflow-debate](./workflow-debate/)                   | 複数サブエージェントで議論を反復し、相違が収束するまで議題を検証                                                                       |

### プロダクト生成スキル

| スキル                                    | 説明                                                                                                                      |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| [demo-site-builder](./demo-site-builder/) | React 19 + Vite + TS + Tailwind v4 + React Router v7 でモバイル向け静的 SPA デモを TDD 構築 → Cloudflare Workers デプロイ |
| [slide-generating](./slide-generating/)   | テキスト入力から Web ベース (HTML + Tailwind + JS) のプレゼンスライドを生成                                               |

### React/Vercel ベストプラクティス

外部プラグイン由来のリファレンススキル。

| スキル                                                        | 説明                                                                 |
| ------------------------------------------------------------- | -------------------------------------------------------------------- |
| [vercel-react-best-practices](./vercel-react-best-practices/) | Vercel Engineering の React/Next.js パフォーマンス最適化ガイドライン |
| [vercel-composition-patterns](./vercel-composition-patterns/) | スケールする React composition パターン (compound/render props 等)   |

### ユーティリティ

| スキル                                                  | 説明                                               |
| ------------------------------------------------------- | -------------------------------------------------- |
| [utility-codex](./utility-codex/)                       | Codex CLI でセカンドオピニオン取得                 |
| [utility-create-skill](./utility-create-skill/)         | スキル作成 + レビュー・自動修正                    |
| [utility-creating-rules](./utility-creating-rules/)     | .claude/rules/ にルールファイルを作成              |
| [utility-drawio](./utility-drawio/)                     | draw.io 図 (.drawio) の生成と PNG/SVG/PDF 書き出し |
| [utility-fix-lsp-warnings](./utility-fix-lsp-warnings/) | LSP 警告を検出・修正                               |
| [utility-reviewing-skills](./utility-reviewing-skills/) | スキルをベストプラクティスに基づいてレビュー       |

## 使い方

各スキルは `/スキル名` で起動できる。

```
/requirements-user-story        # ユーザーストーリー作成
/workflow-spec                  # 設計書 + タスクリスト生成 → 実装方式選択 (autopilot/developing/手動)
/workflow-autopilot             # TODO.md 全フェーズを自律実装 (設計+TODO 済前提)
/implementation-developing      # TDD 実装 (TODO.md があるとフェーズ管理)
/workflow-review                # コードレビュー
/workflow-commit                # コミット (push は手動)
/workflow-create-draft-pr       # Draft PR を作成 (テンプレ自動検出)
/workflow-debate                # 複数視点で議論して結論を得る
/utility-codex                  # Codex CLI に単体で相談
```

## フェーズスキル

開発フローのフェーズ全体を実行するオーケストレータースキル：

| スキル           | フェーズ           | 実行スキル                                                                                                                                                                             | 主要出力                          |
| ---------------- | ------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------- |
| `/requirements`  | 要件・設計         | requirements-user-story → requirements-ui-sketch → requirements-usecase-description → requirements-feasibility-check → requirements-ddd-modeling → requirements-analyzing-requirements | DESIGN.md + DESIGN_DETAIL.md      |
| `/workflow-spec` | 設計 + 計画 + 実装 | requirements-analyzing-requirements → requirements-interview → implementation-planning-tasks → (autopilot or developing 選択)                                                          | DESIGN.md + DESIGN_DETAIL.md + TODO.md |
| `/workflow-autopilot` | TODO 全フェーズ自律実装 | implementation-developing → architecture-guard → utility-fix-lsp-warnings (Lua/Neovim) → workflow-review → workflow-commit (フェーズ毎ループ)                              | 各フェーズのコミット              |

各スキル完了後に確認が入り、途中で終了することも可能。
既存ドキュメントがある場合は、スキップして途中から開始できる。

## 補足

- **必ずしも全スキルを使う必要はない** — プロジェクトの規模や状況に応じてスキップ可能
- **feasibility-check は技術リスクがある場合** — 不確実性が高い技術を使う場合に実施
- **各スキルはセルフレビュー機能を持つ** — 生成したドキュメントを自動でレビュー・修正
