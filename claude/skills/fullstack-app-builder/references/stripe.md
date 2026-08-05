# stripe: Cloudflare Workers での決済実装

- 種別: 実装ガイド
- 読むタイミング: **このスキル (fullstack-app-builder) の実行中には読まない**。Stripe を「使う」で scaffold したプロジェクトで、決済の設計 (dev-spec) または実装 (dev-impl) に着手するときに Read する

**実装前に context7 で最新ドキュメントを確認すること** (`resolve-library-id` で `/stripe/stripe-node` → `query-docs`)。本書はバージョンに依存しにくい構成の定石と、Cloudflare Workers 固有の制約に絞る。

## 目次

- Workers 固有の制約 (最重要)
- 推奨アーキテクチャ: Stripe Checkout
- 環境変数とシークレット
- サーバ実装 (Hono)
- Webhook の冪等化と D1 スキーマ
- フロント実装
- ローカル開発とテスト
- よくある落とし穴

## Workers 固有の制約 (最重要)

Workers には Node.js の `http` モジュールも同期 crypto も無い。stripe-node は両方について Workers 用の差し替えを提供しており、**これを使わないと動かない**:

| 用途 | Workers での指定 | 使わないと |
| --- | --- | --- |
| API 呼び出し | `new Stripe(key, { httpClient: Stripe.createFetchHttpClient() })` | Node の http に依存して実行時エラー |
| Webhook 署名検証 | `Stripe.createSubtleCryptoProvider()` を `constructEventAsync` に渡す | 同期版 `constructEvent` は Workers で失敗する |

`constructEvent` (同期) ではなく **`constructEventAsync` (非同期)** を使う。

## 推奨アーキテクチャ: Stripe Checkout

**Stripe Checkout (リダイレクト型) を既定にする**。カード情報が自社オリジンを通らないため PCI の負担が最も軽く、Worker 側は「Checkout Session を作る」「Webhook を受ける」の 2 エンドポイントで済む。

```
[ブラウザ] --POST /api/checkout--> [Worker] --create session--> [Stripe]
     <---- session.url へリダイレクト ----
[ブラウザ] ---- Stripe のホスト画面で決済 ----> [Stripe]
                                    [Stripe] --POST /api/stripe/webhook--> [Worker] --記録--> [D1]
[ブラウザ] <-- success_url へ戻る
```

埋め込み型 (Payment Element、`@stripe/react-stripe-js`) は次のいずれかに当てはまるときだけ選ぶ: 決済画面を自社デザインに統合する要件がある / サブスクリプションの支払い方法変更 UI を自前で持つ / Checkout がサポートしない決済手段を使う。**選んだ場合は PCI SAQ A-EP の範囲になる**ため、判断理由を DESIGN.md に残す。

**支払い成功の確定は必ず Webhook で行う**。`success_url` へのリダイレクトはユーザーがブラウザを閉じれば発生しないので、これを完了トリガーにしてはいけない。

## 環境変数とシークレット

| 変数 | 置き場所 (ローカル) | 置き場所 (本番) | 用途 |
| --- | --- | --- | --- |
| `STRIPE_SECRET_KEY` | `.dev.vars` | `wrangler secret put STRIPE_SECRET_KEY` | Worker の API 呼び出し |
| `STRIPE_WEBHOOK_SECRET` | `.dev.vars` | `wrangler secret put STRIPE_WEBHOOK_SECRET` | Webhook 署名検証 |
| `VITE_STRIPE_PUBLISHABLE_KEY` | `.env.local` | ビルド時に埋め込み (公開値) | フロント (Payment Element を使う場合のみ) |

`wrangler.jsonc` の `vars` にシークレットを書かない (`vars` は平文で commit される)。`.dev.vars` / `.env.local` は `.gitignore` 済み。

シークレットは `wrangler secret put` (このプロジェクトでは `vp exec wrangler secret put`) で登録する。bindings 定義は変わらないので `worker-configuration.d.ts` の再生成は不要だが、**Hono 側の `Env["Bindings"]` 型には手で追加する** (各ルートがファイル内で型を手書きしているため)。

## サーバ実装 (Hono)

Stripe クライアントは**リクエストごとに `c.env` から生成する** (Workers ではモジュールスコープに環境変数が無い)。テスト容易性のため、生成関数は注入できる形にする (テンプレートの `src/server/auth/verifyAccessToken.ts` が `getKey` を注入している構造に倣う)。

### Checkout Session の作成

```ts
import { Hono } from "hono";
import Stripe from "stripe";

type Env = { Bindings: { DB: D1Database; STRIPE_SECRET_KEY: string } };

export const checkoutRoute = new Hono<Env>().post("/checkout", async (c) => {
  const stripe = new Stripe(c.env.STRIPE_SECRET_KEY, {
    httpClient: Stripe.createFetchHttpClient(),
  });

  const origin = new URL(c.req.url).origin;
  const session = await stripe.checkout.sessions.create({
    mode: "payment",
    line_items: [{ price: "price_xxx", quantity: 1 }],
    success_url: `${origin}/checkout/success?session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: `${origin}/checkout/cancel`,
  });

  return c.json({ url: session.url });
});
```

`success_url` / `cancel_url` は**通常のパス形式**で書く (`/#/...` ではない)。テンプレートは `createBrowserRouter` + `not_found_handling: "single-page-application"` なので、これらの URL に直接アクセスしても index.html が返り React Router が処理する。

`{CHECKOUT_SESSION_ID}` は Stripe が置換するプレースホルダ。成功画面での表示用であって、**支払い確定の根拠にはしない**。

### Webhook の受信

```ts
export const stripeWebhookRoute = new Hono<Env>().post("/stripe/webhook", async (c) => {
  const stripe = new Stripe(c.env.STRIPE_SECRET_KEY, {
    httpClient: Stripe.createFetchHttpClient(),
  });
  const body = await c.req.text();            // raw body のまま渡す (JSON パース禁止)
  const sig = c.req.header("stripe-signature") ?? "";

  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(
      body,
      sig,
      c.env.STRIPE_WEBHOOK_SECRET,
      undefined,                              // tolerance (既定値を使う)
      Stripe.createSubtleCryptoProvider(),    // Workers では必須
    );
  } catch (err) {
    return c.json({ error: "invalid signature" }, 400);
  }

  // ここで冪等化してからビジネスロジックを実行する (次節)
  return c.json({ received: true });
});
```

署名検証は**受信したバイト列そのもの**に対して行う。`c.req.json()` でパースしたオブジェクトを再度 `JSON.stringify` して渡すと、キー順や空白の違いで署名が一致せず必ず失敗する。

Webhook エンドポイントは認証ミドルウェアの対象外にする (Stripe は Cognito のトークンを持たない)。署名検証がそのまま認証になる。

## Webhook の冪等化と D1 スキーマ

Stripe の Webhook は **at-least-once 配送**で、同じイベントが複数回届く。`event.id` を記録して重複を弾く:

```ts
// src/server/db/schema.ts
export const processedStripeEvents = sqliteTable("processed_stripe_events", {
  eventId: text("event_id").primaryKey(),     // Stripe の evt_xxx
  type: text("type").notNull(),
  processedAt: text("processed_at").notNull(),
});
```

挿入が主キー制約で失敗したら処理済みとみなして 200 を返す (Stripe に再送させない)。**イベント記録とビジネスロジックの書き込みは同一トランザクションに入れる**。

スキーマを変えたら `vp run db:generate` (`drizzle-kit generate`) でマイグレーションを生成し、`migrations/` に出力されたファイルを commit する。本番への適用は `deploy.yml` の `wrangler d1 migrations apply <db> --remote` が自動で行う。

Webhook は**受け取ったら速やかに 200 を返す**。重い処理は D1 に記録だけして後段に回す (Stripe は応答が遅いとタイムアウトして再送する)。

## フロント実装

Checkout (リダイレクト型) なら `@stripe/stripe-js` すら不要で、Worker が返した `session.url` へ遷移するだけでよい:

```tsx
async function startCheckout() {
  const res = await fetch("/api/checkout", { method: "POST" });
  const { url } = await res.json();
  window.location.href = url;
}
```

データ取得は SWR を使う (`useEffect` は lint で禁止)。決済状態の表示は「D1 に記録された結果」を `/api/...` 経由で取得する形にし、Stripe の API をフロントから直接叩かない。

Payment Element を使う場合のみ `loadStripe(import.meta.env.VITE_STRIPE_PUBLISHABLE_KEY)` と `<Elements>` プロバイダが必要になる。

## ローカル開発とテスト

### Stripe CLI で Webhook を転送する

前提: Stripe CLI (`brew install stripe/stripe-cli/stripe`)。Webhook のローカル転送にのみ使う (Checkout Session の作成には不要)。

```bash
stripe login
stripe listen --forward-to localhost:5173/api/stripe/webhook
# → whsec_... が表示されるので .dev.vars の STRIPE_WEBHOOK_SECRET に設定する

stripe trigger checkout.session.completed
```

`stripe listen` が出す署名シークレットは本番のものと別物。取り違えると署名検証が通らない。

### テスト方針

- **Stripe API 呼び出しは関数注入で DI する**。ルートハンドラが `new Stripe(...)` を直接呼ぶのではなく、クライアント生成関数を引数で受け取る形にして、`test/worker/` のテストにはフェイクを渡す (テンプレートの `verifyAccessToken.ts` の `getKey` と同じ考え方)。これで Workers pool のテストがオフラインで完結する
- **署名検証のテスト**はネットワーク不要。既知の `whsec_` を固定し、テスト内で HMAC-SHA256 署名を生成して `stripe-signature` ヘッダを組み立てれば、正常系・改竄・タイムスタンプ超過を検証できる
- **冪等化のテスト**は同じ `event.id` を 2 回送り、副作用が 1 回しか起きないことを assert する
- テストカードは `4242 4242 4242 4242` (任意の将来日付・任意の CVC)。3D セキュア必須のケースは `4000 0027 6000 3184`
- **実キーでの課金検証は PoC 扱い**にし、FEASIBILITY.md に `POC_NEEDED` として残す。CI では実行しない

## よくある落とし穴

- **`constructEvent` (同期版) を使う** — Workers で失敗する。`constructEventAsync` + `createSubtleCryptoProvider()` を使う
- **`httpClient` を指定し忘れる** — Node の http に依存して実行時に落ちる
- **署名検証にパース済み JSON を渡す** — 必ず `c.req.text()` の生文字列を渡す
- **`success_url` を支払い完了の根拠にする** — ユーザーがブラウザを閉じると発生しない。確定は Webhook のみ
- **冪等化を入れない** — 再送で二重計上される。`event.id` を主キーにして弾く
- **本番の Webhook エンドポイントを Stripe dashboard に登録し忘れる** — デプロイ後に `https://<project>.<subdomain>.workers.dev/api/stripe/webhook` を登録し、そこで発行される署名シークレットを `wrangler secret put STRIPE_WEBHOOK_SECRET` で設定する (ローカルの `whsec_` とは別)
- **Webhook が認証ミドルウェアに吸われて 401** — Stripe からのリクエストは認証トークンを持たない。ルート登録の順序と適用範囲を確認する
- **金額を小数で扱う** — Stripe の `unit_amount` は最小通貨単位の整数 (JPY は円単位、USD はセント単位)
