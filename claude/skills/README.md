# Claude Code Skills

プロダクト開発を支援する Claude Code スキル集。

## タスク規模別の入口 (まずここを見る)

開発タスクは規模で入口を使い分ける。**入口はタスクの規模に対して 1 つに決まる**。

| 規模 | 入口 | 中身 |
|---|---|---|
| **L: 新規プロダクト・大きい機能** | `/dev-spec` (`cli`/`webapp` 指定可) → (承認ゲート) → `/dev-impl` | 設計ループ (要件〜PoC 検証〜設計書〜TODO) → 実装ループ (全フェーズ自律実装)。プロダクトモード (cli/webapp) は省略時タスク説明から推論。Cloudflare フルスタック (D1 + Hono) の新規立ち上げは先に `/fullstack-app-builder` で scaffold + 環境構築してから `/dev-spec` に入る |
| **M: 1 機能・リファクタの一括委任 (docs 不要)** | `/dev-impl-quick` | 軽量実装ループ。タスク分解 → 直営 TDD → テストゲート → review-tdd (単一観点) → タスク単位コミット。複数観点レビュー fan-out・ログ・レポートは持たない |
| **M: 単発の機能追加・リファクタ (対話しながら)** | plan mode → そのまま実装 | スキル不要。メインループ直営 TDD。まとまったテスト差分を書いたら完了前に `review-tdd` を自分で起動する |
| **S: バグ修正・typo** | 直接依頼 | スキル不要。remind-rules hook が既定の品質を守る |

横断ユーティリティ: `/workflow-review` (手動レビュー) / `/workflow-commit` (コミット) / `/workflow-debate` (壁打ち) / `/workflow-create-draft-pr` (PR 作成)。

```
┌────────────────────────────────────────────────────────────────┐
│  /dev-spec — 設計ループ (賢いモデルのセッションで起動)          │
│                                                                │
│  1 user-story → 2 ui-sketch (webapp のみ) → 3 usecase          │
│      → 4 feasibility → 5 ★PoC 検証 (tech-investigation 並列)  │
│      → 6 ddd-modeling → 7 DESIGN/DETAIL 生成 → 8 interview     │
│      → 9 検証手順補完 → 10 TODO 生成 → 11 ★承認ゲート          │
│                                                                │
│  Feedback: 設計 = 人間承認 / 技術実現性 = PoC 実行結果         │
│  クイックモード: 7〜11 のみ (不確実性があれば 4〜5 を通す)     │
│  プロダクトモード: cli は 2 ui-sketch をスキップし CLI I/F     │
│  仕様をフェーズ 7 内で設計 (DESIGN.md にスタンプで記録)        │
└──────────────────────────┬─────────────────────────────────────┘
                           │ 承認ゲート = 人間が /dev-impl を起動
                           │ (Claude は自律的に越えられない)
┌──────────────────────────▼─────────────────────────────────────┐
│  /dev-impl — 実装ループ (model: opus、直接起動で切り替わる)    │
│                                                                │
│  POC_NEEDED 残存ガード → TODO.md の deps 宣言で wave 構築 →    │
│  wave サイズ 1: メインループで TDD 実装 →                      │
│    architecture-guard → review-* 並列 (opus) → テスト → commit │
│  wave サイズ 2+: implementer を worktree に fan-out (opus)。   │
│    実装〜レビュー修正まで各自完結 → 親が squash merge →        │
│    全テストゲート → commit (統合はフェーズごとに逐次)          │
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
├── dev-impl-quick/            # 軽量実装ループ (docs 不要)
├── workflow-commit/
├── workflow-create-draft-pr/
├── workflow-debate/
├── workflow-review/
├── demo-site-builder/
├── fullstack-app-builder/     # フルスタック scaffold (手順は references/)
├── saas-pricing-design/
├── utility-*/                 # 単発ユーティリティ群
└── README.md
```

> **命名規則**: Claude Code はディレクトリ名をスキル識別子として使用するため、フラット構造。
>
> - `dev-*` — 開発フローの 2 大ループ (設計 / 実装) + 軽量実装ループ
> - `workflow-*` — 横断ユーティリティ (レビュー / コミット / PR / 壁打ち)
> - `utility-*` — 単発のユーティリティ

## モデル方針 (ループエンジニアリング)

モデル割当の正は **CLAUDE.md「オーケストレーションとモデル階層」** (トリアージ手順・割当マトリクス・Fable → Opus 4.8 フォールバック規定)。ここではスキル側への適用だけを記す。原則: **実行器のモデル ≤ 検証器のモデル**。モデルの賢さは検証器の薄いところに配置する。設計思想の全体像 (7 要素・三大失敗モード) は [rules/core/references/loop-engineering.md](../rules/core/references/loop-engineering.md) を参照。

| 対象 | モデル | 理由 |
|---|---|---|
| dev-spec (設計ループ) | セッション継承 (最上位 tier 推奨) | 検証器が人間しかいないため、生成側を賢くする |
| dev-impl (実装ループ) / dev-impl-quick (軽量実装ループ) | `model: opus` (frontmatter) | 実装の質がそのまま成果物の質になるため実行器を下げない |
| dev-impl の implementer subagent (並列モード) | `model: opus` (呼び出し時明示) | 実行器。worktree 内で TDD 実装からレビュー修正までを担うため、逐次モードの actor と同じ tier に揃える |
| review-tdd / review-quality / review-product-readiness / review-spec-compliance subagent | `model: opus` (frontmatter + 呼び出し時明示) | 検証器は実行器より下げない。frontmatter も opus にして、呼び出し時の明示忘れで無音でセッション継承より下に落ちない防御とする |
| review-adversarial subagent | `model: sonnet` (frontmatter + 呼び出し時明示) | 唯一の例外。同一セッション内の直接比較で opus と sonnet の 1 spawn あたり単価がほぼ同一 ($2.55 / $2.51) だったのに対し、high 検出は sonnet が 6 倍 (0.90 件/spawn vs 0.15 件/spawn) だった。「実際に壊して確かめる」作業様式では、同じ予算でターンを多く回せることが検出力に直結する。**検出力の実測が「実行器 ≤ 検証器」の代理指標に優先する**という判断。high 検出件数が opus 時 (0.29 件/spawn) を下回り続けたら opus に戻す |
| tech-investigation subagent (dev-spec フェーズ 5 の PoC 検証) | `model: opus` (frontmatter + 呼び出し時明示) | 「何をどこまで検証すれば行けると言えるか」を自分で設計する探索的な調査。検証範囲の見落としが設計の前提を誤らせる |
| architecture-guard subagent | `model: haiku` (frontmatter) | レイヤ境界違反の検出は機械的な判定でモデル性能に依存しない |

モデル指定はすべて alias (`opus` / `sonnet` / `haiku`) で書く (固定 ID 禁止。世代交代への自動追従のため)。

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

subagent への委譲は「並列化」と「親コンテキストの保護 (巨大出力の隔離)」のためだけに行う。逐次依存する実装・修正・コミットは**メインループ直営** (CLAUDE.md「委譲の判断」)。dev-impl の並列モードが実装を implementer subagent に出すのはこの原則の例外ではなく「並列化」に当たるケースで、独立フェーズを worktree で分離して同時に進めるためのもの。git index を共有する統合 (merge / コミット) は並列化できないので親に残す。なお subagent の Bash は**呼び出しごとに cwd が親セッションのものへ戻る**ため、worktree で作業させる agent には作業ディレクトリを引数で渡し `git -C <path>` を使わせる (`cd` の状態は次の呼び出しに残らない)。

### skill = agent の wrapper の例

| skill (wrapper) | agent (本体) |
|---|---|
| `/utility-self-improving` | `self-improving-extractor` + `self-improving-judge` |
| `/workflow-review` | `review-tdd` + `review-quality` + `review-product-readiness` + `review-adversarial` (4 並列。セキュリティは security-guidance プラグインに委譲) |

### agent only (skill 無し、上位 orchestrator 専用)

| agent | 呼び出し元 |
|---|---|
| `tech-investigation` | `dev-spec` フェーズ 5 (PoC 検証、並列 fan-out) |
| `architecture-guard` | `dev-impl` Step 4.2b |
| `fix-lsp-warnings` | `dev-impl` Step 4.2c / Agent ツールで直接起動 |
| `review-*` (tdd / quality / product-readiness) | `dev-impl` Step 4.2d (model: opus 明示) / `workflow-review` |
| `review-adversarial` | `dev-impl` Step 4.2d (model: sonnet 明示) / `workflow-review` |
| `review-tdd` (単一観点のみ) | `dev-impl-quick` ステップ 4 (model: opus 明示) |
| `general-purpose` (implementer として) | `dev-impl` Step 4 の並列モード (model: opus 明示、worktree 分離) |

## スキル一覧

### 開発フロー

| スキル | 説明 | 入力 | 出力 |
|---|---|---|---|
| [dev-spec](./dev-spec/) | 設計ループ。ユーザーストーリー〜PoC 検証〜設計書〜TODO 生成を対話実行し、承認ゲートで実装ループへ引き渡す。クイックモード・部分実行・途中再開可。プロダクトモード (`cli`/`webapp`) 指定で CLI ツール開発時は UI スケッチ等を軽量化 | `cli`/`webapp` + タスク説明 (省略時は推論して確認) | USER_STORIES.md 〜 DESIGN.md (product-mode スタンプ付き) + DESIGN_DETAIL_APP.md + DESIGN_DETAIL_INFRA.md + TODO.md |
| [dev-impl](./dev-impl/) | 実装ループ。TODO.md 全フェーズを自律実装 (メインループ TDD → guard → review fan-out (敵対的レビュー含む) → テストゲート → commit)。TODO.md の全フェーズに依存宣言 `<!-- deps: ... -->` があれば並列モードになり、互いに独立なフェーズを worktree 分離した implementer (opus) に同時 fan-out する (最大 3、統合は親が逐次)。完了時に第三者受入監査 (review-spec-compliance がゴール検証を独立再実行 + 成果物↔設計突合)、HTML レポート。P1/P2 は動的修正、P3 で停止 | DESIGN.md + DESIGN_DETAIL_APP.md + DESIGN_DETAIL_INFRA.md + TODO.md (必須、承認スタンプは goals_sha 付き) | 各フェーズのコミット + `docs/dev-impl-reports/<run_id>.html` |
| [dev-impl-quick](./dev-impl-quick/) | 軽量実装ループ。依頼文をタスク分解 → 1 件ずつ直営 TDD → テストゲート → review-tdd (単一観点、model: opus 明示) → タスク単位 commit。複数観点レビュー fan-out・進捗ログ・レポートは持たない | 依頼文または簡易タスクリスト (docs 不要) | タスク単位のコミット |

dev-spec の各フェーズ手順書は [dev-spec/references/](./dev-spec/references/) にある (user-story / ui-sketch / usecase-description / feasibility-check / **poc-verification** / ddd-modeling / analyzing-requirements / interview / verification-review / todo-generation)。

### 横断ユーティリティ

| スキル | 説明 |
|---|---|
| [workflow-review](./workflow-review/) | git 差分を 4 観点でレビュー (TDD・品質+ルール+構造・プロダクト readiness・敵対的レビュー)。修正はメインループ直営 TDD |
| [workflow-commit](./workflow-commit/) | Conventional Commit 形式でコミット (push はユーザが手動) |
| [workflow-create-draft-pr](./workflow-create-draft-pr/) | ローカルのコミット履歴と差分から Draft PR を作成 (`.github/` のテンプレート自動検出) |
| [workflow-debate](./workflow-debate/) | 複数サブエージェントで議論を反復し、相違が収束するまで議題を検証 |

### プロダクト生成

| スキル | 説明 |
|---|---|
| [demo-site-builder](./demo-site-builder/) | React 19 + Vite + TS + Tailwind v4 でモバイル向け静的 SPA デモを TDD 構築 → Cloudflare Workers デプロイ |
| [fullstack-app-builder](./fullstack-app-builder/) | skanehira/fullstack-worker-template (React 19 + Hono + Cloudflare D1/Drizzle + Cognito) から scaffold + ローカル環境構築。Stripe / 認証の要否をヒアリングで取捨し、docs/PRODUCT_SPEC.md 経由で `/dev-spec` → `/dev-impl` へ引き渡す (機能実装は行わない) |
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
| [transcribing-meeting-minutes](./transcribing-meeting-minutes/) | 会議録音をローカル文字起こしし、時刻根拠付きの議事録を作成 |
| [llm-feature-design](./llm-feature-design/) | アプリに組み込む LLM 機能のプロンプトと周辺構造を設計 (回答範囲の制限 / 非信頼テキストと injection 対策 / グラウンディング / ガードレール / 評価)。規範は references/ から遅延参照し、逐語引用と出典は references/evidence.md に分離 |

## 補足

- **必ずしも全フェーズを使う必要はない** — dev-spec はクイックモード・部分実行・途中再開に対応
- **PoC 検証は blocker=true がある場合のみ発火** — 技術的不確実性が無ければ自動スキップ
- **各スキルはセルフレビュー機能を持つ** — 生成したドキュメントを自動でレビュー・修正
