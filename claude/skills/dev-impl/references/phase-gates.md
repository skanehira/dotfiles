# dev-impl フェーズ内ゲート 参照

`dev-impl/SKILL.md` の Step 4.2c / 4.2d / 4.2e から参照される、**main が Bash で直接実行する検証コマンド**の詳細。agent の起動方法と述語の算出は [phase-execution.md](./phase-execution.md) が持ち、こちらは「main 側が自分で確かめる」ゲートを集めている。判断基準・分岐・停止条件は SKILL.md 本体にあるので、そちらを先に読んでから該当節だけをここで参照する。

## 目次

- [4.2c: fan-out 前後の clean 確認](#42c-fan-out-前後の-clean-確認)
- [4.2c: 自己免除の抽出](#42c-自己免除の抽出)
- [4.2c: spawn の事前記録](#42c-spawn-の事前記録)
- [4.2c: 「最後の issue」の判定](#42c-最後の-issue-の判定)

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
