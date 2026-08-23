---
name: workflow-review
description: ローカルの git 差分を統合レビュワー review-impl subagent (テスト品質 / 設計準拠 / コード品質 / E2E 実行の 4 項目) で fresh context レビューする薄い orchestrator。「差分検出 → review-impl 起動 → 結果の整形表示 → 修正アクション選択」を担当。セキュリティレビューは security-guidance プラグイン (Stop hook の LLM diff review + Edit 時の pattern 検知) に委譲しており本 skill の対象外。「レビューして」「この差分を見て」「コミット前にチェック」などで起動。
argument-hint: "[--staged]"
allowed-tools: Bash, Read, Glob, Grep, Agent, AskUserQuestion
---

# /workflow-review - 統合コードレビュー (subagent wrapper)

`review-impl` subagent を fresh context で起動してローカル差分をレビューする薄い orchestrator。本体の検査ロジックと入出力契約は `claude/agents/review-impl.md` が正本。

- **dev-impl (実装ループ) は本 skill を呼ばない** (dev-impl 本体が issue サイクル内で review-impl を直接起動する)。本 skill は手動レビュー用
- セキュリティレビューは Anthropic 公式プラグイン `security-guidance@claude-plugins-official` に委譲 (Edit/Write 時の pattern 検知 + Stop hook の LLM diff review が自動で走る)

## 使い方

```
/workflow-review              # working tree 全変更 (unstaged + staged)
/workflow-review --staged     # ステージ済みのみ
```

## 実行手順

### Step 1: 差分検出

```bash
git rev-parse --git-dir          # git リポジトリ確認
git status --porcelain           # 変更ファイル一覧
BASE_SHA=$(git rev-parse HEAD)   # レビュー範囲の基準
```

git リポジトリでない場合は「git リポジトリではありません」、変更 0 件の場合は「レビュー対象がありません」と表示して終了。

### Step 2: review-impl の起動

```javascript
Agent({
  description: "working tree のレビュー",
  subagent_type: "review-impl",
  model: "opus",   // 実行器 ≤ 検証器
  prompt: `repo_dir: <git rev-parse --show-toplevel の結果>
base_sha: <BASE_SHA>
docs_hint: <docs/DESIGN.md や docs/features/ が存在すればそのパス。無ければ「なし (設計 docs の無いリポジトリ)」>
focus: all
report_path: <scratchpad>/workflow-review-<timestamp>.json`
})
```

`--staged` のときは prompt に `diff_scope: staged` を追加する (review-impl の入力契約のキー)。report JSON が生成されない・パース不能の場合は 1 回だけ再試行し、再失敗ならその旨を伝えて手動レビューを案内する。

### Step 3: 結果の整形表示

report JSON を読み、severity 順に表示する:

```
📋 レビュー結果 (review-impl)
  high   <n> 件: <各 1 行: file:line summary>
  medium <n> 件: ...
  low    <n> 件: ...
  検査範囲: tests_run=<>, docs_read=<>, e2e=<>
```

findings 0 件なら `checked` の内容とともに「指摘なし」と報告する。

### Step 4: 修正アクション選択

findings があれば AskUserQuestion で確認する: 「high/medium をメインループで直営修正 (推奨) / 指摘の詳細を表示 / 何もしない」。修正を選んだら、指摘箇所だけを直してテストを再実行し、必要なら Step 2 から再レビューする (`report_path` は別名にする)。

## 関連

- **review-impl** (subagent): 検査ロジックの正本
- **dev-impl / dev-impl-quick**: フロー内で review-impl を自動起動する実装ループ (本 skill は手動用)
