# フェーズ実行の詳細手順 (dev-impl Step 4)

`dev-impl/SKILL.md` の Step 4 (各フェーズの実行) 各節から参照される実行コマンドの詳細。判断基準・観点 gating・ループ規則・エスカレ条件は SKILL.md 本体にあるので、そちらを先に読んでから該当節だけをここで参照する。

本ファイル中のシェル変数の前提: `$REPO_DIR` は作業ディレクトリの絶対パス (逐次モードは main のリポジトリ、並列モードは worktree)、`$PHASE_START_SHA` は SKILL.md 4.1 で記録した SHA、`$RESULT_JSON` は検査 agent が `output_path` に書いた結果 JSON のパス。JavaScript 風の `${...}` は Agent 呼び出しに埋める実値を表す。

## 4.1: run_elapsed_minutes 計算

```bash
RUN_START_EPOCH=$(date -j -f '%Y%m%d-%H%M%S' "$run_id" +%s 2>/dev/null || date -d "${run_id:0:8} ${run_id:9:2}:${run_id:11:2}:${run_id:13:2}" +%s)
run_elapsed_minutes=$(( ($(date +%s) - RUN_START_EPOCH) / 60 ))
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

`mode: fix` は上記 4.2a の呼び出しに加えて `findings_paths` を渡す:

```javascript
  prompt: `mode: fix
phase_context_path: ${absPhaseContextPath}
repo_dir: ${absRepoDir}
report_path: ${absScratchDir}/impl-report-fix-${round}.json
findings_paths:
${fatalResultPaths.map(p => `  - ${p}`).join("\n")}

最終メッセージは report_path の絶対パス 1 行だけにせよ。要約や解説を書くな。`
```

すべて**絶対パス**で渡す。subagent の Bash は呼び出しごとに cwd が親のものへ戻るため、相対パスは並列モードの worktree で解決できない。

TDD の順序・フェーズスコープのテストのみ実行・コミット禁止・`docs/` 編集禁止・報告 JSON スキーマ・停止条件は `claude/agents/dev-impl-implementer.md` に常駐しているので**指示文で繰り返さない** (spawn ごとの prompt 固定費になるため)。

## 4.2c: 検査 fan-out の起動

**起動前に未追跡ファイルを intent-to-add する** (これをしないと新規実装だけのフェーズが全 agent に空差分として見える):

```bash
git -C "$REPO_DIR" ls-files -z --others --exclude-standard \
  | xargs -0 -r git -C "$REPO_DIR" add -N
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

// スキップ述語を満たさなければ実行
{ subagent_type: "review-adversarial", model: "sonnet",
  prompt: `phase_name: ${phaseName}
phase_start_sha: ${phaseStartSha}
repo_dir: ${absRepoDir}
docs_dir: ${absDocsDir}
dev_server: ${devServerOrNull}
scratch_dir: ${absScratchDir}
output_path: ${absScratchDir}/review-adversarial.json` }   // PHASE_CONTEXT は渡さない

// gating に応じて review-tdd / review-quality / review-product-readiness を同様に (model: opus)
//   共通で渡す: PHASE_CONTEXT の絶対パス / phase_name / phase_start_sha / repo_dir / output_path
```

`target_diff` に渡せるのは `HEAD` / `working_tree` / `phase:<フェーズ名>` の 3 値のみ (`claude/agents/architecture-guard.md` の「入力」節)。それ以外の文字列は agent 側の分岐に該当せず未定義動作になる。

**結果の読み方** (SKILL.md「main のコンテキスト規律」):

```bash
jq -c '{ok, skip_reason, dimension, findings: [(.findings // .violations)[]? | {severity, rule, file, line}]}' "$RESULT_JSON"
```

`message` / `fix_proposal` は main では読まない (修正する implementer が JSON を自分で Read する)。

## 4.2c: 観点 gating 述語の算出コマンド

review-adversarial のスキップ述語と、review-quality を最終フェーズ以外でも起動させる条件を算出する。

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
```

判定条件テーブル (review-adversarial の skip/実行の遷移規則、`$CONSUMABLE_CHANGED` による review-quality の起動) は SKILL.md 側の 4.2c を参照。

## 4.2e: テスト弱体化検知コマンド

```bash
git diff ${PHASE_START_SHA} --diff-filter=D --name-only -- '*test*' '*spec*'   # テストファイルの削除
git diff ${PHASE_START_SHA} -U0 | rg '^\+.*\.(skip|only)\s*\(|^\+\s*(xit|xdescribe|xtest)\b|^\+.*#\[ignore\]'   # skip/only/ignore の追加
```
