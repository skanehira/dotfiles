---
name: dev-spec
description: >-
  設計ループ。ユーザーストーリー → UI スケッチ → ユースケース → 実現可能性検証 → PoC 検証 →
  DDD モデリング → 概要/詳細設計 (DESIGN.md / DESIGN_DETAIL.md) → 深掘りインタビュー →
  検証手順補完 → TODO.md 生成までを対話的に実行し、承認ゲートで実装ループ (/dev-impl) へ引き渡す。
  「設計フェーズを開始」「要件を整理したい」「計画を立てたい」「ユーザーストーリーを書きたい」
  「技術的に実現できるか確認したい」「TODO.md を作りたい」「DESIGN.md を深掘りしたい」などで起動。
  docs/ の状態から途中再開・特定フェーズの部分実行も可能。
argument-hint: "[タスク説明]"
---

# dev-spec — 設計ループ

## 概要

設計ループを回して docs/ 配下に設計成果物を生成し、承認ゲートを経て実装ループ (`/dev-impl`) に引き渡す。最終成果物は次の 3 ファイル:

- **docs/DESIGN.md** (概要設計): 目的・スコープ・主要コンポーネント・技術選定・ゴール
- **docs/DESIGN_DETAIL.md** (詳細設計): API・スキーマ・シーケンス・エラー実装・検証手順
- **docs/TODO.md**: TDD 準拠の実装タスクリスト

フェーズごとに Feedback (検証手段) が異なる:

- 要件・設計の妥当性 → **人間の承認** (AskUserQuestion)
- 技術的実現可能性 → **PoC の実行結果** (tech-investigation subagent)。「できるはず」という自己申告のまま設計に進むことを禁止する

### モデルガード

このスキルは賢いモデル (Fable / Opus) のセッションで実行する前提。起動時にセッションモデルを確認し、Sonnet / Haiku なら「設計ループは高知能モデルでの実行を推奨します。このまま続行しますか?」と警告してから進める (強制はしない)。

## フェーズ一覧

**フェーズを開始するときに該当手順書を Read し、その手順に従う。**

| #  | フェーズ             | 手順書                                 | 出力                                  | クイックモード |
| -- | -------------------- | -------------------------------------- | ------------------------------------- | -------------- |
| 1  | ユーザーストーリー   | `references/user-story.md`             | docs/USER_STORIES.md                  | スキップ       |
| 2  | UI スケッチ          | `references/ui-sketch.md`              | docs/UI_SKETCH.md                     | スキップ       |
| 3  | ユースケース記述     | `references/usecase-description.md`    | docs/USECASES.md                      | スキップ       |
| 4  | 実現可能性検証       | `references/feasibility-check.md`      | docs/FEASIBILITY.md (PoC 計画)        | 条件付き実行   |
| 5  | PoC 検証             | `references/poc-verification.md`       | FEASIBILITY.md 更新 (PoC 結果)        | 条件付き実行   |
| 6  | DDD モデリング       | `references/ddd-modeling.md`           | docs/GLOSSARY.md, docs/DOMAIN_MODEL.md | スキップ       |
| 7  | 概要/詳細設計        | `references/analyzing-requirements.md` | docs/DESIGN.md, docs/DESIGN_DETAIL.md | 実行           |
| 8  | 深掘りインタビュー   | `references/interview.md`              | DESIGN / DETAIL 更新                  | 実行           |
| 9  | 検証手順の確認と補完 | `references/verification-review.md`    | DESIGN / DETAIL 更新                  | 実行           |
| 10 | TODO.md 生成         | `references/todo-generation.md`        | docs/TODO.md                          | 実行           |
| 11 | 承認ゲート           | (本ファイル下記)                       | —                                     | 実行           |

### ゲート条件 (フェーズ 7 の開始条件)

FEASIBILITY.md に **`blocker=true` の未解決 PoC 計画が残っている間は、フェーズ 7 (設計書生成) に進んではならない**。フェーズ 5 で全件を「verified」または「ユーザーが fallback 採用を決定」の状態にしてから進む。

## フェーズ 0: ルーティング

### 0.1 タスク説明の取得

`$ARGUMENTS` があればタスク説明として使用。なければ事前の会話から推論し、それも不明なら「どのようなタスクの設計を行いますか?」と質問する。

### 0.2 既存ドキュメントの確認と開始点の決定

docs/ 配下の既存成果物 (USER_STORIES.md / UI_SKETCH.md / USECASES.md / FEASIBILITY.md / GLOSSARY.md / DOMAIN_MODEL.md / DESIGN.md / DESIGN_DETAIL.md / TODO.md) を確認する。

- **DESIGN.md / DESIGN_DETAIL.md / TODO.md の 3 点が揃っている** → 「設計は完成しています。実装ループは `/dev-impl` を起動してください。設計を修正したい場合は更新モードで再実行してください」と案内して終了
- **途中まで存在する** → 「続きから (推奨) / 最初から / 既存を更新」を AskUserQuestion で確認
- **何もない** → モード選択へ

更新モードでは既存ドキュメントを読み取って差分のみ更新し、ファイル先頭に変更履歴コメント (`<!-- 変更履歴 [YYYY-MM-DD]: 要約 -->`) を追記する。

### 0.3 モード選択

```javascript
AskUserQuestion({
  questions: [{
    question: "設計ループの回し方を選んでください",
    header: "モード",
    options: [
      { label: "フルコース", description: "ユーザーストーリー〜DDD まで全フェーズ (1〜11)。新規プロダクト・大きい機能向け" },
      { label: "クイック", description: "タスク説明から設計書 + TODO を直接生成 (7〜11)。技術的な不確実性がある場合のみ実現可能性検証 + PoC (4〜5) を先に通す" }
    ],
    multiSelect: false
  }]
})
```

クイック選択時は「この実装に、成立するか未検証の技術要素 (未経験のライブラリ・外部 API 連携・性能懸念など) はありますか?」を確認し、あればフェーズ 4 → 5 を実行してから 7 へ、なければ 7 から開始する。

### 部分実行

依頼が特定フェーズだけを指す場合 (例: 「ユースケースを詳細化したい」「DESIGN.md を深掘りしたい」「TODO だけ作り直したい」) は、全フェーズを回さず該当フェーズの手順書だけを Read して実行する。

## 各フェーズの進め方

1. 進捗を表示する:

```
📍 設計ループ [n/11]
   ├─ ✓ user-story（完了）
   ├─ ▶ ui-sketch（実行中）
   └─ ○ ...
```

2. 手順書を Read し、手順に従って実行する
3. フェーズ完了後、AskUserQuestion で「次へ進む / ここで終了」を確認する
4. ユーザーが修正内容を入力した場合は反映して再承認を取る (承認されるまで繰り返す)

## フェーズ 11: 承認ゲート (設計 → 実装の遷移)

設計ループと実装ループの境界。**人間の明示承認がないと越えられない Stop** であり、Claude が自律的に実装ループを開始することは禁止。Skill ツール経由の起動では dev-impl のモデル指定 (`model: sonnet`) が適用されないため、実装ループの起動は必ずユーザーが行う。

### 11.1 サマリー表示

```
✓ 設計ループ完了

生成されたファイル:
- docs/DESIGN.md         (概要設計)
- docs/DESIGN_DETAIL.md  (詳細設計)
- docs/TODO.md           (タスクリスト、全 n フェーズ)
- docs/FEASIBILITY.md    (PoC 結果: verified x 件 / fallback 採用 y 件)
```

### 11.2 最終承認

```javascript
AskUserQuestion({
  questions: [{
    question: "設計成果物を確認してください。実装ループへ進んでよいですか?",
    header: "設計承認",
    options: [
      { label: "承認", description: "実装ループの起動方法を案内して終了" },
      { label: "修正", description: "修正内容を指示して該当フェーズへ戻る" },
      { label: "中止", description: "ここで終了 (成果物は残る)" }
    ],
    multiSelect: false
  }]
})
```

### 11.3 実装ループへの引き継ぎ案内

承認されたら以下を表示して**このスキルを終了する** (dev-impl を Skill ツールで起動しない):

```
✓ 設計が承認されました。実装ループは以下のいずれかで開始してください:

A (推奨): 新しいセッションで起動
   claude を新しく開いて /dev-impl を実行。
   設計の対話履歴を持ち込まず、クリーンなコンテキストで実装ループが回る。
   dev-impl は model: sonnet 指定なので、起動ターンから Sonnet で実行される。

B: このセッションで続行
   このまま /dev-impl とタイプ。このターンだけ Sonnet に切り替わる。
   (エスカレーション回答後の再開も /dev-impl の再実行で行う)
```

## 完了条件

- [ ] 対象フェーズがすべて実行された (またはユーザー判断でスキップ)
- [ ] blocker=true の PoC 計画がすべて解決済み (verified または fallback 採用)
- [ ] 全フェーズ実行時: DESIGN.md / DESIGN_DETAIL.md / TODO.md が生成され、承認ゲートを通過した

## 参照ルール

設計・タスク分解で以下を参照する:

- TDD ルール: `rules/core/tdd.md`
- 設計原則: `rules/core/design.md`
- コミットルール: `rules/core/commit.md`

## 関連スキル・エージェント

- **dev-impl**: 実装ループ (旧 workflow-autopilot)。承認ゲート通過後にユーザーが起動する
- **tech-investigation** (subagent): フェーズ 5 の PoC 検証で並列 fan-out される
- **workflow-debate**: 設計判断の壁打ちが必要なとき
