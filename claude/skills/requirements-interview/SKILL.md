---
name: requirements-interview
description: "DESIGN.md と DESIGN_DETAIL.md を読み込み、技術実装・UI/UX・懸念点・トレードオフについて深掘りインタビューを実施し、収集した仕様を概要/詳細の射程に応じて両ファイルに書き出す"
argument-hint: "[DESIGN.mdパス]"
allowed-tools: Read, Write, Edit, AskUserQuestion, Glob
---

# /interview - 深掘りインタビューコマンド

## 概要

DESIGN.md (概要) と DESIGN_DETAIL.md (詳細) を読み込み、ユーザーに対して深掘りインタビューを実施する。
インタビュー完了後、収集した仕様を**質問の射程に応じて適切なファイルに**書き出す。

## 実行手順

### 1. 設計ドキュメントの読み込み

- `$ARGUMENTS` で DESIGN.md のパスが指定されていればそれを基点に使用、なければ `docs/DESIGN.md`
- 同じディレクトリの DESIGN_DETAIL.md (例: `docs/DESIGN_DETAIL.md`) も併せて読み込む
- DESIGN_DETAIL.md が無い場合、ユーザーに「DESIGN_DETAIL.md が見つかりません。analyzing-requirements または planning-tasks のフォールバックで生成してから再実行することをお勧めします」と伝えて続行 (概要のみで深掘りする)

### 2. インタビューの実施

両ファイルの内容を踏まえた上で、AskUserQuestion ツールを使って深掘りインタビューを行う。

**インタビューの観点**:
- 技術実装
- UI/UX
- 懸念点
- トレードオフ
- その他、設計に関わるあらゆること

**質問前に射程を意識する**:

| 質問の対象 | 書き出し先 |
|---|---|
| 主要コンポーネントの責務 / レイヤー方針 / 技術選定理由 / 非機能目標 / ゴール | DESIGN.md |
| API シグネチャ / スキーマ詳細 / シーケンス / エラーパス具体 / 実装パターン・ライブラリ / 検証コマンド | DESIGN_DETAIL.md |

質問文に「これは概要 (DESIGN.md) / 詳細 (DESIGN_DETAIL.md) どちらに関する確認です」と添えると、ユーザーが回答しやすい。

**不確定要素は POC_NEEDED マーカーで残す質問パターン**:

「この技術が想定通り動くか自信が無い」「ライブラリの新機能で挙動が読めない」のような未確定要素を質問で発見したら、ユーザーに「これは autopilot Step 1.5 で自動 PoC させる候補です。マーカーを残してよいですか?」と確認:

```javascript
AskUserQuestion({
  questions: [{
    question: "<対象技術>について実装方針が技術検証次第で変わる場合、autopilot 起動時に自動 PoC させるマーカー (POC_NEEDED) を DESIGN_DETAIL.md に残しますか?",
    header: "POC_NEEDED",
    options: [
      { label: "blocker=true で残す", description: "実装前必須解決。autopilot Step 1.5 で tech-investigation が自動 PoC" },
      { label: "blocker=false で残す", description: "継続可、後追い検証。autopilot 自動 PoC 対象外" },
      { label: "残さない", description: "現時点で方針を確定する (このインタビューで決める)" }
    ],
    multiSelect: false
  }]
})
```

「残す」を選択された場合、DESIGN_DETAIL.md の該当セクションに以下を埋め込む:
```
<!-- POC_NEEDED: id=<unique-id>, scope=<検証対象>, risk=<high|medium|low>, blocker=<true|false> -->
```

**重要なルール**:
- **自明な質問はしない** - 既に書いてあること、答えが明らかなことは聞かない
- **深掘りする** - 表面的な確認ではなく、暗黙の前提や未決定事項を探る
- **継続する** - ユーザーが「完了」と言うまで、または十分な情報が集まるまでインタビューを続ける

### 3. 仕様の書き出し

インタビューが完了したら、収集した情報を**射程に応じて DESIGN.md / DESIGN_DETAIL.md に振り分けて**追記または更新する。

判定基準:
- 「**何を作るか**」(目的・スコープ・主要コンポーネント・前提・技術選定・非機能目標) → DESIGN.md
- 「**どう作るか**」(API・スキーマ・シーケンス・エラー実装・検証コマンド・実装パターン) → DESIGN_DETAIL.md

両ファイルで矛盾が生じないように、書き出し後にクロスチェックする。
