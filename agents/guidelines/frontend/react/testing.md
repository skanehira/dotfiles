# React のテスト

- 種別: ガイドライン (規範)

React のテストは、`act(...)` の警告 (`An update to X inside a test was not wrapped in act(...)`) を 0 件に保つ。この警告は、テストが待たなかった更新か、`act` の外で起きた更新があることを示す。その状態のアサーションは描画の途中の画面を見ていることがある。テストが pass していても警告は不合格として扱う (`~/.claude/guidelines/core/testing.md`「基本原則」)。

警告の原因はほぼ次の 4 つのどれかで、直し方も決まっている。エージェントから実行すると pass したテストの警告が表示されないことがあるので、数える前に `~/.claude/guidelines/core/verification.md`「5. ランナーが pass したテストの出力を隠した」の対策をとる。

## 1. 後片付けは画面を外してから行う

画面を表示したままストアや購読元を止めると、止めたことで部品が `act` の外で再描画される。`afterEach` では、先に Testing Library の `cleanup()` で画面を外し、それからストア・購読・登録を止める。

```tsx
// Bad: 画面がまだ表示されている間に workspace を止める
afterEach(() => disposals.splice(0).forEach((dispose) => dispose()))

// Good: 画面を外してから止める
import { cleanup } from '@testing-library/react'

afterEach(() => {
  cleanup()
  disposals.splice(0).forEach((dispose) => dispose())
})
```

Testing Library の自動の後片付けには頼らない。vitest の `globals` が有効なら、Testing Library は import した時点で後片付けの `afterEach` を登録する。vitest は既定 (`sequence.hooks: 'stack'`) で `afterEach` を登録の逆順に走らせるので、テストファイルが後から書いた `afterEach` が先に走り、画面が残ったまま止めることになる。`globals` が無効なら、自動の後片付けは登録されない。

## 2. テストの途中で購読元を変える呼び出しは `act` で包む

表示中の部品が購読しているストアや登録 (操作・コマンド・イベントの登録など) を、テストの途中で外したり書き換えたりすると再描画が起きる。その呼び出しを `act` で包む。

```tsx
// Bad
f.unregister()

// Good
act(() => f.unregister())
```

## 3. テストが始めた非同期の処理は、終わるまで待ってからテストを終える

マウント時に始まる読み込みや、最後の操作が始めた処理を待たずにテストが終わると、その完了がテストの外の再描画になる。

- マウント時に読み込みを始める部品は、`render` を async の `act` で包み、読み込みの完了を待つ
- 最後の操作が始めた処理は、その結果が画面に現れるのを `findBy*` か `waitFor` で待ってからテストを終える

```tsx
// Bad: マウント時の読み込みが終わる前にテストが進む
render(<Layout controller={controller} />)

// Good
await act(async () => {
  render(<Layout controller={controller} />)
})
```

## 4. 待ち合わせには Testing Library の `waitFor` / `findBy*` を使う

`vi.waitFor` (vitest) は使わない。Testing Library の `waitFor` は、待っている間だけ React の act の環境を切り替えて、その間の再描画を警告にしない。`vi.waitFor` はこの切り替えをしないので、待っている間の再描画がすべて警告になる。

```tsx
// Bad
await vi.waitFor(() => expect(screen.getByRole('status').textContent).toBe('保存しました'))

// Good
import { screen, waitFor } from '@testing-library/react'

await waitFor(() => expect(screen.getByRole('status').textContent).toBe('保存しました'))
```
