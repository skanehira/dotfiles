---
name: dev-impl
description: 実装ループ。/dev-spec が作成した GitHub issue (ゴール / 設計参照 / DoD / 非スコープ / 依存の thin 構成) を入力に、依存順に 1 件ずつ「implementer subagent → 統合レビュー → 修正 ≤2 ラウンド → PR → DoD ローカル実行 → merge → close」で自律実装するオーケストレーター。進捗は issue コメントに残し、詰まった issue は needs-human で駐車して次へ進む。人間の介入はエスカレーション時のみ。issue 作成後にユーザーが直接起動し、エスカレーション回答後の再開も本スキルの再実行で行う。「実装ループを開始」「issue を順に実装して」「残りタスクを自動で実装」などで起動。
argument-hint: "[issue 番号の絞り込み、省略時は ready 全件]"
model: opus
allowed-tools: Read, Edit, Write, Glob, Grep, Bash, Agent
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
| コミット実行・巨大出力のテスト実行 (E2E 等) | subagent | `model: "haiku"` (`~/.claude/rules/core/orchestration.md`「委譲の判断」。メッセージ起草・対象ファイルの判断は親が行い、実行だけを委譲する) |

## Step 0: 前提チェック

```bash
REPO_DIR=$(git rev-parse --show-toplevel)
REPO_SLUG=$(gh repo view --json nameWithOwner -q .nameWithOwner)
DEFAULT=$(git symbolic-ref --short refs/remotes/origin/HEAD | sed 's|origin/||')
rg -n 'POC_NEEDED:.*blocker=true' docs/DESIGN.md docs/features/ 2>/dev/null
```

- git / gh が解決できない → 停止して案内する
- `POC_NEEDED: ... blocker=true` が 1 件以上 → 実装に入らず、`/dev-spec` のフェーズ 5 (PoC 検証) への差し戻しを案内して停止する (未検証の技術前提の上に実装しない)
- ラベル 4 種を冪等に用意する (dev-spec を経ずに用意された issue でも 2.1 のラベル操作が失敗しないように。コマンドは `~/.claude/skills/dev-spec/references/issue-template.md`「ラベルの用意」と同一)
- **docs が push 済みか確認する**: ローカルに `docs/DESIGN.md` があるのに `git log origin/$DEFAULT -1 -- docs/` が空なら、ブランチ基点 (origin) に設計 docs が無い。docs を含むコミットの push を人間に依頼して停止する (2.1 のブランチは origin から切るため、push されていないと implementer が docs を読めない)
- `docs/DESIGN.md` が無い構成でも、issue が自己完結していれば続行してよい (issue の DoD に実行コマンドが揃っていることが条件)

作業ログ用のディレクトリを作る: `SCRATCH=<scratchpad>/dev-impl-$(date +%Y%m%d-%H%M%S)` (report JSON の置き場。git 管理外)。

## Step 1: issue の収集と着手順

```bash
gh issue list --repo "$REPO_SLUG" --state open --label ready --json number,title,body --limit 200
gh issue list --repo "$REPO_SLUG" --state open --label in-progress --json number,title,body --limit 200
```

取得件数が limit に達したら limit を上げて再取得する (無音の取りこぼしは実装漏れになる)。

- 各 issue の `## 依存` 節から `Depends on #<番号>` を読み、トポロジカル順に並べる。依存先が open のままの issue は、依存先が close されるまで着手しない
- `needs-human` の issue は着手しない
- `$ARGUMENTS` で issue 番号が指定されていれば、その issue (と未完了の依存先) だけを対象にする
- `tracking` ラベルの親 issue は実装対象にしない

**`in-progress` が残っている、または対象 issue に残置ブランチ `issue-<N>` がある場合は前回の中断・駐車からの復帰。** その issue の状態を確認して再開位置を決める (needs-human から `ready` に戻された issue はラベルでは区別できないため、ブランチの有無で検出する):

| 状態 (`gh pr list --repo "$REPO_SLUG" --head issue-<N>` と `git branch --list issue-<N>`) | 再開位置 |
| --- | --- |
| PR が open | 2.4 の DoD 実行 → merge から (PR は再作成しない)。レビュー未実施が疑われる場合は 2.3 から |
| ブランチのみ残存 (PR なし) | ブランチへ switch し、`BASE_SHA=$(git merge-base origin/$DEFAULT HEAD)` で基準を復元して 2.2 から。implementer の prompt に「ブランチに前回の差分がある。既存差分を前提に続きから実装せよ」を 1 行追加する |
| どちらも無い | 最初から (2.1 から) |

## Step 2: issue ごとの実装サイクル

対象 issue を依存順に 1 件ずつ、次のサイクルで消化する。

### 2.1 着手

1. `git -C "$REPO_DIR" status --porcelain` が空であることを確認する。残骸があれば停止して人間に報告する (前作業の未コミット差分の上に実装しない)
2. ブランチを origin のデフォルトブランチ最新から切り、基準 SHA を控える:

```bash
git -C "$REPO_DIR" fetch origin
git -C "$REPO_DIR" switch -c "issue-$N" "origin/$DEFAULT"
BASE_SHA=$(git -C "$REPO_DIR" rev-parse HEAD)
```

3. switch が成功してからラベルとコメントを更新する (先にラベルを変えると、switch 失敗時に `in-progress` だけが残る):

```bash
gh issue edit "$N" --repo "$REPO_SLUG" --remove-label ready --add-label in-progress
gh issue comment "$N" --repo "$REPO_SLUG" --body "実装を開始します (dev-impl)"
```

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

**検収**: report JSON を読み、`status: done` は `test_result.exit_code = 0`・`dod_result.exit_code = 0`・`self_review.checklist_applied = true` を満たすときだけ done と扱う (満たさない報告は失敗ブリーフとして `mode: fix` で差し戻す)。

分岐:

- `done` (検収済み) → 2.3 へ
- `escalate` / `failed` (`contract_break` / `spec_insufficient` / `tests_failing`。`test_weakening_suspected` は fix 時のみ発生) → 2.6 へ (report の summary にある試行記録を issue コメントに使う)
- **subagent がエラー、または report JSON が無い・パース不能** → 同条件で 1 回だけ再起動する。再失敗なら 2.6 へ

### 2.3 レビュー (review-impl subagent、修正 ≤ 2 ラウンド)

```javascript
Agent({
  description: "issue #<N> のレビュー",
  subagent_type: "review-impl",
  model: "opus",
  prompt: `repo_dir: <REPO_DIR>
base_sha: <BASE_SHA>       // 2.1 で控えた値
issue_number: <N>
focus: all
report_path: <SCRATCH>/review-<N>-r<ラウンド>.json`
})
```

**`checked` の検収**: findings の件数を見る前に `checked` を確認する。`tests_run: false`、または UI に触れる差分なのに `e2e` が理由の無い `skipped` なら、その検査は成立していない — 指示を明確化して 1 回再実行し、再発なら 2.6 へ (「何も検出できない検証の実行は検証ではない」)。review JSON が無い・パース不能の場合も同様に 1 回再起動 → 再失敗で 2.6。

findings の分岐:

- **high / medium が 0 件** → 2.4 へ (low は完了コメントに「報告のみ」として記載)
- **high / medium がある** → implementer を `mode: fix` (`findings_path` に review JSON を指定) で起動して修正させ、レビューを再実行する。**このループは最大 2 ラウンド (固定)**。2 ラウンド後に **high が残る → 2.6**。**medium だけが残る → low と同様に報告のみとして 2.4 へ進む**
- **`category: test-weakening` の finding** → implementer に直させず親が裁定する: 弱体化が事実なら該当テストを基準時点の強度に戻す修正だけを親が直接行う (最小差分。再レビューは不要 — 2.4 の全体テストが検証する。ラウンド数にも数えない)。誤検出なら根拠を review JSON に追記して次へ進む

### 2.4 コミット・PR・merge

1. **コミット**: 変更を論理単位で Conventional Commit (`~/.claude/rules/core/commit.md`。STRUCTURAL / BEHAVIORAL 分離) にする。メッセージ起草とステージ対象の決定は親、実行は Haiku subagent に委譲してよい (モデル方針の表)。implementer の `docs_updates` (乖離補正) も同じ issue のコミットに含める
2. **全体テスト**: プロジェクトのテストスイート全体と lint を実行し green を確認する (巨大出力になる場合は Haiku subagent に実行だけ委譲し、pass/fail 件数と失敗の要点を受け取る)
3. **PR**: `git push -u origin "issue-$N"` してから作成する (再開で PR が既にあればスキップ)。push が失敗したら (前 run の同名 remote ブランチ残骸等)、原因を確認して解消できなければ 2.6 へ:

```bash
gh pr create --repo "$REPO_SLUG" --title "<issue タイトル>" --body "$(cat <<'EOF'
Closes #<N>

## 変更の要約
<implementer の summary>

## 検証
- テスト: <全体テストの結果 (passed/failed 件数)>
- レビュー: review-impl <ラウンド数> 周、high/medium 0 件 (low <k> 件は merge 後の issue コメントに記載)
- DoD: merge 前にローカルで全コマンドを実行し、green を確認してから merge する

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

4. **DoD のローカル実行 → merge**: issue の `## DoD` のコマンドを PR ブランチ上でそのまま実行し、**全て exit code 0 であることを確認してから** merge する (CI は使わない — 判定はこのローカル実行が兼ねる)。DoD が 1 つでも失敗したら merge しない → 2.6 へ:

```bash
gh pr merge --repo "$REPO_SLUG" --squash --delete-branch
```

merge がコンフリクトで失敗したら (駐車 → 再開の間にデフォルトブランチが進んだ場合)、`git rebase origin/$DEFAULT` を試み、全体テスト green を確認して push し直す。解消できなければ 2.6 へ。

### 2.5 完了処理

merge により `Closes #N` で issue は自動 close される (されていなければ `gh issue close` する)。完了コメントを 1 件残す:

```
実装完了 (dev-impl)
- 変更: <summary と主要ファイル>
- テスト: <2.4 の全体テストの件数>、DoD: green
- レビュー: <ラウンド数> 周 (low の報告: <あれば列挙、なければ「なし」>)
- 設計判断・docs 更新: <design_decisions / docs_updates の要約、なければ「なし」>
```

次の issue へ進む (Step 2 の先頭へ)。

### 2.6 エスカレーション (needs-human 駐車)

解消できない issue (2 ラウンド後の high 残存 / `escalate` / DoD 失敗 / テスト red / subagent の再失敗 / push・merge の解消不能) は:

```bash
gh issue edit "$N" --repo "$REPO_SLUG" --remove-label in-progress --add-label needs-human
gh issue comment "$N" --repo "$REPO_SLUG" --body "<状況: 何を試し、何が起き、何が残っているか (implementer の summary の試行記録を含める)。人間に決めてほしいこと。ブランチ issue-$N (と PR があれば PR) は未 merge のまま残置>"
```

ブランチと open PR は merge せず残す (人間が差分を確認でき、再開時に再利用できる)。**その issue に依存しない次の issue へ進む。**

**run 全体を停止するのは次の 2 つだけ**: (1) 残りの全 issue が未解消 issue に依存してブロックされた (2) `contract_break` の内容が後続 issue の前提を崩し、進めるとやり直しになる。停止時は未解消 issue の一覧と理由をまとめて報告する。

## Step 3: 終了処理

1. 対象 issue がすべて closed になったら、親 issue を特定して全子の完了を確認し、全て closed なら親を close する:

```bash
PARENT_NUM=$(gh issue list --repo "$REPO_SLUG" --state open --label tracking --json number --jq '.[].number')
# 複数ヒットしたらタイトルで特定し、特定できなければ人間に確認する
gh api --paginate "repos/$REPO_SLUG/issues/$PARENT_NUM/sub_issues?per_page=100" --jq '.[] | select(.state == "open") | .number'
# 0 件なら: gh issue close "$PARENT_NUM" --repo "$REPO_SLUG" --comment "全 issue の実装が完了したため close する"
```

2. 最終報告 (会話で 1 回だけ。レポート文書は作らない):
   - 実装した issue と PR の一覧
   - `needs-human` で駐車した issue と、人間がすべき決定
   - 実装中の設計判断・docs 更新の要約

## エスカレーション回答後の再開

人間が `needs-human` の issue に回答したら、**回答の内容を issue 本文 (該当節の書き換え) または参照 docs に反映してから**、ラベルを `ready` に戻して本スキルを再実行する — implementer は issue 本文と docs しか読まないため、コメントに書かれただけの回答は実装に届かない。docs 側を変えた場合は push も行う (Step 0 の確認に掛かる)。Step 1 の収集が駐車 issue を拾い直し、残置ブランチ・PR があれば続きから実装する。

## 参照ルール

- コミット規約: `~/.claude/rules/core/commit.md` / 委譲の判断: `~/.claude/rules/core/orchestration.md`
- implementer・review-impl の入出力契約は各 agent 定義 (`~/.claude/agents/dev-impl-implementer.md` / `review-impl.md`) が正本

## 関連スキル・エージェント

- **dev-spec**: 上流の設計ループ。issue の生成元
- **dev-impl-implementer** (subagent): 実装の葉。issue と docs を直読する
- **review-impl** (subagent): 統合レビュワー (テスト品質 / 設計準拠 / コード品質 / E2E)
