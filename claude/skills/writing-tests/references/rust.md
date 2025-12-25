# Rust テストベストプラクティス

## テストファイル配置

### 単体テスト: モジュール内に配置

```rust
// src/lib.rs または src/user.rs
pub fn validate_email(email: &str) -> bool {
    email.contains('@') && email.contains('.')
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validate_email_returns_true_when_email_is_valid() {
        assert!(validate_email("user@example.com"));
    }

    #[test]
    fn validate_email_returns_false_when_at_sign_missing() {
        assert!(!validate_email("userexample.com"));
    }
}
```

### 統合テスト: `tests/` ディレクトリに配置

```
my_crate/
├── src/
│   ├── lib.rs
│   └── user.rs
├── tests/                    # 統合テスト
│   ├── user_integration.rs
│   └── common/
│       └── mod.rs            # 共通ヘルパー
└── Cargo.toml
```

```rust
// tests/user_integration.rs
use my_crate::UserService;

#[test]
fn user_service_creates_user_when_input_valid() {
    let service = UserService::new();
    let result = service.create_user("john@example.com");
    assert!(result.is_ok());
}
```

### 共通テストヘルパー

```rust
// tests/common/mod.rs
pub fn setup_test_db() -> TestDb {
    TestDb::new(":memory:")
}

// tests/user_integration.rs
mod common;

#[test]
fn test_with_db() {
    let db = common::setup_test_db();
    // ...
}
```

## テスト命名規則

`関数名_returns/does_期待結果_when_条件` パターン：

```rust
#[test]
fn calculate_total_returns_zero_when_cart_is_empty() {}

#[test]
fn calculate_total_returns_sum_when_cart_has_items() {}

#[test]
fn login_returns_error_when_password_is_invalid() {}

#[test]
fn parse_config_panics_when_file_not_found() {}
```

## テスト構造

### AAA (Arrange-Act-Assert) パターン

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

### 複数ケースのテスト（マクロ使用）

```rust
macro_rules! test_add {
    ($name:ident, $a:expr, $b:expr, $expected:expr) => {
        #[test]
        fn $name() {
            assert_eq!(add($a, $b), $expected);
        }
    };
}

test_add!(add_positive_numbers, 2, 3, 5);
test_add!(add_negative_numbers, -2, -3, -5);
test_add!(add_mixed_numbers, -2, 3, 1);
test_add!(add_zeros, 0, 0, 0);
```

### rstest を使用したパラメータ化テスト

```rust
use rstest::rstest;

#[rstest]
#[case(2, 3, 5)]
#[case(-2, -3, -5)]
#[case(-2, 3, 1)]
#[case(0, 0, 0)]
fn add_returns_correct_sum(#[case] a: i32, #[case] b: i32, #[case] expected: i32) {
    assert_eq!(add(a, b), expected);
}
```

### rstest フィクスチャ

```rust
use rstest::*;

#[fixture]
fn test_db() -> TestDb {
    TestDb::new(":memory:")
}

#[fixture]
fn user_repo(test_db: TestDb) -> UserRepository {
    UserRepository::new(test_db)
}

#[rstest]
fn find_by_id_returns_user(user_repo: UserRepository) {
    let user = user_repo.find_by_id("1");
    assert!(user.is_some());
}
```

## エラーテスト

### Result のテスト

```rust
#[test]
fn parse_config_returns_error_when_file_not_found() {
    let result = parse_config("nonexistent.yaml");

    assert!(result.is_err());
    let err = result.unwrap_err();
    assert!(matches!(err, ConfigError::FileNotFound(_)));
}
```

### パニックのテスト

```rust
#[test]
#[should_panic(expected = "index out of bounds")]
fn get_item_panics_when_index_out_of_bounds() {
    let items = vec![1, 2, 3];
    let _ = items[10];
}
```

### カスタムエラーのテスト

```rust
#[test]
fn validate_user_returns_validation_error_when_email_invalid() {
    let user = User { email: "invalid".to_string() };

    let result = validate_user(&user);

    match result {
        Err(ValidationError::InvalidEmail(msg)) => {
            assert!(msg.contains("@"));
        }
        _ => panic!("Expected InvalidEmail error"),
    }
}
```

## モック

### mockall クレート

```rust
use mockall::{automock, predicate::*};

#[automock]
trait UserRepository {
    fn find_by_id(&self, id: &str) -> Option<User>;
    fn create(&self, user: &User) -> Result<(), DbError>;
}

#[test]
fn user_service_get_user_returns_user_when_found() {
    let mut mock_repo = MockUserRepository::new();
    mock_repo
        .expect_find_by_id()
        .with(eq("1"))
        .times(1)
        .returning(|_| Some(User::new("1", "John")));

    let service = UserService::new(Box::new(mock_repo));
    let user = service.get_user("1");

    assert!(user.is_some());
    assert_eq!(user.unwrap().name, "John");
}
```

### 手動モック（トレイトベース）

```rust
trait EmailSender {
    fn send(&self, to: &str, body: &str) -> Result<(), SendError>;
}

struct MockEmailSender {
    sent_emails: RefCell<Vec<(String, String)>>,
}

impl EmailSender for MockEmailSender {
    fn send(&self, to: &str, body: &str) -> Result<(), SendError> {
        self.sent_emails.borrow_mut().push((to.to_string(), body.to_string()));
        Ok(())
    }
}

#[test]
fn notification_service_sends_email() {
    let mock_sender = MockEmailSender {
        sent_emails: RefCell::new(vec![]),
    };
    let service = NotificationService::new(&mock_sender);

    service.notify("user@example.com", "Hello");

    let emails = mock_sender.sent_emails.borrow();
    assert_eq!(emails.len(), 1);
    assert_eq!(emails[0].0, "user@example.com");
}
```

## 非同期テスト

### tokio::test

```rust
#[tokio::test]
async fn fetch_user_returns_user_when_api_succeeds() {
    let client = TestClient::new();
    let result = fetch_user(&client, "1").await;

    assert!(result.is_ok());
    assert_eq!(result.unwrap().name, "John");
}
```

### actix-rt（Actix Web）

```rust
#[actix_rt::test]
async fn index_returns_ok() {
    let app = test::init_service(App::new().route("/", web::get().to(index))).await;
    let req = test::TestRequest::get().uri("/").to_request();
    let resp = test::call_service(&app, req).await;

    assert!(resp.status().is_success());
}
```

## 推奨クレート

| 用途 | クレート |
|------|---------|
| パラメータ化テスト | `rstest` |
| モック | `mockall` |
| アサーション拡張 | `pretty_assertions` |
| HTTPクライアントモック | `wiremock` |
| 非同期テスト | `tokio-test` |
| プロパティベーステスト | `proptest` |

## テスト実行

```bash
# 全テスト実行
cargo test

# 特定のテスト実行
cargo test test_name

# 特定モジュールのテスト
cargo test module_name::

# 統合テストのみ
cargo test --test integration_test_file

# 出力表示
cargo test -- --nocapture

# 並列実行制限
cargo test -- --test-threads=1
```

## アンチパターン

❌ `unwrap()` の乱用（`expect()` でメッセージを追加）
❌ テスト間で共有される可変グローバル状態
❌ `#[ignore]` のまま放置されたテスト
❌ 非決定的なテスト（ランダム、時間依存）
❌ 過度に複雑なセットアップ
❌ アサーションメッセージなしの `assert!`
