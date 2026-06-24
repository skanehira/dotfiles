---
name: demo-site-builder
description: React 19 + Vite+ (`vp`) + TypeScript + Tailwind CSS v4 + React Router v7 (HashRouter) でモバイル向け静的SPAデモサイトをTDDで構築し、Cloudflare Workers (Static Assets) へ自動デプロイするまでの標準ワークフローを提供する。テンプレートリポジトリ `skanehira/demo-site-template` を `gh repo create --template` で clone することで scaffold を省略する。`localStorage` でフロントエンドのみ完結する"フロントのみ完結デモ"に特化。デザインコンセプトの確立には `frontend-design` スキルを呼び出して連携する。起動トリガー：「デモサイトを作りたい」「モバイル向け静的デモ」「SPAを作ってCloudflareにデプロイ」「静的プロトタイプを公開」「localStorage でフロントだけ完結」。ユースケース：(1)クライアント提案用のUI/UXたたき台、(2)新機能のプロトタイプ、(3)モバイル向けランディング。ツールチェーンは Vite+ (`vp`) で統合（内部 PM は pnpm）。
---

# Demo Site Builder

## Overview

モバイル向け静的SPAデモサイトを "完成形でデプロイ" まで一気通貫で立ち上げるワークフロー。**テンプレートリポジトリ `skanehira/demo-site-template` を起点に clone** することで scaffold ステップを省き、数百テスト規模のTDD実装 + Cloudflare Workers Static Assets へのデプロイを再現する。

ターゲット成果物：
- モバイル完結の静的SPA（10〜15 画面規模まで想定）
- localStorage 永続化（ユーザ登録・セッション・既読・フォーム入力）
- `https://<project>.<subdomain>.workers.dev` で即座に公開
- GitHub Actions による push → 自動デプロイ

バックエンドや DB が必要になったら、このスキルは起点として使い、後から Hono / Cloudflare D1 等で拡張する。

## 前提条件（依存コマンド）

実行環境に以下が揃っていること。抜けがあれば最初に対処する。

| コマンド          | 用途                                          | 導入                                      |
| ----------------- | --------------------------------------------- | ----------------------------------------- |
| `vp` (v0.1+)      | Vite+ CLI。scaffold / 依存 / dev / test / build を統合 | `curl -fsSL https://vite.plus \| bash` |
| `node` (v24+)     | ランタイム（vp が管理可能だがホスト側にも入れておく）  | mise / asdf / nvm                         |
| `gh`              | GitHub CLI（テンプレ clone、Secrets 登録、Actions 監視） | `brew install gh`                         |
| `wrangler`        | Cloudflare Workers デプロイ（テンプレに同梱済み）     | テンプレに `devDependencies` として含まれる |
| `op`              | 1Password CLI（deploy token 発行）            | `brew install 1password-cli`              |
| `curl` / `jq`     | deploy token 発行スクリプト                   | macOS / Linux は標準                      |

`pnpm` は内部で `vp` が呼び出す（テンプレの `packageManager` フィールドで pinning 済み）。直接叩く必要はない。

Claude Code から使う MCP：`chrome-devtools:*`（実機確認）。

## ワークフロー（9 ステップ）

1. **プロジェクト構想の合意** — 画面範囲・対応デバイス・動作モードをユーザに確認
2. **テンプレート clone** — `gh repo create <project-name> --template skanehira/demo-site-template --private --clone`
3. **プレースホルダ置換 + `vp install`** — `__PROJECT_NAME__` / `__COMPATIBILITY_DATE__` を sed 置換し、`vp install --frozen-lockfile` で依存セットを取得
4. **デザイン方針** — `frontend-design` スキルを呼び出してコンセプト確立
5. **ドメイン層 TDD** — 純粋関数のバリデーション・判定ロジック
6. **Repository 層 TDD** — KVStorage 抽象 + InMemory/LocalStorage 実装
7. **コンポーネント/ページ TDD** — `features/` コロケーションで機能単位に
8. **Deploy token 発行** — `assets/cf-issue-deploy-token.sh` で Cloudflare API token を発行し GitHub Secrets に登録（`wrangler.jsonc` / `.github/workflows/deploy.yml` はテンプレに同梱済みなので作成不要）
9. **デプロイ実行 & 動作確認** — 承認後に push → Actions 完走 → chrome-devtools MCP

詳細な各ステップは下記の references を参照。

## 参照ドキュメント（references/）

| ファイル                                                 | 内容                                                              | 読むタイミング |
| -------------------------------------------------------- | ----------------------------------------------------------------- | -------------- |
| [references/scaffold.md](references/scaffold.md)         | ステップ 2〜3 の具体コマンド（template clone + sed + `vp install`） | セットアップ時 |
| [references/architecture.md](references/architecture.md) | Domain / Repository / Service の分離パターン、localStorage 永続化 | 設計時         |
| [references/tdd.md](references/tdd.md)                   | TDD RED→GREEN→REFACTOR の具体例（ドメイン・Repo・Component）      | コード書き始め |
| [references/deployment.md](references/deployment.md)     | Deploy token 発行（同梱スクリプト）と push 後の動作確認手順       | デプロイ準備時 |

## バンドル済みアセット（assets/）

| ファイル                                                                 | 用途                                                                                                                  |
| ------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------- |
| [assets/cf-issue-deploy-token.sh](assets/cf-issue-deploy-token.sh)       | Cloudflare deploy token 発行スクリプト。`bash ~/.claude/skills/demo-site-builder/assets/cf-issue-deploy-token.sh <project-name>` で実行 |

`wrangler.jsonc` と `.github/workflows/deploy.yml` は **テンプレ `skanehira/demo-site-template` 側に同梱**されているため、このスキルの assets には含めない。

## 連携する他スキル

| スキル                                                | 役割                                              |
| ----------------------------------------------------- | ------------------------------------------------- |
| `frontend-design` / `frontend-design:frontend-design` | デザインコンセプト（色・フォント・ムード）の確立  |
| `implementation-developing`                           | TDD RED→GREEN→REFACTOR の厳格な運用               |
| `implementation-writing-tests`                        | FP アプローチ、`vi.mock` に頼らない振る舞いテスト (React/TS は `references/react-typescript.md` 参照) |
| `utility-fix-lsp-warnings`                            | 実装完了後の型警告・未使用変数の掃除              |
| `chrome-devtools` MCP                                 | iPhone viewport エミュレート + 画面遷移確認       |

## Step 1: プロジェクト構想の合意

実装前に `AskUserQuestion` で以下を確定する：

| 項目         | 選択肢例                                      |
| ------------ | --------------------------------------------- |
| 画面範囲     | 主要画面のみ / 全画面 / 特定画面のみ          |
| 動作モード   | 完全静的（ハードコード）/ localStorage 永続化 |
| 対応デバイス | モバイルのみ / モバイル+PC / PC 中心          |

固定前提：
- **ツールチェーン**：Vite+ (`vp`) で統合。`vp install` / `vp dev` / `vp test` / `vp check` / `vp build` を使う。内部の package manager は pnpm（テンプレの `packageManager` で pinning 済み）
- **ルーティング**：React Router v7 の `HashRouter`（`#/path` 形式）
- **テーマ**：**ダークテーマ禁止**（ライトテーマのみ。`@theme` ブロックで dark variant を定義しない、`dark:` prefix も使わない）
- **デザイン/実装フロー**：Step 4 以降の実装ステップ（5-7）でも、UI プリミティブや画面を新規作成する際は **`frontend-design` スキルを必ず起動**してコンセプトとの整合を取ること（Step 4 の初回確立だけで終わらせない）

"localStorage 永続化" を選んだ場合、Repository パターンが必須になる（→ `architecture.md` 参照）。

## Step 2-3: セットアップ

`references/scaffold.md` の手順に従って実行。要点：

- `gh repo create <project-name> --template skanehira/demo-site-template --private --clone` でテンプレを clone（`.git` 履歴を引き継がず新規リポになる）
- プレースホルダ `__PROJECT_NAME__` / `__COMPATIBILITY_DATE__` を `package.json` / `wrangler.jsonc` / `index.html` に対して sed で一括置換
- `vp install --frozen-lockfile` で依存セットを取得。テンプレ作成時に lockfile が固定されているので CI と同条件で再現できる
- Tailwind v4 / Vitest / RTL / React Router / wrangler は **テンプレに同梱済み** なので個別 install は不要

## Step 4: デザイン方針

**`frontend-design:frontend-design` スキルを必ず Skill ツールで起動する**（短縮形 `frontend-design` が使える環境ならそちらでも可。両方登録されていれば短縮形が優先）。引数には以下を含むデザイン依頼文を渡す：

- プロジェクト名 / ターゲット（年齢層・属性）/ テイスト（親しみやすさ・モダン・信頼感 など）
- スタック: React + Tailwind CSS v4 + TypeScript
- 要素: カラーパレット / タイポ / コンポーネント（Button/Input/Card/Badge/BottomNav/Header/Checkbox）
- 画面数とモバイル提供前提
- まずはデザインの方向性（ムード・色・タイポ・インタラクション）を提案してもらう

スキルから戻ってきたデザイン提案に基づき、`src/index.css` の Tailwind v4 `@theme` ブロックにカラー・フォント・radius 等を反映する。

**無難な "若年向け tech startup blue" を避ける** — generic AI aesthetics から離れた独自コンセプトを持つこと。命名パターン例：「切符のマイページ」「手帳風ダッシュボード」「カセット UI」。

## Step 5-7: TDD 実装

`references/tdd.md` の例を参照。順序：

1. **ドメイン層**（純粋関数）— validation / status ラベル / 日付計算
2. **Repository 層** — KVStorage 抽象 → InMemory 実装 → LocalStorage 実装（同じテストを通す）
3. **Service 層** — AuthService のように複数 Repository を集約する層
4. **UI プリミティブ** — Button / TextField / Card / Checkbox / BottomNav / AppHeader
5. **機能コンポーネント** — LoginForm / DashboardSummary / DocumentList 等
6. **ページ** — レイアウト + コンポーネントの結線（ここは TDD より e2e の範疇）

すべて**同じディレクトリに `*.test.ts(x)` をコロケーション**。`__tests__/` ディレクトリは作らない。テストの import は `from "vite-plus/test"`（vitest 互換 API を Vite+ 経由で取得）。

## Step 8-9: デプロイ

**デプロイ前の必須ゲート**：ローカルで以下を完了したうえで `AskUserQuestion` による**ユーザ承認**を取得してから push / `wrangler deploy` を実行する。承認なしにデプロイしない。

1. `vp test` / `vp check --no-lint --no-fmt` / `vp build` がすべてグリーン
2. `vp dev` を起動し `chrome-devtools` MCP で Step 1 で合意した対応デバイスの viewport にて主要フローを動作確認（下記「viewport の選び方」参照）
3. 確認結果（通ったフロー・スクリーンショット・console エラー有無）をユーザに提示
4. "このままデプロイしてよいか" を `AskUserQuestion` で明示的に確認 → **承認後にのみ** Step 9 を実行

`references/deployment.md` の手順に従う。核となる判断（テンプレ側で既に定まっている）：

- **Cloudflare Workers Static Assets (assets-only モード) を使う**（Pages ではなく）
  - Cloudflare の 2025 年公式推奨
  - テンプレ同梱の `wrangler.jsonc` が `"assets": { "directory": "./dist/" }` で SPA 完結
  - Worker コード（`main`）は**書かない**
- **GitHub Actions で自動デプロイ**（push → test → check → build → deploy）。CI セットアップは `voidzero-dev/setup-vp@v1` を使う構成
- **deploy token は `assets/cf-issue-deploy-token.sh` で発行**（1Password + gh CLI）— 手動 dashboard 作業を排除

## 検証方法

デプロイ完了後、以下を必ず実行：

1. `gh run watch <run-id>` で Actions 完走確認
2. `gh run view <run-id> --log | grep 'workers.dev'` でデプロイ URL 取得
3. `chrome-devtools:new_page` → `emulate`/`resize_page` で対応デバイスに合わせた viewport → 全画面スクリーンショット
4. `list_console_messages` でエラーなし確認
5. 主要ユーザフロー（ログイン → ダッシュボード）を実際に動かす

### viewport の選び方

Step 1 で合意した "対応デバイス" に応じて切り替える：

| 対応デバイス  | viewport                                         | 備考                                                 |
| ------------- | ------------------------------------------------ | ---------------------------------------------------- |
| モバイルのみ  | 390x844（iPhone 14 相当、DPR 3）                 | `emulate` でモバイルエミュレーション                 |
| モバイル + PC | 390x844 + 1440x900 の両方で確認                  | 両方スクリーンショットしてユーザに提示               |
| PC 中心       | 1440x900（必要に応じて 1920x1080 / 1280x800 も） | `resize_page` で十分。モバイルエミュレーションは不要 |

## よくある落とし穴

- **`wrangler.jsonc` の `compatibility_date`** は実行日の日付（`date +%Y-%m-%d` で取得）を入れる。テンプレ初回 sed で置換する想定。未来日付は Wrangler が reject する
- **`gh secret set` は `--body` に直接値を渡さない**（プロセスリストに露出）→ `printf '%s' "$value" | gh secret set NAME`
- **Cloudflare API `9109` エラー**は master token の `User API Tokens: Edit` + `User Details: Read` 権限欠如
- **1Password CLI の vault 名**は UI 表示と内部名が違うことがある（"個人" ↔ "Personal"）— `op vault list` で確認
- **op ref で非 ASCII 文字は不可** — item を一意識別できる ASCII 名にリネームする
- **`FormEvent` の型 deprecation** は React 19 時点の hint（warn レベル）— 動作に影響なし、気になるなら inline handler で型注釈を省略する
- **SPA のデプロイ先 Worker は事前に存在不要** — 初回 `wrangler deploy` で自動作成される
- **`vp check` の lint/fmt はテンプレで未調整**のため、CI / ローカルともに `vp check --no-lint --no-fmt` で型チェックのみに絞る。lint/fmt を整備する場合は `vite.config.ts` の `lint.options` を別途設定する
