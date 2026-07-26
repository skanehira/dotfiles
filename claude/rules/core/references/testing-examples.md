---
# 常駐読み込みさせないためのマーカー (このパスにマッチするファイルは存在しない)。
# 本ファイルは必要になったときに Read で参照する。
paths:
  - "__read-on-demand-only__"
---

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

## 否定形・不在アサーション

判定リトマス: **テスト対象を no-op に置き換えてもこのテストは通るか**。通るなら仕様を検証していない。

```javascript
// Bad: 「エラーが投げられない」だけ - parse が undefined を返す空実装でも通る
expect(() => parse('1.2.3')).not.toThrow();

// Good: 何が起きるかを assert する
expect(parse('1.2.3')).toEqual({ major: 1, minor: 2, patch: 3 });
```

```javascript
// Bad: 「エラーが表示されない」だけ - 画面が空でも通る
render(<Form email="valid@example.com" />);
expect(screen.queryByText('メールアドレスの形式が不正です')).toBeNull();

// Good: 正常系で「何が表示されるか」を assert する
render(<Form email="valid@example.com" />);
expect(screen.getByRole('button', { name: '送信' })).toBeEnabled();
```

正当な否定形の例（testing.md の条件 (a)(b)(c) をすべて満たす）:

```javascript
// (a) 仕様: 未入力時は送信できない
it('does not call onSubmit when the form is empty', async () => {
  const handleSubmit = vi.fn();
  render(<Form value="" onSubmit={handleSubmit} />);

  const button = screen.getByRole('button', { name: '送信' });
  expect(button).toBeDisabled();        // (b) no-op に置き換えたら落ちる正の assertion
  await userEvent.click(button);

  expect(handleSubmit).not.toHaveBeenCalled();
});

// (c) 対になる正の振る舞いを隣接テストで pin する
it('calls onSubmit with the entered value when the form is filled', async () => {
  const handleSubmit = vi.fn();
  render(<Form value="hello" onSubmit={handleSubmit} />);

  await userEvent.click(screen.getByRole('button', { name: '送信' }));

  expect(handleSubmit).toHaveBeenCalledWith('hello');
});
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
