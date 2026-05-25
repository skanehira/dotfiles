# Deployment: Cloudflare Workers Static Assets

2025 年以降の Cloudflare 公式推奨である **Workers + Static Assets (assets-only)** で静的 SPA をデプロイする。Pages ではなく Workers を使う理由：

- Cloudflare の新規プロジェクト公式推奨
- 将来 Worker コードを足したくなった時の拡張パスが明確
- `wrangler.jsonc` 一本で設定完結

`wrangler` / `wrangler.jsonc` / `.github/workflows/deploy.yml` は **テンプレ `skanehira/demo-site-template` に同梱済み**なので、ここでは追加で行う作業（deploy token 発行、push 後の動作確認）だけを扱う。

## 目次

- 前提：テンプレ同梱済みのデプロイ構成
- Step 1: dry-run で設定検証
- Step 2: Deploy Token を gist スクリプトで発行
- Step 3: 初回デプロイ
- Step 4: 動作確認
- カスタムドメイン
- よくある落とし穴

## 前提：テンプレ同梱済みのデプロイ構成

テンプレ clone + プレースホルダ置換後の状態で、すでに下記が揃っている：

**`wrangler.jsonc`**（プレースホルダは sed で置換済み）：
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
- **`compatibility_date` は実行日**（`date +%Y-%m-%d`）。未来日付は Wrangler が reject する。テンプレ sed で実行日が埋まる

**`package.json` の deploy scripts**：
```json
{
  "scripts": {
    "deploy": "vp build && wrangler deploy",
    "deploy:dry-run": "vp build && wrangler deploy --dry-run",
    "cf:preview": "vp build && wrangler dev"
  }
}
```

**`.github/workflows/deploy.yml`**（`voidzero-dev/setup-vp@v1` ベース）：
- `vp install --frozen-lockfile` → `vp test` → `vp check --no-lint --no-fmt` → `vp build` → `vp exec wrangler deploy`
- deploy は `cloudflare/wrangler-action@v3` を使わず `vp exec wrangler deploy` で直接実行する（wrangler-action は `setup-vp` が用意した `pnpm` を PATH 上で解決できず失敗するため）。`CLOUDFLARE_API_TOKEN` / `CLOUDFLARE_ACCOUNT_ID` は env で渡す
- `paths-ignore: ["**.md", "LICENSE"]` 付き。ドキュメントのみの push ではデプロイが走らない

**`.gitignore`** に `.wrangler` / `.dev.vars` 追加済み。

## Step 1: dry-run で設定検証

認証不要。テンプレ初期化直後でも走らせられる：

```bash
vp run deploy:dry-run
```

`✨ Read N files from the assets directory` と `--dry-run: exiting now.` で正常。

## Step 2: Deploy Token を gist スクリプトで発行

**前提（セットアップ済み）**:
- 1Password に `Cloudflare Token` アイテムがあり、`credential` に Master Token（`User API Tokens: Edit` + `User Details: Read` 権限付与済み）、`account_id` に Account ID を保持
- `~/.zprofile` に以下が設定済み：
  ```bash
  export CF_TOKEN_1P_REF="op://Personal/Cloudflare Token/credential"
  export CF_ACCOUNT_1P_REF="op://Personal/Cloudflare Token/account_id"
  ```

### 事前確認：1Password から Master Token / Account ID を取得できること

スクリプトを走らせる前に、1Password CLI でアイテムが参照できるか確認しておく。未認証なら `eval $(op signin)` を先に実行する：

```bash
# アイテム全体を JSON で取得（credential / account_id 両方のフィールドが見える）
op item get "Cloudflare Token" --vault Personal --format json
```

`fields[].id == "credential"` と `fields[].id == "account_id"` の value が入っていれば OK。スクリプトはこの2つのフィールドを内部で読み取って Cloudflare API を叩く。

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

## Step 3: 初回デプロイ

```bash
git add wrangler.jsonc package.json index.html
git commit -m "🔧 chore: [STRUCTURAL] customize template for <project-name>"
git push origin main
```

`wrangler.jsonc` / `.github/workflows/deploy.yml` はテンプレに同梱されているため commit 不要（プレースホルダ置換した `wrangler.jsonc` のみ commit）。GitHub Actions が起動し、test → check → build → deploy が順次実行される。

## Step 4: 動作確認

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
Wrangler がエラーで落ちる。実行日以前の日付に修正。テンプレ sed で `$(date +%Y-%m-%d)` を埋め込んでいるので、通常はずれない。

### `vp check` が「No checks enabled」で終わる
テンプレ `vite.config.ts` の `lint.options.typeCheck: true` で型チェックは有効化済みだが、lint/fmt がテンプレで未調整。CI も `vp check --no-lint --no-fmt` で型のみに絞っているので、lint/fmt 設定が要る場合は別途整備する。
