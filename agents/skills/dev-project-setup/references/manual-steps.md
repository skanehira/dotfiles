# 人が行う設定

API で自動化できない設定と、人の認証が要る設定。スキルは手順を案内し、終わったかを確かめる。

## 1. Project を更新する GitHub App

GitHub Actions の `GITHUB_TOKEN` は組織の Project を更新できない。また、`GITHUB_TOKEN` で付けたラベルは別のワークフローを起動しないので、`design-approved.yml` のラベル付けも別のトークンで行う。そこで GitHub App を作り、ワークフローが実行のたびに期限 1 時間のトークンを作る (`actions/create-github-app-token`)。長期のトークンを持たないので、期限切れの再発行が要らない。

App は持ち主 (組織) に 1 つ作れば、ほかのリポジトリでも使い回せる。2 つ目以降のリポジトリは、手順 4 と 5 だけを行う。

1. App を作る: `https://github.com/organizations/<組織>/settings/apps/new`
   - GitHub App name: 例 `<組織>-project-sync`
   - Homepage URL: リポジトリの URL など、任意の URL
   - Webhook の Active: 外す (このワークフローは webhook を使わない)
   - Repository permissions の Issues: Read and write
   - Organization permissions の Projects: Read and write
   - Where can this GitHub App be installed?: Only on this account
2. 作成後の画面で Client ID を控える
3. 同じ画面の Private keys で Generate a private key を押し、`.pem` を保存する
4. Install App から組織にインストールする。Only select repositories で対象のリポジトリを選ぶ (既にインストール済みなら、Configure からリポジトリを足す)
5. リポジトリに登録する。登録したら `.pem` は手元から消す

```bash
gh variable set PROJECT_APP_CLIENT_ID --repo <owner>/<repo> --body <Client ID>
gh secret set PROJECT_APP_PRIVATE_KEY --repo <owner>/<repo> < <保存した .pem>
```

確かめ方: `gh variable list --repo <owner>/<repo>` に `PROJECT_APP_CLIENT_ID`、`gh secret list --repo <owner>/<repo>` に `PROJECT_APP_PRIVATE_KEY` が出る。動作は「4. 動作の確認」で確かめる。

個人の持ち物のリポジトリと Project は、App の Projects 権限が組織の Project だけを対象にするので、この方式では動かない見込み (2026-11-10 時点で未検証)。

## 2. Project の組み込みの自動処理

Status は `issue-state-sync.yml` が動かすので、Project の組み込みの自動処理で Status を変えるものは止める。新しい Project の既定の自動処理は「Done」の列を前提にしていて、この運用の列と合わない。

Project の画面 → 右上の「…」→ Workflows で、次を Off にする。

- Item closed
- Pull request merged
- Item reopened
- Item added to project (Status を設定するもの)

「Auto-add to project」は On のままでよい (issue の追加は `issue-state-sync.yml` も行うので、どちらでも動く)。

GraphQL には自動処理を有効・無効にする mutation が無い (`deleteProjectV2Workflow` だけがある。2026-11-10 にスキーマで確認)。

## 3. Project のビュー (任意)

既定のビューは表の形になる。列ごとに並べて見たいときは、新しいビューを Board にして「Group by: Status」を選ぶ。

## 4. 動作の確認

App の登録と PR の merge が済んだら、テスト用の issue で確かめる。

1. `gh issue create --repo <owner>/<repo> --title "dev-project-setup の動作確認" --body "確認が済んだら close する" --label needs-design`
2. 1 分ほどで Project の Status が「設計待ち」になる (Actions の「Issue state sync」の実行結果でも見られる)
3. `gh issue close <番号> --repo <owner>/<repo>` で「完了」になる

失敗したら、Actions の実行ログの最後の行を見る。`Status に列「…」が無い` なら `setup-project.sh` を実行し直す。認証のエラーなら、App の権限 (Issues と Projects) と、インストール先のリポジトリを見直す。
