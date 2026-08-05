# deploy-setup: Cloudflare へのデプロイ設定

- 種別: 手順書
- 対象: `fullstack-app-builder` スキルの本体 Step 6

`wrangler.jsonc` と `.github/workflows/deploy.yml` はテンプレートに同梱済みなので、ここで行うのは **GitHub Secrets の登録と、初回 push が green になることの確認**だけ。

前提コマンド: `gh` / `op` (1Password CLI) / `curl` / `jq` (後 3 つは deploy token 発行スクリプトが要求する)。

## 目次

- 前提: テンプレート同梱の CD 構成
- D-1: deploy token の発行と Secrets 登録
- D-2: 初回 push と Actions の確認
- D-3: 本番 URL での疎通確認
- 本番 Cognito (terraform prod) について
- よくある落とし穴

## 前提: テンプレート同梱の CD 構成

`.github/workflows/deploy.yml` は `main` への push (`**.md` と `LICENSE` のみの変更は除外) で以下を順に実行する:

1. `vp install --frozen-lockfile`
2. `vp test` (フロント) → `vp exec vitest run -c vitest.workers.config.ts` (Worker)
3. `vp check` → `vp build`
4. `vp exec wrangler d1 migrations apply <project-name>-db --remote` — **リモート D1 へのマイグレーション適用**
5. `vp exec wrangler deploy`

必要な Secrets は `CLOUDFLARE_API_TOKEN` と `CLOUDFLARE_ACCOUNT_ID` の 2 つ。**`scaffold.md` Step D-1 (deploy.yml のリポジトリ名ガード削除) が済んでいること**を先に確認する。残っていると deploy ジョブが skipped になり、Secrets を正しく登録しても何も起きない。

```bash
rg 'repository.name' .github/workflows/deploy.yml   # 0 件であること
```

## D-1: deploy token の発行と Secrets 登録

`demo-site-builder` スキルの発行スクリプトを再利用する (同じ Cloudflare アカウント・同じ 1Password アイテムを使うため、スクリプトを二重管理しない):

```bash
ls ~/.claude/skills/demo-site-builder/assets/cf-issue-deploy-token.sh
```

存在すれば:

```bash
# dry-run で事前検証
bash ~/.claude/skills/demo-site-builder/assets/cf-issue-deploy-token.sh --dry-run <project-name>

# 本番実行 (token 発行 + gh secret set まで行う)
bash ~/.claude/skills/demo-site-builder/assets/cf-issue-deploy-token.sh <project-name>
```

スクリプトは 1Password から Master Token / Account ID を読み、`<project-name>-deploy` という子 token を発行して `CLOUDFLARE_API_TOKEN` / `CLOUDFLARE_ACCOUNT_ID` を対象リポジトリに登録する。

### D1 権限の追加が必要

スクリプトが発行する token の権限は **`Workers Scripts Write` のみ** (`wrangler deploy` に必要な権限)。これは静的 SPA (`demo-site-template`) 向けの最小権限で、このテンプレートの deploy.yml が実行する `wrangler d1 migrations apply --remote` はカバーしていない。

Cloudflare dashboard (My Profile → API Tokens → 発行した `<project-name>-deploy` → Edit) で **`D1: Edit` (Account スコープ) を追加する**。権限の編集で token の値は変わらないので、Secrets の再登録は不要。

結果として token が持つべき権限は次の 2 つになる:

| 権限 | スコープ | 用途 | 発行時点 |
| --- | --- | --- | --- |
| Workers Scripts: Edit (= Write) | Account | `wrangler deploy` | スクリプトが付与済み |
| D1: Edit | Account | `wrangler d1 migrations apply --remote` | **手動で追加する** |

スクリプトが無い / 1Password を使わない場合は、dashboard で "Create Custom Token" から上記 2 権限を持つ token を作り、手動で登録する:

```bash
printf '%s' "$TOKEN"      | gh secret set CLOUDFLARE_API_TOKEN
printf '%s' "$ACCOUNT_ID" | gh secret set CLOUDFLARE_ACCOUNT_ID
```

`gh secret set --body "$値"` は使わない (プロセスリストに値が露出する)。

```bash
gh secret list    # 2 件が登録されていること
```

## D-2: 初回 push と Actions の確認

```bash
git push origin main
gh run list --limit 3
gh run watch <run-id> --exit-status
```

push 時は lefthook の `pre-push` フックが `vp check` + `vp build` をローカルで実行する。ここで落ちたら push 自体がブロックされるので、CI に行く前に気付ける。

`ci.yml` と `deploy.yml` の 2 つが起動する。deploy 側が **skipped ではなく実行されている**ことを確認する。

## D-3: 本番 URL での疎通確認

```bash
gh run view <run-id> --log | grep -i 'workers\.dev'
# → https://<project-name>.<subdomain>.workers.dev

curl -s https://<project-name>.<subdomain>.workers.dev/api/health   # {"status":"ok"}
```

`/api/health` がリモート D1 に到達できていれば、マイグレーション適用と D1 バインディングの両方が成立している。ブラウザで `/home` を開き、API status が `ok` と表示されることも確認する。

Worker は事前作成不要 (初回 `wrangler deploy` で `wrangler.jsonc` の `name` から自動作成される)。

## 本番 Cognito (terraform prod) について

**認証ありのプロジェクトでも、ここまでの手順で本番に上がるのは Worker と D1 だけ**。`wrangler.jsonc` の `vars` (`COGNITO_*`) は空文字のプレースホルダのままなので、デプロイが成功し `/api/health` が 200 を返しても**本番環境ではログインが機能しない**。これは想定どおりで、本番 Cognito の構築はこのスキルの範囲外。

実際にユーザーを受け入れる段階になってから、テンプレート README「GitHub Actions での terraform apply」に従って設定する。必要になるもの:

- Secrets: `AWS_ROLE_ARN` / `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY`
- Variables: `R2_BUCKET` / `R2_ACCOUNT_ID` / `TERRAFORM_APPROVERS` (apply を承認できる GitHub ユーザー名をカンマ区切り。例: `alice,bob`)
- AWS 側の GitHub OIDC Provider と IAM Role (この Terraform 構成には含まれないので手動で 1 度だけ作る)
- `terraform/envs/prod/backend.hcl` (`backend.hcl.example` を元に R2 の接続情報を埋める)
- 適用後の User Pool ID / Client ID / Issuer / JWKS URL を `wrangler secret put` で本番 Worker に設定する (`wrangler.jsonc` の `vars` は空文字のプレースホルダ)

apply は PR コメントに `approve` と書くと走る自前承認フロー (Free プランのプライベートリポジトリでは Environment の Required reviewers が使えないため)。

## よくある落とし穴

- **deploy ジョブが skipped になる** — `scaffold.md` Step D-1 のガード削除漏れ。`rg 'repository.name' .github/workflows/deploy.yml` で確認する
- **`wrangler d1 migrations apply` が権限エラーで落ちる** — token に D1: Edit が無い。`demo-site-builder` のスクリプトが発行する token は Workers Scripts のみなので追加が必要
- **deploy は成功するが `/api/health` が 500** — `wrangler.jsonc` の `database_id` が `__D1_DATABASE_ID__` のまま。ローカルでは検知できない (ローカルは別のエミュレート DB を使うため)
- **Cloudflare API 9109 エラー** — 1Password 側の Master Token に `User API Tokens: Edit` + `User Details: Read` が無い
- **本番でログインできない** — 本番 Cognito が未構築 (上記「本番 Cognito について」)。ローカルの moto は本番には関係しない
- **ドキュメントだけの push でデプロイが走らない** — `paths-ignore: ["**.md", "LICENSE"]` による意図した挙動。強制したいときは `workflow_dispatch` で手動実行する
