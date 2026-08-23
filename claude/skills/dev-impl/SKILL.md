---
name: dev-impl
description: 実装ループ。/dev-spec が作成した GitHub issue (ゴール / 設計参照 / DoD / 非スコープ / 依存の thin 構成) を入力に、依存順に 1 件ずつ「implementer subagent → 統合レビュー → 修正 ≤2 ラウンド → PR → DoD ローカル実行 → merge → close」で自律実装するオーケストレーター。進捗は issue コメントに残し、詰まった issue は needs-human で駐車して次へ進む。人間の介入はエスカレーション時のみ。issue 作成後にユーザーが直接起動し、エスカレーション回答後の再開も本スキルの再実行で行う。「実装ループを開始」「issue を順に実装して」「残りタスクを自動で実装」などで起動。
argument-hint: "[issue 番号の絞り込み、省略時は ready 全件]"
model: opus
allowed-tools: Read, Edit, Write, Glob, Bash, Skill, Agent, AskUserQuestion
---

# dev-impl — 実装ループ

`ready` ラベルの open issue を依存順に最後まで自律的に実装するオーケストレーター。実装の指示はすべて issue 本文と参照 docs (docs/DESIGN.md / docs/features/) から取る — **issue が自己完結しているので、親が文脈を編纂して渡すことはしない**。

親 (このセッション) は薄いオーケストレーターに徹する: issue の順序管理 / subagent の起動 / コミット・PR・merge / issue のラベル・コメント操作。実装は implementer、検査は review-impl が fresh context で行う。

## モデル方針

| 役割 | 実行 | モデル |
| --- | --- | --- |
| オーケストレーション (本ループ) | メインセッション | opus (frontmatter 指定。Skill ツール経由起動では効かないため、ユーザーが直接起動する) |
| 実装 | `dev-impl-implementer` subagent | `model: "opus"` 明示 |
| レビュー | `review-impl` subagent | `model: "opus"` 明示 |
| 巨大出力のテスト実行 (E2E 等) | subagent | `model: "haiku"` (`rules/core/orchestration.md`「委譲の判断」) |

## Step 0: 前提チェック

```bash
REPO_DIR=$(git rev-parse --show-toplevel)
REPO_SLUG=$(gh repo view --json nameWithOwner -q .nameWithOwner)
rg -n 'POC_NEEDED:.*blocker=true' docs/DESIGN.md docs/features/ 2>/dev/null
```

- git / gh が解決できない → 停止して案内する
- `POC_NEEDED: ... blocker=true` が 1 件以上 → 実装に入らず、`/dev-spec` のフェーズ 5 (PoC 検証) への差し戻しを案内して停止する (未検証の技術前提の上に実装しない)
- `docs/DESIGN.md` が無い構成でも、issue が自己完結していれば続行してよい (issue の DoD に実行コマンドが揃っていることが条件)

作業ログ用のディレクトリを作る: `SCRATCH=<scratchpad>/dev-impl-$(date +%Y%m%d-%H%M%S)` (report JSON の置き場。git 管理外)。

## Step 1: issue の収集と着手順

```bash
gh issue list --repo "$REPO_SLUG" --state open --label ready --json number,title,body --limit 200
gh issue list --repo "$REPO_SLUG" --state open --label in-progress --json number,title,body --limit 200
```

- `in-progress` が残っていれば前回の中断。その issue から再開する (ブランチが残っていれば続きから、無ければ最初から)
- 各 issue の `## 依存` 節から `Depends on #<番号>` を読み、トポロジカル順に並べる。依存先が open のままの issue は、依存先が close されるまで着手しない
- `needs-human` の issue は着手しない (人間の回答後、ユーザーがラベルを `ready` に戻して本スキルを再実行する)
- `$ARGUMENTS` で issue 番号が指定されていれば、その issue (と未完了の依存先) だけを対象にする

`tracking` ラベルの親 issue は実装対象にしない。

## Step 2: issue ごとの実装サイクル

対象 issue を依存順に 1 件ずつ、次のサイクルで消化する。

### 2.1 着手

```bash
gh issue edit "$N" --repo "$REPO_SLUG" --remove-label ready --add-label in-progress
gh issue comment "$N" --repo "$REPO_SLUG" --body "実装を開始します (dev-impl)"
git -C "$REPO_DIR" switch -c "issue-$N" "$(git -C "$REPO_DIR" remote show origin | sed -n 's/.*HEAD branch: //p')" 2>/dev/null || git -C "$REPO_DIR" switch "issue-$N"
```

ブランチはデフォルトブランチの最新から切る (依存先 issue の merge 結果を取り込むため、切る前に `git pull` する)。

### 2.2 実装 (implementer subagent)

```javascript
Agent({
  description: "issue #<N> の実装",
  subagent_type: "dev-impl-implementer",
  model: "opus",
  prompt: `mode: implement
repo_dir: <REPO_DIR>
issue_number: <N>
report_path: <SCRATCH>/impl-<N>.json`
})
```

報告 JSON の `status` で分岐する:

- `done` → 2.3 へ
- `escalate` (`contract_break` / `test_weakening_suspected` / `spec_insufficient`) → 2.6 のエスカレーションへ
- `failed` (`tests_failing`) → 2.6 へ (試行内容を issue コメントに残す)

### 2.3 レビュー (review-impl subagent、修正 ≤ 2 ラウンド)

`BASE_SHA` (2.1 でブランチを切った時点の commit) を控えてから起動する:

```javascript
Agent({
  description: "issue #<N> のレビュー",
  subagent_type: "review-impl",
  model: "opus",
  prompt: `repo_dir: <REPO_DIR>
base_sha: <BASE_SHA>
issue_number: <N>
focus: all
report_path: <SCRATCH>/review-<N>-r<ラウンド>.json`
})
```

findings の分岐:

- **high / medium が 0 件** → 2.4 へ (low は最終コメントに「報告のみ」として記載)
- **high / medium がある** → implementer を `mode: fix` (`findings_path` に review JSON を指定) で起動して修正させ、レビューを再実行する。**このループは最大 2 ラウンド (固定)**。2 ラウンド後も high が残る → 2.6 へ
- **`category: test-weakening` の finding** → implementer に直させず親が裁定する: 弱体化が事実なら該当テストを基準時点の強度に戻す修正だけを親が直接行い (最小差分)、誤検出なら根拠を review JSON に追記して次へ進む

### 2.4 コミット・PR・merge

1. **コミット** (親が実行): 変更を論理単位で Conventional Commit (`rules/core/commit.md`。STRUCTURAL / BEHAVIORAL 分離) にする。implementer の `docs_updates` (乖離補正) も同じ issue のコミットに含める
2. **全体テスト**: プロジェクトのテストスイート全体と lint を実行し green を確認する (巨大出力になる場合は Haiku subagent に実行だけ委譲し、pass/fail 件数と失敗の要点を受け取る)
3. **PR**: `git push -u origin "issue-$N"` してから作成する。本文は issue リンクとレビュー結果の要約:

```bash
gh pr create --repo "$REPO_SLUG" --title "<issue タイトル>" --body "$(cat <<'EOF'
Closes #<N>

## 変更の要約
<implementer の summary>

## 検証
- テスト: <全体テストの結果 (passed/failed 件数)>
- レビュー: review-impl <ラウンド数> 周、high/medium 0 件 (low <k> 件は issue コメント参照)
- DoD: 下記で実行

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

4. **DoD のローカル実行 → merge**: issue の `## DoD` のコマンドを PR ブランチ上でそのまま実行し、**全て exit code 0 であることを確認してから** merge する (CI は使わない — 判定はこのローカル実行が兼ねる):

```bash
gh pr merge --repo "$REPO_SLUG" --squash --delete-branch
```

DoD が 1 つでも失敗したら merge しない → 2.6 へ。

### 2.5 完了処理

merge により `Closes #N` で issue は自動 close される (されていなければ `gh issue close` する)。完了コメントを 1 件残す:

```
実装完了 (dev-impl)
- 変更: <summary と主要ファイル>
- テスト: <件数>、DoD: green
- レビュー: <ラウンド数> 周 (low の報告: <あれば列挙、なければ「なし」>)
- 設計判断・docs 更新: <design_decisions / docs_updates の要約、なければ「なし」>
```

次の issue へ進む (Step 2 の先頭へ)。

### 2.6 エスカレーション (needs-human 駐車)

解消できない issue (2 ラウンド後の high 残存 / `escalate` / DoD 失敗 / テスト red) は:

```bash
gh issue edit "$N" --repo "$REPO_SLUG" --remove-label in-progress --add-label needs-human
gh issue comment "$N" --repo "$REPO_SLUG" --body "<状況: 何を試し、何が残っているか。人間に決めてほしいこと。ブランチ issue-$N は未 merge のまま残置>"
```

ブランチは merge せず残す (人間が差分を確認できるように)。**その issue に依存しない次の issue へ進む。**

**run 全体を停止するのは次の 2 つだけ**: (1) 残りの全 issue が未解消 issue に依存してブロックされた (2) `contract_break` の内容が後続 issue の前提を崩し、進めるとやり直しになる。停止時は未解消 issue の一覧と理由をまとめて報告する。

## Step 3: 終了処理

1. 対象 issue がすべて closed になったら、親 issue (`tracking`) の全子が closed か確認し、全て closed なら親を close する:

```bash
gh api --paginate "repos/$REPO_SLUG/issues/$PARENT_NUM/sub_issues?per_page=100" --jq '.[] | select(.state == "open") | .number'
# 0 件なら: gh issue close "$PARENT_NUM" --repo "$REPO_SLUG" --comment "全 issue の実装が完了したため close する"
```

2. 最終報告 (会話で 1 回だけ。レポート文書は作らない):
   - 実装した issue と PR の一覧
   - `needs-human` で駐車した issue と、人間がすべき決定
   - 実装中の設計判断・docs 更新の要約

## エスカレーション回答後の再開

人間が `needs-human` の issue に回答したら、ラベルを `ready` に戻して本スキルを再実行する。Step 1 の収集が駐車 issue を拾い直し、残置ブランチがあれば続きから実装する。

## 参照ルール

- コミット規約: `rules/core/commit.md` / 委譲の判断: `rules/core/orchestration.md`
- implementer・review-impl の入出力契約は各 agent 定義 (`claude/agents/dev-impl-implementer.md` / `review-impl.md`) が正本

## 関連スキル・エージェント

- **dev-spec**: 上流の設計ループ。issue の生成元
- **dev-impl-implementer** (subagent): 実装の葉。issue と docs を直読する
- **review-impl** (subagent): 統合レビュワー (テスト品質 / 設計準拠 / コード品質 / E2E)
