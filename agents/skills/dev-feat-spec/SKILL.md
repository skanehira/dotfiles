---
name: dev-feat-spec
description: >-
  機能追加の設計ループ。`needs-design` の付いた issue を、ユーザーに質問せずに設計し、
  設計書の変更が要るものは設計 PR (docs/design/features/ と DESIGN.md の更新、`Design-for: #N`、仮定と確認点) を、
  要らないもの (バグ・小さな修正) は issue に修正方針を出して `design-review` にする。
  人か顧客の判断が要るものは質問を書いて `needs-human` で止める。
  issue の本文は /dev-impl が読む形 (ゴール / 設計 / DoD / 非スコープ / 依存 / 優先度) に書き直すので、
  人が設計 PR を merge して `ready` を付けると、そのまま /dev-impl に渡る。
  人が手元で起動する。`/dev-feat-spec <PR 番号>` で起動すると、人の指摘を受けて設計 PR を直す。
  「needs-design の issue を設計して」「機能追加の設計 PR を出して」「issue の修正方針を書いて」
  「この設計 PR を直して」などで起動する。新規開発の初期段階 (ユーザーストーリーから作る) は /dev-spec を使う。
argument-hint: "[issue 番号 | PR 番号。省略時は needs-design の全件]"
allowed-tools: Read, Edit, Write, Glob, Grep, Bash, Agent, AskUserQuestion
---

# dev-feat-spec — 機能追加の設計ループ

運用の前提: AI が issue を整理・設計・実装し、人はスキルの起動と設計の確認と `ready` の付与を行う。issue の状態はラベルが正本で、`ready` は人が設計を承認した印である。このスキルは `needs-design` の issue を設計して `design-review` にするところまでを受け持ち、`ready` は付けない。状態の定義と着手可能の基準は `~/.claude/skills/dev-triage/references/issue-states.md` が正本で、対象リポジトリに `docs/ISSUE_TRIAGE.md` があれば、そこに書かれた定義を優先する。スコアは `dev-triage` が本文の `## 優先度` に書く。

| 起動 | モード | 人への質問 |
| --- | --- | --- |
| 引数なし、または issue 番号 | 設計モード (下の「設計モード」) | しない。止まらずに最後まで進む (人の判断は PR の「確認点」と `needs-human` のコメントに集める) |
| PR 番号 | 直しのモード (下の「直しのモード」) | してよい。人が手元で起動し、指摘を伝える |

引数の番号が issue か PR かは `gh pr view <番号>` が成功するかで判定する。

## 前提を確かめる

```bash
REPO_SLUG=$(gh repo view --json nameWithOwner -q .nameWithOwner)
DEFAULT=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
~/.claude/skills/dev-triage/scripts/setup-labels.sh "$REPO_SLUG"
ls docs/ISSUE_TRIAGE.md 2>/dev/null
```

- Claude Code の Bash ではシェルの変数が呼び出しをまたいで残らない。ここで得た `REPO_SLUG` / `DEFAULT` と、手順 2 の `SCRATCH` の値を控え、以降のコマンドの `$REPO_SLUG` / `$DEFAULT` / `$SCRATCH` はその値に置き換えて書く (変数のまま書くと、空の値で `gh` や `git` が動く)
- `setup-labels.sh` は、このスキルが付け外しする状態のラベル (`needs-design` / `design-review` / `needs-human` / `tracking`) を含む状態と種別のラベルを、無ければ作る。失敗したら、GitHub に書き込めないので止まって報告する
- 作業ツリーが dirty なら止まる。設計は issue ごとに `origin/$DEFAULT` から切ったブランチで行う
- `~/.claude/skills/dev-triage/references/issue-states.md` と、対象リポジトリの `AGENTS.md` (無ければ `CLAUDE.md`) を Read する。`docs/ISSUE_TRIAGE.md` があれば、それも Read する。受け入れ基準の ID の振り方、設計書の置き場所、ドキュメントの書き方などのプロジェクトの規約は、このスキルより優先する

## 設計モード

### 1. 対象を集めて並べる

```bash
gh issue list --repo "$REPO_SLUG" --state open --label needs-design --limit 200 --json number,title,body,labels
gh pr list --repo "$REPO_SLUG" --state open --limit 200 --json number,headRefName,body,files
```

- 取得件数が limit に達したら limit を上げて取り直す
- `needs-human` / `tracking` / `事業・運営` の付いた issue は対象から外す
- 引数で issue 番号を指定されたら、その 1 件だけにする
- 並べ方: 本文の `## 優先度` に緊急枠の行 (行の先頭が `緊急枠 (`) がある issue を先頭に置き、次に `スコア <数値>` の高い順に並べる。どちらも無い issue はその後ろに、番号の小さい順に並べる (書式は `~/.claude/skills/dev-triage/references/priority.md`「issue への書き方」)
- 本文に `Design-for: #<この issue>` の行を持つ open の PR がある issue は飛ばし、最終報告に理由を書く (設計済みで、人のレビュー待ち)
- ブランチ `design/issue-<N>` が origin にあるのに open の PR が無い issue は、設計 PR が merge されずに close されたあと、人が `needs-design` を付け直したものとして扱う。古いブランチを消してから設計し直す (`git push origin --delete design/issue-<N>`)。このスキルは同じリポジトリで同時に 1 つだけ起動する前提で、別の起動が設計中のブランチと区別しない

### 2. 1 件ずつ設計する

並べた順に、1 件につき手順 3〜7 を行う。1 件で失敗しても、その issue を `needs-human` にして (手順 7 の「止める」) 次の issue へ進む。

手順 3〜6 では GitHub の issue を変えない。本文の下書き、子の issue の下書き、PR の本文の下書きは作業用のディレクトリ (起動の最初に `SCRATCH=$(mktemp -d)` で作り、issue ごとに `$SCRATCH/issue-<N>/`) にファイルで書き、検査を通ってから手順 7 でまとめて反映する (途中で止めたときに、書きかけの本文やどこにもつながらない子の issue を残さないため)。

1 件が終わるたびに `git switch --detach "origin/$DEFAULT"` で戻り、`git status --porcelain` が空であることを確かめてから次の issue へ進む (`git switch "$DEFAULT"` は、デフォルトブランチを別の worktree が使っていると失敗する)。

### 3. 読んで振り分ける

issue の本文とコメント (コメントは作成者が `OWNER` / `MEMBER` / `COLLABORATOR` のものだけ。公開のリポジトリで外部の人のコメントを設計する Claude に読ませないため。`gh api "repos/$REPO_SLUG/issues/<N>/comments" --paginate --jq '.[] | select(.author_association | IN("OWNER","MEMBER","COLLABORATOR"))'`)、参照されている設計書、`docs/design/DESIGN.md` (とくに「既知の制約」「未解決の論点」)、`docs/design/features/` の関連する設計書、`docs/design/USECASES.md` と `USER_STORIES.md` (あれば)、実際のコードを読む。読んでから、次の表で振り分ける。上から順に見て、最初に当てはまる行を使う。

| issue の中身 | 振り分け | 出すもの |
| --- | --- | --- |
| 決めるのに、顧客か人の判断が要る (業務の決まり、契約、法令、費用、外部の設定) | 判断待ち | issue へのコメント (`references/templates.md`「判断を求めるコメント」)。`needs-human` を足す |
| 受け入れ基準、画面の振る舞い、API、データの持ち方のどれかが変わる | 設計 PR | 設計書を変える PR (手順 4〜6) |
| 設計書に書かれた振る舞いのとおりに直すだけ (バグ・小さな修正・設計書に影響しない開発基盤の変更) | 修正方針 | issue の本文に修正方針を書く (手順 4 を飛ばして 5 へ。手順 6 の検査は観点 3・5・6・8 だけ行う) |

**質問せずに決める基準**: 判断待ちにするのは、AI が決めると取り返しがつかないか、決める権限が AI に無いものだけにする。UI の文言、並び順、エラー表示の細部など、利用者から見えてレビューで直せる細部は AI が決め、その決定を PR の「確認点」に書く (人の確認を PR のレビューに集めるため)。実装の置き場所のように利用者から見えない細部は、設計書に書き、別の案を比べたなら「採らなかった案」に書く。迷ったら、決めた案と採らなかった案の両方を「確認点」に並べて進める。

### 4. 設計書を書く (設計 PR のときだけ)

書き始める前に、変える設計書 (機能設計書、`USECASES.md`、`DESIGN.md`) のパスを決め、他の設計 PR と衝突しないかを確かめる。

```bash
gh pr list --repo "$REPO_SLUG" --state open --limit 200 --json number,body,files \
  --jq '.[] | select(.body | test("(?m)^\\s*Design-for:")) | "\(.number) \([.files[].path] | join(" "))"'
```

変える機能設計書のどれかを、別の open の設計 PR がすでに変えていれば、この issue は飛ばして最終報告に理由を書く (先の PR の merge のあとの起動で設計する)。この起動の中で先に出した PR もこの一覧に入るので、issue ごとに取り直す。`USECASES.md`・`DESIGN.md`・`OVERVIEW.md` は複数の機能が共有するので、変える節が重ならなければ衝突として扱わない。`OVERVIEW.md`「機能の一覧」の行の追加は、重なっても衝突として扱わない。

`git switch -c design/issue-<N> origin/$DEFAULT` で切ったブランチで書く。

- **機能設計書**: 既存の `docs/design/features/<機能名>.md` を変えるか、新しく作る。型と記入基準は `~/.claude/skills/dev-spec/references/feature-doc.md` に従う (/dev-impl の implementer と review-impl がこの型で読むため)。「細部は方針から導き、聞くものを絞る」の基準のうち、その場でユーザーに確認する部分だけは、このスキルでは「質問せずに決めて確認点に書く」に読み替える
- **人が読む概要**: 機能設計書の「何を作るか」と `docs/design/OVERVIEW.md` は、人が仕様の概要を知るための要約である (書き方は `~/.claude/skills/dev-spec/references/overview-doc.md` と `feature-doc.md`)。次の表で扱いを決める

  | 対象 | この設計で概要が変わる | 変わらない |
  | --- | --- | --- |
  | 新しい機能設計書の「何を作るか」 | 新しい形で書く | (無い) |
  | 新しい形の「何を作るか」 | いまの仕様の概要として書き直す。末尾に足さない | 触らない |
  | 旧い形の「何を作るか」 (契約の文を含む長い節) | 誤りになる文だけを直す。形は変えない。最終報告に「旧い形」と書く | 触らない |
  | OVERVIEW.md がある | 該当する節を書き直す。機能設計書を足した・消したら「機能の一覧」も直す | 触らない |
  | OVERVIEW.md が無い | 作らない。最終報告に「OVERVIEW.md が無い」と書く | 作らない |

  旧い形かどうかは、書き始める前に `sh ~/.claude/skills/dev-spec/scripts/overview-check.sh docs/design <変える機能設計書>...` がその機能設計書の「何を作るか」を問題にするかで決める。旧い形の移行はこのスキルでは行わない (無人の設計 PR で契約の文を動かすと、落ちた契約に人が気づけないため。移行は `/dev-spec` で行う)。書き終えたら、新しい形の機能設計書と OVERVIEW.md のうち、この PR で変えたものに同じコマンドの指摘が無くなるまで直す。足した・消した機能設計書への参照の指摘も直す。変更履歴のコメントは、どの設計書にも足さない
- **受け入れ基準**: 振る舞いを足すか変えるときは、`USECASES.md` (あれば) の受け入れ基準を足すか直し、機能設計書の「テスト方針」の表へ写す。ID の振り方はプロジェクトの規約に従う。表でレベルを E2E にした行は、表の外の `E2E 対象動線:` の行にも同じ文面で書き写す (書き方は `feature-doc.md`)。既存の機能設計書の表の行を E2E にしたときも、書き写しを忘れない。/dev-impl の動作確認の証跡 (PR に貼るスクリーンショット) は、この行の流れの E2E からだけ撮るためである。書き写さないと、E2E を書いても、その画面が PR のスクリーンショットに載らない
- **横断の設計**: スキーマ、API の共通規約、横断の決まりが変わるときは `docs/design/DESIGN.md` の該当の節を直す。触れる範囲に「既知の制約」があれば、機能設計書から節名で参照する
- **ユーザーから見た変化**: 画面が変わるときは、機能設計書の「入出力と振る舞い」に、操作と画面に起きることの表を書く。あわせて `docs/design/UI_SKETCH.html` を設計どおりに直し、変わる画面の変更前と変更後をスクリーンショットに撮る。PR の本文には、その画像を貼る (レビューする人が、設計書を全部読まずに見た目の変化をつかめるようにするため。テキストの図は全角と罫線の表示幅で崩れて読みにくい)。変更前はスケッチを直す前に撮るので、設計書を書き始める前に `references/sketch-capture.md` を Read し、その手順 1〜5 に従う。スケッチが無いプロジェクトと、gh が画像の添付に対応していないときの扱いも同書にある
- **既存の実装と合わせる**: 「実装の配置」は、実際のコードを読んで、既存のどのファイルとどの層を変えるかまで書く。既存の実装と食い違う設計にするなら、理由を設計書に書く
- **実装先ファイルの作り手**: 変えた機能設計書の「実装の配置」の表は、「作る / 足す」の列を持つ形で書く (書き方は `feature-doc.md` の記入基準「実装先ファイルの作り手を 1 本に決める」)。書き終えたら、clone の最上位で `sh ~/.claude/skills/dev-spec/scripts/placement-check.sh docs/design` を実行する。この PR で変えた機能設計書の行と、その表に書いたファイルの行の指摘が無くなるまで直す。変えていない機能設計書の「列が無い」の指摘は直さない (旧い形の移行は `/dev-spec` で行う。上の「人が読む概要」と同じ理由)。「作る機能設計書が無い」の指摘のうち、列の無い機能設計書がそのファイルを表に書いているものも直さない (作り手がその機能設計書にあるか判定できないため。「足す」のままにする)

設計書は `~/.claude/skills/workflow-doc-write/SKILL.md` の手順 1〜7 で書く (このスキルの中では手順 8 の監査依頼は出さない。下の検査がその代わりになる)。

### 5. issue の本文を書き直す

issue の本文を、/dev-impl が読む形に書き直した下書きを作る (GitHub への反映は手順 7)。型は `~/.claude/skills/dev-spec/references/issue-template.md`「子 issue テンプレート」(ゴール / 設計 / DoD / 非スコープ / 依存) で、末尾に元の `## 優先度` をそのまま残す。人が書いた元の本文の要点 (何に困っているか、何をしたいか) は、「ゴール」の「いま困っていること」と「こうなる」に残す。人が判断に使う背景 (要望の出どころ、測った値) も、上限に入る分は残す。入らない背景と、再現手順・ログは「設計」に移す。「ゴール」の説明は issue を承認する人が読むので、`references/templates.md`「人が読む文章の書き方」に従って書く。

- **設計 PR のとき**: 「設計」節は、この PR で変えた設計書を指す。設計の本文は issue に写さない (正本は設計書)
- **修正方針のとき**: 「設計」節に「設計書の変更は要らない。修正方針:」と書き、直す場所 (ファイルと関数)、直し方、直さないことを箇条書きにする (`references/templates.md`「修正方針」)。参照する設計書の節名も書く
- **DoD**: 実行できるコマンドと期待結果を書く。対象が未実装でも通る DoD (存在の確認だけ、恒真の grep) にしない。足した受け入れ基準をテストで固定することを含める
- **大きな issue を分ける**: 1 issue = 独立して検証できる 1 作業単位にする。分けるときは、元の issue を親にし、子の issue の下書きを作る (作成は手順 7)
  - 子の本文の末尾 (`</details>` の後) に、空行を 1 行はさんで親の `## 優先度` を写す (子は親のスコアを引き継ぐ)
  - 子のあいだの依存は、`Depends on <子の下書きの名前>` と書いておき、手順 7 で作ったときに `Depends on #<番号>` へ置き換える。依存は「依存先が merge した成果物が無いと DoD が失敗する」ときと「別の子が作る共有ファイルに処理を足す」ときだけ書く (`~/.claude/skills/dev-spec/references/issue-template.md`「依存の段数」。作る側の子の「設計」には「作る共有ファイル」の行を書く)

下書きを書いたら、`sh ~/.claude/skills/dev-spec/scripts/issue-check.sh <下書きのファイル>...` を実行し、何も出力しなくなるまで直す。分けたときは子の下書きだけを渡す。親の本文は検査せず、元の本文の先頭に「ゴール」の形の要約を足し、末尾に `## 実装の分け方` (子の番号と作業) と `## 優先度` を置く。手順 6 で本文を直したときも、反映する前に実行する。

書き直した本文は、着手可能の基準 (`issue-states.md`「着手可能の基準」。`docs/ISSUE_TRIAGE.md` が基準を定めていればそちら) を満たしていなければならない。人は承認したら、本文を直さずに `ready` を付けるため。

### 6. 別のコンテキストで検査する

書き手は自分の書き漏れを見つけにくいので、`general-purpose` の subagent を**モデル: opus を明示**して 1 本起動し、完了を待つ。渡すもの: 変えた設計書のパス (と `git diff origin/$DEFAULT` の出力のファイル)、書き直した issue の本文 (子があれば子も) のファイル、着手可能の基準 (`~/.claude/skills/dev-triage/references/issue-states.md`「着手可能の基準」と、対象リポジトリの `docs/ISSUE_TRIAGE.md` があればその基準)、`docs/design/OVERVIEW.md` (あれば、変えていなくても)、`~/.claude/skills/dev-spec/references/overview-doc.md` と `feature-doc.md`。指示文に含める観点:

1. **落とし漏れ**: issue が求めることが、設計書と受け入れ基準にすべて現れているか。足した受け入れ基準が「テスト方針」の表に写っているか。レベルを `なし (<理由>)` にした行の理由が `~/.claude/guidelines/core/testing.md`「テストを書くかを先に決める」の 2 つの軸に沿っているか。表でレベルを E2E にした行が、すべて `E2E 対象動線:` の行に同じ文面で書き写されているか (漏れは medium。その画面が PR の動作確認のスクリーンショットに載らなくなるため)
2. **矛盾**: 変えた設計書と、DESIGN.md や他の機能設計書とが食い違っていないか
3. **未定義・参照切れ**: 用語、テーブル、エンドポイント、節名の参照先が実在するか
4. **エッジケース**: 起こるのに決定が書かれていないエッジケースが無いか (feature-doc.md の観点リスト)
5. **既存の実装との整合**: 「実装の配置」のファイルと関数が実在し、設計がそれと食い違っていないか
6. **着手可能の基準**: issue の本文が基準をすべて満たすか。DoD が空虚でないか
7. **確認点の網羅と読みやすさ**: 設計で AI が決めた細部と仮定のうち、利用者から見える違いを生むものが、PR の本文の「確認点」に並んでいるか。各項目が `references/templates.md`「設計 PR の本文」の確認点の型 (起きる場面・この設計での動き・別の案) を満たし、設計書を読んでいない人がその項目だけで判断できるか。API のパス、関数や変数の名前、設計書の中だけの言い回しで書いていないか (確認点の下書きと `references/templates.md` も渡す)。その項目だけで判断できないものは medium とする (確認点は人が判断する材料で、読めなければ判断が抜けるため。下の low の「読みやすさ」には入れない)
8. **人が読む文章**: PR の本文の「何を決めたか」「画面の変化」と、issue の「ゴール」が、`references/templates.md`「人が読む文章の書き方」に従っているか。設計書を読んでいない人が、その節だけで何に困っていて何がどう変わるかを説明できるか。ゴールの記述が設計書・「担う受け入れ基準」・「非スコープ」と食い違っていないか (食い違いは high) (PR の本文の下書きと `references/templates.md` も渡す)。分からない箇所は medium とする (観点 7 と同じ理由)
9. **画面の画像**: 画面が変わる設計では、撮った png (`<SCRATCH>/issue-<N>/screens/` の全件のパスを渡す) を開き、変更後の画像に機能設計書の「入出力と振る舞い」の変化が写っているか、文言が機能設計書と同じか、表示が崩れていないかを見る。`UI_SKETCH.html` の変更が機能設計書と食い違っていないかも見る。変化が写っていない、または文言が違うものは medium とする (レビューする人が画像で判断するため)
10. **概要の誤り**: この PR で変えた「何を作るか」と OVERVIEW.md の文が、契約の節とビジネスルールに合うか (食い違いは high)。この設計で正しくなくなる OVERVIEW.md の文が残っていないか (medium)。概要に要らない記述 (文言・エラー・データの持ち方・例外の例外) が足されていれば medium とし、修正案は削除か入れ替えにする。例外を落とした言い切りの修正案は、まず言い切りを弱めることにし、例外を足すのは 1 項目に 1 つまでにする。この設計と関わらない既存の誤りは検査の指摘に入れず、最終報告に書く (別件の設計を止めないため)

出力の形式は `[severity] 該当箇所 / 問題の一文 / 修正案の一文` (high = 実装が詰まるか、承認しても正しく実装できない / medium = 曖昧さが残る / low = 読みやすさ)。

- high があれば直して検査をやり直す (概要を直したら `overview-check.sh` も実行し直す)。**最大 2 周**。2 周しても high が残れば、PR も修正方針も出さずに止める (手順 7 の「止める」)。残った high を判断を求めるコメントに書く
- medium は直すか、直さない理由を PR の「確認点」に書く

### 7. 出す

**設計 PR のとき**:

1. 分けたときは、先に子の issue を依存の上流から順に作る (`--label design-review`)。作るたびに、残りの下書きの `Depends on <子の下書きの名前>` を `Depends on #<番号>` へ置き換える。子を親の sub-issue に紐付ける (手順は `~/.claude/skills/dev-spec/references/issue-template.md`「親への紐付け」)
2. 変更を Conventional Commit でコミットする (`📝 docs: [BEHAVIORAL] ...`。スケッチに口といまの画面を足したときは、そのコミット (`[STRUCTURAL]`。`references/sketch-capture.md` の手順 1) が先に積まれている。コミットの実行は `~/.claude/guidelines/core/orchestration.md`「委譲の判断」に従って haiku に委譲してよい。subject の照合は自分で行う)
3. `git push -u origin design/issue-<N>` し、PR を作る。本文は `references/templates.md`「設計 PR の本文」で、`Design-for:` の行を必ず書く。分けなかったときは `Design-for: #<N>` の 1 行、分けたときは子の番号だけを 1 行ずつ書き、親は書かない。この行は、merge した人が `ready` を付ける issue を示す (本文の「承認したら」のコマンドも同じ issue を並べる)。**設計 PR は issue の Development に紐づけない**。本文に `Closes` などのキーワードを書かず、issue の画面からも紐づけない。Development に紐づいた PR は、デフォルトブランチへの merge で issue を close するので、`ready` が付いても /dev-impl が拾えなくなるため。issue の Development に載せるのは /dev-impl の実装 PR だけである。画面の画像があるときは、`gh pr create` に撮った png を全件 `--attach` で渡し、作った後に本文にローカルのパスが残っていないことを確かめる (`references/sketch-capture.md`「添付して PR を作る」)
4. 書き直した本文を issue に反映し、ラベルを付け替える
   - 分けなかったとき: `needs-design` を外して `design-review` を付ける
   - 分けたときの親: `needs-design` を外して `tracking` を付ける。`design-review` は付けない (親は実装の対象ではなく、`design-review` を付けると、人が子と一緒に `ready` にして /dev-impl の対象に紛れるため)
5. issue (分けたときは親) に、PR の URL と、PR を merge した後に本文の「承認したら」のコマンドを実行するよう案内する 1 文をコメントする

**修正方針のとき**: 書き直した本文を issue に反映し、ラベルを `needs-design` から `design-review` に付け替える。issue に、本文を読んで承認したら `gh issue edit <N> --repo <REPO_SLUG> --add-label ready --remove-label design-review` を実行するよう 1 行でコメントする (番号とリポジトリは実際の値にする)。

**止める (判断待ち、または検査で high が残ったとき)**: `references/templates.md`「判断を求めるコメント」で issue にコメントし、`needs-human` を足す。`needs-design` は外さない (人が回答して `needs-human` を外せば、次の起動で設計し直すため)。ブランチを作っていたら消す。

### 8. 最終報告

次を issue ごとに 1 行で並べる: 番号、振り分け (設計 PR / 修正方針 / 判断待ち / 飛ばした)、PR の URL か理由、検査の結果 (high・medium の件数)。最後に、設計 PR を出した issue と修正方針を出した issue を並べ、人が承認したら `ready` を付ける必要があることを 1 文で書く。あわせて、`Design-for:` の PR が merge 済みなのに `design-review` のまま残る issue を並べる (`ready` の付け忘れ。このスキルは付け替えず、人に知らせるだけにする)。

## 直しのモード

人が設計 PR をレビューし、手元で `/dev-feat-spec <PR 番号>` を起動して指摘を伝える。設計時のセッションは残っていない前提で、設計時の判断は PR の本文 (「仮定」「採らなかった案」「確認点」) と issue から引き継ぐ。

1. PR の本文、差分、レビューのコメント、`Design-for:` の issue (子を含む) の本文を読む
2. 人の指摘を聞く。指摘が設計時の仮定や採らなかった案と食い違うときは、その仮定を示して、どちらにするかを人に確かめる (このモードでは質問してよい)
3. PR のブランチで設計書を直す。設計書に合わせて、次も直す (設計書だけを直すと、古い本文のまま `ready` になった issue を /dev-impl が実装してしまうため)
   - `Design-for:` の issue の本文 (ゴール、設計、DoD、非スコープ、依存)。本文をファイルに取り、旧い形 (折りたたみが無い) なら新しい形に直し、`issue-check.sh` の出力が無くなってから反映する
   - 子の issue。分け方が変わったら、足りない子を設計モードの手順 7 の 1 と同じく `--label design-review` で作って親に紐付け、要らなくなった子は close して理由をコメントする。分けていなかった issue を分けたときは、親を `design-review` から `tracking` に付け替える
   - PR の本文の `Design-for:` の行と「承認したら」のコマンド (`Design-for:` の行と同じ issue を同じ順に並べる)、「仮定」「採らなかった案」「確認点」
   - 人が読む概要 (設計モードの手順 4「人が読む概要」の表と、`overview-check.sh` の実行)
   - 画面が変わる指摘なら、`docs/design/UI_SKETCH.html` と PR の本文の「画面の変化」の画像 (`references/sketch-capture.md`「直しのモード」)
4. 設計モードの手順 6 の検査をやり直す
5. コミットして push し (画像を撮り直したときは `gh pr edit --attach` で本文も更新する)、受けた指摘と直した内容を PR にコメントで残す (指摘がチャットにしか無いと、あとから PR を読む人が経緯を追えないため)
6. 人に、直した内容と残った確認点を報告する。merge は人が行う

## 関連

- `dev-triage`: 未整理の issue を採点して `needs-design` にする。このスキルの入力を作る。状態の定義と着手可能の基準の正本と、ラベルを用意する `setup-labels.sh` を持つ
- `/dev-spec`: 新規開発の初期段階 (ユーザーストーリーから作る)。機能設計書と issue の型はこのスキルと共有する
- `/dev-impl`: `ready` の issue を実装する
- 運用の決定の記録: dotfiles の `docs/DESIGN_NOTES.md`「設計 (dev-feat-spec)」「dev-feat-spec の設計」
