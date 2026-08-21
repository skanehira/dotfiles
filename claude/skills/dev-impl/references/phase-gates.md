# dev-impl フェーズ内ゲート 参照

`dev-impl/SKILL.md` の Step 4.2c / 4.2d / 4.2e から参照される、**main が Bash で直接実行する検証コマンド**の詳細。agent の起動方法と述語の算出は [phase-execution.md](./phase-execution.md) が持ち、こちらは「main 側が自分で確かめる」ゲートを集めている。判断基準・分岐・停止条件は SKILL.md 本体にあるので、そちらを先に読んでから該当節だけをここで参照する。

## 目次

- [4.2c: fan-out 前後の clean 確認](#42c-fan-out-前後の-clean-確認)
- [4.2c: 自己免除の抽出](#42c-自己免除の抽出)
- [4.2c: spawn の事前記録](#42c-spawn-の事前記録)
- [4.2c: 「最後の issue」の判定](#42c-最後の-issue-の判定)
- [4.2d 手順 3: fixer へ渡す findings の切り出し](#42d-手順-3-fixer-へ渡す-findings-の切り出し)
- [4.2d 手順 5: fix がテストに触れたかの判定](#42d-手順-5-fix-がテストに触れたかの判定)
- [4.2d 手順 8: 作業ツリーの汚染の検出と復元](#42d-手順-8-作業ツリーの汚染の検出と復元)
- [4.2e: 全体スイートのテストゲート](#42e-全体スイートのテストゲート)
- [4.2e: DoD ブロックの抽出と実行](#42e-dod-ブロックの抽出と実行)
- [4.2e 手順 3: RUN_FACTS.md の更新](#42e-手順-3-run_factsmd-の更新)
- [4.2e 手順 4: spawn 記録の突合](#42e-手順-4-spawn-記録の突合)

## 4.2c: fan-out 前後の clean 確認

**fan-out の直前に、作業ツリーが clean であることを確認する。初回だけでなく 4.2d の再 fan-out でも毎回行う**:

```bash
git -C "$REPO_DIR" status --porcelain    # 出力が空であること
```

非空なら**直前のラウンドのコミットが漏れている** (4.2a / 4.2b / 4.2d は implementer や fix-lsp-warnings の成果を受けるたびに main がコミットする → 「ラウンドごとのコミット」)。コミットしてから fan-out する。

**同じ「`status --porcelain` が非空」でも、観測する時点で意味が違う。** fan-out の**前**は自分のコミット漏れ (直前に動いたのは implementer なので、差分は実装)。fan-out の**後**は検査 agent の汚染 (4.2d 手順 8。直前に動いたのは検査 agent で、実装は既にコミット済み)。**処方が正反対 (前はコミットする / 後は `git restore` で捨てる) なので、取り違えると実装を捨てるか変異をコミットすることになる。** 判断は「いつ観測したか」で機械的に決まるので、迷ったら直前に何が動いたかを見る。**実装がコミット済みであることは、この後の 3 つが成り立つ前提になっている**:

- 全 agent の `git diff <PHASE_START_SHA>` が新規ファイルも含めて同じ差分を返す (`git diff` は未追跡ファイルを一切見ないので、コミットしていないと新規実装だけのフェーズが全 agent に空差分として見える)
- 検査 agent がソースを書き換えたまま戻さなかった場合、clean なツリー上の変更として `git status --porcelain` に現れる (フェーズの差分が未コミットのまま並んでいると、既に「変更済み」の行しか出ないので中身の書き換えを検出できない)
- 中断したフェーズの破棄が `git reset --hard <PHASE_START_SHA>` で済む (Step 0)

**全観点の結果を受け取ったら、同じコマンドで汚染の突合を行う** (agent の `working_tree_polluted` 報告の有無に関わらず必ず実行する)。

```bash
git -C "$REPO_DIR" status --porcelain    # 出力が空であること
```

fan-out の直前に clean を確認しているので、ここで非空なら**検査 agent が書き換えたまま戻していない**。差分が出たら 4.2d 手順 8 に従う。

## 4.2c: 自己免除の抽出

**続けて、implementer の自己免除を抽出して検査 agent へ渡す** (実装者が「検証しない」と宣言した項目は、記録するだけでは誰も裁定しない。実測で修正ラウンド後半の fatal 2 件がいずれも初回に宣言された自己免除に起因していた):

**抽出元は当該フェーズの全 report (`impl-report.json` と `impl-report-fix-*.json`) であり、最新の 1 本ではない。** 免除は宣言されたラウンド以降ずっと有効なままだが、実装者が後続ラウンドの report で再掲するとは限らない (実測: 最も危険だった受容は初回 report、等価変異の宣言は 2 回目の fix report にあり、最終ラウンドの report にはどちらも現れなかった。最新 1 本だけを見ると両方取りこぼす)。

```bash
# glob をシェルに展開させない。初回 fan-out の時点では fix report が 1 件も無く、
# 未展開の glob をそのまま jq に渡すと「ファイルが無い」で落ちるか、出力ファイルが作られない
find "$SCRATCH_DIR" -maxdepth 1 -name 'impl-report*.json' -print0 \
  | xargs -0 -r jq -s -c '
      [ .[]
        | (.design_decisions[]?
            | select((.decision + " " + (.rationale // "")) | test("受容|残余リスク|許容|トレードオフ"))
            | {kind:"accepted_risk", claim:.decision, rationale:.rationale, source:"design_decisions"}),
          (.verification_skipped[]?
            | {kind:(if ((.reason // "") | test("等価変異|equivalent")) then "equivalent_mutation" else "verification_skipped" end),
               claim:.target, rationale:.reason, source:"verification_skipped"}) ]
      | unique_by(.claim)' > "$SCRATCH_DIR/self-exemptions.json"

# 抽出が成立したかを先に判定する。**失敗と「免除 0 件」を同じ [] に潰さない** —
# 潰すと、後段の裁定チェック (4.2d 手順 1: 渡した件数より adjudicated が少なければ未検証) が
# 常に 0 件と比較することになり、自分で自分を無効化する
if ! jq -e 'type == "array"' "$SCRATCH_DIR/self-exemptions.json" >/dev/null 2>&1; then
  if [ -z "$(find "$SCRATCH_DIR" -maxdepth 1 -name 'impl-report*.json' -print -quit)" ]; then
    echo "impl-report が 1 件も無い → impl_report_invalid として 4.2a の表に従う"; exit 1
  fi
  echo "自己免除の抽出に失敗した (report はあるが jq が配列を返さなかった) → exemptions_extract_failed で停止する"; exit 1
fi
EXEMPTIONS_COUNT=$(jq 'length' "$SCRATCH_DIR/self-exemptions.json")
```

**`EXEMPTIONS_COUNT` が 1 以上なのに review-tdd と review-adversarial のどちらも起動しないフェーズでは、免除が誰にも裁定されないまま通過する。** その場合は `verification_skipped` (source: `exemptions_unadjudicated`、context に免除の `claim` 一覧) を記録し、Step 5.6 の集約に載せる (沈黙させない)。

出力が `[]` でも**ファイルは必ず作り、`exemptions_path` として review-tdd と review-adversarial に渡す** (免除が無かったことと、渡し忘れたことを区別できるようにする)。**`EXEMPTIONS_COUNT` は控えるのではなく、使う直前に `jq 'length' "$SCRATCH_DIR/self-exemptions.json"` で取り直す** (シェル変数は Bash 呼び出しをまたぐと消えるが、ファイルは残るため)。結果を受け取ったとき、射影の `adjudicated` がこれを下回っていれば裁定が実行されていないので未検証として扱う (4.2d 手順 1)。**review-adversarial に渡しても fresh context 監査の趣旨は壊れない** — 渡すのは実装者が編纂した実装の説明ではなく「検証しないと宣言した項目の名指しリスト」であり、被監査者の主張をそのまま信じる材料ではなく攻撃対象の指定になるため。受け側の裁定手順は `claude/agents/review-*.md` の `Step 0: 自己免除の裁定`。

再 fan-out のたびに作り直す (追記ではなく上書き。前ラウンドで裁定済みのものは受け側が `upheld` として再掲する)。**作り直したら前ラウンドの内容と `claim` の差分を取り、新規の免除が 1 件でもあれば、再 fan-out の観点に review-adversarial (`mode: weakening_only` で足りる) を必ず含める** — 修正ラウンドで新たに宣言された免除は、そのラウンドの再検査対象に adversarial / tdd が居なければ誰にも裁かれないまま通ってしまう (裁定ゲートの意味が最終ラウンドの宣言にだけ効かなくなる)。

## 4.2c: spawn の事前記録

**続けて、この fan-out で起動する agent の `spawn` を JSONL に先に書く。記録は「起動した後」ではなく、この事前ブロックの中で行う。** 起動後に書く規定だと、待ちに入る直前の・前進を生まないログ 1 行だけが構造的に落ちる。実測: 初回 fan-out は同じブロックで `gating_decided` を書く必要があるため記録が残ったが、**再 fan-out には他に書く理由が無く記録が落ちた**。ある run の 5 フェーズで、architecture-guard の spawn 記録は実行回数に対し 1/1・2/4・1/4・4/4・0/7 件だった (修正ラウンドを多く回したフェーズほど欠落が大きい)。別のフェーズでは全 agent 合計 16 回のうち 8 件が欠落していた。`run_spawns` の予算ゲートはこの記録を唯一のソースにしているので、欠けると上限判定が実態より小さい値で走る。起動する agent 集合はこのブロックの時点で確定しているため先に書いても内容は正確で、起動が失敗した場合は別途 `guard_agent_failed` / `review_agent_failed` が記録されるので実態と食い違ったままにはならない。

## 4.2c: 「最後の issue」の判定

**「最後の issue」とは、その issue を close した時点で他に open issue が 1 件も残らないもの**を指す (issue 駆動では着手順を番号昇順で決めるだけなので、着手前に「最後かどうか」は分からない。検査 fan-out を起動する 4.2c の時点で次を引き、自分以外に open が無ければ最後と判定する)。**`uc-tracking` (親 issue) は数に入れない** — 親は実装対象ではないので、残っていても「最後のフェーズ」であることは変わらない:

```bash
gh issue list --repo "$REPO_SLUG" --state open --limit $LIMIT --json number,labels \
  --jq '[.[] | select((.labels | map(.name) | index("uc-tracking")) | not)] | length'
```

この時点では自分自身がまだ open なので、**出力が `1` (自分だけ) なら最後の issue**である。`0` と比較しない。

## 4.2d 手順 3: fixer へ渡す findings の切り出し

   続けて、fixer に渡す findings ファイルを**観点ごとに 1 本ずつ** `jq` で作る (main は findings 本文を読まず、`jq` の出力をファイルへ直行させる):

   ```bash
   # fatal を出した観点の findings を渡す。ただし手順 7 の 4 rule は除く
   #   (実装者に直させない規定なので、渡すと必ず test_weakening_suspected で停止して 1 ラウンド無駄になる)。
   #   review-* は high だけを渡す (medium は implementer が直さない規約なので渡しても no-op = 4.2d 手順 2)
   jq '{ok, dimension, mode, findings: [.findings[]
        | select((.rule | test("^(test_weakened|vacuous_assertion|skip_added|tautological_test)$")) | not)
        | select(.severity=="high")]}' \
     "$SCRATCH_DIR/review-<観点>-r${ROUND}.json" > "$SCRATCH_DIR/fatal-<観点>-r${ROUND}.json"

   # fatal を出していない観点の medium は **fixer に渡さない**。implementer は review-* の
   # findings[] を high しか直さない規約 (claude/agents/dev-impl-implementer.md) なので、
   # 渡しても構造的に no-op になり、spawn 予算だけを消費する。medium は review_low に記録して残す
   ```

   architecture-guard の分は**キーを `violations` のまま出す** (`jq '{ok, violations: [.violations[] | select(.severity=="high" or .severity=="medium")]}'`)。`findings` に付け替えてはならない — implementer は `violations[]` を high/medium、`findings[]` を high だけ拾う規約なので (`claude/agents/dev-impl-implementer.md`)、付け替えると **guard の medium が誰にも直されず毎ラウンド再検出される**。**これらのファイルの生成者はこの手順だけ**で、4.2e 手順 4 の突合はこれらを spawn の成果物として数えない (main が書いたものなので)

## 4.2d 手順 5: fix がテストに触れたかの判定

   - **fix がテストに触れた場合は review-adversarial を必ず追加する** (`mode: weakening_only` で足りる)。判定は**その fix のコミット差分にテストファイルが含まれるか**を見るだけでよい (ラウンドごとにコミットしているので、fix 差分を切り出す SHA が存在する):

     ```bash
     # fix 起動の直前に控えた SHA と比較する。HEAD~1 を使わない —
     # (a) fix の差分が空でコミットが打たれなかった場合、HEAD~1..HEAD は 1 つ前のラウンドを指して誤判定する
     # (b) そのコミットがリポジトリの最初のコミットだと HEAD~1 が解決できずコマンド自体が失敗する
     # mode: fix を起動する直前にファイルへ落とす (シェル変数は Agent の待ちをまたぐと消える)
     git -C "$REPO_DIR" rev-parse HEAD > "$SCRATCH_DIR/before-$ROUND.sha"
     # ... fix の完了とコミット ...
     if [ ! -f "$SCRATCH_DIR/before-$ROUND.sha" ]; then
       # 規則 (「進捗ログ」節): ファイルの不在を沈黙で通さない。判定不能は「触れていない」ではない
       echo "起動前の SHA が残っていない。テスト接触は判定不能 — 安全側に倒し review-adversarial (mode: weakening_only 以上) を必ず起動する"
     else
       BEFORE_FIX=$(cat "$SCRATCH_DIR/before-$ROUND.sha")
       if [ "$BEFORE_FIX" = "$(git -C "$REPO_DIR" rev-parse HEAD)" ]; then
         echo "fix はコミットを生まなかった (差分なし)。テストには触れていない"
       else
         git -C "$REPO_DIR" diff --name-only "$BEFORE_FIX" HEAD \
           | rg '(_test\.(go|rs|py)|\.test\.|\.spec\.|_spec\.|__tests__/|(^|/)tests?/|(^|/)test_[^/]*\.py)'
       fi
     fi
     ```

     Rust のインラインテスト (`#[cfg(test)]`) はこのファイル名パターンで捕まらないので、Rust プロジェクトでは同じ差分に対して `git -C "$REPO_DIR" diff -U0 "$BEFORE_FIX" HEAD -- '*.rs' | rg '^\+.*#\[cfg\(test\)\]'` も見る (`HEAD~1` を使わない理由は上と同じ)。修正の過程でテストが弱体化されるのはレンズ B が守る対象そのもので、ここに穴を作らない。既に adversarial が `full` で起動していたフェーズでは `full` のまま再実行する

## 4.2d 手順 8: 作業ツリーの汚染の検出と復元

8. **作業ツリーの汚染は、agent の自己申告ではなく main が検出する** (4.2c の検査後ブロック)。`working_tree_polluted` の報告が無くても必ず `git status --porcelain` で突合する。実装はラウンドごとにコミット済みで fan-out 直前のツリーは clean なので、**検査 agent が書き換えたまま戻さなければ必ず変更として現れる**。

   **この検出が捕まえるのは「戻し忘れた汚染」だけである。** 攻撃の途中で変異させ、検査を終える前に正しく戻した場合は `status` が clean に戻るので検出できない — その間に別の観点が変異後のコードを読んでいても分からない。この一過性の窓を構造的に閉じるのが「変異を伴う観点と実行環境を共有する観点を同じ fan-out に入れない」規定 (下記) で、検出はあくまで二重の歯止めである。

   差分が出たら `git restore <該当ファイル>` で直前のコミットの状態に戻す。**実装は既に履歴に入っているので、この復元で失われるのは agent が加えた変異だけである** (フェーズ中に何もコミットしない設計では、実装と変異が同じ未コミット差分に混ざるため機械復元ができなかった)。復元したら JSONL に `working_tree_polluted` を記録する。

   **汚染を検出したラウンドの検査結果は fatal の有無に関わらず全て破棄し、同じ観点で 1 回やり直す。** 並列に走った他の観点が変異後のコードを読んでいた可能性があり、そのラウンドの結果は「fatal なし」も「fatal あり」も信用できない — 前者をそのまま通せば検査していないコードをコミットへ通すことになり、後者をそのまま修正ラウンドへ載せれば**変異が原因の偽の fatal を実装者に直させる**ことになる (実在しない不具合を追わせるので必ず空回りする)。やり直しの spawn は `phase_spawns` に計上するが `phase_fix_round` は進めない (修正ラウンドではないため)。**同一フェーズで 2 回目の汚染を検出したらエスカレ停止する** (`working_tree_polluted`。並列実行と変異が構造的に噛み合っていない状態なので、3 回目を試す価値が無い)

## 4.2e: 全体スイートのテストゲート

コミット前に **main が `full_test_command` を Bash で直接実行し、exit code 0 を確認する** (自己申告ではなく実行結果で判定)。implementer にはフェーズスコープのテストしか実行させていないので、全体スイートの実行はここが初回になる。

全体スイートを main が実行する理由は、main の cache write が 1 時間 TTL で長時間の実行に耐えるため (subagent は 5 分 TTL なので、長いスイートを subagent 内で回すと自分のコンテキストを失効させる)。ただし **Bash の 600 秒上限は主体によらず効く** (実測: `swift test` が 608〜614 秒で上限に張り付いた事例が失効 29 件の主因)。`full_test_command` が 600 秒を超えるプロジェクトでは `run_in_background: true` で起動してポーリングする。**タイムアウトした実行は「未検証」として `verification_skipped` に記録し、成功扱いにしない**。

- 失敗 → `test_gate_retry += 1` し、失敗出力 (末尾 30 行) を 4.2a の「fix ブリーフ」と同じスキーマで `<SCRATCH_DIR>/test-failure-<test_gate_retry>.json` に書いて `mode: fix` の implementer に渡す (main は実装差分を読まない)。`test_gate_retry > 3` で `tests_failing_before_commit` でエスカレ停止。**`test_gate_retry` は `phase_fix_round` とは別カウンタ**にする (検査ラウンドを使い切ったフェーズでもテストゲートの再試行が残るように)。この経路の implementer 起動も**通常のラウンドと同じ扱い**にする:
  - `report_path` は `<SCRATCH_DIR>/impl-report-testgate-<test_gate_retry>.json` (修正ラウンドの `impl-report-fix-<round>.json` と衝突させない。カウンタが別なので番号が重なる)。**`spawn` 記録の `context.round` には文字列 `"tg<test_gate_retry>"` を入れる** (4.2e 手順 4 の突合が成果物のファイル名と 1:1 で対応するようにするため)
  - `model` は `test_gate_retry` が 1 なら `opus`、2 以降は `fable` (「修正ラウンドのモデル昇格」と同じ考え方)
  - 起動の直前に `spawn` を記録し、**報告を受けたら「ラウンドごとのコミット」に従ってコミットする** (コミットしないと作業ツリーが非クリーンなまま次の手順へ進み、4.2c の clean 前提と 4.2d 手順 8 の汚染検知がどちらも壊れる)
  - fix がテストに触れた場合は、修正ラウンドと同じく review-adversarial (`mode: weakening_only` 以上) を 1 回起動してから最終コミットへ進む

## 4.2e: DoD ブロックの抽出と実行

続けて **issue 本文の `## DoD` ブロックを実行する**。全体スイートが緑でも、その issue 固有の受入基準は別に確認しなければならない (`## DoD` は dev-spec のフェーズ 10 が著作し、フェーズ 10.5 の監査が実行可能性まで検査した唯一の issue 単位の受入基準であり、ここで実行しないと誰も実行しない):

```bash
# CRLF を落としてから抽出する。GitHub の Web 画面で編集された issue 本文は CRLF になり、
# 行末の \r のせいで `/^## DoD$/` が一致せず、抽出が丸ごと空振りする
gh issue view "$ISSUE" --repo "$REPO_SLUG" --json body -q .body | tr -d '\r' > "$SCRATCH_DIR/issue-body.md"
awk '/^## DoD$/{f=1;next} /^## /{f=0} f' "$SCRATCH_DIR/issue-body.md" > "$SCRATCH_DIR/dod.md"
# フェンスの言語指定は bash 以外 (sh / shell / console) も許容する
awk '/^```(bash|sh|shell|console)$/{f=1;next} /^```$/{f=0} f' "$SCRATCH_DIR/dod.md" > "$SCRATCH_DIR/dod.sh"

# **抽出が空でないことを先に確認する。** 空の dod.sh に対する `bash -e` は必ず exit 0 を返すので、
# これが無いと「1 件も実行していない」が「全通過」と区別できない (陽性対照の無い検査になる)。
# コメント行と空行を除いて数える (非空白行を数えるだけだと `# 期待: exit 0` のような
# コメントしか無いブロックが「1 件ある」と読めてしまう)
DOD_CMDS=$(rg -v '^\s*(#|$)' "$SCRATCH_DIR/dod.sh" | rg -c '\S' || echo 0)
echo "DoD の自動コマンド数: $DOD_CMDS"
bash -e "$SCRATCH_DIR/dod.sh"   # 期待: exit 0
```

**`DOD_CMDS` が 0 のときは通過扱いにしない。** issue 本文に自動系の DoD が本当に無い (手動系だけ) のか、抽出が空振りしたのかを区別できないため、`verification_skipped` (source: `dod_no_automated`) を記録し、**close コメントから「DoD がすべて通過した」の文言を外して手動確認待ちとして Step 6 のサマリに載せる**。`DOD_CMDS` は close コメントにも書き、「0 件」と「N 件成功」が後から区別できるようにする。

`DoD (手動):` の行は実行できないので、**その本文をそのまま Step 6 のサマリに残して人間に確認を求める** (自動系がすべて通っていれば実装は前進しているので、手動系の存在自体を停止理由にしない)。

自動系が失敗したら `test_gate_retry` と同じ再試行経路に載せる (失敗出力を `mode: fix` の implementer に渡す)。**close コメントで「DoD がすべて通過した」と書けるのは、このブロックが exit 0 になったときだけである。**

## 4.2e 手順 3: RUN_FACTS.md の更新

3. **RUN_FACTS.md を更新する** (書式と規則は [references/phase-context.md](./references/phase-context.md) の `## RUN_FACTS.md`)。implementer 報告の `report_path` から `jq` で引いて「完了フェーズの成果物」「累積 design_decisions」「既知の落とし穴」に追記する。**この更新がフェーズ間の文脈再注入を代替する**ので省略しない (省略すると次フェーズの implementer がプロジェクトの作り方を探索し直す)。追記後にファイルサイズを測り、**4096 バイトを超えていたら最新 3 フェーズ以外の「完了フェーズの成果物」行を要約に畳む**。JSONL に `event_type: run_facts_updated` (context に `sections` / `bytes`) を記録する

## 4.2e 手順 4: spawn 記録の突合

4. **`impl_done` を書く前に spawn 記録を突合する。** 当該フェーズの `event_type: spawn` の件数と、`$SCRATCH_DIR` にある検査結果 JSON の本数 + implementer 報告 (`impl-report*.json`) の本数を突き合わせ、食い違ったら不足分を補記する (`context.backfilled: true` を付ける)。予算ゲートの前提を、フェーズを閉じる時点で 1 回だけ機械的に復元する:

   ```bash
   # 記録された spawn を「agent 名 + ラウンド」の集合として取る
   jq -r --arg p "$PHASE" 'select(.event_type=="spawn" and .phase==$p)
     | "\(.context.agent)-r\(.context.round // 0)"' "$JSONL" | sort -u > "$SCRATCH_DIR/_spawn-recorded.txt"

   # 実際に残った成果物を同じ形の集合にする。**ファイル名はラウンド番号を含む** (guard-r0.json 等)
   # ので、修正ラウンドを回しても上書きで潰れず、起動回数と 1:1 で対応する。
   # 変換先は JSONL の context.agent と同じ綴りに揃える (guard → architecture-guard、
   # impl-report → dev-impl-implementer)。揃えないと差集合が全件ずれる
   # zsh は未マッチの glob を NOMATCH エラーにし `2>/dev/null` では抑止できないので、
   # ls + glob ではなく find を使う (4.2c の self-exemptions 抽出と同じ形)
   { find "$SCRATCH_DIR" -maxdepth 1 -name 'guard-r*.json' \
       | sed 's|.*/||; s|\.json$||; s|^guard-|architecture-guard-|';
     find "$SCRATCH_DIR" -maxdepth 1 -name 'review-*-r*.json' \
       | sed 's|.*/||; s|\.json$||';
     find "$SCRATCH_DIR" -maxdepth 1 -name 'impl-report*.json' \
       | sed 's|.*/||; s|\.json$||;
              s|^impl-report$|dev-impl-implementer-r0|;
              s|^impl-report-fix-|dev-impl-implementer-r|;
              s|^impl-report-testgate-|dev-impl-implementer-rtg|;
              s|^impl-report-retry-|dev-impl-implementer-rretry|'
   } | sort -u > "$SCRATCH_DIR/_spawn-actual.txt"

   echo "--- 記録はあるが成果物が無い (起動に失敗したか、記録が過剰) ---"
   # fix-lsp-warnings と tech-investigation は結果 JSON を出さない仕様なので、記録側から除いて突合する
   comm -23 "$SCRATCH_DIR/_spawn-recorded.txt" "$SCRATCH_DIR/_spawn-actual.txt" | rg -v '^(fix-lsp-warnings|tech-investigation)-'
   echo "--- 成果物はあるが記録が無い (記録漏れ。補記する) ---"
   comm -13 "$SCRATCH_DIR/_spawn-recorded.txt" "$SCRATCH_DIR/_spawn-actual.txt"
   ```

   **件数ではなく集合の差で見る。** 件数比較だと過剰と不足が相殺して一致してしまい、両方見逃す。差集合なら**どちらの向きにずれたか**が出るので対処を分けられる: 「成果物はあるが記録が無い」は記録漏れなので `context.backfilled: true` を付けて補記する。「記録はあるが成果物が無い」は起動が失敗したか記録が過剰なので、**補記ではなく 4.2d 手順 1 の未検証扱い**に回す (成果物の無い観点は検査されていない)。

   `fatal-*.json` / `self-exemptions.json` / `_spawn-*.txt` は main が書いたもので spawn ではないため、上の glob には含めない。

## フェーズ内エスカレ条件まとめ

4.2a〜4.2e のいずれかで下記に当たったらエスカレ停止する。run 全体の停止理由の網羅リストは SKILL.md 本体の「エスカレ停止時の挙動」が正。

| 条件                                                                                                             | reason                                       |
| ---------------------------------------------------------------------------------------------------------------- | -------------------------------------------- |
| 修正ラウンド 3 回でも fatal 残存 (guard 違反 / review high のいずれも)                                           | `phase_fix_exceeded`                         |
| 検査 agent が結果を返せない (未検証をパス扱いにしない)                                                           | `guard_agent_failed` / `review_agent_failed` |
| implementer の報告が読めない / 実装が実在しない (`files_changed` が空) が 3 回続いた                             | `phase_fix_exceeded` (原因は `impl_report_invalid`)  |
| `phase_spawns > phase_spawns_budget` (既定 33) または `run_spawns > run_spawns_budget` (Step 3 のカウンタ規定)                              | `spawn_budget_exceeded`                      |
| テストゲート 3 回不通過                                                                                          | `tests_failing_before_commit`                |
| 自己免除の抽出が成立しない (report はあるが配列が得られない)                                                     | `exemptions_extract_failed`                  |
| `design_overview_break` 検知 (実装・修正中いずれでも、commit 前に停止)                                           | `design_overview_break` (P3)                 |
| テストファイル削除 / skip 追加 / assertion の弱体化・空虚化が設計にトレースできない (4.2e の機械検知 / 4.2c の review-adversarial 検知 / implementer の `test_weakening_suspected` 報告のいずれも) | `test_weakening_detected`                    |
