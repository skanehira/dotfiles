# Claude Code Skills

プロダクト開発を支援するClaude Codeスキル集。

## ディレクトリ構成

```
skills/
├── requirements/                       # /requirements オーケストレーター
├── requirements/                       # 要件・設計オーケストレーター (フェーズ手順は references/)
├── implementation-developing/
├── implementation-planning-tasks/
├── workflow-autopilot/                 # 自律実装オーケストレーター
├── workflow-commit/
├── workflow-create-draft-pr/
├── workflow-debate/
├── workflow-review/
├── workflow-spec/
├── demo-site-builder/
├── saas-pricing-design/
├── utility-create-skill/
├── utility-creating-rules/
├── utility-drawio/
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

## skill と agent の責務分担

dotfiles の Claude 設定では「**skill = ユーザー向けエントリ + 表示整形 / agent = 実体ロジック (subagent 化前提)**」のパターンを推奨する。新規実装はこの形に揃える。

|  | skill (`claude/skills/<name>/SKILL.md`) | agent (`claude/agents/<name>.md`) |
|---|---|---|
| 用途 | ユーザー向けエントリポイント (`/<name>` で起動) | 内部 subagent (Agent ツールから起動) |
| 役割 | 薄い orchestrator + 表示整形 + 確認ダイアログ | 実体ロジック、構造化 JSON 返却 |
| コンテキスト | メインセッションと共有 | 別セッション (分離、トークン効率) |
| 並列化 | 単発 | Promise.all で並列起動可 |
| hook 適用 | parent の Stop/PostToolUse/UserPromptSubmit | parent の hooks は継承されない (subagent frontmatter or SubagentStop hook で別途定義) |

### パターン: skill = agent の wrapper

メンテナンス重複を避けるため、本体ロジックは agent 側に置き、skill は agent を起動して結果を整形表示する薄い層にする。

既存例:

| skill (wrapper) | agent (本体) |
|---|---|
| `/utility-self-improving` | `self-improving-extractor` + `self-improving-judge` |
| `/implementation-developing` | `implementation-developing-agent` |
| `/workflow-review` | `review-tdd` + `review-quality` + `review-product-readiness` (3 並列。quality は rules 準拠 + アーキテクチャ heuristic を統合。セキュリティは security-guidance プラグインに委譲) |

agent only (skill 無し、上位 orchestrator 専用):

| agent | 呼び出し元 |
|---|---|
| `architecture-guard` | `workflow-autopilot` Step 4.3 |
| `tech-investigation` | `workflow-autopilot` Step 1.5 |
| `fix-lsp-warnings` | `workflow-autopilot` (Lua/Neovim フェーズ) / Agent ツールで直接起動 |

### autopilot から呼ぶ場合の経路

`workflow-autopilot` は autopilot 自身が orchestration するため、wrapper skill を経由するか直接 agent を呼ぶかをケース別に選ぶ:

- **直接 agent** (最短経路、コンテキスト分離最大): `implementation-developing-agent` / `architecture-guard` / `tech-investigation` を直接 Agent ツールで起動
- **skill 経由** (ロジック一元化を優先): `workflow-review` skill → 内部で 5 review subagent 並列。autopilot は集約結果を受け取って fatal 判定のみ

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
│ 10. review                3 観点レビュー (autopilot はループ内蔵)        │
│           ↓                                                              │
│ 11. commit                Conventional Commit でコミット                 │
└──────────────────────────────────────────────────────────────────────────┘
```

## スキル一覧

### 要件・設計フェーズ

`/requirements` スキルに統合済み。各フェーズの手順書は `requirements/references/` にあり、オーケストレーターが順次 Read して実行する (部分実行も可)。

| フェーズ手順 (references/)                                                     | 説明                                                       | 入力                                               | 出力                  |
| ----------------------------------------------------------------------------- | ---------------------------------------------------------- | -------------------------------------------------- | --------------------- |
| [user-story](./requirements/references/user-story.md)                         | ユーザーストーリーを作成し、MoSCoW/ICE で優先順位付け      | -                                                  | USER_STORIES.md       |
| [ui-sketch](./requirements/references/ui-sketch.md)                           | 画面構成、ユーザーフロー、ASCII ワイヤーフレームを作成     | USER_STORIES.md                                    | UI_SKETCH.md          |
| [usecase-description](./requirements/references/usecase-description.md)       | 正常系・異常系・代替フロー、ビジネスルールを詳細化         | USER_STORIES.md                                    | USECASES.md           |
| [feasibility-check](./requirements/references/feasibility-check.md)           | 技術リスクを評価し、PoC 計画を作成 (POC_NEEDED マーカー形式、autopilot 自動 PoC 連携) | USECASES.md                                        | FEASIBILITY.md        |
| [ddd-modeling](./requirements/references/ddd-modeling.md)                     | ドメインエキスパートと対話し、用語集とドメインモデルを作成 | USECASES.md, FEASIBILITY.md, USER_STORIES.md       | GLOSSARY.md, MODEL.md |
| [analyzing-requirements](./requirements/references/analyzing-requirements.md) | 技術設計書を作成 (概要 + 詳細の 2 ファイル、ゴールは G1/G2... 標準形式、POC_NEEDED マーカーを DESIGN_DETAIL.md に転記) | USECASES.md, FEASIBILITY.md, GLOSSARY.md, MODEL.md | DESIGN.md, DESIGN_DETAIL.md |
| [interview](./requirements/references/interview.md)                           | DESIGN.md / DESIGN_DETAIL.md を深掘りして射程に応じ追記    | DESIGN.md, DESIGN_DETAIL.md                        | DESIGN.md, DESIGN_DETAIL.md (更新) |

### 実装フェーズ

| スキル                                                            | 説明                                                                             | 入力                              | 出力           |
| ----------------------------------------------------------------- | -------------------------------------------------------------------------------- | --------------------------------- | -------------- |
| [implementation-planning-tasks](./implementation-planning-tasks/) | 詳細設計書から TDD 準拠のタスクリストを作成 (DESIGN_DETAIL.md 不在時は対話的に DESIGN.md から抽出フォールバック) | DESIGN_DETAIL.md (+ DESIGN.md)    | TODO.md        |
| [implementation-developing](./implementation-developing/)         | TDD (RED→GREEN→REFACTOR) でフェーズ単位の実装。docs/TODO.md があるとフェーズ管理 | TODO.md                           | コード         |

### ワークフロースキル

`workflow-*` は対話的オーケストレーター / エントリポイントで、必要に応じて他スキルを内部で呼ぶ。

| スキル                                                  | 説明                                                                                                                                   |
| ------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| [workflow-spec](./workflow-spec/)                       | DESIGN.md (概要) + DESIGN_DETAIL.md (詳細) + TODO.md を対話的に生成 (analyzing-requirements + interview + planning-tasks 統合)、完了後 autopilot / developing / 終了を選択 |
| [workflow-autopilot](./workflow-autopilot/)             | TODO.md 全フェーズを自律実装。起動時に POC_NEEDED マーカーを tech-investigation subagent で自動 PoC 解決 (Step 1.5)、各フェーズで PHASE_CONTEXT を組み立てて implementation-developing-agent subagent (TDD) → architecture-guard subagent (3回まで自動修正) → fix-lsp-warnings (Lua/Neovim 専用) → 3 観点 review subagent 並列 (tdd/quality/product-readiness、3回まで self-fix、fix 後は全観点を再レビュー) → テストゲート → commit、最後に DESIGN.md ゴール達成判定 (Step 5、未達は最大2周回ループ)。セキュリティは security-guidance プラグインに委譲。subagent の TDD 違反は SubagentStop hook で機械チェック。設計乖離は P1/P2 で動的修正、P3 で停止。意思決定経緯は構造化 JSONL + HTML レポート (`docs/autopilot-reports/<run_id>.html`) |
| [workflow-review](./workflow-review/)                   | git 差分を 3 観点でコードレビュー (TDD・品質+ルール+構造・プロダクト readiness、セキュリティは security-guidance プラグインに委譲)                                                    |
| [workflow-commit](./workflow-commit/)                   | Conventional Commit 形式でコミット (push はユーザが手動)                                                                               |
| [workflow-create-draft-pr](./workflow-create-draft-pr/) | ローカルのコミット履歴と差分から Draft PR を作成 (`.github/` のテンプレートを自動検出、無ければ本文を生成)                             |
| [workflow-debate](./workflow-debate/)                   | 複数サブエージェントで議論を反復し、相違が収束するまで議題を検証                                                                       |

### プロダクト生成スキル

| スキル                                    | 説明                                                                                                                      |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| [demo-site-builder](./demo-site-builder/) | React 19 + Vite + TS + Tailwind v4 + React Router v7 でモバイル向け静的 SPA デモを TDD 構築 → Cloudflare Workers デプロイ |
| [saas-pricing-design](./saas-pricing-design/) | SaaS の料金プランをコスト構造から逆算して設計 (Cloudflare 既定コストモデル → 固定/従量の料金体系 → Numbers 互換の Excel 生成 → 実機検証) |

### ユーティリティ

| スキル                                                  | 説明                                               |
| ------------------------------------------------------- | -------------------------------------------------- |
| [utility-create-skill](./utility-create-skill/)         | スキル作成 + レビュー・自動修正                    |
| [utility-creating-rules](./utility-creating-rules/)     | .claude/rules/ にルールファイルを作成              |
| [utility-drawio](./utility-drawio/)                     | draw.io 図 (.drawio) の生成と PNG/SVG/PDF 書き出し |
| [utility-reviewing-skills](./utility-reviewing-skills/) | スキルをベストプラクティスに基づいてレビュー       |

## 使い方

各スキルは `/スキル名` で起動できる。

```
/requirements                   # 要件・設計フェーズ (部分実行可)
/workflow-spec                  # 設計書 + タスクリスト生成 → 実装方式選択 (autopilot/developing/手動)
/workflow-autopilot             # TODO.md 全フェーズを自律実装 (設計+TODO 済前提)
/implementation-developing      # TDD 実装 (TODO.md があるとフェーズ管理)
/workflow-review                # コードレビュー
/workflow-commit                # コミット (push は手動)
/workflow-create-draft-pr       # Draft PR を作成 (テンプレ自動検出)
/workflow-debate                # 複数視点で議論して結論を得る
```

## フェーズスキル

開発フローのフェーズ全体を実行するオーケストレータースキル：

| スキル           | フェーズ           | 実行スキル                                                                                                                                                                             | 主要出力                          |
| ---------------- | ------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------- |
| `/requirements`  | 要件・設計         | references/ の user-story → ui-sketch → usecase-description → feasibility-check → ddd-modeling → analyzing-requirements (+interview) を順次実行 | DESIGN.md + DESIGN_DETAIL.md      |
| `/workflow-spec` | 設計 + 計画 + 実装 | requirements の references (analyzing-requirements → interview) → implementation-planning-tasks → (autopilot or developing 選択)                | DESIGN.md + DESIGN_DETAIL.md + TODO.md |
| `/workflow-autopilot` | TODO 全フェーズ自律実装 + ゴール達成判定 | (Step 1.5) tech-investigation で POC_NEEDED 自動 PoC → (Step 4 ループ) PHASE_CONTEXT 組み立て → implementation-developing-agent (subagent) → architecture-guard (subagent) → fix-lsp-warnings (agent, Lua/Neovim) → 3 観点 review-* subagent 並列 → workflow-commit → (Step 5) ゴール達成判定 + 未達対応ループ → (Step 7) HTML レポート | 各フェーズのコミット + `docs/autopilot-reports/<run_id>.html` |

各スキル完了後に確認が入り、途中で終了することも可能。
既存ドキュメントがある場合は、スキップして途中から開始できる。

## 補足

- **必ずしも全スキルを使う必要はない** — プロジェクトの規模や状況に応じてスキップ可能
- **feasibility-check は技術リスクがある場合** — 不確実性が高い技術を使う場合に実施
- **各スキルはセルフレビュー機能を持つ** — 生成したドキュメントを自動でレビュー・修正
