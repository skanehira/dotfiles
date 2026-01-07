---
paths: "**/*.rs"
---

# Rust 設計思想

共通の設計原則は `core/design.md` を参照。

## 型システムの活用

### newtypeパターン

プリミティブ型をラップして型安全性を向上：

```rust
// Good: 意味のある型で区別
pub struct UserId(u64);
pub struct OrderId(u64);

fn process_user(user_id: UserId) { ... }
fn process_order(order_id: OrderId) { ... }

// Bad: プリミティブ型の混同リスク
fn process_user(user_id: u64) { ... }
fn process_order(order_id: u64) { ... }
```

### 型状態パターン

コンパイル時に状態遷移を強制：

```rust
// Good: 状態を型で表現
struct Connection<S> { state: S }
struct Disconnected;
struct Connected;

impl Connection<Disconnected> {
    fn connect(self) -> Connection<Connected> { ... }
}

impl Connection<Connected> {
    fn send(&self, data: &[u8]) { ... }
    fn disconnect(self) -> Connection<Disconnected> { ... }
}
```

## `From`トレイトによる型変換

型変換に`From`トレイトを使用するが、**変換が単純な場合のみ**：

```rust
// Good: バリアント間の単純な1対1マッピング
impl From<ParseError> for MyError {
    fn from(e: ParseError) -> Self {
        MyError::Parse(e)
    }
}

// Good: 直接的なフィールドマッピング
impl From<RawConfig> for Config {
    fn from(raw: RawConfig) -> Self {
        Config {
            name: raw.name,
            value: raw.value,
        }
    }
}
```

**`From`を実装しない**場合：
- 変換に追加のコンテキストが必要（例：ガード条件）
- 変換に外部状態や副作用が必要
- マッピングが1対1でない（例：複数のソース値が1つのターゲットにマップ）

```rust
// Bad: 変換に外部コンテキストが必要（version_existsチェック）
// Fromを強制せず、明示的なmatchを使用
let status = match compare_result {
    CompareResult::Invalid => VersionStatus::Invalid,
    _ if !version_exists => VersionStatus::NotFound,  // 外部条件
    CompareResult::Latest => VersionStatus::Latest,
    // ...
};
```

## エラー型設計

### thiserrorでカスタムエラー

```rust
use thiserror::Error;

#[derive(Debug, Error)]
pub enum AppError {
    #[error("ファイルが見つかりません: {path}")]
    NotFound { path: String },

    #[error("解析エラー: {0}")]
    Parse(#[from] ParseError),

    #[error("IO エラー")]
    Io(#[from] std::io::Error),

    #[error("不正な入力: {message}")]
    InvalidInput { message: String },
}
```

### thiserror vs anyhow

| 用途 | 選択 |
|------|------|
| ライブラリ | `thiserror` - 呼び出し側がエラーを処理できるよう型付き |
| アプリケーション | `anyhow` - 簡潔なエラー伝播、コンテキスト追加 |

```rust
// アプリケーションコード: anyhow
use anyhow::{Context, Result};

fn load_config() -> Result<Config> {
    let content = std::fs::read_to_string("config.toml")
        .context("設定ファイルの読み込みに失敗")?;
    toml::from_str(&content)
        .context("設定ファイルの解析に失敗")
}
```

## 構造体設計

### `#[non_exhaustive]`

公開APIの構造体やenumに追加して、将来のフィールド追加を許容：

```rust
#[non_exhaustive]
pub struct Config {
    pub name: String,
    pub value: u64,
}

#[non_exhaustive]
pub enum Error {
    NotFound,
    InvalidInput,
}
```

### Builderパターン

多くのオプショナルフィールドを持つ構造体に使用：

```rust
pub struct Request {
    url: String,
    method: Method,
    headers: HashMap<String, String>,
    timeout: Option<Duration>,
}

impl Request {
    pub fn builder(url: impl Into<String>) -> RequestBuilder {
        RequestBuilder {
            url: url.into(),
            method: Method::GET,
            headers: HashMap::new(),
            timeout: None,
        }
    }
}

pub struct RequestBuilder { /* fields */ }

impl RequestBuilder {
    pub fn method(mut self, method: Method) -> Self {
        self.method = method;
        self
    }

    pub fn header(mut self, key: impl Into<String>, value: impl Into<String>) -> Self {
        self.headers.insert(key.into(), value.into());
        self
    }

    pub fn timeout(mut self, timeout: Duration) -> Self {
        self.timeout = Some(timeout);
        self
    }

    pub fn build(self) -> Request {
        Request {
            url: self.url,
            method: self.method,
            headers: self.headers,
            timeout: self.timeout,
        }
    }
}
```

## Defaultトレイト

意味のあるデフォルト値がある場合は`Default`を実装：

```rust
// Good: #[derive(Default)]を使用
#[derive(Default)]
pub struct Config {
    pub timeout: u64,      // 0
    pub retry: bool,       // false
    pub name: String,      // ""
}

// Good: カスタムデフォルト値が必要な場合
impl Default for Config {
    fn default() -> Self {
        Self {
            timeout: 30,
            retry: true,
            name: String::from("default"),
        }
    }
}

// Good: Default + builderパターン
let config = Config {
    timeout: 60,
    ..Default::default()
};
```

## Cow（Clone on Write）

所有権と参照を柔軟に扱う：

```rust
use std::borrow::Cow;

// Good: 必要な時だけ所有権を取る
fn process_text(input: &str) -> Cow<str> {
    if input.contains("error") {
        // 変更が必要: 所有権を取る
        Cow::Owned(input.replace("error", "ERROR"))
    } else {
        // 変更不要: 参照のまま
        Cow::Borrowed(input)
    }
}

// Good: 設定値でよく使うパターン
pub struct Config<'a> {
    pub name: Cow<'a, str>,
    pub path: Cow<'a, Path>,
}
```

### Cowを使うべき場面

- 入力をそのまま返すか、変換して返すかが動的に決まる
- 文字列やパスを所有するか借用するかを柔軟にしたい
- パフォーマンスクリティカルで不要なアロケーションを避けたい

### Cowを避けるべき場面

- 常に所有権が必要 → `String` / `PathBuf` を使用
- 常に参照で十分 → `&str` / `&Path` を使用
- コードの複雑さが増すだけの場合
