---
name: dev-impl
description: 実装ループ。/dev-spec が作成した GitHub issue を入力に、依存順に 1 件ずつレビュー・コミット込みで自律実装するオーケストレーター。実装の指示は issue 本文 (ゴール / DoD / 参照 docs / 変更想定ファイル / 非スコープ) から取り、完了したら close する。人間の介入はエスカレ条件 (概要設計の破綻 P3 等) のみ。dev-spec の承認ゲート通過後にユーザーが直接起動する。エスカレーション回答後の再開も本スキルの再実行で行う。「実装ループを開始」「issue を順に実装して」「残りタスクを自動で実装」などで起動。
argument-hint: "[docs ディレクトリパス、省略時は docs/]"
model: opus
allowed-tools: Read, Edit, Write, Glob, Bash, Skill, Agent, AskUserQuestion
---

# dev-impl — 実装ループ

承認済みの設計 + TODO を入力に、open issue を依存順に最後まで自律的に実装するオーケストレーター。`dev-spec` の下流ステージ (= 設計と TODO が固まった後) を機械的に消化する役割。

人間の介入は **エスカレ条件** (検査 → 修正の周回が 3 回でも fatal 残存 / P3 検出など) でのみ発生する。それ以外は止まらず最後まで走る。

## 目次

- モデル方針
- 入力
- 参照ルール
- 進捗ログ (2 系統)
- 実行手順
- エスカレ停止時の挙動
- 既存プロジェクトでの注意
- 範囲外 (やらないこと)
- 関連スキル / agent

「実行手順」の内訳: Step 0 / Step 1 / Step 1.5 / Step 2 / Step 3 / Step 4 / Step 5 / Step 6 / Step 7

## モデル方針

- 本スキルは frontmatter で `model: opus` を指定している。モデル切り替えが効くのは**ユーザーが `/dev-impl` を直接起動したターンだけ** (Skill ツール経由の起動では適用されない)。エスカレーションに回答した後の再開も `/dev-impl` の再実行で行う (TODO.md の `- [x]` 状態から途中再開できるため、再実行で override が再適用される)
- **Agent ツールの呼び出しには例外なく `model` を明示する。** 未指定だと agent 定義の frontmatter ではなく**親のセッションモデルを継承**するため、最上位 tier のセッションでは haiku 指定の agent まで最上位単価で走る。

| subagent | model | 根拠 |
| --- | --- | --- |
| dev-impl-implementer (4.2a `mode: implement`) | `opus` | フェーズ 1 本を TDD で完結させる実装器 |
| dev-impl-implementer (4.2d `mode: fix`、ラウンド 1) | `opus` | fatal findings の修正。実装と同じ判断力を要する |
| dev-impl-implementer (4.2d `mode: fix`、ラウンド 2 以降) | `fable` | 1 ラウンドで閉じなかった fatal は局所修正では閉じない。下記「修正ラウンドのモデル昇格」参照 |
| architecture-guard (4.2c、最後の issue のみ) | `haiku` | 判定は `claude/scripts/layer-check.ts` が決定的に行い、agent はレイヤ定義の読み取りと報告だけを担う |
| fix-lsp-warnings (4.2b) | `haiku` | LSP が出した警告を規則どおりに潰す機械作業 |
| tech-investigation (Step 1.5 の個別呼び出し) | `opus` | 検証範囲の設計を自分で行う探索的な調査 |
| review-adversarial / review-tdd / review-quality / review-product-readiness (4.2c) | `opus` | 設計意図とテストの対応づけなど、規約の機械照合に還元されない判断を含む。adversarial の検出力を opus と sonnet で比較した経緯 → [references/orchestration-rationale.md](./references/orchestration-rationale.md) の `## review-adversarial のモデル選択の経緯` |
| review-spec-compliance (5.2) | `opus` | 承認ハッシュ照合と成果物 ↔ 詳細設計の突合を伴う受入監査 |

### 修正ラウンドのモデル昇格 (ラウンド 2 以降は `fable`)

**ラウンド 1 で解消しなかった fatal は、指摘箇所の局所修正では閉じない性質のものが多い** (実測の内訳 → [references/orchestration-rationale.md](./references/orchestration-rationale.md) の `## 修正ラウンドのモデル昇格の根拠`)。そこで**ラウンド 2 以降は `model: "fable"` に上げ、指示文で「指摘箇所を局所的に塞ぐ前に、当該箇所が属する不変条件を洗い出して族ごと閉じる」ことを求める** (指示文の全文は [references/phase-execution.md](./references/phase-execution.md) の `## 4.2d: 修正ラウンドの implementer 起動`)。ラウンド 3 でも解消しなければ従来どおり `phase_fix_exceeded` でエスカレ停止する — **モデルを上げても閉じない fatal は、実装の腕ではなく設計の問題である**可能性が高く、人間の判断を仰ぐべき局面だと見なす。`agent-spawn-guard` hook は model の未指定だけを弾き、規定と違う値でも明示されていれば意図的な override として通すので、この昇格に hook の改修は要らない。

### フェーズ実装を subagent に委譲する理由 (`rules/core/orchestration.md` の原則に対する dev-impl 限定の例外)

`rules/core/orchestration.md`「委譲の判断」は**逐次実装の subagent 委譲を禁止**している (固定費と報告往復で総トークン・時間とも増えるため)。dev-impl はこの原則の**唯一の例外**で、issue 1 件ずつの逐次実装であっても implementer subagent に出す。`rules/core/orchestration.md` 本体は変更しないので、他のタスクでは従来どおりメインループ直営で実装する。根拠は dev-impl だけが持つ「フェーズを 100 本単位で回す」性質にあり、実測値は [references/orchestration-rationale.md](./references/orchestration-rationale.md) の `## フェーズ実装を subagent に委譲する根拠` にある。

**implementer は葉であること (子 subagent を起動しないこと) が例外の前提条件**。葉性は指示文ではなく `claude/agents/dev-impl-implementer.md` の `tools` から `Agent` を除くことで構造的に強制する (subagent には親の hooks が届かないため、指示文では違反を検出できない)。

## 入力

`$ARGUMENTS` で docs ディレクトリパスが指定されていればそれを基点にする (省略時は `docs/`)。必須ファイルは `docs/DESIGN.md` (概要) / `docs/DESIGN_DETAIL_APP.md` (アプリ詳細) / `docs/DESIGN_DETAIL_INFRA.md` (インフラ詳細) / `docs/TODO.md` (タスクリスト、フェーズ単位)。詳細設計 2 ファイルが無ければ dev-spec のフォールバック (`../dev-spec/references/todo-generation.md`。旧形式 DESIGN_DETAIL.md からの分割移行 = フォールバック A、DESIGN.md からの抽出 = フォールバック B) でまず生成するよう促してから dev-impl 起動を再案内する。

## 参照ルール

TDD: `rules/core/tdd.md` / 設計原則: `rules/core/design.md` / テスト戦略: `rules/core/testing.md` / コミット規約: `rules/core/commit.md`

## 進捗ログ (2 系統)

**リアルタイム監視用の 1 行テキストログ**と**事後振り返り用の構造化 JSONL** を並走させる。各ステップの「開始 / 完了 / 動的修正 / エスカレ」発生時に両方へ同期して書き込む (1 行ログ = summary のみ、JSONL = summary + context を構造化)。終了時に JSONL から HTML レポート (Step 7) を生成する。`START_SHA` は Step 5.2 の監査 agent 呼び出し ([references/goal-audit.md](./references/goal-audit.md)) と Step 6 の完了サマリ ([references/notification-template.md](./references/notification-template.md) の `## 完了サマリ (Step 6)`) から参照される (エスカレ停止通知が使うのは `<SHA>` と `<PHASE_START_SHA>` で、`START_SHA` は使わない)。

- **run スコープの変数は Step 0 の再入判定を済ませてから確定する** (再入なら `run_id` を引き継ぐので、先に発行すると捨てる羽目になる)
- **シェル変数は Bash ツールの呼び出しをまたいで消える。** run スコープの値は `$RUN_DIR/env.sh`、フェーズスコープの値 (`PHASE` / `PHASE_NAME` / `PHASE_ID` / `PHASE_START_SHA` / `SCRATCH_DIR` / `ISSUE`) は Step 4.1 で `$SCRATCH_DIR/env.sh` に書き、各ブロックの冒頭で両方を `source` して再確立する
- **`ROUND` とカウンタは env.sh に書かない** (ラウンドごとに変わる値で、フェーズ開始時に 1 度書く env.sh の性質と合わない)。カウンタは `spawn` イベントの件数から数え直す。**導出式の正は [references/run-bootstrap.md](./references/run-bootstrap.md) の `## Step 0: カウンタ・予算・gating_decided の復元`** で、本文でも logging.md でも再定義しない
- **`$HOME` を使い、`~` を変数に入れない。** `~` はシェルの展開に依存するので、subagent への受け渡しや `jq --arg` を経由すると文字列 `~/...` のまま渡り、存在しないパスを指す

**「Agent の起動をまたいで比較する値」は env.sh ではなく専用のファイルに落とす。** 該当するのは次の 3 つで、**いずれも「取った時点」と「使う時点」の間に必ず Agent の待ちが挟まる**:

| 値 | 置き場 | 取る時点 → 使う時点 |
| --- | --- | --- |
| `BEFORE_FIX` / `BEFORE` (ラウンド前の HEAD) | `$SCRATCH_DIR/before-<round>.sha` | implementer を起動する直前 → 報告受領後の完了判定と「fix がテストに触れたか」 |
| `SPAWN_EPOCH` (起動時刻) | `$SCRATCH_DIR/spawn-<agent>-<round>.epoch` | Agent 起動の直前 → 30 分タイムアウトの判定 |
| `EXEMPTIONS_COUNT` | `$SCRATCH_DIR/self-exemptions.json` から都度算出 | 4.2c → 4.2d 手順 1 |

**読み出し側は「ファイルが無い」を沈黙で通さない** (`[ -f "$f" ] || exit 1` を必ず置く)。無いまま進むと、たとえば「fix がテストに触れたか」の判定が `git diff` の失敗を経て 0 件 (= 触れていない) を返し、**reward hacking を守るためのゲートが沈黙して開く**。

env.sh の生成コマンドと専用ファイルの詳細規律は [references/run-bootstrap.md](./references/run-bootstrap.md) の `## run スコープ変数と env.sh の生成` / `## フェーズスコープ変数と専用ファイルの規律` を Read してから実行する (**既存の env.sh を作り直すと `START_SHA` が再入時点の HEAD で上書きされ**、run 全体の開始 SHA を失う)。書式・JSONL スキーマ・書き込みコマンド・実行ログの範例は [references/logging.md](./references/logging.md) を Read して従う。

## 実行手順

### Step 0: 再入チェック (エスカレ後の再開対応)

`~/.claude/logs/dev-impl/` の全 run を走査し、**同一プロジェクトで未完了の run** があれば再入モードで動く。判定は 2 条件の AND — ① `event_type: start` の `context.repo_root` が現在の `git rev-parse --show-toplevel` と一致する (このディレクトリは全プロジェクト共通なので、パスで絞らないと他プロジェクトの run を拾う) ② **run 完了イベント `run_done` が無い** (Step 6 の完了サマリ出力時に 1 件だけ記録する専用の event_type)。判定スクリプトは [references/run-bootstrap.md](./references/run-bootstrap.md) の `## Step 0: 再入判定スクリプト` を Read してから実行する (**最新の 1 件だけを見る近似で代替すると**、他プロジェクトで dev-impl を回した直後に自分の未完了 run が最新ではなくなり、新規 run として起動してカウンタが 0 に戻る)。**センチネルに `done` を使わない** — `done` はステップ単位の完了にも使う値なので、run が未完了でも途中のステップ完了で真になる。

再入と判定したら次の 4 手順を行う。各手順の詳細は run-bootstrap.md の対応節を Read する:

1. **run_id とカウンタ・予算を引き継ぐ** (新規発行しない)。run 全体の `p2_fixes_total` / `goal_loop` / `run_spawns` / `run_spawns_budget` と、進行中フェーズの `phase_spawns` / `phase_fix_round` / `test_gate_retry` / `p1_fixes_in_phase` / `phase_spawns_budget` / `phase_fix_budget` / `gating_decided` を decisions.jsonl から復元する。**カウンタだけ復元して予算を復元しないと、上限を超えたカウンタだけが戻り、再入した瞬間に同じ理由で再停止する**
2. **進行中フェーズの突合**: `PHASE_START_SHA` の上に積まれた `[phase-<識別子>]` コミット列を提示し、AskUserQuestion で「続きとして取り込む / 捨ててフェーズをやり直す」を確認する (再入時 1 回だけの人間確認)。**捨てる場合の `git reset --hard` は、対象範囲の全件が `[phase-*]` prefix を持つことを確認してから打つ** — HTML レポートや設計書のコミットが同じ範囲に混ざるため
3. **TODO チェックの突合**: `- [x]` だが issue が open のフェーズは「最終コミットまでは済んだが close 未到達」として **4.2e の手順 3 から再開する** (手順 7 から再開しない)。`impl_done` の SHA を基準にしない
4. **Step 5 系の停止からの再開**: `goal_loop_exceeded` などゴール判定段階の停止では in-progress issue が無く駐車が使えないので、最後の `p3_escalate` を提示して AskUserQuestion で「対応済み / まだ」を確認する。**「対応済み」の回答があったときだけ `goal_loop` を 0 に戻す。Claude の判断で戻さない**

未完了 run が無ければ通常起動 (新規 run_id 発行) で Step 1 へ。

#### needs-human で駐車中の issue の再開

`needs-human` ラベルの open issue があれば、**着手する前に**その issue 番号・停止理由 (issue コメントに記録済み) をユーザーに提示し、AskUserQuestion で「解決した (ready に戻して着手する) / まだ (駐車したまま他の issue を進める) / 中止」を確認する。「解決した」を選ばれた場合だけ `gh issue edit <N> --add-label ready --remove-label needs-human` でラベルを戻す。**Claude の判断で勝手に外さない** — 駐車の解除は人間の回答が入ったことの証拠であり、ここを自動化すると停止条件が実質無効になる。

### Step 1: 前提ドキュメントの確認

`docs/DESIGN.md` / `docs/DESIGN_DETAIL_APP.md` / `docs/DESIGN_DETAIL_INFRA.md` / `docs/TODO.md` を Read する。

#### プロダクトモードの判定

run 全体で保持する `PRODUCT_MODE` を DESIGN.md のスタンプから判定する (以降のステップすべてがこの値を参照する):

```bash
PRODUCT_MODE=$(sed -nE 's/.*<!-- product-mode: (cli|webapp) -->.*/\1/p' docs/DESIGN.md | head -1)
PRODUCT_MODE=${PRODUCT_MODE:-unknown}
```

`cli` / `webapp` は dev-spec がスタンプを書いた新形式 docs。`unknown` (スタンプ不在の旧形式) では後方互換のため、UI 系判定を `dev_server` 推定 ([references/phase-context.md](./references/phase-context.md)) にフォールバックする。

#### GitHub の前提条件

**実装対象は GitHub issue** なので、docs の確認と同時に次を解決する。1 つでも失敗したらエスカレ停止し、「`/dev-spec` を先に実行して issue を作ってください」と案内する。確認コマンドは [references/run-bootstrap.md](./references/run-bootstrap.md) の `## Step 1: GitHub 前提条件の確認コマンド` を Read してから実行する (**`--limit` に張り付いていないことの確認を省くと**、上限ちょうどの件数が「全部取れた」と「切り捨てられた」のどちらか区別できず、見えない issue が未実装のまま「全 issue 完了済み」と判定されうる)。同節では `OPEN` / `CLOSED` の算出 (**`uc-tracking` の親 issue は数に入れない**)、`docs/.dev-impl/` の `.gitignore` 追記と単独コミット (Step 4 に入ってから追記すると `.gitignore` の変更がフェーズの差分に紛れ込む)、親 issue がある構成での「紐付けの差集合」の run ごと 1 回の実行 (前回 run が issue 作成直後・紐付け前に落ちた子を回収する唯一の経路) も併せて扱う。

`OPEN` が 0 で closed も 0 件なら **issue が未生成**である (`/dev-spec` のフェーズ 12 が走っていない)。`OPEN` が 0 で closed が 1 件以上なら**全 issue 完了済み**なので Step 5 (ゴール達成判定) から再開する。**`OPEN` が確定したこの時点で `run_spawns_budget` を確定する。式は Step 3 の「spawn 予算の意図」の更新表が正**で、ここでは繰り返さない (2 箇所に式を書くと片方だけが更新されて食い違う)。確定した値は JSONL の `start` の `context` に記録する。**再入で予算を足さないと、前回が `spawn_budget_exceeded` で止まっていた場合に再実行が構造的に何も解決しない**。

#### 不在時の挙動

判定表は [references/run-bootstrap.md](./references/run-bootstrap.md) の `## Step 1: 前提ファイル不在時の挙動` を Read して従う。

#### 構造ゲート (fail fast)

ファイルが揃っていても、以下に欠けがあれば**実装に入らずエスカレ停止**する (全フェーズ実装後に発覚しても手遅れなので、起動時に機械判定する)。判定表は [references/run-bootstrap.md](./references/run-bootstrap.md) の `## Step 1: 構造ゲートの判定表`、**ゴール行の抽出コマンドと 1:1 照合コマンド**は同ファイルの `## Step 1: ゴール行の抽出と 1:1 照合` を Read して使う (**表のセルに埋めない** — Markdown の表セルではパイプを `\|` にエスケープする必要があり、それがそのまま正規表現へ渡ると「リテラルのパイプ文字」を要求する。実測で、ゴールが 13 行ある DESIGN.md に対して表セル形のコマンドは 0 件、エスケープを外すと 13 件を返した)。

承認ハッシュの再計算コマンド (dev-spec 11.3 の生成と同一定義。P2 ガードでも使う)。**この 2 本の正規表現は `skills/dev-spec/SKILL.md` の生成側および `agents/review-spec-compliance.md` の独立照合側と 1 文字も違えてはならない** — ハッシュはバイト比較なので、抽出される行が 1 行でも違えば承認スタンプと一致せず `approval_stale` が常に発火する。**上のゴール行の抽出とは別物**で、あちらはゴールの存在と 1:1 の照合に使う (ハッシュには関わらないので書き方が違ってよい):

```bash
GOALS_SHA=$(
  {
    rg --no-filename '^- G[0-9]+:|^G[0-9]+:|^- G_E2E:|^G_E2E:' docs/DESIGN.md
    rg --no-filename '^- G[0-9]+ 検証|^G[0-9]+ 検証|^- G_E2E 検証|^G_E2E 検証' docs/DESIGN_DETAIL_APP.md docs/DESIGN_DETAIL_INFRA.md
  } | shasum -a 256 | cut -d' ' -f1
)
```

### Step 1.5: 未解決 PoC マーカーの残存ガード

技術検証 (PoC) は前段の dev-spec フェーズ 5 で完了していることが前提。ここでは未解決マーカーの残存だけを機械チェックする:

```bash
rg -n '<!-- POC_NEEDED: .* -->' docs/DESIGN.md docs/DESIGN_DETAIL_APP.md docs/DESIGN_DETAIL_INFRA.md
```

判定表は [references/run-bootstrap.md](./references/run-bootstrap.md) の `## Step 1.5: PoC マーカー検出結果の分岐` を Read して従う。

### Step 2: issue の抽出と着手順の決定

以下で使う `$REPO_SLUG` / `$LIMIT` は Step 1 で確定し `$RUN_DIR/env.sh` に入っている (定義は [references/run-bootstrap.md](./references/run-bootstrap.md) の `## run スコープ変数と env.sh の生成`)。**実装の単位は GitHub issue** であり、**着手対象の抽出に TODO.md は使わない** (issue はフェーズ 12 が TODO.md から転記したもので、着手順と進捗の原本は GitHub の側にある)。TODO.md は Step 1 で読み、4.2e のチェック更新と P1 動的修正の書き込み先としては引き続き使う。

```bash
gh issue list --repo "$REPO_SLUG" --state open  --limit $LIMIT --json number,title,labels,body > "$RUN_DIR/issues-open.json"
gh issue list --repo "$REPO_SLUG" --state closed --limit $LIMIT --json number --jq '[.[].number]' > "$RUN_DIR/issues-closed.json"
```

以降の着手判定と `Depends on #N` の closed 判定は、この 2 ファイルを `jq` で引く (`gh` を再実行しない)。取得した open issue には UC 親 issue も混ざる。下表の 1 行目 (`uc-tracking`) で先に除外してから着手判定に入る。

| 条件 | 扱い |
| --- | --- |
| `uc-tracking` ラベルが付いている | **着手対象外。** ユースケース単位の親 issue (俯瞰用) であり、実装の実体を持たない。ラベル判定はこの行を**最初に**適用する (親はライフサイクルラベルを持たないため、次行以降の「ラベルが無い open issue」に流すと未完成と誤判定する) |
| `needs-human` ラベルが付いている | **着手しない。** 駐車中の issue であり、ラベルを外すのは人間の回答を得た後 |
| `ready` ラベル | 着手可能な候補 |
| `in-progress` ラベル | 前回の run が中断したもの。**Step 0 が decisions.jsonl から run 記録を復元できた場合だけそのまま再開する。** 対応する run 記録が無い (別マシン・別クローン・ログ削除後) 場合は未着手とみなし、`gh issue edit <N> --add-label ready --remove-label in-progress` でラベルを戻してから通常フローで着手する |
| ラベルが無い open issue (`uc-tracking` でもない) | フェーズ 12 が作成直後に落ちた未完成の issue。`issue_incomplete` でエスカレ停止し、`/dev-spec` の再実行 (12.3 の突き合わせが冪等に貼り直す) を案内する |

候補のうち、本文の `## 依存` にある **`Depends on #N` の参照先がすべて closed になっているものだけが着手可能**。複数あれば issue 番号の昇順で 1 件選ぶ。**並列化はしない** — 1 件実装して close し、次の判定に戻る、を繰り返す (wave / worktree fan-out は持たない)。着手可能な issue が 1 件も無いのに open issue (`uc-tracking` を除く) が残っている場合は、依存の循環か、依存先が `needs-human` で駐車している。どちらかを判別して `dependency_blocked` でエスカレ停止する (JSONL の `context` に残りの issue 番号と各々の未解決依存を残す)。

### Step 3: ループ全体の状態管理

以下の counter を保持して各フェーズで参照する (dev-impl 開始時に 0 で初期化):

| カウンタ                                        | 上限                                                      | 超過時の挙動                                    |
| ----------------------------------------------- | --------------------------------------------------------- | ----------------------------------------------- |
| `p1_fixes_in_phase` (現フェーズ内 P1 修正回数)  | 2 (回)                                                    | P2 として扱う (次のループでは P2 として処理)    |
| `p2_fixes_total` (dev-impl 全体の P2 修正回数)  | なし (上限を設けない)                                     | 停止しない。件数と内訳を記録し Step 6 で提示する |
| `goal_loop` (ゴール達成判定 → 未達対応の周回数) | 2 (周)                                                    | P3 として停止                                   |
| `phase_fix_round` (現フェーズの検査 → 修正の周回数) | `phase_fix_budget` (既定 3。**再入時は `max(3, 復元値 + 1)` に引き上げ、フェーズの `start` イベントの `context.phase_fix_budget` に記録する。復元は記録値の最大**) | `phase_fix_exceeded` でエスカレ停止 (context に guard 由来 / review 由来の内訳を残す) |
| `test_gate_retry` (現フェーズの 4.2e テストゲート再試行回数) | 3 (回)                                       | `tests_failing_before_commit` でエスカレ停止    |
| `phase_spawns` (現フェーズの累計 subagent 起動数) | `phase_spawns_budget` (既定 33 (spawn)。**再入時は `max(33, 復元値 + 16)` に引き上げ、フェーズの `start` イベントの `context.phase_spawns_budget` に記録する。復元は記録値の最大**) — `spawn_budget_exceeded` は「再実行で解決しうる」停止で、復元されたカウンタが上限を超えたままだと再実行が構造的に何も解決しない (`run_spawns_budget` と同じ理由。16 は fix 1 + 再検査 5 の 2 ラウンド分 + 予備) | `spawn_budget_exceeded` でエスカレ停止          |
| `run_spawns` (run 全体の累計 subagent 起動数)   | `run_spawns_budget` (下記「spawn 予算の意図」で定義)      | 同上                                            |

**再入で予算が増える 3 つ (`phase_fix_budget` / `phase_spawns_budget` / `run_spawns_budget`) は同じ理屈で動く。** いずれの停止理由も「再実行で解決しうる」か「人間が対応した後に再開する」ものなので、**再入しても予算が一切増えないなら再実行が構造的に何も解決できず、即座に同じ理由で再停止する**。予算の追加付与を人間の再起動に紐づけることで、1 セッション内の暴走は有限の予算で止めたまま、人間の判断を挟んだ継続だけが前進する。`phase_fix_budget` の増分が **+1** なのは `phase_fix_exceeded` が `needs-human` に分類される停止だからで、人間が 1 回対応したら 1 ラウンド分だけ直す余地を与える対応付けにしてある。

スコープ別のリセット時点:

| スコープ | カウンタ | リセット時点 |
| --- | --- | --- |
| issue | `p1_fixes_in_phase` / `phase_fix_round` / `test_gate_retry` / `phase_spawns` | **その issue の Step 4.1 (最初の subagent を起動する前)** |
| run 全体 | `p2_fixes_total` / `goal_loop` / `run_spawns` | リセットしない。**再入時は Step 0 で decisions.jsonl から復元した値を初期値にする** |
| run 全体 (上限値) | `run_spawns_budget` | リセットしない。**上方向にのみ再計算する** (更新時点は下記「spawn 予算の意図」の表。issue が close されても下げない) |

**run 全体の経過時間では打ち切らない。** 発散は試行回数の上限で止める。長時間走ること自体はフェーズ数の多いプロジェクトでは正常であり停止理由にしない。個々の subagent が応答しないケースは **spawn からの経過時間**で打ち切る (4.2a)。カウンタと findings / deviation_signals の集約は**メインセッションが管理し**、現在値と集約結果は都度 1 行テキストログ + JSONL に書き出して外部化する (compaction をまたいでもログから状態を復元できるように)。

**spawn 予算の意図**:

- 1 フェーズは最小構成でも implementer 1 + review 1〜4 を起動し (最後の issue のフェーズは architecture-guard 1 が加わる)、フェーズ数だけ積み上がるため上限を機械ゲートとして置く。**`phase_spawns` の上限 33・`run_spawns` の上限係数 20 (spawn / issue) はいずれも実測から取った値**で、測定と算出の内訳は [references/orchestration-rationale.md](./references/orchestration-rationale.md) の `## spawn 予算の根拠` にある (値を変えるときはそこの実測と突き合わせる)
- **`run_spawns` の上限は `run_spawns_budget` という別の値で保持し、残作業ベースで上方向にのみ更新する。** 更新するのは次の 3 時点だけで、**issue が close されても下げない**:

  | 更新時点 | 計算 |
  | --- | --- |
  | 新規 run の開始時 (Step 1 で `OPEN` を数えた直後) | `run_spawns_budget = max(OPEN × 20 (spawn/issue), 16 (spawn))` (このとき `run_spawns` は 0) |
  | run 再入時 (Step 1 で `OPEN` を数えた直後) | `run_spawns_budget = max(復元値, run_spawns + OPEN × 20, run_spawns + 16)` |
  | issue 追加時 (P1 / P2 動的修正・Step 5.5) | `run_spawns_budget = max(現在値, run_spawns + その時点の OPEN × 20)` (Step 4.6「新フェーズの issue 化」手順 3) |

  `OPEN` はいずれも Step 1 で数える **`uc-tracking` を除いた実装対象の open issue 件数**を指す (親 issue は実装しないので予算を消費しない)。**下限 16 を置くのは `OPEN = 0` で Step 5 から再開する経路があるため**で、そのまま `OPEN × 20` を使うと予算が 0 になり監査 agent を 1 体も起動できない。16 は Step 5 の監査 2 体 + 未達対応ループ (`goal_loop` 上限 2 周 × 追加フェーズ 1 本) が回る最小限で、**係数とは独立に決まる**。

- **`OPEN × 20` を `run_spawns` と直接比べてはならない。** 前者は「これから使ってよい量」、後者は「すでに使った量」で単位が違う。直接比べると issue を close するたびに上限が下がり、**正常に完了した作業そのものが停止理由になる**。Step 5 では定義上 `OPEN` が 0 件になるため上限も 0 になり、監査 agent の起動が必ず上限違反になる
- `run_spawns_budget` は更新のたびに JSONL の `start` / `phase_added` の `context` に記録する。復元は記録済みの値の**最大**を採る (上方向にしか動かないので一意に決まる)
- **Agent ツールで subagent を起動する箇所は本スキルに 7 つある** — 4.2a / 4.2b / 4.2c / 4.2d 手順 4 / 4.2e のテストゲート再試行 / Step 5.2 / Step 1.5 の `tech-investigation`。**この 7 つすべてで、起動する直前に `event_type: spawn` を JSONL へ書き、`phase_spawns` / `run_spawns` を進める** (起動後に書く規定だと、待ちに入る直前の・前進を生まないログ 1 行だけが構造的に落ちる)。記録が欠けると予算判定が実態より小さい値で走るので、**4.2e 手順 4 の成果物との突合が二段目の歯止め**になる (成果物 JSON を出さない fix-lsp-warnings は補記でも拾えないため、一段目を落とさないことが要点)

### main のコンテキスト規律

**フェーズ実装を implementer に出しても、main がその成果物を読み返せば削減は消える。** 以下を守る:

| 規律 | 内容 |
| --- | --- |
| ソースを Read しない | フェーズの実装内容は implementer の報告要約と review findings 経由でのみ知る |
| `git diff` はパッチ本文を出さない | `--stat` / `--name-only` のみ。フルパッチを main のコンテキストに載せない |
| 検査結果 JSON は射影して読む | 全文 Read せず、[references/phase-execution.md](./references/phase-execution.md) の `## 4.2c: 検査 fan-out の起動` にある射影コマンドで読む。**表のセルにコマンドを埋めない** — Markdown の表ではパイプを `\|` にエスケープする必要があり、それをそのまま実行すると jq がコンパイルエラーになる (実測 exit 3)。射影が拾うのは fatal 判定と未検証判定に要る最小限で、`message` / `fix_proposal` は修正する implementer (`mode: fix`) が JSON を自分で Read するため main に載せない (実測: 全文 5,573 バイト = 約 1,400 トークン → 射影 約 60 トークン) |
| テスト出力は失敗時のみ | 失敗時の末尾 30 行まで。成功時は exit code だけ |
| subagent の最終メッセージを短くさせる | 検査 agent・implementer の呼び出し prompt に「最終メッセージは `output_path` (implementer は `report_path`) の絶対パス 1 行だけにせよ。要約や解説を書くな」を必ず含める。**agent 定義側に同じ規定があっても守られないことがある** (実測: `architecture-guard.md` は「stdout には output_path のみ」と規定しているが Markdown レポート全文が返り、1 ラウンドで約 2,250 トークンが main に流入した) |

例外 (main が実物を読んでよい場面): 4.2e のテスト弱体化のトレース確認、Step 4.6 の P2 判定での DESIGN_DETAIL 参照。

### Step 4: 各 issue の実行

Step 2 で選んだ issue を 1 件実装し、close してから Step 2 に戻る。**同時に複数の issue を走らせない。** implementer は main の working tree で直接編集し、統合の手順は無い (main がそのままコミットする)。骨格は「issue に `in-progress` を貼る → PHASE_CONTEXT を組み立てる → implementer 起動 → 待つ → 検査 fan-out 起動 → 待つ → 修正ラウンド → テストゲート → コミット → issue を close」。

**PHASE_CONTEXT の実装指示は issue 本文から組み立てる。** `## ゴール` / `## DoD` / `## 参照すべき docs` / `## 変更が想定されるファイル` / `## 非スコープ` / `## 実装タスク` をそのまま使う (節名は dev-spec のフェーズ 12 が固定している)。設計の抜粋が必要な場合だけ `## 参照すべき docs` が指す節を docs から読む。着手時と完了時の GitHub 操作:

```bash
gh issue edit <N> --repo "$REPO_SLUG" --add-label in-progress --remove-label ready
# ... 実装 ...
# 完了コミットの本文に `Fixes #<N>` を入れる (マージ不要でそのままブランチにコミットする運用なので、
# 自動クローズが効かない場合は明示的に閉じる)
gh issue close <N> --repo "$REPO_SLUG" --comment "DoD がすべて通過したため close する"
```

**子を close したら、続けて親 issue の自動 close sweep を回す** (4.2e の手順 7 → 8)。

**main が行うこと** (implementer には渡さない): PHASE_CONTEXT と RUN_FACTS の組み立て、事前判定と観点 gating の確定、検査 fan-out の起動と待機、fatal 判定、全テストゲート、テスト弱体化の機械検知、コミット、issue のラベル操作と close、decisions.jsonl への書き込み、Step 4.6 の P1/P2/P3 判定。

**完了判定は main が自分で行う。** implementer の `status: done` を完了根拠にせず、次の 2 点を main が確認する。何も実装せず `status: done` を返した場合に「差分ゼロ → 全テスト green → `- [x]` 化」まで素通りするのを防ぐための判定である:

- (a) **実装が実在すること** — 次の 3 つを**すべて**確認する。**`files_changed` が空でないことを先に見る** — 空配列に対する「全要素が差分に現れる」は空集合の包含として無条件に成立し、**この判定が防ぐと宣言している当のケースで空虚になる**:
  1. `files_changed` が**非空**であること。空なら `impl_report_invalid` として扱う (4.2a の分岐。`mode: implement` で再起動し、3 回で `phase_fix_exceeded`)
  2. `files_changed` の各パスが、実際に `git diff --name-only <PHASE_START_SHA>` + `git ls-files --others --exclude-standard` の結果に現れること
  3. そのラウンドのコミットで変更行数が実際に増えたこと。**起動の直前に `$SCRATCH_DIR/before-<round>.sha` へ落とした SHA と比較する** (`git diff --shortstat "$(cat "$SCRATCH_DIR/before-$ROUND.sha")" HEAD` が非空。ファイルが無ければ判定不能として `impl_report_invalid` に倒す)。working tree が非空であることだけでは足りない (`.gitignore` 追記や作業ファイルで非空になりうるため)
- (b) **fatal が 0 件であること** — 判定基準は 4.2d の fatal の定義に従う (review-* の high と architecture-guard の high/medium)

着手対象の各 issue について以下を順次実行する:


#### Step 4.1: フェーズ開始の SHA を記録

`PHASE_START_SHA=$(git rev-parse HEAD)` を取る。architecture-guard / review-* が「このフェーズの差分」を判定する基準点であり、中断したフェーズの提示 (`git log <SHA>..HEAD`) と破棄 (`git reset --hard <SHA>`) の起点でもある。

**再入で「続きとして取り込む」を選んだフェーズでは、新しく取らずに Step 0 手順 2 で復元した値をそのまま使う。** 中断時点までのラウンドが既にコミットされている以上、いま `HEAD` を取ると**そのフェーズが済ませた実装が全部フェーズ差分の外に出る** — 検査 agent には残りの差分しか見えず、テスト弱体化の機械検知も完了判定も、既存分を一切見ないまま「問題なし」を返す。再入の再開地点は 4.2c (検査 fan-out) からで、`SCRATCH_DIR` も前回のものを引き継ぐ (結果 JSON と report が残っているため)。

**この値を JSONL のフェーズ `start` イベントに必ず書く** (`context.phase_start_sha`)。**Step 0 手順 2 の復元元はこの記録だけ**で、書き忘れると再入時に「続きとして取り込む / 捨てる」の分岐が成立しない:

**まず変数を確定し、作業ファイル置き場 (`SCRATCH_DIR=$RUN_DIR/reviews/$PHASE`) を作り、`$SCRATCH_DIR/env.sh` に書き出してから、`start` イベントを書く。** 順序を守る — `SCRATCH_DIR` を作る前に env.sh は書けず、変数が未定義のまま `start` を書こうとすると `--argjson issue "$ISSUE"` が JSON パースエラーで落ちる。コマンドは [references/phase-execution.md](./references/phase-execution.md) の `## 4.1: フェーズ変数の確定と start イベント` を Read してから実行する (値の一覧と意味は同ファイルの `## 変数の定義`)。**`SCRATCH_DIR` はリポジトリの外に置く** — コミット対象への混入を防ぎ、エスカレ停止後の再入時にも残すため。

#### Step 4.1.5: PHASE_CONTEXT の組み立て

implementer と検査 subagent (architecture-guard / review-*) は parent のコンテキストを継承しないため、dev-impl が「フェーズ 1 本を実装・検査するのに必要な情報パッケージ」を組み立てて **`docs/.dev-impl/<run_id>/phase-<識別子>-context.md` に Write** する (`<識別子>` は issue タイトル `フェーズ<識別子>: <名前>` の `フェーズ` 直後からコロンまでの文字列。`1` だけでなく `4-a` のような接尾辞付きもある。タイトル形式は dev-spec のフェーズ 12.4.2 が固定している)。subagent には prompt にこのファイルの絶対パスだけを渡し、各 agent が必要な節を自分で Read する (1 フェーズあたり implementer 1 + 検査 subagent 最大 5 への同一内容の重複埋め込みを避けるため)。**このファイルが implementer にとってフェーズの唯一の入力になる**ので、抜粋の不足はそのまま実装の質に出る。**Write した直後に必須キーの充足を機械照合する** — `rg -c '^(product_mode|phase_name|phase_start_sha|phase_tasks|phase_test_command|full_test_command|gate_commands_verified|repo_state|related_rules_paths|run_facts_path):' <file>` が 10 件を返すこと。欠けたまま起動すると implementer は「書かれていない」と「調べていない」を区別できない。

`docs/.dev-impl/` は `.gitignore` に追加する (無ければ追記)。**追記が必要なら Step 1 の構造ゲート通過直後に行い、その時点で 1 度コミットする** — Step 4 に入ってから追記すると、`.gitignore` の変更自体が working tree の差分として残り、Step 4 の完了判定に紛れ込む。

#### RUN_FACTS.md の初期作成 (run の最初のフェーズのみ)

`docs/.dev-impl/<run_id>/RUN_FACTS.md` が無ければ、PHASE_CONTEXT を書く前に main が作成する。テンプレートと規則は [references/phase-context.md](./references/phase-context.md) の `## RUN_FACTS.md`。この時点で埋めるのは「プロジェクトコマンド」表だけで、他の節は見出しだけを置く (implementer が必ず Read する必須入力なので、不在ファイルを指さないようにするため)。「run の最初のフェーズか」は**ファイルの存在で判定する** (フェーズ番号や再入状態では判定しない) — 再入した run では前回作った RUN_FACTS.md が残っているので、再作成もコマンド再検証も走らない。

PHASE_CONTEXT の YAML テンプレートと抜粋ロジック (design 節の抜粋上限 4KB・dev_server 推定・poc_results の出典) は [references/phase-context.md](./references/phase-context.md) を Read して従う。組み立てたファイルの path は implementer (4.2a) と review-tdd / review-quality / review-product-readiness (4.2c) の prompt に**絶対パスで**渡し、**architecture-guard と review-adversarial には渡さない** (前者は入力仕様が `design_path` 等を取るため、後者は fresh context 監査のため)。受け渡しの一覧は同ファイルの `## 渡し方`。

#### Step 4.2: フェーズの実装と検査

##### 事前判定 (main)

`IS_NEOVIM_PLUGIN` は init.lua / lua ディレクトリ / plugin/*.lua の有無で決まる (4.2b の要否)。`uiPhase` は `phase_tasks` / フェーズ名の UI キーワード、または `related_source_files` のフロントエンド dir 有無で決まる (4.2c の観点 gating に使う)。**`PRODUCT_MODE=cli` では `uiPhase` を判定せず常に `false` 固定**とする (CLI 実装の「コマンド」「フラグ」等の語がキーワード判定に誤爆するのを防ぐ)。実行コマンドは [references/phase-execution.md](./references/phase-execution.md) の `## 4.2: 事前判定`。

**RUN_FACTS.md を新規作成したフェーズでのみ**、gate コマンド (`full_test_command` / `lint_command` / `format_command`) を main が 1 回実行して exit code を確認する。**未検証のコマンドを渡すと、implementer が自分の実装のせいで失敗していると誤認して発散する。** 結果を RUN_FACTS.md の「確認済み」列に書き、**その後で** PHASE_CONTEXT に `gate_commands_verified` を `true` (全コマンドが exit 0) / `false` で書く。2 フェーズ目以降は同列から引き継ぐ。

##### 4.2a: TDD 実装 (implementer subagent)

`dev-impl-implementer` を `model: "opus"` 明示で 1 フェーズにつき 1 つ起動し、**main は完了を待つ**。渡すのは `mode: implement` / `phase_context_path` / `repo_dir` / `report_path` と、最終メッセージを 1 行に制限する指示 (「main のコンテキスト規律」参照)。指示文の全文テンプレートは [references/phase-execution.md](./references/phase-execution.md) の `## 4.2a: implementer の起動`。implementer 側の規約 (TDD の順序、フェーズスコープのテストのみ実行、コミット・`docs/` 編集の禁止、報告 JSON のスキーマ、停止条件) は `claude/agents/dev-impl-implementer.md` に常駐しているので指示文で繰り返さない。

- **起動する直前に** `phase_spawns += 1` / `run_spawns += 1` し、JSONL に `event_type: spawn` を記録する (起動後に書く規定だと構造的に落ちる。理由は 4.2c の事前ブロック)
- **報告を受けたら main がその差分をコミットする** (下記「ラウンドごとのコミット」)
- 報告受領時に JSONL へ `event_type: impl_report` (context に要約 JSON + `report_path`) を記録する。**報告要約は main のコンテキストに載るが、全文 JSON は載せない** (P1/P2/P3 判定と JSONL 転記に必要なフィールドは `jq` で `report_path` から直接引く)
- `status: failed` の分岐表は [references/phase-execution.md](./references/phase-execution.md) の `## 4.2a: implementer が status: failed を返したときの分岐`

**fix ブリーフ**: `mode: fix` の implementer は `findings_paths` の JSON しか入力に取らないので、検査結果 JSON が存在しないこの経路でも main が同じ形式のファイル (`<SCRATCH_DIR>/impl-failure-<phase_fix_round>.json`) を書いて渡す。スキーマは [references/phase-execution.md](./references/phase-execution.md) の `## 4.2a / 4.2e: fix ブリーフのスキーマ`。`rule` には報告の `reason` (`tests_failing` / `spec_insufficient`) をそのまま入れる。4.2e のテストゲート失敗で書く `<SCRATCH_DIR>/test-failure-<test_gate_retry>.json` も同じスキーマ (`rule: "tests_failing_before_commit"`)。

**implementer が期待どおりに終わらなかった場合は、原因で 2 つに分ける** (混ぜると「フェーズ内で再起動する」のか「issue を駐車して次へ行く」のかが決まらない)。`impl_report_invalid` はフェーズ内で再起動し 3 回で `phase_fix_exceeded`、`impl_timeout` は run を止めず issue を `needs-human` で駐車して次へ進む。判定表は [references/phase-execution.md](./references/phase-execution.md) の `## 4.2a: implementer が期待どおりに終わらなかった場合の分岐`。どちらも検査 agent の `guard_agent_failed` / `review_agent_failed` と同じく**パス扱いにしない**。**`impl_timeout` は「エスカレ停止」ではない**ので、フェーズ内エスカレ条件の表にも停止条件のリストにも載せない (載せるのは `impl_report_invalid` から昇格した `phase_fix_exceeded` の側)。

##### ラウンドごとのコミット (4.2a / 4.2d 共通)

**implementer の報告を受けたら、その差分をその場で main がコミットする。** フェーズの終わりまでコミットを溜めない。溜めると実装が未追跡ファイルとして積み上がり、**検査 agent への差分の見せ方・作業ツリー汚染の検出・中断時の巻き戻しがいずれも「未追跡ファイルを相手にする特殊な操作」に化ける** (4.2c の clean 前提・4.2d 手順 8・Step 0 の巻き戻しは、いずれもラウンドごとにコミットされていることを前提に組んである)。

| 項目 | 規定 |
| --- | --- |
| 実行主体 | **main** (implementer ではない)。形式を機械検証する commit-msg-guard hook は親にしか効かないため |
| subject | `<emoji> <type>: [phase-<識別子>] <要約>`。`<要約>` は implementer 報告の `summary` を 1 行に詰めたもの |
| 識別子 | issue タイトル `フェーズ<識別子>: <名前>` の識別子。`$SCRATCH_DIR` のパスや `### フェーズ<識別子>:` 見出しと同じ値を使う |
| `[STRUCTURAL]` / `[BEHAVIORAL]` | **付けない。** 途中のコミットは「フェーズの実装の一部」であって、動作変更の有無を独立に語れる単位ではない。フェーズ最終コミット (4.2e) にだけ付ける |
| 本文 | `Refs #<issue 番号>` を入れる (close するのは 4.2e の最終コミットだけ) |
| コミットの条件 | **フェーズ範囲のテストが緑であることだけ。** 全体スイートは 4.2e で確認する (`rules/core/commit.md`「dev-impl のフェーズ内コミット」の例外規定) |

prefix を付けるのは `git log --oneline` でどのコミットがどのフェーズのものか目で追えるようにするため。フェーズ 1 本が 1 コミットではなくなるので、prefix が無いと履歴がフェーズ境界を失う。

##### 実装ノートの受け取り (design_decision / open_question)

implementer 報告の `design_decisions` (設計が沈黙・あいまいな箇所での自律判断) と `open_questions` (確信が持てずユーザの事後確認が必要な選択) を、main が JSONL に `event_type: design_decision` / `open_question` として**`report_path` から `jq` で転記する** (スキーマは [references/logging.md](./references/logging.md))。ループは止めない。これらは `deviation_signals` (設計と*矛盾する*変更) とは別物で、混ぜない。

##### 4.2b: LSP 警告修正 (Lua/Neovim のみ)

`IS_NEOVIM_PLUGIN=true` なら `fix-lsp-warnings` agent を `model: "haiku"` 明示で起動する (対象はフェーズ差分ファイルのみ)。**起動の直前に `spawn` を記録する。** 失敗は警告ログのみで継続し、`verification_skipped` (source: `lsp_fix_failed`) を記録する。**修正が入った場合** (`git -C "$REPO_DIR" status --porcelain` が非空。fix-lsp-warnings は結果 JSON を出さないので報告からは判定できず、ツリーの差分で見る) **は main が `phase_test_command` を再実行して緑を確認したうえでコミットする** (subject は `<emoji> style: [phase-<識別子>] LSP 警告を解消する`)。**コミットせずに 4.2c へ進んではならない** — 4.2c の clean 確認が必ず失敗し、「直前のラウンドのコミットが漏れている」という事実と違う診断を出す。**このステップだけは検査 fan-out に混ぜない** (修正する agent なので、レビューと同時に走らせるとレビュー対象のファイルが検査中に書き換わる)。

##### 4.2c: 検査 fan-out (main が起動して待つ)

**このステップで Read する参照節** (起動前にまとめて開く): [phase-gates.md](./references/phase-gates.md) の `## 4.2c: fan-out 前後の clean 確認` / `## 4.2c: 自己免除の抽出` / `## 4.2c: spawn の事前記録` / `## 4.2c: 「最後の issue」の判定`、[phase-execution.md](./references/phase-execution.md) の `## 4.2c: 観点 gating 表` / `## 4.2c: review-adversarial の mode 決定表` / `## 4.2c: review-adversarial のスキップ述語表` / `## 4.2c: 観点 gating 述語の算出コマンド` / `## 4.2c: adversarial_mode 別の起動順序` / `## 4.2c: 検査 fan-out の起動`、[phase-context.md](./references/phase-context.md) の `## 渡し方` (agent ごとの入力集合の正)、[logging.md](./references/logging.md) の `gating_decided` の行 (context スキーマの正)。

**fan-out の前後で作業ツリーが clean であることを確認する。初回だけでなく 4.2d の再 fan-out でも毎回行う。** 同じ「`status --porcelain` が非空」でも観測する時点で意味が違い、**処方が正反対 (前はコミットする / 後は `git restore` で捨てる) なので、取り違えると実装を捨てるか変異をコミットすることになる**。コマンドと 3 つの前提は [references/phase-gates.md](./references/phase-gates.md) の `## 4.2c: fan-out 前後の clean 確認`。

fan-out 前の事前ブロックでは、続けて次の 3 つを行う (いずれも phase-gates.md の同名節が正):

- **implementer の自己免除を抽出して検査 agent へ渡す** (`## 4.2c: 自己免除の抽出`)。実装者が「検証しない」と宣言した項目は、記録するだけでは誰も裁定しない。**抽出元は当該フェーズの全 report であって最新の 1 本ではない**。出力が `[]` でもファイルは必ず作り、`exemptions_path` として review-tdd と review-adversarial に渡す。**失敗と「免除 0 件」を同じ `[]` に潰すと、4.2d 手順 1 の裁定チェックが常に 0 件と比較することになり自分で自分を無効化する**
- **`EXEMPTIONS_COUNT` が 1 以上なのに review-tdd と review-adversarial のどちらも起動しないフェーズ**では免除が誰にも裁定されないまま通過するので、`verification_skipped` (source: `exemptions_unadjudicated`) を記録して Step 5.6 の集約に載せる
- **予算を比較してから起動する。** 事前ブロックで `phase_spawns` / `run_spawns` を JSONL の `spawn` 件数から数え直し、`phase_spawns_budget` (当該 phase の `start` の記録値の最大) / `run_spawns_budget` (`start` / `phase_added` の記録値の最大) と比較する。**この fan-out で起動する体数を足した結果が上限を超えるなら、1 体も起動せず `spawn_budget_exceeded` でエスカレ停止する** — 増分と上限は定義されているのに比較する地点が無いと、上限が一度も評価されないまま走る
- **この fan-out で起動する agent の `spawn` を JSONL に先に書く** (`## 4.2c: spawn の事前記録`)。**起動した後ではなくこの事前ブロックの中で行う** — 起動後に書く規定だと、待ちに入る直前の・前進を生まないログ 1 行だけが構造的に落ちる。`run_spawns` の予算ゲートはこの記録を唯一のソースにしている

**`mode: full` の review-adversarial は fan-out に入れず、単独で先に走らせてから残りを fan-out する。** レンズ A は**共有の作業ツリー上でソースを直接書き換えて実行し、終える前に戻す**ので、その間に並列で走る観点は変異後のコードを読みうる。読んだかどうかは事後に判別できず (戻ってしまえば `status` は clean)、その観点の結果が「fatal なし」でも「fatal あり」でも信用できない。**影響は dev サーバを立てる review-product-readiness に限らない** — guard も tdd も quality も同じツリーを読む。`weakening_only` は変異を行わないので通常どおり fan-out に入れてよい。起動順序の表は [references/phase-execution.md](./references/phase-execution.md) の `## 4.2c: adversarial_mode 別の起動順序`。

gating で決まった観点を**同一メッセージ内の複数 Agent tool_use として並列起動**し、main が全部の完了を待つ。呼び出し方法は [references/phase-execution.md](./references/phase-execution.md) の `## 4.2c: 検査 fan-out の起動`。**`architecture-guard` は最後の issue のフェーズでだけこの fan-out に加える** — 境界違反は累積的なので最終差分に残り、毎フェーズ起動していた頃の実測は 28 回で違反 1 件だった。それ以外のフェーズでレイヤ境界を担保するのはプロジェクト側の lint (`lint_command`) で、検査の方法は当該プロジェクトの `CLAUDE.md` に書かれている前提とする。guard を review と同じ fan-out に入れるのは待ちを 2 回から 1 回に減らすためで、guard の違反も review の fatal も同じ修正ラウンド (4.2d) で処理する。検査 agent も implementer と同じく **30 分応答が無ければ打ち切り** (計測コマンドと `SPAWN_EPOCH` の書き出しは [references/phase-execution.md](./references/phase-execution.md) の `## 4.2a: subagent の応答待ち時間`)、打ち切った観点は 4.2d 手順 1 で扱う。

**観点 gating (トークン削減の要):**

**gating はフェーズごとに 1 回だけ確定する。** 初回 fan-out の直前に述語を評価し、決まった観点の集合 (review-adversarial の `mode` を含む) を JSONL に `event_type: gating_decided` で記録する。**4.2d の再 fan-out はこの記録された集合の部分集合しか起動できない** (毎ラウンド評価し直すと判定が揺れて仕様外の観点が起動する。実測で review-quality が「最後の issue のみ」の規定に反して 3 フェーズで起動していた)。`context` のスキーマは [references/logging.md](./references/logging.md) の `gating_decided` の行が正。判定に使う 3 表 — **`## 4.2c: 観点 gating 表` / `## 4.2c: review-adversarial の mode 決定表` / `## 4.2c: review-adversarial のスキップ述語表`** — はいずれも [references/phase-execution.md](./references/phase-execution.md) の同名節にあり、述語の算出コマンド (`## 4.2c: 観点 gating 述語の算出コマンド`) と同じファイルなので 1 回の Read で揃う (**近似コマンドで代替すると**、untracked ファイルや言語別インラインテストの検知漏れにより review-adversarial を不当に skip する)。**「最後の issue」の判定コマンド**は [references/phase-gates.md](./references/phase-gates.md) の `## 4.2c: 「最後の issue」の判定` (自分自身がまだ open なので、出力が `1` なら最後。`0` と比較しない)。

- mode 決定表の 3 行目は **review-tdd の gating と対になっている**。テストを伴わない実装だけが積まれたフェーズは review-tdd が起動せず (判定対象のテストが無い)、レンズ B も検査対象の差分が無いため実質何も検査されない。この穴をレンズ C (完了主張の反証) で埋めるため `full` に上げる
- **`PRODUCT_MODE=cli` では review-product-readiness を一切起動しない** (`uiPhase` が常に `false`。最後の issue の「全観点フル」からも除外する。cli の G_E2E は Step 5.2 で review-spec-compliance が担当する)
- **review-quality は最後の issue のみ** (機械判定可能な境界違反はプロジェクトの lint が毎ラウンド担保し、最後の issue で architecture-guard が最終差分をまとめて検査するため)。**ただし `$CONSUMABLE_CHANGED` が非空のフェーズ** (ローテーション有効な refresh token・nonce・ワンタイムコード・べき等キー・使い捨て署名 URL など、消費すると無効化される資源を扱う差分) **では最後の issue でなくても起動する** — 多重消費・恒久エラー分岐の漏れが復帰不能障害に直結し、レイヤ境界の検査では検知できないため
- スキップ述語は**全条件が真の場合のみ skip 可** (skip は権利であって義務ではない。1 つでも「実行」と出れば actor はスキップできない)。skip 時は `verification_skipped` (source: `adversarial_skip`、context に `changed_files` / `changed_lines` / `criteria_result`) を記録する (Step 5.6 の集約に自動合流させ、沈黙スキップを構造的に不可能にするため)
- **述語を評価するのは初回 fan-out の前の 1 回だけ。** 修正ラウンドで再検査する観点は 4.2d 手順 5 が決める。**初回に「実行」と判定された観点が次ラウンドで再検査されないことは「実行 → skip への降格」ではない** — 初回の検査は実施済みで、以降は fatal の解消確認に絞るという意味である。例外は**初回評価で skip だったフェーズだけ**で、各修正ラウンドの fan-out 直前に述語一式 (mode 決定に要る `$CONSUMABLE_CHANGED` / `$AUTH_CHANGED` も含む) を再算出し、skip → 実行 に転じたら起動する (降格は禁止)

**結果を受け取ったら、`skipped_lenses` が非空なら `verification_skipped` (source: `mode_degraded`) を書く。** これが Step 5.6 の集約に合流する経路で、書かなければモード縮退が沈黙する。スキップ述語で adversarial を起動しなかった場合は `gating_decided` の `adversarial_mode` に `"skipped"` を記録する。**mode の判定根拠は `basis` に残す。**

各 Agent 呼び出しには **「モデル方針」の表どおり `model` を明示**する。呼び出し時の指定は agent 定義側のデフォルトより優先され、**未指定にすると親のセッションモデルを継承してしまう** (`agent-spawn-guard` hook が未指定を deny する)。**review-adversarial には PHASE_CONTEXT の path を渡さない** — fresh context 監査のため、`mode` / phase_name / phase_start_sha / repo_dir / docs_dir / dev_server / scratch_dir / **exemptions_path** / output_path のみを渡す (**集合の正は phase-context.md「渡し方」の行**)。**`mode` を渡し忘れると agent 側の既定で `full` に戻り、縮退が無音で効かなくなる**。

##### 4.2d: fatal 判定と修正ラウンド (最大 3)

main は各 agent の結果 JSON を「main のコンテキスト規律」の `jq` 射影で読む。

1. **いずれかの agent が結果を返せない → その観点は「未検証」。パス扱いにせず** `guard_agent_failed` (architecture-guard) / `review_agent_failed` (review-*) でエスカレ停止する。high 0 件と同一視しない。該当は「エラー終了か 30 分無応答」「`output_path` の JSON が不在かパース不能」「スキーマ不適合 (guard は `ok`、review-* は `findings` が読めない)」「guard の `skip_reason: "diff_command_failed"`」「guard の `unchecked_files` が非空」「**`exemptions_path` を渡した agent (review-tdd と review-adversarial の 2 つだけ) の `adjudicated` が、取り直した免除件数を下回る**」。
   - **guard の `skip_reason: "no_layer_convention"` は未検証にしない** — レイヤ構造の無いプロジェクトで誤検知を出さないための意図的な素通りで、`checked_files: 0, ok: true` が正しい結果。ただし `verification_skipped` (source: `no_layer_convention`) には記録する。**`skip_reason: "layer_check_failed"` は未検証にする** (判定スクリプトがファイルを読めず検査が成立していないため。`diff_command_failed` と同じ扱い)
   - **`exemptions_path` を渡していない agent (architecture-guard / review-quality / review-product-readiness) に `adjudicated` の条件を適用しない** — 渡していないものを裁定できるはずがなく、免除が 1 件でもあるフェーズが全て偽の停止になる
   - **review-product-readiness の `dev_server_unavailable` は未検証扱いにするが、修正ラウンドには乗せない** (環境起因で実装者が直せないため。guard の `diff_command_failed` と同じ性質)
   - **agent の失敗は「一過性」と「決定的」を分けて扱う。** タイムアウト・JSON 破損・一時的なエラー終了は `in-progress` のまま再実行で解決しうるが、**`TOO_MANY_FILES` / `NO_DESIGN_DOCS` / スキーマ不適合 / `diff_command_failed` / `unchecked_files` 非空 / `adjudicated` 不足は決定的**で、同じ入力なら何度でも同じ結果になる。決定的な失敗と、同一フェーズで同じ agent が 2 回続けて失敗した場合は **`needs-human` に振り分ける** (決定的な失敗を「再実行で解決しうる」に入れると、人間に渡る経路が無いまま同じ停止を繰り返す)
2. **fatal の定義**: review-* の severity: high、または architecture-guard の `violations` のうち severity が high / medium のもの。fatal 0 件 → 4.2e へ。**ただし review-adversarial の `test_weakened` / `vacuous_assertion` / `skip_added` / `tautological_test` は confidence と severity に関わらず fatal に数えない** — 手順 7 のトレース確認・エスカレ経路が優先する (実装者自身に弱体化を直させないため)。**この 4 つの rule 名は `claude/agents/review-adversarial.md` の `rule` enum を正とし、本手順・手順 7・[references/phase-gates.md](./references/phase-gates.md) の `## 4.2d 手順 3: fixer へ渡す findings の切り出し` の jq 正規表現 (唯一機械実行されるコピー)・[references/orchestration-rationale.md](./references/orchestration-rationale.md) の `## 内部呼び出し subagent の役割詳細`・`claude/agents/dev-impl-implementer.md` の 5 箇所を同じ集合に保つ** (どこか 1 つに漏れると、その rule だけが実装者に直させる経路へ流れて必ず空回りする)。
   - **main は agent が付けた severity を変更しない (昇格も降格もしない)。** medium / low を「重要そうだから」と high 扱いにして新ラウンドを起こさない。過小評価は agent 側の severity 基準を直して解決する問題で、実行時の裁量で埋めるとラウンド数が判定基準なしに増える (実測で 9 ラウンド中 2 ラウンド以上が裁量昇格のみで起動していた)
   - **medium の「相乗り」は行わない。** implementer は review-* を high だけ、guard を high/medium 直す規約なので、review-* の medium を渡しても no-op になる。medium は `review_low` として記録し、Step 6 のサマリと HTML レポートに残す
3. fatal あり → `phase_fix_round += 1`。**この時点で `phase_fix_round > phase_fix_budget` (既定 3) なら fix を起動せず `phase_fix_exceeded` でエスカレ停止**する (JSONL の context に guard 由来 / review 由来の内訳を残す)。続けて **JSONL に `event_type: fix_dispatch` を記録する**。`spawn` と同じく**起動する前に書く** — Step 0 の再入で `phase_fix_round` を復元する唯一のソースであり、ラウンド 2 以降の implementer へ渡す「過去ラウンドの経過」の材料でもある。fixer に渡す findings ファイルの切り出しは [references/phase-gates.md](./references/phase-gates.md) の `## 4.2d 手順 3: fixer へ渡す findings の切り出し` を Read してから実行する (**guard の分をキー `findings` に付け替えると、implementer が high しか拾わない規約により guard の medium が誰にも直されず毎ラウンド再検出される**)。
4. **`mode: fix` の `dev-impl-implementer` を起動**する。**モデルはラウンド 1 が `opus`、ラウンド 2 以降が `fable`** (上記「修正ラウンドのモデル昇格」)。ラウンド 2 以降は指示文に「指摘箇所を局所的に塞ぐ前に、その箇所が属する不変条件を洗い出し、同じ族のエッジケースがまとめて閉じるかを確認せよ。族として閉じられない残りは報告の `open_questions` に明記せよ」を加える。渡すのは `findings_paths` / `phase_context_path` / `repo_dir` / `report_path`。**指示文の全文テンプレート (過去ラウンドの経過を渡す `ROUND2_PLUS_BRIEF` を含む) は [references/phase-execution.md](./references/phase-execution.md) の `## 4.2d: 修正ラウンドの implementer 起動` を Read して使う。** main は findings の本文を読まないし、修正内容を指示しない。**報告を受けたら 4.2a と同じく main がコミットする**
5. 修正完了後、**再 fan-out は「fatal を出した観点」に絞って 4.2c に戻る** (最後の issue のフェーズでは architecture-guard も含める)。目的は「前回の fatal が fix 差分で解消したか」の検証であって、フェーズ全体の再レビューではない (毎ラウンド全観点を回すと観点ごとに新しい指摘が出続け、ラウンドが上限まで消化される。実測でフェーズあたり平均 2.25 ラウンド)。起動する観点は**原則として `gating_decided` の `gating_set` の部分集合**とする (guard は gating 対象外なので判定に含めない)。集合外の review-adversarial を追加してよいのは次の 3 つだけで、追加したら `gating_decided` を追記する:
   - **fix がテストに触れた場合** (`mode: weakening_only` で足りる)。判定コマンドは [references/phase-gates.md](./references/phase-gates.md) の `## 4.2d 手順 5: fix がテストに触れたかの判定` を Read してから実行する (**`HEAD~1` で代替すると**、fix が差分ゼロでコミットを生まなかったとき 1 つ前のラウンドを指して誤判定し、最初のコミットでは解決自体に失敗する)。**判定不能なら安全側に倒して起動する**
   - **self-exemptions の claim 差分に新規の免除があった場合** (`mode: weakening_only` で足りる) — 修正ラウンドで新たに宣言された免除を裁く者を確保するため
   - **スキップ述語が「skip → 実行」に転じた場合** (降格は禁止)。この転換で起動するときの `mode` はその時点で mode 決定表を評価して決める (初回 skip したフェーズは `adversarial_mode: "skipped"` しか記録が無いため)

   **`gating_decided` を追記するときは `gating_set` を全体で再掲する** (追加分だけを書かない)。同一 phase では最新の 1 件を採る規定 (logging.md) なので、部分集合を書くと以後それしか起動できず、初回に決まった観点が無音で落ちる。「修正が別観点を壊す」リスクは、最後の issue の全観点フル検査と Step 5 の第三者監査で受け止める。
6. 修正中に `design_overview_break` を検知 → 即エスカレ停止 (commit しない)
7. review-adversarial の `test_weakened` / `vacuous_assertion` / `skip_added` / `tautological_test` は **severity と confidence に関わらず**修正ラウンドに乗せない (これらは medium で出ることが多く、rule 名だけで判定する。severity を条件にすると medium の弱体化が黙って通る)。弱体化を実装者自身に直させると骨抜きの温床になるため、4.2e と同じトレース確認 (TODO.md / DESIGN_DETAIL_APP.md に意図的な変更としてトレースできるか) を **main が**行い、トレース不能なら `test_weakening_detected` でエスカレ停止する。`dev-impl-implementer` 側もこれらを渡されたら修正せず `test_weakening_suspected` で停止する規約 (二重の歯止め)
8. **作業ツリーの汚染は、agent の自己申告ではなく main が検出する。** `working_tree_polluted` の報告が無くても必ず突合する。手順は [references/phase-gates.md](./references/phase-gates.md) の `## 4.2d 手順 8: 作業ツリーの汚染の検出と復元`。**この検出が捕まえるのは「戻し忘れた汚染」だけ**で、検査中に変異させて正しく戻した一過性の窓は捕まらない — それを構造的に閉じるのが 4.2c の「変異を伴う観点を同じ fan-out に入れない」規定であり、検出は二重の歯止めである。**汚染を検出したラウンドの検査結果は fatal の有無に関わらず全て破棄して 1 回やり直す** (「fatal なし」を通せば検査していないコードを通し、「fatal あり」を載せれば変異が原因の偽の fatal を実装者に直させる)。やり直しの spawn は `phase_spawns` に計上するが `phase_fix_round` は進めない。**同一フェーズで 2 回目の汚染を検出したらエスカレ停止する** (`working_tree_polluted`)

severity: low/medium の findings は修正せず JSONL に `event_type: review_low` で記録する。**転記は `jq` で結果 JSON から JSONL へ直接流し込み、`message` を含む本文も入れる** — HTML レポートのレビュー残課題セクションが `message` を表示するため、落とすと「どのファイルの何行目か」しか残らず読めない。**main のコンテキスト規律に反しない**のは、`jq` の出力を標準出力に流さずファイルへ直行させるから。

##### 4.2e: テストゲート + コミット (main)

コミット前に **main が `full_test_command` を Bash で直接実行し、exit code 0 を確認する** (自己申告ではなく実行結果で判定)。**タイムアウトした実行は「未検証」として `verification_skipped` に記録し、成功扱いにしない。** 実行主体を main にする理由・600 秒上限の回避・失敗時の再試行経路 (`test_gate_retry`、上限 3 で `tests_failing_before_commit`) は [references/phase-gates.md](./references/phase-gates.md) の `## 4.2e: 全体スイートのテストゲート` が正で、ここでは繰り返さない。

続けて **issue 本文の `## DoD` ブロックを実行する**。全体スイートが緑でも、その issue 固有の受入基準は別に確認しなければならない (`## DoD` は dev-spec のフェーズ 10 が著作し 10.5 の監査が実行可能性まで検査した唯一の issue 単位の受入基準で、ここで実行しないと誰も実行しない)。抽出と実行のコマンドは [references/phase-gates.md](./references/phase-gates.md) の `## 4.2e: DoD ブロックの抽出と実行` を Read してから実行する (**抽出が空でないことの確認を省くと**、空の `dod.sh` への `bash -e` は必ず exit 0 を返すので「1 件も実行していない」が「全通過」と区別できなくなる)。同節の規定:

- **`DOD_CMDS` が 0 のときは通過扱いにしない。** `verification_skipped` (source: `dod_no_automated`) を記録し、close コメントから「DoD がすべて通過した」の文言を外して手動確認待ちとして Step 6 のサマリに載せる
- `DoD (手動):` の行は実行できないので、**その本文をそのまま Step 6 のサマリに残して人間に確認を求める** (自動系がすべて通っていれば実装は前進しているので、手動系の存在自体を停止理由にしない)
- **close コメントで「DoD がすべて通過した」と書けるのは、抽出したブロックが exit 0 になったときだけである**

続けて**テスト弱体化の機械検知**を行う (reward hacking 対策。review-tdd の LLM 判定に頼らず、編集権限の外で機械判定する)。検知コマンドは [references/phase-execution.md](./references/phase-execution.md) の `## 4.2e: テスト弱体化検知コマンド` 節を Read してから実行する (この節を読まず近似コマンドで代替すると、言語別 skip/ignore パターンの見落としにより test_weakening 検知が漏れるリスクがある)。ヒットしたら TODO.md / DESIGN_DETAIL_APP.md にトレースできる意図的な変更か確認し、トレースできなければ `test_weakening_detected` でエスカレ停止する (パス扱いしない)。

緑を確認したら、以下を **main が**この順で行う:

1. **TODO.md の該当フェーズを `- [x]` に更新する** (issue タイトルの識別子で `### フェーズ<識別子>:` 見出しを引き当てる)。**直後の手順 2 のフェーズ最終コミットに含める** (チェックだけ先に入ってコミットが無い状態を作らない。Step 0 手順 3 の再入突合はこの前提で「チェック済みだがコミット無し = 未完了」と判定する)
2. **フェーズ最終コミットを打つ**。実装はラウンドごとに入っているので、このコミットが載せるのは TODO.md の更新と、どのラウンドにも含まれなかった残りだけになる。
   - subject は `<emoji> <type>: [phase-<識別子>][STRUCTURAL|BEHAVIORAL] <要約>`。**`[STRUCTURAL]` / `[BEHAVIORAL]` を付けるのはこのコミットだけ**で、フェーズ全体の動作変更の有無を表す (途中のラウンドコミットには付けない → 「ラウンドごとのコミット」)
   - 本文に `Fixes #<issue 番号>` を入れる
   - **`rules/core/commit.md` の条件をフェーズ単位で満たすのはこのコミットである。** 本ステップ冒頭の全体スイートと DoD がここまでに緑になっているためで、途中で全体スイートが落ちた場合はその修正が新しいラウンドのコミットとして積まれ、緑になってから最終コミットを打つ
   - **コミットは必ず main が行う** — 形式を機械検証する commit-msg-guard hook は親にしか効かないため。ただし hook が実際に検証するのは `$GHQ_ROOT/github.com/skanehira/` 配下のリポジトリで作業しているときだけで、それ以外では fail-open で素通りする。push はしない (ユーザ手動)
3. **RUN_FACTS.md を更新する。この更新がフェーズ間の文脈再注入を代替する**ので省略しない (省略すると次フェーズの implementer がプロジェクトの作り方を探索し直す)。書式・畳み込み規則は [references/phase-gates.md](./references/phase-gates.md) の `## 4.2e 手順 3: RUN_FACTS.md の更新`
4. **`impl_done` を書く前に spawn 記録を突合する。** 手順は [references/phase-gates.md](./references/phase-gates.md) の `## 4.2e 手順 4: spawn 記録の突合` を Read してから実行する (**件数比較で代替すると**過剰と不足が相殺して一致してしまい両方見逃す。集合の差なら**どちらの向きにずれたか**が出るので、「成果物はあるが記録が無い」= 記録漏れを補記、「記録はあるが成果物が無い」= 手順 1 の未検証扱い、と対処を分けられる)
5. **JSONL に `event_type: impl_done` を記録する** (context: `phase` / `summary` / `commit_sha` / `phase_fix_round` / `phase_spawns` / `review_outputs`)。これが issue 完了の唯一のイベントで、`prev_phase_summary` (次フェーズの PHASE_CONTEXT) と HTML レポートのフェーズタイムラインがこれを読む
6. implementer 報告の `verification_skipped` / `design_decisions` / `open_questions` / `spec_lookups` / `self_review` を `report_path` から `jq` で JSONL に転記する (`verification_skipped` は Step 5.6 の未検証項目集約に合流する)。**転記は 1 回の Bash 実行で全件を流し込む** — コマンドは [references/phase-execution.md](./references/phase-execution.md) の `## 4.2e: implementer 報告の JSONL 一括転記` 節を使う (項目ごとに Bash を呼ぶと main の往復がフェーズあたり 30 回近く増える)
7. **当該 issue を close する** (`gh issue close <N> --comment "DoD がすべて通過したため close する"`)
8. **親 issue の自動 close sweep** を回す (下記)

**手順 7 を 8 より後ろに回さない。** ある UC の最後の子を閉じた後に sweep を回さないと、その親を閉じる契機が二度と来ない (それ以前の子なら次の子の close で sweep が再走して自己修復する)。親は Step 1 / Step 2 / 4.2c のいずれでも `uc-tracking` として除外されるため、open のまま残っても誰も気付かない。

**親 issue の自動 close sweep**

`/dev-spec` のフェーズ 12 が作る `uc-tracking` の親 issue は、そのユースケースを実現する子 (フェーズ issue) が全て closed になった時点で完了する。**GitHub は子が open のままでも親の close を止めない**ので、判定は dev-impl が行う。手順は [references/issue-ops.md](./references/issue-ops.md) の `## 親 issue の自動 close sweep` を Read してから実行する (**`--paginate` と `per_page=100` を省いた近似で代替すると**、既定の 1 ページ 30 件に切られて 31 件目以降の open な子が見えず、まだ実装が残っている親を完了扱いで閉じる。出力を見ても異常と区別できない silent な誤判定になる)。**この sweep が扱うのは close 方向だけ**で、人間が子を手で reopen しても親は closed のままになる。

##### フェーズ内エスカレ条件まとめ

判定表は [references/phase-gates.md](./references/phase-gates.md) の `## フェーズ内エスカレ条件まとめ` を Read して従う。

#### Step 4.6: 設計乖離の判定 (P1 / P2 / P3)

implementer 報告 (`mode: implement` / `mode: fix` 双方) の `deviation_signals` を main が `report_path` から `jq` で集め、P 値に分類する。**implementer は自分で JSONL を書けないので、この転記が Step 4.6 の唯一の入力になる** (逐次モードでも main は実装過程を見ていない)。design 整合の判定は review findings の `dimension: "quality"` かつ `rule: "design_mismatch"` 系エントリも使う。

**シグナル元と分類対応**:

判定表は [references/issue-ops.md](./references/issue-ops.md) の `## Step 4.6: 設計乖離のシグナル元と分類` を Read して従う。

**review-quality の `design_mismatch` が high の場合は、4.2d の fatal として修正ラウンドで処理する** (review-* の high は fatal の定義に入るため)。**同じ finding を 4.6 で P3 のエスカレ停止にも回さない** — 両方に載せると「修正ラウンドを起動する」と「即座に停止する」という排他的な処方が同時に成立してしまう。**設計そのものが破綻しているという判断は implementer の `deviation_signals` の `design_overview_break` からのみ入る** (実装しようとして初めて分かる性質のもので、差分を外から見るレビューが単独で決めることではない)。修正ラウンドで直せなかった high は通常どおり `phase_fix_exceeded` で停止し、そこで人間が設計の問題かを判断する。

**シグナル無しの場合**: Step 2 に戻って次の issue を選ぶ。

**集約のしかた**: 同一 phase 内で同種シグナルが複数回記録された場合、`scope` + `what` で重複排除してから処理 (1 件のシグナルとして扱う)。

##### P1 動的修正

1. `p1_fixes_in_phase += 1`。`p1_fixes_in_phase > 2` なら本シグナルを P2 (design_detail_gap) として扱い、P2 動的修正フローに切り替える (以降のステップは実行しない)
2. TODO.md の該当フェーズ周辺を Edit
3. ログに「P1 fix: <変更内容の 1 行サマリ>」を残す (JSONL は `event_type: p1_fix`)
4. **当該フェーズにタスクを足す場合は、TODO.md だけでなく issue 本文も更新する。** Step 4.6 は 4.2e で issue を close した**後**に走るので、その issue は既に closed であり、**実装指示の実体は TODO.md ではなく issue 本文である** (PHASE_CONTEXT の `phase_tasks` は `gh issue view` から作る)。TODO.md だけ直しても実装器には届かない。手順は [references/issue-ops.md](./references/issue-ops.md) の `## P1 手順 4: issue の reopen と本文更新`。**フェーズを跨ぐ追加なら新フェーズを TODO.md に挿入し、続けて「新フェーズの issue 化」を実行する** (close 済み issue を再利用するより見通しがよいので、迷ったらこちら)
5. **編集した `docs/TODO.md` をコミットする** (下記「動的修正のコミット」)

##### 動的修正のコミット

**P1 / P2 が編集した docs は、その場でコミットする。** Step 4.6 は 4.2e のコミットより**後**に走るため、ここでコミットしないと変更は working tree に残ったまま次のフェーズへ進み、その run がエスカレ停止すれば**設計をどう変えたかが git の履歴に一切残らない**。コマンドとメッセージ書式は [references/issue-ops.md](./references/issue-ops.md) の `## 動的修正のコミット`。規約は 3 点:

- **実装差分とは別コミットにする** (`rules/core/commit.md` の関心事分割。混ぜると後から「設計がいつ変わったか」を追えなくなる)
- type は `docs` を使い、**`[STRUCTURAL]` / `[BEHAVIORAL]` は付けない** — この 2 つはプロダクトコードの動作変更の有無を表す区分で、設計書の更新はどちらでもない (Step 7 の HTML レポートのコミットと同じ扱い)
- **エスカレ停止時もこのコミットは残す。** 停止時に打たないのは**フェーズ最終コミット**だけで (全体スイートと DoD を通っていないため)、ラウンドのコミットも設計判断の記録も実装の成否と無関係に残す

##### P2 動的修正

1. `p2_fixes_total += 1`。**回数では止めない** — 詳細設計の不足は実装しないと分からないことが多く、回数が増えること自体は異常ではない。代わりに**何をどう変えたかを後から追える形で残す**責任を負う (手順 6 のコミット / 手順 7 の JSONL / Step 6 の完了サマリ / HTML レポートのセクション 4 の 4 つが揃って初めて「確認できる」状態になる)。設計の前提そのものが崩れている場合は回数に関わらず P3 (`design_overview_break`) として停止する — これは回数ではなくシグナルの種類で判定する
2. DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md の該当側 (境界基準: 変更に IaC・コンソール操作・環境設定変更が要るなら INFRA) のセクションを Edit
3. **受入基準ガード**: Edit 直後に goals_sha を再計算 (Step 1 のコマンド) し、承認スタンプの値と照合する。不一致 = 受入基準 (ゴール / 検証手順行) を触った P2 であり、実装者による自己適用は禁止。Edit を revert せず `acceptance_criteria_change` でエスカレ停止する (「受入基準の変更が必要になった。dev-spec フェーズ 9 → 11 で再承認せよ」と通知。実装ガイド・スキーマ等の追記はハッシュ対象外なので通過する)
4. **再生成の前にフェーズ見出しのスナップショットを取る** (再生成後では「前」の状態が失われ、増えたフェーズを特定できない)。そのうえで `../dev-spec/references/todo-generation.md` を Read し、その手順に従ってメインループで TODO.md を再生成する (完了済みフェーズのチェック状態は保つ)。**フェーズ見出しの `deps` / `goals` / (USECASES.md がある構成では) `ucs` の宣言を落とさない** — 再生成で `ucs` が消えると、次の `/dev-spec` 実行でフェーズ 12.0 がフラット判定に落ち、親 issue が作られなくなる。スナップショットと差分のコマンドは [references/issue-ops.md](./references/issue-ops.md) の `## P2 手順 4: フェーズ差分のスナップショットと TODO 再生成`
5. **増えたフェーズがあれば、その各件に「新フェーズの issue 化」を実行する** (下記の共通手順)。closed の issue はそのまま完了扱いを維持する
6. **編集した設計書 (`DESIGN_DETAIL_APP.md` / `_INFRA.md`) と `docs/TODO.md` をコミットする** (上記「動的修正のコミット」)
7. ログに「P2 fix: <更新セクション>」を残す (JSONL は `event_type: p2_fix`)。**`context` には `section` / `what` (何をどう変えたか 1 行) / `why` (実装から判明した事実) / `commit_sha` (手順 6 のコミット) / `p2_fixes_total` (この時点の通算) を入れる** — 停止しない代わりに、ユーザーが後から「設計のどこが実装に合わせて書き換わったか」を追える唯一の記録になる
8. 当該フェーズの再実行か次フェーズへ進むかを判定: 再生成後の TODO.md で **当該フェーズ内に新規の未完了タスク (`- [ ]`) が追加されていれば、P1 手順 4 と同じく issue を reopen して本文の `## 実装タスク` を更新し、`ready` に戻してから Step 2 の抽出をやり直す**。既存タスクが全て完了済みのまま (詳細設計の記述を補っただけで実装側の追加作業が無い) なら次フェーズへ進む
9. ユーザに対する通知は「DESIGN_DETAIL_APP.md (または _INFRA.md) / TODO.md を更新しました (詳細はログ参照)」程度 (dev-impl は止まらない)

##### 新フェーズの issue 化 (P1 / P2 / Step 5.5 の共通手順)

**TODO.md にフェーズを追加しただけでは、そのフェーズは永久に実装されない。** 着手対象の抽出は Step 2 が GitHub issue からしか行わないため、issue の無いフェーズは Step 2 に現れない。TODO.md にフェーズを足したら、**同じターンで必ず** [references/issue-ops.md](./references/issue-ops.md) の `## 新フェーズの issue 化` と `## 紐付けの差集合` を Read して次の 5 手順を実行する:

1. **issue を作る。** 本文の節構造・タイトル形式は `/dev-spec` のフェーズ 12.4.2 と同じ。ラベルは `ready`。**識別子は既存と衝突しない値を採る** (例: 元フェーズが `4` なら `4-a`) — 識別子は issue タイトル・`$SCRATCH_DIR` のパス・4.2e の `### フェーズ<識別子>:` 引き当ての 3 箇所で鍵になるため、衝突するとフェーズを取り違える
2. **親 issue がある構成なら紐付ける** (`## 紐付けの差集合`)。**紐付ける対象は「今作った issue」ではなく、`uc-tracking` を除く全 issue のうちどの親にも紐付いていないものの差集合**とする — 自分が作った issue だけを見ると、前の run が issue 作成後・紐付け前に落ちて宙に浮いた子は誰にも拾われない。**判定と引き当ては `--state all` で行う** (4.2e の sweep が完了した親を随時 close するため、open だけを見ると親を取りこぼす)。**親が 0 件のときは差集合へ進まない** (フラット構成では実装対象の全 issue が「未紐付け」として返る)
3. **`run_spawns_budget` を再計算する** (式の正は Step 3 のカウンタ規定)。issue が増えたのに上限が据え置きだと、正当な実装の途中で `spawn_budget_exceeded` に当たる。**手順 4 の記録より前に行う** (再計算した値を `phase_added` に載せるため)
4. **JSONL に `event_type: phase_added` を記録する** (`context`: `phase` / `issue_number` / `parent_number` / `origin` (`p1` / `p2` / `goal_unmet`) / `run_spawns_budget`)
5. **Step 2 の issue 抽出を再実行**して、追加したフェーズを着手対象に含める

**親の付け替え (`replace_parent`) は行わない。** P2 の TODO.md 再生成で `ucs` が変わり別の親にぶら下がったままの子は差集合に現れないが、その貼り替えは `/dev-spec` の 12.4.3 に委ねる — dev-impl が親の付け替えまで行うと、設計側の宣言と実装側の判断のどちらが正かが曖昧になる。

##### P3 検出時

エスカレ停止 (後述の「エスカレ停止時の挙動」へ)。

シグナル処理が終わったら Step 2 に戻って次の issue を選ぶ (コミットは Step 4.2e で実行済み)。

### Step 5: ゴール達成判定 + 未達対応ループ

Step 4 のフェーズループを抜けた時点で「全 TODO 消化」は完了している。ここから DESIGN.md のゴールが**実際に達成されているか**を機械判定する。

**まず 4.2e の「親 issue の自動 close sweep」を無条件で 1 回回す。** 4.2e の sweep は子を close した直後にしか走らないため、前回の run が最後の子を close した後 sweep の前に落ちた場合や、人間が最後の子を手で閉じた場合は、Step 1 が `OPEN=0` を見て Step 5 へ直行し、閉じ忘れた親を誰も閉じない。ここで 1 回流せばその取りこぼしが回収できる (冪等なので閉じるべき親が無ければ何もしない)。

#### Step 5.1: ゴール一覧抽出

DESIGN.md の「ゴール」セクションを Read してゴール一覧を抽出 (例: `G1, G2, ...`)。抽出コマンド例: `rg -n '^- G[0-9]+:|^G[0-9]+:' docs/DESIGN.md`。

ゴール定義は Step 1 の構造ゲートで存在を保証済み。万一この時点で抽出できない場合は `goals_missing` でエスカレ停止する (**skip しない** — ゴール判定を省くと完了条件が「全 TODO 消化」という作業量ベースの自己申告になるため)。

#### Step 5.2: 第三者監査の並列起動

自動系ゴールの検証は**メインループが自分で実行しない** (実装者本人による自己判定を避ける)。`PRODUCT_MODE=cli` の場合は `review-spec-compliance` (mode: post-impl、G_E2E も自動系ゴールとして実行) を単独起動する。`webapp` / `unknown` の場合は `review-spec-compliance` と `review-product-readiness` (G_E2E) を**同一メッセージ内の複数 Agent tool_use として並列起動**する。起動する agent はすべて `model: opus` を明示する。起動コードは [references/goal-audit.md](./references/goal-audit.md) の `## 5.2: 監査 agent の並列起動` 節を Read してから実行する (この節を読まず近似の prompt で起動すると、`docs は自分で全文 Read すること` 等の指示や `output_path` / `holdout_enabled` / `product_mode` の欠落により第三者監査の独立性が落ちる)。

**G_E2E の判定**:
- **webapp / unknown**: review-product-readiness が判定。**まず `rule: dev_server_unavailable` が無いことを確認する** — あれば実機を 1 度も触れていないので、high が 0 件でも **achieved にしてはならない**。`verification_skipped` (source: `dev_server_unavailable`) を記録して手動 pending に落とす (この rule は medium で返るため、severity だけを見る判定では素通りする)。dev サーバが動いたうえでナビ系 findings (`nav_unreachable` 等) の severity: high が 0 件 → achieved、1 件以上 → unmet。**dev_server が推定できない場合も判定不能** = `verification_skipped` を記録して手動 pending に落とす (achieved 扱いにしない)
- **cli**: review-spec-compliance が自動系ゴールとして G_E2E 検証コマンドを実行して判定。exit code 0 → achieved、非 0 → unmet。検証手順が手動系書式 (`G_E2E 検証 (手動)`) の場合は agent 側で実行不能なため `verification_skipped` を記録して手動 pending に落とす

#### Step 5.3: 監査結果の集約と gate 分岐

review-spec-compliance の `goal_results` (自動系) + review-product-readiness の判定 (G_E2E) + 手動系 (`G<n> 検証 (手動):` は manual_pending のまま) を統合し、JSONL に `event_type: goal_check` で記録する (各ゴールの `id / status / evidence`)。findings は `event_type: spec_compliance` で記録する。findings ごとの分岐表は [references/goal-audit.md](./references/goal-audit.md) の `## Step 5.3: 監査結果の findings 別の対処` を Read して従う。

#### Step 5.4: 結果分岐

**上から順に評価し、最初に当てはまった行の対処を採る** (複数に当てはまりうるため順序が意味を持つ)。判定表は [references/goal-audit.md](./references/goal-audit.md) の `## Step 5.4: 結果分岐`。**3 行目を落とさない** — `vacuous_verification` は 5.3 で「自動修正させない = 未達対応ループに載せない」と定めているので、これが残ったまま「high が 0 件でない」を理由に 2 行目へ送ると、**直しようのない finding で `goal_loop` を空に消費し、2 周を使い切って 3 周目の入口で必ず停止する**。

#### Step 5.5: 未達対応ループ

`goal_loop += 1`。`goal_loop > 2` なら `goal_loop_exceeded` で停止 (エスカレ)。それ以外:

1. 未達ゴール・修正可能な high finding (`unimplemented_api` / `schema_drift` / `infra_missing` / `holdout_test_failed`) ごとに **`docs/TODO.md` にフェーズを追記し、Step 4.6 の「新フェーズの issue 化」を実行する** (issue 作成・親への紐付け・`phase_added` の記録・Step 2 の再抽出まで手順はそこに集約してある)。本ステップ固有の中身は、`## DoD` に未達を検出した検証コマンドをそのまま入れること、`## 対応ゴール` にその未達ゴールの識別子を書くこと、フェーズ内容に検証コマンドと失敗ログ (findings 由来は `message` + `fix_proposal`) を書くこと、の 3 点。**`<!-- ucs: ... -->` は TODO.md から引く** — 未達ゴール (`G<n>`) から UC への対応表はどの成果物にも無いので、そのゴールを `goals` に含むフェーズの `ucs` を採り、複数あって一致しなければ `none` (横断) に倒す。TODO.md への追記を省かない (issue の生成元と実体が食い違わないようにするため)
2. Step 4 のフェーズループに戻る (新規追加フェーズだけが pending)
3. 完了後、Step 5.1 に戻って再判定 (Step 5.2 の監査 agent も**再起動**する。前回結果の使い回しは不可 — 修正が別の乖離を生んでいないかを再監査する)

手動 pending ゴールは Step 6 サマリで「人間確認必要」として明示する (dev-impl は判定せず保留)。

#### Step 5.6: POST_MVP.md の更新と status 判定

Step 5 のゴール判定後、`docs/POST_MVP.md` に **「UI/UX gap」セクション**を書き出す。**`PRODUCT_MODE=cli` では本セクションを省略する** (status 判定の「UI/UX gap 全項目空」条件は自動的に満たされる)。`webapp` では常に書き出し、`unknown` では dev_server 推定が真の場合のみ書き出す。

##### UI/UX gap セクションの内容

必須項目テンプレート (未実装画面 / 未実装ナビ経路 / frontend-design 未適用フラグ / a11y 未対応項目 / 視覚的回帰参照) は [references/post-mvp-template.md](./references/post-mvp-template.md) を Read して従う。各項目は **dev-impl が自動でログ / review 結果から収集して埋める** (decisions.jsonl / review-product-readiness の findings / G_E2E 判定結果から)。

##### 未検証項目の集約

**実行しなかった検証は「成功」と区別できるよう必ず可視化する** (沈黙は成功に見えるため)。対象の事象は発生時に JSONL へ `event_type: verification_skipped` を記録し、ここで集約して Step 6 サマリに列挙する。**集約の対象は [references/logging.md](./references/logging.md) の `verification_skipped` の `source` 表が正**で、ここでは列挙し直さない (2 箇所に列挙を持つと片方だけが更新されて取りこぼす)。`source` ごとにまとめ、それぞれ「何を検証しなかったか」と「なぜか」を 1 行で書く。

##### status 判定

UI/UX gap セクションが**空でなければ** dev-impl の終了 status を `partial` にする。**「空」は機械判定する** — 各見出しの配下に `- ` で始まる行が 0 件であること (post-mvp-template.md はプレースホルダ行を含むテンプレートなので、テンプレートのまま埋めなかった場合と本当に 0 件の場合を目視では区別できない。プレースホルダが残っていれば非空 = `partial` に倒す)。判定表は [references/goal-audit.md](./references/goal-audit.md) の `## Step 5.6: status 判定`。`partial` でも commit と HTML レポート生成は実行する (中途半端でも記録は残す)。

### Step 6: 全フェーズ完了サマリ

**サマリを出したら JSONL に `event_type: run_done` を 1 件だけ記録する** (context: `status` = `done` / `partial`、`phases_completed`、`goal_summary`)。**Step 0 の再入判定はこのイベントの有無だけを見る**ので、書き忘れると次回の起動が完了済みの run を「未完了」と誤認して再入モードに入る。

サマリー生成前に、記載する各主張 (フェーズ完了数・ゴール達成状況・動的修正回数・受入監査結果) を本セッションの実際のツール実行結果 (`git log`、`decisions.jsonl`、review agent の出力 JSON) と突き合わせる。裏付けが取れない主張は記載しない、または「未確認」と明記する。テンプレートは [references/notification-template.md](./references/notification-template.md) の `## 完了サマリ (Step 6)` 節を Read し、全フィールドを埋めて出力する。

### Step 7: HTML レポート生成

dev-impl 終了時 (Step 6 完了後、またはエスカレ停止時) に `docs/dev-impl-reports/${run_id}.html` を生成する。

テンプレ関数・生成手順・XSS 対策・エスカレ停止時の差分は [references/report-template.md](./references/report-template.md) を Read して従う。**生成手順は同ファイルの `## 生成プロセス (dev-impl 視点)` 節が正**で、ここでは列挙し直さない (2 箇所に手順を持つと、テンプレ側を更新したときに片方だけが古いまま残る)。コミット本文のフッタ (`🤖 Generated with ...` と `Co-Authored-By: ...`) は同節の heredoc に含まれている — subject の形式だけは commit-msg-guard が機械検証するが、フッタは検証されないので落としやすい。

レポート内容: ヘッダー (run_id / SHA / 所要時間) / 全体サマリ / フェーズタイムライン / 動的修正詳細 (P1/P2/P3) / レビュー残課題 (low/medium) / 実装ノート (設計判断 / 未解決の質問) / POC_NEEDED 残存状況 (pending non-blocker) / ゴール達成判定 / 受入監査結果 (spec_compliance findings) / フッター。

## エスカレ停止時の挙動

停止条件 (**この一覧が停止理由の網羅リストである**。本文で新しい停止理由を使うときは必ずここと下のラベル表の両方に載せる — どちらかに無いと、停止後のラベル状態と再開方法が未定義になる):

- Step 4.2 のフェーズ内エスカレ条件 (`phase_fix_exceeded` / `guard_agent_failed` / `review_agent_failed` / `spawn_budget_exceeded` / `tests_failing_before_commit` / `working_tree_polluted` / `exemptions_extract_failed`)
- P3 検出 (DESIGN.md 概要レベルの再設計必要 = `design_overview_break`)
- 未達対応を 2 周回しても未達ゴールが残存 (`goal_loop_exceeded`。3 周目の入口 = `goal_loop > 2` で発火)
- 必須ドキュメント (DESIGN.md / DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md / TODO.md) 欠如 (`docs_missing`)
- `blocker=true` の POC_NEEDED マーカーが残存 (`poc_marker_unresolved`。dev-spec フェーズ 5 で解決してから再実行)
- Step 1 構造ゲートの欠落 (`design_not_approved` / `approval_stale` / `goals_missing` / `verification_missing`)
- Step 1 の GitHub 前提条件が解決できない (`github_prereq_failed` = `gh` が使えない / issue が未生成) / issue の取得が `$LIMIT` に張り付いた (`issue_list_truncated` = 一部の issue が見えていない)
- Step 2 で着手できない (`dependency_blocked` = 依存の循環か駐車待ち / `issue_incomplete` = ラベルの無い未完成 issue)
- テスト弱体化が設計にトレースできない (`test_weakening_detected`)
- P2 動的修正が受入基準 (ゴール / 検証手順行) を変更した (`acceptance_criteria_change`。dev-spec フェーズ 9 → 11 で再承認)
- 受入監査が受入基準の改変を検知 (`verification_tampered`。P3 扱い、修正ループなし)

**`impl_timeout` はここに含めない** — implementer が応答しない issue は `needs-human` で駐車して**次の issue に進む**ので、run は停止しない (4.2a の表)。

停止時の処理:

1. **ラウンドのコミットはそのまま残す。** フェーズ範囲のテストは緑で、「ラウンドごとのコミット」の条件を満たしているため履歴に置いてよい。**フェーズ最終コミット (4.2e) は打たず、TODO.md の `- [x]` 化もしない** — 全体スイートと DoD を通っていないので、そのフェーズは完了していない。作業ツリーは clean のはずで、非クリーンなら 4.2d 手順 8 の汚染なので `git restore` で戻してから停止する。**issue のラベルを停止理由で振り分ける**:

   **上から順に評価し、最初に当てはまった行を採る** (`verification_tampered` のように複数行の記述に当てはまりうる理由があるため、順序が意味を持つ):

   | # | 停止理由 | ラベル | 再開のしかた |
   | - | --- | --- | --- |
   | 1 | **着手中の issue が無い時点での停止** — Step 1 / 1.5 / 2 の停止 (`docs_missing` / `design_not_approved` / `approval_stale` / `goals_missing` / `verification_missing` / `poc_marker_unresolved` / `github_prereq_failed` / `issue_list_truncated` / `dependency_blocked` / `issue_incomplete`) と Step 5 系の停止 (`goal_loop_exceeded` / `verification_tampered` / `acceptance_criteria_change`) | ラベル操作は行わない (対象の issue が無い) | JSONL の `p3_escalate` を駐車マーカーとし、**Step 0 手順 4 が再入時にユーザーへ確認してから再開する** |
   | 2 | 人間の判断が要るもの (P3 = `design_overview_break` / `test_weakening_detected` / `working_tree_polluted` / `exemptions_extract_failed` / **決定的な** `guard_agent_failed` / `review_agent_failed`) | **`needs-human` を貼り `in-progress` を外す** | 人間が対応した後、次の `/dev-impl` 起動時に Step 0 が確認してラベルを `ready` に戻す |
   | 3 | 再実行で解決しうるもの (`phase_fix_exceeded` / `spawn_budget_exceeded` / `tests_failing_before_commit` / **一過性の** `guard_agent_failed` / `review_agent_failed`) | `in-progress` のまま | `/dev-impl` の再実行で Step 2 が再開対象として拾う |

   **agent 失敗の「一過性」と「決定的」の区別は 4.2d 手順 1 に従う** (タイムアウト・JSON 破損は一過性、`TOO_MANY_FILES` / `NO_DESIGN_DOCS` / スキーマ不適合 / `diff_command_failed` / `unchecked_files` 非空 / `adjudicated` 不足 と 2 回連続の失敗は決定的)。決定的な失敗を再実行側に入れると、同じ入力で同じ停止を繰り返すだけで人間に渡る経路が無くなる。

   人間の判断が要る側で `in-progress` のままにしてはならない。**再実行がそのまま同じ状態から再開してしまい、人間が何もしていないのに前進したように見える**ため。
2. 停止理由を `~/.claude/logs/dev-impl.log` と JSONL (`event_type: p3_escalate`) と stdout 全てに詳細出力
3. HTML レポート (Step 7) を生成 → コミット (停止時もレポートだけは残す)
4. ユーザに通知 (通知内容もログ・review agent の出力から裏付けが取れる事実のみを記載する)。テンプレートは [references/notification-template.md](./references/notification-template.md) の `## エスカレ停止通知` 節を Read し、全フィールドを埋めて出力する (Read せず記憶から近似文面を出すと、最終成功 commit SHA や完了フェーズ数など裏付け必須フィールドが欠落し停止理由の追跡性が落ちる)。

## 既存プロジェクトでの注意

- 既存のコミット history と dev-impl のコミット粒度を混ぜたくない場合は、dev-impl 起動前に専用の作業ブランチを切ることを推奨 (dev-impl 自体は起動ブランチの切替を行わない)
- `bypassPermissions` モード推奨 (途中で permission prompt が出ると dev-impl が止まるため)
- launchd / cron などからヘッドレス実行する場合は `claude -p` 経由で、`--allowedTools` に `Bash,Read,Edit,Write,Glob,Grep,Agent,Skill` を渡す。**headless では AskUserQuestion を使わない** (答える人間がいないため、質問した時点でループが死ぬ)。エスカレ時は停止理由を stdout と JSONL に出力し、darwin なら `terminal-notifier` で通知して終了する。**AskUserQuestion を使う箇所は 3 つあり、headless ではいずれも同じ扱いにする** — Step 0 手順 2 (中断フェーズを取り込むか捨てるか)、Step 0 手順 4 (Step 5 系停止からの再開)、`needs-human` 駐車の解除。どれも「確認せず `p3_escalate` を出力して終了し、人間の対話セッションでの再開を待つ」とする (勝手に「取り込む」「解決済み」を選ぶと、人間が何もしていないのに前進したように見える)

## 範囲外 (やらないこと)

- 設計の合意 (DESIGN.md / DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md 生成) → `/dev-spec`
- TODO.md の初期生成 → `/dev-spec` (フェーズ 10)
- GitHub issue の初期生成 → `/dev-spec` (フェーズ 12)。dev-impl は既にある issue を実装するだけで、着手対象の issue を自分では作らない (例外は Step 4.6 の新フェーズ追加 (P1 / P2) と Step 5 のゴール未達対応。いずれも Step 4.6「新フェーズの issue 化」を通る)
- 並列実装 → 行わない (issue を 1 件ずつ逐次に処理する)
- git push → ユーザー手動
- ブランチ切替・PR 作成 → ユーザー手動 (or `/workflow-create-draft-pr`)
- 動作検証 (実 UI / API テスト) → ユーザーが DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md の検証手順に従って実施

## 関連スキル / agent

### 内部呼び出し (subagent)

各 agent の役割と検査内容の詳細は [references/orchestration-rationale.md](./references/orchestration-rationale.md) の `## 内部呼び出し subagent の役割詳細` にある。model の割当と根拠は上記「モデル方針」の表が正。

- **dev-impl-implementer** (4.2a / 4.2d / 4.2e のテストゲート再試行) — フェーズ 1 本を TDD で実装する**葉**の agent
- **architecture-guard** (4.2c) / **fix-lsp-warnings** (4.2b) — 機械判定と機械修正
- **review-tdd / review-quality / review-product-readiness / review-adversarial** (4.2c) — 観点別レビュー。gating と mode 決定は 4.2c
- **review-spec-compliance** (5.2) — 第三者受入監査。`PRODUCT_MODE=cli` では G_E2E の実行もこの agent が担当する
- **tech-investigation** (Step 1.5 の個別呼び出し) — 実装中に新たな技術検証が必要になった場合のみ (起動前の PoC は dev-spec フェーズ 5 の責務)
- **security-guidance プラグイン** — セキュリティレビューはこのプラグイン (Edit/Write 時の pattern 検知 + Stop hook の LLM diff review) に委譲。自作 subagent は持たない

**空虚テスト検出の分担**: review-tdd の `vacuous_negative_assertion` は**新規に書かれたテストそのものの空虚性**を、review-adversarial レンズ B の `vacuous_assertion` は**基準時点 (PHASE_START_SHA) からの空虚化**を見る。同一フェーズで両者が同種の指摘を上げることがあるが、検査している次元が違うため統合しない (統合するとどちらか一方の次元が検査されなくなる)。

**全ての subagent に作業ディレクトリ (`repo_dir`) を絶対パスで渡す。** subagent の Bash は呼び出しごとに cwd が親のものへ戻るため、渡さないと検査対象・編集対象が意図したディレクトリにならず、空差分で素通りする。

**全テストゲート / コミット / issue のラベル操作と close / RUN_FACTS 更新 / decisions.jsonl は必ず main が行う** (commit-msg-guard hook は親にしか効かないため)。

### 内部呼び出し (skill)

なし。P2 動的修正時の TODO 再生成は `../dev-spec/references/todo-generation.md` を Read してメインループで直営する (Skill ツール経由ではモデル指定が効かないため、skill 呼び出しは増やさない)。

(手動レビュー用の `workflow-review` skill と `workflow-commit` skill は dev-impl からは呼ばない。相当の処理は Step 4.2d / 4.2e が担う)

### 連携 hook

- **commit-msg-guard hook (`claude/hooks/commit-msg-guard.ts`)**: main が打つ**すべてのコミット**の subject 形式を PreToolUse(Bash) で機械検証する (4.2a / 4.2b / 4.2d のラウンドコミット、4.2e のフェーズ最終コミット、4.6 の動的修正コミット、Step 7 のレポートコミット)。検証するのは `<emoji> <type>: <subject>` の形と emoji / type の対応だけで、`[phase-<識別子>]` prefix や `[STRUCTURAL]` / `[BEHAVIORAL]` は検証対象外 (それらは本スキルと `rules/core/commit.md` の規約であって hook は見ない)。検証が働くのは `$GHQ_ROOT/github.com/skanehira/` 配下で作業しているときだけで、それ以外のリポジトリでは fail-open
- **agent-spawn-guard hook (`claude/hooks/agent-spawn-guard.ts`)**: PreToolUse(Agent) で、`MANDATED_MODEL` に登録された agent (dev-impl-implementer / architecture-guard / fix-lsp-warnings / review-*) の **model 未指定を deny** する。加えて review-spec-compliance の prompt に必須フィールドが揃っているかを検証する。無効化は `AGENT_SPAWN_GUARD=off`

### 前段 / 後段

- **dev-spec**: 前段。設計ループ (要件整理 〜 PoC 検証 〜 設計書 〜 TODO 生成)。承認ゲートで本スキルの起動方法を案内する
- **workflow-create-draft-pr**: 後段 (任意)。PR 作成はユーザーが手動で起動する
