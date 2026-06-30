---
name: workflow-review
description: ローカルの git 差分を 5 観点 (TDD / コード品質 / セキュリティ / アーキテクチャ / プロジェクトルール) で並列レビュー。本体ロジックは review-tdd / review-quality / review-security / review-architecture / review-rules subagent に委譲し、本 skill はメインセッション向けの薄い orchestrator として「差分検出 → PHASE_CONTEXT 組み立て → 5 subagent 並列起動 → 結果集約・整形表示 → 修正アクション選択」を担当する。fatal 判定 (autopilot の self-fix loop 用) は本 skill では行わず、呼び出し側に任せる。
argument-hint: "[--staged | --all]"
allowed-tools: Bash, Read, Glob, Grep, Agent, AskUserQuestion
---

# /workflow-review - 5 観点並列コードレビュー (subagent wrapper)

5 つの review subagent を**並列起動**してコードレビューを行う薄い orchestrator。

## 設計方針

- **本体ロジック**: `claude/agents/review-{tdd,quality,security,architecture,rules}.md` (subagent × 5)
- **本 skill**: ユーザー向けエントリポイント。差分検出と PHASE_CONTEXT 組み立て、subagent 並列起動、結果集約・整形表示
- **autopilot からの呼び出し**: 本 skill 経由 (`Skill({ skill: "workflow-review" })`)、fatal 判定は autopilot 側で
- **観点拡張**: 観点を増やしたい場合は `claude/agents/review-<観点>.md` を追加して本 skill の起動リストに加える

skill / agent 責務分担の詳細は `skills/README.md` 参照。

### パフォーマンス観点 (perf) はどこに?

旧 workflow-review にあった「パフォーマンス」観点は、現在 `review-quality` subagent の中の「アルゴリズム効率 / アンチパターン (重複・過剰抽象)」に統合済。専用 perf agent を作るかは future improvement (実プロジェクトで perf 指摘が薄いと感じたら別 agent 化を検討)。

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
phase_start_sha: <HEAD~1 or merge-base or HEAD>  # 差分の基準点
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
  <docs/DESIGN_DETAIL.md があれば全文 or 抜粋>
output_path_prefix: /tmp/review-<観点>-working-tree.json
```

autopilot から呼ばれる場合は、autopilot が `Skill({ skill: "workflow-review", args: { phase_start_sha, phase_name, ... } })` で渡せる (skill 側で受け取って差し替え)。

### Step 3: 5 subagent 並列起動

Agent ツールを同一メッセージ内に複数 tool_use として並べて並列起動:

```javascript
const reviews = await Promise.all([
  Agent({ subagent_type: "review-tdd",          prompt: reviewPromptFor("tdd",          ctx) }),
  Agent({ subagent_type: "review-quality",      prompt: reviewPromptFor("quality",      ctx) }),
  Agent({ subagent_type: "review-security",     prompt: reviewPromptFor("security",     ctx) }),
  Agent({ subagent_type: "review-architecture", prompt: reviewPromptFor("architecture", ctx) }),
  Agent({ subagent_type: "review-rules",        prompt: reviewPromptFor("rules",        ctx) }),
])
```

各 subagent は output_path に JSON を Write、stdout には絶対パス 1 行のみを返す。

#### reviewPromptFor(dimension, ctx)

各 subagent には dimension に応じて rules path を絞った prompt を渡す:

- tdd: `rules/core/tdd.md`, `rules/core/testing.md`
- quality: `rules/core/design.md`
- security: (なし、subagent が自前で観点持つ)
- architecture: `rules/core/design.md`
- rules: 全 related_rules_paths + 拡張子別 (`rules/frontend/react/*.md` 等)

### Step 4: 集約

5 つの JSON を Read してパース、findings をまとめる:

```javascript
const all = []
for (const r of reviews) {
  const json = JSON.parse(await Read(r.trim()))
  all.push({ dimension: json.dimension, findings: json.findings })
}
```

**本 skill は fatal 判定を行わない**。集約結果を「全 findings」としてそのまま返す / 表示する。
autopilot が呼ぶ場合は autopilot 側で severity 基準で fatal 抽出 + self-fix loop 判定する。

### Step 5: 結果整形表示 (メインセッション利用時)

サマリーテーブル → 観点別 findings の順で表示:

```markdown
# Code Review Report

## Summary
| 観点 | high | medium | low |
|---|---|---|---|
| tdd          | X | X | X |
| quality      | X | X | X |
| security     | X | X | X |
| architecture | X | X | X |
| rules        | X | X | X |
| **合計** | **X** | **X** | **X** |

## findings (severity 順)

### [high][security] ハードコードされた API キー
**ファイル**: `src/config.ts:45`
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
      { label: "high をすべて修正", description: "implementation-developing で TDD 修正" },
      { label: "high + medium を修正", description: "同上、対象拡張" },
      { label: "個別に選択", description: "修正対象を選んで TDD 修正" },
      { label: "終了", description: "修正せず完了" }
    ],
    multiSelect: false
  }]
})
```

「修正」選択時は `Skill({ skill: "implementation-developing", args: "<修正タスク説明>" })` で TDD 修正サイクルを起動。

## 範囲外 (やらないこと)

- 観点別の検査ロジック → 各 `review-*` subagent
- fatal 判定 (severity 基準で「修正必須」を決める) → 呼び出し側 (autopilot や本 skill 内の AskUserQuestion)
- 修正実行 → `implementation-developing` skill (TDD で)
- コミット → `workflow-commit`

## 関連

- subagent: `review-tdd` / `review-quality` / `review-security` / `review-architecture` / `review-rules` (本体ロジック)
- 連携 skill: `implementation-developing` (修正実行) / `workflow-commit`
- 上位: `workflow-autopilot` Step 4.5 (本 skill を呼んで集約結果を受け取り、autopilot 側で fatal 判定 + self-fix loop)
