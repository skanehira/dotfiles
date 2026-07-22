---
name: dev-impl
description: 実装ループ。承認済みの DESIGN.md + DESIGN_DETAIL_APP.md + DESIGN_DETAIL_INFRA.md + TODO.md を入力に、TODO.md の全フェーズをレビュー・コミット込みで自律実装するオーケストレーター。人間の介入はエスカレ条件 (概要設計の破綻 P3 等) のみ。dev-spec の承認ゲート通過後にユーザーが直接起動する。エスカレーション回答後の再開も本スキルの再実行で行う。「実装ループを開始」「設計済み TODO で実装を自律実行」「残りタスクを自動で実装」などで起動。
argument-hint: "[docs ディレクトリパス、省略時は docs/]"
model: sonnet
allowed-tools: Read, Edit, Write, Glob, Bash, Skill, Agent, AskUserQuestion
---

# dev-impl — 実装ループ

承認済みの設計 + TODO を入力に、TODO.md の全フェーズを最後まで自律的に実装するオーケストレーター。`dev-spec` の下流ステージ (= 設計と TODO が固まった後) を機械的に消化する役割。

人間の介入は **エスカレ条件** (architecture-guard 3 回失敗 / review 致命違反 3 回残存 / P3 検出など) でのみ発生する。それ以外は止まらず最後まで走る。

## モデル方針

- 本スキルは frontmatter で `model: sonnet` を指定している。モデル切り替えが効くのは**ユーザーが `/dev-impl` を直接起動したターンだけ** (Skill ツール経由の起動では適用されない)。エスカレーションに回答した後の再開も `/dev-impl` の再実行で行う (TODO.md の `- [x]` 状態から途中再開できるため、再実行で override が再適用される)
- 検証 subagent (review-*) は起動時に **`model: opus` を明示**する。原則は「実行器のモデル ≤ 検証器のモデル」。実装ループの actor を Sonnet に下げられるのは、tdd-guard・テストゲート・レビュー fan-out という検証器が厚いため

## 入力

- `$ARGUMENTS` で docs ディレクトリパスが指定されていればそれを基点にする。省略時は `docs/` を使う
- 必須ファイル:
  - `docs/DESIGN.md` (概要)
  - `docs/DESIGN_DETAIL_APP.md` (アプリ詳細)
  - `docs/DESIGN_DETAIL_INFRA.md` (インフラ詳細)
  - `docs/TODO.md` (タスクリスト、フェーズ単位)

詳細設計 2 ファイルが無ければ dev-spec のフォールバック (`../dev-spec/references/todo-generation.md`。旧形式 DESIGN_DETAIL.md からの分割移行 = フォールバック A、DESIGN.md からの抽出 = フォールバック B) でまず生成するよう促してから dev-impl 起動を再案内する。

## 参照ルール

- TDD: `rules/core/tdd.md`
- 設計原則: `rules/core/design.md`
- テスト戦略: `rules/core/testing.md`
- コミット規約: `rules/core/commit.md`

## 進捗ログ (2 系統)

起動時に `run_id = $(date '+%Y%m%d-%H%M%S')` と `START_SHA=$(git rev-parse HEAD)` (run 全体の開始 SHA。フェーズごとに再代入される `PHASE_START_SHA` とは別スコープ) を発行し、**リアルタイム監視用の 1 行テキストログ** (`~/.claude/logs/dev-impl.log`) と**事後振り返り用の構造化 JSONL** (`~/.claude/logs/dev-impl/${run_id}/decisions.jsonl`) を並走させる。各ステップの「開始 / 完了 / 動的修正 / エスカレ」発生時に両方へ同期して書き込む (1 行ログ = summary のみ、JSONL = summary + context を構造化)。終了時に JSONL から HTML レポート (Step 7) を生成する。`START_SHA` は Step 5.2 の監査 agent 呼び出しと Step 6 / エスカレ通知のテンプレート (references/goal-audit.md, references/notification-template.md) から参照される。

書式・JSONL スキーマ・書き込みコマンド・実行ログの範例は [references/logging.md](./references/logging.md) を Read して従う。

## 実行手順

### Step 0: 再入チェック (エスカレ後の再開対応)

`~/.claude/logs/dev-impl/` の最新 run の decisions.jsonl を確認し、**同一プロジェクトで未完了の run** (最後が `p3_escalate` 等で、完了イベントが無い) があれば再入モードで動く:

1. **run_id とカウンタを引き継ぐ** (新規発行しない)。decisions.jsonl から `p2_fixes_total` / `goal_loop` の現在値を復元する — 再実行のたびにカウンタが 0 に戻ると発散上限 (Step 3) が実質無効化されるため
2. **working tree の突合**: `git status --porcelain` が非クリーンなら前回停止時の残骸。内容を確認し、AskUserQuestion で「続きとして取り込む / `git restore` で捨ててフェーズをやり直す」を確認する (再入時 1 回だけの人間確認)
3. **TODO チェックの突合**: 最終フェーズコミット (decisions.jsonl の直近フェーズ done イベントの SHA) 以降に `- [x]` 化されたタスクがあれば、そのフェーズは「チェック済みだが未コミット」= 未完了として pending に戻す (`- [x]` は実行器の自己申告なので、コミットと突き合わせて初めて完了扱いにする)

未完了 run が無ければ通常起動 (新規 run_id 発行) で Step 1 へ。

### Step 1: 前提ドキュメントの確認

1. `docs/DESIGN.md` を Read
2. `docs/DESIGN_DETAIL_APP.md` を Read
3. `docs/DESIGN_DETAIL_INFRA.md` を Read
4. `docs/TODO.md` を Read

#### プロダクトモードの判定

run 全体で保持する `PRODUCT_MODE` を DESIGN.md のスタンプから判定する (以降のステップすべてがこの値を参照する):

```bash
PRODUCT_MODE=$(rg -o -m1 '<!-- product-mode: (cli|webapp) -->' -r '$1' docs/DESIGN.md || echo unknown)
```

- `cli` / `webapp`: dev-spec がスタンプを書いた新形式 docs
- `unknown` (スタンプ不在、旧形式 docs): 後方互換のため、UI 系判定は従来どおり `dev_server` 推定 (references/phase-context.md) にフォールバックする

#### 不在時の挙動

| 不在ファイル                                  | 対処                                                                                                                     |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| TODO.md                                       | エスカレ停止: 「TODO.md が無い。`/dev-spec` (フェーズ 10) で生成してから再実行」とユーザー通知                           |
| DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md | エスカレ停止: 上記「入力」節のフォールバック案内でユーザー通知 (旧形式の単一 `docs/DESIGN_DETAIL.md` しか無い場合も同じ) |
| DESIGN.md                                     | エスカレ停止: 「DESIGN.md が無い。`/dev-spec` で生成」とユーザー通知                                                     |

#### 構造ゲート (fail fast)

ファイルが揃っていても、以下に欠けがあれば**実装に入らずエスカレ停止**する。全フェーズ実装後に発覚しても手遅れなので、起動時に機械判定する:

| チェック                | 判定                                                                                                    | 欠落時の reason / 対処                                                                                                                                                                            |
| ----------------------- | ------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 承認スタンプ            | TODO.md 先頭に `<!-- dev-spec:approved` がある                                                          | `design_not_approved`: 「dev-spec フェーズ 11 の承認ゲートを通してから再実行」                                                                                                                    |
| 承認ハッシュ            | スタンプの `goals_sha=<値>` と再計算値 (下記) が一致する                                                | `approval_stale`: 「承認後に受入基準 (ゴール / 検証手順) が変更されている。dev-spec フェーズ 9 → 11 で再承認してから再実行」。スタンプに `goals_sha=` が無い旧形式は警告ログのみで通過 (後方互換) |
| ゴール定義              | `rg -n '^- G[0-9]+:\|^G[0-9]+:' docs/DESIGN.md` が 1 件以上                                             | `goals_missing`: 「dev-spec フェーズ 9 でゴールを定義してから再実行」                                                                                                                             |
| ゴール ↔ 検証手順の 1:1 | 抽出した各 `G<n>` に対応する `G<n> 検証` 行が DESIGN_DETAIL_APP.md または DESIGN_DETAIL_INFRA.md にある | `verification_missing`: 欠落ゴール ID を列挙して dev-spec フェーズ 9 へ差し戻し                                                                                                                   |
| G_E2E (必須・モード非依存) | `PRODUCT_MODE` が `cli`/`webapp` なら常に必須。`unknown` は Web プロダクト判定 (phase-context.md の dev_server 判定と同じ基準) が真なら必須 | `verification_missing` (同上)                                                                                                                                                                     |

承認ハッシュの再計算コマンド (dev-spec 11.3 の生成と同一定義。P2 ガードでも使う):

```bash
GOALS_SHA=$(
  {
    rg --no-filename '^- G[0-9]+:|^G[0-9]+:|^- G_E2E:|^G_E2E:' docs/DESIGN.md
    rg --no-filename 'G[0-9]+ 検証|G_E2E 検証' docs/DESIGN_DETAIL_APP.md docs/DESIGN_DETAIL_INFRA.md
  } | shasum -a 256 | awk '{print $1}'
)
```

### Step 1.5: 未解決 PoC マーカーの残存ガード

技術検証 (PoC) は前段の dev-spec フェーズ 5 (PoC 検証) で完了していることが前提。ここでは未解決マーカーの残存だけを機械チェックする:

```bash
rg -n '<!-- POC_NEEDED: .* -->' docs/DESIGN.md docs/DESIGN_DETAIL_APP.md docs/DESIGN_DETAIL_INFRA.md
```

| 検出結果             | 対処                                                                                                                                                                                                                                                                                        |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0 件                 | Step 2 へ (no-op)                                                                                                                                                                                                                                                                           |
| `blocker=false` のみ | テキストログに `[dev-impl] POC_NEEDED ${id} pending (non-blocker)`、JSONL に `event_type: poc_pending` (context に id / scope / risk) を記録して Step 2 へ (実装中に検証が必要になったら `tech-investigation` subagent を個別に呼ぶ。HTML レポートのセクション 5 がこのエントリを表示する) |
| `blocker=true` あり  | **エスカレ停止** (`poc_marker_unresolved`)。「未解決の blocker マーカーが残っています。`/dev-spec` のフェーズ 5 (PoC 検証) で解決してから `/dev-impl` を再実行してください」とユーザー通知                                                                                                  |

### Step 2: フェーズ抽出

TODO.md から `### フェーズN: ...` の見出しを順に抽出してフェーズ一覧を作る。

未完了 (`- [ ]` が残っている) フェーズを `pending` 状態でリスト化する。すでに全タスクが `- [x]` になっているフェーズは skip。抽出コマンド例: `rg -n '^### フェーズ' docs/TODO.md`。

### Step 3: ループ全体の状態管理

以下の counter を保持して各フェーズで参照する (dev-impl 開始時に 0 で初期化):

| カウンタ                                        | 上限                                                      | 超過時の挙動                                    |
| ----------------------------------------------- | --------------------------------------------------------- | ----------------------------------------------- |
| `p1_fixes_in_phase` (現フェーズ内 P1 修正回数)  | 2                                                         | P2 として扱う (次のループでは P2 として処理)    |
| `p2_fixes_total` (dev-impl 全体の P2 修正回数)  | 3                                                         | P3 扱いに昇格してエスカレ停止                   |
| `goal_loop` (ゴール達成判定 → 未達対応の周回数) | 2                                                         | P3 として停止                                   |
| `run_elapsed_minutes` (run 開始からの経過時間)  | 480 (分 = 8 時間。プロジェクト規模に応じて起動時に調整可) | `time_budget_exceeded` でエスカレ停止 (P3 扱い) |

各フェーズ開始時に `p1_fixes_in_phase` を 0 にリセットする。`p2_fixes_total` と `goal_loop` は dev-impl 実行中通して保持し、**再入時は Step 0 で decisions.jsonl から復元した値を初期値にする** (リセットしない)。

`run_elapsed_minutes` は各フェーズ開始時 (Step 4.1) に計算する (macOS/Linux 両対応)。算出コマンドは [references/phase-execution.md](./references/phase-execution.md) の `## 4.1: run_elapsed_minutes 計算` 節を Read してから実行する (この節を読まず近似コマンドで代替すると、date コマンドの macOS/Linux 分岐が崩れ time budget (`time_budget_exceeded`) が機能しなくなるリスクがある)。

フェーズ内のループカウンタ (architecture-guard 修正ループ最大 3 / レビュー self-fix ループ最大 3) と findings / deviation_signals の集約も**メインセッションが管理する** (Step 4.2)。各フェーズ開始時に 0 リセットし、カウンタの現在値と集約結果は都度 1 行テキストログ + JSONL に書き出して外部化する (コンテキストが長くなり compaction をまたいでも、ログから状態を復元できるように)。

### Step 4: 各フェーズの実行

各 pending フェーズについて以下を順次実行する:

#### Step 4.1: フェーズ開始の SHA を記録

`PHASE_START_SHA=$(git rev-parse HEAD)` を記録する。architecture-guard / review-* が「このフェーズの差分」を判定する基準点。

#### Step 4.1.5: PHASE_CONTEXT の組み立て

検査 subagent (architecture-guard / review-*) は parent のコンテキストを継承しないため、dev-impl が「検査に必要な情報パッケージ」を組み立てて **`docs/.dev-impl/<run_id>/phase-<n>-context.md` に Write** する。subagent には prompt にこのファイルの path だけを渡し、各 agent が必要な節を自分で Read する (1 フェーズあたり最大 4 検査 subagent への同一内容の重複埋め込みを避けるため)。フェーズ実装自体はメインセッションが行うので、このファイルはメインループにとっても「フェーズ設計情報の作業メモ」として機能する。

`docs/.dev-impl/` は `.gitignore` に追加する (無ければ追記)。

PHASE_CONTEXT の YAML テンプレートと抜粋ロジック (design 節の抜粋上限 4KB・dev_server 推定・poc_results の出典を含む) は [references/phase-context.md](./references/phase-context.md) を Read して従う。

組み立てた PHASE_CONTEXT ファイルの path は Step 4.2 の各検査 subagent の prompt に渡す。ただし review-adversarial は fresh context 監査のため PHASE_CONTEXT を渡さない (Step 4.2d 参照)。

#### Step 4.2: フェーズ実装 (メインループ直営 + 検査 fan-out)

フェーズ内の「実装 → 境界検査 → レビュー → 修正 → テストゲート → コミット」は**メインセッションが直接実行する**。TDD の RED→GREEN→REFACTOR は前段の結果に次段が依存する逐次作業であり、subagent に委譲するとリクエストごとにコンテキストを読み直すため時間もトークンも大きく膨らむ (CLAUDE.md「サブエージェントの使い方」)。subagent を使うのは**互いに独立で並列化できる検査・調査** (architecture-guard / review-* / fix-lsp-warnings / tech-investigation) だけ。

##### 事前判定

判定基準: `IS_NEOVIM_PLUGIN` は init.lua / lua ディレクトリ / plugin/*.lua の有無で決まる (LSP 警告修正ステップ 4.2c の要否)。`uiPhase` は `phase_tasks` / フェーズ名の UI キーワード、または `related_source_files` のフロントエンド dir 有無で決まる (4.2d の観点 gating に使う)。**`PRODUCT_MODE=cli` の場合は `uiPhase` を判定せず常に `false` 固定**とする (CLI 実装の「コマンド」「フラグ」等の語がキーワード判定に誤爆するのを防ぐ)。

実行コマンドは [references/phase-execution.md](./references/phase-execution.md) の `## 4.2: 事前判定` 節を Read してから実行する。

##### 4.2a: TDD 実装 (メインループ)

PHASE_CONTEXT の `phase_tasks` と設計抜粋に従い、メインセッションが TDD (RED→GREEN→REFACTOR) でフェーズを実装する。

- `rules/core/tdd.md` に従う (サイクル順序は tdd-guard hook が tool call レベルで強制する)
- コミットはまだしない (4.2e でまとめて行う)
- 実装中に設計乖離に気付いたら deviation_signals として JSONL に記録する (`type: todo_minor | design_detail_gap | design_overview_break`)
- `design_overview_break` を検知したら**即エスカレ停止** (commit しない)
- 全テスト緑を確認してから 4.2b へ

##### 実装ノートの記録 (design_decision / open_question)

deviation_signals (設計と*矛盾する*変更) とは別に、以下は**設計が沈黙・あいまいな箇所での自律判断**として JSONL に記録する (ループは止めない。スキーマは [references/logging.md](./references/logging.md) を参照):

- **`design_decision`**: DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md / TODO.md のいずれにも規定が無い実装の細部 (デフォルト値・パス/命名形式・ログ/エラーフォーマット・機能の適用範囲・ライブラリ API の選択等) を自分で選んだとき、および代替案を検討して棄却したとき
- **`open_question`**: エスカレ条件 (P3 等) には該当しないが、選択に確信が持てずユーザの事後確認が必要なとき。暫定処理を明記して前進する (CLAUDE.md「自律モード時の優先順位」に整合)。Step 4/5 のどのステップからでも記録可

同一の判断・質問を後続フェーズで踏襲するだけの場合は再記録しない (初回のみ)。「同一」は対象 (`affected_files` が指す機能・レイヤ) と根拠 (`rationale` / `background`) が両方一致する場合を指す。対象または根拠が異なれば別判断として新規に記録する。

##### 4.2b: 境界検査 (architecture-guard subagent、最大 3 修正ループ)

`architecture-guard` を起動する。呼び出し方法は [references/phase-execution.md](./references/phase-execution.md) の `## 4.2b: architecture-guard 呼び出し` 節を Read してから実行する (PHASE_CONTEXT の path と target_diff を渡す)。

- `ok: false` (high/medium 違反 or `diff_command_failed`) → **メインループで TDD 修正** → guard 再実行。3 回修正しても残存なら `guard_loop_exceeded` でエスカレ停止
- low のみ → 警告ログだけ残して通過
- agent が結果を返せない (エラー / JSON 解釈不能) → `guard_agent_failed` でエスカレ停止 (**パス扱いにしない**)
- 修正中に `design_overview_break` を検知 → 即エスカレ停止

##### 4.2c: LSP 警告修正 (Lua/Neovim のみ)

`IS_NEOVIM_PLUGIN=true` なら `fix-lsp-warnings` agent を起動 (対象はフェーズ差分ファイルのみ)。失敗は警告ログのみで継続。修正が入った場合はテストを再実行して緑を確認する。

##### 4.2d: レビュー (観点 gating + 最大 3 self-fix ループ)

**観点 gating (トークン削減の要):**

| タイミング        | 実行観点                                                                                            |
| ----------------- | --------------------------------------------------------------------------------------------------- |
| 毎フェーズ        | review-tdd (境界の機械検査は 4.2b で毎回実施済み) + review-adversarial (下記スキップ述語で skip 可) |
| UI を触るフェーズ (`uiPhase == true`) | 上記 + review-product-readiness (dev_server が無ければ skip)                     |
| 最終フェーズ      | 全観点フル (tdd / quality / product-readiness / adversarial)                                        |

**`PRODUCT_MODE=cli` では review-product-readiness を一切起動しない** (`uiPhase` が常に `false` のため UI を触るフェーズの行は発火せず、最終フェーズの「全観点フル」からも product-readiness を除外する。cli の G_E2E は Step 5.2 で review-spec-compliance が担当する)。

review-quality (rules 準拠 + アーキテクチャ heuristic 統合) は最終フェーズのみ (機械判定可能な境界違反は毎フェーズ architecture-guard が担保するため)。

**review-adversarial のスキップ述語 (機械判定、actor の裁量では skip しない):**

算出コマンド (`$CHANGED` / `$LINES` / `$TEST_FILE_CHANGED` / `$TEST_CONTENT_CHANGED` / `$NON_DOC_CHANGED` / `$CI_FILES_CHANGED`) は [references/phase-execution.md](./references/phase-execution.md) の `## 4.2d: review-adversarial スキップ述語` 節を Read してから実行する (この節を読まず近似コマンドで代替すると、untracked ファイルや言語別インラインテストの検知漏れにより review-adversarial を不当に skip するリスクがある)。判定条件は以下の表に従う。

| # | 条件                                                                                                                                              | 意図                                                                                                                                                 |
| - | ------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1 | `$TEST_FILE_CHANGED` と `$TEST_CONTENT_CHANGED` がともに空                                                                                        | テスト変更時はレンズ B 必須。ファイル名 + 差分内容の 2 層、tracked/untracked 両方で判定 (言語別の具体パターンは phase-execution.md の実コマンドが正) |
| 2 | `$LINES` ≤ 20 (`$NON_DOC_CHANGED` が空、つまり `.md` / `docs/` のみの差分なら行数不問で skip 可)                                                  | typo・軽微修正の機械近似                                                                                                                             |
| 3 | `$CI_FILES_CHANGED` が空 (CI・ビルド/テスト設定 `.github/`, `*config*`, `package.json`, `Cargo.toml`, `go.mod`, `Makefile`, `justfile`, `deno.json` 等の変更なし) | 検証器設定の改変は必ず監査                                                                                                                           |
| 4 | 最終フェーズでない                                                                                                                                | 最終フェーズは全観点フル                                                                                                                             |

全条件が真の場合のみ skip 可 (skip は権利であって義務ではない。1 つでも「実行」と出れば actor はスキップできない)。skip 時は JSONL に `event_type: verification_skipped`、`context: {target: "review-adversarial", changed_files: $CHANGED, changed_lines: $LINES, criteria_result: {...}}` を記録する (Step 5.6 の未検証項目集約に自動合流させ、沈黙スキップを構造的に不可能にするため)。

述語は各 self-fix ループのレビュー直前に評価するが、遷移は **skip → 実行 の一方向のみ許可する** (一度「実行」と判定されたら以降のループでは再評価せず必ず実行し続ける。「実行 → skip」への降格は禁止)。初回評価で skip だった場合のみ、次の self-fix 後の再レビュー時に再評価する。これにより、初回 skip 後の self-fix でテストが追加・弱体化されるケースを取りこぼさない。

gating された観点の review agent を**同一メッセージ内の複数 Agent tool_use として並列起動**する (各 prompt には PHASE_CONTEXT の path と PHASE_START_SHA を渡す。ただし **review-adversarial には PHASE_CONTEXT の path を渡さない** — fresh context 監査のため、phase_name / PHASE_START_SHA / docs_dir / dev_server / scratch_dir / output_path のみを渡す)。各 Agent 呼び出しには **`model: opus` を明示**する (「モデル方針」参照。呼び出し時の model 指定は agent 定義側のデフォルトより優先される)。

ループ規則 (メインセッションが簿記し、カウンタはログに外部化):

1. いずれかの review agent が結果を返せない (エラー / JSON 解釈不能) → その観点は「未検証」。**パス扱いにせず** `review_agent_failed` でエスカレ停止
2. findings の severity: high を fatal とする。fatal 0 件 → 4.2e へ
3. fatal あり → **メインループで TDD 修正** → **gating された全観点を再レビュー** (fix は別観点を壊しうるため、fatal だった観点だけに絞らない)
4. self-fix 3 回でも fatal 残存 → `review_loop_exceeded` でエスカレ停止
5. 修正中に `design_overview_break` を検知 → 即エスカレ停止 (commit しない)
6. review-adversarial の `test_weakened` / `skip_added` (confidence: high) は上記の self-fix ループに乗せない。弱体化を actor 自身に直させると骨抜きの温床になるため、4.2e と同じトレース確認 (TODO.md / DESIGN_DETAIL_APP.md に意図的な変更としてトレースできるか) をメインループが行い、トレース不能なら `test_weakening_detected` でエスカレ停止する
7. review-adversarial の `working_tree_polluted` を検知したら、メインループが `git status --porcelain` で実際の汚染有無を確認し、汚染があれば restore する

severity: low/medium の findings は修正せず JSONL に `event_type: review_low` で記録する。

##### 4.2e: テストゲート + コミット (メインループ)

コミット前に全テストスイートを **Bash で直接実行し、exit code 0 を確認する** (自己申告ではなく実行結果で判定):

- 失敗 → 修正して再実行。3 回試みても緑にならなければ `tests_failing_before_commit` でエスカレ停止

続けて**テスト弱体化の機械検知**を行う (reward hacking 対策。review-tdd の LLM 判定に頼らず、編集権限の外で機械判定する)。検知コマンド (テストファイル削除の検出 + skip/only/ignore 追加の検出) は [references/phase-execution.md](./references/phase-execution.md) の `## 4.2e: テスト弱体化検知コマンド` 節を Read してから実行する (この節を読まず近似コマンドで代替すると、言語別 skip/ignore パターンの見落としにより test_weakening 検知が漏れるリスクがある)。

ヒットした場合、その削除・skip が TODO.md / DESIGN_DETAIL_APP.md にトレースできる意図的な変更 (設計変更で仕様ごと削除等) か確認し、トレースできなければ `test_weakening_detected` でエスカレ停止する (パス扱いしない)。

緑を確認したら `rules/core/commit.md` に従いメインセッションがコミットする (関心事分割 / STRUCTURAL・BEHAVIORAL 分離。形式は commit-msg-guard hook が機械検証する)。push はしない (ユーザ手動)。

##### フェーズ内エスカレ条件まとめ

| 条件                                                                                                             | reason                                       |
| ---------------------------------------------------------------------------------------------------------------- | -------------------------------------------- |
| guard 3 回修正でも high/medium 違反残存                                                                          | `guard_loop_exceeded`                        |
| review self-fix 3 回でも fatal 残存                                                                              | `review_loop_exceeded`                       |
| 検査 agent が結果を返せない (未検証をパス扱いにしない)                                                           | `guard_agent_failed` / `review_agent_failed` |
| テストゲート 3 回不通過                                                                                          | `tests_failing_before_commit`                |
| `design_overview_break` 検知 (実装・修正中いずれでも、commit 前に停止)                                           | `design_overview_break` (P3)                 |
| テストファイル削除 / skip 追加が設計にトレースできない (4.2e の機械検知 / 4.2d の review-adversarial 検知の両方) | `test_weakening_detected`                    |

#### Step 4.6: 設計乖離の判定 (P1 / P2 / P3)

Step 4.2 でメインループが記録・累積した deviation_signals (実装 4.2a / guard 修正 4.2b / review self-fix 4.2d の全過程) を P 値に分類する。design 整合の判定は review findings の `dimension: "quality"` かつ `rule: "design_mismatch"` 系エントリも使う。

**シグナル元と分類対応**:

| シグナル元                                                                       | type                    | 分類                | 対処                                                           |
| -------------------------------------------------------------------------------- | ----------------------- | ------------------- | -------------------------------------------------------------- |
| メインループ実装                                                                 | `todo_minor`            | P1 (TODO 軽微)      | 下記「P1 動的修正」へ                                          |
| メインループ実装 / review-quality の design 整合 finding (severity: medium 以上) | `design_detail_gap`     | P2 (詳細設計の不足) | 下記「P2 動的修正」へ                                          |
| メインループ実装 / review-quality の design 整合 finding (severity: high)        | `design_overview_break` | P3 (概要設計の破綻) | エスカレ停止 (Step 4.2 内で検知した時点で commit 前に停止済み) |

**シグナル無しの場合**: 次の pending フェーズへ進む。

**集約のしかた**: 同一 phase 内で同種シグナルが複数回記録された場合、`scope` + `what` で重複排除してから処理 (1 件のシグナルとして扱う)。

##### P1 動的修正

1. `p1_fixes_in_phase += 1`。`p1_fixes_in_phase > 2` なら本シグナルを P2 (design_detail_gap) として扱い、P2 動的修正フローに切り替える (以降のステップは実行しない)
2. TODO.md の該当フェーズ周辺を Edit
3. ログに「P1 fix: <変更内容の 1 行サマリ>」を残す (JSONL は `event_type: p1_fix`)
4. 残タスクが当該フェーズ内なら継続、フェーズを跨ぐ追加なら新フェーズを挿入して以降のループに含める

##### P2 動的修正

1. `p2_fixes_total += 1`。`p2_fixes_total > 3` なら本シグナルを P3 (design_overview_break) として扱い、エスカレ停止する (以降のステップは実行しない)
2. DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md の該当側 (境界基準: 変更に IaC・コンソール操作・環境設定変更が要るなら INFRA) のセクションを Edit
3. **受入基準ガード**: Edit 直後に goals_sha を再計算 (Step 1 のコマンド) し、承認スタンプの値と照合する。不一致 = 受入基準 (ゴール / 検証手順行) を触った P2 であり、実装者による自己適用は禁止。Edit を revert せず `acceptance_criteria_change` でエスカレ停止する (「受入基準の変更が必要になった。dev-spec フェーズ 9 → 11 で再承認せよ」と通知。実装ガイド・スキーマ等の追記はハッシュ対象外なので通過する)
4. `../dev-spec/references/todo-generation.md` を Read し、その手順に従ってメインループで TODO.md を再生成する (差分更新モード)
5. Step 2 のフェーズ抽出 (`rg -n '^### フェーズ' docs/TODO.md`) を再実行してフェーズ一覧を更新する。既に `- [x]` 済みのタスクはそのまま完了扱いを維持し、再生成で新規追加された未完了タスクだけを pending に加える
6. ログに「P2 fix: <更新セクション>」を残す (JSONL は `event_type: p2_fix`)
7. 当該フェーズの再実行 (Step 4.2 から) か次フェーズへ進むかを判定: 再生成後の TODO.md で **当該フェーズ内に新規の未完了タスク (`- [ ]`) が追加されていれば Step 4.2 から再実行**、既存タスクが全て完了済みのまま (詳細設計の記述を補っただけで実装側の追加作業が無い) なら次フェーズへ進む
8. ユーザに対する通知は「DESIGN_DETAIL_APP.md (または _INFRA.md) / TODO.md を更新しました (詳細はログ参照)」程度 (dev-impl は止まらない)

##### P3 検出時

エスカレ停止 (後述の「エスカレ停止時の挙動」へ)。

シグナル処理が終わったら次の pending フェーズへ進む (コミットは Step 4.2e で実行済み)。

### Step 5: ゴール達成判定 + 未達対応ループ

Step 4 のフェーズループを抜けた時点で「全 TODO 消化」は完了している。ここから DESIGN.md のゴールが**実際に達成されているか**を機械判定する。

#### Step 5.1: ゴール一覧抽出

DESIGN.md の「ゴール」セクションを Read してゴール一覧を抽出 (例: `G1, G2, ...`)。抽出コマンド例: `rg -n '^- G[0-9]+:|^G[0-9]+:' docs/DESIGN.md`。

ゴール定義は Step 1 の構造ゲートで存在を保証済み。万一この時点で抽出できない場合は `goals_missing` でエスカレ停止する (**skip しない** — ゴール判定を省くと完了条件が「全 TODO 消化」という作業量ベースの自己申告になるため)。

#### Step 5.2: 第三者監査の並列起動

自動系ゴールの検証は**メインループが自分で実行しない** (実装者本人による自己判定を避ける)。`PRODUCT_MODE=cli` の場合は `review-spec-compliance` (mode: post-impl、G_E2E も自動系ゴールとして実行) を単独起動する。`webapp` / `unknown` の場合は `review-spec-compliance` と `review-product-readiness` (G_E2E) を**同一メッセージ内の複数 Agent tool_use として並列起動**する。起動する agent はすべて `model: opus` を明示する。起動コードは [references/goal-audit.md](./references/goal-audit.md) の `## 5.2: 監査 agent の並列起動` 節を Read してから実行する (この節を読まず近似の prompt で起動すると、`docs は自分で全文 Read すること` 等の指示や `output_path` / `holdout_enabled` / `product_mode` の欠落により第三者監査の独立性が落ちる)。

**G_E2E の判定**:
- **webapp / unknown**: review-product-readiness が判定。ナビ系 findings (`nav_unreachable` 等) の severity: high が 0 件 → achieved、1 件以上 → unmet。**dev_server が推定できない場合は判定不能** = `verification_skipped` を記録して手動 pending に落とす (achieved 扱いにしない)
- **cli**: review-spec-compliance が自動系ゴールとして G_E2E 検証コマンドを実行して判定。exit code 0 → achieved、非 0 → unmet。検証手順が手動系書式 (`G_E2E 検証 (手動)`) の場合は agent 側で実行不能なため `verification_skipped` を記録して手動 pending に落とす

#### Step 5.3: 監査結果の集約と gate 分岐

review-spec-compliance の `goal_results` (自動系) + review-product-readiness の判定 (G_E2E) + 手動系 (`G<n> 検証 (手動):` は manual_pending のまま) を統合し、JSONL に `event_type: goal_check` で記録する (各ゴールの `id / status / evidence`)。findings は `event_type: spec_compliance` で記録する。

findings ごとの分岐:

| findings (rule)                                                              | 対処                                                                                                                                            |
| ---------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `verification_tampered` (high)                                               | **即エスカレ停止 (P3、修正ループなし)**。受入基準の改変は実行者に直させる対象ではなく、人間の再承認 (dev-spec フェーズ 11) 事案                 |
| `goal_result_mismatch` (high)                                                | 監査 agent の実行結果を正とし、当該ゴールを unmet として未達対応ループへ (自己申告ログとの食い違い自体も JSONL に残す)                          |
| unmet ゴール / `unimplemented_api` / `schema_drift` / `infra_missing` (high) | Step 5.5 の未達対応ループへ (finding の `fix_proposal` / `evidence` を新フェーズの内容に使う)                                                   |
| `vacuous_verification` (high)                                                | **自動修正させない** (検証コマンドを実行者が「直す」のは骨抜きの温床)。当該ゴールを手動 pending に落とし、Step 6 サマリで人間確認要求として明示 |
| medium / low のみ                                                            | JSONL 記録 + POST_MVP.md へ転記 (Step 5.6)。status `partial` 判定に反映                                                                         |
| agent エラー / JSON 解釈不能                                                 | `review_agent_failed` でエスカレ停止 (未検証をパス扱いにしない)                                                                                 |

#### Step 5.4: 結果分岐

| 状況                                                    | 対処                   |
| ------------------------------------------------------- | ---------------------- |
| 全ゴール achieved (or 手動 pending のみ) かつ high 0 件 | Step 6 へ (完了サマリ) |
| unmet ゴール or 修正可能な high findings が 1 件以上    | 未達対応ループへ       |

#### Step 5.5: 未達対応ループ

`goal_loop += 1`。`goal_loop > 2` なら P3 として停止 (エスカレ)。

それ以外:

1. 未達ゴール・修正可能な high finding (`unimplemented_api` / `schema_drift` / `infra_missing`) ごとに TODO.md に新規フェーズを追加 (例: `### フェーズN+1: ゴール G2 達成タスク`)
   - フェーズ内容は「G2 が未達。検証コマンド `<cmd>` が exit code != 0。失敗ログ: `<evidence>`。これを満たす実装を追加する」(findings 由来は `message` + `fix_proposal` を使う)
   - JSONL に `event_type: phase_added` で記録
2. Step 4 のフェーズループに戻る (新規追加フェーズだけが pending)
3. 完了後、Step 5.1 に戻って再判定 (Step 5.2 の監査 agent も**再起動**する。前回結果の使い回しは不可 — 修正が別の乖離を生んでいないかを再監査する)

手動 pending ゴールは Step 6 サマリで「人間確認必要」として明示する (dev-impl は判定せず保留)。

#### Step 5.6: POST_MVP.md の更新と status 判定

Step 5 のゴール判定後、`docs/POST_MVP.md` に **「UI/UX gap」セクション**を書き出す。**`PRODUCT_MODE=cli` の場合は本セクションを省略する** (status 判定の「UI/UX gap 全項目空」条件は自動的に満たされる)。`webapp` では常に書き出す。`unknown` では dev_server 推定が真の場合のみ書き出す (推定できなければ cli と同様に省略)。

##### UI/UX gap セクションの内容

セクションの必須項目テンプレート (未実装画面 / 未実装ナビ経路 / frontend-design 未適用フラグ / a11y 未対応項目 / 視覚的回帰参照) は [references/post-mvp-template.md](./references/post-mvp-template.md) を Read して従う。各項目は **dev-impl が自動でログ / review 結果から収集して埋める** (decisions.jsonl / review-product-readiness の findings / G_E2E 判定結果から)。

##### 未検証項目の集約

**実行しなかった検証は「成功」と区別できるよう必ず可視化する** (沈黙は成功に見えるため)。以下の事象は発生時に JSONL へ `event_type: verification_skipped` (context に対象と理由) を記録し、ここで集約して Step 6 サマリに列挙する:

- dev_server が推定できず skip した review-product-readiness / G_E2E 検証
- fix-lsp-warnings の失敗 (警告残存のまま継続した場合)
- 手動 pending のゴール

##### status 判定

UI/UX gap セクションが**空でなければ** dev-impl の終了 status を `partial` にする:

| 状況                                            | status                              |
| ----------------------------------------------- | ----------------------------------- |
| 全ゴール達成 + UI/UX gap 全項目空 + 未検証 0 件 | `done`                              |
| 全ゴール達成だが UI/UX gap または未検証項目あり | `partial` (未仕上げ / 未検証が残る) |
| 自動ゴール未達ありで未達対応ループ実行中        | (Step 5 内ループ継続)               |
| 未達ゴールで goal_loop > 2                      | `escalated` (Step 5 で P3 停止)     |

`partial` でも commit と HTML レポート生成は実行 (中途半端でも記録は残す)。

### Step 6: 全フェーズ完了サマリ

サマリー生成前に、記載する各主張 (フェーズ完了数・ゴール達成状況・動的修正回数・受入監査結果) を本セッションの実際のツール実行結果 (`git log`、`decisions.jsonl`、review agent の出力 JSON) と突き合わせる。裏付けが取れない主張は記載しない、または「未確認」と明記する。テンプレートは [references/notification-template.md](./references/notification-template.md) の `## 完了サマリ (Step 6)` 節を Read し、全フィールドを埋めて出力する。

### Step 7: HTML レポート生成

dev-impl 終了時 (Step 6 完了後、またはエスカレ停止時) に `docs/dev-impl-reports/${run_id}.html` を生成する。

実装詳細とテンプレ関数は [references/report-template.md](./references/report-template.md) を参照。

生成手順:

1. JSONL ログ (`~/.claude/logs/dev-impl/${run_id}/decisions.jsonl`) を Read
2. テンプレ関数 (single-page Tailwind CDN HTML) でレポート HTML を組み立て
3. `mkdir -p docs/dev-impl-reports/` で出力先確保
4. Write で `docs/dev-impl-reports/${run_id}.html` に書き出し
5. `git add docs/dev-impl-reports/${run_id}.html` してコミット (HTML レポートは履歴管理する): `git commit -m "📝 docs: dev-impl ${run_id} 実行レポート"`

レポート内容: ヘッダー (run_id / SHA / 所要時間) / 全体サマリ / フェーズタイムライン / 動的修正詳細 (P1/P2/P3) / レビュー残課題 (low/medium) / 実装ノート (設計判断 / 未解決の質問) / POC_NEEDED 残存状況 (pending non-blocker) / ゴール達成判定 / 受入監査結果 (spec_compliance findings) / フッター。

## エスカレ停止時の挙動

停止条件:
- Step 4.2 のフェーズ内エスカレ条件 (`guard_loop_exceeded` / `review_loop_exceeded` / `guard_agent_failed` / `review_agent_failed` / `tests_failing_before_commit`)
- P3 検出 (DESIGN.md 概要レベルの再設計必要)
- `p2_fixes_total > 3` (P3 扱いに昇格)
- `goal_loop > 2` (ゴール達成判定 → 未達対応の 3 周回でも未達ゴール残存)
- `run_elapsed_minutes > 480` (`time_budget_exceeded`。試行回数の上限だけでなく経過時間でも打ち切る)
- 必須ドキュメント (DESIGN.md / DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md / TODO.md) 欠如
- `blocker=true` の POC_NEEDED マーカーが残存 (`poc_marker_unresolved`。dev-spec フェーズ 5 で解決してから再実行)
- Step 1 構造ゲートの欠落 (`design_not_approved` / `approval_stale` / `goals_missing` / `verification_missing`)
- テスト弱体化が設計にトレースできない (`test_weakening_detected`)
- P2 動的修正が受入基準 (ゴール / 検証手順行) を変更した (`acceptance_criteria_change`。dev-spec フェーズ 9 → 11 で再承認)
- 受入監査が受入基準の改変を検知 (`verification_tampered`。P3 扱い、修正ループなし)

停止時の処理:

1. 当該フェーズの変更は**コミットしない** (緑状態でないため。working tree は残す)
2. 停止理由を `~/.claude/logs/dev-impl.log` と JSONL (`event_type: p3_escalate`) と stdout 全てに詳細出力
3. HTML レポート (Step 7) を生成 → コミット (停止時もレポートだけは残す)
4. ユーザに通知 (通知内容もログ・review agent の出力から裏付けが取れる事実のみを記載する)。テンプレートは [references/notification-template.md](./references/notification-template.md) の `## エスカレ停止通知` 節を Read し、全フィールドを埋めて出力する (Read せず記憶から近似文面を出すと、最終成功 commit SHA や完了フェーズ数など裏付け必須フィールドが欠落し停止理由の追跡性が落ちる)。

## 既存プロジェクトでの注意

- 既存のコミット history と dev-impl のコミット粒度を混ぜたくない場合は、dev-impl 起動前に専用の作業ブランチを切ることを推奨 (dev-impl 自体はブランチ切替を行わない)
- `bypassPermissions` モード推奨 (途中で permission prompt が出ると dev-impl が止まるため)
- launchd / cron などからヘッドレス実行する場合は `claude -p` 経由で、`--allowedTools` に `Bash,Read,Edit,Write,Glob,Grep,Agent,Skill` を渡す。**headless では AskUserQuestion を使わない** (答える人間がいないため、質問した時点でループが死ぬ)。エスカレ時は停止理由を stdout と JSONL に出力し、darwin なら `terminal-notifier` で通知して終了する。Step 0 の再入確認 (working tree の扱い) も headless では確認せず「そのまま停止を継続」とし、人間の対話セッションでの再開を待つ

## 範囲外 (やらないこと)

- 設計の合意 (DESIGN.md / DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md 生成) → `/dev-spec`
- TODO.md の初期生成 → `/dev-spec` (フェーズ 10)
- git push → ユーザー手動
- ブランチ切替・PR 作成 → ユーザー手動 (or `/workflow-create-draft-pr`)
- 動作検証 (実 UI / API テスト) → ユーザーが DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md の検証手順に従って実施

## 関連スキル / agent

### 内部呼び出し (subagent = 独立した検査・調査の fan-out のみ)

- **tech-investigation**: 実装中に新たな技術検証が必要になった場合の個別呼び出しのみ (起動前の PoC は dev-spec フェーズ 5 の責務)
- **architecture-guard**: Clean Arch / DDD 境界違反検出、機械判定 (Step 4.2b、haiku)
- **fix-lsp-warnings**: Lua/Neovim の LSP 警告修正 (Step 4.2c)
- **review-tdd / review-quality / review-product-readiness**: Step 4.2d から `model: opus` 明示で並列起動 (観点 gating・起動条件は Step 4.2d 参照)。review-quality は rules 準拠 + アーキテクチャ heuristic を統合。review-product-readiness は実機 chrome-devtools MCP 操作で UX 横断項目 (ナビ到達 / ErrorBoundary / 空状態 / loading / SEO meta / 404 / logout) を検査 (Step 5.2 の G_E2E 判定も担当)
- **review-adversarial**: Step 4.2d から `model: opus` 明示で並列起動する敵対的レビュワー。3 レンズ (A: エッジケース/エラーパスを能動的に攻撃し実際に実行して落とす、B: テスト弱体化・トートロジー化・skip 隠蔽の意味論検知、C: PHASE_CONTEXT を信用せず TODO.md の完了主張に反証を試みる) で検査。機械スキップ述語 (Step 4.2d 参照) を満たせば skip 可。`test_weakened` / `skip_added` (confidence: high) は self-fix ループに乗せず即エスカレ判定に直結する (詳細は Step 4.2d ループ規則参照)
- **review-spec-compliance**: Step 5.2 から `model: opus` 明示で起動する第三者受入監査 (mode: post-impl)。承認ハッシュの独立照合・自動系ゴール検証コマンドの独立再実行・成果物全体 ↔ 詳細設計の突合・検証コマンドの空虚性検査。PHASE_CONTEXT 抜粋は渡さず docs を自分で全文 Read させる (被監査者が編纂した入力を信用しない)。`PRODUCT_MODE=cli` では G_E2E 検証コマンドの実行もこの agent が担当する (review-product-readiness は起動しないため)
- **security-guidance プラグイン**: セキュリティレビューはこのプラグイン (Edit/Write 時の pattern 検知 + Stop hook の LLM diff review) に委譲。自作 subagent は持たない

フェーズの TDD 実装・修正・テスト実行・コミットは**メインセッションが直接行う** (CLAUDE.md「サブエージェントの使い方」: 逐次依存する多段作業は subagent に出さない)。

### 内部呼び出し (skill)

なし。P2 動的修正時の TODO 再生成は `../dev-spec/references/todo-generation.md` を Read してメインループで直営する (Skill ツール経由ではモデル指定が効かないため、skill 呼び出しは増やさない)。

(手動レビュー用の `workflow-review` skill と `workflow-commit` skill は dev-impl からは呼ばない。相当の処理は Step 4.2d / 4.2e が担う)

### 連携 hook

- **tdd-guard hook (`tdd-guard.ts`)**: メインループの TDD 違反を機械的に強制 (PreToolUse で実装編集を事前ゲート + Bash 書き込み検知 + 停止時テスト未実行チェック)。dev-impl は意識しない
- **commit-msg-guard hook (`commit-msg-guard.ts`)**: Step 4.2e のコミット形式を機械検証

### 前段 / 後段

- **dev-spec**: 前段。設計ループ (要件整理 〜 PoC 検証 〜 設計書 〜 TODO 生成)。承認ゲートで本スキルの起動方法を案内する
- **workflow-create-draft-pr**: 後段 (任意)。PR 作成はユーザーが手動で起動する
