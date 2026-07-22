---
name: dev-spec
description: >-
  設計ループ。ユーザーストーリー → UI スケッチ → ユースケース → 実現可能性検証 → PoC 検証 →
  DDD モデリング → 概要/詳細設計 (DESIGN.md / DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md) → 深掘りインタビュー →
  検証手順補完 → TODO.md 生成までを対話的に実行し、承認ゲートで実装ループ (/dev-impl) へ引き渡す。
  「設計フェーズを開始」「要件を整理したい」「計画を立てたい」「ユーザーストーリーを書きたい」
  「技術的に実現できるか確認したい」「TODO.md を作りたい」「DESIGN.md を深掘りしたい」などで起動。
  docs/ の状態から途中再開・特定フェーズの部分実行も可能。
  `cli` / `webapp` のプロダクトモード指定で CLI ツール開発時は UI スケッチ等を軽量化できる。
argument-hint: "[cli|webapp] [タスク説明]"
---

# dev-spec — 設計ループ

## 概要

設計ループを回して docs/ 配下に設計成果物を生成し、承認ゲートを経て実装ループ (`/dev-impl`) に引き渡す。最終成果物は次の 4 ファイル:

- **docs/DESIGN.md** (概要設計): 共通 (目的・スコープ・ゴール・全体構成図・技術選定) + アプリ概要 + インフラ概要の 3 章構成
- **docs/DESIGN_DETAIL_APP.md** (アプリ詳細設計): セットアップ・API・スキーマ・シーケンス・エラー実装・UX・検証手順 (ローカル / CI 系)
- **docs/DESIGN_DETAIL_INFRA.md** (インフラ詳細設計): リソース・IaC・CI/CD (GitHub Actions 固定)・監視・シークレット・検証手順 (環境依存系)
- **docs/TODO.md**: TDD 準拠の実装タスクリスト

フェーズごとに Feedback (検証手段) が異なる:

- 要件・設計の妥当性 → **人間の承認** (AskUserQuestion)
- 技術的実現可能性 → **PoC の実行結果** (tech-investigation subagent)。「できるはず」という自己申告のまま設計に進むことを禁止する

### モデルガード

このスキルは賢いモデル (Fable / Opus) のセッションで実行する前提。起動時にセッションモデルを確認し、Sonnet / Haiku なら「設計ループは高知能モデルでの実行を推奨します。このまま続行しますか?」と警告してから進める (強制はしない)。

## プロダクトモード

設計対象がブラウザ操作型か CLI/ターミナル型かを表す横断設定。フェーズ 2 (UI スケッチ) の要否とゴール定義 (G_E2E) の中身を左右する。

| モード   | 対象                                    | 判定ヒント                                                       |
| -------- | --------------------------------------- | ------------------------------------------------------------------ |
| `webapp` | ブラウザで操作するプロダクト (モバイル Web 含む) | 「画面」「サイト」「Web」「SPA」「ダッシュボード」等の語 |
| `cli`    | ターミナルから実行するプロダクト (TUI 含む) | 「CLI」「コマンド」「ツール」「TUI」「パイプ」等の語 |

将来モードを追加する場合はこの表に 1 行足し、下記フェーズ一覧の「cli モード」列に相当する列を追加する。

**判定と保持**: モードは docs/DESIGN.md の 1 行目に `<!-- product-mode: cli -->` (または `webapp`) の形式でスタンプする。フェーズ 7 (概要/詳細設計) が新規生成時に必ず書き込む。判定コマンド:

```bash
rg -o -m1 '<!-- product-mode: (cli|webapp) -->' -r '$1' docs/DESIGN.md
```

スタンプが無い (旧形式 docs) 場合、dev-spec は新規生成時に必ずスタンプを書くため発生しない (更新モードで旧形式 docs を扱う場合のみ想定される)。dev-impl はこのスタンプを Step 1 で読み取り、UI 系の観点別レビューやゴール判定を切り替える。**スタンプ不在時、dev-impl は `webapp` と同一には扱わない**: 独立した `unknown` 状態として扱い、Web プロダクト判定 (`dev_server` 推定) が真の場合のみ webapp 相当のフォールバック動作をとる (推定できなければ Web 系の必須判定は効かない。詳細は dev-impl/SKILL.md Step 1 参照)。

**クイックモードとの合成規則**: 各フェーズの有効・無効は「クイックモード列を適用 → cli モード列を適用」の順で決める。どちらか一方でも「スキップ」なら、そのフェーズはスキップする。クイックモード列が「条件付き実行」(フェーズ 4・5) の場合、cli モード列の値 (いずれも「実行」) はこの条件付き判定を上書きしない。フェーズ 0.3 の不確実性確認の結果 (あり/なし) にそのまま従う。

## フェーズ一覧

**フェーズを開始するときに該当手順書を Read し、その手順に従う。**

| #    | フェーズ             | 手順書                                 | 出力                                                                   | クイックモード | cli モード |
| ---- | -------------------- | -------------------------------------- | ---------------------------------------------------------------------- | -------------- | ---------- |
| 1    | ユーザーストーリー   | `references/user-story.md`             | docs/USER_STORIES.md                                                   | スキップ       | 実行       |
| 2    | UI スケッチ          | `references/ui-sketch.md`              | docs/UI_SKETCH.md                                                      | スキップ       | スキップ   |
| 3    | ユースケース記述     | `references/usecase-description.md`    | docs/USECASES.md                                                       | スキップ       | 実行       |
| 4    | 実現可能性検証       | `references/feasibility-check.md`      | docs/FEASIBILITY.md (PoC 計画)                                         | 条件付き実行   | 実行       |
| 5    | PoC 検証             | `references/poc-verification.md`       | FEASIBILITY.md 更新 (PoC 結果)                                         | 条件付き実行   | 実行       |
| 6    | DDD モデリング       | `references/ddd-modeling.md`           | docs/GLOSSARY.md, docs/DOMAIN_MODEL.md                                 | スキップ       | 実行       |
| 7    | 概要/詳細設計        | `references/analyzing-requirements.md` | docs/DESIGN.md, docs/DESIGN_DETAIL_APP.md, docs/DESIGN_DETAIL_INFRA.md | 実行           | 実行       |
| 8    | 深掘りインタビュー   | `references/interview.md`              | DESIGN / DETAIL 更新                                                   | 実行           | 実行       |
| 9    | 検証手順の確認と補完 | `references/verification-review.md`    | DESIGN / DETAIL 更新                                                   | 実行           | 実行       |
| 10   | TODO.md 生成         | `references/todo-generation.md`        | docs/TODO.md                                                           | 実行           | 実行       |
| 10.5 | 設計整合監査         | (本ファイル下記)                       | 監査 findings (修正は 7〜10 へ差し戻し)                                | 実行           | 実行       |
| 11   | 承認ゲート           | (本ファイル下記)                       | —                                                                      | 実行           | 実行       |

### ゲート条件 (フェーズ 7 の開始条件)

FEASIBILITY.md に **`blocker=true` の未解決 PoC 計画が残っている間は、フェーズ 7 (設計書生成) に進んではならない**。判定はプロンプト遵守ではなく次のコマンドで機械的に行う:

```bash
rg -n 'POC_STATUS:.*blocker=true.*status=unresolved' docs/FEASIBILITY.md
```

- 1 件以上ヒット → フェーズ 5 (PoC 検証) へ戻る
- 0 件 → 通過
- FEASIBILITY.md 自体が無い → フェーズ 0.3 で「不確実性なし」を確認済みの場合のみ通過。未確認ならフェーズ 0.3 の不確実性確認に戻る

`POC_STATUS` 行の書式は `references/poc-verification.md` で定義する (フェーズ 4 が `status=unresolved` で書き、フェーズ 5 が更新する)。

## フェーズ 0: ルーティング

### 0.1 タスク説明とプロダクトモードの取得

`$ARGUMENTS` の先頭トークンが `cli` または `webapp` に完全一致すればプロダクトモードとして消費し、残りをタスク説明とする。それ以外の位置・語は自由文のタスク説明として扱う (フラグパーサは持たない)。

タスク説明: `$ARGUMENTS` の残り部分があればそれを使用。なければ事前の会話から推論し、それも不明なら「どのようなタスクの設計を行いますか?」と質問する。

プロダクトモード: `$ARGUMENTS` にモードトークンが無い場合、タスク説明と会話履歴から「プロダクトモード」節の判定ヒントに沿って推論し、推論結果を推奨ラベルにして AskUserQuestion で確認する:

```javascript
AskUserQuestion({
  questions: [{
    question: "このタスクのプロダクトモードを確認してください",
    header: "プロダクトモード",
    options: [
      { label: "cli (推論)", description: "<推論根拠を 1 行で>。UI スケッチをスキップし、CLI インターフェース仕様をフェーズ 7 の詳細設計内で書く" },
      { label: "webapp", description: "現行のフルフロー (UI スケッチ実行、G_E2E はブラウザでの実機検証)" }
    ],
    multiSelect: false
  }]
})
```

推論が `webapp` 寄りなら、`(推論)` ラベルと推論根拠の description を `webapp` の選択肢に付け替え、`cli` の選択肢は「UI スケッチを実行し、G_E2E は実機ブラウザで検証」の説明文にする (label/description の入れ替えのみ。選択肢の並び順は変えない)。

### 0.2 既存ドキュメントの確認と開始点の決定

docs/ 配下の既存成果物 (USER_STORIES.md / UI_SKETCH.md / USECASES.md / FEASIBILITY.md / GLOSSARY.md / DOMAIN_MODEL.md / DESIGN.md / DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md / TODO.md) を確認する。

旧形式の単一 `docs/DESIGN_DETAIL.md` を見つけたら、`references/todo-generation.md` のフォールバック A (APP / INFRA への分割移行) を案内してから続行する。

DESIGN.md が存在する場合、プロダクトモードは 0.1 の推論・質問を行わず「プロダクトモード」節の判定コマンドでスタンプから復元する (再開時は再質問しない)。DESIGN.md が無く UI_SKETCH.md がある場合は webapp 確定。どちらも無い場合は 0.1 のとおり推論・確認する。

- **DESIGN.md / DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md / TODO.md が揃い、TODO.md 先頭に承認スタンプ (`<!-- dev-spec:approved ... -->`) がある** → 「設計は完成しています。実装ループは `/dev-impl` を起動してください。設計を修正したい場合は更新モードで再実行してください」と案内して終了
- **4 点は揃っているが承認スタンプが無い** → 未承認。フェーズ 10.5 (設計整合監査) から再開する
- **途中まで存在する** → 「続きから (推奨) / 最初から / 既存を更新」を AskUserQuestion で確認。「続きから」の再開フェーズは次の表で決める (存在する成果物のうち最も下流のものを見る):

| 最も下流の既存成果物                                      | 再開フェーズ                                                  |
| --------------------------------------------------------- | --------------------------------------------------------------- |
| USER_STORIES.md                                           | 2 (UI スケッチ)。cli モードでは 2 をスキップし 3 (ユースケース) |
| UI_SKETCH.md                                               | 3 (ユースケース)                                              |
| USECASES.md                                                | 4 (実現可能性)                                                 |
| FEASIBILITY.md (blocker=true が unresolved)                | 5 (PoC 検証)                                                    |
| FEASIBILITY.md (全件解決済み)                               | 6 (DDD)。クイックモードなら 7                                   |
| GLOSSARY.md / DOMAIN_MODEL.md                               | 7 (設計書生成)                                                  |
| DESIGN.md + DESIGN_DETAIL_APP.md + DESIGN_DETAIL_INFRA.md   | 8 (深掘り)。深掘り済みが明らかなら 9                            |
| TODO.md (承認スタンプ無し)                                  | 10.5 (設計整合監査)                                             |

- **何もない** → モード選択へ

更新モードでは既存ドキュメントを読み取って差分のみ更新し、ファイル先頭に変更履歴コメント (`<!-- 変更履歴 [YYYY-MM-DD]: 要約 -->`) を追記する。プロダクトモードのスタンプ行は変更履歴コメントの挿入で押し出さず、DESIGN.md の 1 行目に保つ。

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

クイック選択時は、まず Claude 自身がタスク説明と会話履歴から不確実性候補 (未経験ライブラリ / 外部 API 連携 / 性能・スケール懸念 / 新しいプラットフォーム機能) を走査して列挙し、その候補を提示した上で「これらを含め、成立するか未検証の技術要素はありますか?」と AskUserQuestion で確認する (人間の記憶だけに頼らない)。あればフェーズ 4 → 5 を実行してから 7 へ、なければ 7 から開始する (この「不確実性なし」の確認が、ゲート条件の「FEASIBILITY.md 無し」通過の根拠になる)。

### 部分実行

依頼が特定フェーズだけを指す場合 (例: 「ユースケースを詳細化したい」「DESIGN.md を深掘りしたい」「TODO だけ作り直したい」) は、全フェーズを回さず該当フェーズの手順書だけを Read して実行する。**ただし対象にフェーズ 7 が含まれる場合は、実行前に必ず「ゲート条件」の判定コマンドを実行する** (ゲートはどの経路から入っても効かせる)。対象がフェーズ 2 (UI スケッチ) の場合、DESIGN.md が存在すればそのプロダクトモードで判定し `cli` なら「cli モードでは UI スケッチは対象外です」と案内して終了する。DESIGN.md がまだ無い場合は先に 0.1 のモード確認を行ってから判定する。

## 各フェーズの進め方

1. 進捗を表示する。cli モードでスキップしたフェーズは `⊘` で表示し番号は振り直さない:

```
📍 設計ループ [n/12]
   ├─ ✓ user-story（完了）
   ├─ ⊘ ui-sketch（cli モードのためスキップ）
   ├─ ▶ usecase-description（実行中）
   └─ ○ ...
```

2. 手順書を Read し、手順に従って実行する
3. フェーズ完了後、AskUserQuestion で「次へ進む / ここで終了」を確認する
4. ユーザーが修正内容を入力した場合は反映して再承認を取る (承認されるまで繰り返す)

## フェーズ 10.5: 設計整合監査 (第三者検証)

人間承認 (フェーズ 11) の前捌きとして、`review-spec-compliance` subagent (mode: pre-approval) に docs 4 ファイルの整合を fresh context で監査させる。設計者本人 (このセッション) のセルフレビューでは検出できない見落とし (TODO カバレッジ漏れ / ゴールと検証手順の意味的不整合 / 検証コマンドの空虚性 / APP・INFRA 境界誤配置 / 概要↔詳細の矛盾) を承認前に潰す。**人間承認の代替ではない** (フェーズ 11 は残る)。

```javascript
const audit = await Agent({
  description: "設計整合の第三者監査",
  subagent_type: "review-spec-compliance",
  model: "opus",   // 呼び出し時明示 (実行器 ≤ 検証器)
  prompt: `mode: pre-approval
docs_dir: docs/
output_path: /tmp/review-spec-compliance-pre-approval.json
docs (DESIGN.md / DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md / TODO.md) は自分で全文 Read すること。
作業結果 (output_path のパス) は必ず最終メッセージで親に返すこと。`
})
```

結果の分岐 (**最大 2 周**):

- **severity: high の findings あり** → 指摘の対象で戻り先を決めて修正する: TODO カバレッジ → フェーズ 10、検証手順・空虚性 → フェーズ 9、設計内容・境界・矛盾 → フェーズ 7〜8。修正後に本フェーズを再実行する
- **2 周しても high が残る** → 差し戻しを打ち切り、残存 findings をフェーズ 11 のサマリーに「監査で未解消の指摘」として添付し、人間の判断に委ねる
- **high が 0 件 (medium/low のみ)** → findings をフェーズ 11 のサマリーに参考情報として添付し、フェーズ 11 へ進む
- **agent がエラー / JSON 解釈不能** → 監査未実施のまま進まない。ユーザーに「監査 agent が失敗しました。再試行 / 監査なしで承認ゲートへ / 中止」を AskUserQuestion で確認する (未検証を silent にパス扱いしない)

## フェーズ 11: 承認ゲート (設計 → 実装の遷移)

設計ループと実装ループの境界。**人間の明示承認がないと越えられない Stop** であり、Claude が自律的に実装ループを開始することは禁止。Skill ツール経由の起動では dev-impl のモデル指定 (`model: sonnet`) が適用されないため、実装ループの起動は必ずユーザーが行う。

### 11.1 サマリー表示

```
✓ 設計ループ完了

生成されたファイル:
- docs/DESIGN.md              (概要設計)
- docs/DESIGN_DETAIL_APP.md   (アプリ詳細設計)
- docs/DESIGN_DETAIL_INFRA.md (インフラ詳細設計)
- docs/TODO.md                (タスクリスト、全 n フェーズ)
- docs/FEASIBILITY.md         (PoC 結果: verified x 件 / fallback 採用 y 件)
```

FEASIBILITY.md を作成していない場合 (クイックモードで不確実性なし) は、その行を省略する。

DESIGN.md の「未解決の論点 (Open Issues)」に項目があれば続けて列挙する (「なし」なら省略)。

フェーズ 10.5 の監査 findings があれば続けて列挙する (未解消の high は「監査で未解消の指摘」、medium/low は「参考」として区別する)。

### 11.2 最終承認

未解決の論点が残っている場合、この承認は「その論点を認識した上での承認」であることを前提とする。

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

「修正」の戻り先は指摘内容で決める: ゴール・検証手順 → フェーズ 9、設計内容 → フェーズ 7〜8、タスク分割 → フェーズ 10。戻った後は当該フェーズ以降を再実行し、再度この承認ゲートに来る。

### 11.3 実装ループへの引き継ぎ案内

承認されたら次の 2 つを行って**このスキルを終了する** (dev-impl を Skill ツールで起動しない):

1. **承認スタンプの書き込み**: まず受入基準のハッシュを計算する:

```bash
GOALS_SHA=$(
  {
    rg --no-filename '^- G[0-9]+:|^G[0-9]+:|^- G_E2E:|^G_E2E:' docs/DESIGN.md
    rg --no-filename 'G[0-9]+ 検証|G_E2E 検証' docs/DESIGN_DETAIL_APP.md docs/DESIGN_DETAIL_INFRA.md
  } | shasum -a 256 | awk '{print $1}'
)
```

`docs/TODO.md` の先頭 (1 行目) に `<!-- dev-spec:approved YYYY-MM-DD goals_sha=${GOALS_SHA} -->` を挿入する (既存スタンプがあれば行ごと置換)。ハッシュ対象は**ゴール定義行と検証手順行のみ**で、承認時点の受入基準をスタンプにバインドする。dev-impl は起動時 (Step 1 構造ゲート) にスタンプの存在とハッシュ一致を機械チェックし、承認後に受入基準が変更されていれば実装に入らない (`approval_stale`)。P2 動的修正 (実装ガイド等の追記) はハッシュ対象外なので正当に通る
2. 以下を表示する:

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
- [ ] 全フェーズ実行時: DESIGN.md / DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md / TODO.md が生成され、承認ゲートを通過した
- [ ] フェーズ 10.5 の設計整合監査が実行された (high findings は解消、または未解消のまま人間判断に添付)
- [ ] 承認時: TODO.md 先頭に承認スタンプ (goals_sha 付き) が書き込まれた

## 参照ルール

設計・タスク分解で以下を参照する:

- TDD ルール: `rules/core/tdd.md`
- 設計原則: `rules/core/design.md`
- コミットルール: `rules/core/commit.md`

## 関連スキル・エージェント

- **dev-impl**: 実装ループ (旧 workflow-autopilot)。承認ゲート通過後にユーザーが起動する
- **tech-investigation** (subagent): フェーズ 5 の PoC 検証で並列 fan-out される
- **review-spec-compliance** (subagent): フェーズ 10.5 の設計整合監査 (mode: pre-approval、`model: opus` 明示)
- **workflow-debate**: 設計判断の壁打ちが必要なとき
