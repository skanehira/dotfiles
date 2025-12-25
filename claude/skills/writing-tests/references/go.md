# Go テストベストプラクティス

## テストファイル配置

**同一パッケージ配置**: テストファイルは実装ファイルと同じディレクトリに `_test.go` サフィックスで配置。

```
pkg/auth/
├── handler.go
├── handler_test.go      # 単体テスト
├── service.go
├── service_test.go
├── repository.go
└── repository_test.go
```

**統合テスト**: 別パッケージまたは `testdata/` を使用

```
pkg/auth/
├── handler.go
├── handler_test.go
├── integration_test.go  # // +build integration
└── testdata/
    └── fixtures.json
```

**パッケージ名の選択**:
- `package auth` - 内部実装にアクセス可能（ホワイトボックステスト）
- `package auth_test` - 公開APIのみテスト（ブラックボックステスト、推奨）

## テスト命名規則

`Test関数名_should期待結果_when条件` パターン：

```go
func TestCalculateTotal_shouldReturnZero_whenCartIsEmpty(t *testing.T) {}
func TestCalculateTotal_shouldSumPrices_whenCartHasItems(t *testing.T) {}
func TestLogin_shouldReturnError_whenPasswordIsInvalid(t *testing.T) {}
```

**サブテスト使用時**:

```go
func TestUserService_Create(t *testing.T) {
    t.Run("should create user when input is valid", func(t *testing.T) {})
    t.Run("should return error when email is duplicate", func(t *testing.T) {})
    t.Run("should hash password before storing", func(t *testing.T) {})
}
```

## テスト構造

### AAA (Arrange-Act-Assert) パターン

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

### Table-Driven Tests

```go
func TestAdd(t *testing.T) {
    tests := []struct {
        name     string
        a, b     int
        expected int
    }{
        {"positive numbers", 2, 3, 5},
        {"negative numbers", -2, -3, -5},
        {"mixed numbers", -2, 3, 1},
        {"zeros", 0, 0, 0},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            actual := Add(tt.a, tt.b)
            assert.Equal(t, tt.expected, actual)
        })
    }
}
```

### エラーケースのテスト

```go
func TestParseConfig_shouldReturnError_whenFileNotFound(t *testing.T) {
    _, err := ParseConfig("nonexistent.yaml")

    require.Error(t, err)
    assert.ErrorIs(t, err, os.ErrNotExist)
}

func TestValidateUser_shouldReturnValidationErrors(t *testing.T) {
    user := &User{Email: "invalid"}

    err := ValidateUser(user)

    var validationErr *ValidationError
    require.ErrorAs(t, err, &validationErr)
    assert.Contains(t, validationErr.Fields, "email")
}
```

## テストヘルパー

### t.Helper() の使用

```go
func createTestUser(t *testing.T, db *DB) *User {
    t.Helper() // エラー時のスタックトレースを改善
    user := &User{Name: "Test User", Email: "test@example.com"}
    err := db.Create(user)
    require.NoError(t, err)
    return user
}
```

### t.Cleanup() の使用

```go
func setupTestDB(t *testing.T) *DB {
    t.Helper()
    db, err := NewDB(":memory:")
    require.NoError(t, err)

    t.Cleanup(func() {
        db.Close()
    })

    return db
}
```

## モック

### インターフェースベースのモック

```go
// 実装
type UserRepository interface {
    FindByID(id string) (*User, error)
    Create(user *User) error
}

// モック（手動）
type MockUserRepository struct {
    FindByIDFunc func(id string) (*User, error)
    CreateFunc   func(user *User) error
}

func (m *MockUserRepository) FindByID(id string) (*User, error) {
    return m.FindByIDFunc(id)
}

func (m *MockUserRepository) Create(user *User) error {
    return m.CreateFunc(user)
}

// テストでの使用
func TestUserService_GetUser(t *testing.T) {
    mockRepo := &MockUserRepository{
        FindByIDFunc: func(id string) (*User, error) {
            return &User{ID: id, Name: "John"}, nil
        },
    }
    service := NewUserService(mockRepo)

    user, err := service.GetUser("1")

    require.NoError(t, err)
    assert.Equal(t, "John", user.Name)
}
```

### gomock/mockgen の使用

```go
//go:generate mockgen -source=repository.go -destination=mock_repository_test.go -package=auth_test

func TestUserService_GetUser(t *testing.T) {
    ctrl := gomock.NewController(t)
    defer ctrl.Finish()

    mockRepo := NewMockUserRepository(ctrl)
    mockRepo.EXPECT().
        FindByID("1").
        Return(&User{ID: "1", Name: "John"}, nil)

    service := NewUserService(mockRepo)
    user, err := service.GetUser("1")

    require.NoError(t, err)
    assert.Equal(t, "John", user.Name)
}
```

## HTTPハンドラテスト

```go
func TestUserHandler_GetUser(t *testing.T) {
    // Arrange
    service := &MockUserService{
        GetUserFunc: func(id string) (*User, error) {
            return &User{ID: id, Name: "John"}, nil
        },
    }
    handler := NewUserHandler(service)

    req := httptest.NewRequest(http.MethodGet, "/users/1", nil)
    rec := httptest.NewRecorder()

    // Act
    handler.GetUser(rec, req)

    // Assert
    assert.Equal(t, http.StatusOK, rec.Code)

    var response User
    err := json.Unmarshal(rec.Body.Bytes(), &response)
    require.NoError(t, err)
    assert.Equal(t, "John", response.Name)
}
```

## 推奨ライブラリ

| 用途 | ライブラリ |
|------|-----------|
| アサーション | `github.com/stretchr/testify` |
| モック生成 | `github.com/golang/mock` |
| HTTPテスト | `net/http/httptest` (標準) |
| DBテスト | `github.com/DATA-DOG/go-sqlmock` |

## テストカバレッジ

```bash
# カバレッジ計測
go test -coverprofile=coverage.out ./...

# HTMLレポート生成
go tool cover -html=coverage.out -o coverage.html

# カバレッジ確認
go tool cover -func=coverage.out
```

## アンチパターン

❌ グローバル状態への依存
❌ テスト間の暗黙的な依存関係
❌ time.Now() の直接呼び出し（注入可能にする）
❌ 外部サービスへの実際の接続
❌ t.Parallel() なしの独立したテスト
❌ エラーメッセージのない assert
