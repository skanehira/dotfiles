---
paths:
  - "**/*.tsx"
  - "**/*.ts"
  - "**/*.jsx"
---

# React パフォーマンス最適化

**重要**: React Compiler 有効プロジェクトでは memo / useMemo / useCallback を手で書かない。Compiler が依存追跡とメモ化を自動で行う。手動最適化は Compiler が効かない箇所や、計測で効果が確認できた箇所だけに留める。

## React.memo は early-return を効かせる手段として使う

子コンポーネントが重く、親レンダーの大半は子の入力が変わらない場合に有効。`useMemo` で JSX をキャッシュするより、`memo` 付きコンポーネントに分離する方が early-return できる分強い。

```tsx
// Bad: loading のときも avatar 計算が走る
function Profile({ user, loading }: Props) {
  const avatar = useMemo(() => {
    const id = computeAvatarId(user)
    return <Avatar id={id} />
  }, [user])

  if (loading) return <Skeleton />
  return <div>{avatar}</div>
}

// Good: memoized 子に切り出すと、loading のときに子が呼ばれない
const UserAvatar = memo(function UserAvatar({ user }: { user: User }) {
  const id = useMemo(() => computeAvatarId(user), [user])
  return <Avatar id={id} />
})

function Profile({ user, loading }: Props) {
  if (loading) return <Skeleton />
  return <UserAvatar user={user} />
}
```

## 連続値ではなく派生 boolean を購読

毎ピクセル変わるような連続値を購読すると毎ピクセル再レンダーが走る。閾値で boolean 化した値を返す hook を使う。

```tsx
// Bad: スクロール / リサイズ毎に再レンダー
function Sidebar() {
  const width = useWindowWidth()
  const isMobile = width < 768
  return <nav className={isMobile ? 'mobile' : 'desktop'} />
}

// Good: boolean が変わったときだけ
function Sidebar() {
  const isMobile = useMediaQuery('(max-width: 767px)')
  return <nav className={isMobile ? 'mobile' : 'desktop'} />
}
```

## callback でしか使わない state は購読しない

ハンドラ実行時にだけ読めばいい値を hook で購読すると、無関係な変更まで再レンダーを引き起こす。

```tsx
// Bad: searchParams のあらゆる変更で再レンダー
function ShareButton({ chatId }: { chatId: string }) {
  const searchParams = useSearchParams()
  const handleShare = () => {
    shareChat(chatId, { ref: searchParams.get('ref') })
  }
  return <button onClick={handleShare}>Share</button>
}

// Good: ハンドラ内で都度読む（購読しない）
function ShareButton({ chatId }: { chatId: string }) {
  const handleShare = () => {
    const params = new URLSearchParams(window.location.search)
    shareChat(chatId, { ref: params.get('ref') })
  }
  return <button onClick={handleShare}>Share</button>
}
```

同じ判断は `localStorage`、Zustand などのストアにも適用する。

## startTransition で非緊急更新を譲る

scroll / input / 頻繁な計算結果の反映など、緊急でない state 更新は `startTransition` で囲んで UI を block しない。

```tsx
// Bad: 毎スクロールで synchronous に re-render
useEffect(() => {
  const handler = () => setScrollY(window.scrollY)
  window.addEventListener('scroll', handler, { passive: true })
  return () => window.removeEventListener('scroll', handler)
}, [])

// Good
useEffect(() => {
  const handler = () => {
    startTransition(() => setScrollY(window.scrollY))
  }
  window.addEventListener('scroll', handler, { passive: true })
  return () => window.removeEventListener('scroll', handler)
}, [])
```

## useDeferredValue で重い派生レンダーをずらす

入力に追従する重い計算（フィルタ、可視化）は `useDeferredValue` で deferred 化し、入力 UI を snappy に保つ。

```tsx
// Bad: 入力が重くなる
function Search({ items }: { items: Item[] }) {
  const [query, setQuery] = useState('')
  const filtered = items.filter((item) => fuzzyMatch(item, query))
  return (
    <>
      <input value={query} onChange={(e) => setQuery(e.target.value)} />
      <ResultsList results={filtered} />
    </>
  )
}

// Good: deferred + useMemo
function Search({ items }: { items: Item[] }) {
  const [query, setQuery] = useState('')
  const deferredQuery = useDeferredValue(query)
  const filtered = useMemo(
    () => items.filter((item) => fuzzyMatch(item, deferredQuery)),
    [items, deferredQuery],
  )
  const isStale = query !== deferredQuery
  return (
    <>
      <input value={query} onChange={(e) => setQuery(e.target.value)} />
      <div style={{ opacity: isStale ? 0.7 : 1 }}>
        <ResultsList results={filtered} />
      </div>
    </>
  )
}
```

`useMemo` で囲まないと deferred の意味がない（毎レンダー計算される）。

## 静的 JSX はコンポーネント外に hoist

毎レンダーで JSX オブジェクトを再生成しない。React Compiler 有効時は自動 hoist されるため不要。

```tsx
// Bad: 毎レンダーで <div> オブジェクトを new
function Container({ loading }: { loading: boolean }) {
  return <div>{loading && <div className="animate-pulse h-20 bg-gray-200" />}</div>
}

// Good
const loadingSkeleton = <div className="animate-pulse h-20 bg-gray-200" />
function Container({ loading }: { loading: boolean }) {
  return <div>{loading && loadingSkeleton}</div>
}
```

特に大きな SVG では効果が大きい。

## 重いコンポーネントは dynamic import

初回描画に不要な大型コンポーネント（エディタ、チャート、地図）は `next/dynamic` で遅延ロードする。

```tsx
// Bad: Monaco がメインチャンクに同梱（~300KB）
import { MonacoEditor } from './monaco-editor'

function CodePanel({ code }: { code: string }) {
  return <MonacoEditor value={code} />
}

// Good: 必要なときにロード
import dynamic from 'next/dynamic'

const MonacoEditor = dynamic(
  () => import('./monaco-editor').then((m) => m.MonacoEditor),
  { ssr: false },
)
```

## Barrel import を避ける

`lucide-react`, `@mui/material`, `@radix-ui/*`, `lodash`, `date-fns` などは index.js から数千の re-export を持つ。素直に import すると dev で 200-800ms のコストが発生する。

```tsx
// Bad: 1,500+ モジュールが読み込まれる
import { Check, X, Menu } from 'lucide-react'
```

Next.js 13.5+ なら設定だけで自動最適化される。

```js
// next.config.js
module.exports = {
  experimental: {
    optimizePackageImports: ['lucide-react', '@mui/material'],
  },
}
```

Next.js 以外で同等のことをしたい場合は直接サブパスから import。ただし型定義が落ちるライブラリもあるため、`optimizePackageImports` が使える環境を優先。
