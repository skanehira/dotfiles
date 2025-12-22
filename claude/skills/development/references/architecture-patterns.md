# アーキテクチャパターン リファレンス

高凝集度・低結合度・コロケーションの詳細パターンと実践例。

## 目次

1. [高凝集度パターン](#高凝集度パターン)
2. [低結合度パターン](#低結合度パターン)
3. [コロケーションパターン](#コロケーションパターン)
4. [React/TypeScript特有のパターン](#reacttypescript特有のパターン)
5. [リファクタリング戦略](#リファクタリング戦略)

---

## 高凝集度パターン

### 単一責務の原則（SRP）の適用

**コンポーネントの責務分離:**

```typescript
// ❌ 悪い例: 複数の責務が混在
function TaskManager() {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [filter, setFilter] = useState<Filter>('all');
  const [sortOrder, setSortOrder] = useState<'asc' | 'desc'>('asc');

  // データ取得ロジック
  useEffect(() => {
    fetch('/api/tasks').then(r => r.json()).then(setTasks);
  }, []);

  // フィルタリングロジック
  const filteredTasks = tasks.filter(t => /* ... */);

  // ソートロジック
  const sortedTasks = [...filteredTasks].sort(/* ... */);

  // タスク操作
  const addTask = (task: Task) => { /* ... */ };
  const deleteTask = (id: string) => { /* ... */ };
  const updateTask = (id: string, updates: Partial<Task>) => { /* ... */ };

  return (
    <div>
      <FilterBar filter={filter} onFilterChange={setFilter} />
      <SortControls sortOrder={sortOrder} onSortChange={setSortOrder} />
      <TaskList tasks={sortedTasks} onDelete={deleteTask} onUpdate={updateTask} />
      <AddTaskForm onAdd={addTask} />
    </div>
  );
}

// ✅ 良い例: 責務を分離
// hooks/useTaskData.ts - データ取得の責務
function useTaskData() {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    fetch('/api/tasks')
      .then(r => r.json())
      .then(setTasks)
      .catch(setError)
      .finally(() => setLoading(false));
  }, []);

  return { tasks, loading, error, setTasks };
}

// hooks/useTaskFilter.ts - フィルタリングの責務
function useTaskFilter(tasks: Task[], filter: Filter) {
  return useMemo(() => {
    switch (filter) {
      case 'completed': return tasks.filter(t => t.completed);
      case 'pending': return tasks.filter(t => !t.completed);
      default: return tasks;
    }
  }, [tasks, filter]);
}

// hooks/useTaskSort.ts - ソートの責務
function useTaskSort(tasks: Task[], sortOrder: 'asc' | 'desc') {
  return useMemo(() => {
    return [...tasks].sort((a, b) => {
      const comparison = a.createdAt - b.createdAt;
      return sortOrder === 'asc' ? comparison : -comparison;
    });
  }, [tasks, sortOrder]);
}

// components/TaskManager.tsx - 統合の責務のみ
function TaskManager() {
  const { tasks, setTasks } = useTaskData();
  const [filter, setFilter] = useState<Filter>('all');
  const [sortOrder, setSortOrder] = useState<'asc' | 'desc'>('asc');

  const filteredTasks = useTaskFilter(tasks, filter);
  const sortedTasks = useTaskSort(filteredTasks, sortOrder);

  return (
    <div>
      <FilterBar filter={filter} onFilterChange={setFilter} />
      <SortControls sortOrder={sortOrder} onSortChange={setSortOrder} />
      <TaskList tasks={sortedTasks} />
    </div>
  );
}
```

### 凝集度のレベル

**高い順（目指すべき）:**

1. **機能的凝集**: 単一の機能を完遂するすべての要素が含まれる
2. **逐次的凝集**: 1つの出力が次の入力になる要素が含まれる
3. **通信的凝集**: 同じデータを操作する要素が含まれる

**低い順（避けるべき）:**

4. **手続き的凝集**: 順序に意味がある操作が含まれる
5. **時間的凝集**: 同時に実行される操作が含まれる
6. **論理的凝集**: 論理的に似た操作が含まれる
7. **偶発的凝集**: 関連のない要素が含まれる

---

## 低結合度パターン

### 依存性注入（DI）

```typescript
// ❌ 悪い例: 具象に依存
class TaskService {
  private api = new TaskApiClient(); // 具象クラスに直接依存

  async getTasks() {
    return this.api.fetchTasks();
  }
}

// ✅ 良い例: 抽象に依存
interface TaskDataSource {
  fetchTasks(): Promise<Task[]>;
  createTask(task: NewTask): Promise<Task>;
  updateTask(id: string, updates: Partial<Task>): Promise<Task>;
  deleteTask(id: string): Promise<void>;
}

class TaskService {
  constructor(private dataSource: TaskDataSource) {}

  async getTasks() {
    return this.dataSource.fetchTasks();
  }
}

// 本番環境
const apiDataSource: TaskDataSource = {
  fetchTasks: () => fetch('/api/tasks').then(r => r.json()),
  // ...
};
const service = new TaskService(apiDataSource);

// テスト環境
const mockDataSource: TaskDataSource = {
  fetchTasks: () => Promise.resolve([{ id: '1', title: 'Test Task' }]),
  // ...
};
const testService = new TaskService(mockDataSource);
```

### Reactでの依存性注入

```typescript
// Context を使った依存性注入
interface TaskContextValue {
  tasks: Task[];
  loading: boolean;
  addTask: (task: NewTask) => Promise<void>;
  deleteTask: (id: string) => Promise<void>;
}

const TaskContext = createContext<TaskContextValue | null>(null);

// プロバイダー（本番用）
function TaskProvider({ children, dataSource }: { children: ReactNode; dataSource: TaskDataSource }) {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    dataSource.fetchTasks().then(setTasks).finally(() => setLoading(false));
  }, [dataSource]);

  const value: TaskContextValue = {
    tasks,
    loading,
    addTask: async (task) => {
      const created = await dataSource.createTask(task);
      setTasks(prev => [...prev, created]);
    },
    deleteTask: async (id) => {
      await dataSource.deleteTask(id);
      setTasks(prev => prev.filter(t => t.id !== id));
    },
  };

  return <TaskContext.Provider value={value}>{children}</TaskContext.Provider>;
}

// テスト用のモックプロバイダー
function MockTaskProvider({ children, tasks = [] }: { children: ReactNode; tasks?: Task[] }) {
  return (
    <TaskContext.Provider value={{
      tasks,
      loading: false,
      addTask: async () => {},
      deleteTask: async () => {},
    }}>
      {children}
    </TaskContext.Provider>
  );
}
```

### 結合度のレベル

**低い順（目指すべき）:**

1. **メッセージ結合**: パラメータなしのメッセージのみ
2. **データ結合**: プリミティブデータのみを渡す
3. **スタンプ結合**: データ構造を渡すが、一部のみ使用

**高い順（避けるべき）:**

4. **制御結合**: 制御フラグを渡して動作を変更
5. **外部結合**: 外部リソースを共有
6. **共通結合**: グローバルデータを共有
7. **内容結合**: 他モジュールの内部を直接参照

---

## コロケーションパターン

### 機能別ディレクトリ構造

```
src/
├── features/
│   ├── auth/
│   │   ├── components/
│   │   │   ├── LoginForm.tsx
│   │   │   ├── LoginForm.test.tsx
│   │   │   ├── SignupForm.tsx
│   │   │   └── SignupForm.test.tsx
│   │   ├── hooks/
│   │   │   ├── useAuth.ts
│   │   │   └── useAuth.test.ts
│   │   ├── api/
│   │   │   ├── authApi.ts
│   │   │   └── authApi.test.ts
│   │   ├── types.ts
│   │   └── index.ts          # Public API（re-export）
│   │
│   ├── tasks/
│   │   ├── components/
│   │   │   ├── TaskList.tsx
│   │   │   ├── TaskList.test.tsx
│   │   │   ├── TaskItem.tsx
│   │   │   ├── TaskItem.test.tsx
│   │   │   ├── TaskForm.tsx
│   │   │   └── TaskForm.test.tsx
│   │   ├── hooks/
│   │   │   ├── useTasks.ts
│   │   │   ├── useTasks.test.ts
│   │   │   ├── useTaskFilter.ts
│   │   │   └── useTaskFilter.test.ts
│   │   ├── api/
│   │   │   ├── taskApi.ts
│   │   │   └── taskApi.test.ts
│   │   ├── types.ts
│   │   └── index.ts
│   │
│   └── reservations/
│       ├── components/
│       ├── hooks/
│       ├── api/
│       ├── types.ts
│       └── index.ts
│
├── components/               # 共有UIコンポーネント
│   └── ui/
│       ├── Button/
│       │   ├── Button.tsx
│       │   ├── Button.test.tsx
│       │   └── index.ts
│       ├── Modal/
│       │   ├── Modal.tsx
│       │   ├── Modal.test.tsx
│       │   └── index.ts
│       └── index.ts
│
├── hooks/                    # 共有フック
│   ├── useDebounce.ts
│   ├── useDebounce.test.ts
│   ├── useLocalStorage.ts
│   └── useLocalStorage.test.ts
│
├── utils/                    # 共有ユーティリティ
│   ├── date.ts
│   ├── date.test.ts
│   ├── format.ts
│   └── format.test.ts
│
└── types/                    # 共有型定義
    └── index.ts
```

### コロケーションのルール

**1. テストは実装の隣に:**
```
TaskList.tsx
TaskList.test.tsx  ← 同じディレクトリ
```

**2. 型は使用される場所に:**
```
features/tasks/types.ts  ← タスク機能専用の型
types/index.ts           ← 複数機能で共有される型のみ
```

**3. 公開APIは index.ts で制御:**
```typescript
// features/tasks/index.ts
export { TaskList } from './components/TaskList';
export { useTasks } from './hooks/useTasks';
export type { Task, NewTask } from './types';

// 内部実装は export しない
// useTaskFilter, TaskItem など
```

**4. 機能削除 = ディレクトリ削除:**
```bash
# 機能を削除する場合
rm -rf src/features/tasks/

# 依存関係がなければこれで完了
```

---

## React/TypeScript特有のパターン

### カスタムフックの分離

```typescript
// ❌ 悪い例: コンポーネント内にロジックが混在
function TaskList() {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);
  const [filter, setFilter] = useState<Filter>('all');

  useEffect(() => {
    fetch('/api/tasks')
      .then(r => r.json())
      .then(setTasks)
      .catch(setError)
      .finally(() => setLoading(false));
  }, []);

  const filteredTasks = useMemo(() => {
    return filter === 'all' ? tasks : tasks.filter(t => t.status === filter);
  }, [tasks, filter]);

  // ... レンダリング
}

// ✅ 良い例: フックに分離
// useTasks.ts
function useTasks() {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    fetch('/api/tasks')
      .then(r => r.json())
      .then(setTasks)
      .catch(setError)
      .finally(() => setLoading(false));
  }, []);

  return { tasks, loading, error, setTasks };
}

// useTaskFilter.ts
function useTaskFilter(tasks: Task[], filter: Filter) {
  return useMemo(() => {
    return filter === 'all' ? tasks : tasks.filter(t => t.status === filter);
  }, [tasks, filter]);
}

// TaskList.tsx
function TaskList() {
  const { tasks, loading, error } = useTasks();
  const [filter, setFilter] = useState<Filter>('all');
  const filteredTasks = useTaskFilter(tasks, filter);

  if (loading) return <Loading />;
  if (error) return <Error error={error} />;

  return (
    <>
      <FilterBar filter={filter} onFilterChange={setFilter} />
      <ul>{filteredTasks.map(t => <TaskItem key={t.id} task={t} />)}</ul>
    </>
  );
}
```

### Compound Components パターン

```typescript
// 高凝集・低結合なコンポーネント API
interface TaskListContextValue {
  tasks: Task[];
  selectedId: string | null;
  select: (id: string) => void;
}

const TaskListContext = createContext<TaskListContextValue | null>(null);

function TaskList({ children, tasks }: { children: ReactNode; tasks: Task[] }) {
  const [selectedId, setSelectedId] = useState<string | null>(null);

  return (
    <TaskListContext.Provider value={{ tasks, selectedId, select: setSelectedId }}>
      <ul>{children}</ul>
    </TaskListContext.Provider>
  );
}

function TaskItem({ task }: { task: Task }) {
  const ctx = useContext(TaskListContext);
  if (!ctx) throw new Error('TaskItem must be used within TaskList');

  const isSelected = ctx.selectedId === task.id;

  return (
    <li onClick={() => ctx.select(task.id)} className={isSelected ? 'selected' : ''}>
      {task.title}
    </li>
  );
}

// 使用例
<TaskList tasks={tasks}>
  {tasks.map(task => (
    <TaskItem key={task.id} task={task} />
  ))}
</TaskList>
```

---

## リファクタリング戦略

### God Component の分割

**手順:**

1. コンポーネントの責務を洗い出す
2. 各責務をカスタムフックまたはサブコンポーネントに抽出
3. テストを書きながら1つずつ分離
4. 元のコンポーネントは統合のみ担当

**例:**
```
Before:
TaskDashboard.tsx (500行)
├── データ取得
├── フィルタリング
├── ソート
├── CRUD操作
├── UI状態管理
└── レンダリング

After:
features/tasks/
├── components/
│   ├── TaskDashboard.tsx (50行) - 統合のみ
│   ├── TaskList.tsx
│   ├── TaskFilters.tsx
│   └── TaskForm.tsx
├── hooks/
│   ├── useTasks.ts
│   ├── useTaskFilter.ts
│   ├── useTaskSort.ts
│   └── useTaskMutations.ts
└── types.ts
```

### 段階的なコロケーション移行

**既存プロジェクトの移行手順:**

1. **新機能からコロケーション適用**
   - 新しい機能は features/ ディレクトリに作成
   - テストを同じディレクトリに配置

2. **小さな既存機能から移行**
   - 依存関係が少ない機能を特定
   - テストを書いてから移動
   - index.ts で公開APIを制御

3. **大きな機能は段階的に**
   - まずディレクトリを作成
   - 関連ファイルを1つずつ移動
   - 各移動後にテストを実行

**移行チェックリスト:**
```
□ 移行対象の依存関係を分析
□ 移行先のディレクトリ構造を決定
□ テストがある/作成した
□ ファイルを移動
□ import パスを更新
□ テストが通過することを確認
□ 不要になった空ディレクトリを削除
```

---

**原則を常に意識する:**
- 高凝集度: 1モジュール = 1責務
- 低結合度: 依存は抽象に、注入可能に
- コロケーション: 関連ファイルは近くに
