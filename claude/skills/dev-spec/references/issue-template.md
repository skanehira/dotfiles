# issue テンプレートと作成手順 (dev-spec フェーズ 9〜10)

- 種別: テンプレート + 手順書
- 生成者: dev-spec フェーズ 9 (ドラフト)・フェーズ 10 (issue 作成)
- 消費者: dev-spec フェーズ 9 (ドラフト作成・ドラフトチェック)、フェーズ 10 (issue 作成)、`/dev-impl` (子 issue を読んで実装)、人間 (issue 単体で作業に着手する)

**issue の情報設計の基準は「人間が issue 本文 + 参照 docs だけで実装に着手できるか」。** AI (dev-impl) はその部分集合しか要らないので、この基準を満たせば両方が読める。

## ラベル (4 種)

| ラベル | 意味 | 付与者 |
| --- | --- | --- |
| `ready` | 着手可能 (作成時の既定) | dev-spec フェーズ 10 |
| `in-progress` | dev-impl が実装中 | dev-impl (着手時) |
| `needs-human` | 人間の判断待ちで駐車中 | dev-impl (エスカレーション時) |
| `tracking` | トラッキング用の親 issue。実装対象ではない | dev-spec フェーズ 10 |

親 issue にライフサイクルラベル (`ready` / `in-progress` / `needs-human`) を付けない — 付けると dev-impl が親を実装対象として拾う。

## 子 issue テンプレート

タイトルは作業内容が分かる平叙文 (例: `エクスポート機能の書き出し API を実装する`)。再実行の突き合わせがタイトル一致で行われるため、作成後に整形して変えない。

```markdown
## ゴール
<この issue で何ができるようになるか (1〜3 行)。対応 UC があれば「UC-<n>: <名前>」を明記>

## 設計
docs/design/features/<機能名>.md 参照
<横断事項 (スキーマ・API 規約・認証など) に触れる場合は「docs/design/DESIGN.md「<節名>」」も併記。設計本文は転記しない — 正本は docs 側で、issue は参照のみ>

## DoD
<実行可能なコマンドと期待結果。実行方法の前提 (セットアップ・起動) は DESIGN.md「開発・検証コマンド」に置き、ここでは繰り返さない。例:
- `deno test src/export/` が green
- `npm run lint` が warning 0>

## 非スコープ
<隣接するがこの issue ではやらないこと>

## 依存
Depends on #<番号>
<依存が無ければ「依存なし」と書く。dev-impl はこの行で着手順を決める>
```

## 親 issue テンプレート

親は run 全体で 1 件。タイトルは `<タスク名> トラッキング`。どの issue 群が完了するとどの UC が満たされるかを一覧できるのが存在意義。

```markdown
## 設計
docs/design/DESIGN.md 参照

## ユースケースと issue の対応
### UC-<n>: <ユースケース名>
- #<番号> <タイトル>
### 基盤 (UC に属さない作業)
- #<番号> <タイトル>

## 進捗
残件はこの issue の Sub-issues セクション (進捗バーと子の一覧) を見る。子 issue の close は /dev-impl が行い、全子完了時に本 issue も /dev-impl が close する。
```

USECASES.md が無い構成 (クイックモード) では「ユースケースと issue の対応」を「issue 一覧」に読み替え、グルーピングせず列挙する。

## ドラフトチェックのチェックリスト (フェーズ 9 のドラフトチェック)

fresh context の検査 subagent に、親 + 子の全ドラフトを一括で渡して検査させる観点:

1. **自己完結性**: 人間が issue 本文と参照 docs だけで着手できるか。会話の文脈にしか無い前提が紛れていないか
2. **DoD の実行可能性と空虚性**: DoD が実行可能なコマンドか。対象が未実装でも通る DoD (存在チェックだけ・恒真の grep 等) になっていないか
3. **依存の整合**: 依存グラフに循環が無いか。「依存なし」の issue が実は他 issue の成果物を前提にしていないか
4. **相互の重複・漏れ**: 同じ作業が複数 issue に跨っていないか。機能設計書の「実装の配置」に現れるファイルがどの issue にも属さず漏れていないか
5. **参照の実在**: 参照する docs パス・節名・UC 名が実在するか

## issue 作成手順 (フェーズ 10)

### 前提条件

```bash
REPO_SLUG=$(gh repo view --json nameWithOwner -q .nameWithOwner)
```

失敗する (git リポジトリでない / GitHub リモートが無い / `gh` 未認証) なら停止し、「リポジトリを用意してから再実行してください」と案内する。作れないまま成功したように振る舞わない。

### ラベルの用意 (冪等)

```bash
gh label create ready       --force --color 0E8A16 --description "着手可能"
gh label create in-progress --force --color 1D76DB --description "dev-impl が実装中"
gh label create needs-human --force --color D93F0B --description "人間の判断待ちで駐車中"
gh label create tracking    --force --color 5319E7 --description "トラッキング用の親 issue。実装対象ではない"
```

### 既存 issue との突き合わせ (再実行の冪等化)

```bash
gh issue list --repo "$REPO_SLUG" --state all --limit 200 --json number,title,state,labels
```

取得件数が limit に達したら limit を上げて再取得する (無音の取りこぼしは重複作成になる)。

| 既存 issue の状態 | 動作 |
| --- | --- |
| 同タイトルが無い | 新規作成 |
| タイトル一致・open | 本文を比較し、不一致なら `gh issue edit <番号> --body-file` で貼り直す。`in-progress` の issue を書き換えたときは issue コメントで改訂を告知する |
| タイトル一致・closed | 触らない。本文が現ドラフトと不一致ならその番号を最終報告に列挙する (完了済み issue に改訂が届かないことを人間が把握できるように) |

本文比較はコマンド置換 (`$(...)`) を使わずファイルに落として `cmp` する (末尾改行の欠落を検出するため。`~/.claude/rules/core/verification.md`)。取得側の `sed 's/\r$//'` は CRLF 除去 (GitHub web UI で編集された本文対策)。`gh` の出力はファイル末尾に改行 1 つが付くため、ドラフト側もファイル末尾を改行 1 つで終える形で Write する (毎回不一致になるときはまず末尾改行の差を疑う):

```bash
gh issue view "$ISSUE_NUM" --repo "$REPO_SLUG" --json body -q .body | sed 's/\r$//' > <scratchpad>/issue-current.md
cmp -s <scratchpad>/issue-current.md <scratchpad>/issue-body.md || \
  gh issue edit "$ISSUE_NUM" --repo "$REPO_SLUG" --body-file <scratchpad>/issue-body.md
```

### 親 issue の作成と特定

`tracking` ラベルの open issue を探し、あればそれを親として使う。無ければ作成する。複数見つかったらタイトルで特定し、特定できなければ人間に確認する:

```bash
gh issue list --repo "$REPO_SLUG" --state open --label tracking --json number,title
PARENT_URL=$(gh issue create --repo "$REPO_SLUG" --title "$PARENT_TITLE" --body-file <scratchpad>/parent-body.md --label tracking)
PARENT_NUM=$(printf '%s' "$PARENT_URL" | grep -o '[0-9]*$')
```

closed の親に新しい子を紐付けることになったら (完了後の設計改訂で issue が増えた場合)、先に reopen する:

```bash
[ "$(gh issue view "$PARENT_NUM" --repo "$REPO_SLUG" --json state -q .state)" = "CLOSED" ] && \
  gh issue reopen "$PARENT_NUM" --repo "$REPO_SLUG" --comment "issue が追加されたため再オープンする"
```

### 子 issue の作成

依存の前方参照を避けるため、依存グラフの上流から順に 1 件ずつ作る (依存先の番号が常に確定済みになる)。本文は Write ツールで `<scratchpad>/issue-body.md` に書き出してから渡す:

```bash
ISSUE_URL=$(gh issue create --repo "$REPO_SLUG" --title "$TITLE" --body-file <scratchpad>/issue-body.md --label ready)
ISSUE_NUM=$(printf '%s' "$ISSUE_URL" | grep -o '[0-9]*$')
```

`gh issue create` が返すのは URL であり番号ではない。`Depends on #<番号>` の解決用に「タイトル → 番号」の対応表を作りながら進め、再実行時は突き合わせで得た既存 issue の番号を先に対応表へ seed する (しないと依存が解決できない)。

### 親への紐付け (GitHub sub-issues API)

**対象は全子 issue であり、今回新規作成した分だけではない** (前回の run が作成直後に落ちていると、既存の子が未紐付けのまま残る)。まず紐付け済みの子を seed する:

```bash
gh api --paginate "repos/$REPO_SLUG/issues/$PARENT_NUM/sub_issues?per_page=100" --jq '.[].number'
```

`--paginate` と `per_page=100` を省かない — このエンドポイントの既定は 1 ページ 30 件で、31 件目以降が見えず二重紐付けの 422 を踏む。seed に無い子だけを紐付ける:

```bash
CHILD_ID=$(gh api "repos/$REPO_SLUG/issues/$ISSUE_NUM" --jq .id)
gh api "repos/$REPO_SLUG/issues/$PARENT_NUM/sub_issues" -F sub_issue_id="$CHILD_ID"
```

実測で確定した挙動 (使い捨てリポジトリで検証済み):

| 項目 | 挙動 |
| --- | --- |
| パラメータの型 | `-F` (integer) が必須。`-f` (文字列) は `is not of type integer` で HTTP 422。id は `gh api repos/.../issues/<番号> --jq .id` の numeric id (`gh issue view --json id` が返す `I_kwDO...` 形式の node ID は使えない) |
| 二重紐付け | HTTP 422。メッセージが単一親制約の違反と共通なので、事後に握りつぶさず seed による事前判定で避ける |
| 親の貼り替え | 別の親に紐付いている子は `-F replace_parent=true` を追加して貼り替える (旧構成の親から移行する場合のみ) |

紐付けに失敗したら停止して人間に伝える: 作成済みの子 issue 番号、未紐付けの組、復旧は本フェーズの再実行で行えること (突き合わせと seed が続きから紐付ける)。

### 親 issue 本文の確定

子 issue の番号は作成するまで確定しないため、親を先に作る際の本文は「ユースケースと issue の対応」を `(子 issue の作成後に確定)` のプレースホルダにしてよい。**全子の作成・紐付けが終わったら、「タイトル → 番号」の対応表から親テンプレートの本文を再生成し、突き合わせと同じ cmp → `gh issue edit "$PARENT_NUM" --body-file` で更新する。** この再生成は再実行でも冪等に働く (子が増減すれば本文不一致として検出される)。

### 最終報告

- 子 issue: 新規作成件数 / 本文更新件数 / スキップ件数
- 親 issue: 番号とタイトル (`#12 <タスク名> トラッキング` の形式)
- closed だが本文不一致の issue 番号 (あれば)
