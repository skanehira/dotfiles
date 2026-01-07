---
paths: "**/*.rs"
---

# Rust テストルール

共通のテスト原則は `common/testing.md` を参照。

## パラメータ化テスト

パラメータ化テストには`rstest`クレートを使用：

```rust
#[rstest]
#[case("input1", "expected1")]
#[case("input2", "expected2")]
fn test_something(#[case] input: &str, #[case] expected: &str) {
    assert_eq!(process(input), expected);
}
```

## 非同期テスト

非同期テストには`#[tokio::test]`を使用：

```rust
#[tokio::test]
async fn fetch_data_returns_expected_result() {
    let result = fetch_data().await;
    assert_eq!(result, expected_data());
}

// 特定のランタイム設定が必要なテスト
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn concurrent_operations_complete_successfully() { ... }
```

## エラーケースのテスト

### Result型のテスト

```rust
// エラーバリアントを明示的にテスト
#[test]
fn parse_invalid_input_returns_specific_error() {
    let result = parse("invalid");
    assert!(matches!(result, Err(ParseError::InvalidFormat(_))));
}

// エラーメッセージは完全一致を使用
#[test]
fn validation_error_has_descriptive_message() {
    let err = validate("").unwrap_err();
    assert_eq!(err.to_string(), "Input cannot be empty");
}
```

### panicのテスト

```rust
#[test]
#[should_panic(expected = "index out of bounds")]
fn access_beyond_length_panics() {
    let v = vec![1, 2, 3];
    let _ = v[10];
}
```

## モック

### mockallを使用したモッキング

`mockall`クレートを使用してモックを生成：

```rust
use mockall::predicate::eq;
#[cfg(test)]
use mockall::automock;

// cfg_attrでテスト時のみモック実装を生成
#[cfg_attr(test, automock)]
trait DataStore {
    fn get(&self, key: &str) -> Option<String>;
}

#[test]
fn service_returns_cached_value() {
    let mut mock = MockDataStore::new();
    mock.expect_get()
        .with(eq("key"))
        .returning(|_| Some("value".to_string()));

    let service = Service::new(mock);
    assert_eq!(service.get("key"), Some("value".to_string()));
}
```

**mockall使用時の注意点:**
- 同じクレート内のtraitには`#[cfg_attr(test, automock)]`を使用
- `expect_*`で期待する呼び出しを設定
- `with()`で引数のマッチャーを指定
- `returning()`で戻り値を設定
- `times()`で呼び出し回数を検証可能

## テストの構成

- ユニットテストは`#[cfg(test)] mod tests`を使用して実装と同じファイルに配置
- インテグレーションテスト（`tests/`）は複数モジュールを一緒にテストする場合のみ使用
