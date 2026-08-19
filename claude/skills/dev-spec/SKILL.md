---
name: dev-spec
description: >-
  設計ループ。ユーザーストーリー → UI スケッチ → ユースケース → 実現可能性検証 → PoC 検証 →
  DDD モデリング → 概要/詳細設計 (DESIGN.md / DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md) → 深掘りインタビュー →
  検証手順補完 → TODO.md 生成までを対話的に実行し、承認ゲートで実装ループへ引き渡す。
  「設計フェーズを開始」「要件を整理したい」「計画を立てたい」「ユーザーストーリーを書きたい」
  「技術的に実現できるか確認したい」「TODO.md を作りたい」「DESIGN.md を深掘りしたい」などで起動。
  docs/ の状態から途中再開・特定フェーズの部分実行も可能。
  `cli` / `webapp` のプロダクトモード指定で CLI ツール開発時は UI スケッチ等を軽量化できる。
  承認ゲートを通ると TODO.md の各フェーズを GitHub issue 化し、/dev-impl がそれを 1 件ずつ実装する。
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
sed -nE 's/.*<!-- product-mode: (cli|webapp) -->.*/\1/p' docs/DESIGN.md | head -1
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
| 11   | 承認ゲート           | (本ファイル下記)                       | 承認スタンプ                                                           | 実行           | 実行       |
| 12   | GitHub issue 生成    | (本ファイル下記)                       | `ready` ラベル付きの issue 群                                          | 実行           | 実行       |

**フェーズ 12 はモードに関係なく常に実行する。** 実装ループ (`/dev-impl`) は issue を入力にとるので、issue が無いと次に進めない。進捗表示 (`📍 設計ループ [n/N]`) の分母は 12 とする。

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

`$ARGUMENTS` の先頭トークン群のうち、`cli` / `webapp` に完全一致するものは**プロダクトモード**として消費し、残りをタスク説明とする。それ以外の位置・語は自由文のタスク説明として扱う (フラグパーサは持たない)。

タスク説明: `$ARGUMENTS` の残り部分があればそれを使用。なければ事前の会話から推論し、それも不明なら「どのようなタスクの設計を行いますか?」と質問する。

**引き渡し先は常に `/dev-impl` で、経路の選択肢は無い。** 承認ゲート (フェーズ 11) を通ると、フェーズ 12 が TODO.md の各フェーズを GitHub issue に転記し、`/dev-impl` がその issue を依存順に 1 件ずつ実装する。**実装中の状態の原本は GitHub issue** (ラベルと open/closed) で、TODO.md は監査と承認の対象かつ issue の生成元として残る。

**既存の docs から復元できる項目は質問しない。** `docs/DESIGN.md` があればプロダクトモードはスタンプから復元する (0.2 の手順)。再開時に確定済みの項目を訊き直さないための優先順である。

トークン指定も docs からの復元もできない場合だけ、タスク説明と会話履歴から推論し、推論結果を推奨ラベルにして確認する:

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

プロダクトモードが既に確定していれば AskUserQuestion 自体を呼ばない。

推論が `webapp` 寄りなら、`(推論)` ラベルと推論根拠の description を `webapp` の選択肢に付け替え、`cli` の選択肢は「UI スケッチを実行し、G_E2E は実機ブラウザで検証」の説明文にする (label/description の入れ替えのみ。選択肢の並び順は変えない)。

### 0.2 既存ドキュメントの確認と開始点の決定

docs/ 配下の既存成果物 (USER_STORIES.md / UI_SKETCH.md / USECASES.md / FEASIBILITY.md / GLOSSARY.md / DOMAIN_MODEL.md / DESIGN.md / DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md / TODO.md) を確認する。

旧形式の単一 `docs/DESIGN_DETAIL.md` を見つけたら、`references/todo-generation.md` のフォールバック A (APP / INFRA への分割移行) を案内してから続行する。

DESIGN.md が存在する場合、プロダクトモードは 0.1 の推論・質問を行わず「プロダクトモード」節の判定コマンドでスタンプから復元する (再開時は再質問しない)。DESIGN.md が無く UI_SKETCH.md がある場合は webapp 確定。どちらも無い場合は 0.1 のとおり推論・確認する。

- **DESIGN.md / DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md / TODO.md が揃い、TODO.md 先頭に承認スタンプ (`<!-- dev-spec:approved ... -->`) がある** → 設計は完成している。**フェーズ 12 だけを実行する。** 承認は取得済みなので取り直さない。issue 化済みかの判定は 12.3 の突き合わせが冪等に行うので、ここで自前の確認をしない (全件スキップなら「作成済み」と報告され、`/dev-impl` の案内に進む)
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

人間承認 (フェーズ 11) の前捌きとして、`review-spec-compliance` subagent (mode: pre-approval) に docs 4 ファイルの整合を fresh context で監査させる。設計者本人 (このセッション) のセルフレビューでは検出できない見落とし (TODO カバレッジ漏れ / ゴールと検証手順の意味的不整合 / 検証コマンドとフェーズ DoD の空虚性 / APP・INFRA 境界誤配置 / 概要↔詳細の矛盾) を承認前に潰す。**監査 agent は DoD と検証手順のコマンドを実際に実行し、「著作時点の誤り (不正なフラグ・構文エラー) 」と「実装の不在」を切り分ける** — 静的に読むだけでは、そのフェーズが原理的に受け入れ判定を通せない状態に気付けない (実測)。**人間承認の代替ではない** (フェーズ 11 は残る)。

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

設計ループと実装ループの境界。**人間の明示承認がないと越えられない Stop** であり、Claude が自律的に実装ループを開始することは禁止。Skill ツール経由の起動では dev-impl のモデル指定 (`model: opus`) が適用されないため、実装ループの起動は必ずユーザーが行う。

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

**承認は GitHub への書き込みの承認を兼ねる。** 承認直後にフェーズ 12 が issue を作成するため、選択肢の説明文でそれを明示し、ユーザーが副作用を認識したうえで承認できる状態にする。

**説明文を埋める前に 12.1 の前提条件チェックを実行する。** リポジトリ・`gh` 認証が解決できない環境で承認だけ取得すると、承認スタンプを書いた後にフェーズ 12 が停止し、「承認済みだが issue が無い」という中途半端な状態になる。解決できなければ承認を求めず、12.1 の案内を出して終了する。`<n>` は `docs/TODO.md` のフェーズ数 (`rg -c '^### フェーズ' docs/TODO.md`) とする。

```javascript
AskUserQuestion({
  questions: [{
    question: "設計成果物を確認してください。実装ループへ進んでよいですか?",
    header: "設計承認",
    options: [
      { label: "承認", description: "承認すると <owner/name> に issue を <n> 件作成します (フェーズ 12)。その後 /dev-impl の起動方法を案内して終了" },
      { label: "修正", description: "修正内容を指示して該当フェーズへ戻る" },
      { label: "中止", description: "ここで終了 (成果物は残る。issue は作成しない)" }
    ],
    multiSelect: false
  }]
})
```

「修正」の戻り先は指摘内容で決める: ゴール・検証手順 → フェーズ 9、設計内容 → フェーズ 7〜8、タスク分割 → フェーズ 10。戻った後は当該フェーズ以降を再実行し、再度この承認ゲートに来る。

### 11.3 実装ループへの引き継ぎ案内

承認されたら次の 2 つを行い、2 の案内の前に**フェーズ 12 を実行する**。**実装ループを Skill ツールで起動しない** (`/dev-impl` はユーザーが起動する):

1. **承認スタンプの書き込み**: まず受入基準のハッシュを計算する:

```bash
GOALS_SHA=$(
  {
    rg --no-filename '^- G[0-9]+:|^G[0-9]+:|^- G_E2E:|^G_E2E:' docs/DESIGN.md
    rg --no-filename '^- G[0-9]+ 検証|^G[0-9]+ 検証|^- G_E2E 検証|^G_E2E 検証' docs/DESIGN_DETAIL_APP.md docs/DESIGN_DETAIL_INFRA.md
  } | shasum -a 256 | cut -d' ' -f1
)
```

`docs/TODO.md` の先頭 (1 行目) に `<!-- dev-spec:approved YYYY-MM-DD goals_sha=${GOALS_SHA} -->` を挿入する (既存スタンプがあれば行ごと置換)。ハッシュ対象は**ゴール定義行と検証手順行のみ**で、承認時点の受入基準をスタンプにバインドする。dev-impl は起動時 (Step 1 構造ゲート) にスタンプの存在とハッシュ一致を機械チェックし、承認後に受入基準が変更されていれば実装に入らない (`approval_stale`)。P2 動的修正 (実装ガイド等の追記) はハッシュ対象外なので正当に通る
2. フェーズ 12 を実行してから次を表示する。

```
✓ 設計が承認され、issue を <n> 件作成しました (ready: <a> 件 / needs-human: <b> 件)。

実装ループは以下のいずれかで開始してください:

A (推奨): 新しいセッションで起動
   対象リポジトリのディレクトリで claude を新しく開き、/dev-impl を実行。
   設計の対話履歴を持ち込まず、クリーンなコンテキストで実装ループが回る。
   dev-impl は model: opus 指定なので、起動ターンから Opus で実行される。

B: このセッションで続行
   このまま /dev-impl とタイプ。このターンだけ Opus に切り替わる。
   (エスカレーション回答後の再開も /dev-impl の再実行で行う)

dev-impl は issue を依存順に 1 件ずつ実装して close する。
needs-human が付いた issue は着手せず、最初にユーザーへ質問を出す。
```

## フェーズ 12: GitHub issue 生成

`docs/TODO.md` の各フェーズを GitHub issue に写す。**新しい内容を書かない — TODO.md からの機械的な転記に徹する。**

理由: DoD 設計を fresh context で検査するのはフェーズ 10.5 の `pre-approval` 監査だけである。ここで本文を創作すると、監査後・承認後になり第三者検査を素通りする。転記中に「情報が足りない」と気づいたら、issue に書き足すのではなく**フェーズ 10 へ戻って TODO.md を直し、10.5 から再実行する**。

### 12.1 前提条件 (**11.2 の承認を求める前に実行する**)

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
REPO_SLUG=$(gh repo view --json nameWithOwner -q .nameWithOwner)
DEFAULT_BRANCH=$(git -C "$REPO_ROOT" symbolic-ref --short HEAD)
```

いずれかが失敗する (git リポジトリでない / GitHub リモートが無い / `gh` 未認証) 場合は**停止**し、状況を伝えて「リポジトリを用意してから `/dev-spec team` を再実行してください」と案内する。issue を作れないまま成功したように振る舞わない。

**`docs/` がデフォルトブランチに push 済みであることを確認する。**

```bash
git -C "$REPO_ROOT" ls-tree --name-only "origin/$DEFAULT_BRANCH" -- docs/
```

出力が空なら停止し、次を案内する。issue の「参照すべき docs」はメンバーが **worktree の中で**読むが、worktree は `origin/$DEFAULT_BRANCH` から切られるため、docs が push されていないと参照先が存在しない (メンバーは設計者と会話できないので、これが起きると実装の根拠が消える):

```
docs/ がリモートにありません。issue の「参照すべき docs」をメンバーが読めないため、
先にコミットして push してください:

  git add docs/ && git commit -m "📝 docs: 設計成果物を追加する" && git push
```

`git push` は人間が行う (このスキルは push しない)。

### 12.2 ラベルの用意 (冪等)

`--force` は「無ければ作成、あれば更新」なので毎回流してよい。

```bash
gh label create ready        --force --color 0E8A16 --description "着手可能。依存が解決済みで DoD が判定可能"
gh label create in-progress  --force --color 1D76DB --description "dev-impl が実装中"
gh label create needs-human  --force --color D93F0B --description "人間の判断待ちで駐車中"
```

### 12.3 既存 issue との突き合わせ (冪等)

```bash
gh issue list --repo "$REPO_SLUG" --state all --limit 200 --json number,title,state,labels
```

**ライフサイクルラベル**とは `ready` / `in-progress` / `needs-human` の 3 つ (12.2 で作るもの) を指す。

各フェーズについて、既存 issue を次のとおり分類する:

| 既存 issue の状態 | 判定 | 動作 |
| --- | --- | --- |
| 無い | 未作成 | 12.4 で新規作成する |
| タイトル一致・**ラベル無しの open** | **未完成** (作成直後に落ちた) | 本文を作り直して貼り直し、ラベルを付ける。ラベルが無いと `/dev-impl` の Step 2 が着手対象として拾わず、恒久的に不可視になる |
| タイトル一致・ラベルあり・**本文が現在の TODO.md 転記内容と一致** | 最新 | スキップする |
| タイトル一致・ラベルあり・**本文が不一致** | **設計が改訂された** | `gh issue edit <番号> --body-file` で貼り直す (下記) |
| closed | 完了済み | スキップする (再オープンしない) |

**本文の一致確認を省かない。** フェーズ 12 の冒頭で「情報が足りなければフェーズ 10 へ戻って TODO.md を直し 10.5 から再実行する」と定めているが、タイトル一致だけでスキップすると**その修正が issue に届かない**。修正した DoD が実装者に渡らなければ、戻った意味が消える。

```bash
gh issue view "$ISSUE_NUM" --repo "$REPO_SLUG" --json body -q .body > /tmp/issue-current.md
cmp -s /tmp/issue-current.md /tmp/issue-body.md || \
  gh issue edit "$ISSUE_NUM" --repo "$REPO_SLUG" --body-file /tmp/issue-body.md
```

比較にコマンド置換 (`$(...)`) を使わない — 末尾改行を捨てるため差分を取りこぼす (`rules/core/verification.md`)。

**`in-progress` の issue の本文を書き換えたときは、issue コメントで改訂を告知する。** `/dev-impl` が古い DoD で作業している可能性があるため、再開時に気付けるようにする。

### 12.4 issue の生成

**TODO.md のフェーズ出現順に 1 件ずつ作る。** deps は前方参照が禁止されている (`references/todo-generation.md`「フェーズ依存の宣言」) ため、出現順に作れば依存先の issue 番号は**常に確定済み**になる。識別子 → issue 番号の対応表を作りながら進める。

**対応表は 12.3 の出力で seed してから作成に入る。** 中断後の再実行では先行フェーズが「作成済み」でスキップされるため、seed しないと `Depends on #<issue番号>` を解決できず依存が空になる (`/dev-impl` の Step 2 が着手順を決められず、依存先が未完成のまま実装に入る)。12.3 で取得した `number,title` から、既存 issue のフェーズ識別子 → 番号を先に全件入れておく。

`gh issue create` が返すのは**番号ではなく URL** なので、番号を取り出してから対応表に入れる (そのまま埋めると `Depends on <URL>` になり、`/dev-impl` の Step 2 が依存を読めない):

```bash
# ラベルは 12.5 の判定で先に決めておく ("$LABEL" = ready または needs-human)
ISSUE_URL=$(gh issue create --repo "$REPO_SLUG" --title "$TITLE" --body-file /tmp/issue-body.md --label "$LABEL")
ISSUE_NUM=$(printf '%s' "$ISSUE_URL" | grep -o '[0-9]*$')
```

`$TITLE` と `/tmp/issue-body.md` はフェーズごとに用意する。本文は Write ツールで `/tmp/issue-body.md` に書き出してから渡す (改行を含むため `--body` にインラインで埋めない)。本文の構造は次に固定する — `/dev-impl` がこの見出しで読むため、**節名を変えない**:

```markdown
## ゴール
<TODO.md のメタ情報「ゴール」をそのまま>

## DoD
<TODO.md のメタ情報「DoD」をそのまま。`DoD (手動):` があれば続けて書く>

## 参照すべき docs
<TODO.md のメタ情報「参照 docs」をそのまま>

## 変更が想定されるファイル
<TODO.md のメタ情報「変更想定ファイル」をそのまま>

## 非スコープ
<TODO.md のメタ情報「非スコープ」をそのまま>

## 実装タスク
<TODO.md のチェックボックス群をそのまま>

## 依存
Depends on #<issue番号>        <!-- deps: none なら「依存なし」と書く -->

## 対応ゴール
G1, G2                          <!-- goals: none なら本節を省略 -->
```

本文は TODO.md のフェーズから次を写す。**変換が要るのは依存の 1 項目だけで、残りはそのまま転記する**:

| issue 本文 | TODO.md での所在 | 変換 |
| --- | --- | --- |
| ゴール | メタ情報の**ゴール** | そのまま |
| DoD | メタ情報の **DoD** / **DoD (手動)** | そのまま (両方あれば両方) |
| 参照すべき docs | メタ情報の**参照 docs** | そのまま |
| 変更が想定されるファイル | メタ情報の**変更想定ファイル** | そのまま |
| 非スコープ | メタ情報の**非スコープ** | そのまま |
| 実装タスク | チェックボックス群 | そのまま |
| 依存 | `<!-- deps: 2,3 -->` | **`Depends on #<issue番号>`** に変換 (対応表を引く。`none` なら「依存なし」と書く) |
| 対応ゴール | `<!-- goals: G1,G2 -->` | `G1, G2` と本文に書く (`none` なら省略) |

タイトルは `フェーズ<識別子>: <名前>` (TODO.md の見出しから HTML コメントを除いたもの) をそのまま使う。12.3 の突き合わせがタイトル一致で行われるため、**整形して変えない**。

**TODO.md の全フェーズ共通節も各 issue に転記する。** `## 実装タスク` より前にフェーズ横断の規約 (「DoD ブロックの実行方法」等) がある場合、それを `## DoD` の直後に `### <節名>` として埋め込む。**メンバーが読むのは issue だけ**で TODO.md 冒頭は届かないため、転記しないと規約が失われる (実測: DoD ブロックを `bash -e` で流す前提・`cmd && exit 1 || exit 0` の禁止といった、DoD の解釈に必須の規約が全フェーズ共通節にしか無かった)。共通節が無ければ本項はスキップする。

### 12.5 ラベルの付与

**ラベルは issue の作成前に決める** (12.4 のスニペットの `$LABEL`)。判定は 1 行で機械的に行う:

```bash
rg -q 'DoD \(未定義\):' <該当フェーズの本文> && LABEL=needs-human || LABEL=ready
```

**原則すべて `ready`。** DoD の要件はフェーズ 10 の生成要件として満たされ、フェーズ 10.5 の監査 (`phase_meta_missing` / `phase_dod_vacuous`) と人間承認を通過済みなので、ここで改めて審査しない。二重の門を作ると、どちらが正かが曖昧になる。

例外は 1 つだけ: **`DoD (未定義): <理由>` が書かれているフェーズ**は `needs-human` を貼り、理由を issue コメントに転記する。`ready` と併記しない (`/dev-impl` は `ready` の issue を着手対象にするため、両方付けると駐車したはずの issue が実装される)。

### 12.6 結果の報告

作成件数 (`ready` / `needs-human` / スキップした既存 issue) を数え、11.3 の案内文に埋める。

## 完了条件

- [ ] 対象フェーズがすべて実行された (またはユーザー判断でスキップ)
- [ ] blocker=true の PoC 計画がすべて解決済み (verified または fallback 採用)
- [ ] 全フェーズ実行時: DESIGN.md / DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md / TODO.md が生成され、承認ゲートを通過した
- [ ] フェーズ 10.5 の設計整合監査が実行された (high findings は解消、または未解消のまま人間判断に添付)
- [ ] 承認時: TODO.md 先頭に承認スタンプ (goals_sha 付き) が書き込まれた
- [ ] TODO.md の全フェーズが issue 化され、ラベル (`ready` または `needs-human`) が付いた

## 参照ルール

設計・タスク分解で以下を参照する:

- TDD ルール: `rules/core/tdd.md`
- 設計原則: `rules/core/design.md`
- コミットルール: `rules/core/commit.md`

## 関連スキル・エージェント

- **dev-impl**: issue 駆動の逐次実装ループ。フェーズ 12 が issue を作った後、ユーザーが起動する
- **tech-investigation** (subagent): フェーズ 5 の PoC 検証で並列 fan-out される
- **review-spec-compliance** (subagent): フェーズ 10.5 の設計整合監査 (mode: pre-approval、`model: opus` 明示)
- **workflow-debate**: 設計判断の壁打ちが必要なとき
