# フェーズ実行の詳細手順 (dev-impl Step 4)

`dev-impl/SKILL.md` の Step 4 (各フェーズの実行) 各節から参照される実行コマンドの詳細。判断基準・観点 gating・ループ規則・エスカレ条件は SKILL.md 本体にあるので、そちらを先に読んでから該当節だけをここで参照する。

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

UI フェーズ判定 (`uiPhase`): `phase_tasks` / フェーズ名に UI キーワード (画面 / コンポーネント / page / component / style / CSS / レイアウト) が含まれる、または `related_source_files` にフロントエンド dir (`apps/web/`, `frontend/`, `src/components/`, `src/pages/` 等) が含まれる場合に true。

実行前に `docs/.dev-impl/<run_id>/phase-<n>-context.md` (Step 4.1.5 で組み立て済み) を Read し、YAML フィールド `phase_tasks` / `phase_name` / `related_source_files` の値を確認する。以下のコードの `$PHASE_TASKS` / `$PHASE_NAME` / `$RELATED_SOURCE_FILES` は、その Read した値をそのままシェル変数に代入したものを指す (例: `PHASE_NAME="フェーズ3: ユーザー認証"`)。YAML パーサーは使わず、Read した内容から手動で代入する。

```bash
# $PHASE_TASKS / $PHASE_NAME / $RELATED_SOURCE_FILES は上記の通り PHASE_CONTEXT から代入済みの前提
if echo "$PHASE_TASKS $PHASE_NAME" | rg -qi '画面|コンポーネント|page|component|style|CSS|レイアウト' \
  || echo "$RELATED_SOURCE_FILES" | rg -q 'apps/web/|frontend/|src/components/|src/pages/'; then
  uiPhase=true
else
  uiPhase=false
fi
```

## 4.2b: architecture-guard 呼び出し

```javascript
const guard = await Agent({
  description: "境界違反の機械検査",
  subagent_type: "architecture-guard",
  prompt: `PHASE_CONTEXT: docs/.dev-impl/<run_id>/phase-<n>-context.md を Read。
target_diff: working tree vs ${PHASE_START_SHA}
git diff コマンド自体が失敗した場合は ok:false, skip_reason:"diff_command_failed" とせよ。`
})
```

## 4.2d: review-adversarial スキップ述語

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
```

判定条件テーブルと skip/実行の遷移規則は SKILL.md 側の 4.2d を参照。

## 4.2e: テスト弱体化検知コマンド

```bash
git diff ${PHASE_START_SHA} --diff-filter=D --name-only -- '*test*' '*spec*'   # テストファイルの削除
git diff ${PHASE_START_SHA} -U0 | rg '^\+.*\.(skip|only)\s*\(|^\+\s*(xit|xdescribe|xtest)\b|^\+.*#\[ignore\]'   # skip/only/ignore の追加
```
