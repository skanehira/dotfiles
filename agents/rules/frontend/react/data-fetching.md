---
paths:
  - "**/*.tsx"
  - "**/*.jsx"
---

# React データフェッチ

**重要**: useEffect 内で fetch を呼ぶことは**禁止**。Server Components / SWR / TanStack Query のいずれかを必ず使う。race condition、重複リクエスト、Strict Mode での二重実行、cancel 漏れなどの問題を自前で正しく処理し続けるのは非現実的なため、例外なく禁止とする。

## 優先順位

1. **Server Components**: Next.js App Router 等。サーバーで fetch して RSC から props で渡す。クライアント JS / hydration コストがゼロ
2. **SWR / TanStack Query**: クライアント側に必要な場合。dedup・cache・revalidate・race condition 対策・cancel を全て提供
3. **`useSyncExternalStore`**: 既存の外部ストア（Zustand 等の外部ライブラリ、`window` イベント）との同期

useEffect + fetch という4つ目の選択肢は存在しない。

## useEffect で fetch しない（禁止）

```tsx
// Bad: 禁止。race condition、二重実行、cancel 漏れの温床
function Search({ query }: { query: string }) {
  const [results, setResults] = useState<Result[]>([])
  useEffect(() => {
    fetchResults(query).then(setResults)
  }, [query])
}

// Good: SWR が race condition・cancel・dedup・cache を全部やってくれる
import useSWR from 'swr'

function Search({ query }: { query: string }) {
  const { data: results } = useSWR(['/api/search', query], ([url, q]) =>
    fetchResults(q),
  )
}

// Good: Server Component で完結できるなら最優先
async function Search({ query }: { query: string }) {
  const results = await fetchResults(query)
  return <ResultsList results={results} />
}
```

`useEffect` + `fetch` は cleanup の `ignore` フラグ、`AbortController`、Strict Mode 対策、dedup を全て自前で書き続ける必要があり、必ずどこかで漏れる。SWR / TanStack Query が標準で提供しているので使わない理由がない。

## 重複リクエストは SWR でデデュプ

複数の `UserList` が同時にマウントされても、SWR なら同一 key のリクエストは1本に集約される。

```tsx
// Good: インスタンス数に関係なく1リクエスト
import useSWR from 'swr'

function UserList() {
  const { data: users } = useSWR('/api/users', fetcher)
}
```

### mutation を useEffect で送らない

POST / PUT / DELETE は副作用そのもの。Effect で送ると Strict Mode で2回実行されたり、state 更新トリガーで誤実行される。

```tsx
// Bad: jsonToSubmit が再代入されるたびに POST
useEffect(() => {
  if (jsonToSubmit !== null) {
    post('/api/register', jsonToSubmit)
  }
}, [jsonToSubmit])

// Good: submit ハンドラから送る
function handleSubmit(e: FormEvent) {
  e.preventDefault()
  post('/api/register', { firstName, lastName })
}
```

SWR なら `useSWRMutation` を使う。

```tsx
import useSWRMutation from 'swr/mutation'

function UpdateButton() {
  const { trigger, isMutating } = useSWRMutation('/api/user', updateUser)
  return (
    <button onClick={() => trigger({ name: 'New' })} disabled={isMutating}>
      Update
    </button>
  )
}
```

## 外部ストアは useSyncExternalStore

`window` イベントや localStorage の変化を購読する場合、`useEffect` + `useState` ではなく `useSyncExternalStore` を使う。SSR safe、tearing-free。

```tsx
// Bad
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

// Good
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
    () => true, // SSR snapshot
  )
}
```

## Server Components ファーストの考え方

```tsx
// Bad: client component で fetch（hydration 後にロード開始、waterfall + JS bundle 増）
'use client'
function UserPage({ id }: { id: string }) {
  const { data: user } = useSWR(`/api/users/${id}`, fetcher)
  if (!user) return <Skeleton />
  return <Profile user={user} />
}

// Good: Server Component で fetch（HTML に焼き込まれる、bundle ゼロ）
async function UserPage({ id }: { id: string }) {
  const user = await getUser(id)
  return <Profile user={user} />
}
```

クライアントで interactivity が必要な部分だけ `'use client'` の子に分割する。
