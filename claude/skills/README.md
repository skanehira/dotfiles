# Claude Code Skills

プロダクト開発を支援する Claude Code スキル集。

## タスク規模別の入口 (まずここを見る)

開発タスクは規模で入口を使い分ける。**入口はタスクの規模に対して 1 つに決まる**。

| 規模 | 入口 | 中身 |
|---|---|---|
| **L: 新規プロダクト・大きい機能** | `/dev-spec` → (承認ゲート) → `/dev-impl` | 設計ループ (要件〜PoC 検証〜設計書〜TODO) → 実装ループ (全フェーズ自律実装) |
| **M: 1 機能・リファクタ** | plan mode → そのまま実装 | スキル不要。メインループ直営 TDD (順序は tdd-guard hook が強制) |
| **S: バグ修正・typo** | 直接依頼 | スキル不要。tdd-guard + remind-rules hook が既定の品質を守る |

横断ユーティリティ: `/workflow-review` (手動レビュー) / `/workflow-commit` (コミット) / `/workflow-debate` (壁打ち) / `/workflow-create-draft-pr` (PR 作成)。

```
┌────────────────────────────────────────────────────────────────┐
│  /dev-spec — 設計ループ (賢いモデルのセッションで起動)          │
│                                                                │
│  1 user-story → 2 ui-sketch → 3 usecase → 4 feasibility        │
│      → 5 ★PoC 検証 (tech-investigation 並列 fan-out)           │
│      → 6 ddd-modeling → 7 DESIGN/DETAIL 生成 → 8 interview     │
│      → 9 検証手順補完 → 10 TODO 生成 → 11 ★承認ゲート          │
│                                                                │
│  Feedback: 設計 = 人間承認 / 技術実現性 = PoC 実行結果         │
│  クイックモード: 7〜11 のみ (不確実性があれば 4〜5 を通す)     │
└──────────────────────────┬─────────────────────────────────────┘
                           │ 承認ゲート = 人間が /dev-impl を起動
                           │ (Claude は自律的に越えられない)
┌──────────────────────────▼─────────────────────────────────────┐
│  /dev-impl — 実装ループ (model: sonnet、直接起動で切り替わる)  │
│                                                                │
│  POC_NEEDED 残存ガード → 各フェーズ:                           │
│    メインループで TDD 実装 → architecture-guard →              │
│    review-* 並列 (model: opus) → テストゲート → commit         │
│  → ゴール達成判定 → HTML レポート                              │
│                                                                │
│  エスカレ (P3 等) でのみ停止。再開は /dev-impl 再実行          │
└────────────────────────────────────────────────────────────────┘
```

## ディレクトリ構成

```
skills/
├── dev-spec/                  # 設計ループ (フェーズ手順は references/)
├── dev-impl/                  # 実装ループ (旧 workflow-autopilot)
├── workflow-commit/
├── workflow-create-draft-pr/
├── workflow-debate/
├── workflow-review/
├── demo-site-builder/
├── saas-pricing-design/
├── utility-*/                 # 単発ユーティリティ群
└── README.md
```

> **命名規則**: Claude Code はディレクトリ名をスキル識別子として使用するため、フラット構造。
>
> - `dev-*` — 開発フローの 2 大ループ (設計 / 実装)
> - `workflow-*` — 横断ユーティリティ (レビュー / コミット / PR / 壁打ち)
> - `utility-*` — 単発のユーティリティ

## モデル方針 (ループエンジニアリング)

原則: **実行器のモデル ≤ 検証器のモデル**。モデルの賢さは検証器の薄いところに配置する。

| 対象 | モデル | 理由 |
|---|---|---|
| dev-spec (設計ループ) | セッション継承 (Fable / Opus 推奨) | 検証器が人間しかいないため、生成側を賢くする |
| dev-impl (実装ループ) | `model: sonnet` (frontmatter) | tdd-guard・テストゲート・レビュー fan-out という検証器が厚いため actor は下げられる |
| review-* subagent | `model: opus` (呼び出し時明示) | 検証器は実行器より賢く保つ |

制約: skill frontmatter の `model` は**ユーザーが直接起動したターンだけ**有効 (Skill ツール経由では無視される、実測済み)。このため dev-spec → dev-impl の遷移は必ず人間が `/dev-impl` をタイプする。これは承認ゲートを構造的に強制する仕掛けでもある。

## skill と agent の責務分担

「**skill = ユーザー向けエントリ + 表示整形 / agent = 実体ロジック (subagent 化前提)**」のパターンを推奨する。新規実装はこの形に揃える。

|  | skill (`claude/skills/<name>/SKILL.md`) | agent (`claude/agents/<name>.md`) |
|---|---|---|
| 用途 | ユーザー向けエントリポイント (`/<name>` で起動) | 内部 subagent (Agent ツールから起動) |
| 役割 | 薄い orchestrator + 表示整形 + 確認ダイアログ | 実体ロジック、構造化 JSON 返却 |
| コンテキスト | メインセッションと共有 | 別セッション (分離、トークン効率) |
| 並列化 | 単発 | 同一メッセージ内の複数 Agent tool_use で並列起動可 |
| hook 適用 | parent の Stop/PostToolUse/UserPromptSubmit | parent の hooks は継承されない |

subagent への委譲は「並列化」と「親コンテキストの保護 (巨大出力の隔離)」のためだけに行う。逐次依存する実装・修正・コミットは**メインループ直営** (CLAUDE.md「サブエージェントの使い方」)。

### skill = agent の wrapper の例

| skill (wrapper) | agent (本体) |
|---|---|
| `/utility-self-improving` | `self-improving-extractor` + `self-improving-judge` |
| `/workflow-review` | `review-tdd` + `review-quality` + `review-product-readiness` (3 並列。セキュリティは security-guidance プラグインに委譲) |

### agent only (skill 無し、上位 orchestrator 専用)

| agent | 呼び出し元 |
|---|---|
| `tech-investigation` | `dev-spec` フェーズ 5 (PoC 検証、並列 fan-out) |
| `architecture-guard` | `dev-impl` Step 4.2b |
| `fix-lsp-warnings` | `dev-impl` Step 4.2c / Agent ツールで直接起動 |
| `review-*` | `dev-impl` Step 4.2d (model: opus 明示) / `workflow-review` |

## スキル一覧

### 開発フロー

| スキル | 説明 | 入力 | 出力 |
|---|---|---|---|
| [dev-spec](./dev-spec/) | 設計ループ。ユーザーストーリー〜PoC 検証〜設計書〜TODO 生成を対話実行し、承認ゲートで実装ループへ引き渡す。クイックモード・部分実行・途中再開可 | なし (docs/ の状態から再開可) | USER_STORIES.md 〜 DESIGN.md + DESIGN_DETAIL.md + TODO.md |
| [dev-impl](./dev-impl/) | 実装ループ。TODO.md 全フェーズを自律実装 (メインループ TDD → guard → review fan-out → テストゲート → commit)、ゴール達成判定、HTML レポート。P1/P2 は動的修正、P3 で停止 | DESIGN.md + DESIGN_DETAIL.md + TODO.md (必須) | 各フェーズのコミット + `docs/dev-impl-reports/<run_id>.html` |

dev-spec の各フェーズ手順書は [dev-spec/references/](./dev-spec/references/) にある (user-story / ui-sketch / usecase-description / feasibility-check / **poc-verification** / ddd-modeling / analyzing-requirements / interview / verification-review / todo-generation)。

### 横断ユーティリティ

| スキル | 説明 |
|---|---|
| [workflow-review](./workflow-review/) | git 差分を 3 観点でレビュー (TDD・品質+ルール+構造・プロダクト readiness)。修正はメインループ直営 TDD |
| [workflow-commit](./workflow-commit/) | Conventional Commit 形式でコミット (push はユーザが手動) |
| [workflow-create-draft-pr](./workflow-create-draft-pr/) | ローカルのコミット履歴と差分から Draft PR を作成 (`.github/` のテンプレート自動検出) |
| [workflow-debate](./workflow-debate/) | 複数サブエージェントで議論を反復し、相違が収束するまで議題を検証 |

### プロダクト生成

| スキル | 説明 |
|---|---|
| [demo-site-builder](./demo-site-builder/) | React 19 + Vite + TS + Tailwind v4 でモバイル向け静的 SPA デモを TDD 構築 → Cloudflare Workers デプロイ |
| [saas-pricing-design](./saas-pricing-design/) | SaaS の料金プランをコスト構造から逆算して設計 (Numbers 互換 Excel 生成 + 実機検証) |

### ユーティリティ

| スキル | 説明 |
|---|---|
| [utility-create-skill](./utility-create-skill/) | スキル作成 + レビュー・自動修正 |
| [utility-creating-rules](./utility-creating-rules/) | .claude/rules/ にルールファイルを作成 |
| [utility-drawio](./utility-drawio/) | draw.io 図 (.drawio) の生成と PNG/SVG/PDF 書き出し |
| [utility-reviewing-skills](./utility-reviewing-skills/) | スキルをベストプラクティスに基づいてレビュー |
| [utility-self-improving](./utility-self-improving/) | 過去セッション履歴から繰り返し指摘を抽出し設定を改善 |
| [utility-doc-reading](./utility-doc-reading/) | 知識プロファイルを参照しながらドキュメント読解を支援 |
| [utility-pdf-compress](./utility-pdf-compress/) | PDF のロスレス圧縮 |

## 補足

- **必ずしも全フェーズを使う必要はない** — dev-spec はクイックモード・部分実行・途中再開に対応
- **PoC 検証は blocker=true がある場合のみ発火** — 技術的不確実性が無ければ自動スキップ
- **各スキルはセルフレビュー機能を持つ** — 生成したドキュメントを自動でレビュー・修正
