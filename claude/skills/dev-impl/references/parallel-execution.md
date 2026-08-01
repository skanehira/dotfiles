# 並列フェーズ実行の詳細手順 (dev-impl Step 2 / Step 4)

`dev-impl/SKILL.md` の Step 2 (フェーズ抽出 + wave 構築) と Step 4 (各フェーズの実行) から参照される、**wave サイズ 2 フェーズ以上のときだけ追加される手順**。

実行の骨格 (main が「PHASE_CONTEXT 組み立て → implementer 起動 → 待つ → 検査 fan-out → 待つ → 修正ラウンド → コミット」を回す) は逐次モードと同一で、SKILL.md の 4.1 / 4.1.5 / 4.2 / 4.6 が正。並列モードが変えるのは次の 3 点だけ:

1. implementer がフェーズごとの **git worktree** の中で作業する (main の working tree を共有しない)
2. implementer を **wave 内のフェーズ数だけ同時に起動**する
3. コミット前に **squash merge** が挟まる

判定条件・上限カウンタ・エスカレ条件は SKILL.md 本体にあるので、そちらを先に読んでから該当節をここで参照する。

用語:

| 用語 | 定義 |
| --- | --- |
| **wave** | 同時に着手できるフェーズの集合。TODO.md の `deps` 宣言をトポロジカルソートした 1 層分 |
| **識別子** | フェーズ見出しの `フェーズ` 直後からコロンまでの文字列 (`1` / `3` / `5-a`)。ブランチ名・worktree ディレクトリ名に埋め込むため半角英数字とハイフンのみ (定義は `../../dev-spec/references/todo-generation.md` の `#### フェーズ依存の宣言 (dev-impl の並列実行に使う)`) |
| **統合** | main が implementer の成果ブランチを squash merge し、全テストゲートを通してコミットするまでの一連の処理 |

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

wave 内のフェーズ数が `concurrent_implementers` の上限 (3 フェーズ) を超える場合は**バッチに分割**する。TODO.md の出現順で先頭 3 件ずつを 1 バッチとし、バッチ単位で「fan-out → 全 implementer の完了待ち → 検査 → 統合」を回す。上限 3 は「統合が逐次である以上、実装を増やしても統合待ちが伸びるだけ」という釣り合いから置いた既定値で、統合が軽いプロジェクトでは起動時に増やしてよい (変更したら JSONL の `batch_size` に反映される)。

**4p.1 以降はバッチ単位の手順**として実行する。`WAVE_BASE_SHA` はバッチ開始時に取り直す — wave 全体で 1 回しか取らないと、2 バッチ目の worktree が 1 バッチ目の統合コミットを含まない古い base から分岐し、不要なコンフリクトと古いコードでのテストを招く。

**dev_server を要するフェーズ (`uiPhase == true` かつ PHASE_CONTEXT の `dev_server` が非 null) は 1 バッチにつき 1 フェーズまで**とし、2 つ目以降は次のバッチに回す。同一 wave の複数フェーズが同じポートで dev サーバを起動すると衝突し、review-product-readiness が `dev_server_unavailable` の偽陽性を出して修正ラウンドが実装側で直しようのないエラーを再試行し続けるため。

**最終フェーズの定義** (review-quality / 全観点フルの起動条件、SKILL.md 4.2c) は逐次モードと同じく **TODO.md 上の最後のフェーズ**とする (最終 wave 全体ではない)。

## Step 4 (並列モード): wave の実行

SKILL.md の各節との対応:

| SKILL.md の節 | 並列モードでの実行箇所 |
| --- | --- |
| 4.1 (PHASE_START_SHA 記録) / run_elapsed_minutes 計算 | 4p.1 (バッチ開始時に 1 回。`WAVE_BASE_SHA` が全フェーズ共通の基準) |
| 4.1.5 (PHASE_CONTEXT 組み立て) / 4.2 事前判定 | 4p.2 (バッチ内の全フェーズ分を main が作る) |
| 4.2a (implementer 起動) | 4p.3 (バッチ内の全フェーズを同時起動) |
| 4.2b (LSP 警告修正) / 4.2c (検査 fan-out) / 4.2d (修正ラウンド) | 4p.4 (main が `repo_dir` = worktree で実行) |
| 4.2e (テスト弱体化検知 / テストゲート / コミット / RUN_FACTS 更新) | 4p.5 (main が統合時に実行) |
| 4.6 (設計乖離 P1/P2/P3 判定) | 4p.5 手順 7 |

### 4p.1: worktree の準備 (main)

バッチ開始時にまず JSONL へ `event_type: wave_start` (context に `wave_index` / `phases` / `batch_size`) を記録する。HTML レポートはこのイベントの有無で並列表示に切り替えるため、記録漏れは逐次表示への静かな劣化になる。あわせて `wave_fallbacks` を 0 にリセットする。

```bash
REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")
WAVE_BASE_SHA=$(git rev-parse HEAD)   # バッチ開始時点。このバッチの全 implementer の共通の親
mkdir -p ~/worktrees

# バッチ内の各フェーズについて (PHASE_ID には識別子を入れる。例: PHASE_ID=5-a)
PHASE_ID=<識別子>
git worktree add ~/worktrees/${REPO_NAME}-phase-${PHASE_ID} -b dev-impl/phase-${PHASE_ID} ${WAVE_BASE_SHA}

# 報告・検査結果の置き場 (worktree の外。squash merge の対象にならず、再入時も残る)
SCRATCH_DIR=~/.claude/logs/dev-impl/${run_id}/reviews/phase-${PHASE_ID}
mkdir -p "$SCRATCH_DIR"
```

- 置き場所を `~/worktrees/` 固定 + リポジトリ名 prefix にするのは、**別リポジトリで同時に dev-impl を回してもディレクトリ名が衝突しないため**。Agent ツールには組み込みの `isolation: "worktree"` があるが、置き場所を指定できず統合前に自動クリーンアップされうるので、統合を main が握る本フローでは手動管理する
- `SCRATCH_DIR` を worktree 外かつ run_id 配下に置くのは、(a) squash merge に検査成果物が混入しないため、(b) エスカレ停止後の再入時に main が同じ JSON を Read して統合を再開できるため
- **前回 run の残骸の扱いは SKILL.md Step 0 の再入チェックに一本化する**。Step 0 を通過した時点で「取り込む」と判断された worktree は残っている (4p.5 の統合手順から再開する) ので、ここでは作らない。それでも同名が存在する場合は**同一 run 内の再試行** (フォールバック後の作り直し等) なので掃除してから作り直してよい。掃除も下記「worktree 削除前チェック」を通す (`decision: discarded_stale`)
- 依存パッケージのインストール (`npm ci` / `bun install` / `go mod download` 等) は worktree ごとに必要。**実行は implementer に任せる** (プロジェクトごとにコマンドが違うため)
- **git 管理外だが実行に必須のファイル** (`.env` / ローカル設定 / DB fixture / `.direnv` 等) は worktree に存在しない。main の working tree に該当ファイルがあれば main が worktree へコピーし、何をコピーしたかを JSONL に記録する (コピーしないとセットアップやテストが実行できず、implementer が原因不明の失敗を報告する)
- `run_elapsed_minutes` はバッチ開始時と各フェーズの統合前に計算する。上限超過ならバッチに着手せずエスカレ停止する (逐次モードの 4.1 に相当する評価点がここになるので、省くと time budget が並列モードで一度も評価されない)。フェーズスコープのカウンタ (`p1_fixes_in_phase` / `phase_fix_round` / `test_gate_retry` / `phase_spawns`) は **4p.2 (PHASE_CONTEXT 組み立て時) にリセットする** — 4p.3 の implementer 起動より後にリセットすると、その 1 spawn が `phase_spawns` の予算に計上されない

### 4p.2: PHASE_CONTEXT と観点 gating の確定 (main)

バッチ内の各フェーズについて、SKILL.md Step 4.1.5 と [phase-context.md](./phase-context.md) に従って `docs/.dev-impl/<run_id>/phase-<識別子>-context.md` を Write する。並列モード固有の差分:

- `phase_start_sha`: `WAVE_BASE_SHA` を入れる (implementer の worktree はここから分岐しているため、worktree 内の `git diff ${WAVE_BASE_SHA}` がそのフェーズの差分になる)
- `prev_phase_summary`: wave 内の他フェーズはまだ実装されていないので参照できない。**バッチ開始時点で統合済みの最後のフェーズ**の summary (decisions.jsonl の直近 `impl_done`) を入れる
- `repo_state`: worktree は `WAVE_BASE_SHA` の複製なので、判定は main の working tree に対して行った結果をそのまま使ってよい

PHASE_CONTEXT と RUN_FACTS.md は main の working tree 側 (`docs/.dev-impl/`) に置く。この dir は `.gitignore` 済みで worktree 内には存在しないため、implementer と検査 subagent には**絶対パス**で渡す (相対パスでは worktree 内で解決できない)。

続けて各フェーズの**事前判定を main が確定する**。SKILL.md 4.2「事前判定」のコマンドで `uiPhase` / `IS_NEOVIM_PLUGIN` を算出する。

**観点 gating は 2 段階に分ける。** この時点ではフェーズの差分が存在しないため、差分ベースの述語を評価できないため:

| 判定する時点 | 決めること | 根拠 |
| --- | --- | --- |
| 4p.2 (implementer 起動前) | `uiPhase` による review-product-readiness の要否、`IS_NEOVIM_PLUGIN` による 4.2b の要否、最終フェーズかどうか (TODO.md 上の位置)、review-quality の追加起動 | いずれも差分を必要としない |
| 4p.4 (implementer 完了後) | review-tdd の起動 (`$TEST_FILE_CHANGED` / `$TEST_CONTENT_CHANGED`)、review-adversarial のスキップ述語 | 実装差分がないと算出できない |

review-quality の追加起動条件 `$CONSUMABLE_CHANGED` も本来は差分ベースだが、これだけは 4p.2 で判定する。**`phase_tasks` / `related_source_files` に消費型資源 (ローテーション有効な refresh token・nonce・ワンタイムコード・べき等キー・使い捨て署名 URL) を示す語が現れるか**で判定し、該当すれば review-quality を起動観点に加える (差分を見てから決めると、この種のコードを触るフェーズで観点が落ちる危険が大きいため、前倒しで広めに取る)。

**review-adversarial のスキップ述語は並列モードでは評価せず、常に実行する** (フェーズが同時に進み互いの実装を見られない分、統合前の独立監査を差分規模に関わらず必須にする)。

### 4p.3: implementer の fan-out (main)

バッチ内の全フェーズ分の `dev-impl-implementer` 呼び出しを**同一メッセージ内の複数 tool_use** として並列起動する。渡す値は逐次モード (SKILL.md 4.2a、テンプレートは [phase-execution.md](./phase-execution.md) の `## 4.2a: implementer の起動`) と同じで、並列固有の差分は次の 3 点だけ:

| 引数 | 並列モードでの値 |
| --- | --- |
| `repo_dir` | `~/worktrees/${REPO_NAME}-phase-${PHASE_ID}` の絶対パス |
| `report_path` | `${SCRATCH_DIR}/impl-report.json` |
| `worktree_commit` | `true` (テスト green 後に worktree 内で WIP コミットさせる。メッセージは agent 定義で固定) |

TDD の順序・cwd リセットへの対処・報告スキーマ・停止条件は `claude/agents/dev-impl-implementer.md` に常駐しているので指示文で繰り返さない。

fan-out 時に JSONL へ `event_type: impl_dispatch` (context に `phases` / `worktrees` / `wave_base_sha`) を、報告受領時に `event_type: impl_report` (context に要約 JSON + `wave_base_sha` + `worktree_path` + `report_path`) を記録する。**要約 JSON の記録は必須** — エスカレ停止後の再入 (SKILL.md Step 0) で「worktree を取り込む」を選んだとき、SendMessage の本文は復元できないため。

**implementer が応答しない場合**: 報告が返らないまま `run_elapsed_minutes` が 30 分進んだフェーズは、打ち切って 4p.6 の逐次フォールバックに落とす (reason: `impl_failed`)。待ち続けても他フェーズの統合が進まないため。

### 4p.4: 検査 (main、worktree に対して)

**バッチ内の全 implementer の報告が揃ってから**、フェーズごとに SKILL.md の 4.2b (LSP) → 4.2c (検査 fan-out) → 4.2d (fatal 判定と修正ラウンド) を実行する。逐次モードとの差分は次の 2 点だけ:

- 全 subagent の `repo_dir` に**そのフェーズの worktree の絶対パス**を渡す。`phase_start_sha` は `WAVE_BASE_SHA`
- 差分ベースの観点 gating (review-tdd の起動、review-adversarial のスキップ述語) をここで評価する (4p.2 の表を参照)。ただし review-adversarial は並列モードでは常に実行するので、実際に評価するのは review-tdd の起動条件だけ

複数フェーズの検査 fan-out を同時に走らせてよい (worktree が別なので互いに干渉しない)。ただし `phase_spawns` はフェーズごとに数える。

修正ラウンド (4.2d) の `dev-impl-implementer` (`mode: fix`) にも worktree の `repo_dir` を渡す。修正後は implementer に worktree 内で WIP コミットを追加させる。

`status: failed` の報告と検査結果の扱い:

| 状況 | 対処 |
| --- | --- |
| `reason: design_overview_break` | **即エスカレ停止** (P3)。統合せず、バッチの他フェーズの統合も行わない |
| `reason: test_weakening_suspected` | フォールバックせず、main が該当 finding を読んで SKILL.md 4.2e と同じトレース確認を行う。トレース不能なら `test_weakening_detected` でエスカレ停止、トレース可能なら統合を続行 |
| `phase_fix_exceeded` / `impl_failed` | 4p.6 の逐次フォールバックへ |
| 検査 agent が結果を返せない | `guard_agent_failed` / `review_agent_failed` でエスカレ停止 (high 0 件と同一視しない) |

### 4p.5: 統合 (main、フェーズごとに逐次)

検査を通ったフェーズを TODO.md の出現順に 1 つずつ統合する。

1. **実装が実在することの確認**: `git log --oneline ${WAVE_BASE_SHA}..dev-impl/phase-${PHASE_ID}` が非空であること (何も実装せず `status: done` を返した場合、空 squash → 全テスト green → `- [x]` 化まで素通りしてしまう)

2. **squash merge**

   ```bash
   MERGE_BASE_SHA=$(git rev-parse HEAD)   # このフェーズの統合前 SHA (弱体化検知の diff 基準)
   git merge --squash dev-impl/phase-${PHASE_ID}
   git diff --cached --quiet && echo "EMPTY_SQUASH"   # 差分ゼロなら実装が入っていない → 手順 1 の検証漏れ
   ```

   コンフリクトが出たら main が解消を試みる (deps 宣言の誤りで並列にすべきでないフェーズが同時実行された可能性が高い)。JSONL に `event_type: merge_conflict` を記録し、解消できなければ差分を捨てて 4p.6 のフォールバックへ:

   ```bash
   git restore --staged --worktree .
   rm -f .git/SQUASH_MSG
   ```

   **`git merge --abort` は使わない** — squash merge は `.git/MERGE_HEAD` を作らないため、衝突後に実行しても `fatal: There is no merge to abort` で失敗し衝突状態も解消されない。`git restore --staged --worktree .` 単独で working tree がクリーンに戻る。

3. **テスト弱体化の機械検知**: SKILL.md 4.2e の検知コマンドを、`${PHASE_START_SHA}` を `${MERGE_BASE_SHA}` に置き換えて実行する。ヒットしたら同じトレース確認を行い、トレース不能なら `test_weakening_detected` でエスカレ停止する

4. **全テストゲート**: SKILL.md 4.2e に従い main が `full_test_command` を実行する。フェーズ単体では green でも他フェーズとの統合で壊れることがあるためここが本番。失敗したら失敗出力を `${SCRATCH_DIR}/test-failure.json` に書き、`mode: fix` の `dev-impl-implementer` に**統合先 (main の working tree) を `repo_dir` として**渡して修正させる (worktree には差し戻さない — 原因が複数フェーズの結合部にあるため)。3 回試みても緑にならなければ `tests_failing_before_commit` でエスカレ停止

5. **統合時の修正が入った場合の再検査**: 手順 2〜4 でコードが変わったら、その差分は 4p.4 の検査 (WAVE_BASE_SHA 基準) を通っていない。gating した全観点 + architecture-guard を `MERGE_BASE_SHA` 基準・`repo_dir` = main の working tree で再 fan-out し、fatal 0 件を確認してから次へ進む

6. **コミットと状態更新**: SKILL.md 4.2e に従い main がコミットし、TODO.md の該当フェーズを `- [x]` に更新、RUN_FACTS.md を追記、JSONL に `event_type: impl_done` を記録する (context の `commit_sha` は**main の統合コミット SHA**。implementer の worktree コミットとは別物)。implementer 報告の `design_decisions` / `open_questions` / `verification_skipped` は `report_path` から `jq` で転記する

7. **設計乖離の判定**: implementer 報告の `deviation_signals` を転記した上で SKILL.md Step 4.6 を実行する。P2 で TODO.md を再生成する場合は、**バッチ内の残フェーズの統合をすべて終えてから**行う (再生成が統合待ちフェーズの見出しを書き換えると突合できなくなるため)。再生成後は Step 2 の wave 構築からやり直すが、**implementer が報告済みで未統合のフェーズは wave 再構築の対象から除外**し、既存 worktree の統合を先に完了させる (pending に戻すと worktree があるのに再実装してしまう)

8. **後片付け**: 下記「worktree 削除前チェック」を `decision` の判定つきで実行してから削除する。統合後のここで leftover が出たら、それは **implementer の `git add` 漏れ**であり、squash merge にも入っていない = そのまま消すと実装が失われる。`SCRATCH_DIR` の報告・検査 JSON は worktree 外にあるので消えず、監査証跡として run のログディレクトリに残る

### 4p.6: 逐次フォールバック

implementer の失敗・fatal 残存・マージ不能が起きたフェーズは、**並列を諦めて main の working tree で実装し直す**。エスカレ停止するのは `design_overview_break` / `test_weakening_detected` / テストゲート 3 回不通過だけで、それ以外は停止せずここに落とす:

1. worktree とブランチを削除して差分を捨てる (中途半端な実装を引き継がない)。下記「worktree 削除前チェック」を実行し、**捨てる内容を必ずログに残してから**削除する
2. `wave_fallbacks += 1` して JSONL に `event_type: parallel_fallback` を記録する (context に現在の `wave_fallbacks` を入れる)。reason は下表で変換する

   | 失敗の内容 | `parallel_fallback.reason` |
   | --- | --- |
   | implementer の `tests_failing` / `spec_insufficient` / 30 分無応答 | `impl_failed` |
   | `phase_fix_exceeded` (修正ラウンド 3 回でも fatal 残存) | `review_high_remaining` |
   | マージ不能 | `merge_unresolvable` |

3. そのフェーズを SKILL.md の 4.1 / 4.1.5 / 4.2 / 4.6 (逐次モード = `repo_dir` が main の working tree) でやり直す。**着手はバッチ内の他フェーズの統合をすべて終えた後**にする (先に挟むと後続フェーズの worktree base とコミット順がずれる)

`wave_fallbacks` が上限 (2 フェーズ / wave) を超えたら、以降の wave は並列モードを止めて全フェーズ逐次に切り替える (deps 宣言自体が信用できない状態のため)。JSONL に `event_type: parallel_disabled` (reason: `fallback_threshold`) を記録する。

## worktree 削除前チェック

worktree を削除する 3 箇所 (4p.1 の残骸掃除 / 4p.5 手順 8 の統合後削除 / 4p.6 手順 1 のフォールバック破棄) は、**必ずこの手順を通してから削除する**。無条件に `--force` で消すと、implementer が `git add` し忘れた実装ファイルを「ビルド生成物」と区別できずに失う。

```bash
WT=~/worktrees/${REPO_NAME}-phase-${PHASE_ID}
LEFTOVER=$(git -C "$WT" status --porcelain --untracked-files=all)
```

`--untracked-files=all` はディレクトリ単位でまとめず個々のファイルを出し、`.gitignore` 済みのものは出さない。つまり **`$LEFTOVER` に現れる = git が追跡すべきなのに未コミット = コミット漏れの候補**であり、`node_modules/` のような無視対象の生成物はここに出てこない (実測確認済み)。

### `$LEFTOVER` が空のとき

そのまま削除する。**`--force` は付けない**:

```bash
git worktree remove "$WT"
git branch -D dev-impl/phase-${PHASE_ID}
```

`.gitignore` 済みの生成物しか残っていない worktree は素の `remove` で成功する。あえて `--force` を使わないのは、チェックを飛ばしたり判定を誤ったりしても **git 自体が最後の安全網として削除を拒否する**ようにするため (`--force` を常用するとこの防御が効かなくなる)。削除順序は worktree → ブランチ。逆順だと `error: cannot delete branch ... used by worktree at ...` で失敗する。

### `$LEFTOVER` が非空のとき

まず一覧を 1 行テキストログと JSONL (`event_type: worktree_leftover`、context に `phase` / `files` / `decision`) に記録する。**沈黙して消さない**。その上で削除箇所ごとに次の分岐で処理する:

| 削除箇所 | 扱い | decision |
| --- | --- | --- |
| 4p.5 手順 8 (統合後) | 中身を main が確認する。**ソースファイル (実装・テスト) が含まれていれば implementer のコミット漏れ**なので、`git -C "$WT" add -A && git -C "$WT" commit` でコミットし直し、4p.5 手順 2 の squash merge からやり直して統合に含める (手順 3〜7 も再実行する) | `reintegrated` |
| 4p.5 手順 8 (上記の再統合後や生成物のみの場合) | 残るのが `.gitignore` 漏れの生成物だけなら、ファイル一覧をログに残して削除を続行する。`.gitignore` への追記は**このフェーズの実装にトレースできる場合のみ**行い、できなければ `open_question` として記録する (依頼スコープ外の設定変更を黙って入れない) | `discarded_artifacts` |
| 4p.6 手順 1 (フォールバック破棄) | 破棄は既定の動作。**捨てる内容の一覧をログに残してから**削除する | `discarded_fallback` |
| 4p.1 (同一 run 内の残骸掃除) | 同上。フォールバック後の作り直しなので捨ててよいが、記録は残す | `discarded_stale` |

`discarded_*` で実際に削除するときだけ `git worktree remove --force "$WT"` を使う (未コミット差分がある状態では素の `remove` は `fatal: ... contains modified or untracked files` で失敗するため)。「捨てると判断した記録が JSONL にあること」が `--force` を使う条件になる。

## 状態管理の一元化

並列モードでも、以下は**main だけが読み書きする**。implementer には触らせない:

| 対象 | スコープ | 理由 |
| --- | --- | --- |
| `docs/TODO.md` のチェック更新 | run 全体 | 複数フェーズが同時に進むため lost update が起きる。統合時に main が更新する |
| decisions.jsonl / テキストログ | run 全体 | 追記競合を避ける。implementer の判断は報告経由で main が転記する |
| `docs/.dev-impl/<run_id>/RUN_FACTS.md` | run 全体 | main が統合後に追記し、implementer は Read のみ |
| `p2_fixes_total` / `goal_loop` / `run_elapsed_minutes` / `run_spawns` | run 全体 | 発散上限のグローバル状態 |
| `p1_fixes_in_phase` / `phase_fix_round` / `phase_spawns` | フェーズローカル (main が管理) | 各フェーズの検査開始時 (4p.4) にリセットする |
| `docs/.dev-impl/<run_id>/` の PHASE_CONTEXT | run 全体 | main が組み立て、implementer は Read のみ |

## エスカレ停止時の worktree の扱い

エスカレ停止する場合、**worktree とブランチは削除せず残す** (未統合の実装を消さないため)。停止理由が何であれ、**そのバッチの「統合済みフェーズ」と「未統合フェーズ」の一覧を JSONL (`event_type: p3_escalate` の context) と停止通知の両方に列挙する** — バッチが部分統合のまま止まるため、これが無いと再開時にどこまで進んだか判定できない。停止通知 ([notification-template.md](./notification-template.md) の `## エスカレ停止通知`) の「残存 worktree」欄に、worktree の絶対パス・ブランチ名・`SCRATCH_DIR` の JSON 置き場を書く。

再開時 (SKILL.md Step 0 の再入チェック) は `git worktree list` に `dev-impl/phase-*` が残っていれば前回 run の残骸として扱い、AskUserQuestion で「そのフェーズの実装として取り込む / 捨ててやり直す」を確認する。「取り込む」を選んだ場合は 4p.4 の検査から再開する — implementer 報告の全文は `~/.claude/logs/dev-impl/<前回の run_id>/reviews/phase-<識別子>/impl-report.json` に、検査結果は同ディレクトリに残っているので、main がそれを Read して続きを行う。
