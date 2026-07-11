# /interview - 深掘りインタビューコマンド

## 概要

DESIGN.md (概要) と DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md (詳細) を読み込み、ユーザーに対して深掘りインタビューを実施する。
インタビュー完了後、収集した仕様を**質問の射程に応じて適切なファイルに**書き出す。

## 実行手順

### 1. 設計ドキュメントの読み込み

- `$ARGUMENTS` で DESIGN.md のパスが指定されていればそれを基点に使用、なければ `docs/DESIGN.md`
- 同じディレクトリの DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md も併せて読み込む
- 詳細設計ファイルが無い場合、ユーザーに「詳細設計 (DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md) が見つかりません。analyzing-requirements または todo-generation のフォールバックで生成してから再実行することをお勧めします」と伝えて続行 (概要のみで深掘りする)

### 2. インタビューの実施

全ファイルの内容を踏まえた上で、AskUserQuestion ツールを使って深掘りインタビューを行う。

**インタビューの観点**:
- 技術実装
- インフラ・運用
- UI/UX
- 懸念点
- トレードオフ
- その他、設計に関わるあらゆること

**質問前に射程を意識する**:

| 質問の対象 | 書き出し先 |
|---|---|
| 主要コンポーネントの責務 / レイヤー方針 / 技術選定理由 / 非機能目標 / ゴール | DESIGN.md |
| API シグネチャ / スキーマ詳細 / シーケンス / エラーパス具体 / 実装パターン・ライブラリ / UX 仕様 / ローカル・CI の検証コマンド | DESIGN_DETAIL_APP.md |
| リソース構成 / IaC / workflow・デプロイフロー / シークレット / 監視閾値・通知先 / 環境依存の検証手順 | DESIGN_DETAIL_INFRA.md |

質問文に「これは概要 (DESIGN.md) / アプリ詳細 (DESIGN_DETAIL_APP.md) / インフラ詳細 (DESIGN_DETAIL_INFRA.md) のどれに関する確認です」と添えると、ユーザーが回答しやすい。

**不確定要素は POC_NEEDED マーカーで残す質問パターン**:

「この技術が想定通り動くか自信が無い」「ライブラリの新機能で挙動が読めない」のような未確定要素を質問で発見したら、ユーザーに扱いを確認する:

```javascript
AskUserQuestion({
  questions: [{
    question: "<対象技術>について実装方針が技術検証次第で変わる可能性があります。どう扱いますか?",
    header: "PoC 判断",
    options: [
      { label: "いま PoC で検証する", description: "実装方針を左右する要素。フェーズ 5 (poc-verification.md) に戻り tech-investigation で検証してから設計を確定する" },
      { label: "blocker=false で残す", description: "継続可、後追い検証。POC_NEEDED マーカーとして DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md の該当側に残す" },
      { label: "残さない", description: "現時点で方針を確定する (このインタビューで決める)" }
    ],
    multiSelect: false
  }]
})
```

「残す」を選択された場合、検証対象がアプリ実装なら DESIGN_DETAIL_APP.md、インフラ構成なら DESIGN_DETAIL_INFRA.md の該当セクションに以下を埋め込む:
```
<!-- POC_NEEDED: id=<unique-id>, scope=<検証対象>, risk=<high|medium|low>, blocker=<true|false> -->
```

**重要なルール**:
- **自明な質問はしない** - 既に書いてあること、答えが明らかなことは聞かない
- **深掘りする** - 表面的な確認ではなく、暗黙の前提や未決定事項を探る
- **継続する** - ユーザーが「完了」と言うまで、または十分な情報が集まるまでインタビューを続ける

### 3. 仕様の書き出し

インタビューが完了したら、収集した情報を**射程に応じて DESIGN.md / DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md に振り分けて**追記または更新する。

判定基準:
- 「**何を作るか**」(目的・スコープ・主要コンポーネント・前提・技術選定・非機能目標) → DESIGN.md
- 「**どう実装するか**」(API・スキーマ・シーケンス・エラー実装・UX・ローカル/CI の検証コマンド・実装パターン) → DESIGN_DETAIL_APP.md
- 「**どう構築・運用するか**」(リソース・IaC・workflow・シークレット・監視・環境依存の検証手順) → DESIGN_DETAIL_INFRA.md

全ファイルで矛盾が生じないように、書き出し後にクロスチェックする。
