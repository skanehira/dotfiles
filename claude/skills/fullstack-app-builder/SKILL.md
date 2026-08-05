---
name: fullstack-app-builder
description: >-
  skanehira/fullstack-worker-template (React 19 + Hono + Cloudflare D1/Drizzle + Cognito 認証) から
  本格的なフルスタック Web アプリの scaffold とローカル環境構築を行い、docs/PRODUCT_SPEC.md を生成して
  設計ループ (/dev-spec) → 実装ループ (/dev-impl) へ引き渡すワークフロー。
  プロジェクト作成前に Stripe 決済と Cognito 認証の要否をヒアリングし、不要な方をテンプレートから削除する。
  機能の設計・実装はこのスキルでは行わない。
  「フルスタックアプリを作りたい」「DB 付き Web アプリを新規で立ち上げたい」「fullstack-worker-template から始めたい」
  「D1 と Hono で API 付きのサイトを作りたい」「Cognito でログインできるアプリを作りたい」
  「Stripe 決済付きの Web サービスを立ち上げたい」「バックエンド付きのプロジェクトを scaffold して」などで起動。
  フロントだけで完結する静的デモ (localStorage で足りるもの) は demo-site-builder を使う。
argument-hint: "[project-name] [プロダクト概要]"
---

# Fullstack App Builder

## Overview

`skanehira/fullstack-worker-template` を起点に、**動くことを検証済みのフルスタック開発環境**を用意し、設計ループへ引き渡すワークフロー。

成果物は 3 つ:

1. rename と取捨適用が済んだプライベートリポジトリ (D1 データベース発行済み)
2. ローカルで全コマンドが green になり、`/api/health` の疎通と (認証ありなら) ログインまで実機確認された環境
3. `docs/PRODUCT_SPEC.md` — 確定した技術スタックと scaffold 済みの状態を記録し、`/dev-spec` が読み取る引き継ぎ文書

**スコープ外**: ドメインモデル・画面・API の設計と実装 (`/dev-spec` → `/dev-impl` が担当)。本番 Cognito の構築 (terraform prod)。

## 前提条件 (依存コマンド)

| コマンド | 用途 | 必要な場面 |
| --- | --- | --- |
| `gh` | テンプレートからのリポジトリ作成、Secrets 登録、Actions 監視 | 常時 |
| `vp` (Vite+) | install / dev / test / check / build の統合 CLI | 常時 |
| `node` (v24+) | ランタイム (CI の `setup-vp` が使う版に合わせる) | 常時 |
| `docker` | moto (ローカル Cognito エミュレータ) の起動 | 認証を使う場合 |
| `terraform` (1.15+) | Cognito User Pool / Client のプロビジョニング (テンプレートの terraform 構成が要求) | 認証を使う場合 |
| `op` / `curl` / `jq` | deploy token 発行スクリプトが要求する | Step 6 でデプロイ設定する場合 |

`wrangler` はテンプレートの devDependency なのでグローバルには入らない。**`vp install` の後に `vp exec wrangler ...` の形で呼ぶ** (ベアの `wrangler` は `command not found` になる)。

`pnpm` は `vp` が内部で呼ぶ (テンプレートの `packageManager` で pinning 済み)。直接叩かない。

使う MCP: `chrome-devtools:*` (ログインフローの実機確認)。
他スキルの資産: `~/.claude/skills/demo-site-builder/assets/cf-issue-deploy-token.sh` (Step 6 の token 発行。無ければ手動発行にフォールバック)。

## ワークフロー (8 ステップ)

1. **プロジェクトの確認** — 名前 (kebab-case) と概要を確定。静的で足りるなら `demo-site-builder` へ振り分ける
2. **ヒアリング** — **Stripe 決済と Cognito 認証の要否を `AskUserQuestion` で確認する (リポジトリ作成前に必ず行う)**
3. **scaffold** — clone → rename → 依存インストール → **rename の後始末 4 箇所** → D1 作成
4. **取捨適用** — Step 2 の回答に従って Stripe / 認証を削除する
5. **ローカル環境検証** — moto 起動・`vp dev`・`/api/health` 疎通・ログイン確認・テスト チェック 4 コマンド
6. **デプロイ設定** — GitHub Secrets 登録と初回 push の green 確認 (今やるか後回しかを確認する)
7. **初回コミット & push** — `workflow-commit` で関心事ごとにコミット
8. **引き継ぎ** — `docs/PRODUCT_SPEC.md` を生成し、`/dev-spec` の起動コマンドを案内して終了

### DoD の扱い

各ステップの DoD (完了を判定するコマンドと期待値) は該当 reference に置いてある。落ちた場合:

1. その reference 末尾の「よくある落とし穴」で症状を突き合わせる
2. 該当すれば記載の手当てを行い DoD を再実行する
3. 該当しない、または同じ DoD で 2 回連続失敗したら、症状とコマンド出力を添えてユーザーに報告して止まる

**DoD を書き換えて通す・スキップするのは禁止。**

## 参照ドキュメント (references/)

| ファイル | 内容 | 読むタイミング |
| --- | --- | --- |
| [references/scaffold.md](references/scaffold.md) | clone → rename → **rename の後始末 4 箇所** → D1 作成。手順・DoD の実体 | Step 3 開始時 |
| [references/customize.md](references/customize.md) | 取捨 4 パターンの差分表と削除手順 | Step 4 開始時 |
| [references/local-env.md](references/local-env.md) | moto / cognito:setup / `vp dev` / テスト チェック 4 コマンドの検証手順 | Step 5 開始時 |
| [references/deploy-setup.md](references/deploy-setup.md) | deploy token 発行・Secrets 登録・push 後の確認 | Step 6 開始時 |
| [references/handoff.md](references/handoff.md) | PRODUCT_SPEC.md のテンプレートと dev-spec 側の受け口 | Step 8 開始時 |
| [references/stripe.md](references/stripe.md) | Workers での Stripe 実装の定石 (Checkout + Webhook 検証) | **このスキルでは読まない**。Stripe ありで scaffold した後、`/dev-spec` の設計時 or `/dev-impl` の実装時に読む |

コマンド列と DoD は reference 側にのみ置く。本体には各ステップの目的と分岐だけを書く。

## 連携する他スキル

| スキル / エージェント | 役割 | 使う場面 |
| --- | --- | --- |
| `/dev-spec` | 設計ループ (ユーザーストーリー → 設計書 → TODO.md → 承認ゲート) | Step 8 の後 (ユーザーが起動) |
| `/dev-impl` | 実装ループ | dev-spec の承認ゲート通過後 |
| `workflow-commit` | Conventional Commit 形式でのコミット | Step 7 |
| `demo-site-builder` | 静的 SPA デモの構築 / deploy token 発行スクリプトの提供 | Step 1 の振り分け / Step 6 |
| `chrome-devtools` MCP | ログインフローの実機確認 | Step 5 (認証あり) |

## Step 1: プロジェクトの確認

引数または会話から次の 2 つを確定する:

- **プロジェクト名** — kebab-case。リポジトリ名・Worker 名・D1 名 (`<name>-db`) になる
- **プロダクト概要** — 1〜3 行。誰が何のために使うか。`docs/PRODUCT_SPEC.md` に転記する

**振り分けの判断**: データを永続化する先がブラウザの localStorage で足り、サーバ側の API もログインも要らないなら、このテンプレートは重すぎる。`demo-site-builder` を提案する。判断がつかない場合は「複数ユーザーがデータを共有するか」「別端末から同じデータを見るか」を聞けば分かる (いずれか Yes ならこのスキルで進める)。

## Step 2: ヒアリング (Stripe / 認証)

**リポジトリを作る前に**、`AskUserQuestion` で 2 問まとめて確認する。ここでの回答が Step 4 の削除範囲・Step 5 の検証範囲・Step 8 の PRODUCT_SPEC.md の内容をすべて決める。

質問 1 — ヘッダー `Stripe`:

> Stripe 決済は使いますか? テンプレートには SDK 3 依存 (`stripe` / `@stripe/stripe-js` / `@stripe/react-stripe-js`) が同梱されていますが、決済コードは未実装です

| 選択肢 | 説明 |
| --- | --- |
| 使う | 3 依存を残す。実装フェーズで `references/stripe.md` (Checkout Session + Webhook 署名検証の定石) を読む導線を PRODUCT_SPEC.md に記録する |
| 使わない | `package.json` から 3 依存を削除して `vp install` で lockfile を更新する (コード・設定の変更は不要) |

質問 2 — ヘッダー `認証`:

> Cognito 認証 (ログイン機能) は使いますか? ローカルは moto + Terraform でエミュレートするため Docker と Terraform CLI 1.15+ が必要です

| 選択肢 | 説明 |
| --- | --- |
| 使う | ログイン画面・マイページ・authenticate ミドルウェアを残し、moto を起動してログインまで動作確認する。本番 Cognito の構築は本スキルの範囲外 |
| 使わない | テンプレート README の削除手順に沿って terraform / moto / 認証コード / 関連テストを削除する (Docker と Terraform が不要になる) |

回答後、この場で前提を確認する。認証を「使う」なら docker と terraform も含める:

```bash
gh auth status && vp --version
docker info >/dev/null && terraform version    # 認証を使う場合のみ
```

不足があれば導入を案内し、揃ってから Step 3 へ進む。

## Step 3: scaffold

`references/scaffold.md` の Step A〜E に従う。判断が要るのはここだけ:

- **rename の後始末 4 箇所は省略しない**。スクリプトの取りこぼしと副作用で、放置すると (1) deploy ジョブが恒久的にスキップされる、(2) `.bak` が commit される、(3) スクリプトが上書きした `compatibility_date` が原因で `vp dev` と Worker テストが起動しない、(4) テンプレート名が UI とテストに残る
- `terraform.yml` / `terraform-apply.yml` のリポジトリ名ガードは**置換対象外なので触らない** (認証を使わない場合のみ Step 4 でワークフローごと削除する)
- ファイルを書き換えたら最後に `vp check --fix` をかける (名前の長さが変わるとフォーマッタの折り返しが動くため)

## Step 4: 取捨適用

Step 2 の回答に従って不要な機能を削除する。手順・4 パターン差分表・DoD は `references/customize.md` に従う (両方「使う」なら変更作業はなく DoD 確認のみ)。

判断が要るのはここだけ: **削除範囲はテンプレート README の列挙に忠実に従い、独自判断で広げない**。認証削除後に `vite.config.ts` や `.gitignore` に残る記述はスコープ外として扱う。

## Step 5: ローカル環境検証

`references/local-env.md` に従う。「ビルドが通った」ではなく**実際に応答を見る**ところまでやる:

- `/api/health` が `{"status":"ok"}` を返すこと (SPA・Worker・D1 の 3 つが繋がっている証拠)
- (認証あり) ブラウザで `/login` からサインインし `/mypage` に遷移すること。**browser router なので `/#/login` ではない**
- フロントと Worker のテストランナーは分かれている。**両方走らせないと Worker 側が未実行のまま**になる

moto はパスワード署名を検証しない (誤ったパスワードでもローカルではログインが成功する)。この制限は Step 8 で PRODUCT_SPEC.md に PoC 対象として記録する。

## Step 6: デプロイ設定

`AskUserQuestion` でタイミングを確認する — ヘッダー `デプロイ`:

> Cloudflare へのデプロイ設定 (GitHub Secrets) を今行いますか? 設定すると main への push のたびに deploy.yml がリモート D1 のマイグレーション適用と本番デプロイを実行します

| 選択肢 | 説明 |
| --- | --- |
| 今設定する (推奨) | deploy token を発行して Secrets を登録し、初回 push で ci / deploy が green になり本番 URL の `/api/health` が応答するまで確認する。後回しにすると push のたびに deploy ジョブが赤くなり CI の信号が読めなくなる |
| 後で | Secrets 未設定のまま進む (push すると deploy ジョブが失敗する。想定内)。実装が進んでから `references/deploy-setup.md` を見て設定する |

「今設定する」なら `references/deploy-setup.md` に従う。判断が要る点:

- token 発行スクリプトが付与するのは `Workers Scripts Write` のみ。このテンプレートは `wrangler d1 migrations apply --remote` も実行するので、**dashboard で `D1: Edit` を追加する**
- **(認証あり)** ここで本番に上がるのは Worker と D1 まで。`wrangler.jsonc` の `vars` (`COGNITO_*`) は空のプレースホルダなので、**デプロイが成功しても本番ではログインできない** (本番 Cognito = terraform prod は本スキルの範囲外)。この点をユーザーに伝えてから次へ進む

## Step 7: 初回コミット & push

`workflow-commit` スキルでコミットする。関心事が混ざるので分ける (例: 「テンプレートのリネーム」と「Stripe / 認証の削除」)。

`git push` 時に lefthook の `pre-push` が `vp check` + `vp build` を実行するため、push が通ること自体が追加の検証になる。

## Step 8: 引き継ぎ

`references/handoff.md` に従う。

1. `docs/PRODUCT_SPEC.md` を生成する — 確定した技術スタック (版数は生成時に実測)、scaffold 済みの状態、moto と本番 Cognito の制約、実装時の規約、未確定事項を書く
2. 次のコマンドを案内して**このスキルを終了する** (`/dev-spec` をこのスキルから起動しない):

   ```
   /dev-spec webapp <プロダクト概要 1 行>。技術スタックは docs/PRODUCT_SPEC.md の確定済みスタックに従う
   ```

`docs/PRODUCT_SPEC.md` は dev-spec のフェーズ 1 (ユーザーストーリー) / 2 (UI スケッチ) / 4 (実現可能性検証) が Read する。起動コマンドの本文にも言及を入れるのは、クイックモードではそれらのフェーズが実行されないことがあるため。

## 完了条件

- [ ] リポジトリが作られ、意図しないテンプレート名の残骸と `.bak` が無い (`scaffold.md` の DoD で確認)
- [ ] `deploy.yml` のリポジトリ名ガードが削除されている
- [ ] `compatibility_date` が clone 直後の値に戻っている (rename スクリプトの上書きを取り消した)
- [ ] `wrangler.jsonc` に実 `database_id` が入っている
- [ ] Step 2 の回答どおりに Stripe / 認証が取捨されている
- [ ] `vp test` / Worker テスト / `vp check` / `vp build` がすべて green
- [ ] `/api/health` が `{"status":"ok"}` を返した (認証ありならローカルのログインも実機確認済み)
- [ ] (デプロイ設定を選んだ場合) 本番 URL の `/api/health` が応答した — 認証ありでも**本番ログインは未構築のままで正常**
- [ ] `docs/PRODUCT_SPEC.md` が生成され、コミット済み

## よくある落とし穴

ステップ固有のものは各 reference 末尾に集約している。横断的に効くのは次の 2 つ:

- **`wrangler` はベアで呼べない** — devDependency なので `vp exec wrangler ...`。`vp install` より前には使えない
- **`assets.directory` を `./dist/` に変えてしまう** — Worker ビルド成果物に含まれる `.dev.vars` まで静的配信され、ローカルシークレットが公開される。必ず `./dist/client` のままにする
