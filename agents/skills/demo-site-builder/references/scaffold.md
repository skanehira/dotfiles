# Scaffold: テンプレートからのプロジェクト立ち上げ

`skanehira/demo-site-template` を起点に、React 19 + Vite+ + TypeScript + Tailwind CSS v4 + Vitest 互換テスト + React Router v7 + Cloudflare Workers デプロイ設定が揃った新規プロジェクトを 1 分以内に立ち上げる。

## 目次

- Step 1: テンプレートを clone
- Step 2: プレースホルダ置換
- Step 3: 依存導入 + 動作確認
- 同梱されているもの
- よくある落とし穴

## Step 1: テンプレートを clone

GitHub Template Repository 機能 + `gh repo create --template` を使う。`.git` 履歴を引き継がず、新規リポとして clone される。

```bash
gh repo create <project-name> \
  --template skanehira/demo-site-template \
  --private --clone
cd <project-name>
```

`--public` でもよいが、デモ用途では `--private` がデフォルト。

## Step 2: プレースホルダ置換

テンプレ内の `__PROJECT_NAME__` と `__COMPATIBILITY_DATE__` を sed で一括置換する：

```bash
PROJECT_NAME="<project-name>"
COMPAT_DATE="$(date +%Y-%m-%d)"

sed -i.bak "s/__PROJECT_NAME__/${PROJECT_NAME}/g" package.json wrangler.jsonc index.html
sed -i.bak "s/__COMPATIBILITY_DATE__/${COMPAT_DATE}/g" wrangler.jsonc
rm -f package.json.bak wrangler.jsonc.bak index.html.bak
```

置換対象：
- `package.json` の `"name"`
- `wrangler.jsonc` の `"name"` と `"compatibility_date"`
- `index.html` の `<title>`

## Step 3: 依存導入 + 動作確認

```bash
vp install --frozen-lockfile  # テンプレ lockfile で再現性のあるインストール
vp test                       # サンプルテスト 1 件が通る
vp check --no-lint --no-fmt   # TypeScript 型チェックのみ
vp build                      # dist/ にビルド成果物
vp dev                        # localhost:5173 で起動 → /#/home に Hello が表示される
```

すべてグリーンになればセットアップ完了。`vp dev` のあと chrome-devtools MCP で 200 OK と表示を確認するとなおよい。

## 同梱されているもの

テンプレ `skanehira/demo-site-template` には以下が既に組み込まれている。スキル側で個別に追加する作業は不要：

| 項目                                     | 用途                                                       |
| ---------------------------------------- | ---------------------------------------------------------- |
| React 19 + TypeScript                    | 基本構成                                                   |
| Tailwind CSS v4 (`@tailwindcss/vite`)    | `src/index.css` の `@theme` は空。`frontend-design` で埋める |
| React Router v7 (`HashRouter`)           | `src/main.tsx` / `src/routes.tsx`                          |
| Vitest 互換テスト (`vite-plus/test`)     | `src/test/setup.ts` + `src/test/jest-dom.d.ts`             |
| `@testing-library/{react,user-event,jest-dom}` + `jsdom` | コンポーネントテスト用                       |
| HomePage サンプル + テスト               | `src/pages/HomePage.tsx` / `HomePage.test.tsx`             |
| `wrangler` + `wrangler.jsonc`            | Cloudflare Workers Static Assets デプロイ                  |
| `.github/workflows/deploy.yml`           | `voidzero-dev/setup-vp@v1` ベースの CI                     |
| `pnpm-workspace.yaml` (`allowBuilds`)    | `esbuild` / `workerd` の build scripts 許可済み            |
| `tsconfig.app.json`                      | `erasableSyntaxOnly: true` を維持                          |

## よくある落とし穴

### `tsconfig.app.json` の `erasableSyntaxOnly` で parameter property が使えない

テンプレでも `erasableSyntaxOnly: true` を維持しているため、下記は **NG**：

```ts
// ❌ erasableSyntaxOnly で拒否される
class Repo {
  constructor(
    private readonly storage: KVStorage,
    private readonly clock: Clock,
  ) {}
}
```

明示的にフィールド宣言する：

```ts
// ✅ OK
class Repo {
  private readonly storage: KVStorage;
  private readonly clock: Clock;
  constructor(storage: KVStorage, clock: Clock) {
    this.storage = storage;
    this.clock = clock;
  }
}
```

### React 19 で `FormEvent` が deprecated 警告

```ts
import { type FormEvent } from "react";
// 使うと deprecated hint が出るが warn レベル。動作には影響なし
```

気になるなら `onSubmit={(e) => {...}}` のインライン handler にすれば型推論で型注釈が不要になり警告が消える。

### `vp check` が「No checks enabled」で終わる

テンプレ `vite.config.ts` の `lint.options.typeCheck: true` で型チェックは有効化済み。ただし lint / fmt の oxlint/oxfmt 設定はテンプレで未調整のため、現状は `vp check --no-lint --no-fmt` で型のみ走らせるのが安全。lint/fmt も走らせたい場合は `lint.options` を別途設定する。

### `pnpm install` を直接叩きたい

可能だが推奨しない。`vp install` 経由なら `pnpm-workspace.yaml` の `allowBuilds` を Vite+ が解釈してくれるが、`pnpm install` 直叩きだと build scripts が再び ignore される可能性がある。CI（`voidzero-dev/setup-vp@v1` 経由）と同じ条件を保つために `vp install` 統一で運用する。
