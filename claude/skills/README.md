# Claude Code Skills

プロダクト開発を支援する Claude Code スキル集。

## タスク規模別の入口 (まずここを見る)

開発タスクは規模で入口を使い分ける。**入口はタスクの規模に対して 1 つに決まる**。

| 規模 | 入口 | 中身 |
|---|---|---|
| **L: 新規プロダクト・大きい機能** | `/dev-spec` (`cli`/`webapp` 指定可) → 人間が issue を確認 → `/dev-impl` | 設計ループ (要件〜PoC 検証〜DESIGN.md + docs/features/〜issue 生成) → 実装ループ (issue を依存順に 1 件ずつ自律実装)。issue は親 1 件 (トラッキング) + 子 N 件で、親を見れば UC 単位の進捗を俯瞰できる。Cloudflare フルスタック (D1 + Hono) の新規立ち上げは先に `/fullstack-app-builder` で scaffold + 環境構築してから `/dev-spec` に入る |
| **M: 1 機能・リファクタの一括委任 (docs 不要)** | `/dev-impl-quick` | 軽量実装ループ。タスク分解 → 直営 TDD → テストゲート → review-impl (focus: tests) → タスク単位コミット |
| **M: 単発の機能追加・リファクタ (対話しながら)** | plan mode → そのまま実装 | スキル不要。メインループ直営 TDD。まとまったテスト差分を書いたら完了前に `review-impl` を自分で起動する |
| **S: バグ修正・typo** | 直接依頼 | スキル不要。remind-rules hook が既定の品質を守る |

横断ユーティリティ: `/workflow-review` (手動レビュー) / `/workflow-commit` (コミット) / `/workflow-debate` (壁打ち) / `/workflow-create-draft-pr` (PR 作成) / `/workflow-design-notes` (設計の壁打ち台帳 → dev-spec 互換 docs へ落とし込み)。

```
┌────────────────────────────────────────────────────────────────┐
│  /dev-spec — 設計ループ (賢いモデルのセッションで起動)         │
│                                                                │
│  1 user-story → 2 ui-sketch (webapp のみ) → 3 usecase          │
│      → 4 feasibility → 5 ★PoC 検証 (tech-investigation 並列)   │
│      → 6 DESIGN.md (横断 1 枚) → 7 docs/features/ (機能設計)   │
│      → 8 ★設計チェック (fresh context の突合)                  │
│      → 9 issue ドラフト + ★ドラフト一括チェック                │
│      → 10 GitHub issue 生成 (親 1 + 子 N、sub-issue 紐付け)    │
│                                                                │
│  設計の正本は docs 側。issue は参照のみ (転記・同期なし)       │
│  決めが要る点はフェーズ 6・7 の中でその場で質問する            │
│  クイックモード: 6〜10 のみ (不確実性があれば 4〜5 を通す)     │
└──────────────────────────┬─────────────────────────────────────┘
                           │ 人間が issue をざっと読んで GO
                           │ (= /dev-impl を起動。自動遷移しない)
┌──────────────────────────▼─────────────────────────────────────┐
│  /dev-impl — 実装ループ (model: opus、直接起動で切り替わる)    │
│                                                                │
│  POC_NEEDED 残存ガード → ready issue を Depends on 順に:       │
│    in-progress → implementer subagent (issue と docs を直読、  │
│    TDD。UI は Playwright E2E も書く) →                         │
│    review-impl 1 本 (テスト品質/設計準拠/コード品質/E2E) →     │
│    high/medium は fix (最大 2 ラウンド固定) →                  │
│    commit → PR → DoD ローカル実行 green → merge → close        │
│  詰まったら needs-human + コメントで駐車して次の issue へ      │
│  進捗は issue コメントのみ。2 ラウンド後の未解消 medium は     │
│  チェックリスト HTML に集約し、run 終了時に確認を促す          │
│                                                                │
│  停止は「残り全 issue がブロック」or「契約レベルの乖離」のみ   │
└────────────────────────────────────────────────────────────────┘
```

## ディレクトリ構成

```
skills/
├── dev-spec/                  # 設計ループ (フェーズ手順は references/)
├── dev-impl/                  # 実装ループ (GitHub issue 駆動・逐次)
├── dev-impl-quick/            # 軽量実装ループ (docs 不要)
├── workflow-commit/
├── workflow-create-draft-pr/
├── workflow-debate/
├── workflow-design-notes/
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

モデル割当の正は **`rules/core/orchestration.md`** (トリアージ手順・割当マトリクス・alias フォールバック規定)。ここではスキル側への適用だけを記す。原則: **実行器のモデル ≤ 検証器のモデル**。設計思想の全体像 (7 要素・三大失敗モード) は [rules/core/references/loop-engineering.md](../rules/core/references/loop-engineering.md) を参照。

| 対象 | モデル | 理由 |
|---|---|---|
| dev-spec (設計ループ) | セッション継承 (最上位 tier 推奨) | 検証器が人間しかいないため、生成側を賢くする |
| dev-spec フェーズ 8・9 のチェック subagent (general-purpose) | `model: opus` (呼び出し時明示) | 検証器は実行器より下げない |
| dev-impl / dev-impl-quick | `model: opus` (frontmatter) | 実装の質がそのまま成果物の質になるため実行器を下げない |
| dev-impl-implementer subagent | `model: opus` (frontmatter + 呼び出し時明示) | 実行器。`agent-spawn-guard` hook が呼び出し時の model 未指定を deny する |
| review-impl subagent (統合レビュワー) | `model: opus` (frontmatter + 呼び出し時明示) | 検証器は実行器より下げない。呼び出し時の明示忘れは `agent-spawn-guard` hook が deny する (model 未指定は frontmatter ではなく親のセッションモデルを継承するため、frontmatter は防御にならない) |
| tech-investigation subagent (dev-spec フェーズ 5) | `model: opus` (frontmatter + 呼び出し時明示) | 「何をどこまで検証すれば行けると言えるか」を自分で設計する探索的な調査 |
| コミット実行・巨大出力のテスト実行 | `model: haiku` (subagent) | 機械実行。`rules/core/orchestration.md`「委譲の判断」 |

モデル指定はすべて alias (`opus` / `sonnet` / `haiku`) で書く (固定 ID 禁止。世代交代への自動追従のため)。

制約: skill frontmatter の `model` は**ユーザーが直接起動したターンだけ**有効 (Skill ツール経由では無視される、実測済み)。このため dev-spec → dev-impl の遷移は必ず人間が `/dev-impl` をタイプする。これは「人間が issue を確認してから実装に入る」ゲートを構造的に強制する仕掛けでもある。

## skill と agent の責務分担

「**skill = ユーザー向けエントリ + 表示整形 / agent = 実体ロジック (subagent 化前提)**」のパターンを推奨する。新規実装はこの形に揃える。

|  | skill (`claude/skills/<name>/SKILL.md`) | agent (`claude/agents/<name>.md`) |
|---|---|---|
| 用途 | ユーザー向けエントリポイント (`/<name>` で起動) | 内部 subagent (Agent ツールから起動) |
| 役割 | 薄い orchestrator + 表示整形 + 確認ダイアログ | 実体ロジック、構造化 JSON 返却 |
| コンテキスト | メインセッションと共有 | 別セッション (分離、トークン効率) |
| 並列化 | 単発 | 同一メッセージ内の複数 Agent tool_use で並列起動可 |
| hook 適用 | parent の Stop/PostToolUse/UserPromptSubmit | parent の hooks は継承されない |

subagent への委譲は「並列化」と「親コンテキストの保護 (巨大出力の隔離)」と「fresh context の独立性 (実装者と別コンテキストのレビュー)」のために行う。逐次依存する修正・コミットは**メインループ直営** (`rules/core/orchestration.md`「委譲の判断」)。

**dev-impl の実装だけがこの原則の明示的な例外**で、issue 1 件ずつの逐次実装であっても `dev-impl-implementer` subagent に出す。issue が自己完結しているため親による文脈編纂が不要で、issue ごとに fresh context で始まることで長い run でもメインループのコンテキストが単調増加しない。前提は **implementer が葉である** (子 subagent を起動しない) こと — 葉性は `agents/dev-impl-implementer.md` の `tools` から `Agent` を除いて構造的に強制する (subagent には親の hooks が届かず、指示文では違反を検出できないため)。

git index を共有する操作 (コミット) は並列化できないので親に残す。なお subagent の Bash は**呼び出しごとに cwd が親セッションのものへ戻る**ため、作業ディレクトリは引数で絶対パスを渡し `git -C <path>` を使わせる (`cd` の状態は次の呼び出しに残らない)。

### skill = agent の wrapper の例

| skill (wrapper) | agent (本体) |
|---|---|
| `/utility-self-improving` | `self-improving-extractor` + `self-improving-judge` |
| `/workflow-review` | `review-impl` (統合レビュワー 1 本。セキュリティは security-guidance プラグインに委譲) |

### agent only (skill 無し、上位 orchestrator 専用)

| agent | 呼び出し元 |
|---|---|
| `tech-investigation` | `dev-spec` フェーズ 5 (PoC 検証、並列 fan-out) |
| `dev-impl-implementer` | `dev-impl` Step 2.2 (`mode: implement`) / Step 2.3 (`mode: fix`)、いずれも model: opus 明示。`tools` に `Agent` を持たない葉 |
| `review-impl` | `dev-impl` Step 2.3 (focus: all) / `dev-impl-quick` ステップ 4 (focus: tests) / `workflow-review` (focus: all)。いずれも model: opus 明示 |
| `fix-lsp-warnings` | Agent ツールで直接起動 (Lua/Neovim の警告修正) |

## スキル一覧

開発フローに関わるスキルのみ列挙する (単発スキルの網羅一覧ではない)。

### 開発フロー

| スキル | 説明 | 入力 | 出力 |
|---|---|---|---|
| [dev-spec](./dev-spec/) | 設計ループ。ユーザーストーリー〜PoC 検証〜横断設計 (DESIGN.md 1 枚)〜機能設計 (docs/features/)〜設計チェック〜issue ドラフトチェック〜GitHub issue 生成。クイックモード・部分実行・途中再開可。プロダクトモード (`cli`/`webapp`) 指定で CLI ツール開発時は UI スケッチ等を軽量化 | `cli`/`webapp` + タスク説明 (省略時は推論して確認) | USER_STORIES.md 〜 DESIGN.md (product-mode スタンプ付き) + docs/features/*.md + GitHub issue 群 (親 1 件 `tracking` + 子 N 件 `ready`、sub-issue 紐付け) |
| [dev-impl](./dev-impl/) | 実装ループ。GitHub issue を `Depends on #N` の順に 1 件ずつ自律実装 (implementer subagent が issue と docs を直読して TDD → review-impl → 修正 ≤2 ラウンド → PR → DoD ローカル実行 green で merge → close)。詰まった issue は needs-human で駐車して次へ。進捗は issue コメントのみで、2 ラウンド後の未解消 medium はチェックリスト HTML に集約して run 終了時に確認を促す | GitHub issue (必須)。docs/DESIGN.md + docs/features/ は issue から参照される | issue ごとの PR + merge コミット |
| [dev-impl-quick](./dev-impl-quick/) | 軽量実装ループ。依頼文をタスク分解 → 1 件ずつ直営 TDD → テストゲート → review-impl (focus: tests、model: opus 明示) → タスク単位 commit | 依頼文または簡易タスクリスト (docs 不要) | タスク単位のコミット |

dev-spec の各フェーズ手順書は [dev-spec/references/](./dev-spec/references/) にある (user-story / ui-sketch / usecase-description / feasibility-check / **poc-verification** / design-doc / feature-doc / issue-template)。

### 横断ユーティリティ

| スキル | 説明 |
|---|---|
| [workflow-review](./workflow-review/) | git 差分を review-impl (テスト品質・設計準拠・コード品質・E2E) でレビュー。修正はメインループ直営 TDD |
| [workflow-commit](./workflow-commit/) | Conventional Commit 形式でコミット (push はユーザが手動) |
| [workflow-create-draft-pr](./workflow-create-draft-pr/) | ローカルのコミット履歴と差分から Draft PR を作成 (`.github/` のテンプレート自動検出) |
| [workflow-debate](./workflow-debate/) | 複数サブエージェントで議論を反復し、相違が収束するまで議題を検証 |
| [workflow-design-notes](./workflow-design-notes/) | 議論しながら設計を固める進行様式。決定台帳 → 節目に DESIGN.md + docs/features/ へゼロから落とし込み |

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
| [utility-doc-audit](./utility-doc-audit/) | ドキュメントの整合性・フォーマット適合を fresh context の fan-out で監査 |
| [utility-pdf-compress](./utility-pdf-compress/) | PDF のロスレス圧縮 |
| [utility-cf-deploy-token](./utility-cf-deploy-token/) | 1Password のマスタートークンから Cloudflare のデプロイ用トークン (Workers Scripts + D1) を発行し、GitHub Actions の secrets に登録 |
| [transcribing-meeting-minutes](./transcribing-meeting-minutes/) | 会議録音をローカル文字起こしし、時刻根拠付きの議事録を作成 |
| [llm-feature-design](./llm-feature-design/) | アプリに組み込む LLM 機能のプロンプトと周辺構造を設計 (回答範囲の制限 / 非信頼テキストと injection 対策 / グラウンディング / ガードレール / 評価)。規範は references/ から遅延参照し、逐語引用と出典は references/evidence.md に分離 |

## 補足

- **必ずしも全フェーズを使う必要はない** — dev-spec はクイックモード・部分実行・途中再開に対応
- **PoC 検証は不確実性がある場合のみ発火** — 技術的不確実性が無ければ自動スキップ
- **設計の正本は docs 側** — issue は docs を参照するだけで、転記・同期の機構は無い。機能の設計を知りたければ `docs/features/<機能名>.md` を読む (ローカルで AI に聞くときもここを指す)
