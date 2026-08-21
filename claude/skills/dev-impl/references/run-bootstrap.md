# dev-impl run ブートストラップ 参照

`dev-impl/SKILL.md` の Step 0 / Step 1 / Step 1.5 から参照される、run の起動・再入・前提確認の実行コマンド詳細。判断基準・分岐・停止条件は SKILL.md 本体にあるので、そちらを先に読んでから該当節だけをここで参照する。

## 目次

- [run スコープ変数と env.sh の生成](#run-スコープ変数と-envsh-の生成)
- [フェーズスコープ変数と専用ファイルの規律](#フェーズスコープ変数と専用ファイルの規律)
- [Step 0: 再入判定スクリプト](#step-0-再入判定スクリプト)
- [Step 0: カウンタ・予算・gating_decided の復元](#step-0-カウンタ予算gating_decided-の復元)
- [Step 0: 進行中フェーズと TODO の突合](#step-0-進行中フェーズと-todo-の突合)
- [Step 0: Step 5 系の停止からの再開](#step-0-step-5-系の停止からの再開)
- [Step 1: GitHub 前提条件の確認コマンド](#step-1-github-前提条件の確認コマンド)
- [Step 1: ゴール行の抽出と 1:1 照合](#step-1-ゴール行の抽出と-11-照合)

## run スコープ変数と env.sh の生成

**run スコープの変数は Step 0 の再入判定を済ませてから確定する** (再入なら `run_id` を引き継ぐので、先に発行すると捨てる羽目になる)。順序は「Step 0 で再入かどうかを決める → 下記を確定する → Step 1 へ」:

**シェル変数は Bash ツールの呼び出しをまたいで消える** (呼び出しごとに新しいシェルが立つ)。**run スコープの値はファイルに書き、以降の全ブロックの冒頭で `source` して再確立する**:

```bash
# --- 1 回だけ実行する (Step 0 の再入判定を済ませた直後) ---
# 再入なら run_id は $REENTRY_JSONL のディレクトリ名から取る (シェル変数は前回の起動から
# 引き継がれないので、run_id を「変数が残っている前提」で復元してはならない)
REENTRY_JSONL="$(cat "$HOME/.claude/logs/dev-impl/.reentry" 2>/dev/null)"   # Step 0 が書いたもの
if [ -n "$REENTRY_JSONL" ]; then
  run_id="$(basename "$(dirname "$REENTRY_JSONL")")"
else
  run_id="$(date '+%Y%m%d-%H%M%S')"              # ← = の周りに空白を置かない (置くとコマンド実行になる)
fi
RUN_DIR="$HOME/.claude/logs/dev-impl/$run_id"
mkdir -p "$RUN_DIR"

# **既にあれば作り直さない。** 作り直すと START_SHA が再入時点の HEAD で上書きされ、
# run 全体の開始 SHA (Step 5.2 の監査と Step 6 の完了サマリが使う) が失われる
if [ -f "$RUN_DIR/env.sh" ]; then
  . "$RUN_DIR/env.sh"
else
cat > "$RUN_DIR/env.sh" <<EOF
export run_id="$run_id"
export RUN_DIR="$RUN_DIR"
export JSONL="$RUN_DIR/decisions.jsonl"          # 構造化ログ
export LOG="\$HOME/.claude/logs/dev-impl.log"    # 1 行テキストログ (全 run 共通)
export REPO_DIR="$(git rev-parse --show-toplevel)"   # Step 1 の REPO_ROOT と同じ値。agent へはこの名前で渡す
export START_SHA="$(git rev-parse HEAD)"         # run 全体の開始 SHA (PHASE_START_SHA とは別スコープ)
export REPO_SLUG="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
export LIMIT=1000                                # gh issue list の取得上限 (Step 1)
EOF
. "$RUN_DIR/env.sh"
fi
mkdir -p "$(dirname "$HOME/.claude/logs/dev-impl.log")"
```

```bash
# --- 以降、Bash を呼ぶたびに冒頭でこれを実行する ---
. "$HOME/.claude/logs/dev-impl/<run_id>/env.sh"
```

## フェーズスコープ変数と専用ファイルの規律

**フェーズスコープの値** (`PHASE` / `PHASE_NAME` / `PHASE_START_SHA` / `SCRATCH_DIR` / `ISSUE`) も同じ理由で消えるので、**Step 4.1 で `$SCRATCH_DIR/env.sh` に書き、フェーズ内の各ブロックの冒頭で run スコープと合わせて `source` する**。**`ROUND` とカウンタは env.sh に書かない** — ラウンドごとに変わる値で、フェーズ開始時に 1 度書く env.sh の性質と合わない。`ROUND` は使うブロックの冒頭で **`## Step 0: カウンタ・予算・gating_decided の復元` と同じ式** (`fix_dispatch` 件数 + `context.round` が `retry*` の implementer `spawn` 件数 = `phase_fix_round` の現在値) から導出する。導出式をこの節に再定義しない — **正は同ファイルの `## Step 0: カウンタ・予算・gating_decided の復元`** である。カウンタは `spawn` イベントの件数から数え直す (logging.md)。

**「Agent の起動をまたいで比較する値」は env.sh ではなく専用のファイルに落とす** (env.sh はフェーズ開始時に 1 度書くもので、ラウンドごとに変わる値の置き場ではない)。該当するのは次の 3 つで、**いずれも「取った時点」と「使う時点」の間に必ず Agent の待ちが挟まる**:

(値と置き場の対応表は SKILL.md 本体の「進捗ログ (2 系統)」節にある。)

**読み出し側は「ファイルが無い」を沈黙で通さない。** `[ -f "$f" ] || { echo "起動前の値が残っていない。判定不能"; exit 1; }` を必ず置く — 無いまま進むと、たとえば「fix がテストに触れたか」の判定が `git diff` の失敗を経て 0 件 (= 触れていない) を返し、**reward hacking を守るためのゲートが沈黙して開く**。カウンタ (`PHASE_SPAWNS` / `RUN_SPAWNS`) は env.sh に書いた値ではなく **JSONL の `spawn` イベントの件数から数え直す** (logging.md が復元の正と定めている。ファイルの値は書き損ねると実態からずれるが、件数はイベントそのものから出る)。

**`$HOME` を使い、`~` を変数に入れない。** `~` はシェルの展開に依存するので、subagent への受け渡しや `jq --arg` を経由すると文字列 `~/...` のまま渡り、存在しないパスを指す。

## Step 0: 再入判定スクリプト

`~/.claude/logs/dev-impl/` の最新 run の decisions.jsonl を確認し、**同一プロジェクトで未完了の run** があれば再入モードで動く。判定は 2 条件の AND:

- `event_type: start` の `context.repo_root` が現在の `git rev-parse --show-toplevel` と一致する (このディレクトリは全プロジェクト共通なので、パスで絞らないと他プロジェクトの run を拾う)
- **run 完了イベント `run_done` が無い** (Step 6 の完了サマリ出力時に 1 件だけ記録する専用の event_type)


```bash
# 全 run を新しい順に走査し、「このリポジトリのもので run_done が無い」最初の 1 件を採る。
# **最新の 1 件だけを見てはならない** — このディレクトリは全プロジェクト共通なので、
# 他プロジェクトで dev-impl を回した直後は自分の未完了 run が最新ではなくなり、
# 新規 run として起動してカウンタ (goal_loop / run_spawns / p2_fixes_total) が 0 に戻る
ROOT="$(git rev-parse --show-toplevel)"
REENTRY_JSONL=""
for f in $(find "$HOME/.claude/logs/dev-impl" -maxdepth 2 -name decisions.jsonl -exec ls -1t {} +); do
  v=$(jq -sr --arg root "$ROOT" '
    (map(select(.event_type=="start" and .context.repo_root==$root)) | length) as $mine
    | (map(select(.event_type=="run_done")) | length) as $done
    | if $mine > 0 and $done == 0 then "reentry" else "fresh" end' "$f")
  [ "$v" = "reentry" ] && { REENTRY_JSONL="$f"; break; }
done
# **結果はファイルに落とす。** シェル変数は Bash 呼び出しをまたいで消えるので、
# 次のブロック (run スコープの確定) が $REENTRY_JSONL を読めない
printf '%s' "$REENTRY_JSONL" > "$HOME/.claude/logs/dev-impl/.reentry"
[ -n "$REENTRY_JSONL" ] && echo "reentry: $REENTRY_JSONL" || echo "fresh"
```

**センチネルに `done` を使わない。** `done` はステップ単位の完了にも使う値なので (logging.md)、run が完了していなくても途中のステップ完了で真になり、**「未完了である」ことを検出できない**。実測でも 1 つの未完了 run に `done` が 6 件記録されており、この判定は人手で中身を読んで補うしかなかった。`run_done` は run の完了時にしか書かれないので、仕掛ける前に**未完了の run に対してこの判定が `fresh` を返さないこと**を確認できる (陰性対照)。

## Step 0: カウンタ・予算・gating_decided の復元

**`ROUND` の導出式および `phase_fix_round` の復元式の正はこの節である。** SKILL.md 本体・logging.md は式を再定義せずここを指す。

1. **run_id とカウンタを引き継ぐ** (新規発行しない)。decisions.jsonl から `p2_fixes_total` / `goal_loop` / `run_spawns` の現在値と `run_spawns_budget` (記録済みの値の最大) を復元する — `goal_loop` / `run_spawns` は再実行のたびに 0 に戻ると発散上限 (Step 3) が実質無効化されるため、`p2_fixes_total` は上限こそ無いが run をまたいだ通算件数を Step 6 で提示するため、`run_spawns_budget` はこの復元値を下限として Step 1 で再計算するため。**進行中フェーズのカウンタも JSONL から復元する** — `phase_spawns` は当該 phase の `spawn` 件数、`phase_fix_round` は `fix_dispatch` 件数 + `context.round` が `retry*` の implementer `spawn` 件数 (報告不整合の再起動も 4.2a の表で `phase_fix_round` を進めるため)、`test_gate_retry` は **`context.agent` が `dev-impl-implementer`** かつ `context.round` が `tg*` の `spawn` 件数 (テストゲート再試行では fix がテストに触れると review-adversarial も同じ round ラベルで起動するので、agent で絞らないと二重に数える)、`p1_fixes_in_phase` は当該 phase の `p1_fix` 件数。**あわせて `phase_spawns_budget` / `phase_fix_budget` を当該 phase の `start` イベントの記録値の最大 (無ければ既定 33 / 3) として復元し、Step 3 の式で引き上げる。** カウンタだけ復元して予算を復元しないと、上限を超えた状態のカウンタだけが戻り、再入した瞬間に同じ理由で再停止する。**Step 4.1 のリセットは「その issue を初めて着手したとき」だけ**で、再入や reopen 経由の再着手では復元する (リセットしてしまうと、上限のあるカウンタが再入のたびに 0 に戻って発散上限が実質無効になる)。**進行中フェーズの `gating_decided` (最新の 1 件) も復元する** — 再 fan-out で起動してよい観点の唯一のソースなので、失うと記憶で判断することになる。当該フェーズの `gating_decided` が無ければ 4.2c の初回 fan-out からやり直す。

## Step 0: 進行中フェーズと TODO の突合

2. **進行中フェーズの突合**: ラウンドごとにコミットしているので (4.2a / 4.2d の「ラウンドごとのコミット」)、中断したフェーズは `PHASE_START_SHA` の上に積まれた `[phase-<識別子>]` prefix つきのコミット列として残り、working tree は通常 clean である。
   - 進行中フェーズの `PHASE_START_SHA` は decisions.jsonl の当該フェーズの `start` イベントの `context.phase_start_sha` から復元する
   - `git log --oneline <PHASE_START_SHA>..HEAD` で何が積まれているかを確認し、AskUserQuestion で「続きとして取り込む / 捨ててフェーズをやり直す」を確認する (再入時 1 回だけの人間確認)。各ラウンドが何をしたかは `~/.claude/logs/dev-impl/<前回の run_id>/reviews/phase-<識別子>/impl-report*.json` にも残っている
   - **捨てる場合は `git reset --hard <PHASE_START_SHA>`。** ただし打つ前に、`<PHASE_START_SHA>..HEAD` の全件が `[phase-<識別子>]` prefix を持つことを確認する。**エスカレ停止した run では HTML レポートのコミット (Step 7) が、P1/P2 の動的修正があった run では設計書のコミットが同じ範囲に混ざる**ので、無条件の reset はそれらも巻き戻す。prefix を持たないコミットがあれば、実装コミットだけを `git revert` するかユーザーに判断を仰ぐ
   - working tree が非クリーンなら、ラウンドのコミット前に落ちたか、検査 agent の汚染 (4.2d 手順 8) が残っている。`git status --porcelain` の中身も提示して同じ確認に含める
3. **TODO チェックの突合**: TODO.md で `- [x]` 化されているフェーズのうち、**対応する issue が open のまま**のものは「最終コミットまでは済んだが close まで到達していない」として扱う。**チェックは戻さず、フェーズもやり直さない。**

   **`impl_done` の SHA を基準にしない。** 4.2e はフェーズ最終コミット (手順 2) を打ってから `impl_done` (手順 5) を書くので、その間で落ちると「コミットは済んだが `impl_done` が無い」状態になり、SHA 基準の突合は完了しているフェーズを未完了と誤判定する。**issue の open/closed は 4.2e 手順 7 の close と対になっていて、`- [x]` と同じコミットに入る TODO.md の状態より後に動く**ので、「TODO は `[x]` だが issue が open」= 「最終コミットまでは済んだが close まで到達していない」を正しく表す。**4.2e の手順 3 (RUN_FACTS 更新) から再開する** — ただし**手順 5 (`impl_done`) と手順 6 (転記) は JSONL への追記なので、実行前に当該 phase の `impl_done` が既に無いかを `jq` で確認し、あればスキップする** (JSONL は append-only なので再実行すると重複エントリが入り、件数ベースの復元と集計が全部ずれる)。それ以外の手順 (RUN_FACTS は同内容なら差分なし、突合は読み取り、close は既 closed に冪等) はそのまま再実行してよい。**手順 7 から再開しない** — 手順 3〜6 が永久にスキップされ、RUN_FACTS の更新も実装ノートの転記も失われる。

   例外は `- [x]` が**未コミット** (working tree にだけある) の場合で、これはコミット前に落ちたことを意味するので `- [ ]` に戻してフェーズをやり直す。

   **issue が closed のフェーズも 1 点だけ確認する**: 当該 phase の `impl_done` はあるのに、その後の `deviation` の処理痕 (`p1_fix` / `p2_fix`、またはシグナル無しを示す次フェーズの `start`) が無ければ、**4.2e 手順 8 (親 sweep) と Step 4.6 の判定だけをやり直してから**次の issue へ進む (close 直後・4.6 前に落ちた場合、deviation_signals が未処理のまま失われるため。report は `$SCRATCH_DIR` に残っている)。

## Step 0: Step 5 系の停止からの再開

4. **Step 5 系の停止からの再開**: 前回が `goal_loop_exceeded` / `verification_tampered` / `acceptance_criteria_change` など**ゴール判定の段階で停止**していた場合、in-progress の issue は 1 件も無いので issue ラベルによる駐車が使えない。この場合は decisions.jsonl の最後の `p3_escalate` を提示し、**AskUserQuestion で「対応済み (再判定する) / まだ (中止する)」を確認する**。「対応済み」を選ばれたときだけ `goal_loop` を 0 に戻して Step 5.1 から再開する。**Claude の判断で戻さない** — 戻す条件が「人間の回答が入ったこと」であり、自動化すると `goal_loop` の上限が実質無効になる (needs-human ラベルを Claude が勝手に外さないのと同じ理由)

## Step 1: GitHub 前提条件の確認コマンド

**実装対象は GitHub issue** なので、docs の確認と同時に次を解決する。1 つでも失敗したらエスカレ停止し、「`/dev-spec` を先に実行して issue を作ってください」と案内する:


```bash
REPO_ROOT="$REPO_DIR"   # 「進捗ログ」で代入済み。両者は同じ値で、subagent へ渡すときは REPO_DIR の名前を使う
REPO_SLUG=$(gh repo view --json nameWithOwner -q .nameWithOwner)
NOT_UC='[.[] | select((.labels | map(.name) | index("uc-tracking")) | not)] | length'
LIMIT=1000   # 上限に張り付くと一部の issue が見えないまま「全件」を装うため、実運用の最大想定より大きく取る
OPEN=$(gh issue list --repo "$REPO_SLUG" --state open   --limit $LIMIT --json number,labels --jq "$NOT_UC")
CLOSED=$(gh issue list --repo "$REPO_SLUG" --state closed --limit $LIMIT --json number,labels --jq "$NOT_UC")

# 上限に達していないことを確認する (uc-tracking を含む生の件数で見る)
RAW=$(gh issue list --repo "$REPO_SLUG" --state all --limit $LIMIT --json number --jq 'length')
[ "$RAW" -lt "$LIMIT" ] || { echo "issue が $LIMIT 件の上限に達している。取得漏れの可能性があるため停止する"; exit 1; }
```

**構造ゲート (下記) を通過したら、`docs/.dev-impl/` が `.gitignore` にあることを確認し、無ければ追記して 1 度コミットする** (`🔧 chore: [STRUCTURAL] dev-impl の作業ファイルを ignore する`)。PHASE_CONTEXT と RUN_FACTS の置き場で、Step 4.1.5 が書き始める前に ignore されている必要がある。**Step 4 に入ってから追記すると `.gitignore` の変更自体がフェーズの差分に紛れ込み**、完了判定と検査 agent の差分に無関係なファイルが混ざる。

**`--limit` に張り付いていないことを必ず確認する。** 上限ちょうどの件数が返るのは「全部取れた」と「切り捨てられた」の両方でありえて、出力からは区別できない。切り捨てられたまま進むと、見えない issue が実装されないまま「全 issue 完了済み」と判定されうる。**本スキルで `gh issue list` を使う箇所 (Step 2 の一覧・4.2c の「最後の issue」判定・親 issue の sweep・紐付けの差集合) はすべて同じ `$LIMIT` を使い、同じ確認を通す。**

**`uc-tracking` ラベルの issue は数に入れない。** これは `/dev-spec` のフェーズ 12 が作るユースケース単位の**親 issue** であり、実装対象ではない (詳細は Step 2)。除外しないと、親が残っているだけで「まだ未完了の issue がある」と誤判定する。親 issue が 1 件も無いリポジトリ (フラット構造) でもこのフィルタは無害に通る。

`OPEN` が 0 で、かつ closed issue も 0 件なら **issue が未生成**である (`/dev-spec` のフェーズ 12 が走っていない)。`OPEN` が 0 で closed が 1 件以上なら**全 issue 完了済み**なので、Step 5 (ゴール達成判定) から再開する。

**続けて、親 issue がある構成なら「紐付けの差集合」を run ごとに 1 回流す** (手順は Step 4.6「新フェーズの issue 化」の同名ブロック)。前回の run が issue を作った直後・紐付け前に落ちると、その子は `ready` ラベルを持つので Step 2 が拾って実装・close するが、**親には永久に紐付かないまま完了してしまう** (4.2e の sweep からも見えないので、親が先に close される)。ここで 1 回回すことが、その取りこぼしを回収する唯一の経路である。

## Step 1: ゴール行の抽出と 1:1 照合

**ゴール行の抽出コマンド** (表のセルにコマンドを埋めない。**Markdown の表セルではパイプを `\|` にエスケープする必要があり、それがそのまま正規表現へ渡ると「リテラルのパイプ文字」を要求してしまう** — 実測で、ゴールが 13 行ある DESIGN.md に対して表セル形のコマンドは 0 件、エスケープを外すと 13 件を返した。以後この抽出が要る箇所は表からこのブロックを参照する):

```bash
GOAL_IDS=$(rg -o '^- ?(G[0-9]+|G_E2E):' -r '$1' docs/DESIGN.md | sort -u)
echo "$GOAL_IDS" | rg -c . || echo 0     # 0 なら goals_missing
```

**ゴール ↔ 検証手順の 1:1 の照合**も同じブロックで行う (欠落した ID をそのまま `verification_missing` の通知に載せる):

```bash
# --no-filename を必ず付ける。複数ファイルを渡すと rg は "<path>:<match>" を出力するため、
# 付け忘れると全 ID がファイル名込みになり comm が「全ゴールに検証手順が無い」と誤判定する
VERIFIED_IDS=$(rg --no-filename -o '^- ?(G[0-9]+|G_E2E) 検証' -r '$1' \
  docs/DESIGN_DETAIL_APP.md docs/DESIGN_DETAIL_INFRA.md | sort -u)
comm -23 <(echo "$GOAL_IDS") <(echo "$VERIFIED_IDS")    # 出力が空であること。非空 = 検証手順の無いゴール
```
