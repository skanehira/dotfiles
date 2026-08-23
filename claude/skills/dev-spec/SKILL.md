---
name: dev-spec
description: >-
  設計ループ。ユーザーストーリー → UI スケッチ → ユースケース → 実現可能性検証 → PoC 検証 →
  横断設計 (docs/DESIGN.md) → 機能設計 (docs/features/) → 設計チェック → issue ドラフトチェック →
  GitHub issue 生成 (親子構造) までを対話的に実行し、人間が issue を確認して実装ループへ引き渡す。
  「設計フェーズを開始」「要件を整理したい」「計画を立てたい」「ユーザーストーリーを書きたい」
  「技術的に実現できるか確認したい」「機能設計を書きたい」「issue に落としたい」などで起動。
  docs/ の状態から途中再開・特定フェーズの部分実行も可能。
  `cli` / `webapp` のプロダクトモード指定で CLI ツール開発時は UI スケッチ等を軽量化できる。
  issue 作成後、/dev-impl がそれを 1 件ずつ実装する。
argument-hint: "[cli|webapp] [タスク説明]"
---

# dev-spec — 設計ループ

## 概要

設計ループを回して docs/ 配下に設計成果物を生成し、GitHub issue に落として実装ループ (`/dev-impl`) に引き渡す。成果物は 3 種:

- **docs/DESIGN.md** (横断設計 1 枚): 目的・アーキテクチャ・開発検証コマンド・スキーマ・API 一覧・横断規約
- **docs/features/<機能名>.md** (機能設計): 機能単位の入出力・API・実装配置・エッジケース・テスト方針。**正本は常に docs 側で、issue は参照するだけ** (ローカルで「この機能の設計はどうなっているか」を AI にも人間にも引ける)
- **GitHub issue**: 親 1 件 (トラッキング) + 子 N 件 (作業単位)。**人間が issue 本文 + 参照 docs だけで着手できる**ことが情報設計の基準

フェーズごとに Feedback (検証手段) が異なる:

- 要件・設計の妥当性 → **人間の確認** (AskUserQuestion) + **fresh context の検査 subagent** (フェーズ 8・9)
- 技術的実現可能性 → **PoC の実行結果** (tech-investigation subagent)。「できるはず」という自己申告のまま設計に進むことを禁止する

### モデルガード

このスキルは賢いモデル (Fable / Opus) のセッションで実行する前提。起動時にセッションモデルを確認し、Sonnet / Haiku なら「設計ループは高知能モデルでの実行を推奨します。このまま続行しますか?」と警告してから進める (強制はしない)。

## プロダクトモード

設計対象がブラウザ操作型か CLI/ターミナル型かを表す横断設定。フェーズ 2 (UI スケッチ) の要否と E2E 検証の中身を左右する。

| モード   | 対象                                             | 判定ヒント                                               |
| -------- | ------------------------------------------------ | -------------------------------------------------------- |
| `webapp` | ブラウザで操作するプロダクト (モバイル Web 含む) | 「画面」「サイト」「Web」「SPA」「ダッシュボード」等の語 |
| `cli`    | ターミナルから実行するプロダクト (TUI 含む)      | 「CLI」「コマンド」「ツール」「TUI」「パイプ」等の語     |

**判定と保持**: モードは docs/DESIGN.md の 1 行目に `<!-- product-mode: cli -->` (または `webapp`) の形式でスタンプする (フェーズ 6 が新規生成時に必ず書き込む)。判定コマンド:

```bash
sed -nE 's/.*<!-- product-mode: (cli|webapp) -->.*/\1/p' docs/DESIGN.md | head -1
```

dev-impl はこのスタンプで UI の実機検証 (Playwright E2E) の要否を切り替える。

**クイックモードとの合成規則**: 各フェーズの有効・無効は「クイックモード列を適用 → cli モード列を適用」の順で決める。どちらか一方でも「スキップ」ならスキップする。フェーズ 4・5 の条件は「フェーズ 0.3 の不確実性確認の結果 (あり/なし)」。

## フェーズ一覧

**フェーズを開始するときに該当手順書を Read し、その手順に従う。**

| #  | フェーズ                          | 手順書                              | 出力                               | クイックモード | cli モード |
| -- | --------------------------------- | ----------------------------------- | ---------------------------------- | -------------- | ---------- |
| 1  | ユーザーストーリー                | `references/user-story.md`          | docs/USER_STORIES.md               | スキップ       | 実行       |
| 2  | UI スケッチ                       | `references/ui-sketch.md`           | docs/UI_SKETCH.html                | スキップ       | スキップ   |
| 3  | ユースケース記述                  | `references/usecase-description.md` | docs/USECASES.md                   | スキップ       | 実行       |
| 4  | 実現可能性検証                    | `references/feasibility-check.md`   | docs/FEASIBILITY.md (PoC 計画)     | 条件付き実行   | 実行       |
| 5  | PoC 検証                          | `references/poc-verification.md`    | FEASIBILITY.md 更新 (PoC 結果)     | 条件付き実行   | 実行       |
| 6  | 横断設計                          | `references/design-doc.md`          | docs/DESIGN.md                     | 実行           | 実行       |
| 7  | 機能設計                          | `references/feature-doc.md`         | docs/features/<機能名>.md          | 実行           | 実行       |
| 8  | 設計チェック                      | (本ファイル下記)                    | 指摘の反映 (docs 修正)             | 実行           | 実行       |
| 9  | issue ドラフト + ドラフトチェック | `references/issue-template.md`      | ドラフト (scratchpad) + 指摘の反映 | 実行           | 実行       |
| 10 | GitHub issue 生成                 | `references/issue-template.md`      | 親 issue 1 件 + 子 issue N 件      | 実行           | 実行       |

**フェーズ 10 はモードに関係なく常に実行する** (実装ループは issue を入力にとる)。進捗表示の分母は 10。

### ゲート条件 (フェーズ 6 の開始条件)

FEASIBILITY.md に **`blocker=true` の未解決 PoC 計画が残っている間は、フェーズ 6 (設計書生成) に進んではならない**。判定はプロンプト遵守ではなく次のコマンドで機械的に行う:

```bash
rg -n 'POC_STATUS:.*blocker=true.*status=unresolved' docs/FEASIBILITY.md
```

- 1 件以上ヒット → フェーズ 5 (PoC 検証) へ戻る
- 0 件 → 通過
- FEASIBILITY.md 自体が無い → フェーズ 0.3 で「不確実性なし」を確認済みの場合のみ通過。未確認ならフェーズ 0.3 の不確実性確認に戻る

`POC_STATUS` 行の書式は `references/poc-verification.md` で定義する (フェーズ 4 が `status=unresolved` で書き、フェーズ 5 が更新する)。

## フェーズ 0: ルーティング

### 0.1 タスク説明とプロダクトモードの取得

`$ARGUMENTS` の先頭トークン群のうち、`cli` / `webapp` に完全一致するものは**プロダクトモード**として消費し、残りをタスク説明とする。タスク説明が無ければ事前の会話から推論し、それも不明なら「どのようなタスクの設計を行いますか?」と質問する。

**既存の docs から復元できる項目は質問しない。** `docs/DESIGN.md` があればプロダクトモードはスタンプから復元する。トークン指定も復元もできない場合だけ、タスク説明と会話履歴から推論し、推論結果を推奨ラベル (`(推論)` + 根拠 1 行) にして AskUserQuestion で確認する (確定済みなら呼ばない)。

### 0.2 既存ドキュメントの確認と開始点の決定

docs/ 配下の既存成果物 (USER_STORIES.md / UI_SKETCH.html / USECASES.md / FEASIBILITY.md / DESIGN.md / features/) と、GitHub 上の親 issue (`tracking` ラベル) を確認する (先に `gh auth status` を確認し、未認証なら issue 関連の判定はスキップして「フェーズ 10 までに認証が必要」と伝える)。

旧構成の成果物 (DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md / DOMAIN_MODEL.md / TODO.md) を見つけたら、本スキルの対象外であることを伝え、「新構成 (DESIGN.md 1 枚 + features/) で設計し直す / 中止」を確認する。旧成果物は読み取りの参考にはするが更新しない。

途中まで存在する場合は「続きから (推奨) / 最初から / 既存を更新」を AskUserQuestion で確認する。「続きから」の再開フェーズは次の表で決める (存在する成果物のうち最も下流のものを見る):

| 最も下流の既存成果物                        | 再開フェーズ                                                   |
| ------------------------------------------- | -------------------------------------------------------------- |
| USER_STORIES.md                             | 2 (UI スケッチ)。cli モードでは 3                              |
| UI_SKETCH.html                              | 3 (ユースケース)                                               |
| USECASES.md                                 | 4 (実現可能性)                                                 |
| FEASIBILITY.md (blocker=true が unresolved) | 5 (PoC 検証)                                                   |
| FEASIBILITY.md (全件解決済み)               | 6 (横断設計)                                                   |
| DESIGN.md                                   | 7 (機能設計)。features/ 各ファイルの「対象 UC」と USECASES.md の UC 一覧を突合し、全 UC がカバー済みなら 8 (USECASES.md が無い構成では人間に確認する) |
| GitHub に親 issue (`tracking`) がある       | 9 (ドラフトを docs から再生成) → 10。ドラフトはセッション固有の scratchpad にしか無く、10 単独では突き合わせの比較元が無い |

更新モードでは既存ドキュメントを読み取って差分のみ更新し、ファイル先頭に変更履歴コメント (`<!-- 変更履歴 [YYYY-MM-DD]: 要約 -->`) を追記する (DESIGN.md ではスタンプ行を押し出さず 1 行目に保つ)。**概念の追加・削除を含む更新では該当節だけの局所 Edit にせず全文を読み直して書き直し、更新後はフェーズ 8 (設計チェック) を再実行する。**

### 0.3 モード選択

```javascript
AskUserQuestion({
  questions: [{
    question: "設計ループの回し方を選んでください",
    header: "モード",
    options: [
      { label: "フルコース", description: "ユーザーストーリー〜issue 生成まで全フェーズ (1〜10)。新規プロダクト・大きい機能向け" },
      { label: "クイック", description: "タスク説明から設計書 + issue を直接生成 (6〜10)。技術的な不確実性がある場合のみ実現可能性検証 + PoC (4〜5) を先に通す" }
    ],
    multiSelect: false
  }]
})
```

クイック選択時は、まず Claude 自身がタスク説明と会話履歴から不確実性候補 (未経験ライブラリ / 外部 API 連携 / 性能・スケール懸念 / 新しいプラットフォーム機能) を走査して列挙し、その候補を提示した上で「これらを含め、成立するか未検証の技術要素はありますか?」と AskUserQuestion で確認する (人間の記憶だけに頼らない)。あればフェーズ 4 → 5 を実行してから 6 へ、なければ 6 から開始する (この「不確実性なし」の確認が、ゲート条件の「FEASIBILITY.md 無し」通過の根拠になる)。

### 部分実行

依頼が特定フェーズだけを指す場合 (例: 「ユースケースを詳細化したい」「機能設計だけ書き直したい」「issue を作り直したい」) は、全フェーズを回さず該当フェーズの手順書だけを Read して実行する。**ただし対象にフェーズ 6 が含まれる場合は、実行前に必ず「ゲート条件」の判定コマンドを実行する。** docs を修正する部分実行の後は、フェーズ 8 (設計チェック) → 9 (ドラフト再生成 + ドラフトチェック) → 10 の順で issue に反映する (フェーズ 10 の突き合わせが本文差分を検出して貼り直す)。対象がフェーズ 2 (UI スケッチ) で cli モードなら「cli モードでは UI スケッチは対象外です」と案内して終了する。

## 各フェーズの進め方

1. 進捗を表示する。スキップしたフェーズは `⊘` で表示し番号は振り直さない:

```
📍 設計ループ [n/10]
   ├─ ✓ user-story（完了）
   ├─ ⊘ ui-sketch（cli モードのためスキップ）
   ├─ ▶ usecase-description（実行中）
   └─ ○ ...
```

2. 手順書を Read し、手順に従って実行する
3. フェーズ完了後、AskUserQuestion で「次へ進む / ここで終了」を確認する
4. ユーザーが修正内容を入力した場合は反映して再承認を取る (承認されるまで繰り返す)
5. フェーズ 6・7 では、プロダクト判断が要る点をその場で AskUserQuestion で確認しながら書く (独立したインタビューフェーズは無い。聞き方の基準は各手順書の「記入基準」)

## フェーズ 8: 設計チェック (fresh context)

docs が完成した時点で、書き手と別コンテキストの subagent に全文を突合させる。書き手自身は「定義したつもり」バイアスで漏れ・矛盾を検出できないため。**issue 生成の前に行う** — 設計の穴は issue 化してから見つかるほど手戻りが大きい。

`general-purpose` subagent を **`model: "opus"` 明示**で 1 本起動する (機能設計書が 8 本を超える場合は機能ごとに分担させて並列 fan-out し、横断の整合は親がまとめる)。指示文に含める内容:

> docs/USECASES.md (あれば)・docs/DESIGN.md・docs/features/*.md を**全文 Read** し、次を検査して指摘だけを返せ (修正はしない):
>
> 1. **落とし漏れ**: USECASES.md の各 UC・各規則 (BR) が、いずれかの機能設計書でカバーされているか
> 2. **矛盾**: 機能設計書どうし、および DESIGN.md との食い違い (スキーマと入出力、API 一覧と各機能の API 節)
> 3. **未定義・参照切れ**: 使われている用語・テーブル・エンドポイント・節参照に定義があるか。「後述」「別途定義」のまま宙に浮いた参照が無いか
> 4. **エッジケースの妥当性**: 明らかに起こるのに決定が書かれていないエッジケース
> 5. **開発・検証コマンドの実在**: DESIGN.md「開発・検証コマンド」が現リポジトリで実行可能か (可能なら実行して確かめる)
>
> 出力: `[severity] 該当箇所 / 問題の一文 / 修正案の一文` (severity: high = 実装が詰まる / medium = 曖昧さが残る / low = 可読性)

結果の分岐 (**最大 2 周**): high があれば該当 docs を修正して再実行。2 周しても残る high は人間に提示して判断を仰ぐ。high が無ければ (medium/low は反映するか判断してから) フェーズ 9 へ。subagent がエラーの場合は未検査のまま進まず、「再試行 / チェックなしで続行 / 中止」を AskUserQuestion で確認する。

## フェーズ 9: issue ドラフト + ドラフトチェック

`references/issue-template.md` を Read し、テンプレートに従って**親 1 件 + 子 N 件のドラフトを scratchpad にファイルとして書き出す** (まだ GitHub に作らない)。再実行時 (issue への反映・別セッションからの再開) もドラフトは docs から再生成する — 前セッションの scratchpad は残っていない。作業単位の切り方: 1 issue = 独立して検証可能な 1 単位 (機能 1 つ、または機能を構成する縦切りの 1 段)。依存は最小限にし、並行して着手できる形を優先する。

全ドラフトが揃ったら、`general-purpose` subagent (**`model: "opus"` 明示**、fresh context) を **1 本だけ**起動し、親 + 子の全ドラフトを一括で検査させる (issue ごとに個別起動しない — 依存の整合と相互の重複・漏れはセット全体を見ないと検査できない)。検査観点は issue-template.md「ドラフトチェックのチェックリスト」の 5 項目を指示文に転記し、機能設計書と DESIGN.md のパスを渡して照合させる。出力形式はフェーズ 8 と同じ。

分岐も同じ (**最大 2 周**): high は修正して再実行、2 周で残れば人間に提示、無ければフェーズ 10 へ。

## フェーズ 10: GitHub issue 生成

`references/issue-template.md` の「issue 作成手順」に従う。要点:

1. **docs をコミットする**: docs/ 配下の成果物 (DESIGN.md / features/ ほか。ただし `docs/PENDING_REVIEW.html` は対象外 — dev-impl が管理する) の変更を Conventional Commit でコミットする (コミット実行の委譲は `~/.claude/rules/core/orchestration.md` に従う)。**/dev-impl は origin から切ったブランチで docs を読むため、実装開始前にこのコミットの push が必要** — 手順 4 の案内に含める

2. **作成前に人間の同意を取る** (GitHub への書き込みなので):

```javascript
AskUserQuestion({
  questions: [{
    question: "issue を作成してよいですか? (ドラフトチェック済み)",
    header: "issue 作成",
    options: [
      { label: "作成", description: "<owner/name> に子 issue <n> 件 + 親 issue 1 件を作成し、sub-issue として紐付ける" },
      { label: "ドラフトを見せて", description: "ドラフト全文を表示してから再確認" },
      { label: "中止", description: "ここで終了 (docs とドラフトは残る。issue は作成しない)" }
    ],
    multiSelect: false
  }]
})
```

3. 手順書どおり作成する: ラベル用意 → 既存 issue との突き合わせ (冪等) → 親の特定/作成 → 子を依存順に作成 → sub-issue 紐付け → 親本文の確定
4. 結果を報告し、次を案内する:

```
✓ issue を作成しました: 親 #<番号> + 子 <n> 件 (新規 <a> / 更新 <b> / スキップ <c>)

GitHub で issue をざっと確認し、docs のコミットを push してください (/dev-impl は origin の docs を読みます)。問題がなければ実装ループを起動します:

A (推奨): 新しいセッションで起動 — 対象リポジトリで claude を開き /dev-impl を実行
   (設計の対話履歴を持ち込まず、クリーンなコンテキストで実装ループが回る)
B: このセッションで続行 — このまま /dev-impl とタイプ

修正したい issue があれば、指摘してください (docs を直してフェーズ 8 → 9 → 10 で issue に反映します)。
```

**実装ループを Skill ツールで自動起動しない** — issue を人間が確認して GO を出すことが承認であり、`/dev-impl` はユーザーが起動する。

## 完了条件

- [ ] 対象フェーズがすべて実行された (またはユーザー判断でスキップ)
- [ ] blocker=true の PoC 計画がすべて解決済み (`verified` / `fallback_adopted` / `scope_reduced` のいずれか)
- [ ] docs/DESIGN.md と docs/features/ が生成され、フェーズ 8 の設計チェックを通過した (high 0 件、または未解消のまま人間判断に提示済み)
- [ ] 全ドラフトがフェーズ 9 のドラフトチェックを通過した
- [ ] 親 issue 1 件 + 子 issue 全件が作成され、全子が親に sub-issue として紐付いた (issue-template.md の最終報告の形式で報告した)

## 参照ルール

設計・タスク分解で以下を参照する:

- TDD ルール: `~/.claude/rules/core/tdd.md`
- 設計原則: `~/.claude/rules/core/design.md`
- テスト方針: `~/.claude/rules/core/testing.md`

## 関連スキル・エージェント

- **dev-impl**: issue 駆動の逐次実装ループ。フェーズ 10 が issue を作った後、ユーザーが起動する
- **tech-investigation** (subagent): フェーズ 5 の PoC 検証で並列 fan-out される
- **workflow-debate**: 設計判断の壁打ちが必要なとき
