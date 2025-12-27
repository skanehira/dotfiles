---
description: "対話的計画コマンド。analyzing-requirementsとplanning-tasksスキルを統合実行してDESIGN.mdとTODO.mdを生成"
argument-hint: "[タスク説明]"
allowed-tools: ["Skill", "AskUserQuestion", "Read"]
---

# /spec - 対話的計画コマンド

このコマンドは、Claude Code組み込みのplan modeと同等の機能を提供します。
ユーザーのタスク説明から自動的にDESIGN.md（設計ドキュメント）とTODO.md（タスクリスト）を生成します。

analyzing-requirementsとplanning-tasksスキルを統合実行し、対話的に計画を洗練します。

## 使い方

### 引数付き起動
```
/spec ユーザー認証にOAuth2を追加
```

### 引数なし起動（対話的）
```
/spec
```

### コンテキストからの推論
事前の会話でタスクが明確な場合、コンテキストから理解します。

---

## [1/4] タスク説明の準備

### タスク説明の取得

引数からタスク説明を取得します：
- `$1`が存在する場合: そのまま使用
- `$1`が空の場合: ユーザーに質問

```
タスク説明: $1
```

$1が空の場合、以下の質問をしてください：

「どのようなタスクの計画を作成しますか？具体的なタスク説明を入力してください。

例：
- ユーザー認証システムにOAuth2対応を追加
- CLIツールにログ機能を実装
- 既存のAPIをGraphQLに移行
」

### 既存ドキュメントの確認

Readツールでdocs/DESIGN.mdとdocs/TODO.mdの存在を確認してください。

既存ファイルが存在する場合、AskUserQuestionツールで確認してください：

```javascript
AskUserQuestion({
  questions: [
    {
      question: "既存の計画ドキュメントが見つかりました：\n- docs/DESIGN.md\n- docs/TODO.md\n\nどのように進めますか？",
      header: "既存ドキュメント",
      options: [
        {
          label: "新規作成",
          description: "既存のドキュメントを上書きして新規作成"
        },
        {
          label: "更新",
          description: "既存のドキュメントを読み取って差分更新"
        },
        {
          label: "キャンセル",
          description: "コマンドを終了"
        }
      ],
      multiSelect: false
    }
  ]
})
```

**「更新」を選択された場合**：
- 既存のdocs/DESIGN.mdとdocs/TODO.mdをReadツールで読み取る
- 内容をanalyzing-requirementsとplanning-tasksスキルに渡す

**「キャンセル」を選択された場合**：
- コマンドを終了

---

## [2/4] DESIGN.md生成（analyzing-requirements）

analyzing-requirementsスキルを実行してDESIGN.mdを生成します。

### スキル実行

以下の情報をanalyzing-requirementsスキルに渡してください：

```
タスク説明: [取得したタスク説明]
更新モード: [新規/更新]
既存DESIGN.md: [存在する場合は内容を含める]
```

Skillツールを使用してanalyzing-requirementsスキルを実行してください。

### 生成確認

スキル実行後、docs/DESIGN.mdの存在と内容を確認してください。

生成されたDESIGN.mdの主要セクションを表示してください：
- システム概要
- 機能要件（必須機能のリスト）
- アーキテクチャ設計（システム構成図）

### ユーザー承認

AskUserQuestionツールを使用してユーザー承認を取得してください：

```javascript
AskUserQuestion({
  questions: [
    {
      question: "DESIGN.mdが生成されました。内容を確認してください。\n\n生成場所: docs/DESIGN.md\n\nこのまま次のフェーズ（TODO.md生成）に進めてよろしいですか？",
      header: "DESIGN.md承認",
      options: [
        {
          label: "承認",
          description: "次のフェーズ（TODO.md生成）に進む"
        },
        {
          label: "却下",
          description: "コマンドを終了"
        }
      ],
      multiSelect: false
    }
  ]
})
```

### 承認フロー

**「承認」を選択された場合**：
- 次のフェーズ（TODO.md生成）に進む

**「却下」を選択された場合**：
- コマンドを終了
- 「計画を中断しました。再度実行する場合は /spec を使用してください」と表示

**ユーザーが修正内容を入力した場合（Other選択）**：
1. 入力された修正内容を反映してDESIGN.mdを更新
2. 再度ユーザー承認を取得（このセクションに戻る）
3. 承認されるまで繰り返す

---

## [3/4] TODO.md生成（planning-tasks）

planning-tasksスキルを実行してTODO.mdを生成します。

### スキル実行

以下の情報をplanning-tasksスキルに渡してください：

```
DESIGN.mdの場所: docs/DESIGN.md
更新モード: [新規/更新]
既存TODO.md: [存在する場合は内容を含める]
```

Skillツールを使用してplanning-tasksスキルを実行してください。

### 生成確認

スキル実行後、docs/TODO.mdの存在と内容を確認してください。

生成されたTODO.mdの主要セクションを表示してください：
- タスク概要
- RED-GREEN-REFACTORサイクルのリスト（最初の2-3サイクル）

### ユーザー承認

AskUserQuestionツールを使用してユーザー承認を取得してください：

```javascript
AskUserQuestion({
  questions: [
    {
      question: "TODO.mdが生成されました。内容を確認してください。\n\n生成場所: docs/TODO.md\n\nこのタスクリストで問題ありませんか？",
      header: "TODO.md承認",
      options: [
        {
          label: "承認",
          description: "このタスクリストで完了"
        },
        {
          label: "却下",
          description: "コマンドを終了"
        }
      ],
      multiSelect: false
    }
  ]
})
```

### 承認フロー

**「承認」を選択された場合**：
- 次のフェーズ（完了と実装開始）に進む

**「却下」を選択された場合**：
- コマンドを終了
- 「計画を中断しました。再度実行する場合は /spec を使用してください」と表示

**ユーザーが修正内容を入力した場合（Other選択）**：
1. 入力された修正内容を反映してTODO.mdを更新
2. 再度ユーザー承認を取得（このセクションに戻る）
3. 承認されるまで繰り返す（最大3回）
4. 3回目でも承認されない場合、「直接 docs/TODO.md を編集することをお勧めします」と提案

---

## [4/4] 完了と実装開始

### サマリー表示

以下の情報を表示してください：

```
✓ 計画が完成しました

生成されたファイル:
- docs/DESIGN.md  (設計ドキュメント)
- docs/TODO.md    (タスクリスト)
```

### 変更履歴の記録（更新モードの場合）

更新モードで実行された場合、両ファイルの先頭に変更履歴コメントを追記してください：

```markdown
<!-- 変更履歴
[YYYY-MM-DD]: [変更内容の要約]
-->
```

### 実装開始

TODO.md承認後、自動的に /impl コマンドを実行して実装を開始します。

```javascript
Skill({
  skill: "impl"
})
```

---

## 重要な注意事項

### 依存関係
- analyzing-requirementsスキルが必須です
- planning-tasksスキルが必須です
- 両スキルが正しくインストールされていることを確認してください

### エラーハンドリング
- スキル実行エラー時は明確なエラーメッセージを表示してください
- ユーザーにリトライオプションを提供してください
- 最大再試行回数: 各スキル3回まで

### MUSTルール準拠
計画ドキュメントは以下のルールに準拠します：
- TDD準拠: すべてのタスクはテストファーストで実装
- Tidy First: 構造変更と機能変更を分離
- 不確実性対処: 仮定を立てず、不明点は質問
- コミット規律: テスト合格後のみコミット

### 更新モードの動作
更新モードが選択された場合：
- 既存ドキュメントを読み取ります
- 差分のみを更新します
- 変更履歴をコメントで記録します
- 既存の承認済み内容は保持します
