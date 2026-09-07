# local-env: ローカル環境の起動と検証

- 種別: 手順書
- 対象: `fullstack-app-builder` スキルの本体 Step 5

scaffold と取捨適用を終えた状態で、開発環境が実際に動くことを観測ベースで確認する。「ビルドが通った」ではなく「`/api/health` が D1 疎通を返した」「ログインして `/mypage` に遷移した」まで見る。

## 目次

- 認証あり: moto の起動と Cognito プロビジョニング
- 共通: dev サーバと API 疎通
- 認証あり: ログインフローの実機確認
- 共通: テスト・チェック 4 コマンド
- moto の既知の制限
- DoD
- よくある落とし穴

## 認証あり: moto の起動と Cognito プロビジョニング

認証を残した場合のみ実行する (認証を削除した場合はこの節を飛ばす)。

```bash
docker compose up -d      # moto を localhost:5001 で起動
vp run cognito:setup      # terraform apply (terraform/envs/local) → .dev.vars / .env.local を生成
```

`cognito:setup` は `terraform/envs/local` に対して `terraform init` + `apply -auto-approve` を実行し、出力された User Pool ID / Client ID から次の 2 ファイルを生成する:

| ファイル | 生成される変数 | 用途 |
| --- | --- | --- |
| `.dev.vars` | `COGNITO_ISSUER` / `COGNITO_CLIENT_ID` / `COGNITO_JWKS_URL` | Worker (サーバ側の JWT 検証) |
| `.env.local` | `VITE_COGNITO_USER_POOL_ID` / `VITE_COGNITO_CLIENT_ID` / `VITE_COGNITO_ENDPOINT` | フロント (SRP 認証) |

両ファイルとも `.gitignore` 済み。**テストユーザーは `test@example.com` / `Passw0rd1!`** (ローカル moto 専用の固定値。terraform の local 環境が `create_test_user=true` で作る。本書がこの値の定義箇所で、他のドキュメントはここを参照する)。

moto はインメモリで永続化しないため `docker compose down` でリソースは消えるが、`MOTO_COGNITO_IDP_USER_POOL_ID_STRATEGY=HASH` により ID は名前から決定的に生成される。作り直したら `vp run cognito:setup` を再実行するだけで復旧する。

## 共通: dev サーバと API 疎通

```bash
vp dev    # http://localhost:5173 (SPA + Worker を同時起動)
```

バックグラウンド実行し、起動後に D1 疎通を確認する:

```bash
curl -s http://localhost:5173/api/health
```

`/api/health` (`src/server/routes/health.ts`) は D1 に `select 1` を投げてから `{"status":"ok"}` を返す。この JSON が返れば SPA・Worker・D1 バインディングの 3 つが繋がっている (D1 に到達できないと 500 になる)。

`/api/*` は `wrangler.jsonc` の `run_worker_first: ["/api/*"]` により、ブラウザからの直アクセス (`Sec-Fetch-Mode: navigate`) でも SPA フォールバックに吸われず Worker が処理する。

## 認証あり: ログインフローの実機確認

`chrome-devtools` MCP で以下を確認する (単発の確認なので MCP で十分。修正ループを回す段階になったら Playwright に切り替える):

1. `chrome-devtools:new_page` で `http://localhost:5173/login` を開く — **browser router なので `/#/login` ではない**
2. 上記のテストユーザーでサインインする
3. `/mypage` に遷移し、`sub` などのユーザー情報が表示されること
4. `chrome-devtools:list_console_messages` で error / warning が出ていないこと

`/mypage` を直接 URL で開いても、`not_found_handling: "single-page-application"` により index.html が返り、`RequireAuth` が未認証なら `/login` にリダイレクトする。この直アクセス経路も 1 回踏んでおく (browser router 構成が壊れていないことの確認になる)。

## 共通: テスト・チェック 4 コマンド

```bash
vp test                                          # フロント (jsdom)
vp exec vitest run -c vitest.workers.config.ts   # Worker (@cloudflare/vitest-pool-workers)
vp check                                         # 型チェック + lint + フォーマット
vp build                                         # dist/client (SPA) + dist/<name> (Worker)
```

フロントと Worker のテストランナーが分かれているのは、`@cloudflare/vite-plugin` の Worker environment と Vitest の jsdom environment が同一 `vite.config.ts` 内で共存できないため (`vite.config.ts` は `process.env.VITEST` のとき `cloudflare()` プラグインを無効化している)。**両方走らせないと Worker 側のテストが実行されない**ので、片方だけで済ませない。

このテンプレートの `vp check` は lint / fmt 込みで CI と同じ条件で通る (`--no-lint --no-fmt` は不要。`demo-site-template` とはここが違う)。

## moto の既知の制限

ローカル認証で「動いた」と判断してよい範囲を誤らないために把握しておく。実装フェーズで PoC 対象になり得る:

- **SRP のパスワード署名が検証されない** — moto は `USER_SRP_AUTH` のやり取りは実装しているが暗号学的検証を行わないため、**誤ったパスワードでもローカルではサインインが成功する**。パスワード検証込みの確認は実 AWS Cognito でのみ可能 (`POC_NEEDED` 相当)
- **IdToken の `email` クレームに UUID が入る** — moto の既知の不具合。`/mypage` のメール表示はローカルでは UUID になる。実 Cognito では正しい値が入る
- **`iss` の形式が固定** — moto のトークンは `iss` が `https://cognito-idp.{region}.amazonaws.com/{pool_id}` で上書きできず、JWKS は moto 自身が返す。そのため Worker 側は `COGNITO_ISSUER` (署名検証の issuer) と `COGNITO_JWKS_URL` (鍵取得先) を分離している (`src/server/middleware/authenticate.ts` の `resolveJwksUrl`)

## DoD

```bash
curl -s http://localhost:5173/api/health         # {"status":"ok"}
vp test                                          # exit 0
vp exec vitest run -c vitest.workers.config.ts   # exit 0
vp check                                         # exit 0
vp build                                         # exit 0
```

認証ありの場合はこれに加えて、`.dev.vars` と `.env.local` が生成されていること、ログイン → `/mypage` 遷移が実機で確認できていること。

## よくある落とし穴

- **`vp dev` が起動しない / Worker テストが `ERR_FUTURE_COMPATIBILITY_DATE` で落ちる** — `scaffold.md` Step D-3 (compatibility_date を UTC の今日以前にする) が未実施。この状態では dev サーバが立たないので `curl` は空応答になる
- **`vp dev` を起動せずに `curl` している** — バックグラウンド起動後、ポートが開くまで数秒待つ
- **moto のポートは 5001** (コンテナ内は 5000)。macOS の AirPlay レシーバーが 5000 を専有しているため `compose.yaml` でずらしてある
- **`terraform` が 1.15 未満** — `cognito:setup` が失敗する。`terraform version` で確認する
- **`docker compose down` 後にログインできない** — moto のリソースが消えている。`vp run cognito:setup` を再実行する
- **`/#/login` を開いて 404 になる** — browser router 移行済みなので hash なしの `/login` を使う
- **`assets.directory` を `./dist/` に変えてしまう** — `dist/<name>/.dev.vars` まで静的配信され、ローカルシークレットが公開される。必ず `./dist/client` のままにする
