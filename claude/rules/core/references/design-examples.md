# 設計ルールの詳細例

rules/core/design.md の原則に対応するコード例集。

## 外界 DI

```typescript
// ❌ 悪い例: 具体的な実装に依存
function UserProfile() {
  const user = fetchUserFromAPI(); // テスト困難
}

// ✅ 良い例: 抽象に依存（依存性注入）
function UserProfile({ dataSource }: { dataSource: UserDataSource }) {
  const user = dataSource.getUser(); // テストでモック可能
}
```

IO を持つカスタムフック:

- ✅ ステートだけを持つ hook (`useToggle` / `useDebounce`) は OK
- ❌ 内部で fetch / localStorage に触れる hook (`useFetchUser`) は禁止
- IO 操作は **props / context 経由で渡された関数** を hook が呼び出す形にする。テストでは fake を context に流すだけで済み、モックパッチ不要

## 命名

```
// Good: 関数が実際に何をするか説明
compare_version()
validate_input()
fetch_latest_data()

// Bad: 曖昧すぎる
check_version()
process_data()
handle_request()

// 戻り値の型名
// Good: VersionCompareResult / ParsedConfig
// Bad: CheckResult / Data
```

## 高凝集

```
❌ 悪い例: UserDashboard
- ユーザー情報の取得
- グラフの描画
- 通知の管理
- 設定の保存
→ 4つの責務が混在

✅ 良い例: 責務ごとに分離
- UserProfile: ユーザー情報表示のみ
- UserChart: グラフ描画のみ
- NotificationManager: 通知管理のみ
```

## コロケーション

```
推奨ディレクトリ構造:

src/
├── features/              # 機能別ディレクトリ
│   ├── auth/
│   │   ├── LoginForm.tsx
│   │   ├── LoginForm.test.tsx    # テストをコロケーション
│   │   ├── useAuth.ts
│   │   ├── useAuth.test.ts
│   │   └── types.ts              # この機能の型
│   │
│   └── tasks/
│       ├── TaskList.tsx
│       ├── TaskList.test.tsx
│       └── types.ts
│
├── components/            # 共有UIコンポーネント
│   └── ui/
│       ├── Button.tsx
│       └── Button.test.tsx
│
└── hooks/                 # 共有フック
    ├── useDebounce.ts
    └── useDebounce.test.ts
```

利点: 変更時のファイル探索が不要 / 機能削除時にディレクトリごと削除可能 / レビュー時に関連ファイルが一目瞭然 / テストとソースの対応が明確。
