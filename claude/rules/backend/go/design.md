---
paths: **/*.go
---

# Go 設計思想

## Accept interfaces, return structs

```go
// Good: インターフェースを受け取る
func NewService(repo Repository) *Service {
    return &Service{repo: repo}
}

// Good: 具体的な型を返す
func NewUserRepository(db *sql.DB) *UserRepository {
    return &UserRepository{db: db}
}

// Bad: インターフェースを返す
func NewRepository(db *sql.DB) Repository {
    return &userRepository{db: db}
}
```

## 小さなインターフェース

```go
// Good: 最小限のインターフェース
type UserFinder interface {
    FindByID(ctx context.Context, id string) (*User, error)
}

type UserSaver interface {
    Save(ctx context.Context, user *User) error
}

// 必要に応じて合成
type UserRepository interface {
    UserFinder
    UserSaver
}
```

### インターフェースの定義場所

使用する側でインターフェースを定義（実装側ではない）

```go
// Good: 使用する側（serviceパッケージ）で定義
package service

type Repository interface {
    GetUser(ctx context.Context, id string) (*User, error)
}
```

## 機能オプションパターン

```go
type Option func(*Server)

func WithTimeout(d time.Duration) Option {
    return func(s *Server) { s.timeout = d }
}

func NewServer(opts ...Option) *Server {
    s := &Server{timeout: 30 * time.Second}
    for _, opt := range opts {
        opt(s)
    }
    return s
}
```

## エラー型設計

### センチネルエラー

```go
var (
    ErrNotFound     = errors.New("not found")
    ErrUnauthorized = errors.New("unauthorized")
)

// 使用側
if errors.Is(err, ErrNotFound) {
    // 404を返す
}
```

### カスタムエラー型

```go
type ValidationError struct {
    Field   string
    Message string
}

func (e *ValidationError) Error() string {
    return fmt.Sprintf("validation error: %s: %s", e.Field, e.Message)
}

// 使用側
var validErr *ValidationError
if errors.As(err, &validErr) {
    fmt.Println("field:", validErr.Field)
}
```

## ゼロ値の活用

```go
// Good: ゼロ値が有用な設計
type Buffer struct {
    buf []byte
}

func (b *Buffer) Write(p []byte) {
    b.buf = append(b.buf, p...)  // buf が nil でも動作
}

// Good: オプショナルな設定はゼロ値がデフォルト
type Config struct {
    Timeout time.Duration  // ゼロ値 = デフォルトを使用
}

func NewClient(cfg Config) *Client {
    if cfg.Timeout == 0 {
        cfg.Timeout = 30 * time.Second
    }
    // ...
}
```
