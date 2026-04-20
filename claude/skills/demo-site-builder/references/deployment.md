# Deployment: Cloudflare Workers Static Assets

2025 年以降の Cloudflare 公式推奨である **Workers + Static Assets (assets-only)** で静的 SPA をデプロイする。Pages ではなく Workers を使う理由：

- Cloudflare の新規プロジェクト公式推奨
- 将来 Worker コードを足したくなった時の拡張パスが明確
- `wrangler.jsonc` 一本で設定完結

## 目次

- Step 1: wrangler CLI 導入
- Step 2: wrangler.jsonc を作成
- Step 3: package.json に deploy scripts
- Step 4: .gitignore に追加
- Step 5: dry-run で設定検証（認証不要）
- Step 6: GitHub Actions ワークフロー
- Step 7: Deploy Token を gist スクリプトで発行
- Step 8: 初回デプロイ
- Step 9: 動作確認
- カスタムドメイン
- よくある落とし穴

## Step 1: wrangler CLI 導入

```bash
pnpm add -D wrangler
```

## Step 2: wrangler.jsonc を作成

プロジェクトルートに：

```jsonc
{
  "$schema": "node_modules/wrangler/config-schema.json",
  "name": "<project-name>",
  "compatibility_date": "<YYYY-MM-DD today>",
  "assets": {
    "directory": "./dist/"
  }
}
```

- **`main` は書かない** → assets-only モードで静的配信のみ
- **`not_found_handling` は不要**：このスキルは `HashRouter` を使うので、URL は `/#/path` 形式になりサーバ側のフォールバック設定に依存しない。将来 BrowserRouter に切り替える場合のみ `"not_found_handling": "single-page-application"` を追加する
- **`compatibility_date` は実行日**（`date +%Y-%m-%d` で取得可）。未来日付は Wrangler が reject する
- assets の `directory` は Vite のビルド出力 `./dist/`

assets/wrangler.jsonc にテンプレートあり → `<project-name>` を書き換えてコピー。

## Step 3: package.json に deploy scripts

```json
{
  "scripts": {
    "deploy": "pnpm build && wrangler deploy",
    "deploy:dry-run": "pnpm build && wrangler deploy --dry-run",
    "cf:preview": "pnpm build && wrangler dev"
  }
}
```

## Step 4: .gitignore に追加

```
.wrangler
.dev.vars
```

## Step 5: dry-run で設定検証（認証不要）

```bash
pnpm run deploy:dry-run
```

`✨ Read N files from the assets directory` と `--dry-run: exiting now.` で正常。

## Step 6: GitHub Actions ワークフロー

`.github/workflows/deploy.yml` に以下を配置（`assets/deploy-workflow.yml` を参照）：

```yaml
name: Deploy to Cloudflare Workers

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
        with:
          version: 10
      - uses: actions/setup-node@v4
        with:
          node-version: 24
          cache: pnpm
      - name: Install dependencies
        run: pnpm install --frozen-lockfile
      - name: Run tests
        run: pnpm test
      - name: Type check
        run: pnpm typecheck
      - name: Build
        run: pnpm build
      - name: Deploy to Cloudflare Workers
        uses: cloudflare/wrangler-action@v3
        with:
          apiToken: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          accountId: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
```

## Step 7: Deploy Token を gist スクリプトで発行

**前提（セットアップ済み）**:
- 1Password に `Cloudflare Token` アイテムがあり、`credential` に Master Token（`User API Tokens: Edit` + `User Details: Read` 権限付与済み）、`account_id` に Account ID を保持
- `~/.zprofile` に以下が設定済み：
  ```bash
  export CF_TOKEN_1P_REF="op://Personal/Cloudflare Token/credential"
  export CF_ACCOUNT_1P_REF="op://Personal/Cloudflare Token/account_id"
  ```

### スクリプト実行（スキル配下のローカルスクリプト）

スクリプトはこのスキルの `assets/cf-issue-deploy-token.sh` に同梱されている。`claude/install.sh` により `~/.claude/skills/demo-site-builder/` に symlink されるため、固定パスで参照可能：

```
~/.claude/skills/demo-site-builder/assets/cf-issue-deploy-token.sh
```

各プロジェクトでの実行：

```bash
cd <新プロジェクトのルート>

# dry-run で事前検証
bash ~/.claude/skills/demo-site-builder/assets/cf-issue-deploy-token.sh --dry-run <project-name>

# 本番実行
bash ~/.claude/skills/demo-site-builder/assets/cf-issue-deploy-token.sh <project-name>
```

スクリプトがやること：
1. `op read` で Master Token / Account ID を 1Password から取得
2. Cloudflare API `POST /user/tokens` で `<project-name>-deploy` という名前の子 token を発行（権限: `Workers Scripts Write` のみ、account スコープ限定）
3. `gh secret set` で対象 repo に `CLOUDFLARE_API_TOKEN` と `CLOUDFLARE_ACCOUNT_ID` を登録

## Step 8: 初回デプロイ

```bash
git add wrangler.jsonc .github/workflows/deploy.yml
git commit -m "🔧 chore: [STRUCTURAL] add Cloudflare Workers deployment config"
git push origin main
```

GitHub Actions が起動し、test → typecheck → build → deploy が順次実行。

## Step 9: 動作確認

### workflow の完了を待つ
```bash
gh run list --limit 3
gh run watch <run-id> --exit-status
```

### デプロイ URL を取得
```bash
gh run view <run-id> --log | grep -i 'workers\.dev'
# → https://<project>.<subdomain>.workers.dev
```

### 実機確認（chrome-devtools MCP）
```
1. chrome-devtools:new_page に URL を渡す
2. chrome-devtools:emulate で 390x844x3,mobile,touch
3. navigate_page reload
4. take_screenshot
5. ログインなど主要フロー実行
6. list_console_messages でエラーなし確認
```

## カスタムドメイン

後付けで dashboard から：**Workers & Pages → `<project>` → Settings → Domains & Routes → Add**。DNS レコードは Cloudflare 側で自動追加（Zone を Cloudflare が管理している場合）。

## よくある落とし穴

### Cloudflare API 9109 "Unauthorized to access requested resource"
Master Token の権限不足。以下を追加：
- User API Tokens: Edit
- User Details: Read

### 1Password CLI "Private isn't a vault in this account"
UI 表示と内部 vault 名が違う（"個人" ↔ "Personal"）。`op vault list` で実名確認。

### op ref で日本語が "invalid character"
vault 名が非 ASCII なら使えない。item ID で指定するか、item/vault 名を ASCII にリネーム。

### gh secret set で token がプロセスリストに露出
`--body "$VALUE"` より `printf '%s' "$VALUE" | gh secret set NAME` を使う。

### Cloudflare Worker が存在しないと deploy 失敗する？
**しない**。初回 `wrangler deploy` で `wrangler.jsonc` の `name` に基づき自動作成される。Dashboard で事前作成は不要。

### `compatibility_date` を未来日付にしてしまった
Wrangler がエラーで落ちる。実行日以前の日付に修正。
