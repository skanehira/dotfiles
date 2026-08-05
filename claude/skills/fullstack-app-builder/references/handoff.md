# handoff: 設計ループ (/dev-spec) への引き継ぎ

- 種別: 手順書
- 対象: `fullstack-app-builder` スキルの本体 Step 8 (最終ステップ)

scaffold と環境構築で確定した事実を `docs/PRODUCT_SPEC.md` に書き出し、設計ループの起動コマンドを案内してこのスキルを終える。**このスキルからは `/dev-spec` を起動しない** (設計ループは対話が長く、ユーザーが自分のタイミングで開始するため)。

## 目次

- なぜ PRODUCT_SPEC.md なのか (dev-spec 側の受け口)
- docs/PRODUCT_SPEC.md のテンプレート
- 引き継ぎメッセージ
- dev-spec 側の挙動との対応表

## なぜ PRODUCT_SPEC.md なのか (dev-spec 側の受け口)

dev-spec は以下の 3 フェーズの冒頭で `docs/PRODUCT_SPEC.md` を Read し、存在すればプロダクトのスコープ・技術的制約として利用する:

| dev-spec のフェーズ | 手順書 | PRODUCT_SPEC.md の使われ方 |
| --- | --- | --- |
| フェーズ 1 ユーザーストーリー | `references/user-story.md` | プロダクトのスコープ・コア価値の把握 |
| フェーズ 2 UI スケッチ | `references/ui-sketch.md` | プロダクトのスコープ把握 |
| フェーズ 4 実現可能性検証 | `references/feasibility-check.md` | 技術的制約の把握 (PoC 対象の絞り込み) |

`docs/PRODUCT_SPEC.md` は dev-spec の**途中再開判定の対象外** (判定は USER_STORIES.md 〜 TODO.md を見る) なので、これを置いても「途中から再開」と誤認されず、モード選択から正常に始まる。

## docs/PRODUCT_SPEC.md のテンプレート

`[ ]` の分岐は本体 Step 2 のヒアリング結果で確定させ、角括弧ごと置き換える。**生成日は `date +%Y-%m-%d` の実行結果**を入れる (相対表現を残さない)。

`<ver>` は生成時に実測して埋める (テンプレートの依存更新で版数がずれるため、この文書に固定値を書かない):

```bash
rg -o '"(react|react-router|tailwindcss|hono|drizzle-orm|vite|typescript)": "([^"]+)"' -r '$1 $2' package.json
```

```markdown
# <project-name> プロダクト仕様 (scaffold 時点)

- 種別: プロダクト仕様
- 生成日: YYYY-MM-DD
- 生成元: fullstack-app-builder スキル (skanehira/fullstack-worker-template から scaffold)

## プロダクト概要

[Step 1 で合意した 1〜3 行。誰が何のために使うか]

## 確定済み技術スタック

このプロジェクトは `skanehira/fullstack-worker-template` から scaffold 済みで、下記は選定・動作検証まで完了している。
設計時はこの表を DESIGN.md の技術選定へ転記し (選定理由: テンプレートで scaffold 済み・検証済み)、
実現可能性検証 (dev-spec フェーズ 4〜5) の対象はドメイン固有の不確実性に限定する。

| 区分 | 技術 | 状態 |
| --- | --- | --- |
| フロントエンド | React <ver> / React Router <ver> (`createBrowserRouter`) / Tailwind CSS <ver> | 検証済み |
| データ取得 | SWR (`useEffect` は lint で禁止) | 検証済み |
| バックエンド | Hono <ver> (Cloudflare Workers、`src/server`) | 検証済み |
| DB | Cloudflare D1 + Drizzle ORM <ver> (database_id 発行済み、`migrations/` に初期マイグレーション) | 検証済み |
| 認証 | [Amazon Cognito (ローカルは moto + Terraform) / なし (テンプレートから削除済み)] | [ローカルログイン検証済み / —] |
| 決済 | [Stripe (SDK 同梱・実装は未着手) / なし (依存削除済み)] | [未実装 / —] |
| ビルド | Vite <ver> + `@cloudflare/vite-plugin` / ツールチェーンは `vp` (Vite+) | 検証済み |
| テスト | フロント: `vp test` (jsdom) / Worker: `vp exec vitest run -c vitest.workers.config.ts` | 検証済み |
| CI/CD | GitHub Actions (`ci.yml` / `deploy.yml`。deploy は D1 マイグレーション適用 → `wrangler deploy`) | [本番デプロイ green 確認済み / Secrets 未設定] |

## scaffold 済みの状態

- リポジトリ: `<owner>/<project-name>` (private)
- D1: `<project-name>-db` (`wrangler.jsonc` に実 database_id 反映済み)
- 公開 URL: [https://<project-name>.<subdomain>.workers.dev / 未デプロイ]
- ローカル起動: `vp dev` → http://localhost:5173、`/api/health` が `{"status":"ok"}` を返す
- [認証あり] ローカル認証: `docker compose up -d` → `vp run cognito:setup`。テストユーザーは `test@example.com` / `Passw0rd1!` (ローカル moto 専用の固定値)
- [認証あり] moto の既知の制限により、SRP のパスワード検証と IdToken の `email` クレームはローカルでは正しく検証できない。**実 AWS Cognito でのパスワード検証込みの動作確認は PoC 対象 (POC_NEEDED 相当)**
- [認証あり] **本番 Cognito は未構築**。`wrangler.jsonc` の `vars` (`COGNITO_*`) は空文字のプレースホルダなので、デプロイ済みでも本番ではログインできない。本番運用の前に terraform prod の適用が必要 (`~/.claude/skills/fullstack-app-builder/references/deploy-setup.md` 参照)
- [Stripe あり] 決済の設計・実装に入る前に `~/.claude/skills/fullstack-app-builder/references/stripe.md` を Read すること (Workers 固有の Webhook 検証の制約があるため)

## 実装時に従う規約

リポジトリ直下の `CLAUDE.md` と `README.md` に従う。特に:

- `useEffect` は import 禁止 (データ取得は SWR)
- `worker-configuration.d.ts` は bindings / `main` を変更したときだけ `vp exec wrangler types` で再生成して commit する
- `wrangler.jsonc` の `assets.directory` は `./dist/client` から変えない (`./dist/` にするとローカルシークレットが静的配信される)
- フロントと Worker のテストは別ランナー。両方実行する
- 外部ネットワーク呼び出しは関数注入で DI し、テストはオフラインで完結させる

## 未確定 (設計ループで決めること)

- ドメインモデル・データベーススキーマ (現状は `kv_example` テーブルのサンプルのみ)
- API エンドポイント (現状は `/api/health` と [`/api/me` / —] のみ)
- 画面構成 (現状は `/home` と [`/login`・`/mypage` / —] のみ)
```

## 引き継ぎメッセージ

PRODUCT_SPEC.md を書いたら、以下を表示してスキルを終える:

```
✓ scaffold + ローカル環境構築が完了しました。

次は設計ループへ:

    /dev-spec webapp <プロダクト概要 1 行>。技術スタックは docs/PRODUCT_SPEC.md の確定済みスタックに従う

- docs/PRODUCT_SPEC.md に確定スタックと scaffold 済みの状態を記録済みです。
  dev-spec のフェーズ 1 (ユーザーストーリー) / 2 (UI スケッチ) / 4 (実現可能性検証) が自動で読み込みます。
- 新規プロダクトなのでモードは「フルコース」を推奨します。
- 設計が承認されたら /dev-impl で実装ループに入ります。
```

起動コマンドの本文に `docs/PRODUCT_SPEC.md` への言及を含めるのは、クイックモードを選ぶと PRODUCT_SPEC.md を読むフェーズのうち 1・2 がスキップされ (4 は不確実性があるときだけ実行される条件付き)、フェーズ 7 (概要/詳細設計) は PRODUCT_SPEC.md を読まないため。タスク説明経由でスタックの前提を伝える二重化になっている。

## dev-spec 側の挙動との対応表

| dev-spec の仕組み | このスキルの対応 |
| --- | --- |
| 途中再開判定 (USER_STORIES.md 〜 TODO.md を見る) | PRODUCT_SPEC.md は判定対象外なので、モード選択から正常に開始される |
| フェーズ 1 / 2 / 4 が PRODUCT_SPEC.md を Read | 確定スタックと制約が設計入力になる (主経路) |
| クイックモードでは 1・2 がスキップ、4 は条件付き実行 | 起動コマンドのタスク説明で言及して補う (副経路) |
| フェーズ 7 は PRODUCT_SPEC.md を読まない | 同上 |
| フェーズ 4〜5 の PoC 判定 | 「検証済み」列によりスタック起因の PoC を抑制し、ドメイン固有の不確実性 (実 Cognito でのパスワード検証・Stripe 実課金・外部 API 連携など) だけを PoC 候補に残す |
| DESIGN_DETAIL_APP.md の「セットアップ」節 | scaffold 済みなので PRODUCT_SPEC.md を参照する形で足りる |
| product-mode スタンプ (`<!-- product-mode: webapp -->`) | dev-spec のフェーズ 7 が DESIGN.md に書き込む。このスキルでは触らない (起動時に `webapp` を渡すだけ) |
