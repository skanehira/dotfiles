---
name: workflow-autopilot
description: 承認済みの DESIGN.md (概要) + DESIGN_DETAIL.md (詳細) + TODO.md を入力に、TODO.md の全フェーズを自律実装する。起動時に POC_NEEDED マーカー (技術選定の未確定要素) を tech-investigation で自動 PoC 解決し、各フェーズで implementation-developing (TDD) → architecture-guard (最大3回まで自動修正ループ) → Neovim 判定で utility-fix-lsp-warnings (Lua/Neovim 専用) → workflow-review (致命違反は最大3回 self-fix) → workflow-commit を回す。全フェーズ消化後は DESIGN.md ゴール + DESIGN_DETAIL.md 検証手順で達成判定を実行、未達ゴールがあれば追加フェーズで最大2周回ループ。実装中の設計乖離は P1 (TODO 軽微) / P2 (詳細設計の不足) / P3 (概要設計の破綻) に分類して動的修正かエスカレ停止する。意思決定経緯は構造化 JSONL + HTML レポート (docs/autopilot-reports/<run_id>.html) として残す。「設計済み TODO で実装を自律実行」「autopilot で TODO を消化」「残りタスクを自動で実装」などで起動。
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
  "event_type": "start|done|p1_fix|p2_fix|p3_escalate|poc_resolved|goal_check|goal_unmet|phase_added",
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
| `guard_loop` (現フェーズの architecture-guard 修正ループ) | 3 | エスカレ停止 |
| `review_loop` (現フェーズの workflow-review self-fix ループ) | 3 | エスカレ停止 |
| `goal_loop` (ゴール達成判定 → 未達対応の周回数) | 2 | P3 として停止 |

各フェーズ開始時に `p1_fixes_in_phase` / `guard_loop` / `review_loop` を 0 にリセットする。`p2_fixes_total` と `goal_loop` は autopilot 実行中通して保持する。

### Step 4: 各フェーズの実行

各 pending フェーズについて以下を順次実行する:

#### Step 4.1: フェーズ開始の SHA を記録

```bash
PHASE_START_SHA=$(git rev-parse HEAD)
```

architecture-guard / workflow-review が「このフェーズの差分」を判定する基準点。

#### Step 4.2: implementation-developing でフェーズ実装

Skill ツールで `implementation-developing` を呼び、引数として現フェーズ名を渡す。

```
Skill({ skill: "implementation-developing", args: "フェーズN: <フェーズ名>" })
```

developing skill は TDD (RED → GREEN → REFACTOR → REVIEW → CHECK) サイクルを当該フェーズについて回す。

#### Step 4.3: architecture-guard (最大 3 ループ)

Agent ツールで `architecture-guard` subagent を呼ぶ。`target_diff: phase:<phase-name>` と `PHASE_START_SHA` を渡す:

```
Agent({
  description: "Clean Arch / DDD 境界の検査",
  subagent_type: "architecture-guard",
  prompt: `target_diff: phase:<name>
PHASE_START_SHA: ${PHASE_START_SHA}
design_path: docs/DESIGN.md
design_detail_path: docs/DESIGN_DETAIL.md
output_path: /tmp/guard-<phase-name>.json`
})
```

返ってきた path を Read して JSON をパース:

- `ok: true` → Step 4.4 へ
- `ok: false` で severity が `low` のみ → 警告ログだけ残して Step 4.4 へ
- `ok: false` で `high` / `medium` の violations あり → 修正フローへ

##### architecture-guard 修正フロー

`guard_loop += 1`。`guard_loop > 3` ならエスカレ停止。

それ以外:

1. violations の `fix_proposal` を集約して修正タスクを作る
2. `implementation-developing` を「architecture-guard 違反の修正タスク」として呼ぶ (TDD: 既存テストを保ったまま境界遵守に書き換え。必要に応じて新規テスト追加)
3. developing 完了後、`architecture-guard` を再実行 (このステップの先頭に戻る)

#### Step 4.4: utility-fix-lsp-warnings (Lua/Neovim 専用)

プロジェクトが Lua/Neovim プラグインの場合のみ実行する。判定:

```bash
if test -f init.lua || test -d lua || ls plugin/*.lua >/dev/null 2>&1; then
  IS_NEOVIM_PLUGIN=true
else
  IS_NEOVIM_PLUGIN=false
fi
```

`IS_NEOVIM_PLUGIN=true` の場合のみ Skill で `utility-fix-lsp-warnings` を呼ぶ。それ以外は skip して Step 4.5 へ。

(理由: utility-fix-lsp-warnings は Lua/Neovim 専用設計。他言語の LSP 警告は各言語の LSP plugin (`typescript-lsp@claude-plugins-official` 等) が拾う前提)

#### Step 4.5: workflow-review (最大 3 ループ self-fix)

Skill ツールで `workflow-review` を呼ぶ。5 観点 (TDD / 品質 / セキュリティ / アーキテクチャ / ルール) のレビュー結果を受け取る。

致命違反 (security 系 / 機能を壊す不具合 / rules 直接違反) があれば:

`review_loop += 1`。`review_loop > 3` ならエスカレ停止。

それ以外:
1. `implementation-developing` で self-fix (review 指摘を TDD で直す)
2. `workflow-review` を再実行 (このステップの先頭に戻る)

致命違反なし (= 軽微な改善提案のみ or 通過) → Step 4.6 へ。

#### Step 4.6: 設計乖離の判定 (P1 / P2 / P3)

Step 4.2 〜 4.5 の過程で「設計 / TODO と実装の食い違い」を検出したかを総合判断する。検出例と分類:

| シグナル | 分類 | 対処 |
|---|---|---|
| developing 中に「TODO のタスク順序が誤り」「タスク追加漏れ」と判明 | P1 (TODO 軽微) | autopilot が `docs/TODO.md` を編集して継続。`p1_fixes_in_phase += 1`、上限 (2 回) 超過なら P2 扱いに昇格 |
| developing / guard 中に「DESIGN_DETAIL.md に明記されていない API・スキーマ・エラー型・実装パターンが必要」と判明 | P2 (詳細設計の不足) | autopilot が `docs/DESIGN_DETAIL.md` を更新 → `implementation-planning-tasks` で `docs/TODO.md` を再生成 → 当該フェーズの実装に必要な追加情報をユーザに簡潔に通知 (ブロックはしない) → 継続。`p2_fixes_total += 1`、上限 (3 回) 超過なら P3 扱いに昇格 |
| developing / guard / review 中に「主要コンポーネントの再設計が必要」「非機能要件抵触」「ユースケース成立しない」と判明 (= DESIGN.md 概要に影響) | P3 (概要設計の破綻) | エスカレ停止 |

##### P1 動的修正

```
1. TODO.md の該当フェーズ周辺を Edit
2. ログに「P1 fix: <変更内容の 1 行サマリ>」を残す
3. 残タスクが当該フェーズ内なら継続、フェーズを跨ぐ追加なら新フェーズを挿入して以降のループに含める
```

##### P2 動的修正

```
1. DESIGN_DETAIL.md の該当セクションを Edit
2. implementation-planning-tasks スキルを Skill ツールで呼んで TODO.md を再生成 (差分更新モード)
3. ログに「P2 fix: <更新セクション>」を残す
4. 当該フェーズの再実行 (Step 4.2 から) または次フェーズへ進む (修正範囲による)
5. ユーザに対する通知は「DESIGN_DETAIL.md / TODO.md を更新しました (詳細はログ参照)」程度 (autopilot は止まらない)
```

##### P3 検出時

エスカレ停止 (後述の「エスカレ停止時の挙動」へ)。

#### Step 4.7: workflow-commit

Skill ツールで `workflow-commit` を呼ぶ。関心事ごとに分割して BEHAVIORAL / STRUCTURAL を区別してコミット。

push は実行しない (ユーザ手動)。

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

### Step 6: 全フェーズ完了サマリ

```
✅ workflow-autopilot 完了

実装フェーズ: N / N (全完了)
新規コミット: <git rev-list --count $START_SHA..HEAD>
動的修正: P1 <X> 回 / P2 <Y> 回 / P3 0 回 (停止無し)
ゴール達成: <achieved>/<total> (うち手動確認待ち <manual_pending>)

範囲:
- 開始 SHA: <START_SHA>
- 終了 SHA: <HEAD>
- run_id: <run_id>

次のステップ:
- HTML レポート: docs/autopilot-reports/<run_id>.html を開いて意思決定と検証結果を確認
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
- architecture-guard が同一フェーズで `guard_loop > 3` (= 4 回目でも違反残存)
- workflow-review 致命違反が同一フェーズで `review_loop > 3`
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

- **workflow-spec**: autopilot の前段。設計 + TODO 生成
- **implementation-developing**: 各フェーズの TDD 実装本体
- **tech-investigation**: POC_NEEDED マーカーの自動 PoC (subagent、Step 1.5 から)
- **architecture-guard**: Clean Arch / DDD 境界違反検出 (subagent、Step 4.3)
- **utility-fix-lsp-warnings**: Lua/Neovim LSP 警告修正 (Neovim プラグイン専用、Step 4.4)
- **workflow-review**: 5 観点コードレビュー (Step 4.5)
- **workflow-commit**: Conventional Commit でコミット (Step 4.7)
- **implementation-planning-tasks**: P2 動的修正時の TODO 再生成

## 範例: typical な実行ログ

```
[2026-06-30 10:00:00] autopilot start (docs/DESIGN.md + DESIGN_DETAIL.md + TODO.md)
[2026-06-30 10:00:01] phase-1 / start
[2026-06-30 10:01:23] phase-1 / developing / done
[2026-06-30 10:01:30] phase-1 / architecture-guard / violations=0
[2026-06-30 10:01:31] phase-1 / fix-lsp-warnings / skipped (not a neovim plugin)
[2026-06-30 10:02:45] phase-1 / workflow-review / pass
[2026-06-30 10:02:50] phase-1 / commit / done
[2026-06-30 10:02:51] phase-2 / start
[2026-06-30 10:05:12] phase-2 / developing / done
[2026-06-30 10:05:25] phase-2 / architecture-guard / violations=2 (loop 1/3)
[2026-06-30 10:06:40] phase-2 / developing (fix) / done
[2026-06-30 10:06:50] phase-2 / architecture-guard / violations=0
[2026-06-30 10:08:00] phase-2 / workflow-review / pass
[2026-06-30 10:08:05] phase-2 / commit / done
...
[2026-06-30 10:30:00] all phases done (5/5). P1=1, P2=0
```
