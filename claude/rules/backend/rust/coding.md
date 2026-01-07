---
paths: **/*.rs
---

# Rust コーディングルール

## エラーハンドリング

### `inspect_err`でエラーをログ

`inspect_err`を使用してエラーをログに記録：

```rust
// パターン1: let-elseで早期リターン
let Ok(value) = fallible_operation()
    .inspect_err(|e| warn!("Operation failed: {}", e))
else {
    return;
};

// パターン2: ログして型変換で伝播
fn process() -> Result<Value, MyError> {
    fallible_operation()
        .inspect_err(|e| warn!("Operation failed: {}", e))
        .map_err(MyError::from)
}

// パターン3: ログしてそのまま伝播（同じエラー型）
fn process() -> Result<Value, SameError> {
    fallible_operation()
        .inspect_err(|e| warn!("Operation failed: {}", e))
}
```

**エラーログのためだけに`match`を使わない：**

```rust
// Bad: matchは冗長
let value = match fallible_operation() {
    Ok(v) => v,
    Err(e) => {
        warn!("Operation failed: {}", e);
        return;
    }
};
```

## 早期リターンと`let-else`

ネストした`if let`や`match`の代わりに`let-else`パターンを使用：

```rust
// Good: let-elseで早期リターン
let Some(value) = optional_value else {
    return Error::NotFound;
};

// Bad: ネスト構造
if let Some(value) = optional_value {
    // ... 深いネスト
} else {
    return Error::NotFound;
}
```

## 命名規則

共通の命名規則は `core/design.md` を参照。

### トレイト名

データ型ではなく**役割**や**振る舞い**を説明する名前：

```rust
// Good: トレイトが何をするか説明
pub trait VersionResolver { ... }
pub trait PackageFetcher { ... }
pub trait ConfigProvider { ... }

// Bad: データ型を説明するだけ
pub trait VersionCache { ... }
pub trait PackageData { ... }
pub trait Config { ... }
```

サフィックスガイドライン：
- `-er`: アクションを実行するトレイト（Resolver, Fetcher, Provider, Handler）
- `-able`: 能力を表すトレイト（Readable, Serializable）

## Option/Resultの適切な使用

### unwrap/expectの使用制限

```rust
// Good: エラーを適切に処理
let value = optional.ok_or(MyError::NotFound)?;
let value = result.map_err(MyError::from)?;

// Good: expectは理由を明記（プログラムのバグを示す場合のみ）
let config = load_config().expect("設定ファイルは初期化時に検証済み");

// Bad: 本番コードでunwrap
let value = optional.unwrap();
let value = result.unwrap();
```

### Optionのコンビネータ活用

```rust
// Good: コンビネータを使用
let result = optional
    .filter(|v| v.is_valid())
    .map(|v| v.transform())
    .unwrap_or_default();

// Good: or_elseで遅延評価
let value = cache.get(&key).or_else(|| expensive_lookup(&key));

// Bad: matchの多用
let result = match optional {
    Some(v) if v.is_valid() => Some(v.transform()),
    _ => None,
}.unwrap_or_default();
```

## イテレータの活用

```rust
// Good: イテレータチェーン
let valid_items: Vec<_> = items
    .iter()
    .filter(|item| item.is_valid())
    .map(|item| item.transform())
    .collect();

// Good: filter_mapで変換と絞り込みを同時に
let parsed: Vec<_> = strings
    .iter()
    .filter_map(|s| s.parse::<i32>().ok())
    .collect();

// Good: 畳み込み
let total: u64 = items.iter().map(|i| i.value).sum();

// Bad: 手動ループ
let mut valid_items = Vec::new();
for item in items.iter() {
    if item.is_valid() {
        valid_items.push(item.transform());
    }
}
```

## 所有権とボローイング

### 不要なcloneを避ける

```rust
// Good: 参照を使用
fn process(data: &str) -> Result<Output, Error> { ... }

// Good: 所有権が必要な場合のみ所有権を取る
fn consume(data: String) -> Result<Output, Error> { ... }

// Bad: 不要なclone
fn process(data: &str) -> Result<Output, Error> {
    let owned = data.to_string();  // 本当に必要？
    // ...
}
```

### Clone vs Copy

```rust
// Good: 小さな型はCopyを実装
#[derive(Clone, Copy)]
pub struct Point { x: f64, y: f64 }

// Good: 大きな型や高コストな型はCloneのみ
#[derive(Clone)]
pub struct LargeStruct { /* 多くのフィールド */ }
```

## deriveマクロの活用

### 標準的なderive

```rust
// Good: 必要なトレイトを適切にderive
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct UserId(String);

#[derive(Debug, Clone, PartialEq)]
pub struct Config {
    pub name: String,
    pub value: f64,  // f64はEq, Hashを実装していない
}

// Good: Copy可能な小さな型
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct Point { x: i32, y: i32 }
```

### deriveの順序

慣例的な順序に従う：
1. `Debug` - デバッグ出力
2. `Clone`, `Copy` - 複製
3. `PartialEq`, `Eq` - 等価比較
4. `PartialOrd`, `Ord` - 順序比較
5. `Hash` - ハッシュ化
6. `Default` - デフォルト値
7. `Serialize`, `Deserialize` - シリアライズ（serde）

## 可視性の最小化

公開範囲を必要最小限に制限：

```rust
// Good: クレート内のみ公開
pub(crate) struct InternalConfig { ... }

// Good: 親モジュールのみ公開
pub(super) fn helper_function() { ... }

// Good: モジュール内のみ（デフォルト）
struct PrivateHelper { ... }

// Bad: 不必要にpub
pub struct InternalImplementation { ... }  // 外部に公開する必要がない
```

### フィールドの可視性

```rust
// Good: フィールドは非公開、メソッドで公開
pub struct User {
    id: UserId,
    name: String,
}

impl User {
    pub fn id(&self) -> &UserId { &self.id }
    pub fn name(&self) -> &str { &self.name }
}

// Bad: 全フィールドをpub
pub struct User {
    pub id: UserId,
    pub name: String,
}
```

## #[must_use]属性

戻り値の無視を警告：

```rust
// Good: 結果を無視すべきでない関数
#[must_use = "この結果を使用しないとリソースリークの可能性があります"]
pub fn open_connection() -> Connection { ... }

// Good: Result型を返す関数（Resultは既にmust_use）
pub fn save(&self) -> Result<(), Error> { ... }

// Good: 構造体全体にmust_use
#[must_use]
pub struct Guard { ... }
```

## AsRef / Into による柔軟な引数

```rust
// Good: AsRefで参照を柔軟に受け取る
pub fn read_file(path: impl AsRef<Path>) -> Result<String> {
    std::fs::read_to_string(path.as_ref())
}

// 呼び出し側
read_file("config.toml")?;           // &str
read_file(Path::new("config.toml"))?; // &Path
read_file(PathBuf::from("config"))?;  // PathBuf

// Good: Intoで所有権を柔軟に受け取る
pub fn set_name(&mut self, name: impl Into<String>) {
    self.name = name.into();
}

// 呼び出し側
user.set_name("Alice");         // &str
user.set_name(String::from("Alice")); // String
```

## スライスパターン

配列やVecのパターンマッチ：

```rust
// Good: スライスパターンで先頭/末尾を取得
fn process_args(args: &[String]) {
    match args {
        [] => println!("引数なし"),
        [single] => println!("1つの引数: {}", single),
        [first, second] => println!("2つの引数: {}, {}", first, second),
        [first, rest @ ..] => println!("先頭: {}, 残り: {:?}", first, rest),
    }
}

// Good: 先頭と末尾を同時に取得
fn first_and_last<T>(slice: &[T]) -> Option<(&T, &T)> {
    match slice {
        [first, .., last] => Some((first, last)),
        [single] => Some((single, single)),
        [] => None,
    }
}
```

## ドキュメンテーション

### rustdocコメント

```rust
/// ユーザーを表す構造体
///
/// # Examples
///
/// ```
/// let user = User::new("Alice");
/// assert_eq!(user.name(), "Alice");
/// ```
pub struct User { ... }

/// 指定されたパスからファイルを読み込む
///
/// # Arguments
///
/// * `path` - 読み込むファイルのパス
///
/// # Errors
///
/// ファイルが存在しない場合や読み取り権限がない場合にエラーを返す
///
/// # Examples
///
/// ```no_run
/// let content = read_file("config.toml")?;
/// ```
pub fn read_file(path: impl AsRef<Path>) -> Result<String> { ... }
```

### モジュールドキュメント

```rust
//! # HTTP クライアントモジュール
//!
//! このモジュールはHTTPリクエストを送信するための
//! 高レベルAPIを提供します。
//!
//! ## 使用例
//!
//! ```
//! use mylib::http::Client;
//!
//! let client = Client::new();
//! let response = client.get("https://example.com").await?;
//! ```
```

## ログレベルの使い分け

```rust
use tracing::{trace, debug, info, warn, error};

// trace: 非常に詳細なデバッグ情報（関数の入出力など）
trace!(input = ?data, "処理開始");

// debug: 開発時のデバッグ情報
debug!(user_id = %id, "ユーザー情報を取得");

// info: 通常の動作ログ（起動、設定読み込みなど）
info!("サーバーがポート {} で起動しました", port);

// warn: 問題だが継続可能な状況
warn!("キャッシュの有効期限が切れています");

// error: エラー発生（処理は失敗）
error!(error = %e, "データベース接続に失敗");
```

### ログレベルの選択基準

| レベル | 用途 |
|--------|------|
| `error` | 操作の失敗、要対応 |
| `warn` | 問題だが継続可能、要監視 |
| `info` | 正常な重要イベント |
| `debug` | 開発・デバッグ用詳細 |
| `trace` | 非常に詳細なトレース |

## unsafeガイドライン

### unsafeを最小化

```rust
// Good: unsafeを小さなスコープに閉じ込める
pub fn get_unchecked(slice: &[u8], index: usize) -> u8 {
    // SAFETY: 呼び出し側がindex < slice.len()を保証
    unsafe { *slice.get_unchecked(index) }
}

// Good: 安全なラッパーを提供
pub struct AlignedBuffer { ... }

impl AlignedBuffer {
    /// バッファを作成
    ///
    /// # Safety
    /// - `ptr`は有効なメモリを指すこと
    /// - `len`はバッファの実際のサイズ以下であること
    pub unsafe fn from_raw_parts(ptr: *mut u8, len: usize) -> Self { ... }

    // 安全なコンストラクタも提供
    pub fn new(size: usize) -> Self { ... }
}
```

### SAFETYコメント

unsafeブロックには必ず安全性の根拠をコメント：

```rust
// SAFETY:
// - インデックスは事前にbounds checkされている
// - ポインタはこの関数内で作成され、有効なメモリを指す
unsafe {
    ptr.write(value);
}
```
