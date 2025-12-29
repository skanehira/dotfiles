---
paths: **/*.go
---

# Go テストルール

## 基本原則

### 実装ではなく振る舞いをテストする

実装の詳細ではなく、外部から観測可能な振る舞いをテストする。

**リトマス試験**: テストが失敗した時、ユーザーにとって何が壊れたか説明できるか？

## テーブル駆動テスト

```go
func TestParseVersion(t *testing.T) {
    tests := []struct {
        name    string
        input   string
        want    Version
        wantErr bool
    }{
        {"valid semver", "1.2.3", Version{1, 2, 3}, false},
        {"invalid format", "invalid", Version{}, true},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got, err := ParseVersion(tt.input)
            if (err != nil) != tt.wantErr {
                t.Fatalf("error = %v, wantErr = %v", err, tt.wantErr)
            }
            if diff := cmp.Diff(tt.want, got); diff != "" {
                t.Errorf("mismatch (-want +got):\n%s", diff)
            }
        })
    }
}
```

## go-cmp オプション

```go
// 特定のフィールドを無視（ID, タイムスタンプなど）
opt := cmpopts.IgnoreFields(User{}, "ID", "CreatedAt")

// スライスの順序を無視
opt := cmpopts.SortSlices(func(a, b string) bool { return a < b })

// 非公開フィールドを比較可能に
opt := cmp.AllowUnexported(MyStruct{})
```

## テストヘルパー

ヘルパー関数では必ず `t.Helper()` を呼び出す：

```go
func assertNoError(t *testing.T, err error) {
    t.Helper()  // これがないとヘルパー内の行番号が報告される
    if err != nil {
        t.Fatalf("unexpected error: %v", err)
    }
}
```

クリーンアップは `t.Cleanup()` を使用：

```go
func setupTestDB(t *testing.T) *sql.DB {
    t.Helper()
    db, err := sql.Open("sqlite3", ":memory:")
    if err != nil {
        t.Fatalf("failed to open db: %v", err)
    }
    t.Cleanup(func() { db.Close() })
    return db
}
```

## テスト命名規則

```go
// 関数名: Test<関数名><シナリオ>（キャメルケース）
func TestParseVersionValidInput(t *testing.T) { ... }
func TestUserValidate(t *testing.T) { ... }

// サブテスト名: 説明的な名前
t.Run("returns error when input is empty", func(t *testing.T) { ... })
```

## mockio によるモック

```go
import . "github.com/ovechkin-dm/mockio/mock"

func TestUserServiceGetUser(t *testing.T) {
    SetUp(t)

    repo := Mock[UserRepository]()
    WhenSingle(repo.FindByID("user-1")).ThenReturn(&User{Name: "Alice"}, nil)

    service := NewUserService(repo)
    user, err := service.GetUser("user-1")

    // 検証
    if err != nil {
        t.Fatalf("unexpected error: %v", err)
    }
    if diff := cmp.Diff("Alice", user.Name); diff != "" {
        t.Errorf("mismatch (-want +got):\n%s", diff)
    }

    Verify(repo, Once()).FindByID("user-1")
}
```

### mockio パターン

```go
// 任意の引数にマッチ
WhenSingle(repo.FindByID(Any[string]())).ThenReturn(nil, errors.New("not found"))

// 複数回の呼び出しで異なる結果
WhenSingle(repo.FindByID("user-1")).
    ThenReturn(&User{}, nil).
    ThenReturn(nil, errors.New("error"))
```

## ゴールデンファイルテスト

`testdata/` ディレクトリに期待値ファイルを配置：

```go
func TestRender(t *testing.T) {
    want, _ := os.ReadFile("testdata/golden/output.html")
    got, err := Render(input)
    if err != nil {
        t.Fatalf("unexpected error: %v", err)
    }
    if diff := cmp.Diff(string(want), got); diff != "" {
        t.Errorf("mismatch (-want +got):\n%s", diff)
    }
}
```
