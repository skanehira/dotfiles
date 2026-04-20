# Scaffold: セットアップ手順

Vite + React 19 + TypeScript + Tailwind CSS v4 + Vitest + RTL + React Router v7 の新規プロジェクト立ち上げ手順。

## 目次

- Step 1: Vite scaffolding
- Step 2: ボイラープレート削除
- Step 3: Tailwind CSS v4
- Step 4: Vitest + React Testing Library + jsdom
- Step 5: React Router v7
- Step 6: 動作確認
- よくある落とし穴

## Step 1: Vite scaffolding

### 空ディレクトリの場合
```bash
pnpm create vite@latest . --template react-ts --no-interactive
```

### 既存ファイルがあって対話 cancel される場合
```bash
# 一旦 tmp ディレクトリに生成
pnpm create vite@latest _scaffold_tmp --template react-ts --no-interactive

# 必要なファイルだけ移動（既存 README.md などは保持）
mv _scaffold_tmp/.gitignore \
   _scaffold_tmp/eslint.config.js \
   _scaffold_tmp/index.html \
   _scaffold_tmp/package.json \
   _scaffold_tmp/public \
   _scaffold_tmp/src \
   _scaffold_tmp/tsconfig*.json \
   _scaffold_tmp/vite.config.ts \
   .

rm -rf _scaffold_tmp
```

`package.json` の `name` を正しいプロジェクト名に書き換え、`pnpm install`。

## Step 2: ボイラープレート削除

scaffolding の default は Vite のランディングページ。これを撤去：

```bash
rm -f src/App.css src/assets/*
rmdir src/assets 2>/dev/null
rm -f public/vite.svg
```

`src/App.tsx` と `src/index.css` を空に近い形に書き換え（後述の Tailwind 設定で上書き）。

## Step 3: Tailwind CSS v4

```bash
pnpm add -D tailwindcss @tailwindcss/vite
```

v4 は **`@tailwindcss/vite` プラグイン方式**（PostCSS 設定ファイルは不要）。

### vite.config.ts（後述の Vitest 設定も同時に）
```ts
import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  plugins: [react(), tailwindcss()],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./src/test/setup.ts'],
  },
})
```

**重要**: `defineConfig` は `vitest/config` から import する。`vite` 側の `defineConfig` に `test` フィールドの型定義が無く TypeScript エラーになる。

### src/index.css（Tailwind v4 の @theme）
```css
@import "tailwindcss";

@theme {
  /* デザインコンセプトに合わせて CSS 変数として定義 */
  --color-ink: #12151c;
  --color-cream: #f7f1e3;
  --font-display: "Shippori Mincho B1", serif;
  --font-sans: "Zen Kaku Gothic New", sans-serif;
  --radius-card: 1rem;
}

html, body, #root { height: 100%; }
body {
  margin: 0;
  font-family: var(--font-sans);
  color: var(--color-ink);
  background: var(--color-cream);
}
```

**ポイント**: v3 の `tailwind.config.js` は不要。すべて CSS の `@theme` ブロックで完結。

### Google Fonts（任意）
`index.html` の `<head>` に `<link>` タグを追加。`display=swap` を忘れずに。

## Step 4: Vitest + React Testing Library + jsdom

```bash
pnpm add -D vitest @testing-library/react @testing-library/user-event @testing-library/jest-dom jsdom
```

### src/test/setup.ts
```ts
import "@testing-library/jest-dom/vitest";
import { afterEach } from "vitest";
import { cleanup } from "@testing-library/react";

afterEach(() => {
  cleanup();
  localStorage.clear(); // localStorage 利用時は必須
});
```

### package.json scripts
```json
{
  "scripts": {
    "dev": "vite",
    "build": "tsc -b && vite build",
    "preview": "vite preview",
    "test": "vitest run",
    "test:watch": "vitest",
    "typecheck": "tsc -b --noEmit"
  }
}
```

## Step 5: React Router v7 (HashRouter)

```bash
pnpm add react-router
```

v7 は `react-router` 単体（旧 `react-router-dom` は不要）。

**HashRouter を採用**する理由：
- URL が `https://<project>.workers.dev/#/dashboard` 形式になり、静的ホスティングで直リンク / リロードが必ず動く
- Cloudflare Workers の SPA モード設定（`not_found_handling`）にも依存しないため、将来 GitHub Pages 等に移しても動作保証
- リンク共有時にも CDN キャッシュの罠にはまらない

### src/routes.tsx（最小雛形）
```tsx
import { createHashRouter, Navigate } from "react-router";

export const router = createHashRouter([
  { path: "/", element: <Navigate to="/home" replace /> },
  // { path: "/home", element: <HomePage /> },
  // ...
  { path: "*", element: <Navigate to="/" replace /> },
]);
```

### src/main.tsx
```tsx
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { RouterProvider } from "react-router";
import "./index.css";
import { router } from "./routes";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <RouterProvider router={router} />
  </StrictMode>,
);
```

## Step 6: 動作確認

```bash
pnpm test       # smoke test が通るか
pnpm typecheck  # tsc で型エラーなし
pnpm build      # 本番ビルド通る
pnpm dev        # localhost:5173 で起動
```

`pnpm build` が通れば、この後のデプロイ段階でも同じコマンドで動く。

## よくある落とし穴

### `vite.config.ts` で `test` フィールドが認識されない
`defineConfig` を `vite` からではなく **`vitest/config` から** import する。

### tsconfig.app.json の `erasableSyntaxOnly` で parameter property が使えない
Vite scaffolding のデフォルトで `erasableSyntaxOnly: true` が有効になる。下記は **NG**：

```ts
// ❌ erasableSyntaxOnly で拒否される
class Repo {
  constructor(
    private readonly storage: KVStorage,
    private readonly clock: Clock,
  ) {}
}
```

以下のように明示的にフィールド宣言する：

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
// 使うと ★ deprecated hint が出るが warn レベル。動作には影響なし
```

気になるなら `onSubmit={(e) => {...}}` のインライン handler にすれば型推論で型注釈が不要になり警告が消える。
