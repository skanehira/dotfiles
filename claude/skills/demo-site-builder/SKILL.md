---
name: demo-site-builder
description: React 19 + Vite + TypeScript + Tailwind CSS v4 + React Router v7 (HashRouter) でモバイル向け静的SPAデモサイトをTDDで構築し、Cloudflare Workers (Static Assets) へ自動デプロイするまでの標準ワークフローを提供する。`localStorage` でフロントエンドのみ完結する"フロントのみ完結デモ"に特化。デザインコンセプトの確立には `frontend-design` スキルを呼び出して連携する。起動トリガー：「デモサイトを作りたい」「モバイル向け静的デモ」「SPAを作ってCloudflareにデプロイ」「静的プロトタイプを公開」「localStorage でフロントだけ完結」。ユースケース：(1)クライアント提案用のUI/UXたたき台、(2)新機能のプロトタイプ、(3)モバイル向けランディング。パッケージマネージャは pnpm 固定。
---

# Demo Site Builder

## Overview

モバイル向け静的SPAデモサイトを "完成形でデプロイ" まで一気通貫で立ち上げるワークフロー。数百テスト規模のTDD実装 + Cloudflare Workers Static Assets へのデプロイを、9つの決まったステップで再現する。

ターゲット成果物：
- モバイル完結の静的SPA（10〜15 画面規模まで想定）
- localStorage 永続化（ユーザ登録・セッション・既読・フォーム入力）
- `https://<project>.<subdomain>.workers.dev` で即座に公開
- GitHub Actions による push → 自動デプロイ

バックエンドや DB が必要になったら、このスキルは起点として使い、後から Hono / Cloudflare D1 等で拡張する。

## 前提条件（依存コマンド）

実行環境に以下が揃っていること。抜けがあれば最初に対処する。

| コマンド                      | 用途                                     | 導入                         |
| ----------------------------- | ---------------------------------------- | ---------------------------- |
| `node` (v24+) / `pnpm` (v10+) | ビルド・テスト・依存管理                 | mise / asdf / nvm            |
| `gh`                          | GitHub CLI（Secrets 登録、Actions 監視） | `brew install gh`            |
| `wrangler`                    | Cloudflare Workers デプロイ              | `pnpm add -D wrangler`       |
| `op`                          | 1Password CLI（deploy token 発行）       | `brew install 1password-cli` |
| `curl` / `jq`                 | deploy token 発行スクリプト              | macOS / Linux は標準         |

Claude Code から使う MCP：`chrome-devtools:*`（実機確認）。

## ワークフロー（9 ステップ）

1. **プロジェクト構想の合意** — 画面範囲・対応デバイス・動作モードをユーザに確認
2. **Vite scaffolding** — `pnpm create vite@latest . --template react-ts`
3. **依存導入** — Tailwind v4 / Vitest + RTL + jsdom / React Router v7
4. **デザイン方針** — `frontend-design` スキルを呼び出してコンセプト確立
5. **ドメイン層 TDD** — 純粋関数のバリデーション・判定ロジック
6. **Repository 層 TDD** — KVStorage 抽象 + InMemory/LocalStorage 実装
7. **コンポーネント/ページ TDD** — `features/` コロケーションで機能単位に
8. **Cloudflare Workers デプロイ設定** — `wrangler.jsonc` + GitHub Actions
9. **デプロイ実行 & 動作確認** — `deploy token 発行 gist` → push → chrome-devtools MCP

詳細な各ステップは下記の references を参照。

## 参照ドキュメント（references/）

| ファイル                                                 | 内容                                                              | 読むタイミング |
| -------------------------------------------------------- | ----------------------------------------------------------------- | -------------- |
| [references/scaffold.md](references/scaffold.md)         | ステップ 2〜3 の具体コマンドと設定ファイル                        | セットアップ時 |
| [references/architecture.md](references/architecture.md) | Domain / Repository / Service の分離パターン、localStorage 永続化 | 設計時         |
| [references/tdd.md](references/tdd.md)                   | TDD RED→GREEN→REFACTOR の具体例（ドメイン・Repo・Component）      | コード書き始め |
| [references/deployment.md](references/deployment.md)     | `wrangler.jsonc` + GitHub Actions + deploy token 発行（gist）     | デプロイ準備時 |

## バンドル済みアセット（assets/）

テンプレートとしてコピーして使う：

| ファイル                                                 | 用途                                                                |
| -------------------------------------------------------- | ------------------------------------------------------------------- |
| [assets/wrangler.jsonc](assets/wrangler.jsonc)           | プロジェクト名だけ書き換えて `<project-root>/wrangler.jsonc` に配置 |
| [assets/deploy-workflow.yml](assets/deploy-workflow.yml) | `.github/workflows/deploy.yml` として配置                           |

## 連携する他スキル

| スキル                                                | 役割                                              |
| ----------------------------------------------------- | ------------------------------------------------- |
| `frontend-design` / `frontend-design:frontend-design` | デザインコンセプト（色・フォント・ムード）の確立  |
| `implementation-developing`                           | TDD RED→GREEN→REFACTOR の厳格な運用               |
| `react-testing`                                       | FP アプローチ、`vi.mock` に頼らない振る舞いテスト |
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
- **パッケージマネージャ**：`pnpm`（v10+）
- **ルーティング**：React Router v7 の `HashRouter`（`#/path` 形式）

"localStorage 永続化" を選んだ場合、Repository パターンが必須になる（→ `architecture.md` 参照）。

## Step 2-3: セットアップ

`references/scaffold.md` の手順に従って実行。要点：

- `pnpm create vite@latest . --template react-ts` は既存ディレクトリ非空だと対話を cancel しがち → 一旦 `_tmp/` に生成 → 必要ファイルだけ `mv` する
- Tailwind v4 は `@tailwindcss/vite` プラグイン方式。`index.css` に `@import "tailwindcss";`
- Vitest は `vite.config.ts` で `defineConfig` を `vitest/config` から import（型エラー回避）
- tsconfig の `erasableSyntaxOnly: true` を忘れずに確認（constructor parameter properties が使えなくなる）

## Step 4: デザイン方針

**`frontend-design` スキルを必ず起動する**。Skill tool で以下のように呼び出す：

```
Skill({
  skill: "frontend-design:frontend-design",
  args: `
<プロジェクト名> のデザインシステムを確立したい。
- ターゲット: <年齢層・属性>
- テイスト: <親しみやすさ / モダン / 信頼感 など>
- React + Tailwind CSS v4 + TypeScript
- 要素: カラーパレット / タイポ / コンポーネント (Button/Input/Card/Badge/BottomNav/Header/Checkbox)
- <画面数> 画面をモバイルで提供
まずはデザインの方向性（ムード、色、タイポ、インタラクション）を提案してほしい。
`
})
```

※ 短縮形 `frontend-design` が利用可能な環境ではそちらでも可。両方登録されていれば短縮形が優先。

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

すべて**同じディレクトリに `*.test.ts(x)` をコロケーション**。`__tests__/` ディレクトリは作らない。

## Step 8-9: デプロイ

`references/deployment.md` の手順に従う。核となる判断：

- **Cloudflare Workers Static Assets (assets-only モード) を使う**（Pages ではなく）
  - Cloudflare の 2025 年公式推奨
  - `wrangler.jsonc` に `"assets": { "directory": "./dist/", "not_found_handling": "single-page-application" }` だけで SPA 完結
  - Worker コード（`main`）は**書かない**
- **GitHub Actions で自動デプロイ**（push → test → typecheck → build → deploy）
- **deploy token は gist スクリプトで発行**（1Password + gh CLI）— 手動 dashboard 作業を排除

## 検証方法

デプロイ完了後、以下を必ず実行：

1. `gh run watch <run-id>` で Actions 完走確認
2. `gh run view <run-id> --log | grep 'workers.dev'` でデプロイ URL 取得
3. `chrome-devtools:new_page` → `emulate` で iPhone viewport (390x844x3) → 全画面スクリーンショット
4. `list_console_messages` でエラーなし確認
5. 主要ユーザフロー（ログイン → ダッシュボード）を実際に動かす

## よくある落とし穴

- **`wrangler.jsonc` の `compatibility_date`** は実行日の日付（`date +%Y-%m-%d` で取得）を入れる。未来日付は Wrangler が reject する
- **`gh secret set` は `--body` に直接値を渡さない**（プロセスリストに露出）→ `printf '%s' "$value" | gh secret set NAME`
- **Cloudflare API `9109` エラー**は master token の `User API Tokens: Edit` + `User Details: Read` 権限欠如
- **1Password CLI の vault 名**は UI 表示と内部名が違うことがある（"個人" ↔ "Personal"）— `op vault list` で確認
- **op ref で非 ASCII 文字は不可** — item を一意識別できる ASCII 名にリネームする
- **`FormEvent` の型 deprecation** は React 19 時点の hint（warn レベル）— 動作に影響なし、気になるなら inline handler で型注釈を省略する
- **SPA のデプロイ先 Worker は事前に存在不要** — 初回 `wrangler deploy` で自動作成される
