---
name: workflow-create-draft-pr
description: "ローカルのコミット履歴と差分からDraft PRを作成する。ブランチ未作成・コミット未作成の状態でも、必要に応じてブランチ作成とコミットを行ってからPRを作成する。`.github/` にPRテンプレートがあれば内容を埋めて、なければ作業内容から本文を生成し、`AskUserQuestion`で作成可否を確認してから `gh pr create --draft` を実行する。「PRを出したい」「draft PRを作成」「プルリクを作って」「PR本文を生成」などのリクエストで起動。"
argument-hint: "[--base <branch>]"
model: haiku
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git rev-parse:*), Bash(git symbolic-ref:*), Bash(git branch:*), Bash(git switch:*), Bash(git remote:*), Bash(git push:*), Bash(gh pr create:*), Bash(gh pr view:*), Bash(gh repo view:*), Bash(gh auth status:*), Read, Glob, AskUserQuestion, Skill
---

# /workflow-create-draft-pr - Draft PR作成コマンド

ローカルのコミット履歴と差分を元に、適切なPR本文を生成して **Draft PR** を作成します。
`.github/` に Pull Request テンプレートがある場合は内容を埋め、なければ作業内容から本文を生成します。

ブランチが未作成（ベースブランチ上）の場合や、未コミットの変更がある場合も、必要な作業を提案・実行してからPRを作成します。
PR本文は作成前に必ず提示し、`AskUserQuestion` でユーザーの作成指示を受け取ります。

## 使い方

```
/workflow-create-draft-pr                  # デフォルトブランチ基準でDraft PRを作成
/workflow-create-draft-pr --base develop   # 指定ブランチ基準でDraft PRを作成
```

---

## [1/6] 前提条件の確認

### 引数の解析

```
引数: $ARGUMENTS
- --base <branch>: ベースブランチを明示指定
- 空: デフォルトブランチを自動検出
```

### gitリポジトリ確認

Bashツールで以下を実行:

```bash
git rev-parse --git-dir 2>/dev/null
```

gitリポジトリでない場合は「このディレクトリはgitリポジトリではありません。」と表示して終了。

### gh CLI 認証確認

```bash
gh auth status 2>&1
```

認証されていない場合は「`gh auth login` で GitHub CLI にログインしてください。」と表示して終了。

### 現在のブランチと作業状態の取得

```bash
git rev-parse --abbrev-ref HEAD      # 現在のブランチ名
git status --porcelain               # 未コミット/未追跡変更
```

ここで取得した「現在ブランチ」「未コミット変更の有無」を以降のステップで使用する。
**この時点では強制終了しない**（ベース上にいても次ステップで処理する）。

### ベースブランチの決定

優先順位:

1. `--base <branch>` 引数で明示指定
2. `gh repo view --json defaultBranchRef -q .defaultBranchRef.name` でデフォルトブランチ取得
3. 取得失敗時は `git symbolic-ref refs/remotes/origin/HEAD` から推測（`refs/remotes/origin/<branch>` の末尾）
4. それでも決まらない場合は `AskUserQuestion` で確認

---

## [2/6] ブランチとコミットの準備

[1/6] で取得した「現在ブランチ」「未コミット変更」「ベースブランチ」を元に、以下のフローで PR 作成可能な状態に整える。

### ケース判定

| 現在ブランチ | 未コミット変更 | 対応                                            |
| ------------ | -------------- | ----------------------------------------------- |
| = ベース     | あり           | 2.1 ブランチ作成 → 2.2 コミット作成             |
| = ベース     | なし           | エラー終了（PR対象の作業がない）                |
| ≠ ベース    | あり           | 2.2 コミット作成（ブランチ作成はスキップ）      |
| ≠ ベース    | なし           | スキップして [3/6] へ（既存コミットでPR作成）   |

### 2.1 ブランチ作成（現在ブランチ = ベースの場合）

#### ブランチ名の自動生成

`git diff` および `git status` の内容から Conventional Commit 形式のプレフィックスと簡潔な英語名を生成する。**ユーザー確認は行わず、生成した名前でそのまま作成する**。

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

#### ブランチ作成の実行

```bash
git switch -c <generated-branch-name>
```

#### 既存ブランチ名と衝突した場合

末尾に短い識別子（`-2`, `-3`, ...）を付与して再試行する。3回試して失敗したらエラー表示して終了。

### 2.2 コミット作成（未コミット変更がある場合）

`workflow-commit` スキルに **無条件で委譲** する（ユーザー確認なし）。
`workflow-commit` は push を行わないスキルなので、push は本スキルの [6/6] でまとめて行う。

完了後、`git status --porcelain` で未コミット変更が残っていないことを確認する。
残っている場合は `workflow-commit` が意図的にスキップした可能性があるため、ユーザーに状況を報告して `AskUserQuestion` で続行/中止を確認。

---

## [3/6] 作業内容の収集

### コミット履歴の取得

```bash
git log <base>..HEAD --pretty=format:"%h %s"
```

コミットが0件の場合:
- 「ベースブランチとの差分がありません。」と表示して終了

### 差分サマリーの取得

```bash
git diff <base>...HEAD --stat
```

### 詳細差分の取得（本文生成用）

```bash
git diff <base>...HEAD
```

差分が大きい場合（10,000行超など）は、ファイルリストと統計のみで本文を生成する。

### 変更ファイルの分類

`git diff <base>...HEAD --name-status` の出力を以下に分類:

| ステータス | 意味 |
| ---------- | ---- |
| `A`        | 新規追加 |
| `M`        | 修正 |
| `D`        | 削除 |
| `R`        | リネーム |

---

## [4/6] PRテンプレートの検出

### テンプレートファイルの検索

Glob ツールで以下を以下の優先順位で検索（大文字小文字を区別しない、最初に見つかったものを採用）:

1. `.github/pull_request_template.md`
2. `.github/PULL_REQUEST_TEMPLATE.md`
3. `.github/pull_request_template/*.md`（複数テンプレート）
4. `.github/PULL_REQUEST_TEMPLATE/*.md`（複数テンプレート）
5. `docs/pull_request_template.md`
6. `PULL_REQUEST_TEMPLATE.md`（リポジトリルート）

複数テンプレートディレクトリの場合は、`AskUserQuestion` で使用するテンプレートを選択させる。

### テンプレートがある場合

Read ツールで内容を読み込み、以下のルールで埋める:

| 構造                       | 処理                                                                  |
| -------------------------- | --------------------------------------------------------------------- |
| 見出し (`## Summary` 等)   | コミット履歴と差分から該当する内容を生成                              |
| HTMLコメント `<!-- ... -->` | テンプレート上の指示として読み取り、本文には残さない                  |
| チェックリスト `- [ ]`     | 作業内容から判断できるものはチェック、判断できないものは `- [ ]` のまま |
| プレースホルダ `<...>`     | 該当する内容で置換                                                    |

### テンプレートがない場合

以下の標準構造で本文を生成する:

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

### シークレット混入チェック

生成した本文に以下のパターンが含まれていないか確認し、見つかったらマスクするか除外:

- `password`, `secret`, `api_key`, `token` の値部分
- トークンプレフィックス: `ghp_`, `gho_`, `ghs_`, `sk-`, `AKIA`
- `.env` ファイル内容のような `KEY=VALUE` 形式の値

---

## [5/6] PR本文の提示と確認

### タイトル生成

ルール:

1. コミットが1件 → そのコミットメッセージの 1 行目をそのまま使用
2. コミットが複数 → Conventional Commit 形式で要約（例: `feat: ユーザー認証にバリデーションを追加`）
3. 既存ブランチ名から推測できる場合は補助情報として利用

タイトルは 72 文字以内に収める。

### 本文の表示

ユーザーに以下の形式で提示する:

```
==================== Draft PR Preview ====================

Base: <base>
Head: <current-branch>

Title: <生成したタイトル>

Body:
---
<生成した本文（テンプレート埋め or 生成）>
---

==========================================================
```

### AskUserQuestionで作成指示を受け取る

```javascript
AskUserQuestion({
  questions: [
    {
      question: "上記の内容で Draft PR を作成しますか？",
      header: "PR作成",
      options: [
        {
          label: "この内容で作成",
          description: "提示した内容のまま Draft PR を作成する"
        },
        {
          label: "タイトルを編集",
          description: "タイトルだけ修正してから作成"
        },
        {
          label: "本文を編集",
          description: "本文を修正してから作成（修正指示を入力）"
        },
        {
          label: "キャンセル",
          description: "PR作成を中止"
        }
      ],
      multiSelect: false
    }
  ]
})
```

**「タイトルを編集」「本文を編集」選択時**:
- 続けて `AskUserQuestion` で修正内容を受け取り、再度プレビューを表示して再確認
- 「この内容で作成」が選ばれるまで繰り返す

**「キャンセル」選択時**:
- 「PR作成をキャンセルしました。」と表示して終了

---

## [6/6] Draft PR の作成

### リモートブランチの確認と自動push

upstream の有無を確認:

```bash
git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null
```

#### upstream が未設定の場合

`git push -u origin <current-branch>` を **無条件で実行**（ユーザー確認なし）。

```bash
git push -u origin <current-branch>
```

#### upstream が設定済み、かつローカルが先行している場合

`git status -sb` または `git rev-list @{u}..HEAD --count` が 1 以上 の場合、`git push` を **無条件で実行**。

```bash
git push
```

#### push失敗時

| エラー内容 | 対応 |
| ---------- | ---- |
| `non-fast-forward`（リモートが先行） | 状況を表示し、`AskUserQuestion` で「`git pull --rebase` 後に再push / 中止」を確認 |
| 認証エラー                           | `gh auth refresh` の実行を促して終了 |
| その他                                | エラー出力を表示して `AskUserQuestion` で再実行/中止を確認 |

### gh pr create の実行

本文は HEREDOC で渡して改行・特殊文字を保持する:

```bash
gh pr create --draft \
  --base "<base>" \
  --title "<title>" \
  --body "$(cat <<'EOF'
<body>
EOF
)"
```

必須フラグ:

- `--draft` （**必須**、通常PRにしない）
- `--base` （Step 1 で決定したベース）
- `--title`, `--body`

### 作成結果の表示

`gh pr create` の出力（PR URL）をそのまま表示する:

```
✓ Draft PR を作成しました

  URL: https://github.com/<owner>/<repo>/pull/<number>
  Base: <base>
  Head: <current-branch>
```

### エラー時のハンドリング

| エラー内容                                | 対応                                                                |
| ----------------------------------------- | ------------------------------------------------------------------- |
| `a pull request for branch ... already exists` | 既存PRの URL を `gh pr view --json url -q .url` で取得して表示 |
| `Resource not accessible by integration`       | 権限不足。`gh auth refresh -s repo` の実行を促す                |
| その他                                          | エラー出力を表示し、再実行 / 中止を `AskUserQuestion` で確認    |

---

## 重要な注意事項

### 必ず Draft で作成

`gh pr create` には **必ず** `--draft` を付ける。レビュー準備が整ってから手動で Ready for Review に切り替える運用。

### bodyは HEREDOC で渡す

`--body` を引数で直接渡すと、改行やバッククォート、`$` 記号が壊れるため、必ず HEREDOC (`<<'EOF' ... EOF`) で渡す。
シングルクォート `'EOF'` を使うことで変数展開を抑止する。

### テンプレートのHTMLコメント

`<!-- ... -->` 内の指示はテンプレート作者からPR作成者への指示であり、PR本文には残さない。生成時に削除する。

### シークレット混入の防止

差分や本文に秘密情報が含まれていないか必ずチェックする。検出した場合はマスクする、もしくは作成を中止して報告する。

### ブランチ作成とコミット作成の責務範囲

本スキルは「**PR作成までの最低限の準備**」を目的とする:

- ブランチ作成は **PR用のブランチが無い場合に限り** 行う。既存ブランチがあればそのまま使用。ブランチ名は自動生成し、ユーザー確認は行わない（やり直したい場合はPR作成後に手動で `git branch -m` で改名すればよい）
- コミット作成は **未コミット変更がある場合のみ** `workflow-commit` に無条件で委譲する。論理単位での分割や Conventional Commit 形式への整形はそちらに任せる
- push は **未push or ローカルが先行している場合に自動実行**。確認は行わない（push失敗時のみエラーハンドリング）
- 既存コミットには触らない（amend/rebase/squash は対象外）

### スコープ外

- 通常PR（非Draft）の作成: 別途 `gh pr ready` または手動切り替えで対応
- 既存PRの更新: `gh pr edit` で対応（本スキルの対象外）
- マージ: `gh pr merge` で対応（本スキルの対象外）
- 既存コミットの修正・分割・squash: `git rebase -i` 等で別途対応
