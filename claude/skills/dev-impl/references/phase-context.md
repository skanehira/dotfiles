# PHASE_CONTEXT テンプレートと抜粋ロジック (dev-impl Step 4.1.5)

PHASE_CONTEXT は、フェーズを実装する implementer と検査する subagent が**親のコンテキストを継承しない**前提で、フェーズ 1 本を完結させるのに必要な情報を 1 ファイルにまとめたもの。親 (メインセッション) が `docs/.dev-impl/<run_id>/phase-<識別子>-context.md` に Write し、subagent には絶対パスだけを渡す。

## テンプレート

```yaml
product_mode: <cli|webapp|unknown>       # Step 1 で DESIGN.md スタンプから判定した PRODUCT_MODE
phase_name: <フェーズN: 名前>            # issue タイトルから (12.4.2 が固定した形式)
phase_start_sha: <SHA>                   # Step 4.1 で記録
phase_tasks: |                           # issue 本文の実装指示セクション
  <issue 本文の ## ゴール / ## DoD / ## 非スコープ / ## 実装タスク を awk で抽出>

# --- 検証コマンド (実行主体つき。すべて親が実際に成立を確認した値を書く) ---
phase_test_command: <このフェーズのテストだけを回すコマンド>   # implementer が実行 (4.2b の LSP 修正後は main も実行)
full_test_command: <全体スイート>                            # 親が 4.2e で実行 (implementer は実行しない)
lint_command: <lint コマンド、無ければ null>                  # implementer が実行
format_command: <formatter コマンド、無ければ null>           # implementer が実行
gate_commands_verified: <true|false>     # 上記を親が実際に実行して exit code を確認済みか

# --- run スコープの累積事実 ---
run_facts_path: <docs/.dev-impl/<run_id>/RUN_FACTS.md の絶対パス>

# --- 設計抜粋 ---
design_overview: |                       # DESIGN.md 関連節抜粋 (上限あり、下記「抜粋ロジック」参照)
  <主要コンポーネント / 非機能目標 / ゴール のうち、現フェーズに関連する節>
design_overview_path: docs/DESIGN.md     # 抜粋で不足する場合に subagent が自分で Read するための固定 path
design_detail: |                         # DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md 関連節抜粋 (上限あり)
  <API / スキーマ / シーケンス / 実装ガイド / リソース定義 / CI/CD のうち、現フェーズに関連する節。APP / INFRA どちら由来かを見出しに付記>
design_detail_app_path: docs/DESIGN_DETAIL_APP.md
design_detail_infra_path: docs/DESIGN_DETAIL_INFRA.md

# --- 既存コードの状態 ---
repo_state: <greenfield|existing>        # 下記「repo_state」参照。related_source_files の空配列の意味を確定させる
related_source_files:                    # subagent が Read すべき既存ファイル一覧
  - <Glob で抽出した関連ファイル path>

related_rules_paths:                     # rules/core (固定) + 言語別 rules (下表の機械判定で決まる)
  - $HOME/.claude/rules/core/tdd.md
  - $HOME/.claude/rules/core/design.md
  - $HOME/.claude/rules/core/testing.md
  - $HOME/.claude/rules/core/implementation.md
  - $HOME/.claude/rules/core/verification.md
  - <言語別 rules。下記「言語別 rules の選択」の表で決める>
prev_phase_summary: |                    # 直前フェーズの 1-3 行要約
  <decisions.jsonl から拾う or null>
poc_results:                             # dev-spec フェーズ 5 が FEASIBILITY.md「PoC 結果」に記録した内容から抽出。FEASIBILITY.md が無い場合は空配列
  - id: <POC_NEEDED id>
    recommended_approach: <結論>
dev_server:                              # review-product-readiness (Step 4.2c) 用。Web プロダクトでなければ null
  url: <検出できた URL>
  start_command: <package.json の dev/start script>
snapshot_dir: <$SCRATCH_DIR/product-readiness-snapshots/ の絶対パス>  # 視覚的回帰の参考データと dev サーバの PID ファイルの置き場
```

## 抜粋ロジック

- `phase_tasks`: `gh issue view <N> --json body -q .body` の出力から `## ゴール` / `## DoD` / `## 非スコープ` / `## 実装タスク` の 4 節を切り出す (`## 参照すべき docs` は設計の該当節を読む入口なので、必要な節だけ docs から読んで `design_detail` に入れる)
- `design_overview` / `design_detail`: フェーズ名から推測した key term (例: 「認証」「ユーザー登録」「CI」「デプロイ」) で DESIGN / DETAIL_APP / DETAIL_INFRA を grep、ヒット節とその前後を抜粋。**抜粋は必須、全文フォールバックは禁止** (1 フェーズにつき implementer + 最大 4 検査 subagent がそれぞれ Read するため、全文だとコストが大きい)。抜粋の目安上限は 1 ファイルあたり 4KB、超える場合は該当節の見出し + 要約のみ残す。抜粋に加えて「このフェーズに関連しそうな DESIGN / DETAIL_APP / DETAIL_INFRA の見出し一覧」を必ず列挙し、抜粋に本文が無い見出しが必要になったら subagent が `*_path` を自分で Read する (抜粋漏れを silent にしない。Read した subagent は報告の `spec_lookups` に記録し、親が抜粋精度を事後に確認できるようにする)
- `related_source_files`: フェーズ名 / phase_tasks から推測したキーワードで Glob (`src/**/*<key>*`) + git diff で過去フェーズで触ったファイル
- `prev_phase_summary`: decisions.jsonl の直前 issue の `event_type: impl_done` エントリ summary を引く

### 言語別 rules の選択

`related_rules_paths` の言語別 rules は「あれば追加」ではなく、`related_source_files` の拡張子から機械的に決める (判断を挟むと毎回抜ける。実測で React プロジェクトのフェーズに `rules/frontend/react/` が一度も渡っていなかった):

```bash
EXTS=$(printf '%s\n' $RELATED_SOURCE_FILES | rg -oi '\.[a-z]+$' | tr 'A-Z' 'a-z' | sort -u)
FRONTEND_DIR=$(printf '%s\n' $RELATED_SOURCE_FILES | rg 'apps/web/|frontend/|src/components/|src/pages/|src/web/' || true)
```

| 条件 | 追加する rules |
| --- | --- |
| `$EXTS` に `.tsx` / `.jsx` が含まれる、または `$FRONTEND_DIR` が非空 | `$HOME/.claude/rules/frontend/react/components.md` / `hooks.md` / `data-fetching.md` / `performance.md` |
| `$EXTS` に `.go` が含まれる | `$HOME/.claude/rules/backend/go/design.md` / `coding.md` / `testing.md` |
| `$EXTS` に `.rs` が含まれる | `$HOME/.claude/rules/backend/rust/design.md` / `coding.md` / `testing.md` |

判定に `uiPhase` を使わないのは、`uiPhase` を算出するのが Step 4.2 の事前判定 (本節が動く Step 4.1.5 より後) だからで、代わりに `uiPhase` と同じフロントエンド dir 判定をここで直接行う。

該当が無ければ言語別 rules は空 (`rules/core` の 5 ファイルのみ)。複数該当する場合は該当分をすべて挙げる。**実在するファイルだけを挙げる** — 渡したパスが存在しないと implementer は Read に失敗し、rules 全体を読み飛ばす方向に倒れる。列挙の前に `ls` で存在を確認する。

### repo_state

`related_source_files: []` は「関連ファイルが無い」とも「調査していない」とも読めるため、implementer が既存コードの有無を確認する探索を追加で行ってしまう。空配列の意味を `repo_state` で確定させる:

| 値 | 意味 |
| --- | --- |
| `greenfield` | フェーズの実装対象ディレクトリに既存実装が無い。implementer は既存コードの探索を行わずゼロから書いてよい |
| `existing` | 既存実装がある。`related_source_files` に挙げたファイルを Read してから実装する |

判定は実装対象ディレクトリ (`design_detail` に現れるパスの親ディレクトリ) を Glob し、テスト・設定以外のソースが 1 件でもあれば `existing`。

### 検証コマンドの決定

`phase_test_command` / `full_test_command` / `lint_command` / `format_command` は**親が決めて実値で書く** (implementer に毎フェーズ探索させない)。取得元の優先順:

| プロジェクト | 取得元 |
| --- | --- |
| Node / Bun | `package.json` の `scripts.test` / `scripts.lint` / `scripts.format` |
| Deno | `deno.json` の `tasks`。lint/fmt は `deno lint` / `deno fmt` |
| Go | `go test ./...` / `golangci-lint run` / `gofmt -l .` |
| Rust | `cargo test` / `cargo clippy` / `cargo fmt --check` |
| Make / just | `Makefile` / `justfile` の `test` / `lint` / `fmt` ターゲット |

`phase_test_command` は全体スイートをフェーズのディレクトリ・パターンに絞ったもの (例: `deno test src/version/`、`npm test -- src/auth`、`go test ./internal/auth/...`)。絞り込めないプロジェクトでは `full_test_command` と同じ値を入れたうえで、**その旨を RUN_FACTS の「既知の落とし穴」に書く** (implementer のテスト実行が長時間化してキャッシュを失効させるリスクを親が把握するため)。

**run の最初のフェーズ (= RUN_FACTS.md をこの run で新規作成したフェーズ) では、親が `full_test_command` / `lint_command` / `format_command` を実際に 1 回実行して exit code を確認する。** 結果を RUN_FACTS.md の「確認済み」列に書き、全て exit 0 なら PHASE_CONTEXT を `gate_commands_verified: true` で書く。2 フェーズ目以降は RUN_FACTS.md の同列から値を引き継ぐ。未検証のコマンドを渡すと、implementer が自分の実装のせいで失敗していると誤認して発散する (`false` を受け取った implementer の挙動は `claude/agents/dev-impl-implementer.md` に規定がある)。

### dev_server

- **`product_mode: cli` の場合は判定せず常に `null`** (ディレクトリ名の推定を行わない)
- `webapp` / `unknown` の場合は Web プロダクト判定 (`apps/web/`, `apps/`, `web/`, `frontend/` 等のディレクトリ + `package.json` の `dev`/`start` script の有無) を使う
  - Web プロダクトでなければ `null` (review-product-readiness は URL 不在で no-op、`ok: true` 素通り)
  - Web プロダクトの場合: `start_command` は `package.json` の `scripts.dev` (無ければ `scripts.start`)。`url` は以下の順に推定する:
    ```bash
    rg -n 'port\s*:\s*\d+' vite.config.ts vite.config.js 2>/dev/null   # Vite の server.port 明示指定
    test -f next.config.js -o -f next.config.ts && echo "port=3000"    # Next.js デフォルト
    test -f vite.config.ts -o -f vite.config.js && echo "port=5173"    # Vite デフォルト (上の rg でヒット無ければ)
    ```
    **推定に確信が持てない場合 (上記いずれにも一致しない) は `dev_server` を `null` にする** (誤ったポートを渡すと review-product-readiness が `dev_server_unavailable` の偽陽性を報告し、修正ループが実装側で直しようのないエラーを再試行し続けるため)

## RUN_FACTS.md

run 全体で 1 ファイル (`docs/.dev-impl/<run_id>/RUN_FACTS.md`)。**親だけが書き、implementer と検査 subagent は Read のみ**。フェーズをまたぐ文脈の再注入を 1 ファイルの Read に圧縮するための仕掛けで、これが無いと implementer は毎フェーズ「このプロジェクトはどう作られているか」を探索し直す。

ライフサイクル:

| 時点 | 主体 | 操作 |
| --- | --- | --- |
| run の最初のフェーズの Step 4.1.5 (PHASE_CONTEXT を書く前) | 親 | **新規作成**。「プロジェクトコマンド」表を埋め、他の節は見出しだけ置く。ファイルの存在自体が「この run で gate コマンドを検証済みか」の判定にもなる |
| 各フェーズの Step 4.2e (コミット後) | 親 | implementer 報告から追記し、JSONL に `event_type: run_facts_updated` を記録。4096 バイト超で畳み込む |
| 各フェーズの実装・検査中 | implementer / 検査 subagent | Read のみ |

```markdown
# RUN_FACTS (run_id: <run_id>)

## プロジェクトコマンド

| 用途 | コマンド | 確認済み |
| --- | --- | --- |
| フェーズテスト | `<phase_test_command の雛形>` | <yes/no> |
| 全体テスト | `<full_test_command>` | <yes/no> |
| lint | `<lint_command>` | <yes/no> |
| format | `<format_command>` | <yes/no> |

## 完了フェーズの成果物

| フェーズ | 主要ファイル | 責務 (1 行) |
| --- | --- | --- |
| 1 | `src/auth/session.ts` | セッション発行と失効判定 |

## 累積 design_decisions

- <フェーズ N> <decision の 1 行要約> (根拠: <rationale の要点>)

## 既知の落とし穴

- <実際に観測した事実のみを書く>
```

規則:

- **上限 4KB。** 超えたら古い「完了フェーズの成果物」行から要約に畳む (最新 3 フェーズは原文を残す)
- **「既知の落とし穴」には実際に観測した事実だけを書く。** 「〜を使うとよい」といった未検証の助言を書かない。未検証の前提を書くと implementer がそれに従って失敗し、原因究明のターンを消費する (実測: 未検証の import 指定 1 行が implementer の `deviation_signals` 1 件と lint 失敗 1 往復を生んだ)
- 「累積 design_decisions」は後続フェーズが同じ論点を再検討しないために置く。同一の判断を後続フェーズが踏襲する場合、implementer は再度 `design_decisions` に記録しない

## 渡し方

| 受け取る側 | PHASE_CONTEXT |
| --- | --- |
| implementer (implement / fix) | 絶対パスを渡す |
| review-tdd | 絶対パスを渡す。**加えて `exemptions_path` (`$SCRATCH_DIR/self-exemptions.json`) を渡す** — 免除 0 件でも必ず渡し、受け側は `adjudicated_exemptions` を返す (SKILL.md 4.2c / 4.2d 手順 1) |
| review-quality | 絶対パスを渡す |
| review-product-readiness | 絶対パスを渡す。**加えて `repo_dir` (絶対パス) / `dev_server` (url と start_command) / `snapshot_dir` (`$SCRATCH_DIR/product-readiness-snapshots/`) を渡す** — `snapshot_dir` は dev サーバの PID ファイル置き場でもあり、落とすと agent が起動したサーバを停止できず、以降のフェーズが古いコードのサーバを検査し続ける |
| architecture-guard | **渡さない** (`claude/agents/architecture-guard.md` の入力節が PHASE_CONTEXT を受け取らないため。代わりに `design_path` / `design_detail_path` / `target_diff` / `PHASE_START_SHA` / `repo_dir` / `output_path` を直接渡す) |
| review-adversarial | **渡さない** (fresh context 監査のため、`mode` / phase_name / phase_start_sha / repo_dir / docs_dir / dev_server / scratch_dir / **`exemptions_path`** / output_path のみを直接渡す。`exemptions_path` は免除 0 件でも必ず渡す — 渡すのは実装の説明ではなく「検証しないと宣言した項目の名指しリスト」なので fresh context の趣旨は壊れない。`mode` は SKILL.md 4.2c で確定した `full` / `weakening_only`。省略すると agent 側の既定で `full` になる。`weakening_only` のときは docs_dir / dev_server を渡さない) |
