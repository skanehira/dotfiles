# TODO.md 生成 (dev-spec フェーズ 10)

## 目次

- [参照ルール（必須）](#参照ルール必須)
- [概要](#概要)
- [コアワークフロー](#コアワークフロー)
  - [ステップ1: 設計書の確認](#ステップ1-設計書の確認)
  - [ステップ2: タスク分解](#ステップ2-タスク分解)
  - [ステップ3: TODO.md生成](#ステップ3-todomd生成)
  - [ステップ4: ファイル出力](#ステップ4-ファイル出力)
  - [ステップ5: セルフレビュー（ぬけもれ解消まで繰り返し）](#ステップ5-セルフレビューぬけもれ解消まで繰り返し)
  - [ステップ6: 完了確認](#ステップ6-完了確認)
- [タスク分解のパターン](#タスク分解のパターン)
  - [パターン1: CRUD機能](#パターン1-crud機能)
  - [パターン2: API実装](#パターン2-api実装)
  - [パターン3: UIコンポーネント](#パターン3-uiコンポーネント)

承認済みの詳細設計書 (DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md) から TDD 準拠の TODO.md を作成する手順書。詳細設計が無い・旧形式 (単一 DESIGN_DETAIL.md) の場合は対話的にフォールバックを実行する。生成される TODO.md は実装ループ (`/dev-impl`) で直接使用できる形式となる。

## 参照ルール（必須）

**Claude指示: タスク分解を開始する前に、必ず以下のルールファイルをReadツールで読み込んでください。**

- TDDルール: `rules/core/tdd.md`
- 設計原則: `rules/core/design.md`
- コミットルール: `rules/core/commit.md`

## 概要

承認済みの詳細設計書（`docs/DESIGN_DETAIL_APP.md` + `docs/DESIGN_DETAIL_INFRA.md`）を読み込み、TDD（テスト駆動開発）に準拠した TODO.md を作成する。生成される TODO.md は実装ループ (`/dev-impl`) で直接使用できる形式となる。

**前提条件**: フェーズ 7 (analyzing-requirements) で作成された DESIGN.md / DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md が存在し、ユーザーに承認されていること。

詳細設計 2 ファイルが無い既存プロジェクトの場合は、ステップ 1 のフォールバックで対話的に生成・移行を行う。

## コアワークフロー

### ステップ1: 設計書の確認

詳細設計 2 ファイルと DESIGN.md (概要との整合確認用) を読み込む：

```javascript
Read(file_path="docs/DESIGN_DETAIL_APP.md")
Read(file_path="docs/DESIGN_DETAIL_INFRA.md")
Read(file_path="docs/DESIGN.md")
```

#### フォールバック A: 旧形式の単一 DESIGN_DETAIL.md がある場合

`docs/DESIGN_DETAIL.md` (旧形式) が存在し APP / INFRA が無い場合、AskUserQuestion で確認:

```javascript
AskUserQuestion({
  questions: [{
    question: "旧形式の docs/DESIGN_DETAIL.md が見つかりました。DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md に分割して進めますか？",
    header: "詳細設計の移行",
    options: [
      { label: "分割して進める", description: "境界基準 (analyzing-requirements.md 参照) で APP / INFRA に振り分けて 2 ファイルを生成し、旧ファイルを削除してからタスク分解へ進む" },
      { label: "中止", description: "ユーザーが手動で整えてから再実行" }
    ],
    multiSelect: false
  }]
})
```

「分割して進める」の場合: 境界基準 (変更に IaC・クラウドコンソール操作・環境設定変更が要るか) で各セクションを振り分けて 2 ファイルに書き出し、旧 `docs/DESIGN_DETAIL.md` を削除し、DESIGN.md 内のリンクを更新する。ユーザーに分割後のファイルを確認してもらい承認を取得後、ステップ 2 へ進む。

#### フォールバック B: DESIGN.md しかない場合

既存プロジェクトで DESIGN.md だけある場合、AskUserQuestion で確認:

```javascript
AskUserQuestion({
  questions: [{
    question: "詳細設計 (DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md) が見つかりません。docs/DESIGN.md から詳細部分 (API・スキーマ・エラーパス・実装ガイド・CI/CD 等) を抽出して生成しますか？",
    header: "詳細設計の抽出",
    options: [
      { label: "抽出して進める", description: "DESIGN.md から詳細を切り出して APP / INFRA の 2 ファイルを生成し、全ファイルを更新後にタスク分解へ進む" },
      { label: "中止", description: "ユーザーが手動で詳細設計を整えてから再実行" }
    ],
    multiSelect: false
  }]
})
```

「抽出して進める」を選択された場合:

1. DESIGN.md から「API 設計」「データスキーマ詳細」「データフロー詳細」「エラー戦略 (具体)」「テスト戦略 (具体)」「実装ガイド」に該当する内容を `docs/DESIGN_DETAIL_APP.md` に、「リソース定義」「CI/CD」「監視」「シークレット管理」に該当する内容を `docs/DESIGN_DETAIL_INFRA.md` に抽出 (振り分けは境界基準に従う)
2. DESIGN.md からは詳細部分を削除し、概要 (共通 / アプリ概要 / インフラ概要) のみ残す
3. DESIGN.md の該当箇所には `詳細は [DESIGN_DETAIL_APP.md](./DESIGN_DETAIL_APP.md#section) を参照` 等のリンクを追加
4. ユーザーに分割後の全ファイルを確認してもらい承認を取得
5. 承認後、ステップ2 へ進む

「中止」の場合: 「詳細設計 2 ファイルを作成してから再実行してください」と表示して終了。

設計書の全セクションを把握し、タスク分解に必要な情報を抽出する。

### ステップ2: タスク分解

設計書から実装タスクを抽出し、TDDサイクルに従って分解する：

#### 分解の原則

1. **機能単位で分割**: 1つの機能 = 1つのTDDサイクル
2. **依存関係を考慮**: 基盤 → コア機能 → 拡張機能の順
3. **テストファースト**: 各機能でRED→GREEN→REFACTORを明示
4. **フェーズ1 (基盤構築) は DESIGN_DETAIL_APP.md の「プロジェクトセットアップ」から起こす**: スキャフォールド・テンプレート整理・初回起動確認の手順をそのままタスク化する
5. **インフラタスクは DESIGN_DETAIL_INFRA.md から起こす**: CI/CD workflow 作成・リソースプロビジョニング・シークレット設定等。IaC / 設定ファイルは宣言的でテスト対象外のため TDD サイクル ([RED]/[GREEN]) は付けず、代わりに検証手順 (INFRA 側) を [CHECK] タスクにする

#### タスクの粒度

- 1タスク = 1-4時間で完了可能
- テスト1つ + 実装1つ = 1セット
- リファクタリングは独立したタスク

### ステップ3: TODO.md生成

以下の形式でTODO.mdを生成する：

```markdown
# TODO: [プロジェクト名]

作成日: [日付]
生成元: dev-spec (todo-generation)
設計書: docs/DESIGN_DETAIL_APP.md + docs/DESIGN_DETAIL_INFRA.md (概要は docs/DESIGN.md)

## 概要

[設計書から抽出した目的と範囲]

## 実装タスク

### フェーズ1: 基盤構築

[DESIGN_DETAIL_APP.md「プロジェクトセットアップ」の手順をタスク化する]

- [ ] スキャフォールド実行 (設計書記載のコマンド)
- [ ] テンプレートの整理 (削除・残置・追加設定)
- [ ] [CHECK] 初回起動確認 (dev サーバ起動 + テスト実行が green)

### フェーズ2: [機能名A] の実装

- [ ] [RED] [機能A]の動作テストを作成
- [ ] [GREEN] テストを通過させる最小限の実装
- [ ] [REFACTOR] コード品質の改善
- [ ] [REVIEW] フェーズ実装の簡易セルフレビューと修正
- [ ] [CHECK] lint/format/build の実行と確認

### フェーズ3: [機能名B] の実装

- [ ] [RED] [機能B]の動作テストを作成
- [ ] [GREEN] テストを通過させる最小限の実装
- [ ] [REFACTOR] コード品質の改善
- [ ] [REVIEW] フェーズ実装の簡易セルフレビューと修正
- [ ] [CHECK] lint/format/build の実行と確認

### フェーズN-a: インフラ構築 (DESIGN_DETAIL_INFRA.md 由来)

[IaC / 設定ファイルは宣言的なので TDD サイクルは付けず、検証手順 (INFRA 側) を [CHECK] にする]

- [ ] リソースプロビジョニング (設計書記載の IaC / コマンド)
- [ ] CI workflow 作成 (`.github/workflows/ci.yml`: lint / typecheck / test / build)
- [ ] デプロイ workflow 作成 (`.github/workflows/deploy.yml`)
- [ ] シークレット・環境変数の設定 (GitHub Secrets 等)
- [ ] 監視・アラート設定 (該当する場合)
- [ ] [CHECK] INFRA 検証手順の実行 (IaC plan 差分 0 / PR 作成で CI が green / デプロイ疎通)

### フェーズN-b: 品質保証 (テスト・運用)

- [ ] [STRUCTURAL] コード整理（動作変更なし）
- [ ] 全テスト実行と確認 (unit / integration / e2e)
- [ ] 監査ログ / observability (該当する場合)
- [ ] Rate limit / セキュリティ最終確認 (該当する場合)
- [ ] [REVIEW] フェーズ実装の簡易セルフレビューと修正
- [ ] [CHECK] lint/format/build の実行と確認

### フェーズN-c: UI/UX 仕上げ (Web / モバイル Web プロダクトのみ)

CLI / API のみのプロダクトでは省略可。本フェーズの目的は「ブラウザで開いたら実際に使える状態」をゴールに、Voilog セッション F1-F8 のような UX 仕上げ不足を防ぐこと。

- [ ] frontend-design スキルの適用結果を全画面に反映済か確認 (UI_SKETCH.html ベースと整合)
- [ ] アプリシェル仕上げ (ヘッダー / ナビ / フッター / 404 / 認証ガード / ErrorBoundary / グローバルトースト の最終チェック、`/ui-sketch` フェーズ 4.5 で設計したもの)
- [ ] a11y 対応 (aria-label / role / focus トラップ / キーボード操作 / 色コントラスト最低基準)
- [ ] レスポンシブ動作確認 (主要 breakpoint で `chrome-devtools` MCP の `resize_page` + take_snapshot)
- [ ] 空状態 / loading / error の文言とビジュアル仕上げ (DESIGN_DETAIL_APP.md UX 設計と整合)
- [ ] SEO meta 最終確認 (title 動的反映 / lang / favicon / OG image 任意)
- [ ] [REVIEW] review-product-readiness を含む 4 観点レビュー通過
- [ ] [CHECK] 全自動テスト + ビルド緑、`chrome-devtools` MCP で G_E2E シナリオ通し検証 (URL 直叩きせず UI 操作のみで全 UC 巡回)

## 実装ノート

### MUSTルール遵守事項
- TDD: RED → GREEN → REFACTOR → REVIEW → CHECK サイクルを厳守
- REVIEW: 各フェーズ完了時に簡易セルフレビューを実施し、問題があればその場で修正
- CHECK: REVIEW後に lint/format/build を実行して最終確認
- Tidy First: 構造変更と動作変更を分離
- コミット: [BEHAVIORAL] または [STRUCTURAL] プレフィックス必須
  - [BEHAVIORAL]: 動作を変更するコミット（機能追加、バグ修正、テスト追加）
  - [STRUCTURAL]: 動作を変更しないコミット（リファクタリング、フォーマット、コメント追加）

### 参照ドキュメント
- 概要設計: docs/DESIGN.md
- アプリ詳細設計: docs/DESIGN_DETAIL_APP.md
- インフラ詳細設計: docs/DESIGN_DETAIL_INFRA.md
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

### ステップ5: セルフレビュー（ぬけもれ解消まで繰り返し）

生成したTODO.mdをセルフレビューし、**ぬけもれがなくなるまで修正を繰り返す**。

#### レビュー観点

1. **完全性**: DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md のすべての項目がタスク化されているか
2. **TDD準拠**: 実装タスクにRED/GREEN/REFACTOR/CHECKフェーズが明示されているか (INFRA 由来の宣言的タスクは [CHECK] のみで可)
3. **依存関係**: タスクの順序が依存関係を正しく反映しているか
4. **粒度**: 各タスクが適切なサイズ（1-4時間）か
5. **明確性**: タスク内容が具体的で実装者が迷わないか
6. **概要整合**: DESIGN.md (概要) の主要コンポーネント・前提と矛盾していないか

#### レビュープロセス（必須）

**CRITICAL**: このプロセスは問題がゼロになるまで繰り返すこと。途中で打ち切らない。

```
1. DESIGN_DETAIL_APP.md と DESIGN_DETAIL_INFRA.md を再度読み込む（最新の内容を確認）
2. DESIGN.md (概要) も併せて読み込む
3. TODO.md を読み返す
4. 詳細設計 2 ファイルの各セクションを1つずつ確認し、対応するタスクがあるか照合
5. 以下のチェックリストで問題を洗い出す
6. 問題があれば修正してファイルを更新
7. 問題がゼロになるまで1-6を繰り返す
```

#### ぬけもれ確認の具体的手順

1. **詳細設計 2 ファイルのセクション別照合**
   - DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md の各見出し（##, ###）をリストアップ
   - 各見出しに対応する TODO.md のタスクを特定
   - 対応がないセクションを「ぬけもれ」として記録

2. **機能要件の照合**
   - DESIGN_DETAIL_APP.md に記載された API・データ操作を抽出
   - TODO.md に該当タスクがあるか確認
   - ない場合はタスクを追加

3. **非機能要件・インフラの照合**
   - DESIGN_DETAIL_APP.md のテスト戦略 (具体)、エラー戦略 (具体)、検証手順を確認
   - DESIGN_DETAIL_INFRA.md のリソース定義、CI/CD、シークレット、監視、検証手順を確認
   - 対応するタスクがあるか確認、ない場合はタスクを追加

4. **DESIGN.md (概要) との整合**
   - DESIGN.md の主要コンポーネント一覧 / 非機能目標と TODO.md の方針が矛盾していないか

#### セルフレビューチェックリスト

**設計との整合性（ぬけもれチェック重点項目）**
- [ ] DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md の**すべてのセクション**がタスク化されている
- [ ] DESIGN_DETAIL_APP.md の**すべての API・データ操作**がタスク化されている
- [ ] DESIGN_DETAIL_INFRA.md の CI/CD・リソース・シークレット・監視がタスク化されている
- [ ] 非機能要件（テスト戦略、エラー戦略、検証手順）が反映されている
- [ ] 依存関係の順序が正しい
- [ ] DESIGN.md (概要) と整合している
- [ ] 全ファイルを再読み込みして、見落としがないか最終確認した

**TDD準拠**
- [ ] すべての実装タスクにRED/GREEN/REFACTOR/REVIEW/CHECKが明示されている (INFRA 由来の宣言的タスクは [CHECK] のみで可)
- [ ] テストファーストの順序になっている
- [ ] リファクタリングタスクが適切に配置されている
- [ ] 各フェーズにREVIEW（レビュー＋自動修正）→ CHECK（最終確認）の順で配置されている

**実装可能性**
- [ ] 各タスクが1-4時間で完了可能な粒度
- [ ] タスク内容が具体的で曖昧さがない
- [ ] 実装ループ (/dev-impl) で実装開始できる情報量がある

#### 問題発見時の対応

問題を発見した場合：
1. 問題箇所を特定
2. 修正内容を決定
3. TODO.mdを更新
4. **必ず**再度レビューを実行（問題がゼロになるまで終わらない）

#### レビュー完了条件

以下のすべてを満たすまでレビューを終了しない：
- [ ] DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md の全セクションと TODO.md の照合が完了
- [ ] DESIGN.md (概要) との整合が確認できた
- [ ] ぬけもれゼロを確認
- [ ] 上記チェックリストの全項目がチェック済み

問題が解消しない場合（同じ問題が繰り返し発生する等）は、AskUserQuestionツールでユーザーに確認する。

### ステップ6: 完了確認

セルフレビュー完了後、ユーザーに確認する：

```javascript
AskUserQuestion({
  questions: [
    {
      question: "TODO.mdを確認しました。このタスクリストで確定しますか？",
      header: "TODO承認",
      options: [
        { label: "承認", description: "承認ゲート (フェーズ 11) へ進む。実装ループの起動方法はそこで案内される" },
        { label: "却下", description: "コマンドを終了" }
      ],
      multiSelect: false
    }
  ]
})
```

**ユーザーが修正内容を入力した場合（Other選択）**：
1. 入力された修正内容を反映してTODO.mdを更新
2. 再度ユーザー確認を取得（このセクションに戻る）
3. 承認されるまで繰り返す

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
- [ ] [REVIEW] フェーズ実装の簡易セルフレビューと修正
- [ ] [CHECK] lint/format/build の実行と確認
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
- [ ] [REVIEW] フェーズ実装の簡易セルフレビューと修正
- [ ] [CHECK] lint/format/build の実行と確認
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
- [ ] [REVIEW] フェーズ実装の簡易セルフレビューと修正
- [ ] [CHECK] lint/format/build の実行と確認
```
