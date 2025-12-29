---
paths: **/*.go
---

# Go コーディングルール

## エラーハンドリング

### %w でラップする（%v ではない）

```go
// Good: %w でラップ（errors.Is, errors.As で検査可能）
return fmt.Errorf("failed to parse config: %w", err)

// Bad: %v でラップ（元のエラーが失われる）
return fmt.Errorf("failed: %v", err)
```

### エラー処理のアンチパターン

```go
// Bad: エラーを握りつぶす
if err != nil {
    log.Println(err)
    // return がない！
}

// Bad: 同じエラーを複数回ログ
if err != nil {
    log.Printf("error: %v", err)
    return err  // 呼び出し元でもログされる
}

// Good: エラーはログするか返すか、どちらか一方
if err != nil {
    return fmt.Errorf("operation failed: %w", err)
}
```

## defer

### ループ内で defer しない

```go
// Bad: ループ内でdefer（リソースリーク）
for _, path := range paths {
    f, _ := os.Open(path)
    defer f.Close()  // ループ終了まで閉じられない
}

// Good: 関数に抽出
for _, path := range paths {
    if err := processFile(path); err != nil {
        return err
    }
}

func processFile(path string) error {
    f, err := os.Open(path)
    if err != nil {
        return err
    }
    defer f.Close()
    // ...
}
```

## context

### context を struct に格納しない

```go
// Bad: contextをstructに格納
type Service struct {
    ctx context.Context  // 避ける
}

// Good: メソッドの引数で渡す
func (s *Service) Do(ctx context.Context) error { ... }
```

## goroutine

### リーク防止

```go
// Good: 終了を保証
func StartWorker(ctx context.Context) {
    go func() {
        for {
            select {
            case <-ctx.Done():
                return  // 確実に終了
            case task := <-taskCh:
                process(task)
            }
        }
    }()
}

// Bad: 終了条件がない
func StartWorker() {
    go func() {
        for task := range taskCh {
            process(task)  // チャネルが閉じないと終了しない
        }
    }()
}
```

## チャネル

### close の責任は送信側

```go
// Good: 送信側がclose
func Producer(ch chan<- int) {
    defer close(ch)
    for i := 0; i < 10; i++ {
        ch <- i
    }
}

// Bad: 受信側がclose（パニックの原因）
func Consumer(ch chan int) {
    for v := range ch {
        process(v)
    }
    close(ch)  // 危険！
}
```

## slog

### エラーは error キーで

```go
// Good
slog.Error("operation failed", "error", err)

// Bad
slog.Error(fmt.Sprintf("operation failed: %v", err))
```
