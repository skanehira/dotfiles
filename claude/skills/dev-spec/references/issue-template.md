# issue テンプレートと作成手順 (dev-spec フェーズ 9〜10)

- 種別: テンプレート + 手順書
- 生成者: dev-spec フェーズ 9 (ドラフト)・フェーズ 10 (issue 作成)
- 消費者: dev-spec フェーズ 9 (ドラフト作成・ドラフトチェック)、フェーズ 10 (issue 作成)、`/dev-impl` (子 issue を読んで実装・親 issue を close)、人間 (issue 単体で作業に着手する)

**issue の情報設計の基準は「人間が issue 本文 + 参照 docs だけで実装に着手できるか」。** AI (dev-impl) はその部分集合しか要らないので、この基準を満たせば両方が読める。

## issue の階層 (2 階層)

```
UC-001: マスタと据置端末を整備する          ← 親 (tracking)。ユースケース 1 つ = 1 件
├─ マスタと据置端末の API・ドメインを実装する   ← 子 (ready)。実装の作業単位
└─ マスタ管理と据置端末管理の画面を実装する
基盤: UC に属さない共通実装                  ← 親 (tracking)。UC に属さない子の受け皿
├─ データスキーマと D1 マイグレーションを整備する
└─ 監査ログの追記基盤を作る
```

- **親 = ユースケース**。「どの UC がどこまで進んだか」を GitHub の Sub-issues セクション (進捗バー) で読めるのが存在意義
- **子 = 実装の作業単位**。1 issue = 独立して検証可能な 1 単位。`/dev-impl` が実装して close し、その親の子が全 closed になった時点で `/dev-impl` が親も close する
- 親は open のまま複数 run にまたがってよい (UC に子が後から足されることがある)
- run 全体を束ねる親は作らない。**例外は USECASES.md が無いクイックモード構成だけ** (下記「クイックモード構成」)

## ラベル (4 種)

| ラベル | 意味 | 付与者 |
| --- | --- | --- |
| `ready` | 着手可能 (子 issue の作成時の既定) | dev-spec フェーズ 10 |
| `in-progress` | dev-impl が実装中 | dev-impl (着手時) |
| `needs-human` | 人間の判断待ちで駐車中 | dev-impl (エスカレーション時) |
| `tracking` | 親 issue (トラッキング)。実装対象ではない | dev-spec フェーズ 10 |

親 issue にライフサイクルラベル (`ready` / `in-progress` / `needs-human`) を付けない — 付けると dev-impl が親を実装対象として拾う。

## 子 issue テンプレート

タイトルは作業内容が分かる平叙文 (例: `エクスポート機能の書き出し API を実装する`)。再実行の突き合わせがタイトル一致で行われるため、作成後に整形して変えない。

```markdown
## ゴール
対応 UC: <`UC-001: <名前>` 形式。複数 UC にまたがるなら `, ` 区切りで列挙する。どの UC にも属さない子は「基盤」と書く>
<この issue で何ができるようになるか (1〜3 行)>

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
<依存が無ければ「依存なし」と書く。dev-impl はこの行で着手順を決める。依存先は別の親に属する子でもよい (親をまたぐ依存は許容する)>
```

**「対応 UC」行は省略しない。** この行が子と親の対応づけの正本で、フェーズ 10 の紐付けとドラフトチェック観点 6 の照合がこれに依存する。複数列挙してよいのは、それらの UC を覆う統合親がある場合だけ (無ければ先頭の UC の親に紐付く)。

## 親 issue テンプレート (ユースケース単位)

USECASES.md の UC 1 件につき親 1 件を作る。**タイトルは USECASES.md の見出し表記をそのまま使う** (`## UC-001: マスタと据置端末を整備する` という見出しなら `UC-001: マスタと据置端末を整備する`)。突き合わせがタイトル一致なので、作成後に整形して変えない。

```markdown
## ユースケース
docs/design/USECASES.md「<UC の見出し>」参照

## 設計
docs/design/features/<機能名>.md 参照
<この UC を実現する機能設計書を列挙する。横断事項に触れるなら docs/design/DESIGN.md「<節名>」も併記>

## 完了の定義
この親の Sub-issues がすべて close されること。進捗バーと子の一覧は本 issue の Sub-issues セクションを見る。子 issue の close と、全子完了時の本 issue の close は /dev-impl が行う。
```

例外的に立てる親は 2 種類:

| 親 | タイトル | 立てる条件 |
| --- | --- | --- |
| 基盤 | `基盤: UC に属さない共通実装` (固定文字列) | どの UC にも属さない子 (スキーマ整備・監査ログ基盤・CI 整備など) が 1 件以上ある。「ユースケース」節は `該当なし (UC に属さない共通実装)` と書く |
| UC 統合 | `<UC 番号 1> / <UC 番号 2>: <見出し本文 1> と <見出し本文 2>` (例: `UC-004 / UC-005: 打刻する と 会場間を移動する`) | 2 つの UC が密結合で、子を分けても実装・検証の単位が分かれない。「ユースケース」節に両方の見出しを列挙する。**統合は 2 件までとし、3 件以上は統合せず親を分ける** (子側の「対応 UC」行で複数列挙する) |

**統合親のタイトルは上記の合成規則で機械的に導出する** (自由な要約名を付けない)。再実行の突き合わせがタイトル完全一致なので、名前が揺れると同じ UC 群に親が二重に作られる。合成規則の詳細: 「見出し本文」は USECASES.md の見出しから `UC-<番号>: ` を除いた部分、**並び順は UC 番号の昇順**。

### クイックモード構成 (USECASES.md が無い)

UC が存在しないため、親は `<タスク名> トラッキング` 1 件にフォールバックし、全子をそこに紐付ける。本文の「ユースケース」節は省き、「設計」節に DESIGN.md を書く。子の「対応 UC」行は `基盤` と書き、対応表では `基盤` キーをこの親の番号に seed する。

## ドラフトチェックのチェックリスト (フェーズ 9 のドラフトチェック)

fresh context の検査 subagent に、親 + 子の全ドラフトを一括で渡して検査させる観点:

1. **自己完結性**: 人間が issue 本文と参照 docs だけで着手できるか。会話の文脈にしか無い前提が紛れていないか
2. **DoD の実行可能性と空虚性**: DoD が実行可能なコマンドか。対象が未実装でも通る DoD (存在チェックだけ・恒真の grep 等) になっていないか
3. **依存の整合**: 依存グラフに循環が無いか。「依存なし」の issue が実は他 issue の成果物を前提にしていないか
4. **相互の重複・漏れ**: 同じ作業が複数 issue に跨っていないか。機能設計書の「実装の配置」に現れるファイルがどの issue にも属さず漏れていないか
5. **参照の実在**: 参照する docs パス・節名・UC 名が実在するか
6. **UC 帰属の整合**: 親ドラフトが USECASES.md の UC を過不足なく覆っているか。各子の「ゴール」に「対応 UC」行があり、その UC を覆う親ドラフトが存在するか。`基盤` の子が基盤親に集約されているか。**次の 2 つは違反ではない**: `基盤: UC に属さない共通実装` 親 (USECASES.md に対応する UC が無くてよい)、複数 UC をまとめた統合親 (タイトルが単一の UC 見出しと一致しなくてよい)

フェーズ 9 は上記 6 項目を検査 subagent の指示文に転記するので、**例外の但し書き (項目 6 の末尾) も一緒に転記する** — 転記しないと検査側は例外表を見ておらず、基盤親・統合親に対して必ず high を上げる。

## issue 作成手順 (フェーズ 10)

### 前提条件

```bash
REPO_SLUG=$(gh repo view --json nameWithOwner -q .nameWithOwner)
```

失敗する (git リポジトリでない / GitHub リモートが無い / `gh` 未認証) なら停止し、「リポジトリを用意してから再実行してください」と案内する。作れないまま成功したように振る舞わない。

### ラベルの用意 (冪等)

```bash
gh label create ready       --repo "$REPO_SLUG" --force --color 0E8A16 --description "着手可能"
gh label create in-progress --repo "$REPO_SLUG" --force --color 1D76DB --description "dev-impl が実装中"
gh label create needs-human --repo "$REPO_SLUG" --force --color D93F0B --description "人間の判断待ちで駐車中"
gh label create tracking    --repo "$REPO_SLUG" --force --color 5319E7 --description "親 issue (トラッキング)。実装対象ではない"
```

### 既存 issue との突き合わせ (再実行の冪等化)

親・子の区別なく、**全ドラフトをタイトルで既存 issue と突き合わせる**:

```bash
gh issue list --repo "$REPO_SLUG" --state all --limit 200 --json number,title,state,labels
```

取得件数が limit に達したら limit を上げて再取得する (無音の取りこぼしは重複作成になる)。

| 既存 issue の状態 | 動作 |
| --- | --- |
| 同タイトルが無い | 新規作成 |
| タイトル一致・open | 本文を比較し、不一致なら `gh issue edit <番号> --body-file` で貼り直す。`in-progress` の issue を書き換えたときは issue コメントで改訂を告知する |
| タイトル一致・closed | 子は触らない。親は新しい子を紐付けるときだけ reopen する (下記「親の reopen」)。いずれも本文が現ドラフトと不一致ならその番号を最終報告に列挙する (完了済み issue に改訂が届かないことを人間が把握できるように) |
| ドラフトのどの親ともタイトル一致しない既存 `tracking` issue で、子を持つもの (`<タスク名> トラッキング` 形式を除く) | **UC 見出しが改訂された可能性がある。** 勝手に貼り替えず、その親と子の一覧を提示して「どの新しい親へ貼り替えるか / 旧親のまま残すか」を人間に確認する (貼り替えないと、子は単一親制約で旧親に紐付いたままとなり、新親への紐付けが HTTP 422 になる)。`<タスク名> トラッキング` 形式は下記「旧構成 (run 全体で親 1 件) からの移行」が扱うので、この行の対象外 |

本文比較はコマンド置換 (`$(...)`) を使わずファイルに落として `cmp` する (末尾改行の欠落を検出するため。`~/.claude/rules/core/verification.md`)。取得側の `sed 's/\r$//'` は CRLF 除去 (GitHub web UI で編集された本文対策)。`gh` の出力はファイル末尾に改行 1 つが付くため、ドラフト側もファイル末尾を改行 1 つで終える形で Write する (毎回不一致になるときはまず末尾改行の差を疑う)。`<ドラフトファイル>` は子なら `<scratchpad>/issue-<連番>.md`、親なら `<scratchpad>/parent-<識別子>.md`:

```bash
gh issue view "$ISSUE_NUM" --repo "$REPO_SLUG" --json body -q .body | sed 's/\r$//' > <scratchpad>/issue-current.md
cmp -s <scratchpad>/issue-current.md <ドラフトファイル> || \
  gh issue edit "$ISSUE_NUM" --repo "$REPO_SLUG" --body-file <ドラフトファイル>
```

### 親 issue の特定と作成

**親本文は子の番号を含まない** (進捗は GitHub の Sub-issues セクションが持つ) ため、子の作成後に親本文を再生成する工程は無い。親は子より先に作る。

既存の `tracking` issue を一覧し、ドラフトの親タイトルと突き合わせる。無い分だけ作成する。親ドラフトのファイル名は `parent-<識別子>.md` (識別子は単独 UC 親が UC 番号 `UC-001`、統合親が `UC-<番号 1>-<番号 2>` の昇順で先頭にのみ `UC-` を付けた `UC-004-005`、基盤親が `kiban`、クイックモード親が `quick`):

```bash
gh issue list --repo "$REPO_SLUG" --state all --label tracking --limit 200 --json number,title,state
PARENT_TITLE="<ドラフトの親タイトル>"
PARENT_URL=$(gh issue create --repo "$REPO_SLUG" --title "$PARENT_TITLE" --body-file <scratchpad>/parent-<識別子>.md --label tracking)
PARENT_NUM=$(printf '%s' "$PARENT_URL" | grep -o '[0-9]*$')
```

「対応 UC → 親 issue 番号」の対応表を作りながら進める (子の紐付け先の解決に使う)。既存分は突き合わせで得た番号を先に seed する。キーの作り方:

| 親 | 登録するキー |
| --- | --- |
| 単独 UC 親 | その UC 番号 (`UC-001`) |
| 統合親 | **覆う UC 全件をキーにして同じ番号を登録する** (`UC-004` と `UC-005` の 2 キー → 同じ親番号) |
| 基盤親 | `基盤` |
| クイックモード親 | `基盤` |

子の「対応 UC」行は `UC-001: <名前>` 形式なので、UC 番号の部分だけを取り出して引く。

#### 親の reopen

closed の親に新しい子を紐付けることになったら (完了後の設計改訂で issue が増えた場合)、先に reopen する (`gh issue view --json state` が返す値は大文字):

```bash
[ "$(gh issue view "$PARENT_NUM" --repo "$REPO_SLUG" --json state -q .state)" = "CLOSED" ] && \
  gh issue reopen "$PARENT_NUM" --repo "$REPO_SLUG" --comment "issue が追加されたため再オープンする"
```

### 子 issue の作成

依存の前方参照を避けるため、依存グラフの上流から順に 1 件ずつ作る (依存先の番号が常に確定済みになる)。本文は Write ツールで `<scratchpad>/issue-<連番>.md` に書き出してから渡す:

```bash
TITLE="<ドラフトの子タイトル>"
ISSUE_URL=$(gh issue create --repo "$REPO_SLUG" --title "$TITLE" --body-file <scratchpad>/issue-<連番>.md --label ready)
ISSUE_NUM=$(printf '%s' "$ISSUE_URL" | grep -o '[0-9]*$')
```

`gh issue create` が返すのは URL であり番号ではない。`Depends on #<番号>` の解決用に「タイトル → 番号」の対応表を作りながら進め、再実行時は突き合わせで得た既存 issue の番号を先に対応表へ seed する (しないと依存が解決できない)。

### 親への紐付け (GitHub sub-issues API)

**旧構成 (`<タスク名> トラッキング` の単一親) が残っている場合は、先に下記「旧構成からの移行」を実行してから本節の通常紐付けに入る** — 旧親に紐付いたままの子へ通常紐付けを叩くと単一親制約で HTTP 422 になる。

**対象は全子 issue であり、今回新規作成した分だけではない** (前回の run が作成直後に落ちていると、既存の子が未紐付けのまま残る)。まず各親に紐付け済みの子を seed する:

```bash
gh api --paginate "repos/$REPO_SLUG/issues/$PARENT_NUM/sub_issues?per_page=100" --jq '.[].number'
```

`--paginate` と `per_page=100` を省かない — このエンドポイントの既定は 1 ページ 30 件で、31 件目以降が見えず二重紐付けの 422 を踏む。seed に無い子だけを、その子の親へ紐付ける:

```bash
CHILD_ID=$(gh api "repos/$REPO_SLUG/issues/$ISSUE_NUM" --jq .id)
gh api "repos/$REPO_SLUG/issues/$PARENT_NUM/sub_issues" -F sub_issue_id="$CHILD_ID"
```

紐付け先の親は、**現ドラフトにある子はドラフトの「対応 UC」行から、ドラフトに無い既存の未紐付け子は issue 本文の「対応 UC」行から**決める。本文から読み取れない子は紐付けず、最終報告に「対応 UC 不明の未紐付け子」として番号を列挙する (勝手にどれかの親へ入れない)。

実測で確定した挙動 (2026-08-27 時点、gh 2.97.0・`reedot/HyattTimeKeeper` および使い捨てリポジトリで確認):

| 項目 | 挙動 |
| --- | --- |
| パラメータの型 | `-F` (typed) が必須。`-f` (文字列) は `is not of type integer` で HTTP 422。id は `gh api repos/.../issues/<番号> --jq .id` の numeric id (`gh issue view --json id` が返す `I_kwDO...` 形式の node ID は使えない) |
| 二重紐付け | HTTP 422。メッセージが単一親制約の違反と共通なので、事後に握りつぶさず seed による事前判定で避ける |
| 単一親制約 | 子は同時に 1 つの親にしか紐付かない。別の親に紐付いている子は `-F replace_parent=true` を追加して貼り替える |
| 親の逆引き | `gh api "repos/$REPO_SLUG/issues/<子番号>/parent"` が親の `number` / `state` / `sub_issues_summary` (`total` / `completed` / `percent_completed`) を返す。親が無い子では HTTP 404 (dev-impl が close 判定に使う) |
| 親からの進捗取得 | `gh api "repos/$REPO_SLUG/issues/<親番号>" --jq .sub_issues_summary` でも同じ `total` / `completed` が引ける (子を自前で列挙して数えなくてよい) |
| `state` の大小文字 | `gh api` (REST) は小文字 `open` / `closed`、`gh issue list --json` / `gh issue view --json` は大文字 `OPEN` / `CLOSED`。混ぜない |

紐付けに失敗したら停止して人間に伝える: 作成済みの子 issue 番号、未紐付けの組、復旧は本フェーズの再実行で行えること (突き合わせと seed が続きから紐付ける)。

#### 旧構成 (run 全体で親 1 件) からの移行

`<タスク名> トラッキング` 形式の親がある場合の扱いは USECASES.md の有無で分かれる:

| 構成 | 扱い |
| --- | --- |
| USECASES.md がある | 旧構成なので UC 親へ移行する (下記の手順) |
| USECASES.md が無い (クイックモード) | 正しい構成なので移行しない。既存の `<タスク名> トラッキング` 親が 1 件だけなら**タイトルが現ドラフトと一致しなくてもそれを流用する** (タスク名が変わっただけのため。本文はドラフトで貼り直す)。複数あればタイトルを提示して人間に選ばせる |

移行する場合は、UC 親を作ったうえで旧親の子を貼り替える:

```bash
OLD_PARENT_NUM=$(gh issue list --repo "$REPO_SLUG" --state all --label tracking --limit 200 \
  --json number,title --jq '.[] | select(.title | endswith(" トラッキング")) | .number')
for CHILD_NUM in $(gh api --paginate "repos/$REPO_SLUG/issues/$OLD_PARENT_NUM/sub_issues?per_page=100" --jq '.[].number'); do
  CHILD_ID=$(gh api "repos/$REPO_SLUG/issues/$CHILD_NUM" --jq .id)
  # PARENT_NUM は「対応 UC → 親 issue 番号」の対応表から、その子の「対応 UC」行で引いた値
  gh api "repos/$REPO_SLUG/issues/$PARENT_NUM/sub_issues" -F sub_issue_id="$CHILD_ID" -F replace_parent=true
done
```

`OLD_PARENT_NUM` が複数ヒットしたらタイトルを提示して人間に選ばせる。**「対応 UC」行を持たない子** (旧構成のまま更新されていない子) は貼り替えず旧親に残し、最終報告の「対応 UC 不明の未紐付け子」に列挙する。全子の貼り替えが終わって旧親の `sub_issues` が **0 件になったときだけ**、旧親を close する (残った子があるなら open のままにする):

```bash
gh issue close "$OLD_PARENT_NUM" --repo "$REPO_SLUG" --comment "ユースケース単位のトラッキング issue へ移行したため close する"
```

### 最終報告

- 親 issue: 一覧 (`#3 UC-001: マスタと据置端末を整備する` の形式)。新規作成件数 / 既存流用件数
- 子 issue: 新規作成件数 / 本文更新件数 / スキップ件数
- 旧構成から移行した場合: 貼り替えた子の件数と close した旧親の番号
- 対応 UC 不明で紐付けられなかった子の番号 (あれば)
- closed だが本文不一致の issue 番号 (あれば)
