# dev-impl issue 運用 参照

`dev-impl/SKILL.md` の Step 1 / 4.2e / Step 4.6 / Step 5.5 から参照される、**run の途中で GitHub issue と TODO.md を書き換える操作**の詳細。判断基準・分岐・停止条件は SKILL.md 本体にあるので、そちらを先に読んでから該当節だけをここで参照する。

## 目次

- [親 issue の自動 close sweep](#親-issue-の自動-close-sweep)
- [P1 手順 4: issue の reopen と本文更新](#p1-手順-4-issue-の-reopen-と本文更新)
- [動的修正のコミット](#動的修正のコミット)
- [P2 手順 4: フェーズ差分のスナップショットと TODO 再生成](#p2-手順-4-フェーズ差分のスナップショットと-todo-再生成)
- [新フェーズの issue 化](#新フェーズの-issue-化)
- [紐付けの差集合](#紐付けの差集合)

## 親 issue の自動 close sweep

`/dev-spec` のフェーズ 12 が作る `uc-tracking` の親 issue は、そのユースケースを実現する子 (フェーズ issue) が全て closed になった時点で完了する。**GitHub は子が open のままでも親の close を止めない**ので、判定は dev-impl が行う。open の親を全件見て閉じられるものを閉じる (親は数件なので毎回全件確認で十分。冪等):

```bash
for PARENT in $(gh issue list --repo "$REPO_SLUG" --state open --limit $LIMIT \
                  --label uc-tracking --json number --jq '.[].number'); do
  if ! STATES=$(gh api --paginate "repos/$REPO_SLUG/issues/$PARENT/sub_issues?per_page=100" --jq '.[].state'); then
    echo "sub_issues の取得に失敗: 親 #$PARENT (この親は閉じずに次へ)" >&2
    continue
  fi
  TOTAL=$(printf '%s\n' "$STATES" | grep -c . | tr -d ' ')
  REMAIN=$(printf '%s\n' "$STATES" | grep -c '^open$' | tr -d ' ')
  if [ "$TOTAL" -gt 0 ] && [ "$REMAIN" -eq 0 ]; then
    gh issue close "$PARENT" --repo "$REPO_SLUG" \
      --comment "このユースケースの全フェーズ (sub-issue) が完了したため close する"
  fi
done
```

4 点を外さない:

- **`TOTAL -gt 0` の条件を省かない。** sub-issue が 1 件も紐付いていない親も `REMAIN` は 0 になるため、条件が無いと「まだ子が作られていない親」を完了扱いで閉じてしまう
- **`--paginate` と `per_page=100` を省かない。** このエンドポイントの既定は 1 ページ 30 件なので、子が 30 件を超える親では 31 件目以降の open な子が見えず、**まだ実装が残っている親を完了扱いで閉じる** (出力を見ても異常と区別できない silent な誤判定になる)
- **API 失敗を「子ゼロ」と混同しない。** 取得に失敗した親をそのまま判定に流すと `TOTAL` が空になり、`[ "" -gt 0 ]` がエラー出力なしに偽になる。上のように exit code で分岐して、失敗はログに残して次の親へ進む
- **判定に親の `sub_issues_summary` を使わない。** このフィールドは**遅延反映**するので、close 直後は古い件数を返す (実測)。`/sub_issues` 一覧の `state` は即時整合なのでこちらを引く

**この sweep が扱うのは close 方向だけである。** 人間が完了済みの子 issue を手で reopen した場合、親は closed のままになる (親の reopen は `/dev-spec` のフェーズ 12.3 と本スキルの Step 4.6「新フェーズの issue 化」が、子を新たに紐付けるときだけ行う)。

## P1 手順 4: issue の reopen と本文更新

4. **当該フェーズにタスクを足す場合は、TODO.md だけでなく issue 本文も更新する。** Step 4.6 は 4.2e で issue を close した**後**に走るので、その issue は既に closed であり、**実装指示の実体は TODO.md ではなく issue 本文である** (PHASE_CONTEXT の `phase_tasks` は `gh issue view` から作る)。TODO.md だけ直しても実装器には届かない。手順は `gh issue reopen <N>` → `gh issue edit <N> --body-file` で `## 実装タスク` に追記 → ラベルを `ready` に戻す → Step 2 の抽出をやり直す。**フェーズを跨ぐ追加なら新フェーズを TODO.md に挿入し、続けて「新フェーズの issue 化」を実行する** (下記の共通手順。close 済み issue を再利用するより見通しがよいので、迷ったらこちら)。挿入する見出しには `<!-- deps: ... -->` と `<!-- goals: ... -->` を必ず付け、**`docs/USECASES.md` がある構成では `<!-- ucs: ... -->` も付ける**。メタ情報 5 項目 (ゴール / DoD / 参照 docs / 変更想定ファイル / 非スコープ) も書く (判定基準は `../dev-spec/references/todo-generation.md` の「フェーズ依存の宣言」「対応ゴールの宣言」「対応ユースケースの宣言」「各フェーズが持つメタ情報」)。`ucs` を落とすと、次に `/dev-spec` を再実行したときフェーズ 10.5 の監査が `phase_meta_missing` (high) で差し戻す

## 動的修正のコミット

**P1 / P2 が編集した docs は、その場でコミットする。** Step 4.6 は 4.2e のコミットより**後**に走るため、ここでコミットしないと変更は working tree に残ったまま次のフェーズへ進む。その run がエスカレ停止すれば、**設計をどう変えたかが git の履歴に一切残らない** (JSONL と HTML レポートには残るが、差分そのものは失われる)。

```bash
git add docs/TODO.md            # P2 では編集した DESIGN_DETAIL_APP.md / _INFRA.md も含める
git commit -m "$(cat <<'EOF'
📝 docs: <P1|P2> 動的修正 — <何をどう変えたかの 1 行>

<なぜ変えたか。実装から判明した事実を 2〜3 行>

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

**実装差分とは別コミットにする** (`rules/core/commit.md` の関心事分割。設計の更新と実装は別の関心事であり、混ぜると後から「設計がいつ変わったか」を追えなくなる)。type は `docs` を使い、`[STRUCTURAL]` / `[BEHAVIORAL]` は付けない — この 2 つはプロダクトコードの動作変更の有無を表す区分で、設計書の更新はどちらでもない (Step 7 の HTML レポートのコミットと同じ扱い)。

**エスカレ停止時もこのコミットは残す。** 停止時に打たないのは**フェーズ最終コミット**だけで (全体スイートと DoD を通っていないため)、ラウンドのコミットも設計判断の記録も実装の成否と無関係に残す。

## P2 手順 4: フェーズ差分のスナップショットと TODO 再生成

4. **再生成の前にフェーズ見出しのスナップショットを取る** (再生成後では「前」の状態が失われ、増えたフェーズを特定できない)。そのうえで `../dev-spec/references/todo-generation.md` を Read し、その手順に従ってメインループで TODO.md を再生成する (ステップ 2〜3 を既存の TODO.md に対して適用し、完了済みフェーズのチェック状態は保つ)。**フェーズ見出しの `deps` / `goals` / (USECASES.md がある構成では) `ucs` の宣言を落とさない** — 再生成で `ucs` が消えると、次の `/dev-spec` 実行でフェーズ 12.0 がフラット判定に落ち、親 issue が作られなくなる

   ```bash
   rg -o '^### フェーズ[^:]*' docs/TODO.md | sort -u > $RUN_DIR/phases-before.txt   # 再生成の前に取る
   # ... TODO.md を再生成 ...
   rg -o '^### フェーズ[^:]*' docs/TODO.md | sort -u > $RUN_DIR/phases-after.txt
   comm -13 $RUN_DIR/phases-before.txt $RUN_DIR/phases-after.txt                        # 増えたフェーズ
   ```

## 新フェーズの issue 化

**TODO.md にフェーズを追加しただけでは、そのフェーズは永久に実装されない。** 着手対象の抽出は Step 2 が GitHub issue からしか行わないため、issue の無いフェーズは Step 2 に現れない。TODO.md にフェーズを足したら、**同じターンで必ず**次を行う。

1. **issue を作る。** 本文の節構造・タイトル形式は `/dev-spec` のフェーズ 12.4.2 と同じ (`## ゴール` / `## DoD` / `## 参照すべき docs` / `## 変更が想定されるファイル` / `## 非スコープ` / `## 実装タスク` / `## 依存` / `## 対応ゴール`)。**TODO.md に全フェーズ共通節がある場合の `## DoD` 直後への転記も 12.4.2 と同じく行う** — 落とすと DoD ブロックの実行規約 (`bash -e` 前提等) が追加した issue にだけ無い状態になる。ラベルは `ready`。メタ情報の書き方の判定基準は `../dev-spec/references/todo-generation.md` の「各フェーズが持つメタ情報」

   ```bash
   NEW_URL=$(gh issue create --repo "$REPO_SLUG" --title "フェーズ<識別子>: <名前>" \
               --body-file $RUN_DIR/new-phase-body.md --label ready)
   NEW_NUM=$(printf '%s' "$NEW_URL" | grep -o '[0-9]*$')
   ```

   `## 依存` の `Depends on #N` は、追加フェーズの `deps` が指す識別子を issue 番号に変換して書く (対応表は `gh issue list --repo "$REPO_SLUG" --state all --limit $LIMIT --json number,title` のタイトルから引き、いま作った issue は `$NEW_NUM` で足す)。

   **識別子は既存と衝突しない値を採る** (例: 元フェーズが `4` なら `4-a`)。識別子は issue タイトル・`$SCRATCH_DIR` のパス・4.2e の `### フェーズ<識別子>:` 引き当ての 3 箇所で鍵になるため、衝突するとフェーズを取り違える。**複数フェーズを同時に追加するときは TODO.md の出現順に 1 件ずつ作る** (12.4.2 と同じ理由: deps は前方参照を禁じているので、出現順に作れば依存先の issue 番号が常に確定済みになる)

2. **親 issue がある構成なら紐付ける** (下記「紐付けの差集合」)
3. **`run_spawns_budget` を `max(現在値, run_spawns + その時点の open issue 数 (`uc-tracking` を除く) × 20)` で再計算する** (Step 3 のカウンタ規定。係数の正は Step 3)。issue が増えたのに上限が据え置きだと、正当な実装の途中で `spawn_budget_exceeded` に当たる。**手順 4 の記録より前に行う** (再計算した値を `phase_added` に載せるため)
4. **JSONL に `event_type: phase_added` を記録する** (`context`: `phase` / `issue_number` / `parent_number` (紐付けた親。フラット構成なら省略) / `origin` (`p1` / `p2` / `goal_unmet`) / `run_spawns_budget` (手順 3 で再計算した値))
5. **Step 2 の issue 抽出を再実行**して、追加したフェーズを着手対象に含める

## 紐付けの差集合

判定と引き当ては **`--state all`** で行う。4.2e の sweep が完了した UC の親を随時 close していくため、既定の open だけを見ると親を取りこぼす。とくに Step 5 到達時点では全ての親が closed になっており、`--state all` を落とすと紐付けの分岐が丸ごと死ぬ:

```bash
PARENTS=$(gh issue list --repo "$REPO_SLUG" --state all --limit $LIMIT \
            --label uc-tracking --json number,title)
if [ "$(printf '%s' "$PARENTS" | jq 'length')" -eq 0 ]; then
  : # フラット構成。以降の差集合と紐付けを行わない (回さないと全 issue が「未紐付け」として出る)
else
  : # 以下の差集合と紐付けを実行する
fi
```

**親が 0 件のときに差集合へ進まない。** フラット構成では紐付け済みの子が 1 件も無いため、差集合が実装対象の全 issue を「未紐付け」として返し、存在しない親に紐付けようとする。

**紐付ける対象は「今作った issue」ではなく、`uc-tracking` を除く全 issue のうち、どの親にも紐付いていないものの差集合とする** (`/dev-spec` の 12.4.3 と同じ考え方)。自分が作った issue だけを見ると、前の run が issue 作成後・紐付け前に落ちて宙に浮いた子は誰にも拾われない。**このブロックは Step 1 でも run ごとに 1 回流す**ので、フェーズ追加が起きない run でも取りこぼしが回収される。

```bash
# 紐付け済みの子
gh issue list --repo "$REPO_SLUG" --state all --limit $LIMIT --label uc-tracking --json number --jq '.[].number' |
  while read -r P; do gh api --paginate "repos/$REPO_SLUG/issues/$P/sub_issues?per_page=100" --jq '.[].number'; done | sort -u > $RUN_DIR/linked.txt
# 実装対象の全 issue
gh issue list --repo "$REPO_SLUG" --state all --limit $LIMIT --json number,labels \
  --jq '.[] | select((.labels | map(.name) | index("uc-tracking")) | not) | .number' | sort -u > $RUN_DIR/all-children.txt
comm -13 $RUN_DIR/linked.txt $RUN_DIR/all-children.txt   # 未紐付けの子 = これから紐付ける対象
```

`comm` が返すのは issue 番号なので、そこからフェーズ見出しへ辿る: **issue タイトル `フェーズ<識別子>: <名前>` から識別子を切り出し、TODO.md の `### フェーズ<識別子>:` 見出しを引く。** その見出しの `<!-- ucs: ... -->` が紐付け先の親を決める (`none` なら「横断: UC に属さないフェーズ」)。**見出しを引けない子** (Step 0 の「捨てる」分岐が未コミットのフェーズ挿入を破棄した場合など) は `none` の親に倒し、JSONL に記録して人間が後から辿れるようにする。

**扱うのは「どの親にも紐付いていない子」だけである。** P2 の TODO.md 再生成で `ucs` が変わり、**別の親にぶら下がったままの子は差集合に現れない**。その貼り替え (`replace_parent`) は `/dev-spec` の 12.4.3 に委ねる — dev-impl が親の付け替えまで行うと、設計側の宣言と実装側の判断のどちらが正かが曖昧になる。その値に対応する親のタイトル (`UC-<n>: <名前>` / `横断: UC に属さないフェーズ`) で `$PARENTS` を引いて `$PARENT_NUM` を得る。

**親が closed なら先に reopen する。** 閉じた親にぶら下げると、そのユースケースが未完に戻ったことが俯瞰から消える:

```bash
[ "$(gh issue view "$PARENT_NUM" --repo "$REPO_SLUG" --json state -q .state)" = "CLOSED" ] && \
  gh issue reopen "$PARENT_NUM" --repo "$REPO_SLUG" --comment "フェーズが追加されたため再オープンする"
```

`gh issue reopen` を無条件で打たない (open な親に打つと不要な通知とコメントが残る)。紐付け本体のコマンドと API 仕様 (numeric id を `-F` で渡す・二重紐付けの 422・`replace_parent`) は `../dev-spec/SKILL.md` の 12.4.3 に従う。
