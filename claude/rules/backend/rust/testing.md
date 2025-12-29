---
paths: **/*.rs
---

# Rust テストルール

## 基本原則

### テストは仕様である
テストはシステムが何をするかを明確に伝えるべき。テストは実行可能なドキュメントである。

### テストはセーフティネットである
テストはリファクタリングで何も壊れていない確信を与える。失敗すべき時にのみ失敗すべき。

### 実装ではなく振る舞いをテストする
実装の詳細ではなく、外部から観測可能な振る舞いをテストする。

**リトマス試験**: テストが失敗した時、ユーザーにとって何が壊れたか説明できるか？できないなら、それは振る舞いのテストではない。

```rust
// Bad: 設定値のアサーション（トートロジー、仕様として無意味）
assert_eq!(config.enabled, true);
assert_eq!(capabilities.open_close, Some(true));

// Good: 振る舞いのテスト
// 「ドキュメントが開かれた時、サーバーはXXを行う」をテスト
```

**リファクタリングでテストが壊れるなら、実装の詳細をテストしている。**

### テストの独立性
各テストは完全に独立していなければならない：
- 実行順序に依存しない
- 可変状態を共有しない
- 作成したリソースをクリーンアップする
- 競合を避けるため一意のテストデータを使用する

## セルフレビューチェックリスト

テスト実装後、各テストを以下のチェックリストで必ずセルフレビューする：

1. **振る舞いのテストか？** - このテストが失敗した時、ユーザーにとって何が壊れたか説明できるか？
   - ❌ `assert_eq!(config.registry_type, RegistryType::Npm)` - 設定値であり振る舞いではない
   - ✅ `assert_eq!(diagnostics[0].message, "Update available: 1.0.0 -> 2.0.0")` - ユーザーに見える振る舞い

2. **トートロジーではないか？** - このテストは意味のあることを検証しているか？
   - ❌ getterがsetした値を返すことのテスト
   - ✅ 入力Aが出力Bを生成することのテスト

3. **冗長なヘルパーはないか？** - 不要な抽象化はないか？
   - ❌ `fn matcher() -> Matcher { Matcher }` を定義して `matcher().method()`
   - ✅ `Matcher.method()` を直接呼び出す

4. **既存パターンを盲目的に踏襲していないか？** - 他からコピーして評価せずに使っていないか？
   - 各テストを個別にこれらのルールに照らして評価する

**いずれかのチェックに失敗したら、先に進む前にテストを修正する。**

## テスト命名規則

シナリオと期待される振る舞いを説明する記述的な名前を使用：

```rust
// パターン: function_name_scenario_expected_behavior
#[test]
fn parse_version_with_invalid_input_returns_error() { ... }

#[test]
fn calculate_total_with_empty_cart_returns_zero() { ... }

// エッジケースは具体的に
#[test]
fn parse_version_with_leading_v_strips_prefix() { ... }
```

## パラメータ化テスト

- パラメータ化テストには`rstest`クレートを使用
- 複数の類似テストケースを1つのパラメータ化テストに変換
- `#[rstest]`と`#[case(...)]`属性でテストパラメータを指定

### パラメータ化を検討するタイミング

- 同じ関数に対して2つ以上のテストを書いた後
- TDDのREFACTORフェーズ中

### パラメータ化テストに変換する条件

**変換する場合:**
- テスト構造が同一（setup → execute → assertパターン）
- 入力値と期待される出力のみが異なる
- 複数のテストが異なるデータで同じ振る舞いを検証

**変換しない場合:**
- テストのセットアップロジックがケース間で大きく異なる
- テストが異なる振る舞いを検証（単なる異なる入力ではない）
- 各テストが固有のアサーションやエラーハンドリングを必要とする

例:
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

## モックと外部依存

### 実際の実装を優先

可能な限り実際の実装を使用。モックは以下の場合のみ：
- 外部ネットワーク呼び出し
- 分離が必要なファイルシステム操作
- 時間依存の振る舞い
- 非決定的な操作

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

// 実際の実装
struct RedisStore { ... }
impl DataStore for RedisStore { ... }

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
- 同じクレート内のtraitには`#[cfg_attr(test, automock)]`を使用（テスト時のみモック生成）
- `expect_*`で期待する呼び出しを設定
- `with()`で引数のマッチャーを指定
- `returning()`で戻り値を設定
- `times()`で呼び出し回数を検証可能

## アサーションルール

### 文字列アサーションは完全一致を使用

`contains()`や部分一致ではなく、必ず`assert_eq!`で完全一致比較を使用：

```rust
// Good: 完全一致 - 意図しないメッセージ変更を検出
assert_eq!(params.message, "Update available: 3.0.0 -> 4.0.0");

// Bad: 部分一致 - 不正なメッセージでもパスする可能性
assert!(params.message.contains("3.0.0"));
assert!(params.message.contains("4.0.0"));
```

**理由:**
- 完全一致はメッセージフォーマットの意図しない変更を検出
- 部分一致はメッセージが根本的に間違っていてもパスする可能性
- テストは仕様として機能 - 完全一致は期待される出力を正確にドキュメント化

### 個別フィールドではなく構造体全体を比較

構造体をテストする際は、個別フィールドではなく構造体全体を比較：

```rust
// Good: 構造体全体を比較 - 欠落や不正なフィールドを検出
assert_eq!(
    result,
    PackageInfo {
        name: "lodash".to_string(),
        version: "4.17.21".to_string(),
        registry_type: RegistryType::Npm,
        start_offset: 57,
        end_offset: 64,
        line: 3,
        column: 15,
    }
);

// Bad: 個別フィールドのアサーション - 不正なフィールドを見逃す可能性
assert_eq!(result.name, "lodash");
assert_eq!(result.version, "4.17.21");
assert_eq!(result.registry_type, RegistryType::Npm);
```

**理由:**
- 構造体全体の比較は任意のフィールドの変更を検出
- 個別フィールドのアサーションは新規追加や変更されたフィールドを見逃す可能性
- テストは期待される出力の完全な仕様として機能

**順序が非決定的なコレクション（例：HashMapのキー）の場合:**
```rust
// 比較前にソート
let mut versions = result.versions;
versions.sort();
assert_eq!(versions, vec!["1.0.0".to_string(), "2.0.0".to_string()]);
```

## テストの構成

- ユニットテストは`#[cfg(test)] mod tests`を使用して実装と同じファイルに配置
- インテグレーションテスト（`tests/`）は複数モジュールを一緒にテストする場合のみ使用
- テスト名は記述的に: `function_name_scenario_expected_behavior`
