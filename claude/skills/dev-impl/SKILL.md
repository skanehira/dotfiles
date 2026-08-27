---
name: dev-impl
description: 実装ループ。/dev-spec が作成した GitHub issue (ゴール / 設計参照 / DoD / 非スコープ / 依存の thin 構成) を入力に、依存順に 1 件ずつ「implementer subagent → 統合レビュー → 修正 ≤2 ラウンド → PR → DoD ローカル実行 → merge → close」で自律実装するオーケストレーター。子が全完了した親 (tracking) issue はその場で close し、取りこぼしは run 終了時に回収する。進捗は issue コメントに残し、詰まった issue は needs-human で駐車して次へ進む。人間の介入はエスカレーション時のみ。issue 作成後にユーザーが直接起動し、エスカレーション回答後の再開も本スキルの再実行で行う。「実装ループを開始」「issue を順に実装して」「残りタスクを自動で実装」などで起動。
argument-hint: "[issue 番号の絞り込み、省略時は ready 全件]"
model: opus
allowed-tools: Read, Edit, Write, Glob, Grep, Bash, Agent
---

# dev-impl — 実装ループ

`ready` ラベルの open issue を依存順に最後まで自律的に実装するオーケストレーター。実装の指示はすべて issue 本文と参照 docs (docs/design/DESIGN.md / docs/design/features/) から取る — **issue が自己完結しているので、親が文脈を編纂して渡すことはしない**。

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
rg -n 'POC_NEEDED:.*blocker=true' docs/design/DESIGN.md docs/design/features/ 2>/dev/null
```

- git / gh が解決できない → 停止して案内する
- `POC_NEEDED: ... blocker=true` が 1 件以上 → 実装に入らず、`/dev-spec` のフェーズ 5 (PoC 検証) への差し戻しを案内して停止する (未検証の技術前提の上に実装しない)
- ラベル 4 種を冪等に用意する (dev-spec を経ずに用意された issue でも 2.1 のラベル操作が失敗しないように。コマンドは `~/.claude/skills/dev-spec/references/issue-template.md`「ラベルの用意」と同一)
- **docs が push 済みか確認する**: ローカルに `docs/design/DESIGN.md` があるのに `git log origin/$DEFAULT -1 -- docs/design/DESIGN.md docs/design/features/` が空なら、ブランチ基点 (origin) に設計 docs が無い。docs を含むコミットの push を人間に依頼して停止する (2.1 のブランチは origin から切るため、push されていないと implementer が docs を読めない)
- `docs/design/DESIGN.md` が無い構成でも、issue が自己完結していれば続行してよい (issue の DoD に実行コマンドが揃っていることが条件)

作業ログ用のディレクトリを作る: `SCRATCH=<scratchpad>/dev-impl-$(date +%Y%m%d-%H%M%S)` (report JSON の置き場。git 管理外)。保留レビュー項目のチェックリストは **`docs/PENDING_REVIEW.html`** に置く (リポジトリ内。issue のコミットに含めて merge されるため、別マシン・別セッション・後続 run にも引き継がれる。追記は 2.3、確認案内は Step 3)。

## Step 1: issue の収集と着手順

```bash
gh issue list --repo "$REPO_SLUG" --state open --label ready --json number,title,body --limit 200
gh issue list --repo "$REPO_SLUG" --state open --label in-progress --json number,title,body --limit 200
```

取得件数が limit に達したら limit を上げて再取得する (無音の取りこぼしは実装漏れになる)。

- 各 issue の `## 依存` 節から `Depends on #<番号>` を読み、トポロジカル順に並べる。依存先が open のままの issue は、依存先が close されるまで着手しない
- `needs-human` の issue は着手しない
- `$ARGUMENTS` で issue 番号が指定されていれば、その issue (と未完了の依存先) だけを対象にする
- `tracking` ラベルの親 issue (ユースケース単位のトラッキング) は実装対象にしない

**`in-progress` が残っている、または対象 issue に残置ブランチ `issue-<N>` がある場合は前回の中断・駐車からの復帰。** その issue の状態を確認して再開位置を決める (needs-human から `ready` に戻された issue はラベルでは区別できないため、ブランチの有無で検出する):

| 状態 (`gh pr list --repo "$REPO_SLUG" --head issue-<N>` と、`git fetch origin` 後の `git branch --list issue-<N>` / `git branch -r --list "origin/issue-<N>"`) | 再開位置 |
| --- | --- |
| PR が open | 2.4 の DoD 実行 → merge から (PR は再作成しない)。レビュー未実施が疑われる場合は 2.3 から |
| ブランチのみ残存 (ローカルまたは origin、PR なし) | ブランチへ switch し (origin のみに在る場合は `git switch issue-<N>` が追跡ブランチを作る)、`BASE_SHA=$(git merge-base origin/$DEFAULT HEAD)` で基準を復元して 2.2 から。implementer の prompt に「ブランチに前回の差分がある。既存差分を前提に続きから実装せよ」を 1 行追加する |
| どちらも無い | 最初から (2.1 から) |

実装途中の**未コミット**差分はマシンローカルで、別マシンには引き継げない。ブランチも push されるまではマシンローカル (2.6 の駐車時は WIP を退避して push を試みる)。別マシンで再開して残置ブランチが origin に無い場合、その issue は最初からやり直しになる — これは仕様で、issue 単位が再開の粒度である。ローカルと origin の両方にブランチが在る場合は fetch 後に ahead/behind を確認し、behind ならローカルを origin に合わせ (`git switch -C "issue-<N>" "origin/issue-<N>"`)、ahead なら push してから続行する。

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
- **high / medium がある** → implementer を `mode: fix` (`findings_path` に review JSON を指定) で起動して修正させ、レビューを再実行する。**このループは最大 2 ラウンド (固定)**。2 ラウンド後に **high が残る → 2.6**。**medium だけが残る → `docs/PENDING_REVIEW.html` に追記して 2.4 へ進む** (下記「保留レビュー項目の記録」)
- **`category: test-weakening` の finding** → implementer に直させず親が裁定する: 弱体化が事実なら該当テストを基準時点の強度に戻す修正だけを親が直接行う (最小差分。再レビューは不要 — 2.4 の全体テストが検証する。ラウンド数にも数えない)。誤検出なら根拠を review JSON に追記して次へ進む

#### 保留レビュー項目の記録

2 ラウンドで解消しなかった medium は、これ以上修正もエスカレーションもせず**ユーザーの事後確認に回す**。`docs/PENDING_REVIEW.html` (無ければ作成) に issue ごとの節として追記する — 各 finding はチェックボックス付きの 1 項目で、severity / category / `file:line` / summary / evidence / fix_hint をまとめる。外部依存の無い自己完結の静的 HTML とし、全 issue が同じファイルに追記し続ける。issue ごとの節は issue 番号の見出しで分離し、rebase 等でこのファイルがコンフリクトしたら**両方の節を残す (union)** 解決にする。**追記分は 2.4 手順 1 で本 issue のコミットに含める** (`docs_updates` と同じ経路で merge され、リポジトリで持ち回られる)。

### 2.4 コミット・PR・merge

1. **コミット**: 変更を論理単位で Conventional Commit (`~/.claude/rules/core/commit.md`。STRUCTURAL / BEHAVIORAL 分離) にする。メッセージ起草とステージ対象の決定は親、実行は Haiku subagent に委譲してよい (モデル方針の表)。implementer の `docs_updates` (乖離補正) と、2.3 で追記した `docs/PENDING_REVIEW.html` も同じ issue の**コミット列**に含める (関心事分離に従い docs は独立コミットでよい)
2. **全体テスト**: プロジェクトのテストスイート全体と lint を実行し green を確認する (巨大出力になる場合は Haiku subagent に実行だけ委譲し、pass/fail 件数と失敗の要点を受け取る)
3. **PR**: `git push -u origin "issue-$N"` してから作成する (再開で PR が既にあればスキップ)。push が失敗したら (前 run の同名 remote ブランチ残骸等)、原因を確認して解消できなければ 2.6 へ:

```bash
gh pr create --repo "$REPO_SLUG" --title "<issue タイトル>" --body "$(cat <<'EOF'
Closes #<N>

## 変更の要約
<implementer の summary>

## 検証
- テスト: <全体テストの結果 (passed/failed 件数)>
- レビュー: review-impl <ラウンド数> 周、high 0 件 (low <k> 件・未解消 medium <m> 件は merge 後の issue コメントに記載。medium 0 件ならその旨)
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
- 未解消 medium: <各 1 行で `file:line` + summary。なければ「なし」> (evidence・fix_hint は `docs/PENDING_REVIEW.html` に記録)
- 設計判断・docs 更新: <design_decisions / docs_updates の要約、なければ「なし」>
```

親 (tracking issue) を逆引きし、その親の子が全て完了していれば親も close する。API の挙動の正本は `~/.claude/skills/dev-spec/references/issue-template.md`「親への紐付け」の実測表:

```bash
gh api "repos/$REPO_SLUG/issues/$N/parent" \
  --jq '"\(.number)\t\(.state)\t\(.sub_issues_summary.completed)/\(.sub_issues_summary.total)"' 2>&1
```

| 結果 | 動作 |
| --- | --- |
| 出力に `(HTTP 404)` を含む (親に紐付いていない子) | close はしない。**正常系** (`gh` は非ゼロで終了しエラー行を出すが、エラーとして扱わない)。ただし dev-spec の紐付け漏れの兆候なので、番号を控えて Step 3 の最終報告に載せる |
| `state` が open (小文字) かつ `completed == total` | close する |
| `completed < total` (残り子がある) | 親は open のまま次へ進む |
| それ以外の失敗 (403・5xx・`gh` が sub-issues API 非対応など) | 親 close をスキップし、番号を控えて Step 3 の最終報告に載せる (404 と同じ扱いに丸めない) |

```bash
gh issue close "<親番号>" --repo "$REPO_SLUG" --comment "この親 issue の sub-issue がすべて完了したため close する (dev-impl)"
```

`sub_issues_summary` は API 側が数える値なので、自前で子を列挙して数え直さない (取りこぼしによる誤 close を避ける)。merge 直後は `Closes #N` の自動 close が非同期で、最後の子でも `completed` が古い値のことがある — **再試行はしない**。取りこぼしは Step 3 の掃き掃除が回収する。

次の issue へ進む (Step 2 の先頭へ)。

### 2.6 エスカレーション (needs-human 駐車)

解消できない issue (2 ラウンド後の high 残存 / `escalate` / DoD 失敗 / テスト red / subagent の再失敗 / push・merge の解消不能) は、まず**未コミットの作業をブランチへ WIP コミットとして退避し、`git push -u origin "issue-$N"` を試みる** (push 失敗は続行してよいが、その場合ブランチはマシンローカルに残る旨を駐車コメントに書く)。コミット条件 (全テスト green) は merge されるコミットの規律であり、この退避コミットは merge しない駐車ブランチ上の記録なので例外とする — 退避しないと作業ツリーが dirty のまま残り、次の issue の 2.1 (clean チェック) と run 停止時の Step 3 (デフォルトブランチへの switch) が成立しない。退避後:

```bash
gh issue edit "$N" --repo "$REPO_SLUG" --remove-label in-progress --add-label needs-human
gh issue comment "$N" --repo "$REPO_SLUG" --body "<状況: 何を試し、何が起き、何が残っているか (implementer の summary の試行記録を含める)。未 merge の保留 medium があればその summary も列挙 (PENDING_REVIEW.html への追記が merge されていないため)。人間に決めてほしいこと。ブランチ issue-$N (と PR があれば PR) は未 merge のまま残置>"
```

ブランチと open PR は merge せず残す (人間が差分を確認でき、再開時に再利用できる)。**その issue に依存しない次の issue へ進む。**

**run 全体を停止するのは次の 2 つだけ**: (1) 残りの全 issue が未解消 issue に依存してブロックされた (2) `contract_break` の内容が後続 issue の前提を崩し、進めるとやり直しになる。停止時は未解消 issue の一覧と理由をまとめて報告する — このときも Step 3 の手順 2 (docs/PENDING_REVIEW.html の open と確認促し) を実行する (merge 済み issue の保留 medium を停止で失わない)。

## Step 3: 終了処理

1. **tracking issue の掃き掃除**: 2.5 の随時 close で取りこぼした親 (駐車していた issue が後から解消された場合や、過去 run が残した親) を回収する。open な `tracking` issue を全件走査し、子が 1 件以上あってその全てが完了しているものを close する。判定は 2.5 と同じく `sub_issues_summary` を使う (子を自前で列挙しない):

```bash
for P in $(gh issue list --repo "$REPO_SLUG" --state open --label tracking --limit 200 --json number --jq '.[].number'); do
  SUMMARY=$(gh api "repos/$REPO_SLUG/issues/$P" --jq '"\(.sub_issues_summary.completed) \(.sub_issues_summary.total)"') \
    || { echo "#$P 判定不能"; continue; }
  COMPLETED=${SUMMARY% *}; TOTAL=${SUMMARY#* }
  if [ "$TOTAL" -eq 0 ]; then
    echo "#$P 子ゼロ"
  elif [ "$COMPLETED" -eq "$TOTAL" ]; then
    gh issue close "$P" --repo "$REPO_SLUG" --comment "この親 issue の sub-issue がすべて完了したため close する (dev-impl)"
  else
    echo "#$P 子が残っている ($COMPLETED/$TOTAL)"
  fi
done
```

`TOTAL -eq 0` の分岐を外さない — 子が 1 件も紐付いていない親 (dev-spec の紐付けが途中で落ちた場合) まで close してしまうため。「子ゼロ」「子が残っている」「判定不能」の 3 種の出力をそのまま最終報告の 3 区分に使う。

**この走査は `tracking` ラベルの open issue を repo 全件対象にする。** dev-spec 由来でない手作りの `tracking` issue がある repo では、close 前に対象一覧を提示して人間に確認する。

2. デフォルトブランチへ戻って `git pull` し、`docs/PENDING_REVIEW.html` が存在すれば `open` で開いて (macOS。非 macOS ではパスを提示するだけでよい)、最終報告の先頭で「実装は完了したが、未解消 medium <n> 件のチェックが必要」とユーザーに確認を促す (過去 run の未消化分も累積している)。対応要と判断した項目は新しい issue にするか直接の修正依頼で対応し、確認が済んだ項目はユーザーがチェックリストから消す (手動編集または修正依頼。通常のコミットで反映)
3. 最終報告 (会話で 1 回だけ。run レポート文書は作らない):
   - 実装した issue と PR の一覧
   - close した親 (tracking) issue と、open のまま残した親 (子が残っている / 子ゼロ / 判定不能の別に)
   - 2.5 で親 close を判定できなかった子 issue の番号 (親に紐付いていない 404 の子と、API 失敗の子を分けて)
   - 保留レビュー項目 (未解消 medium) の件数とチェックリストのパス
   - `needs-human` で駐車した issue と、人間がすべき決定
   - 実装中の設計判断・docs 更新の要約

## エスカレーション回答後の再開

人間が `needs-human` の issue に回答したら、**回答の内容を issue 本文 (該当節の書き換え) または参照 docs に反映してから**、ラベルを `ready` に戻して本スキルを再実行する — implementer は issue 本文と docs しか読まないため、コメントに書かれただけの回答は実装に届かない。docs 側を変えた場合は push も行う (Step 0 の確認に掛かる)。Step 1 の収集が駐車 issue を拾い直し、残置ブランチ・PR があれば続きから実装する。チェックリスト (`docs/PENDING_REVIEW.html`) はリポジトリで持ち回るため、再開 run・別マシンでも累積した保留 medium がそのまま引き継がれる。

## 参照ルール

- コミット規約: `~/.claude/rules/core/commit.md` / 委譲の判断: `~/.claude/rules/core/orchestration.md`
- implementer・review-impl の入出力契約は各 agent 定義 (`~/.claude/agents/dev-impl-implementer.md` / `review-impl.md`) が正本

## 関連スキル・エージェント

- **dev-spec**: 上流の設計ループ。issue の生成元
- **dev-impl-implementer** (subagent): 実装の葉。issue と docs を直読する
- **review-impl** (subagent): 統合レビュワー (テスト品質 / 設計準拠 / コード品質 / E2E)
