---
name: development
description: テスト駆動開発（TDD）方法論に従って新機能の実装やバグ修正を行う。新機能の実装、バグ修正、既存機能の拡張時に使用する。RED→GREEN→REFACTORサイクルをテストファーストアプローチで厳格に遵守する。
---

# 開発（TDD）

## 概要

Kent BeckのTDD方法論を使用してすべての本番コードを実装する。まず失敗するテストを書き、テストを通過させる最小限のコードを実装し、その後品質向上のためリファクタリングを行う。失敗するテストなしに本番コードを書いてはならない。

## このスキルを使用するタイミング

以下の場合に使用する：
- 新機能や機能性の実装時
- 既存コードのバグ修正時
- 既存機能の拡張や修正時
- 動作変更を必要とする本番コードの変更時

## TDD絶対ルール

1. **テストなしにコードを書かない** - 例外なし
2. **RED→GREEN→REFACTORサイクルに従う** - 厳格に遵守
3. **最小限の実装** - 現在のテストを通過するコードのみ書く
4. **グリーンの時のみリファクタリング** - リファクタリング前にテストが通過していなければならない

## コアワークフロー

### ステップ1: 作業計画（TodoWriteを使用）

開始前に構造化されたタスクリストを作成する：

```bash
# 例: ユーザー認証機能
- [ ] 認証失敗のテストを書く
- [ ] テストを通過させる最小限の実装
- [ ] 認証成功のテストを書く
- [ ] 実装を拡張
- [ ] リファクタリング（必要に応じてtidy-firstに委譲）
```

### ステップ2: REDフェーズ - 失敗するテストを書く

**要件:**
- 明確で説明的なテスト名（例: `shouldReturnErrorWhenPasswordIsInvalid`）
- 一度に1つの動作のみテスト
- テストの失敗を確認（RED）

**例:**
```javascript
describe('UserAuthentication', () => {
  test('shouldReturnErrorWhenPasswordIsInvalid', () => {
    const auth = new UserAuthentication();
    const result = auth.login('user@example.com', 'wrong_password');
    expect(result.error).toBe('Invalid credentials');
  });
});
```

**テストを実行して失敗を確認:**
```bash
npm test  # または適切なテストコマンド
# テストは失敗するべき - これは期待通りで必須
```

### ステップ3: GREENフェーズ - テストを通過させる

**要件:**
- テストを通過させるために必要な最小限のコードのみ書く
- ハードコーディングは許容される（後でリファクタリング）
- すべてのテストが通過することを確認

**例（最小限の実装）:**
```javascript
class UserAuthentication {
  login(email, password) {
    // 最小限の実装 - テストを通過させるだけ
    return { error: 'Invalid credentials' };
  }
}
```

**再度テストを実行:**
```bash
npm test
# すべてのテストが通過するべき - GREENフェーズ完了
```

### ステップ4: REFACTORフェーズ - 品質向上

**すべてのテストがグリーンの場合のみ進める。**

単純なリファクタリングは直接進める。大規模な構造変更の場合はtidy-firstに委譲する：

```bash
# 複雑なリファクタリングをtidy-firstスキルに委譲
Task(
    subagent_type="tidy-first",
    prompt="認証ロジックの重複を排除し、構造を改善する",
    description="コードクリーンアップ"
)
```

**リファクタリング後:**
```bash
npm test
# すべてのテストが引き続き通過しなければならない
```

## バグ修正プロセス

### ステップ1: テストでバグを再現
バグを示すテストを書く（テストは失敗するべき）：

```javascript
test('shouldHandleNullEmailGracefully', () => {
  const auth = new UserAuthentication();
  const result = auth.login(null, 'password');
  expect(result.error).toBe('Email is required');
});
```

### ステップ2: 最小限の変更で修正
テストを通過させる最小限の修正を実装：

```javascript
class UserAuthentication {
  login(email, password) {
    if (!email) {
      return { error: 'Email is required' };
    }
    // ... 既存のロジック
  }
}
```

### ステップ3: エッジケーステストを追加
修正中に発見した追加シナリオをカバー：

```javascript
test('shouldHandleEmptyEmailString', () => {
  const auth = new UserAuthentication();
  const result = auth.login('', 'password');
  expect(result.error).toBe('Email is required');
});
```

### ステップ4: 必要に応じてリファクタリング
すべてのテストが通過したら、必要に応じてコード品質を向上させる。

## 意味のあるテストのガイドライン

### テストで検証すべきこと

**動作（コードが何をするか）をテストし、初期化をテストしない：**

❌ **悪いテスト**（初期化のみチェック）:
```rust
#[test]
fn test_new() {
    let profiler = CpuProfiler::new();
    assert_eq!(profiler.frequency, 997);
}
```

✅ **良いテスト**（実際の動作と出力を検証）:
```rust
#[test]
fn test_profiler_captures_function_samples() {
    let profiler = CpuProfiler::new();

    // 実際の動作をテスト
    let report = profiler.profile_workload(|| {
        fibonacci(30);
    }).unwrap();

    // 期待される出力を検証
    assert!(report.contains_function("fibonacci"));
    assert!(report.sample_count() > 0);
}
```

### テスト設計の原則

1. **最小限の意味のある動作から始める**
2. **明確な入力 → 処理 → 出力のフロー**
3. **具体的な期待結果**
4. **明確な失敗理由**

## コミットガイドライン

機能追加とバグ修正には`[BEHAVIORAL]`プレフィックスを使用：

```bash
# 良いコミットメッセージ
[BEHAVIORAL] feat: ユーザー認証システムを追加
[BEHAVIORAL] fix: ログインのnullポインタエラーを解決
[BEHAVIORAL] feat: パスワードバリデーションを実装
```

## 品質保証（必須）

実装後、必ずこれらのコマンドを実行する：

```bash
# 1. リンターを実行
npm run lint     # または適切なlintコマンド
# 続行前にエラーを修正

# 2. フォーマッターを実行
npm run format   # または適切なformatコマンド

# 3. ビルドを実行
npm run build    # または適切なbuildコマンド
# ビルドエラーを修正

# 4. テストを実行
npm test         # または適切なtestコマンド
# すべてのテストが通過しなければならない
```

**重要**: すべての品質チェックが通過するまでタスクは完了しない。

コマンドが不明な場合は、package.jsonまたはREADMEを確認するか、ユーザーに質問する。

## 禁止事項

❌ テストを「後で」書く
❌ テストを書く前に実装する
❌ テストがREDの時にリファクタリング
❌ 複数の機能を同時に実装
❌ テストが通過していない状態でコミット
❌ 初期化のみチェックする意味のないテストを書く

## 必須遵守事項

**重要**: 共通ルールについては`references/must-rules.md`を参照：
- バックグラウンドプロセス管理（ghostを使用）
- 不確実性の処理（仮定しない）
- コミットルール（テストが通過していること）
- エラー処理
- 作業進行（TodoWriteを使用）

## 連携パターン

1. **大規模機能** → 小さなタスクに分割してTDDを適用
2. **リファクタリングが必要** → tidy-firstスキルに委譲
3. **仕様が不明確** → TDD開始前に調査またはAskUserQuestionツールで質問

## リソース

### references/tdd-guidelines.md
以下を含む詳細なTDDガイドライン：
- 高度なテストパターン
- テスト整理戦略
- 一般的なTDDアンチパターン
- 言語別TDDの例
- 統合テストとE2Eテストのアプローチ

### ../shared/references/must-rules.md
すべてのスキルで共有される共通MUSTルール：
- バックグラウンドプロセス管理（ghost）
- 不確実性の処理
- コミット規律
- 作業サイクルガイドライン

開発中の包括的なガイダンスについてはこれらのファイルを参照すること。

---

**覚えておくこと: すべての実装はテスト駆動でなければならない。例外なし。これは交渉の余地がない。**
