# Claude Code Skills

プロダクト開発を支援する Claude Code スキル集。

## タスク規模別の入口 (まずここを見る)

開発タスクは規模で入口を使い分ける。**入口はタスクの規模に対して 1 つに決まる**。

| 規模 | 入口 | 中身 |
|---|---|---|
| **L: 新規プロダクト・大きい機能** | `/dev-spec` (`cli`/`webapp` 指定可) → (承認ゲート) → GitHub issue → `/dev-impl` | 設計ループ (要件〜PoC 検証〜設計書〜TODO〜issue 生成) → 実装ループ (issue を依存順に 1 件ずつ自律実装)。issue はユースケース単位の親 issue にフェーズ issue がぶら下がる 2 階層で、親を見れば進捗を俯瞰できる。プロダクトモード (cli/webapp) は省略時タスク説明から推論。Cloudflare フルスタック (D1 + Hono) の新規立ち上げは先に `/fullstack-app-builder` で scaffold + 環境構築してから `/dev-spec` に入る |
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
│      → 9 検証手順補完 → 10 TODO 生成 → 10.5 設計整合監査       │
│      → 11 ★承認ゲート → 12 GitHub issue 生成                   │
│         (UC 単位の親 issue + フェーズ子 issue の 2 階層)       │
│                                                                │
│  Feedback: 設計 = 人間承認 / 技術実現性 = PoC 実行結果         │
│  クイックモード: 7〜12 のみ (不確実性があれば 4〜5 を通す)     │
│  プロダクトモード: cli は 2 ui-sketch をスキップし CLI I/F     │
│  仕様をフェーズ 7 内で設計 (DESIGN.md にスタンプで記録)        │
└──────────────────────────┬─────────────────────────────────────┘
                           │ 承認ゲート = 人間が /dev-impl を起動
                           │ (Claude は自律的に越えられない)
┌──────────────────────────▼─────────────────────────────────────┐
│  /dev-impl — 実装ループ (model: opus、直接起動で切り替わる)    │
│                                                                │
│  POC_NEEDED 残存ガード → open issue の Depends on で着手順決定 │
│  issue 1 件ずつ (並列化しない):                                │
│    in-progress を貼る → issue 本文から PHASE_CONTEXT 組み立て →│
│    implementer subagent で TDD 実装 (葉、opus) → 親が待つ →    │
│    guard + review-* を親が fan-out (1 回の待ち) →              │
│    fatal あれば implementer(mode: fix) 再 spawn (最大 3) →     │
│    親が全テストゲート → commit → issue を close                │
│    (子が揃った UC 親 issue も自動 close)                       │
│  P1/P2 の設計乖離でフェーズが増えたら issue 化して同ループへ   │
│  → ゴール達成判定 (未達は新規 issue) → HTML レポート           │
│                                                                │
│  エスカレ (P3 等) でのみ停止。再開は /dev-impl 再実行          │
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

モデル割当の正は **`rules/core/orchestration.md`** (トリアージ手順・割当マトリクス・Fable → Opus 4.8 フォールバック規定)。ここではスキル側への適用だけを記す。原則: **実行器のモデル ≤ 検証器のモデル**。モデルの賢さは検証器の薄いところに配置する。設計思想の全体像 (7 要素・三大失敗モード) は [rules/core/references/loop-engineering.md](../rules/core/references/loop-engineering.md) を参照。

| 対象 | モデル | 理由 |
|---|---|---|
| dev-spec (設計ループ) | セッション継承 (最上位 tier 推奨) | 検証器が人間しかいないため、生成側を賢くする |
| dev-impl (実装ループ) / dev-impl-quick (軽量実装ループ) | `model: opus` (frontmatter) | 実装の質がそのまま成果物の質になるため実行器を下げない |
| dev-impl-implementer subagent (`mode: implement` / `mode: fix`) | `model: opus` (frontmatter + 呼び出し時明示) | 実行器。実装の質がそのまま成果物の質になるため下げない。`agent-spawn-guard` hook が呼び出し時の model 未指定を deny する |
| review-tdd / review-quality / review-product-readiness / review-spec-compliance subagent | `model: opus` (frontmatter + 呼び出し時明示) | 検証器は実行器より下げない。frontmatter も opus にして、呼び出し時の明示忘れで無音でセッション継承より下に落ちない防御とする |
| review-adversarial subagent | `model: opus` (frontmatter + 呼び出し時明示) | 一時 sonnet を規定していたが、settings.json の alias 再マップにより実行時は opus になっており規定が成立していなかった。2026-08-22 に mind の run を実測すると opus 実行で 0.56 件/spawn (review-tdd の 0.55 と同水準) で、sonnet 優位 (0.90 対 0.15) は再現しなかった。経緯は `skills/dev-impl/references/orchestration-rationale.md` の `## review-adversarial のモデル選択の経緯` |
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

subagent への委譲は「並列化」と「親コンテキストの保護 (巨大出力の隔離)」のためだけに行う。逐次依存する実装・修正・コミットは**メインループ直営** (`rules/core/orchestration.md`「委譲の判断」)。

**dev-impl だけがこの原則の明示的な例外**で、issue 1 件ずつの逐次実装であっても `dev-impl-implementer` subagent に出す。根拠は「フェーズを 100 本単位で回すとメインループのコンテキストが単調増加し、平均 475k トークン × 1 万リクエストになる」という実測で、詳細は `dev-impl/SKILL.md` の「フェーズ実装を subagent に委譲する理由」にある。この例外は dev-impl に閉じており、他のスキル・plan mode・直接依頼では従来どおり直営で実装する。

例外の前提は **implementer が葉である** (子 subagent を起動しない) こと。子を待つ subagent は 5 分 TTL のキャッシュを失効させるため、レビューの起動と待機は 1 時間 TTL の親に置く。葉性は `agents/dev-impl-implementer.md` の `tools` から `Agent` を除いて構造的に強制する (subagent には親の hooks が届かず、指示文では違反を検出できないため)。

git index を共有する操作 (コミット) は並列化できないので親に残す。なお subagent の Bash は**呼び出しごとに cwd が親セッションのものへ戻る**ため、作業ディレクトリは引数で絶対パスを渡し `git -C <path>` を使わせる (`cd` の状態は次の呼び出しに残らない)。

### skill = agent の wrapper の例

| skill (wrapper) | agent (本体) |
|---|---|
| `/utility-self-improving` | `self-improving-extractor` + `self-improving-judge` |
| `/workflow-review` | `review-tdd` + `review-quality` + `review-product-readiness` + `review-adversarial` (4 並列。セキュリティは security-guidance プラグインに委譲) |

### agent only (skill 無し、上位 orchestrator 専用)

| agent | 呼び出し元 |
|---|---|
| `tech-investigation` | `dev-spec` フェーズ 5 (PoC 検証、並列 fan-out) |
| `dev-impl-implementer` | `dev-impl` Step 4.2a (`mode: implement`) / Step 4.2d (`mode: fix`)、いずれも model: opus 明示。`tools` に `Agent` を持たない葉 |
| `architecture-guard` | `dev-impl` Step 4.2c (検査 fan-out に**最後の issue のフェーズでだけ**含める。それ以外のフェーズでレイヤ境界を担保するのはプロジェクトの lint) |
| `fix-lsp-warnings` | `dev-impl` Step 4.2b (単独・逐次。修正 agent なので検査 fan-out に混ぜない) / Agent ツールで直接起動 |
| `review-*` (tdd / quality / product-readiness) | `dev-impl` Step 4.2c (model: opus 明示) / `workflow-review` |
| `review-adversarial` | `dev-impl` Step 4.2c (model: opus 明示。リスク面が空なら `mode: weakening_only`、面を踏む差分・テスト差分なしの大量実装・最後の issue のフェーズは `mode: full`) / `workflow-review` (常に `full`) |
| `review-tdd` (単一観点のみ) | `dev-impl-quick` ステップ 4 (model: opus 明示) |

## スキル一覧

### 開発フロー

| スキル | 説明 | 入力 | 出力 |
|---|---|---|---|
| [dev-spec](./dev-spec/) | 設計ループ。ユーザーストーリー〜PoC 検証〜設計書〜TODO 生成を対話実行し、設計整合監査 → 承認ゲート → GitHub issue 生成まで通して実装ループへ引き渡す。クイックモード・部分実行・途中再開可。プロダクトモード (`cli`/`webapp`) 指定で CLI ツール開発時は UI スケッチ等を軽量化 | `cli`/`webapp` + タスク説明 (省略時は推論して確認) | USER_STORIES.md 〜 DESIGN.md (product-mode スタンプ付き) + DESIGN_DETAIL_APP.md + DESIGN_DETAIL_INFRA.md + TODO.md (承認スタンプ付き) + GitHub issue 群 (`ready` のフェーズ issue + `uc-tracking` の UC 親 issue) |
| [dev-impl](./dev-impl/) | 実装ループ。dev-spec が作った GitHub issue を `Depends on #N` の順に 1 件ずつ自律実装 (implementer subagent で TDD → guard + review を親が fan-out (敵対的レビュー含む) → fatal は implementer(mode: fix) で修正 → テストゲート → commit → issue を close)。並列化はしない。子が全て closed になった UC 親 issue は自動で close する。完了時に第三者受入監査 (review-spec-compliance がゴール検証を独立再実行 + 成果物↔設計突合)、HTML レポート。P1/P2 は動的修正、P3 で停止 | GitHub issue (必須) + DESIGN.md + DESIGN_DETAIL_APP.md + DESIGN_DETAIL_INFRA.md + TODO.md (承認スタンプは goals_sha 付き) | issue ごとのコミット + `docs/dev-impl-reports/<run_id>.html` |
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
| [utility-dev-impl-measure](./utility-dev-impl-measure/) | dev-impl の改修効果を before/after で計測 (手順の正は `~/.claude/handoff/dev-impl-refactor/MEASUREMENT.md`) |
| [utility-pdf-compress](./utility-pdf-compress/) | PDF のロスレス圧縮 |
| [utility-cf-deploy-token](./utility-cf-deploy-token/) | 1Password のマスタートークンから Cloudflare のデプロイ用トークン (Workers Scripts + D1) を発行し、GitHub Actions の secrets に登録 |
| [transcribing-meeting-minutes](./transcribing-meeting-minutes/) | 会議録音をローカル文字起こしし、時刻根拠付きの議事録を作成 |
| [llm-feature-design](./llm-feature-design/) | アプリに組み込む LLM 機能のプロンプトと周辺構造を設計 (回答範囲の制限 / 非信頼テキストと injection 対策 / グラウンディング / ガードレール / 評価)。規範は references/ から遅延参照し、逐語引用と出典は references/evidence.md に分離 |

## 補足

- **必ずしも全フェーズを使う必要はない** — dev-spec はクイックモード・部分実行・途中再開に対応
- **PoC 検証は blocker=true がある場合のみ発火** — 技術的不確実性が無ければ自動スキップ
- **各スキルはセルフレビュー機能を持つ** — 生成したドキュメントを自動でレビュー・修正
