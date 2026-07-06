---
name: implementation-developing
description: TDD (RED→GREEN→REFACTOR) でフェーズ単位の新機能実装やバグ修正を行うエントリスキル。本体ロジックは `implementation-developing-agent` subagent に委譲し、本 skill はメインセッション向けの薄い orchestrator として「タスク説明取得 → PHASE_CONTEXT 組み立て → subagent 起動 → 結果整形表示 → コミット確認」を担当する。docs/TODO.md があるとフェーズ単位、なければ単独タスクとして 1 サイクル。「実装したい」「TDD で実装」「機能を追加」「バグを修正」などで起動。
argument-hint: "[タスク説明]"
allowed-tools: Read, Glob, Grep, Bash, Agent, Skill, AskUserQuestion
---

# /implementation-developing - TDD 実装スキル (subagent wrapper)

`implementation-developing-agent` subagent を起動して TDD 実装を実行する薄い orchestrator。

## 設計方針

- **本体ロジック**: `claude/agents/implementation-developing-agent.md` (subagent)
- **本 skill**: ユーザーがメインセッションで `/implementation-developing` を打って実装したい時のエントリポイント。subagent への入力 (PHASE_CONTEXT) を組み立てて起動、結果を整形表示する
- **autopilot からの呼び出し**: 直接 `implementation-developing-agent` を呼ぶ (本 skill は経由しない、最短経路でコンテキスト分離を保つ)

skill と agent の責務分担詳細は `skills/README.md` の規約セクションを参照。

## 参照ルール

- TDD ルール: @rules/core/tdd.md (agent 側でも参照される)
- 設計原則: @rules/core/design.md
- アーキテクチャパターン詳細: `references/architecture-patterns.md`

## 使い方

```
/implementation-developing                                # 対話で入力
/implementation-developing ログインフォームにバリデーションを追加  # 引数で指定
```

事前会話でタスクが明確なら、コンテキストから推論。

## 実行手順

### Step 1: タスク説明取得

- `$ARGUMENTS` があればそのまま使用
- 無ければ AskUserQuestion で「どのタスクを実装するか」を確認

### Step 2: 既存ドキュメントの確認

Read で以下を確認:

- `docs/DESIGN.md` (概要設計)
- `docs/DESIGN_DETAIL.md` (詳細設計)
- `docs/TODO.md` (フェーズ管理)

存在パターン別の挙動:

| 状態 | 挙動 |
|---|---|
| TODO.md あり、フェーズ指定 (引数) | 該当フェーズの phase_tasks を抽出 |
| TODO.md あり、フェーズ指定なし | AskUserQuestion で「どのフェーズを実装するか」確認 |
| TODO.md なし、タスク説明あり | 単独タスクとして 1 サイクル (擬似フェーズ名 "ad-hoc") |
| DESIGN.md / DESIGN_DETAIL.md なし | 警告表示後にタスク説明だけで進める (subagent 側で「設計書不在」を意識して動く) |

### Step 3: PHASE_CONTEXT の組み立て

subagent に渡す構造化情報を組み立てる:

```yaml
phase_name: <フェーズ名 または "ad-hoc: <タスク説明>">
phase_start_sha: <git rev-parse HEAD>
phase_tasks: |
  <TODO.md 該当部分。無ければユーザーのタスク説明>
design_overview: |
  <DESIGN.md 関連節抜粋。無ければ空>
design_detail: |
  <DESIGN_DETAIL.md 関連節抜粋。無ければ空>
related_source_files:
  - <Glob で抽出した関連ファイル>
related_rules_paths:
  - rules/core/tdd.md
  - rules/core/design.md
  - rules/core/testing.md
  - rules/core/commit.md
  - <言語別 rules があれば追加: rules/frontend/react/*.md など>
prev_phase_summary: ""
poc_results: []
```

メインセッション利用では `prev_phase_summary` / `poc_results` は空 (autopilot のみが提供)。

### Step 4: subagent 起動

Agent ツールで `implementation-developing-agent` を呼ぶ:

```javascript
const result = await Agent({
  description: "TDD 実装",
  subagent_type: "implementation-developing-agent",
  prompt: `PHASE_CONTEXT:\n${yamlStringify(PHASE_CONTEXT)}`
})
```

subagent 内の TDD 違反は tdd-guard hook (`tdd-guard.ts`) が並走チェックする (実装ファイルへの Edit を PreToolUse で事前ゲート + SubagentStop で停止時チェック。skill 側は意識しない)。

### Step 5: 結果整形表示

返り値 (stdout 末尾の JSON) をパースしてユーザーに整形表示:

```javascript
const dev = JSON.parse(result.match(/\{[\s\S]*\}$/)[0])
```

表示内容:

```
✓ TDD 実装完了

実装フェーズ: <phase_name>
変更ファイル: <modified_files の一覧>
TDD 順守: RED first=<...>, tests green=<...>, notes=<...>

検出されたシグナル:
- [todo_minor] <what> / <fix_proposal>
- [design_detail_gap] <what> / <fix_proposal>

セルフレビュー: <self_review_notes>
```

`status: escalate` の場合は、エスカレ理由を強調表示してユーザー判断を仰ぐ。

### Step 6: 次アクション確認

AskUserQuestion で次のアクションを選択:

```javascript
AskUserQuestion({
  questions: [{
    question: "TDD 実装が完了しました。次のアクションを選択してください。",
    header: "次のアクション",
    options: [
      { label: "レビュー (推奨)", description: "workflow-review で 5 観点レビュー → 指摘対応後にコミットへ" },
      { label: "コミット", description: "workflow-commit でコミット (push は手動)。レビュー済みの場合" },
      { label: "次フェーズ", description: "TODO.md がある場合、次フェーズの実装に進む" },
      { label: "完了", description: "ここで終了" }
    ],
    multiSelect: false
  }]
})
```

選択別の処理:
- レビュー: `Skill({ skill: "workflow-review" })` → 指摘対応が終わったら Step 6 に戻る (autopilot 経路がループ内でレビューを必須にしているのと対称に、対話実装でもレビュー → コミットを既定の流れとする)
- コミット: `Skill({ skill: "workflow-commit" })`
- 次フェーズ: Step 2 に戻る (phase_tasks の次フェーズを指定)
- 完了: 終了

## 範囲外 (やらないこと)

- 本体の TDD ロジック → `implementation-developing-agent` (subagent)
- 設計判断 / DESIGN.md 編集 → `requirements-*` 系 skill
- TODO.md の生成 → `implementation-planning-tasks`
- 複数フェーズの自動連続実行 → `workflow-autopilot`
- git push → ユーザー手動

## 関連

- subagent: `implementation-developing-agent` (本体ロジック)
- hook: `tdd-guard.ts` (PreToolUse で実装編集を事前ゲート / SubagentStop で停止時チェック)
- 連携 skill: `workflow-commit` / `workflow-review` / `implementation-planning-tasks`
- 上位: `workflow-autopilot` (本 skill を経由せず agent を直接呼ぶ)
