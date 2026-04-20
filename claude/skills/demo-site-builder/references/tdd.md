# TDD: RED → GREEN → REFACTOR の具体例

このスキルの対象プロジェクトでは、100+ テスト規模を TDD で組み上げる。順序は **ドメイン → Repository → Service → UI プリミティブ → 機能コンポーネント → ページ（結線）**。

## 目次

- 原則
- コミット粒度
- テスト命名（TypeScript / React）
- Layer 1: ドメイン層（純粋関数）
- Layer 2: Repository 層
- Layer 3: Service 層
- Layer 4: UI プリミティブ
- Layer 5: 機能フォーム
- Layer 6: ルーティング + BottomNav
- ページ層はどうするか
- よくあるハマり

## 原則

- **テストなしにコードなし**（交渉の余地なし）
- RED：失敗するテストを最初に書く（`test` 実行で未実装のため FAIL）
- GREEN：最小限のコードで pass させる
- REFACTOR：重複削除・命名改善。**テストがグリーンの時のみ**
- 構造的変更（リファクタ）と振る舞い変更は**別コミット**に分ける

## コミット粒度

```
✨ feat: [BEHAVIORAL] add email validation
♻️  refactor: [STRUCTURAL] extract regex to constant
```

## テスト命名（TypeScript / React）

3要素：**何を / どういう条件で / どうなるか**

```ts
describe('isValidEmail', () => {
  it('returns false when value is empty', () => {});
  it('returns true for plus-addressed emails', () => {});
});

describe('LoginForm', () => {
  it('shows error message when email format is invalid', () => {});
  it('calls onSubmit with entered credentials when form is valid', () => {});
});
```

## Layer 1: ドメイン層（純粋関数）

### RED

```ts
// src/domain/validation.test.ts
import { describe, it, expect } from "vitest";
import { isValidEmail, isValidPassword } from "./validation";

describe("isValidEmail", () => {
  it("returns false when value is empty", () => {
    expect(isValidEmail("")).toBe(false);
  });
  it("returns true for a well-formed email", () => {
    expect(isValidEmail("user@example.com")).toBe(true);
  });
  // ...
});
```

`pnpm test` → モジュール未存在で FAIL。

### GREEN

```ts
// src/domain/validation.ts
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export function isValidEmail(value: string): boolean {
  return EMAIL_PATTERN.test(value);
}

export const PASSWORD_MIN_LENGTH = 8;
const LETTER = /[A-Za-z]/;
const DIGIT = /[0-9]/;
const SYMBOL = /[^A-Za-z0-9]/;

export function isValidPassword(value: string): boolean {
  if (value.length < PASSWORD_MIN_LENGTH) return false;
  return LETTER.test(value) && DIGIT.test(value) && SYMBOL.test(value);
}
```

### REFACTOR

今回はシンプル過ぎるので不要。もし複雑化したら `extract method` / `extract constant`。

## Layer 2: Repository 層

### Table-driven テストで InMemory / LocalStorage 両方カバー

```ts
// src/repositories/kvStorage.test.ts
import { describe, it, expect, beforeEach } from "vitest";
import { InMemoryKVStorage, LocalStorageKV, type KVStorage } from "./kvStorage";

describe.each<[string, () => KVStorage]>([
  ["InMemoryKVStorage", () => new InMemoryKVStorage()],
  ["LocalStorageKV",    () => new LocalStorageKV()],
])("%s", (_name, factory) => {
  let storage: KVStorage;
  beforeEach(() => { storage = factory(); });

  it("returns null when key has not been set", () => {
    expect(storage.get("missing")).toBeNull();
  });

  it("returns the stored value after set", () => {
    storage.set("user", { id: "u1" });
    expect(storage.get("user")).toEqual({ id: "u1" });
  });
  // overwrites, removes, arrays...
});
```

jsdom 環境では `localStorage` が自動で使えるので追加セットアップ不要。

### UserRepository で依存注入

```ts
// src/repositories/userRepository.test.ts
const repo = new UserRepository(new InMemoryKVStorage(), () => "user-id-1");

it("throws when registering a duplicate email", () => {
  repo.register(baseRegistration);
  expect(() => repo.register(baseRegistration)).toThrow(/already registered/i);
});
```

**generateId と clock を外部から注入**するとテストが決定論的になる（`() => "user-id-1"` を渡せば ID 固定）。

## Layer 3: Service 層

```ts
// src/services/authService.test.ts
function createService() {
  const storage = new InMemoryKVStorage();
  let counter = 0;
  const users = new UserRepository(storage, () => `user-${++counter}`);
  const session = new SessionRepository(storage);
  return {
    auth: new AuthService(
      users, session,
      () => new Date("2026-04-18T00:00:00.000Z"),
    ),
  };
}

it("logs in with correct credentials and sets the session", () => {
  const ctx = createService();
  ctx.auth.register(registration);
  const user = ctx.auth.login("user@example.com", "Passw0rd!");
  expect(ctx.auth.currentUser()?.id).toBe(user.id);
});

it("throws INVALID_CREDENTIALS when password is wrong", () => {
  const ctx = createService();
  ctx.auth.register(registration);
  expect(() => ctx.auth.login("user@example.com", "wrong!")).toThrow(/INVALID_CREDENTIALS/);
});
```

## Layer 4: UI プリミティブ

`@testing-library/react` + `@testing-library/user-event` で**振る舞いテスト**。実装詳細（className, ステート変数）には依存しない。

```tsx
// src/components/ui/Button.test.tsx
import { describe, it, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { Button } from "./Button";

it("calls onClick when the user clicks it", async () => {
  const handle = vi.fn();
  render(<Button onClick={handle}>送信</Button>);
  await userEvent.click(screen.getByRole("button", { name: "送信" }));
  expect(handle).toHaveBeenCalledTimes(1);
});

it("does not call onClick when disabled", async () => {
  const handle = vi.fn();
  render(<Button onClick={handle} disabled>送信</Button>);
  await userEvent.click(screen.getByRole("button", { name: "送信" }));
  expect(handle).not.toHaveBeenCalled();
});
```

**getByRole を優先**、次に `getByLabelText` / `getByText`。`querySelector` や `testid` は最終手段。

## Layer 5: 機能フォーム

**props-driven** で onSubmit コールバックを受け取る形に。副作用（navigate / repo 書き込み）は上位のページが担当。

```tsx
// src/features/auth/LoginForm.test.tsx
it("calls onSubmit with trimmed email and password when valid", async () => {
  const onSubmit = vi.fn();
  render(<LoginForm onSubmit={onSubmit} />);
  await userEvent.type(screen.getByLabelText("メールアドレス"), "user@example.com");
  await userEvent.type(screen.getByLabelText("パスワード"), "Passw0rd!");
  await userEvent.click(screen.getByRole("button", { name: "ログイン" }));
  expect(onSubmit).toHaveBeenCalledWith({
    email: "user@example.com",
    password: "Passw0rd!",
  });
});
```

**`vi.mock` は原則使わない**（`react-testing` スキル方針）。依存は props 注入で済ます。

## Layer 6: ルーティング + BottomNav

```tsx
import { MemoryRouter } from "react-router";

function renderAt(path: string) {
  return render(
    <MemoryRouter initialEntries={[path]}>
      <BottomNav />
    </MemoryRouter>,
  );
}

it("marks the dashboard link as current when on /dashboard", () => {
  renderAt("/dashboard");
  expect(screen.getByRole("link", { name: /ダッシュボード/ }))
    .toHaveAttribute("aria-current", "page");
});
```

## ページ層はどうするか

ページは "Layout + 機能コンポーネント + navigate 副作用" の thin wrapper なので、単体テスト優先度は低い。**代わりに chrome-devtools MCP での e2e 確認でカバー**：

1. `pnpm dev` 起動
2. `chrome-devtools:new_page` でアクセス
3. `emulate` で iPhone viewport
4. `take_snapshot` → `fill` / `click` で画面遷移
5. `take_screenshot` + `list_console_messages` で確認

## よくあるハマり

### `getByText` で "Found multiple elements"
同じ文字列が見出しとラベルの両方に入っている場合。`getAllByText(...)[0]` か、より specific なクエリ（`getByRole`）に変更。

### `FormEvent` が deprecated 警告
warn レベルなので当面は無視で OK。気になるなら inline handler。

### `erasableSyntaxOnly` で constructor parameter property が使えない
`references/scaffold.md` 参照。明示的にフィールド宣言する。

### async act 警告
`userEvent` は await を忘れない。`fireEvent` より `userEvent` を優先。
