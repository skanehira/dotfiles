# フェーズ実行の詳細手順 (dev-impl Step 4)

`dev-impl/SKILL.md` の Step 4 (各フェーズの実行) 各節から参照される実行コマンドの詳細。判断基準・観点 gating・ループ規則・エスカレ条件は SKILL.md 本体にあるので、そちらを先に読んでから該当節だけをここで参照する。


## 目次

- [変数の定義](#変数の定義)
- [4.2a: subagent の応答待ち時間](#42a-subagent-の応答待ち時間)
- [4.2: 事前判定](#42-事前判定)
- [4.2a: implementer の起動](#42a-implementer-の起動)
- [4.2d: 修正ラウンドの implementer 起動](#42d-修正ラウンドの-implementer-起動)
- [4.2c: 検査 fan-out の起動](#42c-検査-fan-out-の起動)
- [4.2c: 観点 gating 述語の算出コマンド](#42c-観点-gating-述語の算出コマンド)
- [4.2e: テスト弱体化検知コマンド](#42e-テスト弱体化検知コマンド)
- [4.2e: implementer 報告の JSONL 一括転記](#42e-implementer-報告の-jsonl-一括転記)
- [4.1: フェーズ変数の確定と start イベント](#41-フェーズ変数の確定と-start-イベント)
- [4.2a / 4.2e: fix ブリーフのスキーマ](#42a-42e-fix-ブリーフのスキーマ)
- [4.2a: implementer が status: failed を返したときの分岐](#42a-implementer-が-status-failed-を返したときの分岐)
- [4.2a: implementer が期待どおりに終わらなかった場合の分岐](#42a-implementer-が期待どおりに終わらなかった場合の分岐)
- [4.2c: adversarial_mode 別の起動順序](#42c-adversarial_mode-別の起動順序)
- [4.2c: 観点 gating 表](#42c-観点-gating-表)
- [4.2c: リスク面の表](#42c-リスク面の表)
- [4.2c: review-adversarial の mode 決定表](#42c-review-adversarial-の-mode-決定表)
- [4.2c: review-adversarial のスキップ述語表](#42c-review-adversarial-のスキップ述語表)

## 変数の定義

本ファイルのコマンドが前提にするシェル変数。**どれも「どこかで代入されているはず」ではなく、下記の時点で main が代入する。** JavaScript 風の `${...}` は Agent 呼び出しに埋める実値を表す (シェル変数ではない)。

| 変数 | 代入する時点 | 値 |
| --- | --- | --- |
| `REPO_DIR` | Step 1 (`REPO_ROOT` と同時) | `git rev-parse --show-toplevel` の絶対パス。**SKILL.md Step 1 が代入する `REPO_ROOT` と同じ値**で、本ファイルと agent への受け渡しでは `REPO_DIR` の名前を使う |
| `RUN_DIR` / `JSONL` / `LOG` | 起動時 (SKILL.md「進捗ログ」) | `~/.claude/logs/dev-impl/${run_id}` / その下の `decisions.jsonl` / `~/.claude/logs/dev-impl.log` |
| `SCRATCH_DIR` | Step 4.1 | `$RUN_DIR/reviews/phase-<識別子>` |
| `PHASE_START_SHA` | Step 4.1 | そのフェーズ開始時の `git rev-parse HEAD`。**JSONL のフェーズ `start` イベントにも記録する** (再入時の復元元) |
| `PHASE` | Step 4.1 | 短縮識別子 (`phase-4-a` 形式)。JSONL の `phase` に入れる値 |
| `PHASE_NAME` | Step 4.1 (env.sh 書き出しブロック) | issue タイトル形式 (`フェーズ4-a: 名前`)。agent へ渡す `phase_name` と `target_diff: phase:<...>` に使う |
| `ISSUE` | Step 4 の着手時 | 着手中の issue 番号 |
| `ROUND` | 各 fan-out / implementer 起動の直前 | **文字列として扱う**。初回 fan-out は `"0"`、修正ラウンド後の再検査は `phase_fix_round` の値、テストゲート再試行は `"tg<test_gate_retry>"`、報告不整合の再起動は `"retry<phase_fix_round>"`。`--argjson` で数値として書くと後 2 者が JSON エラーになる |
| `AGENTS_TO_SPAWN` | 各 fan-out の直前 | `<agent>:<model>:<mode>` を**改行区切り**で並べた文字列 (mode 無しは `-`)。空白区切りにしない — zsh は `$VAR` を単語分割しない |
| `PHASE_SPAWNS` / `RUN_SPAWNS` | Step 4.1 (フェーズ) / Step 0 か Step 1 (run) | カウンタの現在値。復元の正は `spawn` イベントの件数 (logging.md) |
| `REPO_SLUG` / `LIMIT` | Step 1 (run) | `<owner>/<repo>` と `gh issue list` の取得上限 (1000 件)。代入は run-bootstrap.md の `## run スコープ変数と env.sh の生成` |
| `PHASE_ID` | Step 4.1 (フェーズ) | issue タイトル `フェーズ<識別子>: <名前>` の識別子。`$SCRATCH_DIR` のパスと `### フェーズ<識別子>:` の引き当てに使う |
| `REPORT_PATH` | implementer 起動の直前 | 起動の種類ごとに分ける: `impl-report.json` (初回) / `impl-report-fix-<round>.json` (修正ラウンド) / `impl-report-testgate-<test_gate_retry>.json` (4.2e の再試行) / `impl-report-retry-<phase_fix_round>.json` (`impl_report_invalid` の再起動)。**衝突させない** — 4.2e 手順 4 の突合が成果物とラウンドを 1:1 で対応させるため |
| `EXEMPTIONS_COUNT` | 4.2c の事前ブロック | `jq 'length' "$SCRATCH_DIR/self-exemptions.json"`。**消えても再算出できる** (ファイルが残るため) ので env.sh には入れず、4.2d 手順 1 で使う直前に取り直してよい |
| `ROUND` | 検査 fan-out / 修正ラウンドを起動する直前 | 文字列。初回 fan-out は `"0"`、修正ラウンドは `"<phase_fix_round>"`、テストゲート再試行は `"tg<n>"`、報告不整合の再起動は `"retry<n>"`、フェーズ末の累積弱体化監査は `"final"` の **5 形式**。env.sh には書かない (カウンタと同じ理由) ので、必要な時点で JSONL から数え直す |
| `RESULT_JSON` | 検査結果を読む時 | 検査 agent が `output_path` に書いた結果 JSON のパス |
| `START_SHA` | Step 0 か Step 1 (run) | run 開始時の HEAD。**architecture-guard を最終フェーズで起動するときの差分の基準** (`BASE_SHA` として渡す)。代入は run-bootstrap.md の `## run スコープ変数と env.sh の生成`。**`PHASE_START_SHA` で代替しない** — フェーズ差分だけを見ると、過去フェーズで入って以降触られていない違反が検査対象から外れる |
| `SPEC_TEXT` | Step 4.1 (フェーズ) | issue 本文 (`gh issue view`) と、機能仕様 (`docs/features/UC-<n>.md`) + USECASES.md の該当 UC 節を連結した文字列 (無い構成では issue 本文のみ)。リスク面の一次算出の入力。**PHASE_CONTEXT を入力にしない** — PHASE_CONTEXT は 4.1.5 で組み立てるため循環する |
| `DOCS_DIR` | Step 1 (run) | `$REPO_DIR/docs` の絶対パス。`traces_to` の照合 (`## 4.2d 手順 3`) とリスク面の一次算出が読む。代入は run-bootstrap.md の `## run スコープ変数と env.sh の生成` |
| `RISK_FACES` | Step 4.1 (フェーズ) で一次、4.2c で二次を足して確定。**env.sh に `export` して Bash 呼び出しをまたいで保つ** | このフェーズが踏む攻撃面のカンマ区切り集合 (`## 4.2c: リスク面の表` の 5 つ)。PHASE_CONTEXT の `risk_faces` / adversarial の `mode` 決定 / 修正ラウンド上限の伸縮の 3 箇所で使う。空文字列は「どの面にも当たらない」を表す |

**`PHASE` と `PHASE_NAME` を取り違えない。** JSONL の集計は `PHASE` (短縮識別子) で行い、同じフェーズが 2 表記で混ざるとレポートのフェーズ集計が割れる。

## 4.2a: subagent の応答待ち時間

subagent が応答しないまま 30 分経過したかの判定に使う (SKILL.md 4.2a / 4.2c)。**run 全体の経過時間は計測しない** — 経過時間で run を打ち切る基準は無い。

**起動時刻はファイルに落とす。** 待ちの実体は Agent ツール呼び出しそのものなので、判定する Bash は必ず別の呼び出しになり、シェル変数は生き残らない (空のまま引き算すると必ず「30 分超」になり、正常な agent を打ち切る):

```bash
# Agent を起動する直前
date +%s > "$SCRATCH_DIR/spawn-$NAME-$ROUND.epoch"
# ... 応答を待つ ...
EPOCH_FILE="$SCRATCH_DIR/spawn-$NAME-$ROUND.epoch"
if [ -f "$EPOCH_FILE" ]; then
  waited_minutes=$(( ($(date +%s) - $(cat "$EPOCH_FILE")) / 60 ))
else
  # 不在のまま計算すると cat が空を返し「現在時刻 ÷ 60 分待った」ことになり、正常な agent を必ず打ち切る
  echo "起動時刻が残っていない。タイムアウト判定は行わず待ちを継続する"
fi
```

## 4.2: 事前判定

```bash
# Lua/Neovim プラグイン判定 (LSP 警告修正ステップの有無)
if test -f init.lua || test -d lua || ls plugin/*.lua >/dev/null 2>&1; then
  IS_NEOVIM_PLUGIN=true
else
  IS_NEOVIM_PLUGIN=false
fi
```

**リスク面は 4.1 で一次算出済み** (`$RISK_FACES`。env.sh から `source` で読む)。ここでは実装後の差分を見て**二次シグナルで補強する** — 一次は仕様の日本語だけを見るので、仕様に書かれていない形で面を踏んだ差分を取りこぼす。二次の算出は `## 4.2c: 観点 gating 述語の算出コマンド` の後半にある。

UI フェーズ判定 (`uiPhase`): `phase_tasks` / フェーズ名に UI キーワード (画面 / コンポーネント / page / component / style / CSS / レイアウト) が含まれる、または `related_source_files` にフロントエンド dir (`apps/web/`, `frontend/`, `src/components/`, `src/pages/` 等) が含まれる場合に true。**`product_mode: cli` の場合はキーワード判定を行わず常に false** (CLI 実装の「コマンド」「フラグ」等の語がキーワード誤爆するのを防ぐ)。

実行前に `docs/.dev-impl/<run_id>/phase-<識別子>-context.md` (Step 4.1.5 で組み立て済み) を Read し、YAML フィールド `product_mode` / `phase_tasks` / `phase_name` / `related_source_files` の値を確認する。以下のコードの `$PRODUCT_MODE` / `$PHASE_TASKS` / `$PHASE_NAME` / `$RELATED_SOURCE_FILES` は、その Read した値をそのままシェル変数に代入したものを指す (例: `PHASE_NAME="フェーズ3: ユーザー認証"`)。YAML パーサーは使わず、Read した内容から手動で代入する。

```bash
# $PRODUCT_MODE / $PHASE_TASKS / $PHASE_NAME / $RELATED_SOURCE_FILES は上記の通り PHASE_CONTEXT から代入済みの前提
if [ "$PRODUCT_MODE" = "cli" ]; then
  uiPhase=false
elif echo "$PHASE_TASKS $PHASE_NAME" | rg -qi '画面|コンポーネント|page|component|style|CSS|レイアウト' \
  || echo "$RELATED_SOURCE_FILES" | rg -q 'apps/web/|frontend/|src/components/|src/pages/'; then
  uiPhase=true
else
  uiPhase=false
fi
```

## 4.2a: implementer の起動

```javascript
await Agent({
  description: `フェーズ${phaseId} の実装`,
  subagent_type: "dev-impl-implementer",
  model: "opus",                       // 未指定は agent-spawn-guard hook が deny する
  run_in_background: false,            // main はここで待つ (待ちを 1h TTL の main に集約するのが本構造の要点)
  prompt: `mode: implement
phase_context_path: ${absPhaseContextPath}
repo_dir: ${absRepoDir}
report_path: ${absScratchDir}/impl-report.json

最終メッセージは report_path の絶対パス 1 行だけにせよ。要約や解説を書くな (要約は SendMessage で送ること)。`
})
```

**起動する直前に、そのラウンドの HEAD と起動時刻をファイルへ落とす。初回ラウンド (`mode: implement`) でも必ず行う** — SKILL.md Step 4 の完了判定 (a)-3 は**全ラウンド**でこのファイルとの比較を要求しており、書かずに進むと初回のたびに「起動前の SHA が残っていない = 判定不能」に倒れて `impl_report_invalid` になり、偽の `phase_fix_exceeded` でフェーズが止まる:

```bash
# $ROUND は初回が 0、修正ラウンドは phase_fix_round の現在値、
# テストゲート再試行は tg<n>、報告不整合の再起動は retry<n>、フェーズ末の累積弱体化監査は final
# (綴りの正は本ファイルの `## 変数の定義` の ROUND 行)
git -C "$REPO_DIR" rev-parse HEAD > "$SCRATCH_DIR/before-$ROUND.sha"
date +%s > "$SCRATCH_DIR/spawn-dev-impl-implementer-$ROUND.epoch"
```

## 4.2d: 修正ラウンドの implementer 起動

`mode: fix` は上記 4.2a の呼び出しに加えて `findings_paths` を渡す。**`model` はラウンド 1 が `opus`、ラウンド 2 以降が `fable`** (SKILL.md「修正ラウンドのモデル昇格」):

```javascript
{ subagent_type: "dev-impl-implementer",
  model: round === 1 ? "opus" : "fable",
  run_in_background: false,
  prompt: `mode: fix
phase_context_path: ${absPhaseContextPath}
repo_dir: ${absRepoDir}
report_path: ${absScratchDir}/impl-report-fix-${round}.json
findings_paths:
${fatalResultPaths.map(p => `  - ${p}`).join("\n")}
${FAMILY_BRIEF}
${round === 1 ? "" : ROUND2_PLUS_BRIEF}
最終メッセージは report_path の絶対パス 1 行だけにせよ。要約や解説を書くな。` }
```

`FAMILY_BRIEF` (**ラウンド 1 から必ず足す**):

```text
指摘箇所を局所的に塞ぐ前に、その箇所が属する不変条件を洗い出し、同じ族のエッジケースがまとめて閉じるかを
確認せよ。findings の evidence には検査側が走査した族の範囲が書かれているので、それを閉じるべき範囲の
下限とみなせ。族として閉じられない残りがあれば、その旨を報告の open_questions に明記せよ。
```

族単位をラウンド 1 から求めるのは、**局所修正が族を閉じないことが周回の直接原因**だと実測で分かっているためである ([orchestration-rationale.md](./orchestration-rationale.md) の `## 修正ラウンドのモデル昇格の根拠` の実測と、検査側の規範 `rules/core/references/finding-coverage.md`)。報告粒度と修正粒度は対になっていて、片方だけでは効かない。

`ROUND2_PLUS_BRIEF` (ラウンド 2 以降だけ足す。**過去ラウンドの実績を必ず埋めて渡す** — 「同じ族の隣が出続けている」ことは実装者からは見えないため):

```text
これはラウンド ${round}/${phaseFixBudget} で、ラウンド 1 では解消しきれなかった fatal である。
${phaseFixBudget} ラウンド目でも fatal が残ればこのフェーズはエスカレ停止となる。

過去ラウンドの経過: ${roundHistory}
(例: 「round 1 は A:100 を指摘 → 解消したが round 2 で B:79 が新規に出た」)
```

`phaseFixBudget` はフェーズ `start` イベントに記録した `context.phase_fix_budget` から取る (基底は `RISK_FACES` の有無で 3 / 4 に振れるので 3 を決め打ちしない)。`roundHistory` は JSONL の `fix_dispatch` の `fatal_summary` と、その次ラウンドの検査結果から main が組み立てる (main は findings 本文を読まないので、`{rule, file, line}` の射影と解消 / 未解消の別だけで足りる)。

すべて**絶対パス**で渡す。subagent の Bash は呼び出しごとに cwd が親のものへ戻るため、相対パスは意図したディレクトリで解決できない。

TDD の順序・フェーズスコープのテストのみ実行・コミット禁止・`docs/` 編集禁止・報告 JSON スキーマ・停止条件は `claude/agents/dev-impl-implementer.md` に常駐しているので**指示文で繰り返さない** (spawn ごとの prompt 固定費になるため)。

## 4.2c: 検査 fan-out の起動

**起動の形は `adversarial_mode` で変わる** (正は本ファイルの `## 4.2c: adversarial_mode 別の起動順序`):

| `adversarial_mode` | 起動のしかた |
| --- | --- |
| `full` | ① 下の事前ブロックを adversarial 1 件で流し、単独起動して完了を待つ → ② 汚染の突合 → ③ 事前ブロックを残りの観点で流し、fan-out |
| `weakening_only` / `skipped` | 事前ブロックを全観点で流し、1 回の fan-out で並列起動 |

`full` の adversarial はレンズ A が共有の作業ツリーを書き換えるため、並列にすると他観点が変異後のコードを読みうる (SKILL.md 4.2c)。`AGENTS_TO_SPAWN` は段ごとに作る — `full` の段 1 は `review-adversarial:opus:full` の 1 行だけ、段 3 はそれを除いた残り。

**起動前に 2 つを 1 ブロックで行う** (作業ツリーが clean であることの確認 / spawn の先行記録)。**どちらも「起動する前」でなければ意味を成さない**ので、上のどの段でも起動の前に必ずこのブロックを流す:

```bash
# このブロックが前提にする変数 (フェーズ / ラウンドのスコープ。値の出どころは冒頭「変数の定義」)
PHASE="phase-4-a"                    # 短縮識別子。JSONL の phase に入れる値
ROUND=0                              # 初回 fan-out は 0、修正ラウンド後の再検査は phase_fix_round と同値
# 形式は <agent>:<model>:<mode> を 1 行 1 件。mode を持たない agent は "-" を置く
# (logging.md の spawn スキーマが mode を要求するため、無い場合も明示的に「無い」と書く)。
# **空白区切りの 1 変数にしない** — zsh は $VAR を単語分割しないため、`for a in $VAR` が
# 全体を 1 要素として扱い、記録が 1 件しか残らない (実行シェルが zsh のとき必ず起きる)
# (例は weakening_only の一段 fan-out。full の場合は冒頭の表のとおり段ごとに作る —
#  段 1 = 'review-adversarial:opus:full' の 1 行だけ、段 3 = それを除いた残り)
# architecture-guard は最後の issue のフェーズでだけこの一覧に加える
AGENTS_TO_SPAWN='review-tdd:opus:-
review-adversarial:opus:weakening_only'

# (0) カウンタを JSONL から数え直す (env.sh の値ではなく spawn イベントの件数が正 = logging.md)
PHASE_SPAWNS=$(jq -r --arg p "$PHASE" 'select(.event_type=="spawn" and .phase==$p)|1' "$JSONL" | wc -l | tr -d ' ')
RUN_SPAWNS=$(jq -r 'select(.event_type=="spawn")|1' "$JSONL" | wc -l | tr -d ' ')

# (1) ツリーが clean であること。非空なら直前のラウンドのコミット漏れ (SKILL.md 4.2c)。
#     実装がコミット済みであることが「全 agent の git diff が同じ差分を返す」ことと
#     「検査 agent の書き換えが status に現れる」ことの前提になっている
git -C "$REPO_DIR" status --porcelain

# (2) これから起動する agent の spawn を JSONL に先に書く (起動後に書く規定だと構造的に落ちる = SKILL.md 4.2c)。
#     phase_spawns / run_spawns は「これから起動する 1 件を含めた値」を書く (logging.md)
# here-string で読む。パイプ (`printf ... | while`) にするとループが subshell で走り、
# ループ内で進めた PHASE_SPAWNS / RUN_SPAWNS がループを抜けた時点で失われる
while IFS= read -r a; do
  [ -n "$a" ] || continue
  NAME="${a%%:*}"; REST="${a#*:}"; MODEL="${REST%%:*}"; MODE="${REST#*:}"
  PHASE_SPAWNS=$((PHASE_SPAWNS + 1)); RUN_SPAWNS=$((RUN_SPAWNS + 1))
  jq -nc --arg ts "$(date +%Y-%m-%dT%H:%M:%S%z)" --arg p "$PHASE" \
     --arg n "$NAME" --arg m "$MODEL" --arg mo "$MODE" --arg r "$ROUND" \
     --argjson ps "$PHASE_SPAWNS" --argjson rs "$RUN_SPAWNS" '{
    timestamp:$ts, phase:$p, step:"review", event_type:"spawn", severity:"info",
    summary:("spawn " + $n + " (" + $m + ", round " + $r + ")"),
    context:{phase:$p, agent:$n, model:$m, mode:(if $mo == "-" then null else $mo end),
             round:$r, phase_spawns:$ps, run_spawns:$rs}}' >> "$JSONL"
done <<< "$AGENTS_TO_SPAWN"
```

**結果を全部受け取った後**に、同じ `git -C "$REPO_DIR" status --porcelain` を取る。非空なら検査 agent がソースを書き換えたまま戻していない (SKILL.md 4.2d 手順 8)。

gating で決まった観点 + architecture-guard を**同一メッセージ内の複数 Agent tool_use** として並列起動する。全呼び出しに共通で付ける末尾指示:

```text
最終メッセージは output_path の絶対パス 1 行だけにせよ。findings 本文や要約を書くな。
```

**`output_path` はラウンド番号で分ける (`-r${round}`)。** 固定名にするとラウンドごとに上書きされ、(a) `impl_done` の `review_outputs` に残る監査証跡が最終ラウンド分だけになり、(b) 4.2e 手順 4 の spawn 突合が「起動回数」ではなく「観点の種類数」を数えることになって、修正ラウンドを回したフェーズで必ず記録漏れと誤診する。

```javascript
// 最後の issue のフェーズのみ
{ subagent_type: "architecture-guard", model: "haiku", run_in_background: false,
  prompt: `target_diff: run:${runId}
design_path: ${absDocsDir}/DESIGN.md
design_detail_path: ${absDocsDir}/DESIGN_DETAIL_APP.md
BASE_SHA: ${runStartSha}
repo_dir: ${absRepoDir}
output_path: ${absScratchDir}/guard-r${round}.json
git diff コマンド自体が失敗した場合は ok:false, skip_reason:"diff_command_failed" とせよ。` }

// スキップ述語を満たさなければ実行。mode は 本ファイルの `## 4.2c: review-adversarial の mode 決定表` で決め、
// gating_decided に記録した値をそのまま渡す (再 fan-out でも同じ値を使う)
{ subagent_type: "review-adversarial", model: "opus",
  prompt: `mode: ${adversarialMode}
phase_name: ${phaseName}
phase_start_sha: ${phaseStartSha}
repo_dir: ${absRepoDir}
docs_dir: ${absDocsDir}
dev_server: ${devServerOrNull}
risk_faces: ${riskFaces}
scratch_dir: ${absScratchDir}
exemptions_path: ${absScratchDir}/self-exemptions.json
output_path: ${absScratchDir}/review-adversarial-r${round}.json` }   // PHASE_CONTEXT は渡さない
// mode: weakening_only のときは docs_dir / dev_server / risk_faces の行を省く (レンズ A/C を実行しないため不要)

// gating に応じて review-tdd / review-quality / review-product-readiness を同様に (model: opus)
//   共通で渡す: PHASE_CONTEXT の絶対パス / phase_name / phase_start_sha / repo_dir (絶対パス)
//               / output_path (`${absScratchDir}/review-<観点>-r${round}.json`)
//   review-tdd には加えて exemptions_path: ${absScratchDir}/self-exemptions.json を渡す
//     (SKILL.md 4.2c が review-tdd と review-adversarial への受け渡しを義務づけている)
//   review-product-readiness には加えて dev_server (url / start_command) と
//     snapshot_dir: ${absScratchDir}/product-readiness-snapshots/ を渡す
//     (snapshot_dir は視覚的回帰の参考データと dev サーバの PID ファイルの置き場。渡さないと
//      agent が起動した dev サーバを停止できず、以降のフェーズが古いサーバを検査し続ける)
```

`target_diff` に渡せるのは `HEAD` / `working_tree` / `phase:<フェーズ名>` / `run:<run_id>` の 4 値のみ (`claude/agents/architecture-guard.md` の「入力」節)。それ以外の文字列は agent 側の分岐に該当せず未定義動作になる。

**結果の読み方** (SKILL.md「main のコンテキスト規律」):

```bash
jq -c '{
  ok, skip_reason, dimension, mode, skipped_lenses,
  unchecked: (.unchecked_files // []),                  # architecture-guard: 未検証ファイル (非空なら未検証扱い)
  checked: (.checked_files // 0),                       # architecture-guard: 読んだファイル数
  sbd: ((.skipped_by_design // []) | length),           # architecture-guard: 対象外としたファイル数
  adjudicated: ((.adjudicated_exemptions // []) | length),  # review-tdd / review-adversarial: 免除を裁定した件数
  findings: [(.findings // .violations)[]? | {severity, rule, file, line}]
}' "$RESULT_JSON"
```

architecture-guard については、main 側で `checked + sbd + (unchecked の件数)` が**run 全体の差分のソースファイル数と一致すること**を突き合わせる (`git -C "$REPO_DIR" diff --name-only "$START_SHA" | wc -l` と比較。**基準は `PHASE_START_SHA` ではなく run 開始 SHA** — guard は最終フェーズで run 全体を検査するため)。一致しなければ guard の自己申告に漏れがある = 未検証として扱う。**ただし `skip_reason` が非 null のときはこの突合を行わない** — `no_layer_convention` は検査自体を意図的に省いた状態 (checked 0 が正)、`diff_command_failed` は差分が取れていない状態で、どちらも件数の一致を期待できない (各々の扱いは SKILL.md 4.2d 手順 1)。

`message` / `fix_proposal` は main では読まない (修正する implementer が JSON を自分で Read する)。

射影に `unchecked` と `adjudicated` を含めるのは、**どちらも「検査していないこと」を検出するための値**だから。前者が非空なら guard は差分の一部を見ていない (architecture-guard.md の `unchecked_files`)。後者は `exemptions_path` に渡した件数と突き合わせ、**渡した件数より少なければ免除の裁定が実行されていない** — 裁定は「実装者が検証しないと宣言した項目を第三者が裁く」仕掛けなので、実行の有無を検証しないと自己申告のままになる。どちらの判定も 4.2d 手順 1 で使う。

## 4.2c: 観点 gating 述語の算出コマンド

review-adversarial のスキップ述語と mode 判定、review-quality を最終フェーズ以外でも起動させる条件を算出する。**フェーズの初回 fan-out 前に 1 回だけ実行し、結果を `gating_decided` に記録する。** 4.2d の再 fan-out では再評価しない。例外は 1 つだけで、**初回評価で review-adversarial を skip したフェーズ**に限り、各修正ラウンドの fan-out 直前に本節の述語一式を再算出して skip → 実行 の転換を判定する (SKILL.md 4.2c の遷移規定)。テストへの接触を理由にした review-adversarial の起動は、ラウンドごとではなく**フェーズ末に 1 回**、累積差分に対して行う ([phase-gates.md](./phase-gates.md) の `## 4.2e: 累積テスト差分の弱体化監査`)。

```bash
CHANGED=$({ git diff --name-only "${PHASE_START_SHA}"; git ls-files --others --exclude-standard; } | sort -u)
# LINES は tracked (コミット済との差分) + untracked (新規ファイル) の合算。ラウンドごとにコミット
# するため fan-out 時点の untracked は通常 空だが、コミット漏れがあっても取りこぼさないよう両方を足す
# (clean なときは untracked が 0 なので tracked 差分と一致する)
TRACKED_LINES=$(git diff --shortstat "${PHASE_START_SHA}" | rg -o '[0-9]+' | tail -n +2 | paste -sd+ - | bc)
UNTRACKED_LINES=$(git ls-files --others --exclude-standard -z | xargs -0 cat 2>/dev/null | wc -l)
LINES=$(( ${TRACKED_LINES:-0} + ${UNTRACKED_LINES:-0} ))
# テストコードへの変更検知は「ファイル名」と「差分内容」の 2 層、かつ tracked/untracked 両方を見る
# (Rust のインラインテストは src ファイル内に書かれるためファイル名 glob では検知できず、
# その内容層も git diff だけでは untracked ファイルを見ないため、両方を欠くと検知が完全に抜ける)。
# 内容層は .md / docs/ を除外する (ドキュメント散文中の `test(` 等の字句引用による誤検知を防ぐため)
TEST_FILE_CHANGED=$(echo "$CHANGED" | rg '(_test\.(go|rs|py)|\.test\.|\.spec\.|_spec\.|__tests__/|(^|/)tests?/|(^|/)test_[^/]*\.py)' || true)
TRACKED_CONTENT_CHANGED=$(git diff "${PHASE_START_SHA}" -U0 -- ':!*.md' ':!docs/' | rg '^[+-].*(#\[(test|cfg\(test\)|tokio::test|rstest)\]|func Test[A-Z]|\b(it|test|describe)\s*\(|def\s+test_|@pytest\.)' || true)
UNTRACKED_CONTENT_CHANGED=$(git ls-files --others --exclude-standard -z -- ':!*.md' ':!docs/' | xargs -0 -I{} rg -l '#\[(test|cfg\(test\)|tokio::test|rstest)\]|func Test[A-Z]|\b(it|test|describe)\s*\(|def\s+test_|@pytest\.' {} 2>/dev/null || true)
TEST_CONTENT_CHANGED="${TRACKED_CONTENT_CHANGED}${UNTRACKED_CONTENT_CHANGED}"
# 条件2: .md/docs 以外の変更ファイルが無いか (無ければ行数不問で skip 可)
NON_DOC_CHANGED=$(echo "$CHANGED" | rg -v '\.md$|(^|/)docs/' || true)
# 条件3: CI・ビルド/テスト設定の変更があるか
CI_FILES_CHANGED=$(echo "$CHANGED" | rg '\.github/|config|package\.json|Cargo\.toml|go\.mod|Makefile|justfile|deno\.json' || true)
# review-quality の追加起動条件: 消費すると無効化される資源 (ローテーション有効な refresh token・
# nonce・ワンタイムコード・べき等キー・使い捨て署名 URL) を扱う差分か
TRACKED_CONSUMABLE=$(git diff "${PHASE_START_SHA}" -U0 -- ':!*.md' ':!docs/' | rg -i '^[+-].*(refresh[_-]?token|\bnonce\b|one[_-]?time|idempotenc|\botp\b|presigned)' || true)
UNTRACKED_CONSUMABLE=$(git ls-files --others --exclude-standard -z -- ':!*.md' ':!docs/' | xargs -0 -I{} rg -li 'refresh[_-]?token|\bnonce\b|one[_-]?time|idempotenc|\botp\b|presigned' {} 2>/dev/null || true)
CONSUMABLE_CHANGED="${TRACKED_CONSUMABLE}${UNTRACKED_CONSUMABLE}"
# 認証・認可・セッションに触れる差分 (review-adversarial の mode を full に上げる条件の 1 つ)。
# CONSUMABLE と同じ 2 層 (tracked の差分内容 + untracked のファイル内容) で見る
TRACKED_AUTH=$(git diff -U0 "${PHASE_START_SHA}" -- ':!*.md' ':!docs/' | rg -i '^\+.*(\bauth|\bsession\b|\bcookie\b|\bjwt\b|\blogin\b|\blogout\b|authoriz|credential|\bpassword\b)' || true)
UNTRACKED_AUTH=$(git ls-files --others --exclude-standard -z -- ':!*.md' ':!docs/' | xargs -0 -I{} rg -li '\bauth|\bsession\b|\bcookie\b|\bjwt\b|\blogin\b|\blogout\b|authoriz|credential|\bpassword\b' {} 2>/dev/null || true)
AUTH_CHANGED="${TRACKED_AUTH}${UNTRACKED_AUTH}"
```

続けて**リスク面の二次シグナル**を評価し、4.1 の一次算出に足し込む (面の定義と各面のパターンは `## 4.2c: リスク面の表`)。**二次は言語依存**なので、対応表に無い言語のプロジェクトでは評価せず `SECONDARY_SIGNAL=false` を記録する (判定材料が片方だけだったことを後から分かるようにする)。

```bash
. "$SCRATCH_DIR/env.sh"          # 4.1 で算出した RISK_FACES を読み直す
has_face() { echo ",$RISK_FACES," | rg -q ",$1,"; }
add_face() { has_face "$1" || RISK_FACES="${RISK_FACES}${RISK_FACES:+,}$1"; }
DIFF=$(git diff -U0 "${PHASE_START_SHA}" -- ':!*.md' ':!docs/'; \
       git ls-files --others --exclude-standard -z -- ':!*.md' ':!docs/' | xargs -0 cat 2>/dev/null)

# 対応言語か (表に無い言語では二次を評価しない)
if echo "$CHANGED" | rg -q '\.(ts|tsx|mts|cts|js|jsx|mjs|cjs)$'; then
  SECONDARY_SIGNAL=true
  echo "$DIFF" | rg -q 'AbortController|\bsignal\b|debounce|setTimeout|setInterval|suspend|cancel|pending|inFlight|compare-and-set|\bversion\b|\bseq\b' \
    && add_face async_roundtrip
  echo "$DIFF" | rg -qi 'inArray|\bIN \(|\bLIMIT\b|batch|\.length\b' && add_face persistence_limit
  echo "$DIFF" | rg -q 'invalidate|refetch|revalidate' && add_face ui_consistency
else
  SECONDARY_SIGNAL=false
fi
# 既存の 2 述語は面にそのまま対応する
[ -n "$AUTH_CHANGED" ] && add_face auth_error_path
[ -n "$CONSUMABLE_CHANGED" ] && add_face consumable
# 確定値を書き戻す (以降の Bash 呼び出しと gating_decided が読む)
sed -i '' "s|^export RISK_FACES=.*|export RISK_FACES=\"$RISK_FACES\"|" "$SCRATCH_DIR/env.sh"
printf '%s\n' "$RISK_FACES" > "$SCRATCH_DIR/risk-faces.txt"
```

判定条件テーブル (review-adversarial の skip/実行の遷移規則と mode 決定、`$CONSUMABLE_CHANGED` による review-quality の起動) は 本ファイルの `## 4.2c: review-adversarial のスキップ述語表` を参照。

## 4.2e: テスト弱体化検知コマンド

```bash
# (1) テストファイルの削除
git diff "${PHASE_START_SHA}" --diff-filter=D --name-only -- '*test*' '*spec*'

# (2) skip/only/ignore の追加。**検知はテストファイルの差分に限定する** — 対象を絞らないと
#     プロダクションコードの `iter().skip(` や `array.only(` のような無関係な行にマッチし、
#     偽陽性のたびにトレース確認 (SKILL.md 4.2e) を人手で回すことになる
TEST_PATHS=$(git diff "${PHASE_START_SHA}" --name-only \
  | rg '(_test\.(go|rs|py)|\.test\.|\.spec\.|_spec\.|__tests__/|(^|/)tests?/|(^|/)test_[^/]*\.py)' || true)
WEAKENING_HITS=0
if [ -n "$TEST_PATHS" ]; then
  WEAKENING_HITS=$(printf '%s\n' "$TEST_PATHS" | tr '\n' '\0' \
    | xargs -0 git diff "${PHASE_START_SHA}" -U0 -- \
    | rg '^\+.*\b(it|test|describe|context|suite)\.(skip|only)\s*\(|^\+\s*(xit|xdescribe|xtest)\b|^\+.*#\[ignore\]|^\+\s*@(unittest\.)?skip|^\+.*t\.Skip\(' \
    | tee /dev/stderr | wc -l | tr -d ' ')
fi
echo "弱体化の検出行数: $WEAKENING_HITS"   # 0 でなければ 4.2e のトレース確認へ

# (3) Rust のインラインテスト (src ファイル内の #[cfg(test)]) は (2) のパスに載らないので別途見る
git diff "${PHASE_START_SHA}" -U0 -- '*.rs' | rg '^\+.*#\[ignore\]' || true
```

`.skip(` / `.only(` を単独で照合せず、直前のトークン (`it` / `test` / `describe` / `context` / `suite`) を含めて照合するのも同じ理由 (メソッドチェーンの `.skip(` との区別)。

**判定は exit code ではなく出力行数で行う。** (2) は `if` で囲ってあるため、テスト差分が 1 件も無いフェーズでは中身が実行されず全体が exit 0 になる。「何も検出しなかった」と「検出器が走らなかった」が exit code では区別できないので、`| wc -l` で数えて 0 件であることを確認する。

上記の検知は**陽性・陰性の両対照を取ってある**: テストファイルに `it.skip(` を足すと 1 件検出し、プロダクションコードに `.values().skip(1)` を足しても 0 件のままであることを実測で確認済み (パス制限を外した以前の形は後者にも誤爆した)。

## 4.2e: implementer 報告の JSONL 一括転記

SKILL.md 4.2e 手順 6 の転記は、**項目ごとに Bash を呼ばず 1 回の実行で全件を流し込む**。実測 (4 フェーズ) で JSONL 239 件中 121 件が `design_decision` / `open_question` の転記で、これを逐次実行すると main の往復がフェーズあたり 30 回近く増える。

`REPORT_PATH` は implementer 報告 (`report_path`) の絶対パス、`JSONL` は当該 run の `decisions.jsonl`、`PHASE` は Step 4.1 で代入した短縮識別子で、**JSONL の `phase` にはこれを入れる** (1 行ログと同じ `phase-3` 形式) (フェーズ名そのままだと同じフェーズが別表記で混ざり、HTML レポートのフェーズ集計が割れる)。

```bash
jq -c --arg phase "$PHASE" --arg ts "$(date +%Y-%m-%dT%H:%M:%S%z)" '
  [ (.design_decisions[]?      | {event_type:"design_decision",      context:.}),
    (.open_questions[]?        | {event_type:"open_question",        context:.}),
    (.verification_skipped[]?  | {event_type:"verification_skipped", context:(. + {source:"implementer"})}),
    (.spec_lookups[]?          | {event_type:"spec_lookup",          context:{path:.}}),
    (.self_review              | select(. != null) | {event_type:"self_review", context:.}) ][]
  | . + {timestamp:$ts, phase:$phase, step:"implement",
         severity:(if .event_type == "open_question" or .event_type == "verification_skipped" then "warn" else "info" end),
         summary:(. as $e
                  | (($e.context.decision // $e.context.question // $e.context.target
                      // $e.context.path // $e.context.notes // "") | tostring) as $c
                  | (if $c == "" then ($e.context | tostring) else $c end) | .[0:200])}
' "$REPORT_PATH" >> "$JSONL"
```

`severity` を出し分けるのは、`open_question` と `verification_skipped` の severity を `warn` と定める [logging.md](./logging.md) の規定に合わせるため。`verification_skipped` に `source: "implementer"` を付けるのは、同じ event_type を 4.2c の adversarial スキップでも使い context の形が異なるため (識別キーの規定は [logging.md](./logging.md))。

出力を main のコンテキストに載せない (`>>` でファイルへ直行させ、標準出力に流さない)。転記件数だけ確認したい場合は `wc -l` の差分を見る。

1 行ログ側にも同じ件数を出す必要はない (JSONL が正)。**`spawn` / `fix_dispatch` / エスカレ系はリアルタイム監視の価値があるので、発生時に 1 件ずつ追記する** (一括化の対象は implementer 報告由来の転記だけ)。

## 4.1: フェーズ変数の確定と start イベント

**まず変数を確定し、作業ファイル置き場を作り、`$SCRATCH_DIR/env.sh` に書き出してから、`start` イベントを書く** (Bash の呼び出しをまたぐと変数が消えるため。値の一覧と意味は本ファイルの `## 変数の定義`)。**この順序で行う** — `SCRATCH_DIR` を作る前に env.sh は書けない:

```bash
# 値は着手中の issue から取る (下は「フェーズ4-a: ノードの編集と階層操作」= issue #15 の例)
PHASE_ID="4-a"                          # issue タイトル `フェーズ<識別子>: <名前>` の識別子
ISSUE=15                                # issue 番号
PHASE="phase-$PHASE_ID"                 # JSONL の phase に入れる短縮識別子
PHASE_NAME="フェーズ$PHASE_ID: ノードの編集と階層操作"   # agent へ渡す phase_name

# 作業ファイル置き場 (implementer の報告 JSON・検査結果 JSON・攻撃スクリプト等)。
# **リポジトリの外に置く**ことでコミット対象への混入を防ぎ、エスカレ停止後の再入時にも残す
SCRATCH_DIR="$RUN_DIR/reviews/$PHASE"
mkdir -p "$SCRATCH_DIR"

# --- リスク面の一次算出 (仕様の記述から。面の定義は `## 4.2c: リスク面の表`) ---
# **PHASE_CONTEXT を入力にしない** — PHASE_CONTEXT は 4.1.5 で組み立てるので、
# そこから面を取ると「面が要る 4.1 と、面を書く 4.1.5」が循環する。issue 本文と
# docs を直接読めば循環しない。
ISSUE_BODY=$(gh issue view "$ISSUE" --json body -q .body) || {
  # 取得に失敗したまま進むと SPEC_TEXT が痩せ、**全フェーズが黙って「面なし」に倒れる**。
  # 面の有無は adversarial の mode と修正ラウンド上限の両方を決めるので影響が大きい
  echo "issue 本文を取得できない。リスク面の算出が成立しないので停止する"; exit 1
}
# 機能仕様と UC 節を連結する (面の語彙「締め出し」「中断」等は BR 側に住むため、
# issue 本文だけでは一次シグナルが鳴らない)。無い構成では issue 本文のみで判定する
UC_ID=$(rg -o "^### フェーズ${PHASE_ID}: .*<!-- ucs: (UC-[0-9]+)" -r '$1' "$DOCS_DIR/TODO.md" 2>/dev/null || true)
FEATURE_SPEC_TEXT=""
UC_SECTION_TEXT=""
if [ -n "$UC_ID" ]; then
  [ -f "$DOCS_DIR/features/$UC_ID.md" ] && FEATURE_SPEC_TEXT=$(cat "$DOCS_DIR/features/$UC_ID.md")
  [ -f "$DOCS_DIR/USECASES.md" ] && UC_SECTION_TEXT=$(awk "/^## ${UC_ID}:/{f=1} f && /^## /&& !/^## ${UC_ID}:/{exit} f" "$DOCS_DIR/USECASES.md")
fi
SPEC_TEXT="$ISSUE_BODY
$FEATURE_SPEC_TEXT
$UC_SECTION_TEXT"
RISK_FACES=""
add_face() { RISK_FACES="${RISK_FACES}${RISK_FACES:+,}$1"; }
echo "$SPEC_TEXT" | rg -qi '並行|同時|競合|中断|再開|締め出し|巻き戻し|順序|冪等|再試行|リトライ|応答待ち' \
  && add_face async_roundtrip
echo "$SPEC_TEXT" | rg -qi '上限|件数|バイト|文字数|深さ|一括|バッチ|ページング' \
  && add_face persistence_limit
echo "$SPEC_TEXT" | rg -qi '認証|認可|セッション|失効|ログイン|ログアウト|権限' \
  && add_face auth_error_path
echo "$SPEC_TEXT" | rg -qi '一覧|遷移|戻る|再取得|再描画|反映' \
  && add_face ui_consistency
echo "$SPEC_TEXT" | rg -qi '連番|採番|一度きり|使い捨て|消費|ワンタイム' \
  && add_face consumable

cat > "$SCRATCH_DIR/env.sh" <<EOF
export PHASE="$PHASE"
export PHASE_NAME="$PHASE_NAME"
export PHASE_ID="$PHASE_ID"
export ISSUE=$ISSUE
export SCRATCH_DIR="$SCRATCH_DIR"
export PHASE_START_SHA="$PHASE_START_SHA"
export RISK_FACES="$RISK_FACES"
EOF
```

**語彙は 18 件の実測 finding (2026-08-22、mind の run) から逆算したもので、次の run で当たるかは未検証である。** そのため 4.2c で `gating_decided` の `basis.risk_faces` に記録し、そのフェーズで実際に出た `rule` と後から突き合わせられるようにする (外れていたら語彙を直す)。**再入時は `gating_decided` の `basis.risk_faces` から復元する** (env.sh は再入で作り直さないので通常は残るが、記録の方を正とする)。

変数が揃ったところで、JSONL のフェーズ `start` イベントを書く (**この順序を守る** — 先に書こうとすると `$PHASE` も `$ISSUE` も未定義で、`--argjson issue "$ISSUE"` が JSON パースエラーで落ちる):

```bash
# 予算は再入で引き上がる値なので必ず context に載せる。載せないと Step 0 の復元が
# 既定にフォールバックし、再入のたびに引き上げが失われて同じ上限で止まり続ける
PHASE_SPAWNS_BUDGET=${PHASE_SPAWNS_BUDGET:-33}
# phase_fix_budget の基底は RISK_FACES の有無で決まる (SKILL.md「カウンタと予算」が正)。
# 基底を載せずに既定 3 で書くと、再入時に面ありフェーズの上限が黙って 1 下がる
FIX_BUDGET_BASE=$([ -n "$RISK_FACES" ] && echo 4 || echo 3)
PHASE_FIX_BUDGET=${PHASE_FIX_BUDGET:-$FIX_BUDGET_BASE}
jq -nc --arg ts "$(date +%Y-%m-%dT%H:%M:%S%z)" --arg p "$PHASE" \
   --arg sha "$PHASE_START_SHA" --argjson issue "$ISSUE" \
   --argjson psb "$PHASE_SPAWNS_BUDGET" --argjson pfb "$PHASE_FIX_BUDGET" '{
  timestamp:$ts, phase:$p, step:"start", event_type:"start", severity:"info",
  summary:("フェーズ開始 (issue #" + ($issue|tostring) + ")"),
  context:{issue:$issue, phase_start_sha:$sha,
           phase_spawns_budget:$psb, phase_fix_budget:$pfb}}' >> "$JSONL"
```

以降このフェーズで Bash を呼ぶときは、冒頭で run スコープと合わせて `source` する:

```bash
. "$HOME/.claude/logs/dev-impl/<run_id>/env.sh"
. "$SCRATCH_DIR/env.sh"
```

## 4.2a / 4.2e: fix ブリーフのスキーマ

**fix ブリーフ**: `mode: fix` の implementer は `findings_paths` の JSON しか入力に取らないので、検査結果 JSON が存在しないこの経路でも main が同じ形式のファイルを書いて渡す。書き出し先は `<SCRATCH_DIR>/impl-failure-<phase_fix_round>.json`:

```json
{
  "ok": false,
  "dimension": "implementation",
  "findings": [
    {
      "severity": "high",
      "rule": "tests_failing",
      "file": "<報告の files_changed の代表 1 件、無ければ null>",
      "line": null,
      "message": "<implementer 報告の reason と、直前のテスト実行出力の末尾 30 行>",
      "fix_proposal": null
    }
  ]
}
```

`rule` には implementer 報告の `reason` (`tests_failing` / `spec_insufficient`) をそのまま入れる。4.2e のテストゲート失敗で書く `<SCRATCH_DIR>/test-failure-<test_gate_retry>.json` も同じスキーマを使う (`rule: "tests_failing_before_commit"`)。

## 4.2a: implementer が status: failed を返したときの分岐

報告の `reason` に応じて分岐する。

| `reason` | 対処 |
| --- | --- |
| `design_overview_break` | **即エスカレ停止** (P3、commit しない) |
| `test_weakening_suspected` | 4.2e と同じトレース確認を main が行い、トレース不能なら `test_weakening_detected` でエスカレ停止 |
| `tests_failing` | 本ファイルの `## 4.2a / 4.2e: fix ブリーフのスキーマ`を書いて `mode: fix` で再起動する (4.2d の修正ラウンドと同じ扱い。`phase_fix_round` を共有する) |
| `spec_insufficient` | **fix で再起動しない。** 足りないのは設計情報であって修正の指示ではなく、fix ブリーフが運べるのは reason 文字列とテスト出力だけなので、同じ情報で再実行しても同じ理由で止まる。**Step 4.6 の P2 (`design_detail_gap`) として扱い**、報告の `reason` が指す不足を DESIGN_DETAIL に補ってから `mode: implement` で再起動する (`phase_fix_round` を進める。**`report_path` と `spawn` の `context.round` は `impl_report_invalid` の再起動と同じ retry 系** — `impl-report-retry-<phase_fix_round>.json` / `"retry<phase_fix_round>"`)。補うべき内容が概要設計に及ぶなら P3 |

## 4.2a: implementer が期待どおりに終わらなかった場合の分岐

**原因で 2 つに分ける。** 混ぜると「フェーズ内で再起動する」のか「issue を駐車して次へ行く」のかが決まらない。どちらも検査 agent の `guard_agent_failed` / `review_agent_failed` と同じく**パス扱いにしない**。**`impl_timeout` は「エスカレ停止」ではない** (run は次の issue へ進む) ので、フェーズ内エスカレ条件の表にも停止条件のリストにも載せない。

| reason | 該当する状況 | 対処 |
| --- | --- | --- |
| `impl_report_invalid` | `report_path` が不在 / `jq` でパース不能 / 必須フィールド (`status` / `summary` / `files_changed` / `test_result`) の欠落 / `files_changed` が空 (完了判定 (a)) | **フェーズ内で処理する。** `phase_fix_round += 1` して `mode: implement` で再起動 (fix ではない — 何が実装されたか分からないため)。**`report_path` は `impl-report-retry-<phase_fix_round>.json`、`spawn` 記録の `context.round` は文字列 `"retry<phase_fix_round>"`** にする (4.2e 手順 4 の集合突合が成果物と 1:1 で対応するようにするため。変換は同手順の sed の `impl-report-retry-` 行が対応する — 定義済みなので足さない)。3 回で `phase_fix_exceeded` でエスカレ停止。issue は `in-progress` のまま |
| `impl_timeout` | spawn から **30 分**応答が無い (計測は本ファイルの `## 4.2a: subagent の応答待ち時間` 節) | **run は止めない。** その issue に `gh issue comment <N>` で停止理由 (何分待って応答が無かったか・そのラウンドまでに積まれたコミット) を残し、`gh issue edit <N> --add-label needs-human --remove-label in-progress` で駐車して、**次の着手可能な issue に移る** (Step 0 の再開確認は issue コメントに理由が書かれている前提で「解決したか」を尋ねるので、コメントが無いと人間が何を判断すればよいか分からない) (`in-progress` を外さないとラベルが併記になり Step 2 の判定が割れる)。着手可能な issue が他に無ければ `dependency_blocked` と同じ扱いで停止する |

## 4.2c: adversarial_mode 別の起動順序

`mode: full` のレンズ A は共有の作業ツリー上でソースを直接書き換えるため、fan-out に入れず単独で先に走らせる。

| `adversarial_mode` | 起動のしかた |
| --- | --- |
| `full` | ① review-adversarial を単独起動して完了を待つ → ② 汚染の突合 → ③ 残りの観点を fan-out |
| `weakening_only` / `skipped` | 全観点を 1 回の fan-out で並列起動 |

`architecture-guard` は**最後の issue のフェーズでだけ** fan-out に加える (下の gating 表)。それ以外のフェーズでレイヤ境界を担保するのは、プロジェクト側の lint (`lint_command`) である。

## 4.2c: 観点 gating 表

フェーズごとに 1 回だけ評価し、決まった集合を `gating_decided` に記録する。

| タイミング        | 実行観点                                                                                            |
| ----------------- | --------------------------------------------------------------------------------------------------- |
| 毎フェーズ        | review-adversarial (`mode` は下表で決める。下記スキップ述語で skip 可) |
| テスト差分があるフェーズ (`$TEST_FILE_CHANGED` または `$TEST_CONTENT_CHANGED` が非空) | 上記 + review-tdd                              |
| UI を触るフェーズ (`uiPhase == true` **または `RISK_FACES` に `ui_consistency` を含む**) | 上記 + review-product-readiness (dev_server が無ければ skip)。**条件を面まで広げたのは実測に基づく** (2026-08-22、mind の run) — 9 本で high 6 件 = 0.67 件/本と全観点で最も産出率が高く、単独稼働は 24 分しかない (検査は並列なので実時間はほぼ無料)。検出内容も実機でしか出ないもの (404 デッドループ / ErrorBoundary 不在 / 二度押しで重複登録) で、他観点では代替できない |
| **最後の issue** | 全観点フル (tdd / quality / product-readiness / adversarial) **+ architecture-guard** — 境界違反は累積的で、途中で入ったものも最終差分に残るため、ここで 1 回検査すれば足りる。毎フェーズ起動していた頃の実測 (2026-08-22、mind の run) は 28 回で違反 1 件だった |
| **`$CONSUMABLE_CHANGED` が非空のフェーズ** | 上記 + review-quality (最後の issue でなくても起動する。多重消費・恒久エラー分岐の漏れはレイヤ境界の検査では検知できないため) |
| `PRODUCT_MODE=cli` | review-product-readiness を**一切起動しない** (`uiPhase` が常に `false`。「最後の issue」の全観点フルからも除外する。cli の G_E2E は Step 5.2 で review-spec-compliance が担当する) |

## 4.2c: リスク面の表

**面の集合 `RISK_FACES` は 2 段で決まる。** 一次は実装前に仕様の日本語から出し (`## 4.2: 事前判定` の
`### リスク面の一次算出`)、二次はこの表のコード差分パターンで補強する。**二次は言語依存なので、
表に無い言語では一次だけで判定し、`gating_decided` の `basis.secondary_signal` に `false` を記録する**
(判定材料が片方だけだったことを後から分かるようにする)。

| 面 ID | 何を踏むか | 二次シグナル (コード差分。TypeScript / JavaScript の例) | 実測 (2026-08-22 mind の run。high 18 件中) |
| --- | --- | --- | --- |
| `async_roundtrip` | 非同期の往復と中断可能な状態。応答待ちの間に別の操作が通る / 中断の解除漏れ / 重複要求 | `AbortController` / `signal` / `debounce` / `setTimeout` / `setInterval` / `suspend`・`cancel`・`pending`・`inFlight` の識別子 / compare-and-set・`version`・`seq` | **10 件 (56%)** |
| `persistence_limit` | 永続化層の上限・境界。可変長の入力をそのまま DB へ渡す経路 | SQL の `inArray` / `IN (` / `LIMIT` / バッチ書き込み / 文字列長を文字数で数えている箇所 | 3 件 (17%) |
| `auth_error_path` | 認証・認可・セッションとそのエラー経路 | `$AUTH_CHANGED` が非空 (`## 4.2c: 観点 gating 述語の算出コマンド`) | 2 件 (11%) |
| `ui_consistency` | 画面間の不整合。遷移して戻ったときにキャッシュが古いまま | ルータ遷移とキャッシュ無効化 (`invalidate` / `refetch` / `revalidate`) が同じ差分にある | 2 件 (11%) |
| `consumable` | 消費型資源の採番。一度使うと無効になる値の二重消費 | `$CONSUMABLE_CHANGED` が非空 (同上) | 1 件 (6%) |

**既存の 2 述語 (`$AUTH_CHANGED` / `$CONSUMABLE_CHANGED`) が捕捉できていたのは 18 件中 3 件 (17%) だけ**で、
最大クラスタの `async_roundtrip` に対応する信号が無かった。これが面を導入した理由である。

## 4.2c: review-adversarial の mode 決定表

`claude/agents/review-adversarial.md` の「モード」節が受け側の規定。

| 条件 (いずれかが真なら `full`) | 述語 |
| --- | --- |
| **`RISK_FACES` が非空** | 上の表のいずれかの面を踏む (一次または二次のどちらかで当たれば非空) |
| **テスト差分が無く、実装が 20 行を超えて積まれたフェーズ** | `$TEST_FILE_CHANGED` と `$TEST_CONTENT_CHANGED` がともに空、かつ `$LINES` > 20 |
| 最後の issue | 自分以外に open issue が残らない |


**どの行にも当たらなければ `weakening_only`** (レンズ B のみ。docs を読まず攻撃も実行しない)。

**`full` で起動するときは `risk_faces` を prompt に渡し、その面を名指しで優先攻撃させる。** 面の名指しが
無いと「一般的に攻撃せよ」としか伝わらず、最大クラスタに当たるかが運任せになる (渡し方は
[phase-context.md](./phase-context.md) の `## 渡し方`)。

## 4.2c: review-adversarial のスキップ述語表

機械判定であり、actor の裁量では skip しない。全条件が真の場合のみ skip 可。

| # | 条件                                                                                                                                              | 意図                                                                                                                                                 |
| - | ------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1 | `$TEST_FILE_CHANGED` と `$TEST_CONTENT_CHANGED` がともに空                                                                                        | テスト変更時はレンズ B 必須。ファイル名 + 差分内容の 2 層、tracked/untracked 両方で判定 (言語別の具体パターンは本ファイルの `## 4.2c: 観点 gating 述語の算出コマンド` が正) |
| 2 | `$LINES` ≤ 20 (`$NON_DOC_CHANGED` が空、つまり `.md` / `docs/` のみの差分なら行数不問で skip 可)                                                  | typo・軽微修正の機械近似                                                                                                                             |
| 3 | `$CI_FILES_CHANGED` が空 (CI・ビルド/テスト設定 `.github/`, `*config*`, `package.json`, `Cargo.toml`, `go.mod`, `Makefile`, `justfile`, `deno.json` 等の変更なし) | 検証器設定の改変は必ず監査                                                                                                                           |
| 4 | 最後の issue でない (自分以外に open issue が残る。`uc-tracking` の親は数えない)                                                                  | 最後の issue は全観点フル                                                                                                                            |
