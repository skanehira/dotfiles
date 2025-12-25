---
name: writing-tests
description: TDD方法論に従ってテストを作成します。テストファイルの配置（コロケーション）、命名規則、テスト構造のベストプラクティスに従います。React/TypeScript、Go、Rustで適切なパターンを使い分けます。「テストを書いて」「テストを作成」「単体テストを追加」などのリクエストで起動します。
---

# テスト作成

TDD方法論に従ってテストを作成する。

## ワークフロー

### ステップ1: テスト対象の確認

テスト対象のコードを読み込み、以下を把握する：
- 対象の機能/メソッドの責務
- 入力と出力の型
- エッジケースと境界条件
- 依存関係（モックが必要か）

### ステップ2: 言語/フレームワークの特定

プロジェクトの言語を特定し、対応するリファレンスを参照する：

| 言語/フレームワーク | リファレンス |
|-------------------|-------------|
| React + TypeScript | [references/react-typescript.md](references/react-typescript.md) |
| Go | [references/go.md](references/go.md) |
| Rust | [references/rust.md](references/rust.md) |

### ステップ3: テストファイルの配置

**共通原則: コロケーション** - テストは実装の近くに配置する。

#### React + TypeScript
```
src/features/auth/
├── LoginForm.tsx
├── LoginForm.test.tsx    # コンポーネントと同じディレクトリ
├── useAuth.ts
└── useAuth.test.ts
```

#### Go
```
pkg/auth/
├── handler.go
├── handler_test.go       # 同ディレクトリに _test.go
├── service.go
└── service_test.go
```

#### Rust
```
src/
├── lib.rs                # 単体テストは #[cfg(test)] mod tests {} でモジュール内
└── user.rs
tests/                    # 統合テストは tests/ ディレクトリ
└── user_integration.rs
```

詳細は各言語のリファレンスを参照。

### ステップ4: テスト命名

テスト名には3要素を含める：
1. **何を**（対象の機能/メソッド）
2. **どういう条件で**（入力/状態）
3. **どうなるか**（期待する結果）

| 言語 | パターン | 例 |
|------|---------|---|
| React/TS | `describe` + `it` | `it('returns zero when cart is empty')` |
| Go | `Test関数_should結果_when条件` | `TestCalculateTotal_shouldReturnZero_whenCartIsEmpty` |
| Rust | `関数_returns結果_when条件` | `calculate_total_returns_zero_when_cart_is_empty` |

### ステップ5: テスト構造

**AAA (Arrange-Act-Assert) パターン**を基本とする。

#### React + TypeScript
```typescript
it('displays user name when data is loaded', async () => {
  // Arrange
  const mockUser = { name: 'John' }
  server.use(rest.get('/api/user', (req, res, ctx) => res(ctx.json(mockUser))))

  // Act
  render(<UserProfile />)

  // Assert
  expect(await screen.findByText('John')).toBeInTheDocument()
})
```

#### Go
```go
func TestUserRepository_FindByID_shouldReturnUser_whenExists(t *testing.T) {
    // Arrange
    db := setupTestDB(t)
    repo := NewUserRepository(db)
    expected := &User{ID: "1", Name: "John"}
    repo.Create(expected)

    // Act
    actual, err := repo.FindByID("1")

    // Assert
    require.NoError(t, err)
    assert.Equal(t, expected.Name, actual.Name)
}
```

#### Rust
```rust
#[test]
fn user_repository_find_by_id_returns_user_when_exists() {
    // Arrange
    let db = setup_test_db();
    let repo = UserRepository::new(&db);
    let expected = User::new("1", "John");
    repo.create(&expected).unwrap();

    // Act
    let actual = repo.find_by_id("1").unwrap();

    // Assert
    assert_eq!(expected.name, actual.name);
}
```

詳細は各言語のリファレンスを参照。

### ステップ6: テストの種類と優先度

**テスティングトロフィー**（優先順位）：

1. **単体テスト**（基盤）: 高速、集中、多数
2. **統合テスト**（中間）: コンポーネント間の相互作用
3. **E2Eテスト**（頂点）: 最小限だが重要なユーザーフロー

### ステップ7: モック

依存性注入を活用してテスト可能にする。詳細は各言語のリファレンスを参照。

## 必須テストケース

- **正常系**: 期待通りの入力で期待通りの出力
- **エッジケース**: 境界値、空の入力、最大値/最小値
- **エラー系**: 不正な入力、例外処理

## セルフレビュー

テスト作成後、以下のチェックリストで確認する。
**問題がある場合は修正し、すべての項目がクリアされるまで繰り返す。**

- [ ] テスト名が3要素（何を、条件、結果）を含んでいる
- [ ] AAA/Given-When-Thenパターンに従っている
- [ ] 正常系・エッジケース・エラー系をカバー
- [ ] テストが独立していて他のテストに依存しない
- [ ] モックが適切に使用されている
- [ ] テストが高速に実行できる
