---
name: workflow-spec
description: "対話的計画コマンド。requirements スキルの設計手順と implementation-planning-tasks を統合実行して DESIGN.md (概要)、DESIGN_DETAIL.md (詳細)、TODO.md を生成"
argument-hint: "[タスク説明]"
allowed-tools: Skill, AskUserQuestion, Read
---

# /spec - 対話的計画コマンド

このコマンドは、Claude Code組み込みのplan modeと同等の機能を提供します。
ユーザーのタスク説明から自動的に以下の 3 ファイルを生成します:

- **DESIGN.md (概要設計)**: 目的・スコープ・主要コンポーネント・前提・技術選定・非機能目標
- **DESIGN_DETAIL.md (詳細設計)**: API・スキーマ・シーケンス・エラー実装・検証コマンド・実装ガイド
- **TODO.md (タスクリスト)**: TDD 準拠の実装タスク (DESIGN_DETAIL.md から生成)

requirements スキルの設計手順 (analyzing-requirements / interview) と implementation-planning-tasks スキルを統合実行し、対話的に計画を洗練します。

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

## [1/6] タスク説明の準備

### タスク説明の取得

引数からタスク説明を取得します：
- `$ARGUMENTS`が存在する場合: そのまま使用
- `$ARGUMENTS`が空の場合: ユーザーに質問

```
タスク説明: $ARGUMENTS
```

$ARGUMENTSが空の場合、以下の質問をしてください：

「どのようなタスクの計画を作成しますか？具体的なタスク説明を入力してください。

例：
- ユーザー認証システムにOAuth2対応を追加
- CLIツールにログ機能を実装
- 既存のAPIをGraphQLに移行
」

### 既存ドキュメントの確認

Read ツールで以下の存在を確認してください:
- `docs/DESIGN.md`
- `docs/DESIGN_DETAIL.md`
- `docs/TODO.md`

既存ファイルが存在する場合、AskUserQuestionツールで確認してください：

```javascript
AskUserQuestion({
  questions: [
    {
      question: "既存の計画ドキュメントが見つかりました：\n- docs/DESIGN.md\n- docs/DESIGN_DETAIL.md\n- docs/TODO.md\n\nどのように進めますか？",
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
- 既存の DESIGN.md / DESIGN_DETAIL.md / TODO.md を Read ツールで読み取る
- 内容を analyzing-requirements と implementation-planning-tasks スキルに渡す
- 既存プロジェクトに DESIGN.md だけあって DESIGN_DETAIL.md が無い場合、planning-tasks の詳細抽出フォールバックが起動する

**「キャンセル」を選択された場合**：
- コマンドを終了

---

## [2/6] DESIGN.md / DESIGN_DETAIL.md 生成（analyzing-requirements）

`skills/requirements/references/analyzing-requirements.md` を Read し、その手順に従って DESIGN.md (概要) と DESIGN_DETAIL.md (詳細) の 2 ファイルを生成します。

### 手順実行時の入力

以下の情報を前提として手順を実行してください：

```
タスク説明: [取得したタスク説明]
更新モード: [新規/更新]
既存 DESIGN.md: [存在する場合は内容を含める]
既存 DESIGN_DETAIL.md: [存在する場合は内容を含める]
```

### 生成確認

スキル実行後、`docs/DESIGN.md` と `docs/DESIGN_DETAIL.md` の存在と内容を確認してください。

表示する主要セクション:
- DESIGN.md: システム概要 / 主要コンポーネント / 技術選定 / 非機能目標 / ゴール
- DESIGN_DETAIL.md: API 設計 / データスキーマ / シーケンス / エラー戦略具体

### ユーザー承認

AskUserQuestion ツールを使用してユーザー承認を取得してください：

```javascript
AskUserQuestion({
  questions: [
    {
      question: "DESIGN.md (概要) と DESIGN_DETAIL.md (詳細) が生成されました。内容を確認してください。\n\n生成場所:\n- docs/DESIGN.md\n- docs/DESIGN_DETAIL.md\n\nこのまま次のフェーズ（インタビューによる深掘り）に進めてよろしいですか？",
      header: "設計書承認",
      options: [
        {
          label: "承認",
          description: "次のフェーズ（インタビュー）に進む"
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
- 次のフェーズ（インタビュー）に進む

**「却下」を選択された場合**：
- コマンドを終了
- 「計画を中断しました。再度実行する場合は /spec を使用してください」と表示

**ユーザーが修正内容を入力した場合（Other選択）**：
1. 入力された修正内容を反映し、概要/詳細の射程に応じて DESIGN.md または DESIGN_DETAIL.md を更新
2. 再度ユーザー承認を取得（このセクションに戻る）
3. 承認されるまで繰り返す

---

## [3/6] 設計書の深掘り（interview）

`skills/requirements/references/interview.md` を Read し、その手順に従って DESIGN.md / DESIGN_DETAIL.md をブラッシュアップします (対象は `docs/DESIGN.md`。手順内で DESIGN_DETAIL.md も併せて読み込む)。

interview 手順は以下を実行します：
- DESIGN.md と DESIGN_DETAIL.md の両方を読み込み
- 技術実装、UI/UX、懸念点、トレードオフについて深掘りインタビュー
- 質問の射程に応じて DESIGN.md (概要) または DESIGN_DETAIL.md (詳細) に追記・更新

### インタビューの繰り返し

インタビュー完了後、以下の条件を満たすまで繰り返しインタビューを実施する：
- 質問がなくなった場合
- ユーザーが「インタビュー終了」と明示した場合

繰り返しごとに DESIGN.md / DESIGN_DETAIL.md を更新し、より詳細な仕様を蓄積していく。

すべてのインタビューが完了したら、次のフェーズ（検証手順の確認と補完）に進みます。

---

## [4/6] 検証手順の確認と補完

ゴール (DESIGN.md) と検証手順 (DESIGN_DETAIL.md) を精査し、不足を補完する。

### 情報収集

以下のソースから検証に関する情報を収集する：

1. **DESIGN.md のゴール**: 「ゴール」セクションを読み取り、観測可能性・検証可能性を評価
2. **DESIGN_DETAIL.md の検証手順**: 「検証手順」セクションを読み取り、実行コマンド・操作手順の充実度を評価
3. **既存プロジェクトの検証手段**: テストファイル、CI 設定、Makefile、package.json の scripts を検索
4. **テスト戦略との整合**: DESIGN.md の「テスト戦略 (方針)」と DESIGN_DETAIL.md の「テスト戦略 (具体)」が矛盾していないか

### 充実度の評価

以下の観点で検証手順の充実度を評価する：

- ゴールが具体的かつ検証可能か
- 手動検証の手順が操作レベルで記述されているか
- 自動検証（テストコマンド等）が明記されているか
- 完了条件チェックリストがゴールを網羅しているか

### 不足の補完

不足がある場合、AskUserQuestionツールで確認する：

```javascript
AskUserQuestion({
  questions: [
    {
      question: "検証手順について確認させてください。\n\n現在のゴール:\n[DESIGN.mdから抽出したゴール一覧]\n\n以下の点が不明です:\n- [不明点1]\n- [不明点2]\n\nどのように検証しますか？",
      header: "検証手順",
      options: [
        { label: "選択肢1", description: "..." },
        { label: "選択肢2", description: "..." }
      ],
      multiSelect: false
    }
  ]
})
```

具体的な質問例：
- 「この機能の動作確認はどの環境で行いますか？（ローカル / ステージング / 本番）」
- 「パフォーマンス要件の検証方法は？（負荷テストツール / 手動計測 / APM）」
- 「E2Eテストは必要ですか？必要な場合、どのシナリオをカバーしますか？」

### 設計書更新

収集した情報を以下に振り分けて反映する:
- ゴール (観測可能・検証可能な目標) → DESIGN.md の「ゴール」セクション
- 検証手順の具体 (実行コマンド・操作手順・閾値) → DESIGN_DETAIL.md の「検証手順」セクション

### ユーザー承認

AskUserQuestionツールで確認：

```javascript
AskUserQuestion({
  questions: [
    {
      question: "検証手順を更新しました。確認してください。次のフェーズ（TODO.md生成）に進めてよろしいですか？",
      header: "検証手順承認",
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

**「承認」を選択された場合**：
- 次のフェーズ（TODO.md生成）に進む

**「却下」を選択された場合**：
- コマンドを終了
- 「計画を中断しました。再度実行する場合は /spec を使用してください」と表示

**ユーザーが修正内容を入力した場合（Other選択）**：
1. 入力された修正内容を反映して、ゴールは DESIGN.md、検証手順は DESIGN_DETAIL.md に振り分けて更新
2. 再度ユーザー承認を取得（このセクションに戻る）
3. 承認されるまで繰り返す

---

## [5/6] TODO.md 生成（implementation-planning-tasks）

implementation-planning-tasks スキルを実行して TODO.md を生成します。**入力は DESIGN_DETAIL.md** です。

### スキル実行

以下の情報を implementation-planning-tasks スキルに渡してください：

```
詳細設計書: docs/DESIGN_DETAIL.md
概要設計書 (整合確認用): docs/DESIGN.md
更新モード: [新規/更新]
既存TODO.md: [存在する場合は内容を含める]
```

Skill ツールを使用して implementation-planning-tasks スキルを実行してください。

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

## [6/6] 完了と実装開始

### サマリー表示

以下の情報を表示してください：

```
✓ 計画が完成しました

生成されたファイル:
- docs/DESIGN.md         (概要設計)
- docs/DESIGN_DETAIL.md  (詳細設計)
- docs/TODO.md           (タスクリスト)
```

### 変更履歴の記録（更新モードの場合）

更新モードで実行された場合、両ファイルの先頭に変更履歴コメントを追記してください：

```markdown
<!-- 変更履歴
[YYYY-MM-DD]: [変更内容の要約]
-->
```

### 実装方式の選択

TODO.md 承認後、残りフェーズの実装方式を AskUserQuestion で確認:

```javascript
AskUserQuestion({
  questions: [{
    question: "残りフェーズの実装方式を選んでください",
    header: "実装方式",
    options: [
      {
        label: "autopilot (自律)",
        description: "workflow-autopilot で全フェーズを最後まで自律実装。架構違反は3回まで自動修正、設計乖離はP1/P2を自動更新、P3で停止"
      },
      {
        label: "developing (対話)",
        description: "implementation-developing で 1 フェーズずつ。各フェーズ完了で人間が確認"
      },
      {
        label: "ここで終了",
        description: "実装は後で /workflow-autopilot または /implementation-developing を手動起動"
      }
    ],
    multiSelect: false
  }]
})
```

選択別の処理:

- **autopilot (自律)** → `workflow-autopilot` スキルを Skill ツールで実行 (docs ディレクトリパスを引数で渡す)
- **developing (対話)** → `implementation-developing` スキルを Skill ツールで実行
- **ここで終了** → 「計画は完成しました。実装を開始する場合は `/workflow-autopilot` または `/implementation-developing` を起動してください」と表示して終了

---

## 重要な注意事項

### 依存関係
- requirements スキルの references (analyzing-requirements.md / interview.md) が必須 (DESIGN.md + DESIGN_DETAIL.md 生成と深掘り)
- implementation-planning-tasks スキルが必須 (DESIGN_DETAIL.md → TODO.md 生成、DESIGN_DETAIL 不在時は対話的フォールバック)
- これらが正しくインストールされていることを確認してください

### エラーハンドリング
- スキル実行エラー時は明確なエラーメッセージを表示してください
- ユーザーにリトライオプションを提供してください
- 最大再試行回数: 各スキル3回まで

### ドキュメント検索（context7）

ライブラリやフレームワークのドキュメントを検索する際は、context7 MCPサーバーを使用する：

1. まず`resolve-library-id`を呼び出してContext7互換のライブラリIDを取得
2. 次に解決されたIDで`get-library-docs`を呼び出す
3. 例外: ユーザーが明示的に`/org/project`形式でライブラリIDを提供した場合

**適切な使用例:**
- 「context7を使用してReactドキュメントを検索します」
- 「context7を使用して最新のNext.js APIドキュメントを見つけます」

**禁止:**
- context7にある公式ドキュメントをWeb検索で探す
- ドキュメントを確認せずにAPIメソッドを推測する
- 記憶にある古いドキュメントを使用する

### 参照ルール
計画ドキュメントは以下のルールを参照します：
- TDDルール: `rules/core/tdd.md`
- コミットルール: `rules/core/commit.md`
- 設計原則: `rules/core/design.md`

### 更新モードの動作
更新モードが選択された場合：
- 既存ドキュメントを読み取ります
- 差分のみを更新します
- 変更履歴をコメントで記録します
- 既存の承認済み内容は保持します
