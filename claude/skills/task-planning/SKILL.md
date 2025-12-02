---
name: task-planning
description: 承認済みの設計書（DESIGN.md）からTDD準拠のTODO.mdを作成する。requirements-analysisスキルで設計が完了・承認された後に使用する。developmentスキルで実装できる形式のタスクリストを生成する。
---

# タスク計画

## 概要

承認済みの設計書（DESIGN.md）を読み込み、TDD（テスト駆動開発）に準拠したTODO.mdを作成する。生成されるTODO.mdはdevelopmentスキルで直接使用できる形式となる。

**前提条件**: requirements-analysisスキルで作成されたDESIGN.mdが存在し、ユーザーに承認されていること。

## コアワークフロー

### ステップ1: 設計書の確認

DESIGN.mdを読み込み、以下を確認する：

```javascript
Read(file_path="docs/DESIGN.md")
```

確認事項：
- システム概要とアーキテクチャ
- コンポーネント構成
- インターフェース定義
- データ設計

### ステップ2: タスク分解

設計書から実装タスクを抽出し、TDDサイクルに従って分解する：

#### 分解の原則

1. **機能単位で分割**: 1つの機能 = 1つのTDDサイクル
2. **依存関係を考慮**: 基盤 → コア機能 → 拡張機能の順
3. **テストファースト**: 各機能でRED→GREEN→REFACTORを明示

#### タスクの粒度

- 1タスク = 1-4時間で完了可能
- テスト1つ + 実装1つ = 1セット
- リファクタリングは独立したタスク

### ステップ3: TODO.md生成

以下の形式でTODO.mdを生成する：

```markdown
# TODO: [プロジェクト名]

作成日: [日付]
生成元: task-planning
設計書: docs/DESIGN.md

## 概要

[設計書から抽出した目的と範囲]

## 実装タスク

### フェーズ1: 基盤構築

- [ ] プロジェクト構造のセットアップ
- [ ] 依存パッケージのインストール
- [ ] 開発環境の設定

### フェーズ2: [機能名A] の実装

- [ ] [RED] [機能A]の動作テストを作成
- [ ] [GREEN] テストを通過させる最小限の実装
- [ ] [REFACTOR] コード品質の改善

### フェーズ3: [機能名B] の実装

- [ ] [RED] [機能B]の動作テストを作成
- [ ] [GREEN] テストを通過させる最小限の実装
- [ ] [REFACTOR] コード品質の改善

### フェーズN: 品質保証

- [ ] [STRUCTURAL] コード整理（動作変更なし）
- [ ] 全テスト実行と確認
- [ ] lint/format/buildの確認

## 実装ノート

### MUSTルール遵守事項
- TDD: RED → GREEN → REFACTOR サイクルを厳守
- Tidy First: 構造変更と動作変更を分離
- コミット: [BEHAVIORAL] または [STRUCTURAL] プレフィックス必須

### 参照ドキュメント
- 設計書: docs/DESIGN.md
- MUSTルール: 参照 shared/references/must-rules.md
```

### ステップ4: ファイル出力

TODO.mdをdocsディレクトリに出力する：

```javascript
Write(
    file_path="docs/TODO.md",
    content=todoContent
)
```

### ステップ5: 確認と次のステップ

生成完了後、ユーザーに確認する：

```javascript
AskUserQuestion({
  questions: [
    {
      question: "TODO.mdを確認しました。このタスクリストで実装を開始しますか？",
      header: "実装開始",
      options: [
        { label: "開始する", description: "developmentスキルで実装を開始" },
        { label: "修正が必要", description: "TODO.mdの修正点を指摘する" }
      ],
      multiSelect: false
    }
  ]
})
```

## タスク分解のパターン

### パターン1: CRUD機能

```markdown
### [エンティティ名] CRUD実装

- [ ] [RED] Create機能のテスト作成
- [ ] [GREEN] Create機能の実装
- [ ] [RED] Read機能のテスト作成
- [ ] [GREEN] Read機能の実装
- [ ] [RED] Update機能のテスト作成
- [ ] [GREEN] Update機能の実装
- [ ] [RED] Delete機能のテスト作成
- [ ] [GREEN] Delete機能の実装
- [ ] [REFACTOR] CRUD処理の共通化
```

### パターン2: API実装

```markdown
### [エンドポイント名] API実装

- [ ] [RED] 正常系レスポンスのテスト作成
- [ ] [GREEN] 正常系の実装
- [ ] [RED] バリデーションエラーのテスト作成
- [ ] [GREEN] バリデーションの実装
- [ ] [RED] エラーハンドリングのテスト作成
- [ ] [GREEN] エラーハンドリングの実装
- [ ] [REFACTOR] レスポンス形式の統一
```

### パターン3: UIコンポーネント

```markdown
### [コンポーネント名] 実装

- [ ] [RED] レンダリングテスト作成
- [ ] [GREEN] 基本UIの実装
- [ ] [RED] インタラクションテスト作成
- [ ] [GREEN] イベントハンドラの実装
- [ ] [RED] エッジケーステスト作成
- [ ] [GREEN] エッジケース対応
- [ ] [REFACTOR] スタイルとロジックの分離
```

## 品質チェックリスト

TODO.md生成前に確認：
- [ ] すべての設計項目がタスクに反映されている
- [ ] 各タスクにTDDフェーズ（RED/GREEN/REFACTOR）が明示されている
- [ ] タスクの依存関係が順序に反映されている
- [ ] 各タスクの粒度が適切（1-4時間）
- [ ] MUSTルール遵守事項が記載されている

## リソース

### ../shared/references/must-rules.md
すべてのスキルで共有される共通MUSTルール：
- TDD方法論の詳細
- Tidy First原則
- コミット規律

タスク分解時はこのファイルを参照してMUSTルール準拠を確認すること。
