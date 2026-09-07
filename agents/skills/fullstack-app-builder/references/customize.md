# customize: Stripe / Cognito 認証の取捨

- 種別: 手順書
- 対象: `fullstack-app-builder` スキルの本体 Step 4

本体 Step 2 のヒアリング結果に従い、使わない機能をテンプレートから削除する。**削除範囲は下記の列挙に忠実に従い、独自判断で広げない** (外科的変更の原則)。

## 目次

- 取捨 4 パターンの差分表
- Stripe を使わない場合の削除手順
- 認証を使わない場合の削除手順
- DoD

## 取捨 4 パターンの差分表

凡例: ○ = 実施する / — = 実施しない (該当なし)

| 作業 | 両方あり | 認証のみ (Stripe なし) | Stripe のみ (認証なし) | 両方なし |
| --- | :---: | :---: | :---: | :---: |
| `package.json` から Stripe 3 依存を削除 | — | ○ | — | ○ |
| 認証関連ファイル・ルート・依存を削除 (下記手順) | — | — | ○ | ○ |
| `wrangler.jsonc` の `vars` 削除 → `vp exec wrangler types` で再生成 | — | — | ○ | ○ |
| `vp install` (`--frozen-lockfile` **なし**、lockfile 更新) | — | ○ | ○ | ○ |
| 本体 Step 2 の前提コマンド `docker` + `terraform` 1.15+ | ○ | ○ | — | — |
| 本体 Step 5: moto 起動 + `vp run cognito:setup` + ログイン動作確認 | ○ | ○ | — | — |
| 本体 Step 5: `/api/health` 疎通 + テスト・チェック 4 コマンド | ○ | ○ | ○ | ○ |
| 本体 Step 6 のデプロイ直後に**本番ログインが動くか** | ✗ (要 terraform prod) | ✗ (要 terraform prod) | — | — |
| 実装フェーズ: `references/stripe.md` を読む + `STRIPE_*` secret 設定 | ○ | — | ○ | — |
| 将来: terraform prod CI の secrets (AWS OIDC + R2 backend) | ○ | ○ | — | — |
| `docs/PRODUCT_SPEC.md` の認証行 / 決済行 | 検証済み / 未実装 | 検証済み / なし | なし / 未実装 | なし / なし |

「両方あり」を選んだ場合、Step 4 での変更作業はない (DoD の確認だけ行って本体 Step 5 へ進む)。

**「両方なし」の場合**は Stripe と認証の両方で `package.json` を編集するので、**編集をまとめてから `vp install` を 1 回だけ実行**する。

「本番ログインが動くか」が ✗ なのは、本番 Cognito の構築 (terraform prod) がこのスキルの範囲外だから。デプロイ後も `wrangler.jsonc` の `vars` は空文字プレースホルダのままで、本番環境ではログインが機能しない (`references/deploy-setup.md`「本番 Cognito について」)。

## Stripe を使わない場合の削除手順

テンプレートの Stripe は **`package.json` の依存 3 つだけ**で、`src/` のコード・`wrangler.jsonc` の設定・`terraform/`・`migrations/`・テストのいずれにも利用箇所がない (調査で確認済み)。したがって依存を外すだけで完結する。

`package.json` の `dependencies` から次の 3 キーを削除する (値のバージョンは問わない):

- `@stripe/react-stripe-js`
- `@stripe/stripe-js`
- `stripe`

その後:

```bash
vp install          # --frozen-lockfile を付けない (lockfile を更新するため)
```

型定義には影響しないので `wrangler types` の再生成は不要。

## 認証を使わない場合の削除手順

テンプレート README「認証が不要な場合」の列挙に対応する。ファイルを消したら、参照元の import / ルート定義も同時に消す。

### 削除するファイル・ディレクトリ

| 対象 | 補足 |
| --- | --- |
| `compose.yaml` | moto コンテナ定義 |
| `terraform/` (ディレクトリごと) | local / prod 両方の Cognito 定義 |
| `scripts/cognito-setup.sh` | |
| `.dev.vars.example` / `.env.local.example` | |
| `src/server/auth/` (ディレクトリごと) | `verifyAccessToken.ts` |
| `src/server/middleware/authenticate.ts` | |
| `src/server/routes/me.ts` | |
| `src/front/lib/cognitoClient.ts` | |
| `src/front/pages/LoginPage.tsx` (+ `.test.tsx`) | |
| `src/front/pages/MyPage.tsx` (+ `.test.tsx`) | |
| `src/front/components/RequireAuth.tsx` (+ `.test.tsx`) | |
| `src/front/routes.test.tsx` | `/login` `/mypage` の遷移を検証しているテスト |
| `test/worker/verifyAccessToken.test.ts` | |
| `test/worker/authenticate.test.ts` | |
| `.github/workflows/terraform.yml` / `terraform-apply.yml` | `terraform/` を消すと対象が無くなるため併せて削除する (テンプレート README の列挙には無いが、`terraform/**` を監視する plan/apply ワークフローなので残すと定義だけが宙に浮く)。`scaffold.md` Step D-1 で「触らない」としたのはこの 2 本のことで、認証を残す場合はそのまま残す |

### 参照元の修正

**`src/server/index.ts`** — `meRoute` の import と `.route("/", meRoute)` を削除し、`Env.Bindings` から `COGNITO_ISSUER` / `COGNITO_CLIENT_ID` / `COGNITO_JWKS_URL` を削除する。残るのは:

```ts
import { Hono } from "hono";
import { healthRoute } from "./routes/health";

type Env = { Bindings: { DB: D1Database } };

const app = new Hono<Env>().basePath("/api").route("/", healthRoute);

export default app;
```

**`src/front/routes.tsx`** — `RequireAuth` / `LoginPage` / `MyPage` の import と `/login` `/mypage` のルート定義を削除する。残るのは `/` (`/home` への Navigate) / `/home` / `*` の 3 ルート。

**`wrangler.jsonc`** — `vars` ブロック (`COGNITO_ISSUER` / `COGNITO_CLIENT_ID` / `COGNITO_JWKS_URL`) を削除する。

**`package.json`** — `dependencies` から `amazon-cognito-identity-js` と `jose` を、`scripts` から `cognito:setup` を削除する。

### 依存の反映と型定義の再生成

```bash
vp install                                  # 依存削除を反映 (--frozen-lockfile なし)
vp exec wrangler types                      # worker-configuration.d.ts を再生成
vp fmt worker-configuration.d.ts --write    # 生成物のフォーマット (postinstall と同じ処理)
```

`vars` を消したのは bindings の変更にあたるので、生成物 `worker-configuration.d.ts` から消えた変数の型を落としておく。**ただしこれは衛生上の措置であり、機械ゲートではない**: 各 Hono ルートは `type Env = { Bindings: {...} }` をファイル内で手書きしているため、再生成しなくても `vp check` は通る (実測確認済み)。逆に bindings を**追加**したときは、手書き型と生成物の両方を更新しないと型エラーになる。

## DoD

```bash
vp check                                          # exit 0 (型 + lint + フォーマット)
vp test                                           # exit 0 (フロント)
vp exec vitest run -c vitest.workers.config.ts    # exit 0 (Worker)
```

Worker テストが `ERR_FUTURE_COMPATIBILITY_DATE` で落ちる場合は `scaffold.md` Step D-3 (compatibility_date を UTC の今日以前にする) が未実施。

加えて、選択に応じて:

```bash
# Stripe を使わない場合
rg -n '"(stripe|@stripe/[a-z-]+)":' package.json    # 0 件
rg -i 'stripe' src/                                 # 0 件

# 認証を使わない場合
rg -i 'cognito' src/front src/server package.json wrangler.jsonc    # 0 件
```

認証削除後も `vite.config.ts` のコメント (`amazon-cognito-identity-js` が Node の global を参照する件) と `define: { global: "globalThis" }`、`.gitignore` の `terraform/**` 行、`README.md` / `CLAUDE.md` の認証節は残る。**これらは依頼スコープ外なので触らない** (上の DoD は「削除対象の消し漏れが無い」ことの確認であって、「cognito の語が 1 つも無い」ことの確認ではない)。README / CLAUDE.md の記述はプロジェクトの実態に合わせて書き換えてもよいが、その判断はユーザーに確認する。
