---
name: workflow-create-pr
description: "ローカルのコミット履歴と差分から GitHub の PR を作成する。既定は通常の PR で、`--draft` で Draft PR にする。画面のスクリーンショットと API の実行結果の証跡マニフェストを受け取ると、本文の「動作確認」節に埋め込み、画像を `gh pr create --attach` で添付する。ブランチ未作成・コミット未作成の状態でも、必要に応じてブランチ作成とコミットを行ってから作成する。`.github/` にPRテンプレートがあれば内容を埋め、なければ作業内容から本文を生成し、作成してよいかをユーザーに確認してから実行する。`--yes` の非対話モードは dev-impl が証跡付きの PR を作るときに使う。「PRを出したい」「PRを作って」「プルリクを作って」「draft PRを作成」「PR本文を生成」「証跡付きでPRを出して」などのリクエストで起動。"
argument-hint: "[--base <branch>] [--draft] [--evidence <manifest.json>] [--yes --repo <owner/name> --repo-dir <path> --head <branch> --title <title> --body-file <path>]"
model: haiku
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git rev-parse:*), Bash(git rev-list:*), Bash(git symbolic-ref:*), Bash(git branch:*), Bash(git switch:*), Bash(git remote:*), Bash(git push:*), Bash(git -C:*), Bash(gh pr create:*), Bash(gh pr edit:*), Bash(gh pr list:*), Bash(gh pr view:*), Bash(gh repo view:*), Bash(gh auth status:*), Bash(gh --version:*), Bash(ls:*), Bash(rg:*), Read, Write, Glob, AskUserQuestion, Skill
---

# /workflow-create-pr - PR 作成コマンド

ローカルのコミット履歴と差分を元に PR 本文を作り、GitHub に PR を作成します。

- 既定は通常の PR です。`--draft` を付けると Draft PR になります
- 証跡マニフェスト (`--evidence`) を受け取ると、画面のスクリーンショットと API の実行結果を本文の「動作確認」節に載せます。スクリーンショットは PR に添付します。証跡の集め方は `references/evidence.md` が正本で、このスキルは証跡を集めません
- `.github/` に Pull Request テンプレートがあれば内容を埋め、なければ作業内容から本文を生成します

## 使い方

```
/workflow-create-pr                                   # デフォルトブランチ基準で PR を作成
/workflow-create-pr --draft                           # Draft PR を作成
/workflow-create-pr --base develop                    # 指定ブランチ基準で PR を作成
/workflow-create-pr --evidence /path/to/manifest.json # 証跡を本文に載せて添付する
```

## 引数

```
引数: $ARGUMENTS
```

| 引数 | 意味 | 省略時 |
| --- | --- | --- |
| `--base <branch>` | ベースブランチ | デフォルトブランチを自動検出する ([1/6]) |
| `--draft` | Draft PR にする | 通常の PR |
| `--evidence <path>` | 証跡マニフェスト (`manifest.json`) の絶対パス | 手動モードではユーザーに聞く ([4/6])。非対話モードでは「動作確認」節に未指定と書く |
| `--yes` | 非対話モードにする (下記「モード」) | 手動モード |
| `--repo <owner/name>` | PR を作るリポジトリ | `gh repo view` で取得する |
| `--repo-dir <path>` | 作業ツリーの絶対パス | `git rev-parse --show-toplevel` |
| `--head <branch>` | PR の head ブランチ | 現在のブランチ |
| `--title <title>` | PR タイトル | コミットから生成する ([5/6]) |
| `--body-file <path>` | 本文の下書き。証跡はこの本文に足す | テンプレートか作業内容から生成する ([4/6]) |

## モード

**手動モード**はユーザーが `/workflow-create-pr` で起動する形で、本文を見せて作成の指示を受け取ってから PR を作る。

**非対話モード** (`--yes`) は、dev-impl のようにユーザーの応答を待てない呼び出し元が使う。本文の下書きは呼び出し元が書き、このスキルは証跡の埋め込み・添付・作成だけを行う。`--repo` / `--repo-dir` / `--base` / `--head` / `--title` / `--body-file` を全て必須とし、1 つでも欠けたら何もせず `PR_FAILED missing_arg <引数名>` を返す。非対話モードは質問しない。判断が要る場面では PR を作らずに `PR_FAILED <理由>` を返して呼び出し元に任せる。

Skill ツールから起動された場合、frontmatter の `model: haiku` は効かず、呼び出し元のモデルとコンテキストで動く。非対話モードが差分の全文を読まず、本文を生成し直さないのは、呼び出し元のコンテキストを差分で埋めないためである。

| 手順 | 手動モード | 非対話モード |
| --- | --- | --- |
| [1/6] 前提条件 | git・gh 認証・ベースの決定を確かめる | 認証確認は省く。ベースは `--base` を使う |
| [2/6] ブランチとコミット | 必要ならブランチを作り、`workflow-commit` でコミットする | 何もしない。未コミット変更があれば `PR_FAILED dirty_worktree` を返す |
| [3/6] 作業内容の収集 | コミット履歴と差分を読む | ベースとの差分のコミットが 1 件以上あることだけ確かめる |
| [4/6] 本文の用意 | テンプレートか作業内容から本文を作り、証跡を埋め込む | `--body-file` を読み、証跡を埋め込む |
| [5/6] 確認 | 本文と添付ファイルの一覧を見せ、作成の指示を受け取る | 確認せず、タイトル・base・head・添付の枚数を表示する |
| [6/6] 作成 | push して PR を作る | 同左。最終行を `PR_CREATED` / `PR_UPDATED` / `PR_FAILED` の 1 行にする |

## コマンドの書き方

以下のコマンドの `$REPO_DIR` / `$REPO` / `$BASE` / `$HEAD` は、引数か [1/6] で決めた値である。

- git は `git -C "$REPO_DIR" ...` で実行する
- gh は `--repo "$REPO"` と `--head "$HEAD"` を明示する
- `cd` しない。dev-impl のメインセッションから起動されると、`cd` した先が次の Bash 呼び出しにも残り、呼び出し元が後で消す worktree の中に作業ディレクトリが取り残される

---

## [1/6] 前提条件の確認

### gitリポジトリ確認

```bash
git -C "${REPO_DIR:-.}" rev-parse --show-toplevel 2>/dev/null
```

gitリポジトリでない場合は「このディレクトリはgitリポジトリではありません。」と表示して終了 (非対話モードでは `PR_FAILED not_a_git_repo`)。`--repo-dir` が無ければ、この出力を `REPO_DIR` にする。

### gh CLI 認証確認 (手動モードのみ)

```bash
gh auth status 2>&1
```

認証されていない場合は「`gh auth login` で GitHub CLI にログインしてください。」と表示して終了。

### 現在のブランチと作業状態の取得

```bash
git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD      # 現在のブランチ名
git -C "$REPO_DIR" status --porcelain               # 未コミット/未追跡変更
```

`--head` が無ければ、現在のブランチを `HEAD` にする。手動モードでは、この時点では強制終了しない (ベース上にいても [2/6] で処理する)。

### リポジトリとベースブランチの決定

`--repo` が無ければ `gh repo view --json nameWithOwner -q .nameWithOwner` を `REPO` にする。

ベースの優先順位:

1. `--base <branch>` 引数で明示指定 (非対話モードではこれだけを使う)
2. `gh repo view --json defaultBranchRef -q .defaultBranchRef.name` でデフォルトブランチ取得
3. 取得失敗時は `git -C "$REPO_DIR" symbolic-ref refs/remotes/origin/HEAD` から推測（`refs/remotes/origin/<branch>` の末尾）
4. それでも決まらない場合はユーザーに確認

### 添付できる gh か (証跡に画面があるときだけ)

```bash
gh --version
```

先頭行の版が 2.99.0 未満なら `--attach` が無い。スクリーンショットは添付せず、[4/6] の「動作確認」節に「スクリーンショット <n> 枚はローカルにあるが、gh <版> が添付に対応していないため載せていない」と書く。画像の参照を本文に残すとローカルのパスが PR に載るので、参照も書かない。

---

## [2/6] ブランチとコミットの準備

**非対話モードでは何もしない。** `git -C "$REPO_DIR" status --porcelain` が空でなければ `PR_FAILED dirty_worktree` を返して終了する (呼び出し元に無断でコミットを作らない)。

手動モードでは、[1/6] で取得した「現在ブランチ」「未コミット変更」「ベースブランチ」を元に、以下のフローで PR 作成可能な状態に整える。

### ケース判定

| 現在ブランチ | 未コミット変更 | 対応                                            |
| ------------ | -------------- | ----------------------------------------------- |
| = ベース     | あり           | 2.1 ブランチ作成 → 2.2 コミット作成             |
| = ベース     | なし           | エラー終了（PR対象の作業がない）                |
| ≠ ベース    | あり           | 2.2 コミット作成（ブランチ作成はスキップ）      |
| ≠ ベース    | なし           | スキップして [3/6] へ（既存コミットでPR作成）   |

### 2.1 ブランチ作成（現在ブランチ = ベースの場合）

`git -C "$REPO_DIR" diff` および `git -C "$REPO_DIR" status` の内容から Conventional Commit 形式のプレフィックスと簡潔な英語名を生成する。**ユーザー確認は行わず、生成した名前でそのまま作成する**。

| 変更内容のヒント                  | プレフィックス |
| --------------------------------- | -------------- |
| 新規ファイル追加、機能追加        | `feat/`        |
| 既存ロジックの修正、バグ修正      | `fix/`         |
| リファクタリング・構造変更のみ    | `refactor/`    |
| ドキュメント更新のみ              | `docs/`        |
| テスト追加・修正のみ              | `test/`        |
| 設定・ビルド・依存更新のみ        | `chore/`       |

例: `feat/add-user-validation`, `fix/handle-empty-input`, `refactor/extract-auth-module`

英語名は変更ファイル名や関数名から `kebab-case` で30文字以内に整形する。

```bash
git -C "$REPO_DIR" switch -c <generated-branch-name>
```

既存ブランチ名と衝突した場合は、末尾に短い識別子（`-2`, `-3`, ...）を付与して再試行する。3回試して失敗したらエラー表示して終了。作成したブランチを `HEAD` にする。

### 2.2 コミット作成（未コミット変更がある場合）

`workflow-commit` スキルに **無条件で委譲** する（ユーザー確認なし）。
`workflow-commit` は push を行わないスキルなので、push は本スキルの [6/6] でまとめて行う。

完了後、`git -C "$REPO_DIR" status --porcelain` で未コミット変更が残っていないことを確認する。
残っている場合は `workflow-commit` が意図的にスキップした可能性があるため、ユーザーに状況を報告し、続行するか中止するかを確認する。

---

## [3/6] 作業内容の収集

### コミット履歴の取得

```bash
git -C "$REPO_DIR" log <base>..<head> --pretty=format:"%h %s"
```

コミットが0件の場合は「ベースブランチとの差分がありません。」と表示して終了 (非対話モードでは `PR_FAILED no_commits`)。**非対話モードはここまでで [4/6] へ進む** (差分は読まない)。

### 差分の取得 (手動モードのみ)

```bash
git -C "$REPO_DIR" diff <base>...<head> --stat
git -C "$REPO_DIR" diff <base>...<head>
git -C "$REPO_DIR" diff <base>...<head> --name-status
```

差分が大きい場合（10,000行超など）は、ファイルリストと統計のみで本文を生成する。`--name-status` の出力は `A` (新規追加) / `M` (修正) / `D` (削除) / `R` (リネーム) に分類して本文に使う。

---

## [4/6] 本文の用意

次の順に組み立て、最終本文をファイルに書き出す。

1. 本文の下書きを用意する (4.1)
2. 証跡を読み、「動作確認」節を埋め込む (4.2)
3. シークレットを検査する (4.3)
4. 最終本文を書き出す (4.4)

### 4.1 本文の下書き

**非対話モード、または `--body-file` があるとき**は、そのファイルを Read して下書きにする。テンプレートの検出と本文の生成は行わない。

それ以外は、テンプレートを Glob ツールで以下の優先順位で検索する（大文字小文字を区別しない、最初に見つかったものを採用）:

1. `.github/pull_request_template.md`
2. `.github/PULL_REQUEST_TEMPLATE.md`
3. `.github/pull_request_template/*.md`（複数テンプレート）
4. `.github/PULL_REQUEST_TEMPLATE/*.md`（複数テンプレート）
5. `docs/pull_request_template.md`
6. `PULL_REQUEST_TEMPLATE.md`（リポジトリルート）

複数テンプレートディレクトリの場合は、使用するテンプレートをユーザーに選ばせる。

テンプレートがある場合は Read ツールで内容を読み込み、以下のルールで埋める:

| 構造                       | 処理                                                                  |
| -------------------------- | --------------------------------------------------------------------- |
| 見出し (`## Summary` 等)   | コミット履歴と差分から該当する内容を生成                              |
| HTMLコメント `<!-- ... -->` | テンプレート上の指示として読み取り、本文には残さない                  |
| チェックリスト `- [ ]`     | 作業内容から判断できるものはチェック、判断できないものは `- [ ]` のまま |
| プレースホルダ `<...>`     | 該当する内容で置換                                                    |

テンプレートに動作確認・スクリーンショットの見出しがあれば、4.2 の内容はそこに入れる。無ければ 4.2 の規則どおり節を足す。

テンプレートがない場合は以下の標準構造で本文を生成する:

```markdown
## Summary

<コミット履歴と差分から要約を1〜3点の箇条書きで>

## Changes

<変更ファイルを分類して列挙>

- 追加: ...
- 修正: ...
- 削除: ...

## Test Plan

- [ ] <作業内容から推測されるテスト項目>
```

### 4.2 証跡の埋め込み

**証跡マニフェストを決める。** `--evidence` があればそのファイルを使う。無いとき、手動モードでは AskUserQuestion で 1 問だけ聞く (「証跡マニフェスト `manifest.json` のパスを入力する」「証跡なしで作成する」の 2 択。パスは「Other」で受け取る)。このスキルは証跡を探しに行かず、撮りもしない。

マニフェストの書式は `references/evidence.md`「置き場所とマニフェスト」にある。Read して、`screens[].file` と `api[].file` の全パスが実在することを確かめる。

```bash
ls -1 <screens[].file と api[].file を全て並べる>
```

1 つでも無ければ、手動モードではユーザーに報告して中止するか証跡なしで続けるかを聞き、非対話モードでは `PR_FAILED evidence_missing <パス>` を返す。

**「動作確認」節を置く場所**: 本文に `🤖 Generated` で始まる行があればその直前に、無ければ末尾に `## 動作確認` を足す。テンプレートが該当する見出しを持つときはその見出しの中に入れる。

**画面** (`screens` が 1 件以上): `flow` ごとに小見出しを立て、`step` の順に「番号と状態の行」と「画像」を並べる。表にはしない (gh が表のセルの中の画像参照も書き換えるかは確かめていない)。画像参照の alt には `state` を使い、`|` と `]` は全角に置き換える。

```markdown
### 画面

#### （US-003）会員がメールアドレスを入力して登録すると、確認メールの案内が出る

**1. 会員登録画面 (初期表示)**

![会員登録画面 (初期表示)](/abs/evidence-12/screens/01-screen.png)

**2. 登録ボタンを押した後 (確認メールの案内)**

![登録ボタンを押した後 (確認メールの案内)](/abs/evidence-12/screens/02-screen.png)
```

画像参照のパスは `file` の絶対パスをそのまま書く。[6/6] で同じパスを `--attach` に渡すと、gh がアップロード先の URL に書き換える。

**API** (`api` が 1 件以上): ケースごとに `<details>` で折りたたむ。`file` の 1 行目から `$ ` を除いたものをコマンド、3 行目以降を実行結果として書く。

````markdown
### API

<details>
<summary>POST /api/members — 成功</summary>

リクエスト:

```sh
curl -sS -i -X POST http://localhost:43123/api/members -H "Content-Type: application/json" -H "Authorization: <masked>" -d '{"email":"member@example.com"}'
```

実行結果:

```http
HTTP/1.1 201 Created
content-type: application/json

{"id":"m_01","email":"member@example.com","status":"申請中"}
```

</details>
````

**画面も API も無いとき**: `## 動作確認` の下に `該当なし (<note>)` の 1 行を書く。証跡なしを選んだときは `該当なし (証跡なし)`、非対話モードで `--evidence` が無いときは `該当なし (証跡マニフェスト未指定)` と書く。

**`note` が空でないとき**は、画面・API の記載に加えて `補足: <note>` の 1 行を節の末尾に書く (例: 動線外の変更の注記)。

### 4.3 シークレット混入チェック

最終本文 (埋め込んだ API の実行結果を含む) を次のパターンで検査する。パターンは `references/evidence.md` が証跡のマスクに使うものと同じである。

```bash
rg -n '(?i)(authorization|cookie):[[:space:]]*[^<[:space:]"]|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.|(^|[^A-Za-z0-9])(ghp_|gho_|ghs_|sk-)[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}' <最終本文のファイル>
```

あわせて、`password` / `secret` / `api_key` / `token` の値部分と、`.env` ファイル内容のような `KEY=VALUE` 形式の値が無いかを読んで確かめる。

- **手動モード**: 見つかったらマスクするか除外し、ユーザーに伝える
- **非対話モード**: マスクせず、PR を作らずに `PR_FAILED secret_detected <ファイル>:<行>` を返す。黙ってマスクすると、証跡が欠けたことを呼び出し元が知らないまま PR が作られる

### 4.4 最終本文の書き出し

最終本文を Write ツールで書き出す。書き出し先は、`--body-file` があれば `<body-file>.final.md`、無ければ `<git-dir>/PR_BODY.md` (`git -C "$REPO_DIR" rev-parse --absolute-git-dir` の下。追跡されず、ホーム直下も汚さない)。以降の手順と [6/6] はこのファイルを `--body-file` で渡す。本文を `--body` の引数や HEREDOC で渡さない (`<details>` を含む長い本文を二度出力することになり、特殊文字も壊れやすい)。

書き出したら、本文の画像参照と添付するファイルが一致することを確かめる。一致しないと、添付されなかったローカルのパスが PR に残る。

```bash
rg -o '!\[[^]]*\]\(([^)]+)\)' -r '$1' <最終本文のファイル> | sort
# 出力が screens[].file を並べたもの (sort 済み) と同じであること
```

[1/6] で gh が添付に対応していなかったときや、スクリーンショットが無いときは、期待する出力は空である。

---

## [5/6] 確認

### タイトル

`--title` があればそれを使う。無ければ次のルールで生成する:

1. コミットが1件 → そのコミットメッセージの 1 行目をそのまま使用
2. コミットが複数 → Conventional Commit 形式で要約（例: `feat: ユーザー認証にバリデーションを追加`）
3. 既存ブランチ名から推測できる場合は補助情報として利用

タイトルは 72 文字以内に収める。

### 非対話モード

確認せずに次の 1 ブロックを表示して [6/6] へ進む:

```
PR を作成します: <REPO> <base> <- <head> / <title> / Draft: <yes|no> / 添付 <n> 枚 / API <m> 件
```

### 手動モード

ユーザーに以下の形式で提示する:

```
==================== PR Preview ====================

Repo:  <REPO>
Base:  <base>
Head:  <head>
Draft: <yes|no>

Title: <生成したタイトル>

添付するスクリーンショット: <n> 枚
  - <screens[].file を 1 行ずつ>

Body:
---
<最終本文>
---

====================================================
```

「上記の内容で PR を作成しますか？」と聞き、次の 4 択から 1 つだけ選ばせる。スクリーンショットは GitHub にアップロードされて PR の閲覧者が見られるようになる。この確認で「この内容で作成」が選ばれたことを、添付の承認として扱う。

| 選択肢 | 意味 |
| --- | --- |
| この内容で作成 | 提示した内容のまま PR を作成し、スクリーンショットを添付する |
| タイトルを編集 | タイトルだけ修正してから作成 |
| 本文を編集 | 本文を修正してから作成 (修正指示を入力) |
| キャンセル | PR 作成を中止 |

**「タイトルを編集」「本文を編集」選択時**: 続けて修正内容をユーザーに聞き、最終本文のファイルを書き直してから再度プレビューを表示して再確認する。「この内容で作成」が選ばれるまで繰り返す。

**「キャンセル」選択時**: 「PR作成をキャンセルしました。」と表示して終了。

---

## [6/6] PR の作成

### リモートブランチの確認と自動push

upstream の有無を確認:

```bash
git -C "$REPO_DIR" rev-parse --abbrev-ref --symbolic-full-name "<head>@{u}" 2>/dev/null
```

- upstream が未設定: `git -C "$REPO_DIR" push -u origin <head>` を**無条件で実行**（ユーザー確認なし）
- upstream が設定済みで、`git -C "$REPO_DIR" rev-list "<head>@{u}..<head>" --count` が 1 以上: `git -C "$REPO_DIR" push origin <head>` を**無条件で実行**
- それ以外 (push 済み): 何もしない

push失敗時:

| エラー内容 | 手動モード | 非対話モード |
| ---------- | ---- | ---- |
| `non-fast-forward`（リモートが先行） | 状況を表示し、「`git pull --rebase` 後に再push / 中止」のどちらにするかをユーザーに確認 | `PR_FAILED push_rejected` |
| 認証エラー                           | `gh auth refresh` の実行を促して終了 | `PR_FAILED push_auth` |
| その他                                | エラー出力を表示し、再実行するか中止するかをユーザーに確認 | `PR_FAILED push_failed <エラーの 1 行目>` |

### gh pr create の実行

```bash
gh pr create --repo "$REPO" --base "<base>" --head "<head>" \
  --title "<title>" --body-file "<最終本文のファイル>" \
  --attach "<screens[0].file>" --attach "<screens[1].file>"
```

- `--draft` 引数があったときだけ `--draft` を付ける
- `--attach` は `screens[].file` を全件、1 つずつ渡す。スクリーンショットが無い、または [1/6] で gh が添付に対応していなかったときは付けない
- gh は、本文の `![alt](<path>)` のうち `--attach` と同じファイルを指す参照を、アップロード先の URL に書き換える。参照されていない添付は本文の末尾に足される
- 一部の添付だけが失敗しても PR は作られ、gh は非ゼロで終了する。そのときは下の「作成結果の確認」で本文を読み直し、ローカルのパスが残っていないかを確かめる

### 同じ head の PR が既にあるとき

`a pull request for branch ... already exists` で失敗したら、その PR の本文と添付を更新する。同じ呼び出しを再実行したときに証跡が付かないまま終わらないようにするためである。

```bash
PR_NUM=$(gh pr list --repo "$REPO" --head "<head>" --json number -q '.[0].number')
gh pr edit "$PR_NUM" --repo "$REPO" --title "<title>" --body-file "<最終本文のファイル>" \
  --attach "<screens[0].file>" --attach "<screens[1].file>"
```

`PR_NUM` が空なら更新せず、手動モードではエラーを表示し、非対話モードでは `PR_FAILED pr_lookup` を返す。既存の本文は最終本文で置き換わる。手動モードでは、置き換える前に `gh pr view "$PR_NUM" --repo "$REPO" --json body -q .body` で既存の本文を見せ、人が書き足した内容が消えてよいかを確かめる。

### 作成結果の確認

作成または更新の後に本文を読み直す。

```bash
gh pr view "<PR の URL か番号>" --repo "$REPO" --json url,isDraft -q '.url, .isDraft'
gh pr view "<PR の URL か番号>" --repo "$REPO" --json body -q .body | rg -n '!\[[^]]*\]\(/'
```

2 つ目のコマンドが何か出したら、画像参照にローカルの絶対パスが残っている (添付に失敗した画像)。画像ではないリンク (`[設計書](/docs/...)`) には反応しない。手動モードではユーザーに伝え、非対話モードでは `PR_FAILED attach_partial <PR の URL>` を返す。PR 自体はできているので、呼び出し元はこの URL で状況を確かめられる。

手動モードの表示:

```
✓ PR を作成しました

  URL:   https://github.com/<owner>/<repo>/pull/<number>
  Base:  <base>
  Head:  <head>
  Draft: <yes|no>
  添付:  <n> 枚
```

非対話モードは、最後の行を次のどれか 1 行にする。呼び出し元はこの行だけで分岐する。

| 最終行 | 意味 |
| --- | --- |
| `PR_CREATED <url>` | 新しく作成した |
| `PR_UPDATED <url>` | 同じ head の既存 PR の本文と添付を更新した |
| `PR_FAILED <理由> [詳細]` | 作成も更新もしていない (`attach_partial` だけは PR がある) |

### エラー時のハンドリング

| エラー内容                                | 手動モード | 非対話モード |
| ----------------------------------------- | ---- | ---- |
| `a pull request for branch ... already exists` | 上の「同じ head の PR が既にあるとき」 | 同左 |
| `Resource not accessible by integration`       | 権限不足。`gh auth refresh -s repo` の実行を促す | `PR_FAILED permission` |
| その他                                          | エラー出力を表示し、再実行するか中止するかをユーザーに確認 | `PR_FAILED gh_error <エラーの 1 行目>` |

---

## 重要な注意事項

### Draft は指定したときだけ

`--draft` があるときだけ Draft PR にする。dev-impl は作成後に CI の pass を待って (CI があれば) そのまま merge するため `--draft` を渡さない (Draft PR は merge できない)。

### 本文はファイルで渡す

本文は [4/6] で書き出したファイルを `--body-file` で渡す。`--body` の引数に直接書くと、改行やバッククォート、`$` 記号が壊れる。

### テンプレートのHTMLコメント

`<!-- ... -->` 内の指示はテンプレート作者からPR作成者への指示であり、PR本文には残さない。生成時に削除する。

### ローカルのパスと秘密を PR に載せない

本文の画像参照は、全て `--attach` で添付するファイルを指していなければならない ([4/6] 4.4 の照合)。API の実行結果はマスク済みであることを [4/6] 4.3 で確かめる。

### 確かめていない前提

次の 3 点は gh 2.102.0 のソースとヘルプから推した挙動で、実際の PR では確かめていない。

- `gh pr edit --attach` も本文の画像参照を書き換える (`gh pr create` と同じ `internal/attachments` パッケージを使うため)
- `gh pr create --repo --head` は、作業ディレクトリが同じリモートを持つ別の作業ツリー (dev-impl の並列実行で、メインの作業ツリーから worktree のブランチを指す場合) でも動く
- 表のセルの中の画像参照も書き換わるか (分からないので表に画像を入れない)

### ブランチ作成とコミット作成の責務範囲

本スキルは「**PR作成までの最低限の準備**」を目的とする:

- ブランチ作成は **手動モードで、PR用のブランチが無い場合に限り** 行う。既存ブランチがあればそのまま使用。ブランチ名は自動生成し、ユーザー確認は行わない（やり直したい場合はPR作成後に手動で `git branch -m` で改名すればよい）
- コミット作成は **手動モードで、未コミット変更がある場合のみ** `workflow-commit` に無条件で委譲する。論理単位での分割や Conventional Commit 形式への整形はそちらに任せる
- push は **未push or ローカルが先行している場合に自動実行**。確認は行わない（push失敗時のみエラーハンドリング）
- 既存コミットには触らない（amend/rebase/squash は対象外）

### スコープ外

- 証跡の収集 (スクリーンショットの撮影・API の実行): `references/evidence.md` に従って呼び出し元が行う
- Draft から Ready for Review への切り替え: `gh pr ready` で対応
- 既存 PR の更新: 同じ head の PR の本文・添付の更新だけを行う ([6/6])。それ以外の編集は `gh pr edit` で対応
- マージ: `gh pr merge` で対応
- 既存コミットの修正・分割・squash: `git rebase -i` 等で別途対応
