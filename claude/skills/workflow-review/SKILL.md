---
name: workflow-review
description: ローカルの git 差分を 4 観点 (TDD / コード品質+ルール準拠+構造 / プロダクト readiness / 敵対的レビュー) で並列レビュー。本体ロジックは review-tdd / review-quality / review-product-readiness / review-adversarial subagent に委譲し、本 skill はメインセッション向けの薄い orchestrator として「差分検出 → PHASE_CONTEXT 組み立て → subagent 並列起動 → 結果集約・整形表示 → 修正アクション選択」を担当する。セキュリティレビューは security-guidance プラグイン (Stop hook の LLM diff review + Edit 時の pattern 検知) に委譲しており本 skill の対象外。fatal 判定は本 skill では行わず、呼び出し側に任せる。
argument-hint: "[--staged | --all]"
allowed-tools: Bash, Read, Glob, Grep, Agent, AskUserQuestion
---

# /workflow-review - 4 観点並列コードレビュー (subagent wrapper)

4 つの review subagent を**並列起動**してコードレビューを行う薄い orchestrator。

## 設計方針

- **本体ロジック**: `claude/agents/review-{tdd,quality,product-readiness,adversarial}.md` (subagent × 4。quality は rules 準拠とアーキテクチャ heuristic を統合済み。adversarial は実装破壊・reward hacking 検知・完了報告の反証の 3 レンズ)
- **本 skill**: ユーザー向けエントリポイント。差分検出と PHASE_CONTEXT 組み立て、subagent 並列起動、結果集約・整形表示
- **dev-impl (実装ループ) は本 skill を呼ばない** (dev-impl 本体が Step 4.2d で review subagent を観点 gating 付きで直接起動する)。本 skill は手動レビュー用
- **観点拡張**: 観点を増やしたい場合は `claude/agents/review-<観点>.md` を追加して本 skill の起動リストに加える

skill / agent 責務分担の詳細は `skills/README.md` 参照。

### パフォーマンス観点 (perf) はどこに?

旧 workflow-review にあった「パフォーマンス」観点は、現在 `review-quality` subagent の中の「アルゴリズム効率 / アンチパターン (重複・過剰抽象)」に統合済。専用 perf agent を作るかは future improvement (実プロジェクトで perf 指摘が薄いと感じたら別 agent 化を検討)。

### セキュリティ観点はどこに?

セキュリティレビューは自作 subagent 化せず、Anthropic 公式プラグイン `security-guidance@claude-plugins-official` に委譲している。Edit/Write 時の pattern 検知と `Stop` hook での LLM diff review が自動で走るため、本 skill の並列レビューには含めない (`git commit` 毎のエージェント型レビュー層は `ENABLE_COMMIT_REVIEW=0` で無効化済、粒度が過剰なため)。

## 使い方

```
/workflow-review              # working tree 全変更 (unstaged + staged)
/workflow-review --staged     # ステージ済みのみ
```

## 実行手順

### Step 1: 差分検出

```bash
git rev-parse --git-dir          # gitリポジトリ確認
git status --porcelain           # 変更ファイル一覧
git diff [--staged]              # 差分本体
git rev-parse HEAD               # 基準 SHA (= phase_start_sha 相当)
```

git リポジトリでない場合: 「gitリポジトリではありません」表示して終了。
変更 0 件の場合: 「レビュー対象がありません」表示して終了。

### Step 2: PHASE_CONTEXT 組み立て (簡素版)

メインセッション利用なので「フェーズ」概念は無い。差分範囲を `working_tree` として扱い、PHASE_CONTEXT を最小限で組み立てる:

```yaml
phase_name: "working-tree-review"
phase_start_sha: <HEAD>                           # Step 1 の `git rev-parse HEAD` の結果をそのまま使う (working tree の未コミット差分だけを見るため)
diff_range: working_tree                          # subagent 側で git diff (no range) する
related_source_files:
  - <変更ファイル一覧>
related_rules_paths:
  - rules/core/tdd.md
  - rules/core/design.md
  - rules/core/testing.md
  - rules/core/commit.md
  - <変更ファイル拡張子に応じて path 別 rules を追加>
design_overview: |
  <docs/DESIGN.md があれば全文 or 抜粋>
design_detail: |
  <docs/DESIGN_DETAIL_APP.md / docs/DESIGN_DETAIL_INFRA.md があれば全文 or 抜粋 (旧形式 docs/DESIGN_DETAIL.md しか無ければそれを使う)>
dev_server:                                        # review-product-readiness 用。Web プロダクトでなければ省略 (null)
  url: <検出できた URL>
  start_command: <package.json の dev/start script>
output_path_prefix: /tmp/review-<観点>-working-tree.json
```

呼び出し側は `Skill({ skill: "workflow-review", args: { phase_start_sha, phase_name, dimensions, dev_server, ... } })` で args を渡せる。本 skill は受け取った `args` をそのまま `ctx` として使う (`args` 未指定のフィールドは上記 yaml サンプルの手動収集ロジックで埋める):

```javascript
const ctx = {
  phase_name: args.phase_name ?? "working-tree-review",
  phase_start_sha: args.phase_start_sha ?? execSync("git rev-parse HEAD").trim(),
  related_source_files: args.related_source_files ?? gitStatusPorcelainFiles(),
  related_rules_paths: args.related_rules_paths ?? defaultRulesPaths(),
  design_overview: args.design_overview ?? readIfExists("docs/DESIGN.md"),
  design_detail: args.design_detail ??
    [readIfExists("docs/DESIGN_DETAIL_APP.md"), readIfExists("docs/DESIGN_DETAIL_INFRA.md")]
      .filter(Boolean).join("\n\n") || readIfExists("docs/DESIGN_DETAIL.md"), // 旧形式フォールバック
  dev_server: args.dev_server, // 無ければ undefined のまま (review-product-readiness が no-op で扱う)
}
```

`dev_server` が無い場合は省略してよい (`review-product-readiness` が URL 不在で no-op になる)。

`args.dimensions` (optional array, 例: `["tdd"]` のような観点名の配列) が指定されていれば、その観点の subagent だけを起動する (呼び出し側での絞り込み用)。未指定時 (手動 `/workflow-review` 実行時など) は 4 観点フル起動 (ただし adversarial は下記スキップ述語を満たせば自動的に外れる)。

### Step 2.5: 観点トリアージ

「実装内容に応じた観点選択」を機械述語で行う。dev-impl Step 4.2d の adversarial スキップ述語を全観点に一般化したもの (手動利用なので JSONL 記録はしない。Step 5 のサマリに `adversarial: skipped (trivial diff: N 行)` のように観点ごとの採否理由を表示する)。基準は Step 2 の `phase_start_sha` (= `HEAD`) に揃える (`--staged` 実行時に staged 差分が判定から漏れることや、ctx が使う基準と述語の基準がズレることを防ぐため)。`$CHANGED` は porcelain の 2 文字ステータスプレフィックス付き出力ではなく `git diff --name-only` + `git ls-files --others` のプレーンなパス一覧を使う (プレフィックス付き出力にアンカー正規表現 `(^|/)tests?/` を当てると先頭一致が機能しない)。

```bash
CHANGED=$({ git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u)
NEW_FILES=$(git ls-files --others --exclude-standard)
TRACKED_LINES=$(git diff --shortstat HEAD | rg -o '[0-9]+' | tail -n +2 | paste -sd+ - | bc)
UNTRACKED_LINES=$(git ls-files --others --exclude-standard -z | xargs -0 cat 2>/dev/null | wc -l)
LINES=$(( ${TRACKED_LINES:-0} + ${UNTRACKED_LINES:-0} ))

TEST_FILE_CHANGED=$(echo "$CHANGED" | rg '(_test\.(go|rs|py)|\.test\.|\.spec\.|_spec\.|__tests__/|(^|/)tests?/|(^|/)test_[^/]*\.py)' || true)
TRACKED_CONTENT_CHANGED=$(git diff HEAD -U0 -- ':!*.md' ':!docs/' | rg '^[+-].*(#\[(test|cfg\(test\)|tokio::test|rstest)\]|func Test[A-Z]|\b(it|test|describe)\s*\(|def\s+test_|@pytest\.)' || true)
UNTRACKED_CONTENT_CHANGED=$(git ls-files --others --exclude-standard -z -- ':!*.md' ':!docs/' | xargs -0 -I{} rg -l '#\[(test|cfg\(test\)|tokio::test|rstest)\]|func Test[A-Z]|\b(it|test|describe)\s*\(|def\s+test_|@pytest\.' {} 2>/dev/null || true)
TEST_CONTENT_CHANGED="${TRACKED_CONTENT_CHANGED}${UNTRACKED_CONTENT_CHANGED}"

TRACKED_CONSUMABLE=$(git diff HEAD -U0 -- ':!*.md' ':!docs/' | rg -i '^[+-].*(refresh[_-]?token|\bnonce\b|one[_-]?time|idempotenc|\botp\b|presigned)' || true)
UNTRACKED_CONSUMABLE=$(git ls-files --others --exclude-standard -z -- ':!*.md' ':!docs/' | xargs -0 -I{} rg -li 'refresh[_-]?token|\bnonce\b|one[_-]?time|idempotenc|\botp\b|presigned' {} 2>/dev/null || true)
CONSUMABLE_CHANGED="${TRACKED_CONSUMABLE}${UNTRACKED_CONSUMABLE}"

NON_DOC_CHANGED=$(echo "$CHANGED" | rg -v '(^|/)docs/|\.md$' || true)
UI_CHANGED=$(echo "$CHANGED" | rg '\.(tsx|jsx|vue|svelte|css|scss)$|(^|/)(routes|pages|components)/' || true)
CI_CHANGED=$(echo "$CHANGED" | rg '(^|/)\.github/workflows/|(^|/)\.gitlab-ci|Dockerfile|docker-compose|(^|/)\.circleci/' || true)
```

観点ごとの起動条件 (機械述語。満たさなければ pre-filter でその観点を候補から外す):

| 観点 | 起動条件 |
|---|---|
| tdd | `$TEST_FILE_CHANGED` または `$TEST_CONTENT_CHANGED` が非空 (テストファイルの差分がある) |
| quality | `$NON_DOC_CHANGED` が非空 (実装ファイル差分あり) かつ (`$NEW_FILES` が非空 または `$LINES` > 20 または `$CONSUMABLE_CHANGED` が非空) |
| product_readiness | `$UI_CHANGED` が非空 (web UI 系差分がある) |
| adversarial | テスト変更なし (`$TEST_FILE_CHANGED` と `$TEST_CONTENT_CHANGED` がともに空) かつ `$LINES` ≤ 20 (または `.md`/`docs/` のみの差分) かつ `$CI_CHANGED` が空、の**すべてを満たさない**場合に起動 (= trivial diff でなければ起動) |

`$CONSUMABLE_CHANGED` は消費すると無効化される資源 (ローテーション有効な refresh token・nonce・ワンタイムコード・べき等キー・使い捨て署名 URL) を扱う差分の検知で、行数が小さくても quality を起動させるためにある。この種の差分は 1 行の変更でも多重消費・恒久エラー分岐の漏れで復帰不能障害になるため、行数ゲートの例外とする。

pre-filter で候補になった観点をそのままメインループに渡し、**メインループが diff の内容を見て最終的にどの観点を実際に起動するかを選択し、「選択と根拠」を 1 行出力**する (自律モード規約と同型。事後にユーザがレビューで乖離に気付ける状態を保つ)。`args.dimensions` が指定されている場合はこの述語評価をスキップし、指定観点をそのまま使う。

### Step 3: subagent 並列起動

`selectedDimensions` は Step 2.5 の pre-filter 候補からメインループが最終選択した観点の配列 (「選択と根拠」1 行出力の結果)。Agent ツールを同一メッセージ内に複数 tool_use として並べて並列起動:

```javascript
const DIMENSIONS = ["tdd", "quality", "product_readiness", "adversarial"]
// args.dimensions 指定時はそれを最優先。未指定なら Step 2.5 の pre-filter 候補から
// メインループが diff 内容を見て最終選択する (選択と根拠を 1 行出力してから実行)。
const targetDimensions = args.dimensions?.length ? args.dimensions : selectedDimensions

// model は必ず明示する。未指定だと agent 定義の frontmatter ではなく
// 親のセッションモデルを継承し、最上位 tier のセッションでは全 agent がその単価で走る。
const AGENT_TYPE = {
  tdd: { type: "review-tdd", model: "opus" },
  quality: { type: "review-quality", model: "opus" },
  product_readiness: { type: "review-product-readiness", model: "opus" },
  adversarial: { type: "review-adversarial", model: "sonnet" },
}

const reviews = await Promise.all(
  targetDimensions.map(d => Agent({
    subagent_type: AGENT_TYPE[d].type,
    model: AGENT_TYPE[d].model,
    prompt: reviewPromptFor(d, ctx),
  }))
)
```

各 subagent は output_path に JSON を Write、stdout には絶対パス 1 行のみを返す。

#### reviewPromptFor(dimension, ctx)

各 subagent には dimension に応じて rules path を絞った prompt を渡す:

- tdd: `rules/core/tdd.md`, `rules/core/testing.md`
- quality: `rules/core/design.md` + 拡張子別 (`rules/frontend/react/*.md` 等) + design_overview / design_detail (DESIGN 整合チェック用)
- product_readiness: design_overview の「ゴール」(G_E2E 含む) と design_detail の「UX 設計」を必ず含める + `dev_server` (start_command と URL) を渡す。CLI / API のみなら本 dimension は no-op で素通り
- adversarial: design 抜粋は渡さない (fresh context 監査のため)。`phase_name` (= ctx.phase_name、既定 `"working-tree-review"`) / `phase_start_sha` (= Step 1 の基準 SHA) / `docs_dir` (docs/ が存在すれば) / `dev_server` / `scratch_dir` (`/tmp/review-adversarial-working-tree/`) / `output_path` を渡す。review-adversarial.md の入力仕様は phase_name を TODO.md 該当節の切り出しキーとして要求するため必須 (`docs_dir` が無い場合はレンズ C は対象なしとして agent 側が skip する)

### Step 4: 集約

起動した subagent (`targetDimensions`) それぞれの JSON を Read してパース、findings を 1 つのフラット配列にまとめる:

```javascript
const findings = []
for (const r of reviews) {
  const json = JSON.parse(await Read(r.trim()))
  for (const f of json.findings) findings.push({ ...f, dimension: json.dimension })
}
// 呼び出し側が「今回どの観点を実際にレビューしたか」を区別できるよう、
// findings とあわせて targetDimensions もそのまま返す
return { findings, dimensions_reviewed: targetDimensions }
```

**本 skill は fatal 判定を行わない**。集約結果を「全 findings」としてそのまま返す / 表示する。
`dimensions_reviewed` は呼び出し側が findings を観点単位で洗い替えする際に使う (再実行しなかった観点の古い findings を誤って消さないため)。

### Step 5: 結果整形表示 (メインセッション利用時)

サマリーテーブル → 観点別 findings の順で表示:

```markdown
# Code Review Report

## Summary
| 観点 | high | medium | low |
|---|---|---|---|
| tdd                | X | X | X |
| quality            | X | X | X |
| product_readiness  | X | X | X |
| adversarial        | X | X | X |
| **合計** | **X** | **X** | **X** |

## findings (severity 順)

### [high][quality] レイヤ境界違反 (domain → infra import)
**ファイル**: `src/domain/user.ts:12`
**内容**: <message>
**推奨**: <fix_proposal>

### [high][tdd] テストファイルが存在しない
...
```

### Step 6: 修正アクション選択

AskUserQuestion で次のアクションを確認:

```javascript
AskUserQuestion({
  questions: [{
    question: "レビューで X 件の high / Y 件の medium が検出されました。どう進めますか？",
    header: "次のアクション",
    options: [
      { label: "high をすべて修正", description: "メインループで TDD 修正 (RED→GREEN→REFACTOR)" },
      { label: "high + medium を修正", description: "同上、対象拡張" },
      { label: "個別に選択", description: "修正対象を選んで TDD 修正" },
      { label: "終了", description: "修正せず完了" }
    ],
    multiSelect: false
  }]
})
```

「修正」選択時は findings を修正タスクとして**メインループで直接 TDD 修正サイクルを実行**する (RED: findings を再現する失敗テスト → GREEN → REFACTOR)。修正後は同じ観点を再レビューして解消を確認する。

## 範囲外 (やらないこと)

- 観点別の検査ロジック → 各 `review-*` subagent
- fatal 判定 (severity 基準で「修正必須」を決める) → 呼び出し側 (本 skill 内の AskUserQuestion)
- 修正実行の委譲 → しない (メインループで直接 TDD 修正する)
- コミット → `workflow-commit`

## 関連

- subagent: `review-tdd` / `review-quality` / `review-product-readiness` / `review-adversarial` (本体ロジック)
- セキュリティレビュー: `security-guidance@claude-plugins-official` プラグイン (本 skill の外、Edit/Write pattern 検知 + Stop hook LLM diff review)
- 連携 skill: `workflow-commit` (修正後のコミット)
- 上位: なし (dev-impl は本 skill を経由せず Step 4.2d で review subagent を直接起動する)
