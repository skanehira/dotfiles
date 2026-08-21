# フェーズ実行の詳細手順 (dev-impl Step 4)

`dev-impl/SKILL.md` の Step 4 (各フェーズの実行) 各節から参照される実行コマンドの詳細。判断基準・観点 gating・ループ規則・エスカレ条件は SKILL.md 本体にあるので、そちらを先に読んでから該当節だけをここで参照する。

本ファイル中のシェル変数の前提: `$REPO_DIR` は作業ディレクトリ (main のリポジトリ) の絶対パス、`$PHASE_START_SHA` は SKILL.md 4.1 で記録した SHA、`$RESULT_JSON` は検査 agent が `output_path` に書いた結果 JSON のパス。JavaScript 風の `${...}` は Agent 呼び出しに埋める実値を表す。

## 4.2a: subagent の応答待ち時間

subagent が応答しないまま 30 分経過したかの判定に使う (SKILL.md 4.2a / 4.2c)。**run 全体の経過時間は計測しない** — 経過時間で run を打ち切る基準は無い。

```bash
SPAWN_EPOCH=$(date +%s)          # Agent を起動した直後に記録する
# ... 応答を待つ ...
waited_minutes=$(( ($(date +%s) - SPAWN_EPOCH) / 60 ))
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
${round === 1 ? "" : ROUND2_PLUS_BRIEF}
最終メッセージは report_path の絶対パス 1 行だけにせよ。要約や解説を書くな。` }
```

`ROUND2_PLUS_BRIEF` (ラウンド 2 以降だけ足す。**過去ラウンドの実績を必ず埋めて渡す** — 「同じ族の隣が出続けている」ことは実装者からは見えないため):

```text
これはラウンド ${round}/3 で、ラウンド 1 では解消しきれなかった fatal である。3 ラウンド目でも fatal が残れば
このフェーズはエスカレ停止となる。

過去ラウンドの経過: ${roundHistory}
(例: 「round 1 は A:100 を指摘 → 解消したが round 2 で B:79 が新規に出た」)

指摘箇所を局所的に塞ぐ前に、その箇所が属する不変条件を洗い出し、同じ族のエッジケースがまとめて閉じるかを
確認せよ。族として閉じられない残りがあれば、その旨を報告の open_questions に明記せよ。
```

`roundHistory` は JSONL の `fix_dispatch` の `fatal_summary` と、その次ラウンドの検査結果から main が組み立てる (main は findings 本文を読まないので、`{rule, file, line}` の射影と解消 / 未解消の別だけで足りる)。

すべて**絶対パス**で渡す。subagent の Bash は呼び出しごとに cwd が親のものへ戻るため、相対パスは意図したディレクトリで解決できない。

TDD の順序・フェーズスコープのテストのみ実行・コミット禁止・`docs/` 編集禁止・報告 JSON スキーマ・停止条件は `claude/agents/dev-impl-implementer.md` に常駐しているので**指示文で繰り返さない** (spawn ごとの prompt 固定費になるため)。

## 4.2c: 検査 fan-out の起動

**起動前に 3 つを 1 ブロックで行う** (intent-to-add / 内容ハッシュのベースライン / spawn の先行記録)。**この 3 つはいずれも「起動する前」でなければ意味を成さない**ので、fan-out ごとに必ずこのブロックを流す:

```bash
# (1) 未追跡ファイルを intent-to-add (これをしないと新規実装だけのフェーズが全 agent に空差分として見える)
git -C "$REPO_DIR" ls-files -z --others --exclude-standard \
  | xargs -0 -r git -C "$REPO_DIR" add -N

# (2) 内容ハッシュのベースライン (検査 agent が攻撃・変異でソースを書き換えたまま戻さない事故の検出用。
#     git status --porcelain では検出できない = SKILL.md 4.2d 手順 8)
git -C "$REPO_DIR" diff --name-only "$PHASE_START_SHA" | xargs shasum > "$SCRATCH_DIR/content-hash-before-${ROUND}.txt"

# (3) これから起動する agent の spawn を JSONL に先に書く (起動後に書く規定だと構造的に落ちる = SKILL.md 4.2c)
for a in $AGENTS_TO_SPAWN; do   # 例: "architecture-guard:haiku review-tdd:opus review-adversarial:sonnet"
  jq -nc --arg ts "$(date +%Y-%m-%dT%H:%M:%S%z)" --arg p "$PHASE" \
     --arg n "${a%%:*}" --arg m "${a##*:}" --arg r "$ROUND" '{
    timestamp:$ts, phase:$p, step:"review", event_type:"spawn", severity:"info",
    summary:("spawn " + $n + " (" + $m + ", round " + $r + ")"),
    context:{phase:$p, agent:$n, model:$m, round:$r}}' >> "$JSONL"
done
```

**結果を全部受け取った後**に、(2) の対照を取る:

```bash
git -C "$REPO_DIR" diff --name-only "$PHASE_START_SHA" | xargs shasum > "$SCRATCH_DIR/content-hash-after-${ROUND}.txt"
cmp -s "$SCRATCH_DIR/content-hash-before-${ROUND}.txt" "$SCRATCH_DIR/content-hash-after-${ROUND}.txt" \
  || diff "$SCRATCH_DIR/content-hash-before-${ROUND}.txt" "$SCRATCH_DIR/content-hash-after-${ROUND}.txt"
```

gating で決まった観点 + architecture-guard を**同一メッセージ内の複数 Agent tool_use** として並列起動する。全呼び出しに共通で付ける末尾指示:

```text
最終メッセージは output_path の絶対パス 1 行だけにせよ。findings 本文や要約を書くな。
```

```javascript
// 毎フェーズ必須
{ subagent_type: "architecture-guard", model: "haiku", run_in_background: false,
  prompt: `target_diff: phase:${phaseName}
design_path: ${absDocsDir}/DESIGN.md
design_detail_path: ${absDocsDir}/DESIGN_DETAIL_APP.md
PHASE_START_SHA: ${phaseStartSha}
repo_dir: ${absRepoDir}
output_path: ${absScratchDir}/guard.json
git diff コマンド自体が失敗した場合は ok:false, skip_reason:"diff_command_failed" とせよ。` }

// スキップ述語を満たさなければ実行。mode は SKILL.md 4.2c の「review-adversarial の mode 決定」表で決め、
// gating_decided に記録した値をそのまま渡す (再 fan-out でも同じ値を使う)
{ subagent_type: "review-adversarial", model: "sonnet",
  prompt: `mode: ${adversarialMode}
phase_name: ${phaseName}
phase_start_sha: ${phaseStartSha}
repo_dir: ${absRepoDir}
docs_dir: ${absDocsDir}
dev_server: ${devServerOrNull}
scratch_dir: ${absScratchDir}
output_path: ${absScratchDir}/review-adversarial.json` }   // PHASE_CONTEXT は渡さない
// mode: weakening_only のときは docs_dir / dev_server の行を省く (レンズ A/C を実行しないため不要)

// gating に応じて review-tdd / review-quality / review-product-readiness を同様に (model: opus)
//   共通で渡す: PHASE_CONTEXT の絶対パス / phase_name / phase_start_sha / repo_dir / output_path
```

`target_diff` に渡せるのは `HEAD` / `working_tree` / `phase:<フェーズ名>` の 3 値のみ (`claude/agents/architecture-guard.md` の「入力」節)。それ以外の文字列は agent 側の分岐に該当せず未定義動作になる。

**結果の読み方** (SKILL.md「main のコンテキスト規律」):

```bash
jq -c '{ok, skip_reason, dimension, mode, skipped_lenses, findings: [(.findings // .violations)[]? | {severity, rule, file, line}]}' "$RESULT_JSON"
```

`message` / `fix_proposal` は main では読まない (修正する implementer が JSON を自分で Read する)。

## 4.2c: 観点 gating 述語の算出コマンド

review-adversarial のスキップ述語と mode 判定、review-quality を最終フェーズ以外でも起動させる条件を算出する。**フェーズの初回 fan-out 前に 1 回だけ実行し、結果を `gating_decided` に記録する。** 4.2d の再 fan-out では再評価しない。例外は 1 つだけで、**初回評価で review-adversarial を skip したフェーズ**に限り、各修正ラウンドの fan-out 直前に本節の述語一式を再算出して skip → 実行 の転換を判定する (SKILL.md 4.2c の遷移規定)。fix がテストに触れたかの判定は本節の述語ではなく `## 4.2d: fix がテストに触れたかの判定` を使う。

```bash
CHANGED=$({ git diff --name-only "${PHASE_START_SHA}"; git ls-files --others --exclude-standard; } | sort -u)
# LINES は tracked (コミット済との差分) + untracked (新規ファイル) の合算。dev-impl は 4.2e まで
# コミットしないため、フェーズの新規実装ファイルは常に untracked であり、tracked 差分だけでは
# 大規模な新規実装を「変更 0 行」と誤判定してしまう
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

判定条件テーブル (review-adversarial の skip/実行の遷移規則と mode 決定、`$CONSUMABLE_CHANGED` による review-quality の起動) は SKILL.md 側の 4.2c を参照。

## 4.2e: テスト弱体化検知コマンド

```bash
git diff ${PHASE_START_SHA} --diff-filter=D --name-only -- '*test*' '*spec*'   # テストファイルの削除
git diff ${PHASE_START_SHA} -U0 | rg '^\+.*\.(skip|only)\s*\(|^\+\s*(xit|xdescribe|xtest)\b|^\+.*#\[ignore\]'   # skip/only/ignore の追加
```

## 4.2d: fix がテストに触れたかの判定

4.2d 手順 5 の例外 1 で使う。**4.2e までコミットしないため fix 差分だけを切り出す SHA は存在しない**ので、fix 起動の直前と完了直後にテストファイル群の署名を取って比較する (フェーズ開始 SHA 比の `$TEST_CONTENT_CHANGED` では「implement 段階で触れたか」しか分からず、通常のフェーズでは常に真になって絞り込みが効かない)。

```bash
test_signature() {
  { git -C "$REPO_DIR" ls-files -z; git -C "$REPO_DIR" ls-files --others --exclude-standard -z; } \
    | rg --null-data '(_test\.(go|rs|py)|\.test\.|\.spec\.|_spec\.|__tests__/|(^|/)tests?/|(^|/)test_[^/]*\.py)' \
    | sort -z | xargs -0 -r -I{} shasum "$REPO_DIR/{}" | shasum | cut -d' ' -f1
}
SIG_BEFORE=$(test_signature)   # mode: fix の implementer を起動する直前
# ... fix 完了後 ...
SIG_AFTER=$(test_signature)
[ "$SIG_BEFORE" != "$SIG_AFTER" ] && echo "fix がテストに触れた"
```

Rust のインラインテスト (src ファイル内の `#[cfg(test)]`) はこのファイル名パターンで捕まらない。**Rust プロジェクトでは `rg -l '#\[cfg\(test\)\]'` の結果も署名の対象に加える**こと。署名が一致しても `$CI_FILES_CHANGED` に相当する設定変更があれば同様に adversarial を追加する。

## 4.2e: implementer 報告の JSONL 一括転記

SKILL.md 4.2e 手順 6 の転記は、**項目ごとに Bash を呼ばず 1 回の実行で全件を流し込む**。実測 (4 フェーズ) で JSONL 239 件中 121 件が `design_decision` / `open_question` の転記で、これを逐次実行すると main の往復がフェーズあたり 30 回近く増える。

`REPORT_PATH` は implementer 報告 (`report_path`) の絶対パス、`JSONL` は当該 run の `decisions.jsonl`、`PHASE_NAME` は `## 4.2: 事前判定` で PHASE_CONTEXT から代入したフェーズ識別子だが、**JSONL の `phase` には 1 行ログと同じ短い識別子 (`phase-3` 形式) を入れる** (フェーズ名そのままだと同じフェーズが別表記で混ざり、HTML レポートのフェーズ集計が割れる)。

```bash
jq -c --arg phase "$PHASE_NAME" --arg ts "$(date +%Y-%m-%dT%H:%M:%S%z)" '
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
