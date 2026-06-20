---
paths:
  - "**/*.tsx"
  - "**/*.ts"
  - "**/*.jsx"
---

# React コンポーネント設計

## コンポーネントは pure に保つ

Rules of React の最重要原則。

- **idempotent**: 同じ props / state / context で常に同じ JSX を返す
- **レンダー中に副作用を起こさない**: API 呼び出し、subscribe、DOM 操作、グローバル変数の書き換えは禁止
- **props / state / hook の引数を mutate しない**: スナップショットとして扱う
- **JSX に渡した値はその後 mutate しない**: 必要なら JSX 構築前に変更を済ませる

```tsx
// Bad: レンダー中に副作用（mutation + API 呼び出し）
function Cart({ items }: { items: Item[] }) {
  items.push({ id: 'free-gift' }) // props を mutate
  analytics.track('cart_viewed')   // レンダー中に副作用
  return <List items={items} />
}

// Good: 副作用はイベントハンドラ or useEffect、props は不変
function Cart({ items }: { items: Item[] }) {
  const displayItems = [...items, { id: 'free-gift' }]
  return <List items={displayItems} />
}
```

## コンポーネントを別コンポーネントの中で定義しない

**影響度: HIGH**。毎レンダーで新しいコンポーネント型が生まれ、React は別物として fully remount する。子の state / DOM / focus / scroll / effect 状態がすべて失われる。

```tsx
// Bad: 親変数を参照したくて内側に定義
function UserProfile({ user, theme }: Props) {
  const Avatar = () => (
    <img
      src={user.avatarUrl}
      className={theme === 'dark' ? 'avatar-dark' : 'avatar-light'}
    />
  )
  return <Avatar />
}

// Good: 外に出して props で渡す
function Avatar({ src, theme }: { src: string; theme: string }) {
  return (
    <img
      src={src}
      className={theme === 'dark' ? 'avatar-dark' : 'avatar-light'}
    />
  )
}

function UserProfile({ user, theme }: Props) {
  return <Avatar src={user.avatarUrl} theme={theme} />
}
```

**症状**: 入力フィールドが1キーごとに focus を失う / アニメーションが毎回最初から再生 / `useEffect` の cleanup→setup が親の再レンダー毎に走る / コンポーネント内 scroll 位置がリセット。

## state は最近共通の親へリフトアップ

複数の子が共有する state は、それらの最近共通の親に持たせ、props で配る。

```tsx
// Bad: 兄弟がそれぞれ自前 state を持つ → 同期が崩れる
function Tab1() {
  const [active, setActive] = useState(false)
}
function Tab2() {
  const [active, setActive] = useState(false)
}

// Good: 親に持たせる
function Tabs() {
  const [activeId, setActiveId] = useState<'tab1' | 'tab2'>('tab1')
  return (
    <>
      <Tab id="tab1" active={activeId === 'tab1'} onActivate={setActiveId} />
      <Tab id="tab2" active={activeId === 'tab2'} onActivate={setActiveId} />
    </>
  )
}
```

## controlled / uncontrolled の使い分け

- **controlled**（親が値を持つ）: 親が値を読み書きする必要があるとき。フォーム検証、複数フィールド連動、外部 state との同期
- **uncontrolled**（子が内部 state を持つ、`defaultValue` で初期化）: 単純な入力で、submit 時にだけ値を読めば十分なとき。`ref` で読む

中途半端な mix（`value` を渡しつつ `onChange` を渡さない等）は React の警告対象。どちらかに統一する。

## state 構造の5原則

1. **関連する state はまとめる**: 常に同時更新するなら1つの state にする
2. **矛盾を許す構造を避ける**: `isLoading: true` かつ `isSuccess: true` のような状態が作れない型にする（discriminated union を使う）
3. **冗長を避ける**: props や他の state から計算できる値を state にしない（派生はレンダー中計算 or `useMemo`）
4. **重複を避ける**: 同じデータを複数の state に持たない。ID で参照する
5. **深いネストを避ける**: 更新コストが上がる。フラットに正規化する

```tsx
// Bad: 矛盾を許す
const [isLoading, setIsLoading] = useState(false)
const [isError, setIsError] = useState(false)
const [data, setData] = useState<Data | null>(null)

// Good: discriminated union
type State =
  | { status: 'idle' }
  | { status: 'loading' }
  | { status: 'success'; data: Data }
  | { status: 'error'; error: Error }
const [state, setState] = useState<State>({ status: 'idle' })
```

## 条件分岐レンダリングは三項演算子で

`&&` は左辺が falsy のとき右辺を返す。`0` や `NaN` はそのまま JSX に出てしまう。

```tsx
// Bad: count が 0 のとき "0" が描画される
function Badge({ count }: { count: number }) {
  return <div>{count && <span className="badge">{count}</span>}</div>
}

// Good
function Badge({ count }: { count: number }) {
  return <div>{count > 0 ? <span className="badge">{count}</span> : null}</div>
}
```

文字列や数値を `&&` の左辺に置かない。boolean に明示変換するか三項演算子を使う。
