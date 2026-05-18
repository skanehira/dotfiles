# React + TypeScript テストベストプラクティス

React/TypeScript コンポーネントの振る舞いテストを、FP アプローチで設計・実装する。

## 原則

1. **振る舞いテスト**: 実装詳細ではなくユーザーから見た動作を検証
2. **vi.mock 禁止**: IO の分離と DI で解決。モジュールモックは使わない
3. **FP アプローチ**: 純粋関数を抽出し、IO を境界に押し出す
4. **コロケーション**: テストとユーティリティは対象と同じディレクトリに配置
5. **テスト不要の判断**: primitive すぎるコンポーネントはスキップ

## ワークフロー

### Step 1: 対象コンポーネントの分析

対象ディレクトリの全ファイルを読み、各コンポーネントを分類:

| 分類         | 特徴                          | テスト                      |
| ------------ | ----------------------------- | --------------------------- |
| 純粋表示     | props→JSX のみ、状態・分岐なし | スキップ                    |
| ロジック内包 | フィルタ、URL 構築等の計算    | 純粋関数抽出→テスト         |
| IO 依存      | useSWR、API 呼び出し          | DI 化→振る舞いテスト        |
| 状態管理     | Context、useState             | Provider 注入→振る舞いテスト |

**テスト不要 (primitive) の例**:
- props をそのまま表示するだけのアイコン: `({ open }) => <svg className={open ? "rotate-90" : ""} />`
- 値を透過するラッパー: `({ children }) => <div className="container">{children}</div>`
- 定数を返すだけ: `export const LABEL = "送信"`

**テスト必要 (振る舞いあり) の例**:
- 条件分岐で表示が変わる: 添付数 > 0 なら「N件」、0 なら「-」を表示
- ユーザー入力でリスト絞り込み: テキスト入力→フィルタ→候補表示
- 展開/折り畳み: クリックで子要素の表示/非表示が切り替わる
- フォーム送信: 入力→バリデーション→コールバック呼び出し

### Step 2: 実装改善（テスタビリティ向上）

#### 2a. 純粋関数の抽出

コンポーネント内のロジックを同ディレクトリの `utils.ts` に抽出:

```typescript
// components/example/utils.ts
export function filterItems(items: Item[], query: string): Item[] {
  if (!query) return items;
  return items.filter(item => item.name.includes(query));
}

export const yearKey = (year: number) => `y:${year}`;

export function buildItemLink(id: number, params: Record<string, string>): string {
  const sp = new URLSearchParams(params);
  return `/items/${id}?${sp.toString()}`;
}
```

**抽出基準**: 入力→出力の変換で、DOM・API・ブラウザ API に触れない処理。

#### 2b. IO の DI 化

API 呼び出し関数を直接 import せず、Context で DI:

```typescript
// Before: API を直接 import（テスト時 vi.mock 必要）
import { fetchData } from "../../lib/api";
const { data } = useSWR(key, () => fetchData(params));

// After: Context から注入（テスト時フェイク注入）
const { fetchData } = useMyContext();
const { data } = useSWR(key, () => fetchData(params));
```

**検証**: 改善後にビルドコマンド (`npm run build` 等) でビルド通過を確認。

### Step 3: テスト設計

2 層に分ける:

**層1: 純粋関数テスト** (`utils.test.ts`) — React なし、入力→出力の検証:

```typescript
import { filterItems, yearKey } from "./utils";

describe("filterItems", () => {
  it("returns all items when query is empty", () => {
    const items = [{ name: "foo" }, { name: "bar" }];
    expect(filterItems(items, "")).toEqual(items);
  });
  it("filters items by name", () => {
    const items = [{ name: "foo" }, { name: "bar" }];
    expect(filterItems(items, "foo")).toEqual([{ name: "foo" }]);
  });
});
```

**層2: コンポーネント振る舞いテスト** (`*.test.tsx`) — ユーザー操作→画面変化:

```typescript
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router";
import { SWRConfig } from "swr";

function renderWith(ui: React.ReactElement) {
  return render(
    <SWRConfig value={{ provider: () => new Map() }}>
      <MemoryRouter>
        <MyProvider value={{ fetchData: fakeFetch }}>
          {ui}
        </MyProvider>
      </MemoryRouter>
    </SWRConfig>
  );
}

it("shows filtered results when user types", async () => {
  renderWith(<MyCombobox items={testItems} onSelect={vi.fn()} />);
  await userEvent.type(screen.getByPlaceholder("検索"), "foo");
  expect(screen.getByText("foo")).toBeVisible();
  expect(screen.queryByText("bar")).not.toBeInTheDocument();
});
```

### Step 4: テスト実装

#### ファイル配置 (コロケーション)

```
components/example/
  ├── utils.ts              ← 純粋関数
  ├── utils.test.ts         ← 純粋関数テスト
  ├── MyComponent.tsx
  ├── MyComponent.test.tsx  ← 振る舞いテスト
  └── index.ts
```

#### テスト命名

`describe` + `it` パターンで 3 要素 (何を / 条件 / 期待結果) を含める:

```typescript
describe('LoginForm', () => {
  describe('when credentials are valid', () => {
    it('redirects to dashboard', () => {})
    it('stores auth token', () => {})
  })
  describe('when credentials are invalid', () => {
    it('displays error message', () => {})
  })
})
```

#### クエリ優先順位 (Testing Library)

1. `getByRole` — アクセシビリティに基づく (推奨)
2. `getByLabelText` — フォーム要素
3. `getByPlaceholderText` — プレースホルダー
4. `getByText` — テキストコンテンツ
5. `getByTestId` — 最後の手段

```typescript
// 推奨
const submitButton = screen.getByRole('button', { name: /submit/i })

// 避ける
const submitButton = screen.getByTestId('submit-btn')
```

#### 非同期テスト

```typescript
// findBy*: 自動リトライで要素出現を待つ (推奨)
expect(await screen.findByText('User 1')).toBeInTheDocument()

// waitFor: 任意の条件を待つ
await waitFor(() => {
  expect(screen.getByText('User 1')).toBeInTheDocument()
})
```

#### フックテスト

```typescript
import { renderHook, act } from '@testing-library/react'

describe('useCounter', () => {
  it('increments count when increment is called', () => {
    const { result } = renderHook(() => useCounter())
    act(() => { result.current.increment() })
    expect(result.current.count).toBe(1)
  })
})
```

#### 実装上の注意

- SWR の非同期データは `findByText` (自動リトライ) で待つ。`getByText` は即座に失敗する
- `act` ワーニングが出たら `await findByText` や `waitFor` で状態更新の完了を待つ
- `SWRConfig` の `provider: () => new Map()` でテスト間のキャッシュ汚染を防ぐ
- テスト実装後にテストランナーで全テスト通過を確認

### Step 5: フォーマット・リント実行

テスト実装・修正後に、プロジェクトのフォーマッター・リンターを実行する。

**コマンドの特定方法** (以下の順で確認):
1. `CLAUDE.md` に記載されたコマンド (最優先)
2. `justfile` / `Makefile` のタスク (例: `just fmt`, `just lint`)
3. `package.json` の `scripts` (例: `npm run lint`, `npm run format`)
4. プロジェクトのツールチェーン固有コマンド (例: `vp check --fix`, `deno fmt`)

**実行タイミング**: テストが全件通過した後、コミット前に必ず実行する。

## テスト環境

パッケージ: `vitest`, `@testing-library/react`, `@testing-library/jest-dom`, `@testing-library/user-event`, `jsdom`

```typescript
// vitest.config.ts
import { defineConfig } from "vitest/config";
export default defineConfig({
  test: { environment: "jsdom", setupFiles: ["./src/test-setup.ts"] },
});

// src/test-setup.ts
import "@testing-library/jest-dom/vitest";
```

## アンチパターン

| やらない                      | 代わりに                     |
| ----------------------------- | ---------------------------- |
| `vi.mock("swr")`              | SWRConfig + DI               |
| `vi.mock("../lib/api")`       | Context 経由でフェイク注入   |
| `wrapper.find(".class-name")` | `screen.getByRole("button")` |
| `expect(state).toBe(...)`     | 操作後の画面変化を検証       |
| 全コンポーネントにテスト      | primitive はスキップ         |
| `data-testid` 乱用            | アクセシブルなロケータ優先   |
| スナップショットテスト乱用    | 振る舞いテストで意図を表現   |
| `setTimeout` ハードコード     | `vi.useFakeTimers()`         |
| `act` 警告の無視              | `findBy*` / `waitFor` で待つ |
