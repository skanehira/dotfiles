# テストルールの詳細例

rules/core/testing.md の原則に対応するコード例集。

## 振る舞い vs 実装詳細

```
// Bad: 設定値のアサーション（トートロジー、仕様として無意味）
assert(config.enabled == true)
assert(capabilities.open_close == true)

// Good: 振る舞いのテスト
// 「ドキュメントが開かれた時、サーバーはXXを行う」をテスト
```

## アサーション

文字列は完全一致:

```
// Good: 完全一致 - 意図しないメッセージ変更を検出
assert(message == "Update available: 3.0.0 -> 4.0.0")

// Bad: 部分一致 - 不正なメッセージでもパスする可能性
assert(message.contains("3.0.0"))
```

構造体は全体比較:

```
// Good: 構造体全体を比較 - 欠落や不正なフィールドを検出
assert(result == expected_struct)

// Bad: 個別フィールドのアサーション - 不正なフィールドを見逃す可能性
assert(result.name == "lodash")
assert(result.version == "4.17.21")
```

## AAA (Arrange-Act-Assert) パターン

```javascript
test('should calculate total with tax', () => {
  // Arrange: テストデータと前提条件をセットアップ
  const cart = new ShoppingCart();
  cart.addItem({ price: 100, quantity: 2 });
  const taxRate = 0.1;

  // Act: テスト対象の動作を実行
  const total = cart.calculateTotal(taxRate);

  // Assert: 期待される結果を検証
  expect(total).toBe(220);
});
```
