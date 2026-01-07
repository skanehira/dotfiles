# 言語別テスト命名規則

テスト名には3要素を含める：
1. **何を**（対象の機能/メソッド）
2. **どういう条件で**（入力/状態）
3. **どうなるか**（期待する結果）

## TypeScript / React

```typescript
describe('UserService', () => {
  it('returns user when valid ID is provided', () => { ... });
  it('throws error when user not found', () => { ... });
});
```

## Go

```go
// Test関数Should結果When条件
func TestUserRepositoryFindByIDShouldReturnUserWhenExists(t *testing.T) { ... }
func TestCalculateTotalShouldReturnZeroWhenCartIsEmpty(t *testing.T) { ... }
```

## Rust

```rust
// 関数_returns結果_when条件
#[test]
fn user_repository_find_by_id_returns_user_when_exists() { ... }

#[test]
fn calculate_total_returns_zero_when_cart_is_empty() { ... }
```
