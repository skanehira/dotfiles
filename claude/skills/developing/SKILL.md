---
name: developing
description: テスト駆動開発（TDD）方法論に従って新機能の実装やバグ修正を行います。新機能の実装、バグ修正、既存機能の拡張時に使用します。RED→GREEN→REFACTORサイクルをテストファーストアプローチで厳格に遵守します。高凝集度・低結合度・コロケーションを意識したアーキテクチャ設計を適用します。
---

# 開発（TDD + アーキテクチャ設計）

Kent BeckのTDD方法論と、高凝集度・低結合度・コロケーションの原則を組み合わせた開発アプローチ。

## Design Thinking（設計思考）

実装前に以下の観点で設計を検討する：

### 1. 責務の明確化
- **この機能の単一責務は何か？**
- **この変更は既存の責務を侵害しないか？**
- **テストしやすい単位に分割できるか？**

### 2. 依存関係の分析
- **このモジュールが依存するものは何か？**（依存方向は内向き？外向き？）
- **依存を注入可能にできるか？**（テストダブルで置換可能か）
- **循環依存が発生しないか？**

### 3. 配置の決定
- **この機能はどこに配置すべきか？**（コロケーション原則に従う）
- **関連するテスト・型・ヘルパーは同じ場所に配置できるか？**
- **変更時に影響範囲が最小化されるか？**

## コア原則

### 高凝集度（High Cohesion）

**1つのモジュール/コンポーネントは1つの責務に集中する**

```
❌ 悪い例: UserDashboard.tsx
- ユーザー情報の取得
- グラフの描画
- 通知の管理
- 設定の保存
→ 4つの責務が混在

✅ 良い例:
src/features/user/
├── UserProfile.tsx      # ユーザー情報表示のみ
├── UserProfile.test.tsx # コロケーション
├── useUserData.ts       # データ取得ロジック
├── useUserData.test.ts
└── types.ts             # この機能の型定義
```

**判断基準:**
- 変更理由が1つだけか（Single Responsibility）
- テストが1つの観点に集中できるか
- 説明が「〜と〜と〜」ではなく「〜」で済むか

### 低結合度（Low Coupling）

**モジュール間の依存は最小限かつ明示的にする**

```typescript
// ❌ 悪い例: 具体的な実装に依存
import { fetchUserFromAPI } from '../api/userApi';

function UserProfile() {
  const user = fetchUserFromAPI(); // テスト困難
}

// ✅ 良い例: 抽象に依存（依存性注入）
interface UserDataSource {
  getUser(): Promise<User>;
}

function UserProfile({ dataSource }: { dataSource: UserDataSource }) {
  const user = dataSource.getUser(); // テストでモック可能
}
```

**依存の方向性:**
```
外部（不安定）  →  ドメイン（安定）
UI層 → ビジネスロジック層 → ドメインモデル
```

### コロケーション（Colocation）

**関連するファイルは物理的に近くに配置する**

```
推奨ディレクトリ構造:

src/
├── features/              # 機能別ディレクトリ
│   ├── auth/
│   │   ├── LoginForm.tsx
│   │   ├── LoginForm.test.tsx    # テストをコロケーション
│   │   ├── useAuth.ts
│   │   ├── useAuth.test.ts
│   │   ├── authApi.ts
│   │   ├── authApi.test.ts
│   │   └── types.ts              # この機能の型
│   │
│   └── tasks/
│       ├── TaskList.tsx
│       ├── TaskList.test.tsx
│       ├── TaskItem.tsx
│       ├── TaskItem.test.tsx
│       ├── useTaskActions.ts
│       ├── useTaskActions.test.ts
│       └── types.ts
│
├── components/            # 共有UIコンポーネント
│   └── ui/
│       ├── Button.tsx
│       ├── Button.test.tsx
│       ├── Modal.tsx
│       └── Modal.test.tsx
│
├── hooks/                 # 共有フック
│   ├── useDebounce.ts
│   └── useDebounce.test.ts
│
└── types/                 # 共有型定義
    └── index.ts
```

**コロケーションの利点:**
- 変更時のファイル探索が不要
- 機能削除時にディレクトリごと削除可能
- レビュー時に関連ファイルが一目瞭然
- テストとソースの対応関係が明確

## TDD絶対ルール

1. **テストなしにコードを書かない** - 例外なし
2. **RED→GREEN→REFACTORサイクルに従う** - 厳格に遵守
3. **最小限の実装** - 現在のテストを通過するコードのみ書く
4. **グリーンの時のみリファクタリング** - リファクタリング前にテストが通過していなければならない

## ワークフロー

### ステップ1: 設計思考（Design Thinking）

実装前に問いかける：
```
□ この機能の単一責務は何か？
□ どのディレクトリに配置すべきか？（コロケーション）
□ 依存は注入可能か？（テスト容易性）
□ 既存コードへの影響範囲は？
```

### ステップ2: 作業計画（TodoWriteを使用）

構造化されたタスクリストを作成：
```
- [ ] 失敗するテストを書く（RED）
- [ ] テストを通過させる最小限の実装（GREEN）
- [ ] リファクタリング（必要に応じて）
- [ ] 品質チェック（lint, format, build, test）
```

### ステップ3: REDフェーズ - 失敗するテストを書く

**テストファイルの配置（コロケーション）:**
```
src/features/auth/
├── LoginForm.tsx         # 実装
└── LoginForm.test.tsx    # テスト（同じディレクトリ）
```

**テストの書き方:**
```typescript
// src/features/auth/LoginForm.test.tsx
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { LoginForm } from './LoginForm';

describe('LoginForm', () => {
  // 依存を注入可能にする
  const mockOnSubmit = vi.fn();

  test('正しい資格情報でログインできる', async () => {
    render(<LoginForm onSubmit={mockOnSubmit} />);

    await userEvent.type(screen.getByLabelText('メール'), 'user@example.com');
    await userEvent.type(screen.getByLabelText('パスワード'), 'password123');
    await userEvent.click(screen.getByRole('button', { name: 'ログイン' }));

    expect(mockOnSubmit).toHaveBeenCalledWith({
      email: 'user@example.com',
      password: 'password123',
    });
  });
});
```

**テストを実行して失敗を確認:**
```bash
npm test
# テストは失敗するべき - これは期待通りで必須
```

### ステップ4: GREENフェーズ - テストを通過させる

**最小限の実装:**
```typescript
// src/features/auth/LoginForm.tsx
interface LoginFormProps {
  onSubmit: (credentials: { email: string; password: string }) => void;
}

export function LoginForm({ onSubmit }: LoginFormProps) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onSubmit({ email, password });
  };

  return (
    <form onSubmit={handleSubmit}>
      <label>
        メール
        <input value={email} onChange={(e) => setEmail(e.target.value)} />
      </label>
      <label>
        パスワード
        <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} />
      </label>
      <button type="submit">ログイン</button>
    </form>
  );
}
```

### ステップ5: REFACTORフェーズ - 品質向上

**すべてのテストがグリーンの場合のみ進める。**

リファクタリングの観点：
- 高凝集度を維持しているか
- 低結合度を維持しているか
- 重複を排除できるか

### ステップ6: 品質チェック（必須）

```bash
# すべてのチェックが通過するまでタスクは完了しない
npm run lint     # リンターを実行
npm run format   # フォーマッターを実行
npm run build    # ビルドを実行
npm test         # テストを実行
```

## バグ修正プロセス

1. **テストでバグを再現**（テストは失敗するべき）
2. **最小限の変更で修正**
3. **エッジケーステストを追加**
4. **必要に応じてリファクタリング**

## アンチパターン

### 避けるべき設計

❌ **God Component**: 1つのコンポーネントが多すぎる責務を持つ
❌ **Prop Drilling地獄**: 深いネストで大量のpropsを渡す
❌ **テストと実装の分離**: `__tests__/`ディレクトリにテストを隔離
❌ **Feature Envy**: 他モジュールのデータに過度に依存
❌ **Shotgun Surgery**: 1つの変更で多数のファイルを修正

### 避けるべきTDD違反

❌ テストを「後で」書く
❌ テストを書く前に実装する
❌ テストがREDの時にリファクタリング
❌ 複数の機能を同時に実装
❌ 初期化のみチェックする意味のないテストを書く

## コミットガイドライン

```bash
# 構造変更（リファクタリング）
[STRUCTURAL] refactor: コンポーネントをfeatures/ディレクトリに移動

# 動作変更（機能追加・バグ修正）
[BEHAVIORAL] feat: ユーザー認証機能を追加
[BEHAVIORAL] fix: ログインエラーハンドリングを修正
```

## リソース

### references/architecture-patterns.md
高凝集度・低結合度・コロケーションの詳細パターン：
- コンポーネント分割戦略
- 依存性注入パターン
- ディレクトリ構造の具体例
- React/TypeScript特有のパターン

### references/tdd-guidelines.md
詳細なTDDガイドライン：
- 高度なテストパターン
- テスト整理戦略
- 一般的なTDDアンチパターン
- 言語別TDDの例

---

**覚えておくこと: 高凝集度・低結合度・コロケーションを意識し、すべての実装はテスト駆動でなければならない。例外なし。**
