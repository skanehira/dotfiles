# 並列フェーズ実行の詳細手順 (dev-impl Step 2 / Step 4)

`dev-impl/SKILL.md` の Step 2 (フェーズ抽出 + wave 構築) と Step 4 (各フェーズの実行) から参照される実行コマンドの詳細。並列モードの可否判定条件・上限カウンタ・エスカレ条件は SKILL.md 本体にあるので、そちらを先に読んでから該当節だけをここで参照する。本ファイルは**同時に 2 フェーズ以上を実装する場合の差分**を定義し、逐次モード (wave サイズ 1 フェーズ) の手順は SKILL.md 本体の 4.1 / 4.1.5 / 4.2 / 4.6 が正。

用語:

| 用語 | 定義 |
| --- | --- |
| **wave** | 同時に着手できるフェーズの集合。TODO.md の `deps` 宣言をトポロジカルソートした 1 層分 |
| **識別子** | フェーズ見出しの `フェーズ` 直後からコロンまでの文字列 (`1` / `3` / `5-a`)。ブランチ名・worktree ディレクトリ名に埋め込むため半角英数字とハイフンのみ (定義は `../../dev-spec/references/todo-generation.md` の `#### フェーズ依存の宣言 (dev-impl の並列実行に使う)`) |
| **implementer** | wave 内の 1 フェーズを専用 worktree で実装する subagent (`model: sonnet`)。実装 + guard + レビュー + 修正までを worktree 内で完結させる |
| **統合** | 親 (メインセッション) が implementer の成果ブランチを squash merge し、全テストゲートを通してコミットするまでの一連の処理 |

## Step 2: wave の構築

### deps 抽出

```bash
rg -n '^### フェーズ' docs/TODO.md
```

各見出し行から次の 2 つを取り出す:

- **識別子**: `フェーズ` 直後からコロンまでの文字列
- **deps**: 行末の `<!-- deps: <識別子のカンマ区切り、または none> -->`

可否判定 (`deps_missing` / `deps_unknown_ref` / `deps_cycle`) の条件表は SKILL.md の Step 2 にある。判定に失敗したら全フェーズ逐次モードで実行する。

### トポロジカル層への分割 (Kahn 法)

pending フェーズのみを対象に、完了済み (`- [x]` のみ) フェーズへの依存は「充足済み」として無視する:

1. 各 pending フェーズの未充足 deps 数を数える
2. 未充足 0 のフェーズ集合を 1 つの wave として取り出す
3. 取り出した wave のフェーズを deps から削除し、2 に戻る
4. pending が尽きるまで繰り返す

wave 内のフェーズ数が `concurrent_implementers` の上限 (3 フェーズ) を超える場合は**バッチに分割**する。TODO.md の出現順で先頭 3 件ずつを 1 バッチとし、バッチ単位で「fan-out → 全 implementer の完了待ち → 統合」を回す。上限 3 は「統合が逐次である以上、実装を増やしても統合待ちが伸びるだけ」という釣り合いから置いた既定値で、統合が軽いプロジェクトでは起動時に増やしてよい (変更したら JSONL の `batch_size` に反映される)。

**4p.1 以降はバッチ単位の手順**として実行する。`WAVE_BASE_SHA` はバッチ開始時に取り直す — wave 全体で 1 回しか取らないと、2 バッチ目の worktree が 1 バッチ目の統合コミットを含まない古い base から分岐し、不要なコンフリクトと古いコードでのテストを招く。

**dev_server を要するフェーズ (`uiPhase == true` かつ PHASE_CONTEXT の `dev_server` が非 null) は 1 バッチにつき 1 フェーズまで**とし、2 つ目以降は次のバッチに回す。同一 wave の複数 implementer が同じポートで dev サーバを起動すると衝突し、review-product-readiness が `dev_server_unavailable` の偽陽性を出して self-fix ループが実装側で直しようのないエラーを再試行し続けるため。

**最終フェーズの定義** (review-quality / 全観点フルの起動条件、SKILL.md 4.2d) は逐次モードと同じく **TODO.md 上の最後のフェーズ**とする (最終 wave 全体ではない)。

## Step 4 (並列モード): wave の実行

wave サイズが 1 フェーズなら SKILL.md の 4.1 / 4.1.5 / 4.2 / 4.6 をそのまま実行する (worktree も implementer も使わない)。2 フェーズ以上のときだけ以下に従う。

SKILL.md の各節との対応:

| SKILL.md の節 | 並列モードでの実行箇所 |
| --- | --- |
| 4.1 (PHASE_START_SHA 記録) / run_elapsed_minutes 計算 | 4p.1 (wave 開始時に 1 回。`WAVE_BASE_SHA` が全フェーズ共通の基準) |
| 4.1.5 (PHASE_CONTEXT 組み立て) | 4p.2 (wave 内の全フェーズ分を親が作る) |
| 4.2 事前判定 (`uiPhase` / `IS_NEOVIM_PLUGIN`) | 4p.2 (親が算出し、観点 gating を確定して指示文に埋める) |
| 4.2a〜4.2d (実装 / guard / LSP / レビュー) | 4p.3 (implementer が worktree 内で実行) |
| 4.2e (テスト弱体化検知 / テストゲート / コミット) | 4p.4 (親が統合時に実行) |
| 4.6 (設計乖離 P1/P2/P3 判定) | 4p.4 手順 9 (親が implementer 報告の deviation_signals を転記してから実行) |

### 4p.1: worktree の準備 (親)

```bash
REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")
WAVE_BASE_SHA=$(git rev-parse HEAD)   # バッチ開始時点。このバッチの全 implementer の共通の親
mkdir -p ~/worktrees

# wave 内の各フェーズについて (PHASE_ID には識別子を入れる。例: PHASE_ID=5-a)
PHASE_ID=<識別子>
git worktree add ~/worktrees/${REPO_NAME}-phase-${PHASE_ID} -b dev-impl/phase-${PHASE_ID} ${WAVE_BASE_SHA}

# レビュー結果 JSON の置き場 (worktree の外。squash merge の対象にならず、再入時も残る)
SCRATCH_DIR=~/.claude/logs/dev-impl/${run_id}/reviews/phase-${PHASE_ID}
mkdir -p "$SCRATCH_DIR"
```

- 置き場所を `~/worktrees/` 固定 + リポジトリ名 prefix にするのは、**別リポジトリで同時に dev-impl を回してもディレクトリ名が衝突しないため**。Agent ツールには組み込みの `isolation: "worktree"` があるが、置き場所を指定できず統合前に自動クリーンアップされうるので、統合を親が握る本フローでは手動管理する
- `SCRATCH_DIR` を worktree 外かつ run_id 配下に置くのは、(a) squash merge にレビュー成果物が混入しないため、(b) エスカレ停止後の再入時に親が同じ JSON を Read して統合を再開できるため
- **前回 run の残骸の扱いは SKILL.md Step 0 の再入チェックに一本化する**。Step 0 を通過した時点で「取り込む」と判断された worktree は残っている (4p.4 の統合手順から再開する) ので、ここでは作らない。それでも同名が存在する場合は**同一 run 内の再試行** (フォールバック後の作り直し等) なので `git worktree remove --force` + `git branch -D` で掃除してから作り直してよい
- 依存パッケージのインストール (`npm ci` / `bun install` / `go mod download` 等) は worktree ごとに必要。**実行は implementer に任せる** (プロジェクトごとにコマンドが違うため、指示文で「必要ならセットアップコマンドを実行せよ」と伝える)
- **git 管理外だが実行に必須のファイル** (`.env` / ローカル設定 / DB fixture / `.direnv` 等) は worktree に存在しない。メインの working tree に該当ファイルがあれば親が worktree へコピーし、何をコピーしたかを JSONL に記録する (コピーしないとセットアップやテストが実行できず、implementer が原因不明の失敗を報告する)
- `run_elapsed_minutes` はバッチ開始時と各フェーズの統合前に計算する ([phase-execution.md](./phase-execution.md) の `## 4.1: run_elapsed_minutes 計算`)。上限超過ならバッチに着手せずエスカレ停止する (逐次モードの 4.1 に相当する評価点がここになるので、省くと time budget が並列モードで一度も評価されない)。`p1_fixes_in_phase` は各フェーズの統合時 (4p.4) にリセットする

### 4p.2: PHASE_CONTEXT と観点 gating の確定 (親)

wave 内の各フェーズについて、SKILL.md Step 4.1.5 と [phase-context.md](./phase-context.md) に従って `docs/.dev-impl/<run_id>/phase-<識別子>-context.md` を Write する。並列モード固有の差分:

- `phase_start_sha`: `WAVE_BASE_SHA` を入れる (implementer の worktree はここから分岐しているため、worktree 内の `git diff ${WAVE_BASE_SHA}` がそのフェーズの差分になる)
- `prev_phase_summary`: wave 内の他フェーズはまだ実装されていないので参照できない。**wave 開始時点で統合済みの最後のフェーズ**の summary (decisions.jsonl の直近 `impl_done` または `done`) を入れる

PHASE_CONTEXT はメインの working tree 側 (`docs/.dev-impl/`) に置く。この dir は `.gitignore` 済みで worktree 内には存在しないため、implementer と、implementer が起動する検査 subagent には**絶対パス**で渡す (相対パスでは worktree 内で解決できない)。

続けて各フェーズの**事前判定と観点 gating を親が確定する**。[phase-execution.md](./phase-execution.md) の `## 4.2: 事前判定` で `uiPhase` / `IS_NEOVIM_PLUGIN` を算出し、SKILL.md 4.2d の gating 表 (最終フェーズの定義は上記「Step 2」節) で起動すべきレビュー観点のリストを決めて、4p.3 の指示文に実値で埋め込む。implementer には gating の判断をさせない。

### 4p.3: implementer の fan-out (親)

wave (バッチ) 内の全フェーズ分の Agent 呼び出しを**同一メッセージ内の複数 tool_use** として並列起動する。各呼び出しは `model: sonnet` を明示し、guard / review subagent を自分で起動できるよう Agent ツールを持つ `general-purpose` を `subagent_type` に指定する。

指示文テンプレート (`<...>` を実値で埋める):

```text
あなたは dev-impl の implementer です。git worktree <worktree の絶対パス> の中だけで作業します。

## 事前に必ず Read するもの
- ~/.claude/rules/core/tdd.md / design.md / testing.md (親の hooks も CLAUDE.md も継承されないので、これを読まずに実装しない)
- <PHASE_CONTEXT の絶対パス> (フェーズのタスク・設計抜粋・関連ファイル・rules パス)

## 作業ディレクトリの制約 (最重要)
- **Bash の cwd は呼び出しごとにリセットされる。`cd` した状態は次の Bash 呼び出しに引き継がれない。**
  したがって全てのコマンドは `cd <worktree の絶対パス> && ...` で始めるか、git なら `git -C <worktree の絶対パス> ...`
  を使う。これを守らないと編集もコミットも親リポジトリ側に対して行われ、他の implementer と衝突する
- 編集してよいのは <worktree の絶対パス> 配下のソースのみ
  (特に docs/TODO.md・docs/DESIGN*.md・decisions.jsonl は親が管理するので触らない)
- Read は worktree 外も可 (rules・PHASE_CONTEXT は親側にある)
- 書き込みの例外: 検査 subagent の結果 JSON と攻撃スクリプト等の作業ファイルは <SCRATCH_DIR の絶対パス> 配下に書く
  (worktree 内に置くと squash merge で成果物に混入するため)
- ブランチ切替・rebase・親ブランチへの merge・push はしない
- 依存パッケージが未インストールならセットアップコマンド (npm ci 等) を worktree 内で実行してよい

## 手順
1. TDD (RED→GREEN→REFACTOR) で <phase_name> のタスクを実装する
2. フェーズのテストを Bash で実行し exit code 0 を確認する (自己申告ではなく実行結果で判定)
3. architecture-guard を起動する (model: haiku)。prompt には次を渡す:
     PHASE_CONTEXT の絶対パス / target_diff: phase:<phase_name> /
     repo_dir: <worktree の絶対パス> / output_path: <SCRATCH_DIR>/guard.json
   (repo_dir を渡さないと agent は自分の cwd = 親リポジトリを検査し、worktree の差分が空と判定されて
    無検出で通過する。output_path を明示しないと agent 側の固定デフォルトパスを他の implementer と
    共有して上書きし合う)。
   high/medium 違反があれば TDD で修正して再実行、3 回で残存なら失敗として報告する
4. <IS_NEOVIM_PLUGIN が true の場合のみ> fix-lsp-warnings を起動する (対象はフェーズ差分ファイルのみ)。
   失敗しても継続してよいが、警告が残ったまま進んだ場合は報告の verification_skipped に含める
5. レビューを起動する。観点は <gating で決まった観点リスト> で、
   同一メッセージ内の複数 tool_use として並列起動し、各呼び出しに model: opus を明示する。
   各 agent に repo_dir: <worktree の絶対パス> と phase_start_sha: <WAVE_BASE_SHA> を必ず渡す
   (repo_dir を落とすと guard と同じ理由でレビューが空差分を見て無検出通過する)。
   output_path は <SCRATCH_DIR>/review-<観点>.json とする
   (review-adversarial には PHASE_CONTEXT を渡さない。phase_name / phase_start_sha / repo_dir /
    docs_dir=<親リポジトリの docs 絶対パス。TODO.md は親だけが更新するため worktree 内の複製は使わない> /
    dev_server / scratch_dir / output_path のみ渡す)
6. severity: high の findings があれば worktree 内で TDD 修正 → gating 全観点を再レビュー。
   3 回でも残るなら失敗として報告する
   **例外: rule が test_weakened / skip_added の finding は自分で修正せず、実装を止めて即報告する**
   (テストの弱体化を実装者自身に直させると骨抜きの温床になるため、判定は親が行う)
7. テスト green かつ high 0 件 (上記例外を除く) になったら worktree の内容をコミットする。
   cwd リセットに備え必ず `-C` を使う:
     git -C <worktree の絶対パス> add -A
     git -C <worktree の絶対パス> commit -m "🔧 chore: [WIP] フェーズ<識別子> 実装"
   (メッセージは固定。親が squash 時に正式なメッセージを付け直す)

## 停止条件 (実装を続けずに即報告する)
- DESIGN.md の概要設計と矛盾する実装が必要になった (design_overview_break)
- test_weakened / skip_added の finding が出た (test_weakening_suspected)
- guard 3 回・レビュー 3 回でも違反が残る
- テストが 3 回試みても green にならない
- 検査 subagent が結果 JSON を返せない (エラー / JSON 解釈不能。パス扱いにしない)

## 報告 (必須)
作業結果は必ず SendMessage で親に送る。以下を含む JSON を本文にすること:
{
  "phase": "<識別子>",
  "status": "done|failed",
  "reason": "failed の場合のみ: design_overview_break | test_weakening_suspected |
             guard_loop_exceeded | review_loop_exceeded | tests_failing | agent_failed",
  "worktree_commit_sha": "worktree でのコミット SHA (done の場合)",
  "summary": "実装内容の 1-3 行要約",
  "review_outputs": ["<レビュー結果 JSON の絶対パス>", ...],   // 起動した観点の数だけ
  "guard_result": { "violations": 0, "loops": 1, "output_path": "<SCRATCH_DIR>/guard.json" },
  "review_loops": <レビュー self-fix の実施回数 (0-3)>,
  "working_tree_clean": <レビュー完了時点で worktree に想定外の未追跡汚染が無いか true/false>,
  "verification_skipped": [{ "target": "...", "reason": "..." }],
  "deviation_signals": [{ "type": "todo_minor|design_detail_gap|design_overview_break",
                          "scope": "...", "what": "...", "evidence": "..." }],
  "design_decisions": [{ "decision": "...", "spec_gap": "silent|ambiguous",
                         "alternatives": [{ "option": "...", "rejected_because": "..." }],
                         "rationale": "...", "affected_files": [...],
                         "related_design_section": "... または null" }],
  "open_questions": [{ "question": "...", "background": "...",
                       "suggested_action": "...", "affected_files": [...] }]
}
design_decisions / open_questions のフィールドは親が JSONL にそのまま転記するため、
検討していない項目も空配列 / null で必ず埋めること (欠けると HTML レポート生成が壊れる)。
```

`deviation_signals` は SKILL.md 4.2a と同じ分類 (設計と*矛盾する*変更) で、`design_decisions` (設計が沈黙・あいまいな箇所での自律判断) とは区別する。並列モードではこれが親の Step 4.6 (P1/P2/P3 判定) の唯一の入力になるため、implementer に必ず出力させる。

**review-adversarial のスキップ述語 (SKILL.md 4.2d) は並列モードでは評価せず、常に実行する** (フェーズが同時に進み互いの実装を見られない分、統合前の独立監査を差分規模に関わらず必須にする)。

fan-out 時に JSONL へ `event_type: impl_dispatch` (context に `phases` / `worktrees` / `wave_base_sha`) を記録する。

**implementer が応答しない場合**: SendMessage による報告が返らないまま `run_elapsed_minutes` が 30 分進んだフェーズは、打ち切って 4p.5 の逐次フォールバックに落とす (reason: `impl_failed`)。待ち続けても他フェーズの統合が進まないため。打ち切ったフェーズの worktree は 4p.5 の手順で削除する。

**報告受領時に JSONL へ `event_type: impl_report` (context に報告 JSON 全文 + `wave_base_sha` + `worktree_path`) を記録する**。エスカレ停止後の再入 (SKILL.md Step 0) で「worktree を取り込む」を選んだとき、親が 4p.4 の検証を再実行するにはこの報告が必要で、SendMessage の本文は再開時に復元できないため。

### 4p.4: 統合 (親、フェーズごとに逐次)

バッチ内の全 implementer の報告が揃ったら、TODO.md の出現順に 1 フェーズずつ統合する。**implementer の `status: "done"` を完了根拠にしない** — 以下を親が自分で検証する。

1. **報告の検証** (どれか 1 つでも満たさなければ 4p.5 のフォールバックへ)
   - `status: "failed"` でないこと。ただし `reason: "design_overview_break"` は**即エスカレ停止** (P3)。統合せず、wave の他フェーズの統合も行わない
   - `reason: "test_weakening_suspected"` の場合はフォールバックせず、親が該当 finding を読んで SKILL.md 4.2e と同じトレース確認 (TODO.md / DESIGN_DETAIL_APP.md に意図的な変更としてトレースできるか) を行う。トレース不能なら `test_weakening_detected` でエスカレ停止、トレース可能なら統合を続行する
   - **実装が実在すること**: `git log --oneline ${WAVE_BASE_SHA}..dev-impl/phase-${PHASE_ID}` が非空であること (何も実装せず `status: done` を返した場合、空 squash → 全テスト green → `- [x]` 化まで素通りしてしまう)
   - `review_outputs` の件数とファイル名が **4p.2 で gating した観点の集合と一致**し (観点を間引いても通過させないため)、各 JSON が実在して `agents/review-*.md` の出力スキーマ (`ok` / `dimension` / `findings[]`) を満たすこと (欠落・Read 不能・パース不能は「未検証」であり、逐次モードの `review_agent_failed` に相当する。high 0 件と同一視しない)
   - 各 JSON を親が Read し、severity: high の findings が 0 件であること
   - `working_tree_clean` が false なら親が `git status --porcelain` で worktree の汚染を確認し restore する (SKILL.md 4.2d ループ規則 7 の並列版)
   - severity: low/medium の findings は JSONL に `event_type: review_low` として記録する (逐次モードと同じくレポートのセクションに集約するため)

2. **squash merge**

   ```bash
   MERGE_BASE_SHA=$(git rev-parse HEAD)   # このフェーズの統合前 SHA (弱体化検知の diff 基準)
   git merge --squash dev-impl/phase-${PHASE_ID}
   git diff --cached --quiet && echo "EMPTY_SQUASH"   # 差分ゼロなら実装が入っていない → 手順 1 の検証漏れ
   ```

   コンフリクトが出たら親が解消を試みる (deps 宣言の誤りで並列にすべきでないフェーズが同時実行された可能性が高い)。JSONL に `event_type: merge_conflict` を記録し、解消できなければ差分を捨てて 4p.5 のフォールバックへ:

   ```bash
   git restore --staged --worktree .
   rm -f .git/SQUASH_MSG
   ```

   **`git merge --abort` は使わない** — squash merge は `.git/MERGE_HEAD` を作らないため、衝突後に実行しても `fatal: There is no merge to abort` で失敗し衝突状態も解消されない。`git restore --staged --worktree .` 単独で working tree がクリーンに戻る。

3. **テスト弱体化の機械検知**: [phase-execution.md](./phase-execution.md) の `## 4.2e: テスト弱体化検知コマンド` を、`${PHASE_START_SHA}` を `${MERGE_BASE_SHA}` に置き換えて実行する。ヒットしたら SKILL.md 4.2e と同じトレース確認を行い、トレース不能なら `test_weakening_detected` でエスカレ停止する

4. **全テストゲート**: 全テストスイートを Bash で実行し exit code 0 を確認する。フェーズ単体では green でも、他フェーズとの統合で壊れることがあるためここが本番。失敗したら**親が直営 TDD で修正**する (implementer には差し戻さない — 原因が複数フェーズの結合部にあるため)。3 回試みても緑にならなければ `tests_failing_before_commit` でエスカレ停止

5. **親の修正が入った場合の再レビュー**: 手順 1〜4 で親がコードを修正したら、その差分は implementer 側のレビュー (WAVE_BASE_SHA 基準) を通っていない。gating した全観点を親が `MERGE_BASE_SHA` 基準で再レビューし、fatal 0 件を確認してから次へ進む (SKILL.md 4.2d のループ規則をそのまま適用)

6. **コミット**: `rules/core/commit.md` に従い親がコミットする (commit-msg-guard hook はここで効く)。implementer の WIP コミットは squash されているので履歴には残らない

7. **状態更新**: TODO.md の該当フェーズを `- [x]` に更新し、JSONL に `event_type: impl_done` を記録する (context の `commit_sha` は**親の統合コミット SHA**。implementer の `worktree_commit_sha` とは別物)。implementer 報告の `design_decisions` / `open_questions` / `verification_skipped` は親が `event_type: design_decision` / `open_question` / `verification_skipped` として JSONL に転記する

8. **後片付け**

   ```bash
   git worktree remove --force ~/worktrees/${REPO_NAME}-phase-${PHASE_ID}
   git branch -D dev-impl/phase-${PHASE_ID}
   ```

   `--force` を付けるのは、implementer が入れた依存パッケージや生成物が worktree に未追跡で残っていると素の `remove` が `fatal: ... contains modified or untracked files` で失敗するため (`.gitignore` 済みのファイルだけなら素の remove でも成功するが、当てにしない)。順序も重要で、worktree を先に削除しないと `git branch -D` は `error: cannot delete branch ... used by worktree at ...` で失敗する。`SCRATCH_DIR` のレビュー JSON は worktree 外にあるので消えず、監査証跡として run のログディレクトリに残る。

9. **設計乖離の判定**: implementer 報告の `deviation_signals` を JSONL に転記した上で、SKILL.md Step 4.6 (P1 / P2 / P3 分類) を実行する。並列モードではこの転記が 4.6 の唯一の入力になる (逐次モードのように親が実装中に signals を観測できないため)。P2 で TODO.md を再生成する場合は、**バッチ内の残フェーズの統合をすべて終えてから**行う (再生成が統合待ちフェーズの見出しを書き換えると突合できなくなるため)。再生成後は Step 2 の wave 構築からやり直すが、**implementer が報告済みで未統合のフェーズは wave 再構築の対象から除外**し、既存 worktree の統合を先に完了させる (pending に戻すと worktree があるのに再実装してしまう)

### 4p.5: 逐次フォールバック

implementer の失敗・レビュー high 残存・マージ不能が起きたフェーズは、**並列を諦めて親が直営で実装し直す**。エスカレ停止するのは `design_overview_break` / `test_weakening_detected` / テストゲート 3 回不通過だけで、それ以外は停止せずここに落とす:

1. worktree とブランチを削除して差分を捨てる (中途半端な実装を引き継がない)。フォールバック対象は未コミット差分や失敗した実装を抱えているため、`--force` と削除順序が必須:

   ```bash
   git worktree remove --force ~/worktrees/${REPO_NAME}-phase-${PHASE_ID}
   git branch -D dev-impl/phase-${PHASE_ID}
   ```
2. JSONL に `event_type: parallel_fallback` を記録する。implementer 報告の `reason` は下表で `parallel_fallback.reason` に変換する

   | implementer の reason | parallel_fallback.reason |
   | --- | --- |
   | `guard_loop_exceeded` / `tests_failing` / `agent_failed` | `impl_failed` |
   | `review_loop_exceeded` / 親の検証で high 残存を確認 | `review_high_remaining` |
   | (マージ不能。implementer 報告に由来しない) | `merge_unresolvable` |

3. そのフェーズを SKILL.md の 4.1 / 4.1.5 / 4.2 / 4.6 (逐次モード) で親が最初から実装する。**着手はバッチ内の他フェーズの統合をすべて終えた後**にする (先に直営実装を挟むと後続フェーズの worktree base とコミット順がずれる)

`wave_fallbacks` が上限 (2 フェーズ / wave) を超えたら、以降の wave は並列モードを止めて全フェーズ逐次に切り替える (deps 宣言自体が信用できない状態のため)。JSONL に `event_type: parallel_disabled` (reason: `fallback_threshold`) を記録する。

## 状態管理の一元化

並列モードでも、以下は**親だけが読み書きする**。implementer には触らせない:

| 対象 | スコープ | 理由 |
| --- | --- | --- |
| `docs/TODO.md` のチェック更新 | run 全体 | 複数 implementer が同時に書くと lost update が起きる。統合時に親が更新する |
| decisions.jsonl / テキストログ | run 全体 | 追記競合を避ける。implementer の判断は報告経由で親が転記する |
| `p2_fixes_total` / `goal_loop` / `run_elapsed_minutes` | run 全体 | 発散上限のグローバル状態 |
| `p1_fixes_in_phase` | フェーズローカル (親が管理) | 各フェーズの統合時 (4p.4) にリセットする |
| `docs/.dev-impl/<run_id>/` の PHASE_CONTEXT | run 全体 | 親が組み立て、implementer は Read のみ |

implementer 内のループ回数 (guard 修正 / レビュー self-fix) は implementer に閉じ、上限超過は「失敗報告」として親に伝わる (親は報告の `guard_result.loops` / `review_loops` を `impl_done` に転記してレポートに残す)。

## エスカレ停止時の worktree の扱い

エスカレ停止する場合、**worktree とブランチは削除せず残す** (未統合の実装を消さないため)。停止理由が何であれ (`design_overview_break` / `test_weakening_detected` / `tests_failing_before_commit` のいずれでも)、**そのバッチの「統合済みフェーズ」と「未統合フェーズ」の一覧を JSONL (`event_type: p3_escalate` の context) と停止通知の両方に列挙する** — バッチが部分統合のまま止まるため、これが無いと再開時にどこまで進んだか判定できない。停止通知 ([notification-template.md](./notification-template.md) の `## エスカレ停止通知`) の「残存 worktree」欄に、worktree の絶対パス・ブランチ名・`SCRATCH_DIR` のレビュー JSON 置き場を書く。

再開時 (SKILL.md Step 0 の再入チェック) は `git worktree list` に `dev-impl/phase-*` が残っていれば前回 run の残骸として扱い、AskUserQuestion で「そのフェーズの実装として取り込む / 捨ててやり直す」を確認する。「取り込む」を選んだ場合は 4p.4 の統合手順から再開する — 検証に必要なレビュー結果 JSON は `~/.claude/logs/dev-impl/<前回の run_id>/reviews/phase-<識別子>/` に残っているので、親がそれを Read して手順 1 の検証を行う (前回の SendMessage 本文は復元できないため、報告 JSON でしか分からない項目 = `deviation_signals` / `design_decisions` 等は失われる。この場合は取り込んだ差分を親が読み直して 4.6 の判定を行う)。
