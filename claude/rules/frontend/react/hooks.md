---
paths:
  - "**/*.tsx"
  - "**/*.ts"
  - "**/*.jsx"
---

# React Hooks ルール

<important>
useEffect は外部システムとの同期にだけ使う。それ以外のほぼ全ての場面で useEffect は不要であり、乱用は再レンダリング・stale state・race condition・テスト困難の温床となる。
</important>

## Rules of Hooks

- フックはトップレベルでのみ呼ぶ。条件分岐・ループ・ネストした関数の中で呼ばない
- React の関数コンポーネント or カスタムフックからのみ呼ぶ
- カスタムフックも pure に保つ（idempotent、レンダー中の副作用禁止、引数の mutation 禁止）

```tsx
// Bad: 条件分岐の中で hook を呼ぶ
function Form({ enabled }: { enabled: boolean }) {
  if (enabled) {
    const [value, setValue] = useState('')
  }
}

// Good: トップレベルで呼ぶ
function Form({ enabled }: { enabled: boolean }) {
  const [value, setValue] = useState('')
  if (!enabled) return null
}
```

## useEffect を使わないべき場面

### 1. props / state から派生する値の計算

```tsx
// Bad: Effect で派生値を state に格納（無駄な再レンダー + state drift）
function Form() {
  const [firstName, setFirstName] = useState('')
  const [lastName, setLastName] = useState('')
  const [fullName, setFullName] = useState('')

  useEffect(() => {
    setFullName(firstName + ' ' + lastName)
  }, [firstName, lastName])

  return <p>{fullName}</p>
}

// Good: レンダー中に計算
function Form() {
  const [firstName, setFirstName] = useState('')
  const [lastName, setLastName] = useState('')
  const fullName = firstName + ' ' + lastName

  return <p>{fullName}</p>
}
```

### 2. 高価な計算のキャッシュ

```tsx
// Bad: Effect で state に書き戻す
useEffect(() => {
  setVisibleTodos(getFilteredTodos(todos, filter))
}, [todos, filter])

// Good: useMemo（または React Compiler に任せる）
const visibleTodos = useMemo(
  () => getFilteredTodos(todos, filter),
  [todos, filter],
)
```

### 3. props 変更時の state 全リセット

```tsx
// Bad: Effect で個別に reset（1度ずれた古い state でレンダーされる）
function ProfilePage({ userId }: { userId: string }) {
  const [comment, setComment] = useState('')
  useEffect(() => {
    setComment('')
  }, [userId])
}

// Good: key で強制的に再マウント
<ProfilePage userId={userId} key={userId} />
```

### 4. props 変更時の一部 state 調整

```tsx
// Bad: Effect で reset
useEffect(() => {
  setSelection(null)
}, [items])

// Good: レンダー中に setState（同レンダー内で即座に反映）
const [prevItems, setPrevItems] = useState(items)
if (items !== prevItems) {
  setPrevItems(items)
  setSelection(null)
}

// Better: そもそも state を消して派生値に
const selection = items.find((item) => item.id === selectedId) ?? null
```

### 5. イベント固有のロジック

```tsx
// Bad: Effect で post（ページ表示の副作用と混ざる）
function Form() {
  const [submitted, setSubmitted] = useState(false)
  useEffect(() => {
    if (submitted) {
      post('/api/register')
      showToast('Registered')
    }
  }, [submitted])

  return <button onClick={() => setSubmitted(true)}>Submit</button>
}

// Good: イベントハンドラで実行
function Form() {
  function handleSubmit() {
    post('/api/register')
    showToast('Registered')
  }

  return <button onClick={handleSubmit}>Submit</button>
}
```

### 6. POST / mutation

```tsx
// Bad: Effect で POST（Strict Mode で2回実行されうる）
useEffect(() => {
  if (jsonToSubmit !== null) {
    post('/api/register', jsonToSubmit)
  }
}, [jsonToSubmit])

// Good: submit ハンドラから呼ぶ
function handleSubmit(e: FormEvent) {
  e.preventDefault()
  post('/api/register', { firstName, lastName })
}
```

### 7. 計算の連鎖（Effect → setState → Effect）

```tsx
// Bad: 連鎖した Effect（複数回再レンダー、追跡困難）
useEffect(() => {
  if (card?.gold) setGoldCardCount((c) => c + 1)
}, [card])

useEffect(() => {
  if (goldCardCount > 3) setRound((r) => r + 1)
}, [goldCardCount])

// Good: 起点のイベントハンドラでまとめて計算
function handlePlaceCard(nextCard: Card) {
  setCard(nextCard)
  if (nextCard.gold) {
    if (goldCardCount < 3) {
      setGoldCardCount(goldCardCount + 1)
    } else {
      setGoldCardCount(0)
      setRound(round + 1)
    }
  }
}
```

### 8. アプリ初期化

```tsx
// Bad: Effect で初期化（Strict Mode で2回走る）
useEffect(() => {
  loadDataFromLocalStorage()
  checkAuthToken()
}, [])

// Good: モジュールトップで実行
if (typeof window !== 'undefined') {
  checkAuthToken()
}

// Good: どうしてもコンポーネント内なら didInit フラグ
let didInit = false
function App() {
  useEffect(() => {
    if (!didInit) {
      didInit = true
      loadDataFromLocalStorage()
    }
  }, [])
}
```

### 9. 親への state 変更通知

```tsx
// Bad: Effect で onChange を呼ぶ（state 更新後にもう1レンダー走る）
function Toggle({ onChange }: { onChange: (v: boolean) => void }) {
  const [isOn, setIsOn] = useState(false)
  useEffect(() => {
    onChange(isOn)
  }, [isOn, onChange])
}

// Good: state 更新と同じハンドラで親に通知（同期）
function Toggle({ onChange }: { onChange: (v: boolean) => void }) {
  const [isOn, setIsOn] = useState(false)
  function updateToggle(next: boolean) {
    setIsOn(next)
    onChange(next)
  }
}
```

### 10. 子から親へのデータ伝搬

```tsx
// Bad: 子が fetch して親に流す（データフロー逆向き）
function Child({ onFetched }: { onFetched: (d: Data) => void }) {
  const data = useSomeAPI()
  useEffect(() => {
    if (data) onFetched(data)
  }, [data, onFetched])
}

// Good: 親で fetch して props で渡す
function Parent() {
  const data = useSomeAPI()
  return <Child data={data} />
}
```

### 11. 外部ストアの購読

```tsx
// Bad: Effect で window event を購読
function useOnlineStatus() {
  const [isOnline, setIsOnline] = useState(true)
  useEffect(() => {
    const update = () => setIsOnline(navigator.onLine)
    window.addEventListener('online', update)
    window.addEventListener('offline', update)
    return () => {
      window.removeEventListener('online', update)
      window.removeEventListener('offline', update)
    }
  }, [])
  return isOnline
}

// Good: useSyncExternalStore（SSR 安全、tear-free）
function useOnlineStatus() {
  return useSyncExternalStore(
    (cb) => {
      window.addEventListener('online', cb)
      window.addEventListener('offline', cb)
      return () => {
        window.removeEventListener('online', cb)
        window.removeEventListener('offline', cb)
      }
    },
    () => navigator.onLine,
    () => true,
  )
}
```

### 12. データフェッチ

**useEffect 内で fetch を呼ぶことは禁止**。Server Components / SWR / TanStack Query を使う。詳細は @data-fetching.md を参照。

```tsx
// Bad: 禁止。race condition、二重実行、cancel 漏れの温床
useEffect(() => {
  fetchResults(query).then(setResults)
}, [query])

// Good: SWR
const { data: results } = useSWR(['/api/search', query], ([_, q]) =>
  fetchResults(q),
)
```

## useEffect を使ってよい場面

**外部システムとの同期だけ**：

- DOM API（`document.title`、IntersectionObserver、サードパーティ widget の生成/破棄）
- ネットワーク購読（WebSocket、SSE 接続のセットアップ/teardown）
- 外部ライブラリのライフサイクル連携（map ライブラリ、エディタ）

それ以外は本ドキュメントの12パターンに当てはまっていないか必ず確認する。

## useEffect の正しい書き方

### 依存配列はプリミティブで絞る

```tsx
// Bad: user オブジェクト全体に依存（無関係なフィールド変更でも再実行）
useEffect(() => {
  console.log(user.id)
}, [user])

// Good: 必要なプリミティブだけ
useEffect(() => {
  console.log(user.id)
}, [user.id])
```

### 連続値ではなく派生 boolean を依存に

```tsx
// Bad: width=767, 766, 765... と毎回再実行
useEffect(() => {
  if (width < 768) enableMobileMode()
}, [width])

// Good: boolean が変わったときだけ
const isMobile = width < 768
useEffect(() => {
  if (isMobile) enableMobileMode()
}, [isMobile])
```

### 独立した副作用は別 Effect に分割

```tsx
// Bad: pathname 変更で title もセットされる
useEffect(() => {
  analytics.trackPageView(pathname)
  document.title = `${pageTitle} | My App`
}, [pathname, pageTitle])

// Good: 関心ごとに分ける
useEffect(() => {
  analytics.trackPageView(pathname)
}, [pathname])

useEffect(() => {
  document.title = `${pageTitle} | My App`
}, [pageTitle])
```

### useEffectEvent は依存配列に入れない

`useEffectEvent` の戻り値は毎レンダー identity が変わる仕様。依存に入れると Effect が毎レンダー再実行され、lint エラーにもなる。

```tsx
// Bad
const handleConnected = useEffectEvent(onConnected)
useEffect(() => {
  const conn = createConnection(roomId)
  conn.on('connected', handleConnected)
  conn.connect()
  return () => conn.disconnect()
}, [roomId, handleConnected])

// Good
const handleConnected = useEffectEvent(onConnected)
useEffect(() => {
  const conn = createConnection(roomId)
  conn.on('connected', handleConnected)
  conn.connect()
  return () => conn.disconnect()
}, [roomId])
```

## useState の使い分け

### 派生値は state に入れない

state 構造5原則（@components.md 参照）の「冗長を避ける」。props や他の state から計算できるものは state にしない。

### 関数型 setState で stale closure を避ける

現在の state を元に更新する場合は必ず関数形式で。

```tsx
// Bad: items を依存にすると毎回 callback が再生成、忘れると stale closure
const addItems = useCallback(
  (newItems: Item[]) => {
    setItems([...items, ...newItems])
  },
  [items],
)

// Good: 安定した callback、常に最新 state
const addItems = useCallback((newItems: Item[]) => {
  setItems((curr) => [...curr, ...newItems])
}, [])
```

直接更新でよいのは静的値・props/引数のみ・前 state に依存しないとき (`setCount(0)`, `setName(newName)`)。

### 重い初期値は lazy initialization

```tsx
// Bad: 毎レンダーで buildSearchIndex が実行される（戻り値は捨てられる）
const [index, setIndex] = useState(buildSearchIndex(items))

// Good: 関数を渡せば初回のみ実行
const [index, setIndex] = useState(() => buildSearchIndex(items))
```

localStorage の `JSON.parse`、Map / Set の構築、DOM 計測などは lazy init。プリミティブ (`useState(0)`) や props 直渡し (`useState(props.value)`) は不要。

## useMemo / useCallback の判断

### プリミティブな単純式に useMemo は不要

```tsx
// Bad: hook 呼び出しと依存比較のオーバーヘッドが式より重い
const isLoading = useMemo(
  () => user.isLoading || notifications.isLoading,
  [user.isLoading, notifications.isLoading],
)

// Good
const isLoading = user.isLoading || notifications.isLoading
```

`useMemo` を使う基準: (a) 高価な計算、(b) 結果が非プリミティブで参照同一性が他の hook の依存に影響する、(c) 重い子の `memo` を効かせるため。

### memoized component のオプショナル非プリミティブ default は定数に

```tsx
// Bad: 毎回新しい関数で渡される → memo が無効化
const UserAvatar = memo(function UserAvatar({
  onClick = () => {},
}: { onClick?: () => void }) {
  // ...
})

// Good: 安定した default
const NOOP = () => {}
const UserAvatar = memo(function UserAvatar({
  onClick = NOOP,
}: { onClick?: () => void }) {
  // ...
})
```

### 独立した計算は別の useMemo に分割

```tsx
// Bad: sortOrder 変更で filtering も再計算
const sortedProducts = useMemo(() => {
  const filtered = products.filter((p) => p.category === category)
  return filtered.toSorted((a, b) =>
    sortOrder === 'asc' ? a.price - b.price : b.price - a.price,
  )
}, [products, category, sortOrder])

// Good: 段階を分ける
const filteredProducts = useMemo(
  () => products.filter((p) => p.category === category),
  [products, category],
)
const sortedProducts = useMemo(
  () =>
    filteredProducts.toSorted((a, b) =>
      sortOrder === 'asc' ? a.price - b.price : b.price - a.price,
    ),
  [filteredProducts, sortOrder],
)
```

### React Compiler 有効時は手動 memo を書かない

React Compiler が有効なプロジェクトでは `memo` / `useMemo` / `useCallback` は基本的に書かない。Compiler が自動で依存追跡・メモ化を行う。手動最適化は Compiler が効かない箇所や計測で効果が確認できた箇所だけに留める。
