---
description: "TDD方法論に従って新機能の実装やバグ修正を行う。RED→GREEN→REFACTORサイクルを厳格に遵守"
argument-hint: "[タスク説明]"
---

# /impl - TDD開発コマンド

このコマンドは、Kent BeckのTDD方法論と高凝集度・低結合度・コロケーションの原則に従って開発を行います。
developingスキルを活用し、RED→GREEN→REFACTORサイクルをテストファーストアプローチで厳格に遵守します。

## 使い方

### 引数付き起動
```
/impl ログインフォームにバリデーションを追加
```

### 引数なし起動（対話的）
```
/impl
```

### コンテキストからの推論
事前の会話でタスクが明確な場合、コンテキストから理解します。

---

## [1/4] タスク準備

### タスク説明の取得

引数からタスク説明を取得します：
- `$1`が存在する場合: そのまま使用
- `$1`が空の場合: ユーザーに質問

```
タスク説明: $1
```

$1が空の場合、以下の質問をしてください：

「どのようなタスクを実装しますか？具体的なタスク説明を入力してください。

例：
- ユーザー認証にバリデーション機能を追加
- APIレスポンスのエラーハンドリングを修正
- 商品一覧のページネーションを実装
」

### 既存ドキュメントの確認

Readツールでdocs/DESIGN.mdとdocs/TODO.mdの存在を確認してください。

**docs/TODO.mdが存在する場合**：
- 内容を読み取り、フェーズ構成を把握
- 各フェーズ内のRED/GREEN/REFACTORタスクを確認

TODO.mdの構造例：
```markdown
### フェーズ1: バージョン計算関数の実装 (semver.rs)

- [ ] [RED] calculate_latest_patch のテスト作成
- [ ] [GREEN] calculate_latest_patch の実装
- [ ] [REFACTOR] calculate_latest_patch のリファクタリング
- [ ] [RED] calculate_latest_minor のテスト作成
- [ ] [GREEN] calculate_latest_minor の実装
- [ ] [REFACTOR] calculate_latest_minor のリファクタリング

### フェーズ2: API統合 (api.rs)

- [ ] [RED] fetch_versions のテスト作成
- [ ] [GREEN] fetch_versions の実装
- [ ] [REFACTOR] fetch_versions のリファクタリング
```

**docs/DESIGN.mdが存在する場合**：
- 内容を読み取り、設計方針を把握
- 実装時の参考として使用

---

## [2/4] フェーズ実行

### TodoWriteでタスク管理

現在のフェーズのタスクをTodoWriteで管理：

```javascript
TodoWrite({
  todos: [
    // 各機能ごとにRED→GREEN→REFACTORサイクルを登録
    { content: "[RED] calculate_latest_patch のテスト作成", activeForm: "テストを作成している", status: "pending" },
    { content: "[GREEN] calculate_latest_patch の実装", activeForm: "実装している", status: "pending" },
    { content: "[REFACTOR] calculate_latest_patch のリファクタリング", activeForm: "リファクタリングしている", status: "pending" },
    { content: "[RED] calculate_latest_minor のテスト作成", activeForm: "テストを作成している", status: "pending" },
    { content: "[GREEN] calculate_latest_minor の実装", activeForm: "実装している", status: "pending" },
    { content: "[REFACTOR] calculate_latest_minor のリファクタリング", activeForm: "リファクタリングしている", status: "pending" }
  ]
})
```

### RED-GREEN-REFACTORサイクルの実行

フェーズ内の各タスクを順番に実行する。

#### REDタスク（テスト作成）

1. TodoWriteで該当タスクを`in_progress`に更新
2. **writing-testsスキル**を使用してテストを作成
3. **サブエージェントでテスト実行**（後述）して**失敗を確認**
4. docs/TODO.mdの該当行を`[x]`に更新
5. TodoWriteで該当タスクを`completed`に更新

#### GREENタスク（実装）

1. TodoWriteで該当タスクを`in_progress`に更新
2. テストを通過する**最小限の実装**を行う
3. **サブエージェントでテスト実行**して**成功を確認**
4. docs/TODO.mdの該当行を`[x]`に更新
5. TodoWriteで該当タスクを`completed`に更新

#### REFACTORタスク（リファクタリング）

1. TodoWriteで該当タスクを`in_progress`に更新
2. **設計原則チェックリスト**に従ってコード品質を改善
3. **サブエージェントでテスト実行**して**成功を確認**
4. docs/TODO.mdの該当行を`[x]`に更新
5. TodoWriteで該当タスクを`completed`に更新

**設計原則チェックリスト**:

| カテゴリ | チェック項目 | 確認内容 |
|---------|------------|---------|
| **SOLID** | 単一責任原則 (SRP) | 1つの関数/モジュールが1つの責務のみを持っているか |
| | 依存性逆転原則 (DIP) | 具象ではなく抽象（インターフェース/トレイト）に依存しているか |
| | インターフェース分離原則 (ISP) | 使わないメソッドへの依存を強制していないか |
| **テスタビリティ** | 依存性注入 | 依存関係が外部から注入可能か（モックしやすいか） |
| | 純粋関数 | 副作用を分離し、可能な限り純粋関数にしているか |
| | グローバル状態 | グローバル変数や静的状態に依存していないか |
| **構造** | 高凝集度 | 関連する機能が同じモジュールにまとまっているか |
| | 低結合度 | モジュール間の依存が最小限か |
| | 重複排除 (DRY) | 同じロジックが複数箇所に存在していないか |
| **シンプルさ** | YAGNI | 現時点で不要な抽象化や機能を追加していないか |
| | KISS | 必要以上に複雑な実装になっていないか |
| **境界** | 公開API最小化 | 公開する関数/型は必要最小限か |
| | モジュール境界 | 責務ごとに適切にモジュール分割されているか |

**リファクタリングの優先順位**:
1. テスタビリティの確保（DI、純粋関数化）
2. 単一責任の徹底
3. 重複の排除
4. 命名の改善

### テスト実行（サブエージェント）

トークン消費を抑えるため、テスト実行はTaskツールでサブエージェントに委譲する。

```javascript
Task({
  description: "テスト実行",
  prompt: `プロジェクトのテストを実行し、結果を報告してください。

テストコマンド: [プロジェクトに応じたコマンド]

報告形式:
- 全テスト成功の場合: "SUCCESS: X tests passed"
- 失敗がある場合: "FAILED: 以下のテストが失敗" + 失敗したテスト名とエラーメッセージのみ

注意: 成功したテストの詳細は報告不要。失敗したテストの情報のみ返すこと。`,
  subagent_type: "general-purpose",
  model: "haiku"
})
```

**サブエージェントの報告例**:
```
# 成功時
SUCCESS: 15 tests passed

# 失敗時
FAILED: 以下のテストが失敗
- test_calculate_latest_patch: expected "1.2.5" but got "1.2.3"
- test_calculate_latest_minor: assertion failed at line 42
```

**実装のルール**：
- 現在のテストを通過するために**必要最小限**のコードのみ書く
- 将来の要件を先取りしない
- 過度な抽象化を避ける

---

## [3/4] フェーズ承認

フェーズ内のすべてのタスク（RED/GREEN/REFACTOR）が完了したら、以下の2ステップを実行する。

### ステップ1: セルフレビュー（サブエージェント）

トークン消費を抑えるため、セルフレビューはTaskツールでサブエージェントに委譲する。

```javascript
Task({
  description: "セルフレビュー実行",
  prompt: `このフェーズで変更されたファイルに対してコードレビューを実行してください。

レビュー観点:
1. TDD/テスト品質 - テストの存在、カバレッジ、テスト品質
2. コード品質 - 可読性、命名、複雑度、重複、凝集度、結合度
3. セキュリティ - 脆弱性、入力検証
4. アーキテクチャ - 設計パターン、依存関係、責務分離
5. プロジェクトルール - CLAUDE.md, DESIGN.md準拠

報告形式:
- 問題なしの場合: "PASSED: レビュー通過"
- 問題ありの場合: "ISSUES FOUND:" + Critical/Warningの問題のみリスト

注意: Infoレベルの軽微な指摘は報告不要。Critical/Warningのみ返すこと。`,
  subagent_type: "Explore",
  model: "opus"
})
```

**サブエージェントの報告例**:
```
# 問題なし
PASSED: レビュー通過

# 問題あり
ISSUES FOUND:
- [Critical] src/auth.rs:45 - ハードコードされたAPIキー
- [Warning] src/user.rs:120 - 関数が60行を超えている（分割推奨）
```

**レビュー結果に問題がある場合**：
1. 問題を修正
2. サブエージェントでテスト実行して成功を確認
3. 再度セルフレビューを実行
4. **問題がなくなるまで繰り返す**

**レビューに問題がない場合**：
- ステップ2（品質チェック）に進む

### ステップ2: 品質チェック

セルフレビュー通過後、品質チェックを実行：

```bash
# プロジェクトに応じたコマンドを実行
npm run lint     # または cargo clippy, go vet など
npm run format   # または cargo fmt, gofmt など
npm run build    # または cargo build, go build など
npm test         # または cargo test, go test など
```

**品質チェック失敗時**：
1. 問題を修正
2. 再度品質チェックを実行
3. 通過するまで繰り返す

**両ステップ通過後**：
- フェーズ完了確認に進む

### フェーズ完了確認

セルフレビュー（/review）と品質チェックの両方が通過したら、AskUserQuestionツールで承認を求める：

```javascript
AskUserQuestion({
  questions: [
    {
      question: "フェーズ1が完了しました。\n\n実装内容:\n- calculate_latest_patch\n- calculate_latest_minor\n- calculate_latest_major\n\n作成/変更ファイル:\n- src/semver.rs\n- src/semver_test.rs\n\nテスト結果: X tests passed\n\n次のフェーズに進みますか？",
      header: "フェーズ完了",
      options: [
        { label: "承認", description: "次のフェーズに進む" },
      ],
      multiSelect: false
    }
  ]
})
```

**「承認」を選択された場合**：
1. 次のフェーズがあれば [2/4] フェーズ実行に戻る
2. すべてのフェーズが完了していれば [4/4] 完了処理へ

**「Other」を選択された場合**：
1. ユーザーの指示に従って修正
2. 修正後、再度セルフレビュー → 品質チェック → フェーズ完了確認

---

## [4/4] 完了処理

### 完了サマリー

```
✓ 開発が完了しました

実装内容:
- [実装した機能/修正のリスト]

作成/変更したファイル:
- [ファイルパスのリスト]

テスト結果:
- [テスト数] tests passed

完了したフェーズ:
- [x] フェーズ1: バージョン計算関数の実装
- [x] フェーズ2: API統合
```

### 次のアクション確認

```javascript
AskUserQuestion({
  questions: [
    {
      question: "すべてのフェーズが完了しました。次のアクションを選択してください。",
      header: "次のアクション",
      options: [
        { label: "コミット", description: "変更をコミットする" },
        { label: "完了", description: "開発を終了" }
      ],
      multiSelect: false
    }
  ]
})
```

**「コミット」を選択された場合**：
- committerスキルを使用してコミットを作成

---

## 重要な注意事項

### TDD絶対ルール

1. **テストなしにコードを書かない** - 例外なし
2. **RED→GREEN→REFACTORサイクルに従う** - 厳格に遵守
3. **最小限の実装** - 現在のテストを通過するコードのみ書く
4. **グリーンの時のみリファクタリング** - テストが通過していなければリファクタリングしない

### フェーズ管理のルール

1. **フェーズ内タスクは順番に実行** - 飛ばさない
2. **各タスク完了時にTODO.mdを更新** - 進捗を可視化
3. **フェーズ完了時に承認を得る** - 勝手に次に進まない
4. **品質チェックはフェーズ承認後** - 承認前は実行しない

### アンチパターン（避けるべきこと）

❌ テストを「後で」書く
❌ テストを書く前に実装する
❌ テストがREDの時にリファクタリング
❌ 複数のフェーズを同時に実装
❌ 承認なしで次のフェーズに進む
❌ TODO.mdの更新を忘れる

### コミットガイドライン

```bash
# 構造変更（リファクタリング）
[STRUCTURAL] refactor: コンポーネントをfeatures/ディレクトリに移動

# 動作変更（機能追加・バグ修正）
[BEHAVIORAL] feat: ユーザー認証機能を追加
[BEHAVIORAL] fix: ログインエラーハンドリングを修正
```

### エラーハンドリング

- テスト実行エラー時は明確なエラーメッセージを表示
- ユーザーにリトライオプションを提供
- 品質チェック失敗時は修正を促す
