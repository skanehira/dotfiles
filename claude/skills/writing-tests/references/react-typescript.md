# React + TypeScript テストベストプラクティス

## テストファイル配置

**コロケーション原則**: テストファイルは実装ファイルと同じディレクトリに配置する。

```
src/features/auth/
├── LoginForm.tsx
├── LoginForm.test.tsx    # コンポーネントテスト
├── useAuth.ts
├── useAuth.test.ts       # フックテスト
├── authApi.ts
└── authApi.test.ts       # APIテスト
```

**例外: E2Eテスト**
```
e2e/
├── auth.spec.ts
└── checkout.spec.ts
```

## テスト命名規則

`describe` + `it` パターンを使用：

```typescript
describe('LoginForm', () => {
  describe('when credentials are valid', () => {
    it('redirects to dashboard', () => {})
    it('stores auth token', () => {})
  })

  describe('when credentials are invalid', () => {
    it('displays error message', () => {})
    it('keeps form values', () => {})
  })
})
```

**命名の3要素**:
1. 何を（対象コンポーネント/関数）
2. どういう条件で（入力/状態）
3. どうなるか（期待結果）

## テスト構造

### AAA (Arrange-Act-Assert) パターン

```typescript
it('displays user name when data is loaded', async () => {
  // Arrange: テストデータと前提条件を準備
  const mockUser = { name: 'John', email: 'john@example.com' }
  server.use(
    rest.get('/api/user', (req, res, ctx) => res(ctx.json(mockUser)))
  )

  // Act: テスト対象の操作を実行
  render(<UserProfile />)

  // Assert: 期待する結果を検証
  expect(await screen.findByText('John')).toBeInTheDocument()
})
```

### Given-When-Then (BDDスタイル)

```typescript
describe('ShoppingCart', () => {
  describe('given an empty cart', () => {
    describe('when adding an item', () => {
      it('then shows item count as 1', () => {
        const { result } = renderHook(() => useCart())
        act(() => result.current.addItem({ id: '1', name: 'Item' }))
        expect(result.current.itemCount).toBe(1)
      })
    })
  })
})
```

## コンポーネントテスト

### Testing Libraryの原則

**ユーザー視点でテスト**: 実装詳細ではなく、ユーザーが見る/操作するものをテスト

```typescript
// 悪い例: 実装詳細に依存
expect(wrapper.state('isOpen')).toBe(true)

// 良い例: ユーザーが見るものをテスト
expect(screen.getByRole('dialog')).toBeVisible()
```

### クエリの優先順位

1. `getByRole` - アクセシビリティに基づく（推奨）
2. `getByLabelText` - フォーム要素
3. `getByPlaceholderText` - プレースホルダー
4. `getByText` - テキストコンテンツ
5. `getByTestId` - 最後の手段

```typescript
// 推奨
const submitButton = screen.getByRole('button', { name: /submit/i })

// 避ける
const submitButton = screen.getByTestId('submit-btn')
```

### 非同期テスト

```typescript
it('loads and displays data', async () => {
  render(<UserList />)

  // waitForを使用して非同期処理を待つ
  await waitFor(() => {
    expect(screen.getByText('User 1')).toBeInTheDocument()
  })

  // または findBy* を使用
  expect(await screen.findByText('User 1')).toBeInTheDocument()
})
```

## フックテスト

```typescript
import { renderHook, act } from '@testing-library/react'

describe('useCounter', () => {
  it('increments count when increment is called', () => {
    const { result } = renderHook(() => useCounter())

    act(() => {
      result.current.increment()
    })

    expect(result.current.count).toBe(1)
  })
})
```

## モック

### MSW (Mock Service Worker) - API モック

```typescript
import { rest } from 'msw'
import { setupServer } from 'msw/node'

const server = setupServer(
  rest.get('/api/users', (req, res, ctx) => {
    return res(ctx.json([{ id: 1, name: 'John' }]))
  })
)

beforeAll(() => server.listen())
afterEach(() => server.resetHandlers())
afterAll(() => server.close())
```

### モジュールモック

```typescript
vi.mock('./api', () => ({
  fetchUser: vi.fn().mockResolvedValue({ name: 'John' })
}))
```

### コンポーネントモック

```typescript
vi.mock('./HeavyComponent', () => ({
  HeavyComponent: () => <div data-testid="mock-heavy">Mocked</div>
}))
```

## テストカバレッジ目標

| 種類 | 目標 |
|------|------|
| ライン | 80%以上 |
| ブランチ | 70%以上 |
| 重要パス | 100% |

## アンチパターン

❌ スナップショットテストの乱用
❌ 実装詳細のテスト（state, props直接アクセス）
❌ テスト間の依存関係
❌ タイマーのハードコード（`setTimeout`の代わりに`vi.useFakeTimers()`）
❌ act警告の無視
