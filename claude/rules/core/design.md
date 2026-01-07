---
paths:
  - "**/*.go"
  - "**/*.rs"
  - "**/*.ts"
  - "**/*.lua"
---

# 設計共通ルール

## SOLID原則

### 単一責任の原則 (SRP)
- クラス/モジュールは1つの責任のみを持つ
- 変更する理由は1つだけであるべき

### 開放閉鎖の原則 (OCP)
- 拡張に対して開いている、修正に対して閉じている
- 既存コードを変更せずに機能追加できる設計

### リスコフの置換原則 (LSP)
- 派生型は基底型と置換可能であるべき
- サブタイプは親の契約を破らない

### インターフェース分離の原則 (ISP)
- クライアントが使わないメソッドへの依存を強制しない
- 大きなインターフェースより小さな専用インターフェース

### 依存性逆転の原則 (DIP)
- 上位モジュールは下位モジュールに依存しない
- 両者とも抽象に依存する

## YAGNI原則

- 「将来必要になるかもしれない」というコードを書かない
- 現在必要な機能のみを実装する
- 未使用のメソッド、フィールド、パラメータは即座に削除
- 意図が不明確なコードを変更する前にユーザーに確認

## 命名規則

### 曖昧な名前を避ける

`check`、`process`、`handle`、`do` のような曖昧な名前を避け、具体的なアクションを説明：

```
// Good: 関数が実際に何をするか説明
compare_version()
validate_input()
fetch_latest_data()

// Bad: 曖昧すぎる
check_version()
process_data()
handle_request()
```

### 戻り値の型名

操作の結果を説明する型名を使用：

```
// Good
VersionCompareResult
ParsedConfig

// Bad
CheckResult
Data
```

## 高凝集度（High Cohesion）

1つのモジュール/コンポーネントは1つの責務に集中する。

**判断基準:**
- 変更理由が1つだけか（Single Responsibility）
- テストが1つの観点に集中できるか
- 説明が「〜と〜と〜」ではなく「〜」で済むか

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

## 低結合度（Low Coupling）

モジュール間の依存は最小限かつ明示的にする。

**依存の方向性:**
```
外部（不安定）  →  ドメイン（安定）
UI層 → ビジネスロジック層 → ドメインモデル
```

**依存性注入でテスト可能にする:**
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

## コロケーション（Colocation）

関連するファイルは物理的に近くに配置する。

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

**コロケーションの利点:**
- 変更時のファイル探索が不要
- 機能削除時にディレクトリごと削除可能
- レビュー時に関連ファイルが一目瞭然
- テストとソースの対応関係が明確

## アンチパターン

避けるべき設計：

- **God Component**: 1つのコンポーネントが多すぎる責務を持つ
- **Prop Drilling地獄**: 深いネストで大量のpropsを渡す
- **テストと実装の分離**: `__tests__/`ディレクトリにテストを隔離
- **Feature Envy**: 他モジュールのデータに過度に依存
- **Shotgun Surgery**: 1つの変更で多数のファイルを修正
