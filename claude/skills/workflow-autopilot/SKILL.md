---
name: workflow-autopilot
description: 承認済みの DESIGN.md + DESIGN_DETAIL.md + TODO.md を入力に、TODO.md の全フェーズをレビュー・コミット込みで自律実装するオーケストレーター。人間の介入はエスカレ条件 (概要設計の破綻 P3 等) のみ。「設計済み TODO で実装を自律実行」「autopilot で TODO を消化」「残りタスクを自動で実装」などで起動。
argument-hint: "[docs ディレクトリパス、省略時は docs/]"
allowed-tools: Read, Edit, Write, Glob, Bash, Skill, Agent, AskUserQuestion
---

# workflow-autopilot

承認済みの設計 + TODO を入力に、TODO.md の全フェーズを最後まで自律的に実装するオーケストレーター。`workflow-spec` の下流ステージ (= 設計と TODO が固まった後) を機械的に消化する役割。

人間の介入は **エスカレ条件** (architecture-guard 3 回失敗 / review 致命違反 3 回残存 / P3 検出など) でのみ発生する。それ以外は止まらず最後まで走る。

## 入力

- `$ARGUMENTS` で docs ディレクトリパスが指定されていればそれを基点にする。省略時は `docs/` を使う
- 必須ファイル:
  - `docs/DESIGN.md` (概要)
  - `docs/DESIGN_DETAIL.md` (詳細)
  - `docs/TODO.md` (タスクリスト、フェーズ単位)

DESIGN_DETAIL.md が無ければ planning-tasks の対話的フォールバックでまず分割するよう促してから autopilot 起動を再案内する。

## 参照ルール

- TDD: `rules/core/tdd.md`
- 設計原則: `rules/core/design.md`
- テスト戦略: `rules/core/testing.md`
- コミット規約: `rules/core/commit.md`

## 進捗ログ (2 系統)

autopilot は 2 つのログを並走させる: **リアルタイム監視用の 1 行テキスト** と、**事後振り返り用の構造化 JSONL**。

### 1 行テキストログ (リアルタイム監視)

`~/.claude/logs/workflow-autopilot.log` に追記:

```bash
LOG="$HOME/.claude/logs/workflow-autopilot.log"
mkdir -p "$(dirname "$LOG")"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] <message>" >> "$LOG"
```

メッセージには「フェーズ名 + ステップ名 + 結果」を含める (例: `phase-3 / architecture-guard / violations=2 (loop 1/3)`)。

### 構造化 JSONL ログ (事後振り返り)

autopilot 起動時に `run_id = $(date '+%Y%m%d-%H%M%S')` を発行し、`~/.claude/logs/workflow-autopilot/${run_id}/decisions.jsonl` に追記する。終了時にこの JSONL から HTML レポート (後述 Step 7) を生成する。

各エントリのスキーマ:

```json
{
  "timestamp": "2026-06-30T10:00:00+09:00",
  "phase": "phase-3",
  "step": "architecture-guard",
  "event_type": "start|done|p1_fix|p2_fix|p3_escalate|poc_resolved|goal_check|goal_unmet|phase_added|review_low",
  "severity": "info|warn|error",
  "summary": "1 行サマリ (テキストログにも残る内容)",
  "context": {
    "violations": [...],
    "diff_before": "...",
    "diff_after": "...",
    "rationale": "なぜこの修正を選んだか",
    "affected_files": ["src/foo.ts"],
    "related_design_section": "DESIGN_DETAIL.md#api-設計"
  }
}
```

`event_type: review_low` の場合 (Step 4.2 参照)、`severity` は常に `info` (fatal ではない軽微な指摘のため)。`context` には `phaseFindings` を severity: low/medium に絞った上で dimension ごとにまとめて入れる:

```json
"context": {
  "findings_by_dimension": {
    "tdd": [{ "file": "...", "line": 12, "severity": "low", "message": "..." }],
    "quality": [],
    "architecture": [],
    "rules": [{ "file": "...", "line": 5, "severity": "medium", "message": "..." }],
    "product_readiness": []
  }
}
```

書き込みは `jq -nc --arg ... '{...}' >> $JSONL` で 1 行 1 エントリの append-only。`context` は event_type に応じて中身が変わる (`start` / `done` ではほぼ空でも良い)。

両ログとも各ステップの「開始 / 完了 / 動的修正 / エスカレ」発生時に同期して書き込む。1 行ログ = summary のみ、JSONL = summary + context を構造化。

## 実行手順

### Step 1: 前提ドキュメントの確認

1. `docs/DESIGN.md` を Read
2. `docs/DESIGN_DETAIL.md` を Read
3. `docs/TODO.md` を Read

#### 不在時の挙動

| 不在ファイル | 対処 |
|---|---|
| TODO.md | エスカレ停止: 「TODO.md が無い。`/workflow-spec` で生成してから再実行」とユーザー通知 |
| DESIGN_DETAIL.md | エスカレ停止: 「DESIGN_DETAIL.md が無い。`implementation-planning-tasks` の対話的フォールバックで生成してから再実行」とユーザー通知 |
| DESIGN.md | エスカレ停止: 「DESIGN.md が無い。`/requirements` で生成」とユーザー通知 |

### Step 1.5: 未確定マーカーの自動 PoC 解決

Step 1 で読み込んだ DESIGN.md / DESIGN_DETAIL.md から、技術選定の未確定要素マーカー (`POC_NEEDED`) を検出する:

```bash
rg -n '<!-- POC_NEEDED: .* -->' docs/DESIGN.md docs/DESIGN_DETAIL.md
```

マーカー書式:
```
<!-- POC_NEEDED: id=<unique-id>, scope=<検証対象>, risk=high|medium|low, blocker=true|false -->
```

#### 検出 0 件 → そのまま Step 2 へ (no-op)

#### 検出 1 件以上 → tech-investigation 順次呼び出し

`blocker=true` のマーカーを順次 `tech-investigation` subagent に渡す:

```javascript
const result = await Agent({
  description: "POC_NEEDED の自動調査",
  subagent_type: "tech-investigation",
  prompt: `marker: <マーカー本文>
design_path: docs/DESIGN.md
design_detail_path: docs/DESIGN_DETAIL.md
output_path: /tmp/tech-investigation-${id}.json
workspace_dir: /tmp/poc-${id}/`
})
const json = JSON.parse(await Read(result.trim()))
```

返り値の処理:

| 返り値 | 対処 |
|---|---|
| `blocker_resolved: true` | DESIGN_DETAIL.md に「## 技術調査結果 (autopilot 自動)」セクションを追加し、`recommended_approach` / `references` を追記。対応する POC_NEEDED マーカーを削除。JSONL に `event_type: poc_resolved` を記録 |
| `blocker_resolved: false` (`partial` で確信度低、環境不足等) | autopilot を P3 として停止、ユーザーに「自動 PoC で解決不能、人間判断必要」と通知 |
| `INVALID_MARKER` / `NO_DESIGN_DOCS` / `INVESTIGATION_FAILED` (stdout エラー) | autopilot を P3 として停止、エラー詳細を通知 |

`blocker=false` のマーカーは autopilot 起動時の自動 PoC 対象外 (実装中に必要になったら個別に呼ぶ運用)。テキストログには `[autopilot] POC_NEEDED ${id} pending (non-blocker)` と記録のみ。

#### Step 1.5 終了時の commit

autopilot が DESIGN_DETAIL.md を書き換えた (= マーカー解決した) 場合、その変更を 1 件のコミットにまとめる:

```bash
git add docs/DESIGN_DETAIL.md
git commit -m "📝 docs: autopilot で POC_NEEDED ${id} を解決"
```

これにより Step 2 以降のフェーズ commit と分離される。

### Step 2: フェーズ抽出

TODO.md から `### フェーズN: ...` の見出しを順に抽出してフェーズ一覧を作る。

未完了 (`- [ ]` が残っている) フェーズを `pending` 状態でリスト化する。すでに全タスクが `- [x]` になっているフェーズは skip。

```bash
# 例: フェーズ見出しと未完了タスク数を抽出
rg -n '^### フェーズ' docs/TODO.md
```

### Step 3: ループ全体の状態管理

以下の counter を保持して各フェーズで参照する (autopilot 開始時に 0 で初期化):

| カウンタ | 上限 | 超過時の挙動 |
|---|---|---|
| `p1_fixes_in_phase` (現フェーズ内 P1 修正回数) | 2 | P2 として扱う (次のループでは P2 として処理) |
| `p2_fixes_total` (autopilot 全体の P2 修正回数) | 3 | P3 扱いに昇格してエスカレ停止 |
| `goal_loop` (ゴール達成判定 → 未達対応の周回数) | 2 | P3 として停止 |

各フェーズ開始時に `p1_fixes_in_phase` を 0 にリセットする。`p2_fixes_total` と `goal_loop` は autopilot 実行中通して保持する。

フェーズ内のループカウンタ (architecture-guard 修正ループ最大 3 / レビュー self-fix ループ最大 3) と findings / deviation_signals の集約も**メインセッションが管理する** (Step 4.2)。各フェーズ開始時に 0 リセットし、カウンタの現在値と集約結果は都度 1 行テキストログ + JSONL に書き出して外部化する (コンテキストが長くなり compaction をまたいでも、ログから状態を復元できるように)。

### Step 4: 各フェーズの実行

各 pending フェーズについて以下を順次実行する:

#### Step 4.1: フェーズ開始の SHA を記録

```bash
PHASE_START_SHA=$(git rev-parse HEAD)
```

architecture-guard / review-* が「このフェーズの差分」を判定する基準点。

#### Step 4.1.5: PHASE_CONTEXT の組み立て

検査 subagent (architecture-guard / review-*) は parent のコンテキストを継承しないため、autopilot が「検査に必要な情報パッケージ」を組み立てて **`docs/.autopilot/<run_id>/phase-<n>-context.md` に Write** する。subagent には prompt にこのファイルの path だけを渡し、各 agent が必要な節を自分で Read する (1 フェーズあたり最大 4 検査 subagent への同一内容の重複埋め込みを避けるため)。フェーズ実装自体はメインセッションが行うので、このファイルはメインループにとっても「フェーズ設計情報の作業メモ」として機能する。

`docs/.autopilot/` は `.gitignore` に追加する (無ければ追記)。

ファイルに書く PHASE_CONTEXT:

```yaml
phase_name: <フェーズN: 名前>           # TODO.md の見出しから
phase_start_sha: <SHA>                   # Step 4.1 で記録
phase_tasks: |                            # TODO.md の該当フェーズセクション全文
  <TODO.md 該当部分を rg / awk で抽出>
design_overview: |                        # DESIGN.md 関連節抜粋 (上限あり、詳細は抜粋ロジック参照)
  <主要コンポーネント / 非機能目標 / ゴール のうち、現フェーズに関連する節>
design_overview_path: docs/DESIGN.md      # 抜粋で不足する場合に subagent が自分で Read するための固定 path
design_detail: |                          # DESIGN_DETAIL.md 関連節抜粋 (上限あり、詳細は抜粋ロジック参照)
  <API / スキーマ / シーケンス / 実装ガイドのうち、現フェーズに関連する節>
design_detail_path: docs/DESIGN_DETAIL.md # 抜粋で不足する場合に subagent が自分で Read するための固定 path
related_source_files:                     # subagent が Read すべき既存ファイル一覧
  - <Glob で抽出した関連ファイル path>
related_rules_paths:                      # rules/core + 言語別 rules
  - rules/core/tdd.md
  - rules/core/design.md
  - rules/core/testing.md
  - rules/core/commit.md
  - <言語別 rules があれば追加>
prev_phase_summary: |                     # 直前フェーズの 1-3 行要約
  <decisions.jsonl から拾う or skip>
poc_results:                              # Step 1.5 の tech-investigation 結果
  - id: <POC_NEEDED id>
    recommended_approach: <結論>
dev_server:                                # review-product-readiness (Step 4.2d) 用。Web プロダクトでなければ省略 (null)
  url: <検出できた URL>
  start_command: <package.json の dev/start script>
```

抜粋ロジック:

- `phase_tasks`: TODO.md を Read して `### フェーズN:` から次フェーズ見出しまでを切り出し
- `design_overview` / `design_detail`: フェーズ名から推測した key term (例: 「認証」「ユーザー登録」) で DESIGN/DETAIL を grep、ヒット節とその前後を抜粋。**抜粋は必須、全文フォールバックは禁止** (context ファイルは 1 フェーズにつき最大 4 検査 subagent がそれぞれ Read するため、全文だとコストが大きい)。抜粋の目安上限は 1 ファイルあたり 4KB、超える場合は該当節の見出し + 要約のみ残す。抜粋に加えて「このフェーズに関連しそうな DESIGN/DETAIL の見出し一覧」を必ず列挙し、抜粋に本文が無い見出しが必要になったら `design_overview_path` / `design_detail_path` を自分で Read する (メインループ・検査 subagent 共通。抜粋漏れを silent にしない)
- `related_source_files`: フェーズ名 / phase_tasks から推測したキーワードで Glob (`src/**/*<key>*`) + git diff で過去フェーズで触ったファイル
- `prev_phase_summary`: decisions.jsonl の直前 phase の `event_type: done` エントリ summary を引く
- `dev_server`: Web プロダクト判定 (`apps/web/`, `apps/`, `web/`, `frontend/` 等のディレクトリ + `package.json` の `dev`/`start` script の有無) を使う
  - Web プロダクトでなければ `dev_server` を省略 (review-product-readiness は URL 不在で no-op、`ok: true` 素通り)
  - Web プロダクトの場合: `start_command` は `package.json` の `scripts.dev` (無ければ `scripts.start`) をそのまま使う。`url` は以下の順に推定する:
    ```bash
    rg -n 'port\s*:\s*\d+' vite.config.ts vite.config.js 2>/dev/null   # Vite の server.port 明示指定
    test -f next.config.js -o -f next.config.ts && echo "port=3000"    # Next.js デフォルト
    test -f vite.config.ts -o -f vite.config.js && echo "port=5173"    # Vite デフォルト (上のrgでヒット無ければ)
    ```
    **推定に確信が持てない場合 (上記いずれにも一致しない) は `dev_server` ごと省略する** (誤ったポートを渡すと review-product-readiness が `dev_server_unavailable` の偽陽性を報告し、self-fix loop が実装側で直しようのないエラーを無限に再試行することになるため)

組み立てた PHASE_CONTEXT ファイルの path は Step 4.2 の各検査 subagent の prompt に渡す。

#### Step 4.2: フェーズ実装 (メインループ直営 + 検査 fan-out)

フェーズ内の「実装 → 境界検査 → レビュー → 修正 → テストゲート → コミット」は**メインセッションが直接実行する**。TDD の RED→GREEN→REFACTOR は前段の結果に次段が依存する逐次作業であり、subagent に委譲するとリクエストごとにコンテキストを読み直すため時間もトークンも大きく膨らむ (CLAUDE.md「サブエージェントの使い方」)。subagent を使うのは**互いに独立で並列化できる検査・調査** (architecture-guard / review-* / fix-lsp-warnings / tech-investigation) だけ。

##### 事前判定 (Bash)

```bash
# Lua/Neovim プラグイン判定 (LSP 警告修正ステップの有無)
if test -f init.lua || test -d lua || ls plugin/*.lua >/dev/null 2>&1; then
  IS_NEOVIM_PLUGIN=true
else
  IS_NEOVIM_PLUGIN=false
fi
```

UI フェーズ判定 (`uiPhase`): `phase_tasks` / フェーズ名に UI キーワード (画面 / コンポーネント / page / component / style / CSS / レイアウト) が含まれる、または `related_source_files` にフロントエンド dir (`apps/web/`, `frontend/`, `src/components/`, `src/pages/` 等) が含まれる場合に true。

##### 4.2a: TDD 実装 (メインループ)

PHASE_CONTEXT の `phase_tasks` と設計抜粋に従い、メインセッションが TDD (RED→GREEN→REFACTOR) でフェーズを実装する。

- `rules/core/tdd.md` に従う (サイクル順序は tdd-guard hook が tool call レベルで強制する)
- コミットはまだしない (4.2e でまとめて行う)
- 実装中に設計乖離に気付いたら deviation_signals として JSONL に記録する (`type: todo_minor | design_detail_gap | design_overview_break`)
- `design_overview_break` を検知したら**即エスカレ停止** (commit しない)
- 全テスト緑を確認してから 4.2b へ

##### 4.2b: 境界検査 (architecture-guard subagent、最大 3 修正ループ)

```javascript
const guard = await Agent({
  description: "境界違反の機械検査",
  subagent_type: "architecture-guard",
  prompt: `PHASE_CONTEXT: docs/.autopilot/<run_id>/phase-<n>-context.md を Read。
target_diff: working tree vs ${PHASE_START_SHA}
git diff コマンド自体が失敗した場合は ok:false, skip_reason:"diff_command_failed" とせよ。`
})
```

- `ok: false` (high/medium 違反 or `diff_command_failed`) → **メインループで TDD 修正** → guard 再実行。3 回修正しても残存なら `guard_loop_exceeded` でエスカレ停止
- low のみ → 警告ログだけ残して通過
- agent が結果を返せない (エラー / JSON 解釈不能) → `guard_agent_failed` でエスカレ停止 (**パス扱いにしない**)
- 修正中に `design_overview_break` を検知 → 即エスカレ停止

##### 4.2c: LSP 警告修正 (Lua/Neovim のみ)

`IS_NEOVIM_PLUGIN=true` なら `fix-lsp-warnings` agent を起動 (対象はフェーズ差分ファイルのみ)。失敗は警告ログのみで継続。修正が入った場合はテストを再実行して緑を確認する。

##### 4.2d: レビュー (観点 gating + 最大 3 self-fix ループ)

**観点 gating (トークン削減の要):**

| タイミング | 実行観点 |
|---|---|
| 毎フェーズ | review-tdd (境界の機械検査は 4.2b で毎回実施済み) |
| UI を触るフェーズ | 上記 + review-product-readiness (dev_server が無ければ skip) |
| 最終フェーズ | 全観点フル (tdd / quality / product-readiness) |

review-quality (rules 準拠 + アーキテクチャ heuristic 統合) は最終フェーズのみ (機械判定可能な境界違反は毎フェーズ architecture-guard が担保するため)。

gating された観点の review agent を**同一メッセージ内の複数 Agent tool_use として並列起動**する (各 prompt には PHASE_CONTEXT の path と PHASE_START_SHA を渡す)。

ループ規則 (メインセッションが簿記し、カウンタはログに外部化):

1. いずれかの review agent が結果を返せない (エラー / JSON 解釈不能) → その観点は「未検証」。**パス扱いにせず** `review_agent_failed` でエスカレ停止
2. findings の severity: high を fatal とする。fatal 0 件 → 4.2e へ
3. fatal あり → **メインループで TDD 修正** → **gating された全観点を再レビュー** (fix は別観点を壊しうるため、fatal だった観点だけに絞らない)
4. self-fix 3 回でも fatal 残存 → `review_loop_exceeded` でエスカレ停止
5. 修正中に `design_overview_break` を検知 → 即エスカレ停止 (commit しない)

severity: low/medium の findings は修正せず JSONL に `event_type: review_low` で記録する。

##### 4.2e: テストゲート + コミット (メインループ)

コミット前に全テストスイートを **Bash で直接実行し、exit code 0 を確認する** (自己申告ではなく実行結果で判定):

- 失敗 → 修正して再実行。3 回試みても緑にならなければ `tests_failing_before_commit` でエスカレ停止

緑を確認したら `rules/core/commit.md` に従いメインセッションがコミットする (関心事分割 / STRUCTURAL・BEHAVIORAL 分離。形式は commit-msg-guard hook が機械検証する)。push はしない (ユーザ手動)。

##### フェーズ内エスカレ条件まとめ

| 条件 | reason |
|---|---|
| guard 3 回修正でも high/medium 違反残存 | `guard_loop_exceeded` |
| review self-fix 3 回でも fatal 残存 | `review_loop_exceeded` |
| 検査 agent が結果を返せない (未検証をパス扱いにしない) | `guard_agent_failed` / `review_agent_failed` |
| テストゲート 3 回不通過 | `tests_failing_before_commit` |
| `design_overview_break` 検知 (実装・修正中いずれでも、commit 前に停止) | `design_overview_break` (P3) |

#### Step 4.6: 設計乖離の判定 (P1 / P2 / P3)

Step 4.2 でメインループが記録・累積した deviation_signals (実装 4.2a / guard 修正 4.2b / review self-fix 4.2d の全過程) を P 値に分類する。design 整合の判定は review findings の `dimension: "quality"` かつ `rule: "design_mismatch"` 系エントリも使う。

**シグナル元と分類対応**:

| シグナル元 | type | 分類 | 対処 |
|---|---|---|---|
| メインループ実装 | `todo_minor` | P1 (TODO 軽微) | autopilot が `docs/TODO.md` を編集して継続。`p1_fixes_in_phase += 1`、上限 (2 回) 超過なら P2 扱いに昇格 |
| メインループ実装 / review-quality の design 整合 finding (severity: medium 以上) | `design_detail_gap` | P2 (詳細設計の不足) | autopilot が `docs/DESIGN_DETAIL.md` を更新 → `implementation-planning-tasks` で `docs/TODO.md` を再生成 → 当該フェーズの実装に必要な追加情報をユーザに簡潔に通知 (ブロックはしない) → 継続。`p2_fixes_total += 1`、上限 (3 回) 超過なら P3 扱いに昇格 |
| メインループ実装 / review-quality の design 整合 finding (severity: high) | `design_overview_break` | P3 (概要設計の破綻) | エスカレ停止 (Step 4.2 内で検知した時点で commit 前に停止済み) |

**シグナル無しの場合**: 次の pending フェーズへ進む。

**集約のしかた**: 同一 phase 内で同種シグナルが複数回記録された場合、`scope` + `what` で重複排除してから処理 (1 件のシグナルとして扱う)。

##### P1 動的修正

```
1. `p1_fixes_in_phase += 1`。`p1_fixes_in_phase > 2` なら本シグナルを P2 (design_detail_gap) として扱い、P2 動的修正フローに切り替える (以降のステップは実行しない)
2. TODO.md の該当フェーズ周辺を Edit
3. ログに「P1 fix: <変更内容の 1 行サマリ>」を残す
4. 残タスクが当該フェーズ内なら継続、フェーズを跨ぐ追加なら新フェーズを挿入して以降のループに含める
```

##### P2 動的修正

```
1. `p2_fixes_total += 1`。`p2_fixes_total > 3` なら本シグナルを P3 (design_overview_break) として扱い、エスカレ停止する (以降のステップは実行しない)
2. DESIGN_DETAIL.md の該当セクションを Edit
3. implementation-planning-tasks スキルを Skill ツールで呼んで TODO.md を再生成 (差分更新モード)
4. Step 2 のフェーズ抽出 (`rg -n '^### フェーズ' docs/TODO.md`) を再実行してフェーズ一覧を更新する。既に `- [x]` 済みのタスクはそのまま完了扱いを維持し、再生成で新規追加された未完了タスクだけを pending に加える
5. ログに「P2 fix: <更新セクション>」を残す
6. 当該フェーズの再実行 (Step 4.2 から) か次フェーズへ進むかを判定: 再生成後の TODO.md で **当該フェーズ内に新規の未完了タスク (`- [ ]`) が追加されていれば Step 4.2 から再実行**、既存タスクが全て完了済みのまま (DESIGN_DETAIL.md の記述を補っただけで実装側の追加作業が無い) なら次フェーズへ進む
7. ユーザに対する通知は「DESIGN_DETAIL.md / TODO.md を更新しました (詳細はログ参照)」程度 (autopilot は止まらない)
```

##### P3 検出時

エスカレ停止 (後述の「エスカレ停止時の挙動」へ)。

シグナル処理が終わったら次の pending フェーズへ進む (コミットは Step 4.2e で実行済み)。

### Step 5: ゴール達成判定 + 未達対応ループ

Step 4 のフェーズループを抜けた時点で「全 TODO 消化」は完了している。ここから DESIGN.md のゴールが**実際に達成されているか**を機械判定する。

#### Step 5.1: ゴール一覧抽出

DESIGN.md の「ゴール」セクションを Read してゴール一覧を抽出 (例: `G1, G2, ...`):

```bash
rg -n '^- G[0-9]+:|^G[0-9]+:' docs/DESIGN.md
```

ゴール定義が無い (= 旧形式の DESIGN.md / ゴール未記載) → Step 5 全体を skip して Step 6 へ (後方互換、no-op)。

#### Step 5.2: 検証手順の取得

DESIGN_DETAIL.md の「検証手順」セクションから、各ゴールに紐付いた検証方法を抽出:

- 自動: `G1 検証: <bash コマンド>` 形式 → Bash で実行、exit code で判定
- 手動: `G1 検証 (手動): <操作手順>` 形式 → 人間確認待ちリストに追加

#### Step 5.3: ゴール判定実行

各ゴールについて:

```bash
# 自動系
cd "$PROJECT_ROOT" && eval "$VERIFICATION_COMMAND"
if [ $? -eq 0 ]; then
  STATUS="achieved"
else
  STATUS="unmet"
fi
```

判定結果を JSONL に `event_type: goal_check` で記録 (各ゴールの `id / status / actual_output (失敗時)`)。

#### Step 5.4: 結果分岐

| 状況 | 対処 |
|---|---|
| 全ゴール achieved (or 手動 pending のみ) | Step 6 へ (完了サマリ) |
| 自動ゴールで unmet が 1 件以上 | 未達対応ループへ |

#### Step 5.5: 未達対応ループ

`goal_loop += 1`。`goal_loop > 2` なら P3 として停止 (エスカレ)。

それ以外:

1. 未達ゴールごとに TODO.md に新規フェーズを追加 (例: `### フェーズN+1: ゴール G2 達成タスク`)
   - フェーズ内容は「G2 が未達。検証コマンド `<cmd>` が exit code != 0。失敗ログ: `<actual_output>`。これを満たす実装を追加する」
   - JSONL に `event_type: phase_added` で記録
2. Step 4 のフェーズループに戻る (新規追加フェーズだけが pending)
3. 完了後、Step 5.1 に戻ってゴール再判定

手動 pending ゴールは Step 6 サマリで「人間確認必要」として明示する (autopilot は判定せず保留)。

### Step 5.6: POST_MVP.md の更新と status 判定

Step 5 のゴール判定後、`docs/POST_MVP.md` に **「UI/UX gap」セクション**を必須で書き出す (Web / モバイル Web プロダクトのみ。CLI / API のみは省略)。

#### UI/UX gap セクションの内容 (必須項目)

```markdown
## UI/UX gap (autopilot ${run_id} 時点)

### 未実装画面
- <DESIGN にあるが実装されていない画面>

### 未実装ナビ経路
- <DESIGN_DETAIL.md UX 設計のナビ仕様に対して、実機で到達できない画面>
  (review-product-readiness の `nav_unreachable` finding を反映)

### frontend-design 未適用フラグ
- 適用済 / 未適用 (未適用なら理由を記載)

### a11y 未対応項目
- <review-product-readiness や手動チェックで残った a11y 違反>

### 視覚的回帰参照
- スナップショット: /tmp/review-product-readiness-snapshots/<phase>/
```

各項目は **autopilot が自動でログ / review 結果から収集して埋める** (decisions.jsonl / review-product-readiness の findings / G_E2E 判定結果から)。

#### status 判定

UI/UX gap セクションが**空でなければ** autopilot の終了 status を `partial` にする:

| 状況 | status |
|---|---|
| 全ゴール達成 + UI/UX gap 全項目空 | `done` |
| 全ゴール達成 + UI/UX gap に項目あり | `partial` (機能は揃ったが UX が未仕上げ) |
| 自動ゴール未達ありで未達対応ループ実行中 | (Step 5 内ループ継続) |
| 未達ゴールで goal_loop > 2 | `escalated` (Step 5 で P3 停止) |

`partial` でも commit と HTML レポート生成は実行 (中途半端でも記録は残す)。

### Step 6: 全フェーズ完了サマリ

```
✅ workflow-autopilot 完了 (status: <done|partial|escalated>)

実装フェーズ: N / N (全完了)
新規コミット: <git rev-list --count $START_SHA..HEAD>
動的修正: P1 <X> 回 / P2 <Y> 回 / P3 0 回 (停止無し)
ゴール達成: <achieved>/<total> (うち手動確認待ち <manual_pending>)
UI/UX gap: <未実装画面数> 画面 / <未実装ナビ経路数> 経路 / frontend-design: <適用|未適用>

範囲:
- 開始 SHA: <START_SHA>
- 終了 SHA: <HEAD>
- run_id: <run_id>

次のステップ:
- HTML レポート: docs/autopilot-reports/<run_id>.html を開いて意思決定と検証結果を確認
- UI/UX gap (status: partial の場合): docs/POST_MVP.md の「UI/UX gap」セクションで残課題を確認
- 手動確認待ちゴール (あれば): <ゴール ID リスト> を実機で検証
- 手動レビュー: git log <START_SHA>..HEAD で差分確認
- push はユーザ手動で実行
```

### Step 7: HTML レポート生成

autopilot 終了時 (Step 6 完了後、またはエスカレ停止時) に `docs/autopilot-reports/${run_id}.html` を生成する。

実装詳細とテンプレ関数は [references/report-template.md](./references/report-template.md) を参照。

生成手順:

1. JSONL ログ (`~/.claude/logs/workflow-autopilot/${run_id}/decisions.jsonl`) を Read
2. テンプレ関数 (single-page Tailwind CDN HTML) でレポート HTML を組み立て
3. `mkdir -p docs/autopilot-reports/` で出力先確保
4. Write で `docs/autopilot-reports/${run_id}.html` に書き出し
5. `git add docs/autopilot-reports/${run_id}.html` してコミット (HTML レポートは履歴管理する):

```bash
git commit -m "📝 docs: autopilot ${run_id} 実行レポート"
```

レポート内容: ヘッダー (run_id / SHA / 所要時間) / 全体サマリ / フェーズタイムライン / 動的修正詳細 (P1/P2/P3) / 技術調査結果 (POC_NEEDED) / ゴール達成判定 / フッター。

## エスカレ停止時の挙動

停止条件:
- Step 4.2 のフェーズ内エスカレ条件 (`guard_loop_exceeded` / `review_loop_exceeded` / `guard_agent_failed` / `review_agent_failed` / `tests_failing_before_commit`)
- P3 検出 (DESIGN.md 概要レベルの再設計必要)
- `p2_fixes_total > 3` (P3 扱いに昇格)
- `goal_loop > 2` (ゴール達成判定 → 未達対応の 3 周回でも未達ゴール残存)
- 必須ドキュメント (DESIGN.md / DESIGN_DETAIL.md / TODO.md) 欠如
- 自動 PoC で blocker マーカーが解決できなかった (tech-investigation が `blocker_resolved: false` / `INVESTIGATION_FAILED` 等を返した)

停止時の処理:

1. 当該フェーズの変更は**コミットしない** (緑状態でないため。working tree は残す)
2. 停止理由を `~/.claude/logs/workflow-autopilot.log` と JSONL (`event_type: p3_escalate`) と stdout 全てに詳細出力
3. HTML レポート (Step 7) を生成 → コミット (停止時もレポートだけは残す)
4. ユーザに通知:

```
⛔ workflow-autopilot 停止

停止フェーズ: <フェーズ名>
停止理由: <理由カテゴリ>
詳細:
  <違反内容や乖離の構造化サマリ>

範囲:
- 完了済みフェーズ: <完了数> / <全フェーズ数>
- 最終成功 commit: <SHA>

次のステップ:
- 上記詳細を踏まえ DESIGN.md / DESIGN_DETAIL.md を見直す
- (フェーズ実装やり直したい場合) git restore で working tree クリア後、autopilot 再起動
- (DESIGN 修正後) /workflow-spec で TODO 再生成後、autopilot 再起動
```

## 既存プロジェクトでの注意

- 既存のコミット history と autopilot のコミット粒度を混ぜたくない場合は、autopilot 起動前に専用の作業ブランチを切ることを推奨 (autopilot 自体はブランチ切替を行わない)
- `bypassPermissions` モード推奨 (途中で permission prompt が出ると autopilot が止まるため)
- launchd / cron などからヘッドレス実行する場合は `claude -p` 経由で、`--allowedTools` に `Bash,Read,Edit,Write,Glob,Grep,Agent,Skill,AskUserQuestion` を渡す。AskUserQuestion はエスカレ停止時にしか発火しないが、許可リストには含めておく

## 範囲外 (やらないこと)

- 設計の合意 (DESIGN.md / DESIGN_DETAIL.md 生成) → `/workflow-spec` / `/requirements`
- TODO.md の初期生成 → `implementation-planning-tasks`
- git push → ユーザー手動
- ブランチ切替・PR 作成 → ユーザー手動 (or `/workflow-create-draft-pr`)
- 動作検証 (実 UI / API テスト) → ユーザーが DESIGN_DETAIL.md の検証手順に従って実施

## 関連スキル / agent

### 内部呼び出し (subagent = 独立した検査・調査の fan-out のみ)

- **tech-investigation**: POC_NEEDED マーカーの自動 PoC (Step 1.5)
- **architecture-guard**: Clean Arch / DDD 境界違反検出、機械判定 (Step 4.2b、haiku)
- **fix-lsp-warnings**: Lua/Neovim の LSP 警告修正 (Step 4.2c)
- **review-tdd / review-quality / review-product-readiness**: Step 4.2d から観点 gating 付きで並列起動 (毎フェーズ tdd のみ / UI フェーズ +product-readiness / 最終フェーズ全観点フル、fix 後は全観点再レビュー)。review-quality は rules 準拠 + アーキテクチャ heuristic を統合。review-product-readiness は実機 chrome-devtools MCP 操作で UX 横断項目 (ナビ到達 / ErrorBoundary / 空状態 / loading / SEO meta / 404 / logout) を検査
- **security-guidance プラグイン**: セキュリティレビューはこのプラグイン (Edit/Write 時の pattern 検知 + Stop hook の LLM diff review) に委譲。自作 subagent は持たない

フェーズの TDD 実装・修正・テスト実行・コミットは**メインセッションが直接行う** (CLAUDE.md「サブエージェントの使い方」: 逐次依存する多段作業は subagent に出さない)。

### 内部呼び出し (skill)

- **implementation-planning-tasks**: P2 動的修正時の TODO 再生成

(手動レビュー用の `workflow-review` skill と `workflow-commit` skill は autopilot からは呼ばない。相当の処理は Step 4.2d / 4.2e が担う)

### 連携 hook

- **tdd-guard hook (`tdd-guard.ts`)**: メインループの TDD 違反を機械的に強制 (PreToolUse で実装編集を事前ゲート + Bash 書き込み検知 + 停止時テスト未実行チェック)。autopilot は意識しない
- **commit-msg-guard hook (`commit-msg-guard.ts`)**: Step 4.2e のコミット形式を機械検証

### 前段 / 後段

- **workflow-spec**: 前段。DESIGN + TODO 生成
- **implementation-developing** (skill): 単一フェーズを対話的に実装したい場合のエントリ (`implementation-developing-agent` への委譲版)。autopilot は subagent を経由せずメインループで直営する

## 範例: typical な実行ログ

```
[2026-06-30 10:00:00] autopilot start (docs/DESIGN.md + DESIGN_DETAIL.md + TODO.md)
[2026-06-30 10:00:01] phase-1 / start
[2026-06-30 10:01:23] phase-1 / implement (main) / done
[2026-06-30 10:01:30] phase-1 / architecture-guard / violations=0
[2026-06-30 10:01:31] phase-1 / fix-lsp-warnings / skipped (not a neovim plugin)
[2026-06-30 10:02:45] phase-1 / review (dims: tdd) / pass
[2026-06-30 10:02:48] phase-1 / test-gate / green
[2026-06-30 10:02:50] phase-1 / commit / done
[2026-06-30 10:02:51] phase-2 / start
[2026-06-30 10:05:12] phase-2 / implement (main) / done
[2026-06-30 10:05:25] phase-2 / architecture-guard / violations=2 (loop 1/3)
[2026-06-30 10:06:40] phase-2 / fix (main) / done
[2026-06-30 10:06:50] phase-2 / architecture-guard / violations=0
[2026-06-30 10:08:00] phase-2 / review (dims: tdd) / pass
[2026-06-30 10:08:03] phase-2 / test-gate / green
[2026-06-30 10:08:05] phase-2 / commit / done
...
[2026-06-30 10:30:00] all phases done (5/5). P1=1, P2=0
```
