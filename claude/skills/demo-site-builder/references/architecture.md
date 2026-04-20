# Architecture: Domain / Repository / Service 分離と localStorage 永続化

フロント単独で "本物っぽく" 動くデモを作るための設計パターン。依存方向とコロケーションを守る。

## 目次

- ディレクトリ構造（コロケーション前提）
- 依存方向
- Repository パターン（localStorage 抽象化）
- Service 層
- localStorage 永続化時のキー設計
- Context で配線
- シードデータ（起動直後からログイン可能にする）
- 静的シードデータ vs localStorage

## ディレクトリ構造（コロケーション前提）

```
src/
├── domain/              純粋関数・型定義（React 非依存・副作用なし）
│   ├── validation.ts
│   ├── validation.test.ts  ← 同じディレクトリに .test を併置
│   └── ...
├── repositories/        永続化抽象 + 実装
│   ├── kvStorage.ts
│   ├── userRepository.ts
│   └── *.test.ts
├── services/            Repository を集約するアプリサービス
│   ├── authService.ts
│   └── authService.test.ts
├── data/                静的シードデータ（申込・資料・お知らせなど）
│   ├── applications.ts
│   └── applications.test.ts
├── context/             React Context（AppProvider、認証状態）
│   └── AppContext.tsx
├── components/ui/       ボタン・カード等の汎用プリミティブ
│   ├── Button.tsx
│   └── Button.test.tsx
├── features/            機能別ディレクトリ（フォーム、一覧など）
│   ├── auth/
│   │   ├── LoginForm.tsx
│   │   └── LoginForm.test.tsx
│   └── ...
├── layouts/             AuthLayout / AppLayout
├── pages/               ルート単位のページ
└── routes.tsx
```

**`__tests__/` ディレクトリは作らない**。テストは対象ファイルと同じ場所に置く（レビュー効率 + 機能削除時のディレクトリごと削除を可能にする）。

## 依存方向

```
pages → features → components/ui
              ↓
         services → repositories → domain (純粋関数)
                           ↓
                   KVStorage (InMemory or LocalStorage)
```

- **ドメインは何にも依存しない**（純粋関数のみ）
- **Repository はドメイン型を使うが React は見ない**
- **Service は Repository を集約**（例: AuthService が User + Session Repo をまとめる）
- **React 側は Service と domain を使う**（Repo を直接叩かない）

## Repository パターン（localStorage 抽象化）

### 1. KV 抽象を定義

```ts
// src/repositories/kvStorage.ts
export interface KVStorage {
  get<T>(key: string): T | null;
  set<T>(key: string, value: T): void;
  remove(key: string): void;
}

export class InMemoryKVStorage implements KVStorage {
  private readonly store = new Map<string, string>();
  get<T>(key: string): T | null {
    const raw = this.store.get(key);
    return raw === undefined ? null : (JSON.parse(raw) as T);
  }
  set<T>(key: string, value: T): void {
    this.store.set(key, JSON.stringify(value));
  }
  remove(key: string): void {
    this.store.delete(key);
  }
}

export class LocalStorageKV implements KVStorage {
  get<T>(key: string): T | null {
    const raw = localStorage.getItem(key);
    return raw === null ? null : (JSON.parse(raw) as T);
  }
  set<T>(key: string, value: T): void {
    localStorage.setItem(key, JSON.stringify(value));
  }
  remove(key: string): void {
    localStorage.removeItem(key);
  }
}
```

### 2. ドメイン Repository は KVStorage を受け取る

```ts
// src/repositories/userRepository.ts
export class UserRepository {
  private readonly storage: KVStorage;
  private readonly generateId: () => string;

  constructor(storage: KVStorage, generateId: () => string) {
    this.storage = storage;
    this.generateId = generateId;
  }

  register(registration: UserRegistration): UserRecord {
    const users = this.readAll();
    if (findByEmail(users, registration.email)) {
      throw new Error(`Email already registered: ${registration.email}`);
    }
    const record = { id: this.generateId(), ...registration, createdAt: new Date().toISOString() };
    this.writeAll([...users, record]);
    return record;
  }
  // findByEmail, updatePassword など
}
```

### 3. テストは InMemory で書く

```ts
// src/repositories/userRepository.test.ts
const repo = new UserRepository(new InMemoryKVStorage(), () => "user-1");
```

**同じテストを `LocalStorageKV` でも通せるように書く**（jsdom 環境ならそのまま動く）と、実装差し替え時の安心感が得られる。

## Service 層

Repository を複数束ねてアプリ固有のユースケースを表現する。

```ts
// src/services/authService.ts
export class AuthService {
  constructor(
    private users: UserRepository,
    private session: SessionRepository,
    private now: () => Date = () => new Date(),
  ) {}

  register(params: RegisterParams): UserRecord {
    return this.users.register({
      ...params,
      passwordHash: hashPassword(params.password),
    });
  }

  login(email: string, password: string): UserRecord {
    const user = this.users.findByEmail(email);
    if (!user || user.passwordHash !== hashPassword(password)) {
      throw new Error("INVALID_CREDENTIALS");
    }
    this.session.set({
      userId: user.id,
      authenticatedAt: this.now().toISOString(),
    });
    return user;
  }

  currentUser(): UserRecord | null {
    const s = this.session.get();
    if (!s) return null;
    return this.users.findById(s.userId);
  }
  // logout, updatePassword, resetPassword など
}
```

## localStorage 永続化時のキー設計

プロジェクトプレフィクスを揃える：

| key                              | 内容                                      |
| -------------------------------- | ----------------------------------------- |
| `<project>.users`                | 登録済みユーザ（暗号化PW込み）            |
| `<project>.session`              | 現在のログイン状態                        |
| `<project>.readDocuments`        | 既読資料の `{userId: {docId: readAtISO}}` |
| `<project>.readNotifications`    | 既読お知らせ（同上）                      |
| `<project>.importantTermsChecks` | フォームチェック状態                      |
| `<project>.seedVersion`          | シード管理用（二重挿入防止）              |

**平文パスワードを保存しない**：簡易ハッシュ（FNV-1a + salt）でも OK。デモ用途なので cryptographically secure でなくても可、ただし reversible にしない。

```ts
// src/domain/hash.ts（デモ用途の非暗号学的ハッシュ）
export function hashPassword(plain: string): string {
  const salted = `nmt-v1:${plain}`;
  let h = 2166136261 >>> 0;
  for (let i = 0; i < salted.length; i++) {
    h ^= salted.charCodeAt(i);
    h = Math.imul(h, 16777619) >>> 0;
  }
  return `nmt-v1:${h.toString(16).padStart(8, "0")}:${salted.length}`;
}
```

## Context で配線

```tsx
// src/context/AppContext.tsx
function createContainer() {
  const storage = new LocalStorageKV();
  const users = new UserRepository(storage, () => crypto.randomUUID());
  const session = new SessionRepository(storage);
  seedUsersIfNeeded(users, storage, SEED_USERS, SEED_VERSION);
  return {
    auth: new AuthService(users, session),
    // ...
  };
}

export function AppProvider({ children }) {
  const [instance] = useState(createContainer);
  const [currentUser, setCurrentUser] = useState(() => instance.auth.currentUser());
  // useCallback でラップして ctx value を作る
  // ...
}
```

## シードデータ（起動直後からログイン可能にする）

```ts
// src/services/seedService.ts
export function seedUsersIfNeeded(
  users: UserRepository,
  storage: KVStorage,
  seeds: UserRegistration[],
  version: string,
): void {
  if (storage.get<string>("<project>.seedVersion") === version) return;
  for (const seed of seeds) {
    if (!users.findByEmail(seed.email)) users.register(seed);
  }
  storage.set("<project>.seedVersion", version);
}
```

これで `pnpm dev` 初回起動時に demo ユーザが自動登録される。ログイン画面にデモ用メール+パスワードのヒントを表示しておくとすぐ試せる。

## 静的シードデータ vs localStorage

- **静的データ**（申込情報・資料・お知らせなど読み取り専用）→ `src/data/*.ts` で JS モジュール import
- **ユーザ生成状態**（登録・ログイン・既読・チェック）→ localStorage

この分離で「本物のバックエンドが必要になった時」に `data/` だけ API fetch に置換すれば済む。
