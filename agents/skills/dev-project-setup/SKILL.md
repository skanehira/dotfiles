---
name: dev-project-setup
description: 新しいリポジトリで本格的な開発を始める前に、AI が issue を整理・設計・実装する運用の土台を用意する。状態のラベル、非公開の GitHub Project と Status の列、ラベルと列を同期する GitHub Actions、設計 PR の merge で ready を付ける GitHub Actions、AGENTS.md の運用の節の雛形を作る。既存のリポジトリに足りないものを足す用途にも使え、何度実行しても結果は変わらない。「プロジェクトをセットアップして」「issue の運用を用意して」「ラベルと Project を作って」「dev-spec の前の準備をして」「このリポジトリに状態のラベルを入れて」などで起動する。/dev-spec より前に使う。
argument-hint: "[owner/repo。省略時はカレントのリポジトリ] [--business] [--project <番号>]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, AskUserQuestion
---

# dev-project-setup

AI が issue の整理・設計・実装を進め、人は設計の確認だけを行う運用の土台を、リポジトリに用意する。

この運用では、**ラベルが状態の正本**で、Project は人が状況を把握するためのものである。AI はラベルだけを読み書きし、Project の Status は GitHub Actions がラベルに合わせて動かす。状態とラベルの対応は `~/.claude/skills/dev-triage/references/issue-states.md`「状態の管理」の表が正本で、`assets/workflows/issue-state-sync.yml`・`scripts/setup-labels.sh`・`scripts/setup-project.sh` はこの表に合わせてあり、`assets/agents-section.md` はラベルの付け替えの手順でこの表を参照する。表を変えるときはこれらを揃える。

状態の定義、着手可能の基準、優先度の定義は dev-triage の references に置き、リポジトリには置かない。プロジェクト固有の定義 (緊急枠、要件の正本など) が要るリポジトリは、人が `docs/ISSUE_TRIAGE.md` を書いてよい。あれば dev-triage と dev-feat-spec がそちらを優先する。このスキルは `docs/ISSUE_TRIAGE.md` を作らない。

## 作るもの

| 対象 | 作り方 | 既にあるとき |
| --- | --- | --- |
| 状態のラベル 6 つ | `scripts/setup-labels.sh` | 色と説明を定義どおりに上書きする |
| 種別のラベル | 同上 | そのまま残す |
| 非公開の Project と Status の列 | `scripts/setup-project.sh` | 足りない列を足す。定義に無い列は、item が無ければ消し、あれば残して警告する |
| リポジトリ変数 `PROJECT_OWNER` / `PROJECT_NUMBER` | 同上 | 上書きする |
| `.github/workflows/issue-state-sync.yml` と `design-approved.yml` | `assets/workflows/` から複製する | 同じなら何もしない。違えば差分を見せて確認する |
| `AGENTS.md` の「issue とボードの運用」 | `assets/agents-section.md` を末尾に足す | 節があれば足さない |
| GitHub App と Project の自動処理の設定 | 人が行う (`references/manual-steps.md`) | 済んでいるかを確かめる |

何度実行しても結果が変わらないように作ってある。途中で失敗したら、原因を直して最初から実行し直してよい。

スクリプトは `bash`、`jq`、`gh` (`project` 権限つきでログイン済み) を使う。ワークフローは `actions/create-github-app-token` と、GitHub のランナーに入っている `gh` と `jq` を使う。

## 手順

### 1. 前提を確かめる

```bash
gh auth status 2>&1 | grep -E 'Token scopes|Logged in'
REPO=${1:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}
gh api "repos/$REPO" --jq '"\(.owner.type) \(.visibility)"'
```

- `gh` のトークンに `project` が無ければ、`gh auth refresh -s project` を案内して止まる (Project を作れないため)
- 引数に `--business` が無ければ、「事業・運営」の issue を扱うかを 1 回だけ聞く。開発の対象外の issue (営業・契約・運用の連絡など) を同じボードに置くプロジェクトでだけ使う
- 既存のリポジトリに使うときは、紐づいている Project の番号を `--project` で受け取るか、`gh api graphql` でリポジトリの `projectsV2` を引いて、どれを使うかを確かめる。タイトルがリポジトリ名と違う Project は自動では見つからない

### 2. ラベルと Project を用意する

```bash
SKILL_DIR=<このスキルのディレクトリ>
bash "$SKILL_DIR/scripts/setup-labels.sh" "$REPO" [--business]
bash "$SKILL_DIR/scripts/setup-project.sh" "$REPO" [--business] [--project <番号>]
```

出力の各行は `created` / `updated` / `kept` / `dropped` / `WARN` のどれかで始まる。完了報告にそのまま使う。

`setup-project.sh` は Status の列を送り直すときに、既存の列の `id` を必ず付ける。`id` を付けずに送ると、その列にある item の Status が消える。手で列を変えるときも同じ注意が要る。

`WARN columns outside the definition still have items` が出たら、その列の issue を状態のラベルに合わせて移すかを人に確かめる。勝手に移さない。

### 3. ワークフローを置く

`assets/workflows/` の 2 本を `.github/workflows/` に複製する。どちらも `actions/create-github-app-token` で GitHub App のトークンを作り、ランナーに入っている `gh` で操作する。`runs-on` は `${{ vars.RUNNER || 'ubuntu-latest' }}` で、リポジトリ変数 `RUNNER` があればその self-hosted runner で、無ければ GitHub のランナーで動く。self-hosted runner のイメージには `gh` と `jq` が要る。

リポジトリが `gh actions-lock` の lockfile (`.github/workflows/actions.lock`) を使っているなら、`gh actions-lock` を実行して lockfile を更新し、同じ PR に含める。lockfile に行の無いワークフローは `gh actions-lock --verify` で失敗する。

既に同名のファイルがあって中身が違うときは、差分を見せて上書きしてよいかを聞く。リポジトリ側で直している可能性があるため。

### 4. 文書の雛形を置く

- `AGENTS.md` に「issue とボードの運用」の節が無ければ、`assets/agents-section.md` を末尾に足す。`AGENTS.md` が無く `CLAUDE.md` があれば、`CLAUDE.md` に足す
- 雛形の `<!-- 記入: Project の URL -->` を埋める。埋められなければ、残った「記入:」を完了報告に載せて、人に埋めてもらう

### 5. 変更を PR にする

ファイルの変更 (ワークフロー 2 本と `AGENTS.md`) は、ブランチを切ってコミットし、PR を出す。デフォルトブランチに直接コミットしない。ラベル・Project・変数はリポジトリの外の設定なので PR には含まれない。PR の本文に「この PR の外で済ませたこと」として列挙する。

### 6. 人が行う設定を案内する

`references/manual-steps.md` を読み、まだ済んでいないものを案内する。

- 変数 `PROJECT_APP_CLIENT_ID` か secret `PROJECT_APP_PRIVATE_KEY` が無ければ、GitHub App の作成と登録を案内する。持ち主に App が既にあれば、インストール先にリポジトリを足して登録するだけで済む
- Project の組み込みの自動処理のうち、Status を変えるものを止めてもらう (この運用の列と合わないため)
- PR の merge と App の登録が済んだら、`references/manual-steps.md`「4. 動作の確認」で確かめる。テスト用の issue を作るので、実行の前に人に確かめる

## 完了報告

次の 4 点を書く。

1. 作ったもの・変えたもの・そのままのもの (スクリプトの出力の行をまとめる)
2. PR の URL と、PR の外で済ませた設定
3. 人がまだ行う設定 (GitHub App、Project の自動処理) と、雛形に残った「記入:」の一覧
4. 動作の確認が済んだか。済んでいなければ、その旨と確かめ方

## 関連

- `/dev-spec`: このスキルの後に、新規開発の設計で使う
- `dev-triage`: 未整理の issue を採点し、状態のラベルを付ける。状態の定義・着手可能の基準・優先度の定義の正本を持つ
- `/dev-impl`: `ready` の issue を実装する。`in-progress` を付け、merge で close する
- 運用の決定の記録: dotfiles の `docs/DESIGN_NOTES.md`
