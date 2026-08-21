---
name: dev-impl
description: 実装ループ。/dev-spec が作成した GitHub issue を入力に、依存順に 1 件ずつレビュー・コミット込みで自律実装するオーケストレーター。実装の指示は issue 本文 (ゴール / DoD / 参照 docs / 変更想定ファイル / 非スコープ) から取り、完了したら close する。人間の介入はエスカレ条件 (概要設計の破綻 P3 等) のみ。dev-spec の承認ゲート通過後にユーザーが直接起動する。エスカレーション回答後の再開も本スキルの再実行で行う。「実装ループを開始」「issue を順に実装して」「残りタスクを自動で実装」などで起動。
argument-hint: "[docs ディレクトリパス、省略時は docs/]"
model: opus
allowed-tools: Read, Edit, Write, Glob, Bash, Skill, Agent, AskUserQuestion
---

# dev-impl — 実装ループ

承認済みの設計 + TODO を入力に、open issue を依存順に最後まで自律的に実装するオーケストレーター。`dev-spec` の下流ステージ (= 設計と TODO が固まった後) を機械的に消化する役割。

人間の介入は **エスカレ条件** (検査 → 修正の周回が 3 回でも fatal 残存 / P3 検出など) でのみ発生する。それ以外は止まらず最後まで走る。

## モデル方針

- 本スキルは frontmatter で `model: opus` を指定している。モデル切り替えが効くのは**ユーザーが `/dev-impl` を直接起動したターンだけ** (Skill ツール経由の起動では適用されない)。エスカレーションに回答した後の再開も `/dev-impl` の再実行で行う (TODO.md の `- [x]` 状態から途中再開できるため、再実行で override が再適用される)
- **Agent ツールの呼び出しには例外なく `model` を明示する。** 未指定だと agent 定義の frontmatter ではなく**親のセッションモデルを継承**するため、最上位 tier のセッションでは haiku 指定の agent まで最上位単価で走る。

| subagent | model | 根拠 |
| --- | --- | --- |
| dev-impl-implementer (4.2a `mode: implement`) | `opus` | フェーズ 1 本を TDD で完結させる実装器 |
| dev-impl-implementer (4.2d `mode: fix`、ラウンド 1) | `opus` | fatal findings の修正。実装と同じ判断力を要する |
| dev-impl-implementer (4.2d `mode: fix`、ラウンド 2 以降) | `fable` | 1 ラウンドで閉じなかった fatal は局所修正では閉じない。下記「修正ラウンドのモデル昇格」参照 |
| architecture-guard (4.2c) | `haiku` | レイヤ境界違反の検出は機械的・宣言的な判定でモデル性能に依存しない |
| fix-lsp-warnings (4.2b) | `haiku` | LSP が出した警告を規則どおりに潰す機械作業 |
| tech-investigation (Step 1.5 の個別呼び出し) | `opus` | 検証範囲の設計を自分で行う探索的な調査 |
| review-adversarial (4.2c) | `sonnet` | 下記のとおり実測で opus の優位が確認できず、同額でより多くのターンを回せる sonnet が有利 |
| review-tdd / review-quality / review-product-readiness (4.2c) | `opus` | 設計意図とテストの対応づけなど、規約の機械照合に還元されない判断を含む |
| review-spec-compliance (5.2) | `opus` | 承認ハッシュ照合と成果物 ↔ 詳細設計の突合を伴う受入監査 |

### 修正ラウンドのモデル昇格 (ラウンド 2 以降は `fable`)

**ラウンド 1 で解消しなかった fatal は、指摘箇所の局所修正では閉じない性質のものが多い。** 実測: `opus` の fix は毎ラウンド「指摘された high」を必ず解消したのに、そのたびに同じ族の隣接箇所へ新しい high が出た。あるフェーズでは 3 ラウンドすべてがこの形を繰り返し (指摘 → 解消 → 隣接箇所に新規)、high の出所は同じ 2 ファイルの間を往復したまま上限に達して停止した。個別のエッジケースを潰す作業になっていて、状態遷移の不変条件という根が閉じていなかった。

そこで**ラウンド 2 以降は `model: "fable"` に上げ、指示文で「指摘箇所を局所的に塞ぐ前に、当該箇所が属する不変条件を洗い出して族ごと閉じる」ことを求める** (指示文の全文は [references/phase-execution.md](./references/phase-execution.md) の `## 4.2d: 修正ラウンドの implementer 起動`)。ラウンド 3 でも解消しなければ従来どおり `phase_fix_exceeded` でエスカレ停止する — **モデルを上げても閉じない fatal は、実装の腕ではなく設計の問題である**可能性が高く、人間の判断を仰ぐべき局面だと見なす。

- `agent-spawn-guard` hook は **model の未指定だけを弾き、規定と違う値でも明示されていれば意図的な override として通す** (`claude/hooks/agent-spawn-guard.ts` の `validateAgentSpawn`)。この昇格に hook の改修は要らない
- この昇格により、当該ラウンドだけ「実行器のモデル > 検証器のモデル」となり `rules/core/orchestration.md` の原則を満たさなくなる。**検証器 (review-*) を上げるのではなく実行器だけを上げるのは、ラウンド 2 に至った時点で不足しているのが検出力ではなく修正の設計力だと実測で分かっているため** (検出は毎ラウンド機能しており、新しい high を実行証拠つきで出し続けている)

- **review-adversarial が `sonnet` である理由**: 同一セッション・同一フェーズ群での直接比較 (2026-08 のセッションログ実測) で、opus は 20 spawn・2.55 ドル/spawn で high 3 件 (0.15 件/spawn)、sonnet は 21 spawn・2.51 ドル/spawn で high 19 件 (0.90 件/spawn) だった。**1 spawn あたりの金額はほぼ同一で、単価が 1/5 の sonnet は同じ予算で 3.8 倍のターンを回せるため、実際に壊して確かめる本 agent の作業様式と噛み合う**。sonnet の findings は空虚ではなく、TOCTOU 並行削除を実際に再現し修正前ロジックで 20/20 再現するところまで確認する等、実行証拠を伴っていた。この 1 点で `rules/core/orchestration.md` の原則「実行器のモデル ≤ 検証器のモデル」を満たさなくなるが、当該原則は「検証が実行より弱いと骨抜きになる」ことを避けるための代理指標であり、**検出力の実測が代理指標に優先する**。切り替え後は high 検出件数の推移を監視し、opus 時の 0.15 件/spawn を下回り続けるようなら opus に戻す。

### フェーズ実装を subagent に委譲する理由 (`rules/core/orchestration.md` の原則に対する dev-impl 限定の例外)

`rules/core/orchestration.md`「委譲の判断」は**逐次実装の subagent 委譲を禁止**している (固定費と報告往復で総トークン・時間とも増えるため)。dev-impl はこの原則の**唯一の例外**で、issue 1 件ずつの逐次実装であっても implementer subagent に出す。`rules/core/orchestration.md` 本体は変更しないので、他のタスクでは従来どおりメインループ直営で実装する。

例外にする根拠は、dev-impl だけが持つ「フェーズを 100 本単位で回す」性質にある (実測値はいずれも 2026-07 の dev-impl 実行 7 セッション):

- メインループ直営では**フェーズ境界でコンテキストが一度も下がらず単調増加する**。実測で 160k → 286k → … → 980k → 自動圧縮 106k と推移し、平均コンテキストは 443,863〜515,258 トークンに収束した。cache read 48.7 億トークンの実体は「平均 475k × 10,247 リクエスト」であり、1 リクエストの単価ではなく**往復回数 × 常駐コンテキスト**が支配的だった
- 委譲の固定費はフェーズ 1 本あたりで見れば小さい (U0 spike 実測: implementer 1 spawn 6.39 ドル、検査 3 観点 1.83 ドル、修正 1 ラウンド 2.96 ドル の計 11.18 ドル)。単発タスクなら固定費が勝つが、フェーズ数だけ常駐コンテキストが積み上がる dev-impl では逆転する
- **待ちを親に集約できる。** main の cache write は全量 1 時間 TTL、subagent は全量 5 分 TTL (ハーネス仕様、スキルから制御不可)。子を待つ subagent は 5 分超のギャップでキャッシュを失効させる (実測: 失効 62 件のうち 32 件がこれ)。実装を葉の subagent に閉じ込め、レビューの起動と待機を 1 時間 TTL の main に置くことで、同じ待ち時間でもキャッシュが生き残る

**implementer は葉であること (子 subagent を起動しないこと) が例外の前提条件**。葉の agent は実測で失効ゼロだった (architecture-guard 975 ギャップ / review-quality 55 / review-spec-compliance 165 のいずれも 0 件)。葉性は指示文ではなく `claude/agents/dev-impl-implementer.md` の `tools` から `Agent` を除くことで構造的に強制する (subagent には親の hooks が届かないため、指示文では違反を検出できない)。

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

**フェーズ / ラウンドのスコープの値** (`PHASE` / `PHASE_NAME` / `PHASE_START_SHA` / `SCRATCH_DIR` / `ISSUE` / `ROUND` / カウンタ) も同じ理由で消えるので、**Step 4.1 で `$SCRATCH_DIR/env.sh` に書き、フェーズ内の各ブロックの冒頭で run スコープと合わせて `source` する**。カウンタ (`PHASE_SPAWNS` / `RUN_SPAWNS`) は env.sh に書いた値ではなく **JSONL の `spawn` イベントの件数から数え直す** (logging.md が復元の正と定めている。ファイルの値は書き損ねると実態からずれるが、件数はイベントそのものから出る)。

**`$HOME` を使い、`~` を変数に入れない。** `~` はシェルの展開に依存するので、subagent への受け渡しや `jq --arg` を経由すると文字列 `~/...` のまま渡り、存在しないパスを指す。

**リアルタイム監視用の 1 行テキストログ**と**事後振り返り用の構造化 JSONL** を並走させる。各ステップの「開始 / 完了 / 動的修正 / エスカレ」発生時に両方へ同期して書き込む (1 行ログ = summary のみ、JSONL = summary + context を構造化)。終了時に JSONL から HTML レポート (Step 7) を生成する。`START_SHA` は Step 5.2 の監査 agent 呼び出しと Step 6 / エスカレ通知のテンプレート (references/goal-audit.md, references/notification-template.md) から参照される。

書式・JSONL スキーマ・書き込みコマンド・実行ログの範例は [references/logging.md](./references/logging.md) を Read して従う。

## 実行手順

### Step 0: 再入チェック (エスカレ後の再開対応)

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

1. **run_id とカウンタを引き継ぐ** (新規発行しない)。decisions.jsonl から `p2_fixes_total` / `goal_loop` / `run_spawns` の現在値と `run_spawns_budget` (記録済みの値の最大) を復元する — `goal_loop` / `run_spawns` は再実行のたびに 0 に戻ると発散上限 (Step 3) が実質無効化されるため、`p2_fixes_total` は上限こそ無いが run をまたいだ通算件数を Step 6 で提示するため、`run_spawns_budget` はこの復元値を下限として Step 1 で再計算するため。**進行中フェーズのカウンタも JSONL から復元する** — `phase_spawns` は当該 phase の `spawn` 件数、`phase_fix_round` は `fix_dispatch` 件数、`test_gate_retry` は `context.round` が `tg*` の `spawn` 件数、`p1_fixes_in_phase` は当該 phase の `p1_fix` 件数。**Step 4.1 のリセットは「その issue を初めて着手したとき」だけ**で、再入や reopen 経由の再着手では復元する (リセットしてしまうと、上限のあるカウンタが再入のたびに 0 に戻って発散上限が実質無効になる)。**進行中フェーズの `gating_decided` (最新の 1 件) も復元する** — 再 fan-out で起動してよい観点の唯一のソースなので、失うと記憶で判断することになる。当該フェーズの `gating_decided` が無ければ 4.2c の初回 fan-out からやり直す。
2. **進行中フェーズの突合**: ラウンドごとにコミットしているので (4.2a / 4.2d の「ラウンドごとのコミット」)、中断したフェーズは `PHASE_START_SHA` の上に積まれた `[phase-<識別子>]` prefix つきのコミット列として残り、working tree は通常 clean である。
   - 進行中フェーズの `PHASE_START_SHA` は decisions.jsonl の当該フェーズの `start` イベントの `context.phase_start_sha` から復元する
   - `git log --oneline <PHASE_START_SHA>..HEAD` で何が積まれているかを確認し、AskUserQuestion で「続きとして取り込む / 捨ててフェーズをやり直す」を確認する (再入時 1 回だけの人間確認)。各ラウンドが何をしたかは `~/.claude/logs/dev-impl/<前回の run_id>/reviews/phase-<識別子>/impl-report*.json` にも残っている
   - **捨てる場合は `git reset --hard <PHASE_START_SHA>`。** ただし打つ前に、`<PHASE_START_SHA>..HEAD` の全件が `[phase-<識別子>]` prefix を持つことを確認する。**エスカレ停止した run では HTML レポートのコミット (Step 7) が、P1/P2 の動的修正があった run では設計書のコミットが同じ範囲に混ざる**ので、無条件の reset はそれらも巻き戻す。prefix を持たないコミットがあれば、実装コミットだけを `git revert` するかユーザーに判断を仰ぐ
   - working tree が非クリーンなら、ラウンドのコミット前に落ちたか、検査 agent の汚染 (4.2d 手順 8) が残っている。`git status --porcelain` の中身も提示して同じ確認に含める
3. **TODO チェックの突合**: TODO.md で `- [x]` 化されているフェーズのうち、**対応する issue が open のまま**のものは「最終コミットまでは済んだが close まで到達していない」として扱う。**チェックは戻さず、フェーズもやり直さない。**

   **`impl_done` の SHA を基準にしない。** 4.2e はフェーズ最終コミット (手順 2) を打ってから `impl_done` (手順 5) を書くので、その間で落ちると「コミットは済んだが `impl_done` が無い」状態になり、SHA 基準の突合は完了しているフェーズを未完了と誤判定する。**issue の open/closed は 4.2e 手順 7 の close と対になっていて、`- [x]` と同じコミットに入る TODO.md の状態より後に動く**ので、「TODO は `[x]` だが issue が open」= 「最終コミットまでは済んだが close まで到達していない」を正しく表す。**4.2e の手順 3 (RUN_FACTS 更新) から再開する** — 手順 3〜8 はどれも冪等 (RUN_FACTS の追記は同じ内容なら差分が出ず、突合と転記と close は再実行しても結果が変わらない) なので、どこから落ちたかを特定せずに済む。**手順 7 から再開しない** — 手順 3〜6 が永久にスキップされ、RUN_FACTS の更新も実装ノートの転記も失われる。

   例外は `- [x]` が**未コミット** (working tree にだけある) の場合で、これはコミット前に落ちたことを意味するので `- [ ]` に戻してフェーズをやり直す。
4. **Step 5 系の停止からの再開**: 前回が `goal_loop > 2` / `verification_tampered` / `acceptance_criteria_change` など**ゴール判定の段階で停止**していた場合、in-progress の issue は 1 件も無いので issue ラベルによる駐車が使えない。この場合は decisions.jsonl の最後の `p3_escalate` を提示し、**AskUserQuestion で「対応済み (再判定する) / まだ (中止する)」を確認する**。「対応済み」を選ばれたときだけ `goal_loop` を 0 に戻して Step 5.1 から再開する。**Claude の判断で戻さない** — 戻す条件が「人間の回答が入ったこと」であり、自動化すると `goal_loop` の上限が実質無効になる (needs-human ラベルを Claude が勝手に外さないのと同じ理由)

未完了 run が無ければ通常起動 (新規 run_id 発行) で Step 1 へ。

#### needs-human で駐車中の issue の再開

`needs-human` ラベルの open issue があれば、**着手する前に**その issue 番号・停止理由 (issue コメントに記録済み) をユーザーに提示し、AskUserQuestion で「解決した (ready に戻して着手する) / まだ (駐車したまま他の issue を進める) / 中止」を確認する。

「解決した」を選ばれた場合だけ、`gh issue edit <N> --add-label ready --remove-label needs-human` でラベルを戻す。**Claude の判断で勝手に外さない** — 駐車の解除は人間の回答が入ったことの証拠であり、ここを自動化すると停止条件が実質無効になる。

### Step 1: 前提ドキュメントの確認

1. `docs/DESIGN.md` を Read
2. `docs/DESIGN_DETAIL_APP.md` を Read
3. `docs/DESIGN_DETAIL_INFRA.md` を Read
4. `docs/TODO.md` を Read

#### プロダクトモードの判定

run 全体で保持する `PRODUCT_MODE` を DESIGN.md のスタンプから判定する (以降のステップすべてがこの値を参照する):

```bash
PRODUCT_MODE=$(sed -nE 's/.*<!-- product-mode: (cli|webapp) -->.*/\1/p' docs/DESIGN.md | head -1)
PRODUCT_MODE=${PRODUCT_MODE:-unknown}
```

- `cli` / `webapp`: dev-spec がスタンプを書いた新形式 docs
- `unknown` (スタンプ不在、旧形式 docs): 後方互換のため、UI 系判定は従来どおり `dev_server` 推定 (references/phase-context.md) にフォールバックする

#### GitHub の前提条件

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

**`OPEN` が確定したこの時点で `run_spawns_budget` を確定する。式は Step 3 の「spawn 予算の意図」の更新表が正**で、ここでは繰り返さない (2 箇所に式を書くと片方だけが更新されて食い違う)。確定した値は JSONL の `start` の `context` に記録する。**再入で予算を足さないと、前回が `spawn_budget_exceeded` で止まっていた場合に再実行が構造的に何も解決しない** (`run_spawns` は Step 0 で復元され、リセットされないため)。

**続けて、親 issue がある構成なら「紐付けの差集合」を run ごとに 1 回流す** (手順は Step 4.6「新フェーズの issue 化」の同名ブロック)。前回の run が issue を作った直後・紐付け前に落ちると、その子は `ready` ラベルを持つので Step 2 が拾って実装・close するが、**親には永久に紐付かないまま完了してしまう** (4.2e の sweep からも見えないので、親が先に close される)。ここで 1 回回すことが、その取りこぼしを回収する唯一の経路である。

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
| ゴール定義              | 下記「ゴール行の抽出コマンド」が 1 件以上を返す                                                          | `goals_missing`: 「dev-spec フェーズ 9 でゴールを定義してから再実行」                                                                                                                             |
| ゴール ↔ 検証手順の 1:1 | 抽出した各 `G<n>` に対応する `G<n> 検証` 行が DESIGN_DETAIL_APP.md または DESIGN_DETAIL_INFRA.md にある | `verification_missing`: 欠落ゴール ID を列挙して dev-spec フェーズ 9 へ差し戻し                                                                                                                   |
| G_E2E (必須・モード非依存) | `PRODUCT_MODE` が `cli`/`webapp` なら常に必須。`unknown` は Web プロダクト判定 (phase-context.md の dev_server 判定と同じ基準) が真なら必須 | `verification_missing` (同上)                                                                                                                                                                     |

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

承認ハッシュの再計算コマンド (dev-spec 11.3 の生成と同一定義。P2 ガードでも使う)。

**この 2 本の正規表現は `skills/dev-spec/SKILL.md` の生成側および `agents/review-spec-compliance.md` の独立照合側と 1 文字も違えてはならない。** ハッシュはバイト比較なので、抽出される行が 1 行でも違えば承認スタンプと一致せず `approval_stale` が常に発火する。**上の「ゴール行の抽出コマンド」とは別物**で、あちらはゴールの存在と 1:1 の照合に使う (ハッシュには関わらないので書き方が違ってよい):

```bash
GOALS_SHA=$(
  {
    rg --no-filename '^- G[0-9]+:|^G[0-9]+:|^- G_E2E:|^G_E2E:' docs/DESIGN.md
    rg --no-filename '^- G[0-9]+ 検証|^G[0-9]+ 検証|^- G_E2E 検証|^G_E2E 検証' docs/DESIGN_DETAIL_APP.md docs/DESIGN_DETAIL_INFRA.md
  } | shasum -a 256 | cut -d' ' -f1
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
| `blocker=false` のみ | テキストログに `[dev-impl] POC_NEEDED ${id} pending (non-blocker)`、JSONL に `event_type: poc_pending` (context に id / scope / risk) を記録して Step 2 へ (実装中に検証が必要になったら `tech-investigation` subagent を `model: "opus"` 明示で個別に呼ぶ。HTML レポートのセクション 5 がこのエントリを表示する) |
| `blocker=true` あり  | **エスカレ停止** (`poc_marker_unresolved`)。「未解決の blocker マーカーが残っています。`/dev-spec` のフェーズ 5 (PoC 検証) で解決してから `/dev-impl` を再実行してください」とユーザー通知                                                                                                  |

### Step 2: issue の抽出と着手順の決定

**実装の単位は GitHub issue** であり、**着手対象の抽出に TODO.md は使わない** (issue はフェーズ 12 が TODO.md から転記したもので、着手順と進捗の原本は GitHub の側にある)。TODO.md は Step 1 で読み、4.2e のチェック更新と P1 動的修正の書き込み先としては引き続き使う。

```bash
gh issue list --repo "$REPO_SLUG" --state open  --limit $LIMIT --json number,title,labels,body > "$RUN_DIR/issues-open.json"
gh issue list --repo "$REPO_SLUG" --state closed --limit $LIMIT --json number --jq '[.[].number]' > "$RUN_DIR/issues-closed.json"
```

取得した open issue には UC 親 issue も混ざる。下の表の 1 行目 (`uc-tracking`) で先に除外してから着手判定に入る。

着手対象の決め方:

| 条件 | 扱い |
| --- | --- |
| `uc-tracking` ラベルが付いている | **着手対象外。** ユースケース単位の親 issue (俯瞰用) であり、実装の実体を持たない。ラベル判定はこの行を**最初に**適用する (親はライフサイクルラベルを持たないため、次行以降の「ラベルが無い open issue」に流すと未完成と誤判定する) |
| `needs-human` ラベルが付いている | **着手しない。** 駐車中の issue であり、ラベルを外すのは人間の回答を得た後 |
| `ready` ラベル | 着手可能な候補 |
| `in-progress` ラベル | 前回の run が中断したもの。**Step 0 が decisions.jsonl から run 記録を復元できた場合だけそのまま再開する。** 対応する run 記録が無い (別マシン・別クローン・ログ削除後) 場合は未着手とみなし、`gh issue edit <N> --add-label ready --remove-label in-progress` でラベルを戻してから通常フローで着手する |
| ラベルが無い open issue (`uc-tracking` でもない) | フェーズ 12 が作成直後に落ちた未完成の issue。`issue_incomplete` でエスカレ停止し、`/dev-spec` の再実行 (12.3 の突き合わせが冪等に貼り直す) を案内する |

候補のうち、本文の `## 依存` にある **`Depends on #N` の参照先がすべて closed になっているものだけが着手可能**。複数あれば issue 番号の昇順で 1 件選ぶ。

**並列化はしない。** 1 件実装して close し、次の判定に戻る、を繰り返す。フェーズを同時に走らせる wave / worktree fan-out は持たない。

着手可能な issue が 1 件も無いのに open issue (`uc-tracking` を除く) が残っている場合は、依存が循環しているか、依存先が `needs-human` で駐車している。どちらかを判別して `dependency_blocked` でエスカレ停止する (JSONL の `context` に残りの issue 番号と各々の未解決依存を残す)。

### Step 3: ループ全体の状態管理

以下の counter を保持して各フェーズで参照する (dev-impl 開始時に 0 で初期化):

| カウンタ                                        | 上限                                                      | 超過時の挙動                                    |
| ----------------------------------------------- | --------------------------------------------------------- | ----------------------------------------------- |
| `p1_fixes_in_phase` (現フェーズ内 P1 修正回数)  | 2 (回)                                                    | P2 として扱う (次のループでは P2 として処理)    |
| `p2_fixes_total` (dev-impl 全体の P2 修正回数)  | なし (上限を設けない)                                     | 停止しない。件数と内訳を記録し Step 6 で提示する |
| `goal_loop` (ゴール達成判定 → 未達対応の周回数) | 2 (周)                                                    | P3 として停止                                   |
| `phase_fix_round` (現フェーズの検査 → 修正の周回数) | 3 (回)                                                | `phase_fix_exceeded` でエスカレ停止 (context に guard 由来 / review 由来の内訳を残す) |
| `test_gate_retry` (現フェーズの 4.2e テストゲート再試行回数) | 3 (回)                                       | `tests_failing_before_commit` でエスカレ停止    |
| `phase_spawns` (現フェーズの累計 subagent 起動数) | 33 (回)                                                | `spawn_budget_exceeded` でエスカレ停止          |
| `run_spawns` (run 全体の累計 subagent 起動数)   | `run_spawns_budget` (下記「spawn 予算の意図」で定義)      | 同上                                            |

スコープ別のリセット時点:

| スコープ | カウンタ | リセット時点 |
| --- | --- | --- |
| issue | `p1_fixes_in_phase` / `phase_fix_round` / `test_gate_retry` / `phase_spawns` | **その issue の Step 4.1 (最初の subagent を起動する前)** |
| run 全体 | `p2_fixes_total` / `goal_loop` / `run_spawns` | リセットしない。**再入時は Step 0 で decisions.jsonl から復元した値を初期値にする** |
| run 全体 (上限値) | `run_spawns_budget` | リセットしない。**上方向にのみ再計算する** (更新時点は下記「spawn 予算の意図」の表。issue が close されても下げない) |

**run 全体の経過時間では打ち切らない。** 発散は試行回数の上限 (`phase_fix_round` / `test_gate_retry` / `goal_loop` / `phase_spawns` / `run_spawns`) で止める。長時間走ること自体は、フェーズ数の多いプロジェクトでは正常な状態であり停止理由にしない。個々の subagent が応答しないケースは、run の経過時間ではなく **spawn からの経過時間**で打ち切る (Step 4.2a)。

カウンタと findings / deviation_signals の集約は**メインセッションが管理する**。各カウンタの現在値と集約結果は都度 1 行テキストログ + JSONL に書き出して外部化する (コンテキストが長くなり compaction をまたいでも、ログから状態を復元できるように)。

**spawn 予算の意図**:

- 1 フェーズは最小構成でも implementer 1 + architecture-guard 1 + review 1〜4 の subagent を起動する。フェーズ数だけ積み上がるため、上限を機械ゲートとして置く
- 根拠: subagent を最も使ったセッションは 129 spawn でフェーズ単価が最悪 (116.4 ドル / フェーズ、subagent が全体の 66.8%) だった (2026-07 の実測)。2026-08 の実測でも、4 フェーズで 66 spawn (16.5 spawn / フェーズ) のうち 53 がレビュー系で、全体コストの 35% を占めていた。**このとき JSONL に記録されていた `spawn` は 44 件で、実際の 66 件に対し 22 件 (33%) が記録漏れしていた** — 記録が欠けると `phase_spawns` の上限判定が実態より小さい値で走るので、下記の全件記録は予算ゲートの前提そのものである
- `phase_spawns` の上限 33 の内訳 (最悪ケース = 最後の issue): implementer 1 + 初回検査 5 (guard 1 + review 最大 4) + (fix 1 + 再検査 最大 5) × 3 ラウンド = 24 に、**同じフェーズで正当に起きうる残りを足した値**: 4.2b の `fix-lsp-warnings` 1 + 4.2e のテストゲート再試行 3 + 報告不整合の再起動 3 + 汚染検出によるやり直し 2 = 9。合計 33。**以前の 24 は検査ラウンドだけを数えた値で、本文自身が挙げる正当な経路を足すと超えてしまっていた** (正常な作業が上限で止まる偽陽性になる)。上限に当たったら `spawn_budget_exceeded` で止めてよい (安全網として機能させる)。再検査は 4.2d 手順 5 のとおり「fatal を出した観点 + guard」に絞るため通常は 2〜3 に収まるが、全観点が同時に fatal を出す最悪ケースを上限に据える (上限は安全網であって想定値ではない)
- 中央値の想定は 4 (implementer 1 + guard 1 + review-adversarial 1 + review-tdd 1)。`run_spawns` の上限係数 8 はこの中央値に修正ラウンド 1 回分 (fix 1 + 再検査 2〜3) を見込んだ値
- **`run_spawns` の上限は `run_spawns_budget` という別の値で保持し、残作業ベースで上方向にのみ更新する。** 更新するのは次の 3 時点だけで、**issue が close されても下げない**:

  | 更新時点 | 計算 |
  | --- | --- |
  | 新規 run の開始時 (Step 1 で `OPEN` を数えた直後) | `run_spawns_budget = max(OPEN × 8, 16)` (このとき `run_spawns` は 0) |
  | run 再入時 (Step 1 で `OPEN` を数えた直後) | `run_spawns_budget = max(復元値, run_spawns + OPEN × 8, run_spawns + 16)` |
  | issue 追加時 (P1 / P2 動的修正・Step 5.5) | `run_spawns_budget = max(現在値, run_spawns + その時点の OPEN × 8)` (Step 4.6「新フェーズの issue 化」手順 3) |

  `OPEN` はいずれも Step 1 で数える **`uc-tracking` を除いた実装対象の open issue 件数**を指す (親 issue は実装しないので予算を消費しない)。予算の母数をこう取ることは本スキルを通じて一貫している。

  **下限 16 を置くのは、`OPEN = 0` で Step 5 (ゴール達成判定) から再開する経路があるため** (Step 1 の「`OPEN` が 0 で closed が 1 件以上なら全 issue 完了済み」)。この経路で `OPEN × 8` をそのまま使うと予算が 0 になり、Step 5.2 の監査 agent を 1 体も起動できない。16 は Step 5 の監査 2 体 + 未達対応ループ (`goal_loop` 上限 2 周 × 追加フェーズ 1 本) が回る最小限として置いている。

- **`OPEN × 8` を `run_spawns` と直接比べてはならない。** 前者は「これから使ってよい量」、後者は「すでに使った量」で、比べる単位が違う。直接比べると issue を close するたびに上限が下がるので、**正常に完了した作業そのものが停止理由になる** (実測: 5 フェーズ完了・`run_spawns` 74 の run で残 `OPEN` が 10 件 → 上限 80。次の 1 件を close した瞬間に `OPEN` 9 件 → 上限 72 となり、消費済み 80 を下回って breach する)。さらに Step 5 (ゴール達成判定) では定義上 `OPEN` が 0 件になるため上限も 0 になり、`review-spec-compliance` / `review-product-readiness` の起動が必ず上限違反になる
- **再入で予算が増えるのは意図した挙動である。** `spawn_budget_exceeded` は「再実行で解決しうる」停止理由に分類されている (「エスカレ停止時の挙動」の表) ので、再入で予算が一切増えないなら、再実行しても同じ状態のまま即座に再停止して何も解決しない。予算の追加付与を人間の再起動に紐づけることで、1 セッション内の暴走は有限の `run_spawns_budget` で止めたまま、正当な継続だけが人間の判断を挟んで前進する
- `run_spawns_budget` は更新のたびに JSONL の `start` / `phase_added` の `context` に記録する (compaction や再入をまたいでも値を復元できるように)。復元は記録済みの値の**最大**を採る (上方向にしか動かないので一意に決まる)
- **Agent ツールで subagent を起動する箇所は、本スキルに 7 つある** — 4.2a (implementer)、4.2b (fix-lsp-warnings)、4.2c (検査 fan-out)、4.2d 手順 4 (`mode: fix` の implementer)、4.2e のテストゲート再試行 (`mode: fix` の implementer)、Step 5.2 (監査 agent)、Step 1.5 の `tech-investigation` (未解決 PoC を実装中に検証する個別呼び出し)。**この 7 つすべてで、起動する直前に `event_type: spawn` を JSONL へ書き、`phase_spawns` / `run_spawns` を進める。** 起動後に書く規定だと、待ちに入る直前の・前進を生まないログ 1 行だけが構造的に落ちる (4.2c 参照)
- 記録が欠けると `run_spawns` の予算判定が実態より小さい値で走る。**フェーズを閉じる直前 (4.2e 手順 4) に成果物と突合して補記する**のが二段目の歯止めだが、成果物 JSON を出さない fix-lsp-warnings は補記でも拾えないので、一段目 (起動前の記録) を落とさないことが要点である

### main のコンテキスト規律

**フェーズ実装を implementer に出しても、main がその成果物を読み返せば削減は消える。** 以下を守る:

| 規律 | 内容 |
| --- | --- |
| ソースを Read しない | フェーズの実装内容は implementer の報告要約と review findings 経由でのみ知る |
| `git diff` はパッチ本文を出さない | `--stat` / `--name-only` のみ。フルパッチを main のコンテキストに載せない |
| 検査結果 JSON は射影して読む | 全文 Read せず、[references/phase-execution.md](./references/phase-execution.md) の `## 4.2c: 検査 fan-out の起動` にある射影コマンドで読む。**表のセルにコマンドを埋めない** — Markdown の表ではパイプを `\|` にエスケープする必要があり、それをそのまま実行すると jq がコンパイルエラーになる (実測 exit 3)。射影が拾うのは fatal 判定と未検証判定に要る最小限で、`message` / `fix_proposal` は修正する implementer (`mode: fix`) が JSON を自分で Read するため main に載せない (実測: 全文 5,573 バイト = 約 1,400 トークン → 射影 約 60 トークン) |
| テスト出力は失敗時のみ | 失敗時の末尾 30 行まで。成功時は exit code だけ |
| subagent の最終メッセージを短くさせる | 検査 agent・implementer の呼び出し prompt に「最終メッセージは `output_path` (implementer は `report_path`) の絶対パス 1 行だけにせよ。要約や解説を書くな」を必ず含める。**agent 定義側に同じ規定があっても守られないことがある** (実測: `architecture-guard.md` は「stdout には output_path のみ」と規定しているが Markdown レポート全文が返り、1 ラウンドで約 2,250 トークンが main に流入した) |

例外 (main が実物を読んでよい場面): 4.2e のテスト弱体化のトレース確認、Step 4.6 の P2 判定での DESIGN_DETAIL 参照。

### Step 4: 各 issue の実行

Step 2 で選んだ issue を 1 件実装し、close してから Step 2 に戻る。**同時に複数の issue を走らせない。** implementer は main の working tree で直接編集し、統合の手順は無い (main がそのままコミットする)。

骨格は「issue に `in-progress` を貼る → PHASE_CONTEXT を組み立てる → implementer 起動 → 待つ → 検査 fan-out 起動 → 待つ → 修正ラウンド → テストゲート → コミット → issue を close」。

**PHASE_CONTEXT の実装指示は issue 本文から組み立てる。** `## ゴール` / `## DoD` / `## 参照すべき docs` / `## 変更が想定されるファイル` / `## 非スコープ` / `## 実装タスク` をそのまま使う (節名は dev-spec のフェーズ 12 が固定している)。設計の抜粋が必要な場合だけ `## 参照すべき docs` が指す節を docs から読む。

着手時と完了時の GitHub 操作:

```bash
gh issue edit <N> --repo "$REPO_SLUG" --add-label in-progress --remove-label ready
# ... 実装 ...
# 完了コミットの本文に `Fixes #<N>` を入れる (マージ不要でそのままブランチにコミットする運用なので、
# 自動クローズが効かない場合は明示的に閉じる)
gh issue close <N> --repo "$REPO_SLUG" --comment "DoD がすべて通過したため close する"
```

**子を close したら、続けて親 issue の自動 close sweep を回す** (4.2e の手順 6 → 7)。

**main が行うこと** (implementer には渡さない): PHASE_CONTEXT と RUN_FACTS の組み立て、事前判定と観点 gating の確定、検査 fan-out の起動と待機、fatal 判定、全テストゲート、テスト弱体化の機械検知、コミット、issue のラベル操作と close、decisions.jsonl への書き込み、Step 4.6 の P1/P2/P3 判定。

**完了判定は main が自分で行う。** implementer の `status: done` を完了根拠にせず、次の 2 点を main が確認する:

- (a) **実装が実在すること** — 次の 3 つを**すべて**確認する。**`files_changed` が空でないことを先に見る** — 空配列に対する「全要素が差分に現れる」は空集合の包含として無条件に成立し、**この判定が防ぐと宣言している当のケース (何も実装せず `status: done`) で空虚になる**:
  1. `files_changed` が**非空**であること。空なら `impl_report_invalid` として扱う (4.2a の表。`mode: implement` で再起動し、3 回で `phase_fix_exceeded`)
  2. `files_changed` の各パスが、実際に `git diff --name-only <PHASE_START_SHA>` + `git ls-files --others --exclude-standard` の結果に現れること
  3. そのラウンドのコミットで変更行数が実際に増えたこと。**起動の直前に控えた SHA と比較する** (`BEFORE=$(git rev-parse HEAD)` を implementer 起動前に取り、コミット後に `git diff --shortstat "$BEFORE" HEAD` が非空であることを見る)。working tree が非空であることだけでは足りない (`.gitignore` 追記や作業ファイルで非空になりうるため)
- (b) **fatal が 0 件であること** — 判定基準は 4.2d の fatal の定義に従う (review-* の high と architecture-guard の high/medium)

何も実装せず `status: done` を返した場合に「差分ゼロ → 全テスト green → `- [x]` 化」まで素通りするのを防ぐための判定。

着手対象の各 issue について以下を順次実行する:

#### Step 4.1: フェーズ開始の SHA を記録

`PHASE_START_SHA=$(git rev-parse HEAD)` を取る。architecture-guard / review-* が「このフェーズの差分」を判定する基準点であり、中断したフェーズの提示 (`git log <SHA>..HEAD`) と破棄 (`git reset --hard <SHA>`) の起点でもある。

**再入で「続きとして取り込む」を選んだフェーズでは、新しく取らずに Step 0 手順 2 で復元した値をそのまま使う。** 中断時点までのラウンドが既にコミットされている以上、いま `HEAD` を取ると**そのフェーズが済ませた実装が全部フェーズ差分の外に出る** — 検査 agent には残りの差分しか見えず、テスト弱体化の機械検知も完了判定も、既存分を一切見ないまま「問題なし」を返す。再入の再開地点は 4.2c (検査 fan-out) からで、`SCRATCH_DIR` も前回のものを引き継ぐ (結果 JSON と report が残っているため)。

**この値を JSONL のフェーズ `start` イベントに必ず書く** (`context.phase_start_sha`)。**Step 0 手順 2 の復元元はこの記録だけ**で、書き忘れると再入時に「続きとして取り込む / 捨てる」の分岐が成立しない:

**まず変数を確定し、作業ファイル置き場を作り、`$SCRATCH_DIR/env.sh` に書き出してから、`start` イベントを書く** (Bash の呼び出しをまたぐと変数が消えるため。値の一覧と意味は [references/phase-execution.md](./references/phase-execution.md) の `## 変数の定義`)。**この順序で行う** — `SCRATCH_DIR` を作る前に env.sh は書けない:

```bash
# 値は着手中の issue から取る (下は「フェーズ4-a: ノードの編集と階層操作」= issue #15 の例)
PHASE_ID="4-a"                          # issue タイトル `フェーズ<識別子>: <名前>` の識別子
ISSUE=15                                # issue 番号
PHASE="phase-$PHASE_ID"                 # JSONL の phase に入れる短縮識別子
PHASE_NAME="フェーズ$PHASE_ID: ノードの編集と階層操作"   # agent へ渡す phase_name

# 作業ファイル置き場 (implementer の報告 JSON・検査結果 JSON・攻撃スクリプト等)。
# **リポジトリの外に置く**ことでコミット対象への混入を防ぎ、エスカレ停止後の再入時にも残す
SCRATCH_DIR="$RUN_DIR/reviews/$PHASE"
mkdir -p "$SCRATCH_DIR"

cat > "$SCRATCH_DIR/env.sh" <<EOF
export PHASE="$PHASE"
export PHASE_NAME="$PHASE_NAME"
export PHASE_ID="$PHASE_ID"
export ISSUE=$ISSUE
export SCRATCH_DIR="$SCRATCH_DIR"
export PHASE_START_SHA="$PHASE_START_SHA"
EOF
```

変数が揃ったところで、JSONL のフェーズ `start` イベントを書く (**この順序を守る** — 先に書こうとすると `$PHASE` も `$ISSUE` も未定義で、`--argjson issue "$ISSUE"` が JSON パースエラーで落ちる):

```bash
jq -nc --arg ts "$(date +%Y-%m-%dT%H:%M:%S%z)" --arg p "$PHASE" \
   --arg sha "$PHASE_START_SHA" --argjson issue "$ISSUE" '{
  timestamp:$ts, phase:$p, step:"start", event_type:"start", severity:"info",
  summary:("フェーズ開始 (issue #" + ($issue|tostring) + ")"),
  context:{issue:$issue, phase_start_sha:$sha}}' >> "$JSONL"
```

以降このフェーズで Bash を呼ぶときは、冒頭で run スコープと合わせて `source` する:

```bash
. "$HOME/.claude/logs/dev-impl/<run_id>/env.sh"
. "$SCRATCH_DIR/env.sh"
```


#### Step 4.1.5: PHASE_CONTEXT の組み立て

implementer と検査 subagent (architecture-guard / review-*) は parent のコンテキストを継承しないため、dev-impl が「フェーズ 1 本を実装・検査するのに必要な情報パッケージ」を組み立てて **`docs/.dev-impl/<run_id>/phase-<識別子>-context.md` に Write** する (`<識別子>` は issue タイトル `フェーズ<識別子>: <名前>` の `フェーズ` 直後からコロンまでの文字列。`1` だけでなく `4-a` のような接尾辞付きもある。タイトル形式は dev-spec のフェーズ 12.4.2 が固定している)。subagent には prompt にこのファイルの絶対パスだけを渡し、各 agent が必要な節を自分で Read する (1 フェーズあたり implementer 1 + 検査 subagent 最大 5 への同一内容の重複埋め込みを避けるため)。**このファイルが implementer にとってフェーズの唯一の入力になる**ので、抜粋の不足はそのまま実装の質に出る。

`docs/.dev-impl/` は `.gitignore` に追加する (無ければ追記)。**追記が必要なら Step 1 の構造ゲート通過直後に行い、その時点で 1 度コミットする** — Step 4 に入ってから追記すると、`.gitignore` の変更自体が working tree の差分として残り、Step 4 の完了判定に紛れ込む。

#### RUN_FACTS.md の初期作成 (run の最初のフェーズのみ)

`docs/.dev-impl/<run_id>/RUN_FACTS.md` が存在しなければ、PHASE_CONTEXT を書く前に main が作成する。テンプレートと規則は [references/phase-context.md](./references/phase-context.md) の `## RUN_FACTS.md`。この時点で埋めるのは「プロジェクトコマンド」表だけで、他の節は見出しだけを置く (implementer が必ず Read する必須入力なので、不在ファイルを指さないようにするため)。

「run の最初のフェーズか」は**ファイルの存在で判定する** (フェーズ番号や再入状態では判定しない)。再入した run では前回作った RUN_FACTS.md がそのまま残っているので、再作成もコマンド再検証も走らない。

PHASE_CONTEXT の YAML テンプレートと抜粋ロジック (design 節の抜粋上限 4KB・dev_server 推定・poc_results の出典を含む) は [references/phase-context.md](./references/phase-context.md) を Read して従う。

組み立てた PHASE_CONTEXT ファイルの path は implementer (4.2a) と review-tdd / review-quality / review-product-readiness (4.2c) の prompt に**絶対パスで**渡す。**architecture-guard と review-adversarial には渡さない** (前者は入力仕様が PHASE_CONTEXT を受け取らず `design_path` 等を取るため、後者は fresh context 監査のため)。受け渡しの一覧は [references/phase-context.md](./references/phase-context.md) の `## 渡し方`。

#### Step 4.2: フェーズの実装と検査

##### 事前判定 (main)

判定基準: `IS_NEOVIM_PLUGIN` は init.lua / lua ディレクトリ / plugin/*.lua の有無で決まる (LSP 警告修正ステップ 4.2b の要否)。`uiPhase` は `phase_tasks` / フェーズ名の UI キーワード、または `related_source_files` のフロントエンド dir 有無で決まる (4.2c の観点 gating に使う)。**`PRODUCT_MODE=cli` の場合は `uiPhase` を判定せず常に `false` 固定**とする (CLI 実装の「コマンド」「フラグ」等の語がキーワード判定に誤爆するのを防ぐ)。

実行コマンドは [references/phase-execution.md](./references/phase-execution.md) の `## 4.2: 事前判定` 節を Read してから実行する。

**RUN_FACTS.md を新規作成したフェーズでのみ** (= run の最初のフェーズ。判定は Step 4.1.5 参照)、gate コマンド (`full_test_command` / `lint_command` / `format_command`) を main が 1 回実行して exit code を確認する。未検証のコマンドを渡すと、implementer が自分の実装のせいで失敗していると誤認して発散する。

確認結果を RUN_FACTS.md の「プロジェクトコマンド」表の「確認済み」列に書き、**その後で** PHASE_CONTEXT を `gate_commands_verified: true` (全コマンドが exit 0) または `false` で書く。2 フェーズ目以降は RUN_FACTS.md の同列から値を引き継ぐ。`false` を渡された implementer の挙動は `claude/agents/dev-impl-implementer.md` に規定がある。

##### 4.2a: TDD 実装 (implementer subagent)

`dev-impl-implementer` を `model: "opus"` 明示で 1 フェーズにつき 1 つ起動し、**main は完了を待つ**。渡すのは `mode: implement` / `phase_context_path` / `repo_dir` / `report_path` と、最終メッセージを 1 行に制限する指示 (「main のコンテキスト規律」参照)。指示文の全文テンプレートは [references/phase-execution.md](./references/phase-execution.md) の `## 4.2a: implementer の起動` 節を Read して使う。

implementer 側の規約 (TDD の順序、フェーズスコープのテストのみ実行、コミット・`docs/` 編集の禁止、報告 JSON のスキーマ、停止条件) は `claude/agents/dev-impl-implementer.md` に常駐しているので、指示文で繰り返さない。

- **起動する直前に** `phase_spawns += 1` / `run_spawns += 1` し、JSONL に `event_type: spawn` を記録する (起動後に書く規定だと構造的に落ちる。理由は 4.2c の事前ブロック)
- **報告を受けたら main がその差分をコミットする** (下記「ラウンドごとのコミット」)
- 報告受領時に JSONL へ `event_type: impl_report` (context に要約 JSON + `report_path`) を記録する。**報告要約は main のコンテキストに載るが、全文 JSON は載せない** (P1/P2/P3 判定と JSONL 転記に必要なフィールドは `jq` で `report_path` から直接引く)
- `status: failed` の場合は `reason` に応じて分岐する:

| `reason` | 対処 |
| --- | --- |
| `design_overview_break` | **即エスカレ停止** (P3、commit しない) |
| `test_weakening_suspected` | 4.2e と同じトレース確認を main が行い、トレース不能なら `test_weakening_detected` でエスカレ停止 |
| `tests_failing` | 下記「fix ブリーフ」を書いて `mode: fix` で再起動する (4.2d の修正ラウンドと同じ扱い。`phase_fix_round` を共有する) |
| `spec_insufficient` | **fix で再起動しない。** 足りないのは設計情報であって修正の指示ではなく、fix ブリーフが運べるのは reason 文字列とテスト出力だけなので、同じ情報で再実行しても同じ理由で止まる。**Step 4.6 の P2 (`design_detail_gap`) として扱い**、報告の `reason` が指す不足を DESIGN_DETAIL に補ってから `mode: implement` で再起動する (`phase_fix_round` を進める)。補うべき内容が概要設計に及ぶなら P3 |

**fix ブリーフ**: `mode: fix` の implementer は `findings_paths` の JSON しか入力に取らないので、検査結果 JSON が存在しないこの経路でも main が同じ形式のファイルを書いて渡す。書き出し先は `<SCRATCH_DIR>/impl-failure-<phase_fix_round>.json`:

```json
{
  "ok": false,
  "dimension": "implementation",
  "findings": [
    {
      "severity": "high",
      "rule": "tests_failing",
      "file": "<報告の files_changed の代表 1 件、無ければ null>",
      "line": null,
      "message": "<implementer 報告の reason と、直前のテスト実行出力の末尾 30 行>",
      "fix_proposal": null
    }
  ]
}
```

`rule` には implementer 報告の `reason` (`tests_failing` / `spec_insufficient`) をそのまま入れる。4.2e のテストゲート失敗で書く `<SCRATCH_DIR>/test-failure-<test_gate_retry>.json` も同じスキーマを使う (`rule: "tests_failing_before_commit"`)。

**implementer が期待どおりに終わらなかった場合は、原因で 2 つに分ける。** 混ぜると「フェーズ内で再起動する」のか「issue を駐車して次へ行く」のかが決まらない:

| reason | 該当する状況 | 対処 |
| --- | --- | --- |
| `impl_report_invalid` | `report_path` が不在 / `jq` でパース不能 / 必須フィールド (`status` / `summary` / `files_changed` / `test_result`) の欠落 / `files_changed` が空 (完了判定 (a)) | **フェーズ内で処理する。** `phase_fix_round += 1` して `mode: implement` で再起動 (fix ではない — 何が実装されたか分からないため)。**`report_path` は `impl-report-retry-<phase_fix_round>.json`、`spawn` 記録の `context.round` は文字列 `"retry<phase_fix_round>"`** にする (4.2e 手順 4 の集合突合が成果物と 1:1 で対応するようにするため。ファイル名の変換規則は同手順の sed に `s|^impl-report-retry-|dev-impl-implementer-rretry|` を足す)。3 回で `phase_fix_exceeded` でエスカレ停止。issue は `in-progress` のまま |
| `impl_timeout` | spawn から **30 分**応答が無い (計測は [references/phase-execution.md](./references/phase-execution.md) の `## 4.2a: subagent の応答待ち時間` 節) | **run は止めない。** その issue に `gh issue comment <N>` で停止理由 (何分待って応答が無かったか・そのラウンドまでに積まれたコミット) を残し、`gh issue edit <N> --add-label needs-human --remove-label in-progress` で駐車して、**次の着手可能な issue に移る** (Step 0 の再開確認は issue コメントに理由が書かれている前提で「解決したか」を尋ねるので、コメントが無いと人間が何を判断すればよいか分からない) (`in-progress` を外さないとラベルが併記になり Step 2 の判定が割れる)。着手可能な issue が他に無ければ `dependency_blocked` と同じ扱いで停止する |

どちらも検査 agent の `guard_agent_failed` / `review_agent_failed` と同じく、**パス扱いにしない**。**`impl_timeout` は「エスカレ停止」ではない** (run は次の issue へ進む) ので、フェーズ内エスカレ条件の表にも停止条件のリストにも載せない。載せるのは `impl_report_invalid` から昇格した `phase_fix_exceeded` の側である。

##### ラウンドごとのコミット (4.2a / 4.2d 共通)

**implementer の報告を受けたら、その差分をその場で main がコミットする。** フェーズの終わりまでコミットを溜めない。溜めると実装が未追跡ファイルとして積み上がり、**検査 agent への差分の見せ方・作業ツリー汚染の検出・中断時の巻き戻しがいずれも「未追跡ファイルを相手にする特殊な操作」に化ける** (4.2c の clean 前提・4.2d 手順 8・Step 0 の巻き戻しは、いずれもラウンドごとにコミットされていることを前提に組んである)。

| 項目 | 規定 |
| --- | --- |
| 実行主体 | **main** (implementer ではない)。形式を機械検証する commit-msg-guard hook は親にしか効かないため |
| subject | `<emoji> <type>: [phase-<識別子>] <要約>`。`<要約>` は implementer 報告の `summary` を 1 行に詰めたもの |
| 識別子 | issue タイトル `フェーズ<識別子>: <名前>` の識別子。`$SCRATCH_DIR` のパスや `### フェーズ<識別子>:` 見出しと同じ値を使う |
| `[STRUCTURAL]` / `[BEHAVIORAL]` | **付けない。** 途中のコミットは「フェーズの実装の一部」であって、動作変更の有無を独立に語れる単位ではない。フェーズ最終コミット (4.2e) にだけ付ける |
| 本文 | `Refs #<issue 番号>` を入れる (close するのは 4.2e の最終コミットだけ) |
| コミットの条件 | **フェーズ範囲のテストが緑であることだけ。** 全体スイートは 4.2e で確認する (`rules/core/commit.md`「dev-impl のフェーズ内コミット」の例外規定) |

prefix を付けるのは `git log --oneline` でどのコミットがどのフェーズのものか目で追えるようにするため。フェーズ 1 本が 1 コミットではなくなるので、prefix が無いと履歴がフェーズ境界を失う。

##### 実装ノートの受け取り (design_decision / open_question)

implementer 報告の `design_decisions` (設計が沈黙・あいまいな箇所での自律判断) と `open_questions` (確信が持てずユーザの事後確認が必要な選択) を、main が JSONL に `event_type: design_decision` / `open_question` として**`report_path` から `jq` で転記する** (スキーマは [references/logging.md](./references/logging.md) を参照)。ループは止めない。

これらは `deviation_signals` (設計と*矛盾する*変更) とは別物で、混ぜない。同一の判断・質問を後続フェーズが踏襲するだけの場合、implementer は再記録しない規約になっている (RUN_FACTS の「累積 design_decisions」を読むため)。

##### 4.2b: LSP 警告修正 (Lua/Neovim のみ)

`IS_NEOVIM_PLUGIN=true` なら `fix-lsp-warnings` agent を `model: "haiku"` 明示で起動する (対象はフェーズ差分ファイルのみ)。**起動の直前に `spawn` を記録する** (4.2c と同じ理由 — 記録は起動前に書く)。失敗は警告ログのみで継続し、`verification_skipped` (source: `lsp_fix_failed`) を記録する。

**修正が入った場合は、main が `phase_test_command` を再実行して緑を確認したうえでコミットする** (「ラウンドごとのコミット」に従う。subject は `<emoji> style: [phase-<識別子>] LSP 警告を解消する`)。**コミットせずに 4.2c へ進んではならない** — 4.2c は fan-out 直前にツリーが clean であることを前提にしており、ここでの修正が未コミットのまま残ると、その clean 確認が必ず失敗して「直前のラウンドのコミットが漏れている」という事実と違う診断を出す。

**このステップだけは検査 fan-out に混ぜない。** fix-lsp-warnings は修正する agent なので、レビューと同時に走らせるとレビュー対象のファイルが検査中に書き換わる。

##### 4.2c: 検査 fan-out (main が起動して待つ)

**fan-out の直前に、作業ツリーが clean であることを確認する。初回だけでなく 4.2d の再 fan-out でも毎回行う**:

```bash
git -C "$REPO_DIR" status --porcelain    # 出力が空であること
```

非空なら**直前のラウンドのコミットが漏れている** (4.2a / 4.2b / 4.2d は implementer や fix-lsp-warnings の成果を受けるたびに main がコミットする → 「ラウンドごとのコミット」)。コミットしてから fan-out する。

**同じ「`status --porcelain` が非空」でも、観測する時点で意味が違う。** fan-out の**前**は自分のコミット漏れ (直前に動いたのは implementer なので、差分は実装)。fan-out の**後**は検査 agent の汚染 (4.2d 手順 8。直前に動いたのは検査 agent で、実装は既にコミット済み)。**処方が正反対 (前はコミットする / 後は `git restore` で捨てる) なので、取り違えると実装を捨てるか変異をコミットすることになる。** 判断は「いつ観測したか」で機械的に決まるので、迷ったら直前に何が動いたかを見る。**実装がコミット済みであることは、この後の 3 つが成り立つ前提になっている**:

- 全 agent の `git diff <PHASE_START_SHA>` が新規ファイルも含めて同じ差分を返す (`git diff` は未追跡ファイルを一切見ないので、コミットしていないと新規実装だけのフェーズが全 agent に空差分として見える)
- 検査 agent がソースを書き換えたまま戻さなかった場合、clean なツリー上の変更として `git status --porcelain` に現れる (フェーズの差分が未コミットのまま並んでいると、既に「変更済み」の行しか出ないので中身の書き換えを検出できない)
- 中断したフェーズの破棄が `git reset --hard <PHASE_START_SHA>` で済む (Step 0)

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

再 fan-out のたびに作り直す (追記ではなく上書き。前ラウンドで裁定済みのものは受け側が `upheld` として再掲する)。

**続けて、この fan-out で起動する agent の `spawn` を JSONL に先に書く。記録は「起動した後」ではなく、この事前ブロックの中で行う。** 起動後に書く規定だと、待ちに入る直前の・前進を生まないログ 1 行だけが構造的に落ちる。実測: 初回 fan-out は同じブロックで `gating_decided` を書く必要があるため記録が残ったが、**再 fan-out には他に書く理由が無く記録が落ちた**。ある run の 5 フェーズで、architecture-guard の spawn 記録は実行回数に対し 1/1・2/4・1/4・4/4・0/7 件だった (修正ラウンドを多く回したフェーズほど欠落が大きい)。別のフェーズでは全 agent 合計 16 回のうち 8 件が欠落していた。`run_spawns` の予算ゲートはこの記録を唯一のソースにしているので、欠けると上限判定が実態より小さい値で走る。起動する agent 集合はこのブロックの時点で確定しているため先に書いても内容は正確で、起動が失敗した場合は別途 `guard_agent_failed` / `review_agent_failed` が記録されるので実態と食い違ったままにはならない。

**`mode: full` の review-adversarial は fan-out に入れず、単独で先に走らせてから残りを fan-out する。** レンズ A は**共有の作業ツリー上でソースを直接書き換えて実行し、終える前に戻す**ので、その間に並列で走る観点は変異後のコードを読みうる。読んだかどうかは事後に判別できず (戻ってしまえば `status` は clean)、その観点の結果が「fatal なし」でも「fatal あり」でも信用できない。**影響は dev サーバを立てる review-product-readiness に限らない** — guard も tdd も quality も同じツリーを読む。`mode: weakening_only` の adversarial は変異を行わないので通常どおり fan-out に入れてよい。

したがって起動の順序は次のいずれかになる:

| `adversarial_mode` | 起動のしかた |
| --- | --- |
| `full` | ① review-adversarial を単独起動して完了を待つ → ② 汚染の突合 → ③ 残りの観点 + architecture-guard を fan-out |
| `weakening_only` / `skipped` | 全観点 + architecture-guard を 1 回の fan-out で並列起動 |

gating された観点と `architecture-guard` を**同一メッセージ内の複数 Agent tool_use として並列起動**し、main が全部の完了を待つ (`full` の adversarial だけは上表のとおり先に単独で走らせる)。呼び出し方法は [references/phase-execution.md](./references/phase-execution.md) の `## 4.2c: 検査 fan-out の起動` 節を Read してから実行する。

**全観点の結果を受け取ったら、汚染の突合を行う** (agent の `working_tree_polluted` 報告の有無に関わらず必ず実行する):

```bash
git -C "$REPO_DIR" status --porcelain    # 出力が空であること
```

fan-out の直前に clean を確認しているので、ここで非空なら**検査 agent が書き換えたまま戻していない**。差分が出たら 4.2d 手順 8 に従う。

guard を review と同じ fan-out に入れるのは、待ちを 2 回から 1 回に減らすため。guard の違反も review の fatal も同じ修正ラウンド (4.2d) で処理する。

検査 agent も implementer と同じく **30 分応答が無ければ打ち切る**。打ち切った観点は「未検証」として 4.2d 手順 1 の `guard_agent_failed` / `review_agent_failed` で扱う。

**観点 gating (トークン削減の要):**

**gating はフェーズごとに 1 回だけ確定する。** 4.2c の初回 fan-out の直前に下表と述語を評価し、決まった観点の集合 (review-adversarial の `mode` を含む) を JSONL に `event_type: gating_decided` で記録する。**4.2d の再 fan-out はこの記録された集合の部分集合しか起動できない** (毎ラウンド評価し直すと、判定が揺れて仕様外の観点が起動する。実測で review-quality が「最後の issue のみ」の規定に反して 3 フェーズで起動していた)。`context` のスキーマは [references/logging.md](./references/logging.md) の `gating_decided` の行が正 (ここでは重ねて定義しない)。

| タイミング        | 実行観点                                                                                            |
| ----------------- | --------------------------------------------------------------------------------------------------- |
| 毎フェーズ        | architecture-guard (gating 対象外、常に実行) + review-adversarial (`mode` は下表で決める。下記スキップ述語で skip 可) |
| テスト差分があるフェーズ (`$TEST_FILE_CHANGED` または `$TEST_CONTENT_CHANGED` が非空) | 上記 + review-tdd                              |
| UI を触るフェーズ (`uiPhase == true`) | 上記 + review-product-readiness (dev_server が無ければ skip)                     |
| **最後の issue** | 全観点フル (tdd / quality / product-readiness / adversarial)                                        |

**review-adversarial の mode 決定** (`claude/agents/review-adversarial.md` の「モード」節が受け側の規定):

| 条件 (いずれかが真なら `full`) | 述語 |
| --- | --- |
| 消費型資源を扱う差分 | `$CONSUMABLE_CHANGED` が非空 |
| 認証・認可・セッションの処理を含む差分 | `$AUTH_CHANGED` が非空 |
| **テスト差分が無く、実装が 20 行を超えて積まれたフェーズ** | `$TEST_FILE_CHANGED` と `$TEST_CONTENT_CHANGED` がともに空、かつ `$LINES` > 20 |
| 最後の issue | 自分以外に open issue が残らない |
| 上記のいずれでもない | → `weakening_only` (レンズ B のみ。docs を読まず攻撃も実行しない) |

述語の算出コマンドは [references/phase-execution.md](./references/phase-execution.md) の `## 4.2c: 観点 gating 述語の算出コマンド` 節にある。

3 行目の条件は **review-tdd の gating と対になっている**。テストを伴わない実装だけが積まれたフェーズは review-tdd が起動せず (判定対象のテストが無い)、レンズ B も検査対象の差分が無いため実質何も検査されない。この穴をレンズ C (完了主張の反証) で埋めるため `full` に上げる。

**結果を受け取ったら、`skipped_lenses` が非空なら JSONL に `event_type: verification_skipped` を書く** (`context: {target: "review-adversarial", source: "mode_degraded", lenses: [...], mode: "..."}`)。これが Step 5.6 の未検証項目集約に合流する経路で、書かなければモード縮退が沈黙する。スキップ述語で adversarial を起動しなかった場合は `gating_decided` の `adversarial_mode` に `"skipped"` を記録する。**mode の判定根拠は `basis` に残す。**

**「最後の issue」とは、その issue を close した時点で他に open issue が 1 件も残らないもの**を指す (issue 駆動では着手順を番号昇順で決めるだけなので、着手前に「最後かどうか」は分からない。検査 fan-out を起動する 4.2c の時点で次を引き、自分以外に open が無ければ最後と判定する)。**`uc-tracking` (親 issue) は数に入れない** — 親は実装対象ではないので、残っていても「最後のフェーズ」であることは変わらない:

```bash
gh issue list --repo "$REPO_SLUG" --state open --limit $LIMIT --json number,labels \
  --jq '[.[] | select((.labels | map(.name) | index("uc-tracking")) | not)] | length'
```

この時点では自分自身がまだ open なので、**出力が `1` (自分だけ) なら最後の issue**である。`0` と比較しない。

**review-tdd をテスト差分の有無で gating する理由**: review-tdd が判定するのは「書かれたテストの質」なので、テストに差分が無いフェーズには判定対象が存在しない。テストを伴わない実装だけが積まれた場合は、上の mode 決定表 3 行目が review-adversarial を `full` に上げ、レンズ C (完了主張の反証) がテスト不在を検出する。

**`PRODUCT_MODE=cli` では review-product-readiness を一切起動しない** (`uiPhase` が常に `false` のため UI を触るフェーズの行は発火せず、最後の issue の「全観点フル」からも product-readiness を除外する。cli の G_E2E は Step 5.2 で review-spec-compliance が担当する)。

review-quality (rules 準拠 + アーキテクチャ heuristic 統合) は最後の issue のみ (機械判定可能な境界違反は毎フェーズ同じ fan-out の architecture-guard が担保するため)。**ただし `$CONSUMABLE_CHANGED` が非空のフェーズ (消費すると無効化される資源 — ローテーション有効な refresh token・nonce・ワンタイムコード・べき等キー・使い捨て署名 URL — を扱う差分) では最後の issue でなくても起動する**。この種のコードは多重消費・恒久エラー分岐の漏れが復帰不能障害に直結し、architecture-guard の境界検査では検知できないため、最後の issue まで持ち越さない。

**review-adversarial のスキップ述語 (機械判定、actor の裁量では skip しない):**

算出コマンド (`$CHANGED` / `$LINES` / `$TEST_FILE_CHANGED` / `$TEST_CONTENT_CHANGED` / `$NON_DOC_CHANGED` / `$CI_FILES_CHANGED` / `$CONSUMABLE_CHANGED`) は [references/phase-execution.md](./references/phase-execution.md) の `## 4.2c: 観点 gating 述語の算出コマンド` 節を Read してから実行する (この節を読まず近似コマンドで代替すると、untracked ファイルや言語別インラインテストの検知漏れにより review-adversarial を不当に skip するリスクがある)。判定条件は以下の表に従う。

| # | 条件                                                                                                                                              | 意図                                                                                                                                                 |
| - | ------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1 | `$TEST_FILE_CHANGED` と `$TEST_CONTENT_CHANGED` がともに空                                                                                        | テスト変更時はレンズ B 必須。ファイル名 + 差分内容の 2 層、tracked/untracked 両方で判定 (言語別の具体パターンは phase-execution.md の実コマンドが正) |
| 2 | `$LINES` ≤ 20 (`$NON_DOC_CHANGED` が空、つまり `.md` / `docs/` のみの差分なら行数不問で skip 可)                                                  | typo・軽微修正の機械近似                                                                                                                             |
| 3 | `$CI_FILES_CHANGED` が空 (CI・ビルド/テスト設定 `.github/`, `*config*`, `package.json`, `Cargo.toml`, `go.mod`, `Makefile`, `justfile`, `deno.json` 等の変更なし) | 検証器設定の改変は必ず監査                                                                                                                           |
| 4 | 最後の issue でない (自分以外に open issue が残る。`uc-tracking` の親は数えない)                                                                  | 最後の issue は全観点フル                                                                                                                            |

全条件が真の場合のみ skip 可 (skip は権利であって義務ではない。1 つでも「実行」と出れば actor はスキップできない)。skip 時は JSONL に `event_type: verification_skipped`、`context: {target: "review-adversarial", source: "adversarial_skip", changed_files: $CHANGED, changed_lines: $LINES, criteria_result: {...}}` を記録する (Step 5.6 の未検証項目集約に自動合流させ、沈黙スキップを構造的に不可能にするため)。

**述語を評価するのは初回 fan-out の前の 1 回だけ**で、結果は `gating_decided` に固定する。修正ラウンドで再検査する観点は 4.2d 手順 5 が決める (fatal を出した観点 + guard)。**初回に「実行」と判定された観点が次ラウンドで再検査されないことは「実行 → skip への降格」ではない** — 初回の検査は実施済みで、以降は fatal の解消確認に絞るという意味である。

例外は **初回評価で skip だったフェーズだけ**: 各修正ラウンドの fan-out 直前に述語一式 (`$CHANGED` / `$LINES` / `$TEST_FILE_CHANGED` / `$TEST_CONTENT_CHANGED` / `$CI_FILES_CHANGED` に加え、**mode 決定に要る `$CONSUMABLE_CHANGED` / `$AUTH_CHANGED` も**) を再算出し、skip → 実行 に転じたら起動する (降格は禁止)。mode の判定材料まで揃えないと、起動すると決めた直後に mode を決められない。初回 skip 後の修正でテストが追加・弱体化されるケースを取りこぼさないため。

各 Agent 呼び出しには **「モデル方針」の表どおり `model` を明示**する。呼び出し時の model 指定は agent 定義側のデフォルトより優先され、**未指定にすると親のセッションモデルを継承してしまう** (`agent-spawn-guard` hook が未指定を deny する)。**review-adversarial には PHASE_CONTEXT の path を渡さない** — fresh context 監査のため、`mode` (上記「review-adversarial の mode 決定」で確定した値) / phase_name / phase_start_sha / repo_dir / docs_dir / dev_server / scratch_dir / output_path のみを渡す。**`mode` を渡し忘れると agent 側の既定で `full` に戻り、縮退が無音で効かなくなる** (`claude/agents/review-adversarial.md` の「モード」節)。

##### 4.2d: fatal 判定と修正ラウンド (最大 3)

main は各 agent の結果 JSON を「main のコンテキスト規律」の `jq` 射影で読む。

1. いずれかの agent が結果を返せない → その観点は「未検証」。**パス扱いにせず** `guard_agent_failed` (architecture-guard) / `review_agent_failed` (review-*) でエスカレ停止する。high 0 件と同一視しない。該当するのは次のいずれか:
   - agent がエラー終了した、または 30 分応答しない (implementer と同じ打ち切り基準)
   - `output_path` の JSON が実在しない、`jq` でパースできない
   - **スキーマ不適合**: architecture-guard は `ok` が読めない、review-* は `findings` が配列として読めない
   - architecture-guard が `skip_reason: "diff_command_failed"` を返した (差分が取れておらず検査が成立していない。**修正ラウンドに乗せない** — 実装を直しても解消しない性質のため)
   - **architecture-guard の `unchecked_files` が非空** (差分の一部を見ていない。「違反 0 件」と「そのファイルを見ていない」を区別するための値なので、非空を `ok: true` と同一視しない)
   - **architecture-guard が `skip_reason: "no_layer_convention"` を返した**場合は**未検証にしない**。DESIGN 文書にも慣例にもレイヤ構造が無いプロジェクトで誤検知を出さないための意図的な素通りで、`checked_files: 0, ok: true` が正しい結果である (guard 側の規定と揃える)。ただし `verification_skipped` (source: `no_layer_convention`) には記録し、「レイヤ境界を検査していない run」であることを Step 5.6 の集約から読めるようにする
   - **`exemptions_path` を渡した agent (review-tdd と review-adversarial の 2 つだけ) について、`jq 'length' "$SCRATCH_DIR/self-exemptions.json"` で取り直した件数より `adjudicated` が少ない** (免除の裁定が実行されていない。裁定は実装者が「検証しない」と宣言した項目を第三者が裁く仕掛けで、実行を検証しないと自己申告のまま通る)。**`exemptions_path` を渡していない agent (architecture-guard / review-quality / review-product-readiness) にこの条件を適用しない** — 渡していないものを裁定できるはずがなく、免除が 1 件でもあるフェーズが全て偽の停止になる

   **review-product-readiness の `dev_server_unavailable` は未検証扱いにするが、修正ラウンドには乗せない。** 環境起因で実装者が直せる問題ではないため (architecture-guard の `diff_command_failed` と同じ性質)。そのフェーズの product-readiness を `verification_skipped` (source: `dev_server_unavailable`) として記録し、他の観点の fatal 判定は通常どおり続ける。

   **agent の失敗は「一過性」と「決定的」を分けて扱う。** タイムアウト・JSON 破損・一時的なエラー終了は `in-progress` のまま再実行で解決しうるが、**`TOO_MANY_FILES` / `NO_DESIGN_DOCS` / スキーマ不適合 / `diff_command_failed` / `unchecked_files` 非空 / `adjudicated` 不足 は決定的**で、同じ入力なら何度再実行しても同じ結果になる。決定的な失敗と、同一フェーズで同じ agent が 2 回続けて失敗した場合は **`needs-human` に振り分ける** (「エスカレ停止時の挙動」の表)。決定的な失敗を「再実行で解決しうる」に入れると、人間に渡る経路が無いまま同じ停止を繰り返す
2. **fatal の定義**: review-* の severity: high、または architecture-guard の `violations` のうち severity が high / medium のもの。fatal 0 件 → 4.2e へ。**ただし review-adversarial の `test_weakened` / `vacuous_assertion` / `skip_added` / `tautological_test` は confidence と severity に関わらず fatal に数えない** — 手順 7 のトレース確認・エスカレ経路が優先する (実装者自身に弱体化を直させないため)。**この 4 つの rule 名は `claude/agents/review-adversarial.md` の `rule` enum を正とし、本手順・手順 7・「関連スキル / agent」節・`claude/agents/dev-impl-implementer.md` の 4 箇所を同じ集合に保つ** (どこか 1 つに漏れると、その rule だけが実装者に直させる経路へ流れて必ず空回りする)。

   **main は agent が付けた severity を変更しない (昇格も降格もしない)。** 修正ラウンドを起こすのは上記の fatal だけで、medium / low を「重要そうだから」と high 扱いにして新ラウンドを起こすことはしない。過小評価は agent 側の severity 基準 (各 agent 定義の「severity の判定基準」節 (節を持たない agent は該当する判定記述)) を直して解決する問題であり、実行時の裁量で埋めるとラウンド数が判定基準なしに増える (実測で 9 ラウンド中 2 ラウンド以上が裁量昇格のみで起動していた)。

   **medium の「相乗り」は行わない。** implementer は review-* の `findings[]` を high だけ、architecture-guard の `violations[]` を high/medium 直す規約なので、review-* の medium を渡しても no-op になる (guard の medium は fatal の定義に入っているので通常の経路で直る)。medium は `review_low` として記録し、Step 6 のサマリと HTML レポートに残す。
3. fatal あり → `phase_fix_round += 1` する。**この時点で `phase_fix_round > 3` なら fix を起動せず `phase_fix_exceeded` でエスカレ停止**する (JSONL の context に guard 由来 / review 由来の内訳を残す)。

   **続けて JSONL に `event_type: fix_dispatch` を記録する** (context は logging.md の規定)。`spawn` と同じく**起動する前に書く**。このイベントは 2 箇所が読む load-bearing な記録である: Step 0 の再入で `phase_fix_round` を復元する唯一のソースであり、ラウンド 2 以降の implementer へ渡す「過去ラウンドの経過」の材料でもある (references/phase-execution.md の `ROUND2_PLUS_BRIEF`)。

   続けて、fixer に渡す findings ファイルを**観点ごとに 1 本ずつ** `jq` で作る (main は findings 本文を読まず、`jq` の出力をファイルへ直行させる):

   ```bash
   # fatal を出した観点: high + 相乗りの medium を残す。ただし手順 7 の 4 rule は除く
   #   (実装者に直させない規定なので、渡すと必ず test_weakening_suspected で停止して 1 ラウンド無駄になる)
   jq '{ok, dimension, mode, findings: [.findings[]
        | select((.rule | test("^(test_weakened|vacuous_assertion|skip_added|tautological_test)$")) | not)
        | select(.severity=="high" or .severity=="medium")]}' \
     "$SCRATCH_DIR/review-<観点>-r${ROUND}.json" > "$SCRATCH_DIR/fatal-<観点>-r${ROUND}.json"

   # fatal を出していない観点の medium は **fixer に渡さない**。implementer は review-* の
   # findings[] を high しか直さない規約 (claude/agents/dev-impl-implementer.md) なので、
   # 渡しても構造的に no-op になり、spawn 予算だけを消費する。medium は review_low に記録して残す
   ```

   architecture-guard の分は**キーを `violations` のまま出す** (`jq '{ok, violations: [.violations[] | select(.severity=="high" or .severity=="medium")]}'`)。`findings` に付け替えてはならない — implementer は `violations[]` を high/medium、`findings[]` を high だけ拾う規約なので (`claude/agents/dev-impl-implementer.md`)、付け替えると **guard の medium が誰にも直されず毎ラウンド再検出される**。**これらのファイルの生成者はこの手順だけ**で、4.2e 手順 4 の突合はこれらを spawn の成果物として数えない (main が書いたものなので)
4. **`mode: fix` の `dev-impl-implementer` を起動**する。**モデルはラウンド 1 が `opus`、ラウンド 2 以降が `fable`** (上記「修正ラウンドのモデル昇格」)。ラウンド 2 以降は指示文に「指摘箇所を局所的に塞ぐ前に、その箇所が属する不変条件を洗い出し、同じ族のエッジケースがまとめて閉じるかを確認せよ。族として閉じられない残りは報告の `open_questions` に明記せよ」を加える。渡すのは `findings_paths` (fatal を含む結果 JSON の絶対パスの配列) / `phase_context_path` / `repo_dir` / `report_path`。main は findings の本文を読まないし、修正内容を指示しない (fixer が JSON を自分で Read する)。**fixer が直す対象は「review-* の high」と「architecture-guard の high/medium」**で、fatal の定義と一致させてある (guard の medium が誰にも直されず空回りするのを防ぐため)。**報告を受けたら 4.2a と同じく main がコミットする** (「ラウンドごとのコミット」)
5. 修正完了後、**再 fan-out は「fatal を出した観点 + architecture-guard」に絞って 4.2c に戻る**。目的は「前回の fatal が fix 差分で解消したか」の検証であって、フェーズ全体の再レビューではない (毎ラウンド全観点を回すと観点ごとに新しい指摘が出続け、ラウンドが上限まで消化される。実測でフェーズあたり平均 2.25 ラウンド)。起動する観点は**原則として `gating_decided` に記録した `gating_set` の部分集合**とする (`architecture-guard` は gating 対象外で常に実行するため、この判定の対象に含めない)。下記 2 つの場合に限り集合外の review-adversarial を追加してよく、追加したときは `gating_decided` を追記して事後に正当な例外だと分かるようにする:

   - **fix がテストに触れた場合は review-adversarial を必ず追加する** (`mode: weakening_only` で足りる)。判定は**その fix のコミット差分にテストファイルが含まれるか**を見るだけでよい (ラウンドごとにコミットしているので、fix 差分を切り出す SHA が存在する):

     ```bash
     # fix 起動の直前に控えた SHA と比較する。HEAD~1 を使わない —
     # (a) fix の差分が空でコミットが打たれなかった場合、HEAD~1..HEAD は 1 つ前のラウンドを指して誤判定する
     # (b) そのコミットがリポジトリの最初のコミットだと HEAD~1 が解決できずコマンド自体が失敗する
     BEFORE_FIX=$(git -C "$REPO_DIR" rev-parse HEAD)   # ← mode: fix を起動する直前に取る
     # ... fix の完了とコミット ...
     if [ "$BEFORE_FIX" = "$(git -C "$REPO_DIR" rev-parse HEAD)" ]; then
       echo "fix はコミットを生まなかった (差分なし)。テストには触れていない"
     else
       git -C "$REPO_DIR" diff --name-only "$BEFORE_FIX" HEAD \
         | rg '(_test\.(go|rs|py)|\.test\.|\.spec\.|_spec\.|__tests__/|(^|/)tests?/|(^|/)test_[^/]*\.py)'
     fi
     ```

     Rust のインラインテスト (`#[cfg(test)]`) はこのファイル名パターンで捕まらないので、Rust プロジェクトでは同じ差分に対して `git -C "$REPO_DIR" diff -U0 "$BEFORE_FIX" HEAD -- '*.rs' | rg '^\+.*#\[cfg\(test\)\]'` も見る (`HEAD~1` を使わない理由は上と同じ)。修正の過程でテストが弱体化されるのはレンズ B が守る対象そのもので、ここに穴を作らない。既に adversarial が `full` で起動していたフェーズでは `full` のまま再実行する
   **`gating_decided` を追記するときは `gating_set` を全体で再掲する** (追加分だけを書かない)。同一 phase に複数あるときは**最新の 1 件を採る**規定 (logging.md) なので、追加分だけの部分集合を書くと、以後その部分集合しか起動できなくなり、初回に決まった観点が無音で落ちる。

   - review-adversarial のスキップ述語が「skip → 実行」に転じた場合 (既存規定どおり、降格は禁止)。**この転換で起動するときの `mode` は、その時点で「review-adversarial の mode 決定」表を評価して決める** (初回に skip したフェーズは mode を確定しておらず `adversarial_mode: "skipped"` しか記録が無いため)。決まった値で `gating_decided` を追記する

   「修正が別観点を壊す」リスクは、最後の issue の全観点フル検査と Step 5 の第三者監査 (`review-spec-compliance`) で受け止める
6. 修正中に `design_overview_break` を検知 → 即エスカレ停止 (commit しない)
7. review-adversarial の `test_weakened` / `vacuous_assertion` / `skip_added` / `tautological_test` は **severity と confidence に関わらず**修正ラウンドに乗せない (これらは medium で出ることが多く、rule 名だけで判定する。severity を条件にすると medium の弱体化が黙って通る) (`dev-impl-implementer` 側も rule 名だけで無条件に `test_weakening_suspected` で停止する規約なので、confidence で線を引くと fix を起動しても必ず空振りして 1 ラウンド無駄になる)。弱体化を実装者自身に直させると骨抜きの温床になるため、4.2e と同じトレース確認 (TODO.md / DESIGN_DETAIL_APP.md に意図的な変更としてトレースできるか) を main が行い、トレース不能なら `test_weakening_detected` でエスカレ停止する。`dev-impl-implementer` 側もこれらの finding を渡されたら修正せず `test_weakening_suspected` で停止する規約になっている (二重の歯止め)
8. **作業ツリーの汚染は、agent の自己申告ではなく main が検出する** (4.2c の検査後ブロック)。`working_tree_polluted` の報告が無くても必ず `git status --porcelain` で突合する。実装はラウンドごとにコミット済みで fan-out 直前のツリーは clean なので、**検査 agent が書き換えたまま戻さなければ必ず変更として現れる**。

   **この検出が捕まえるのは「戻し忘れた汚染」だけである。** 攻撃の途中で変異させ、検査を終える前に正しく戻した場合は `status` が clean に戻るので検出できない — その間に別の観点が変異後のコードを読んでいても分からない。この一過性の窓を構造的に閉じるのが「変異を伴う観点と実行環境を共有する観点を同じ fan-out に入れない」規定 (下記) で、検出はあくまで二重の歯止めである。

   差分が出たら `git restore <該当ファイル>` で直前のコミットの状態に戻す。**実装は既に履歴に入っているので、この復元で失われるのは agent が加えた変異だけである** (フェーズ中に何もコミットしない設計では、実装と変異が同じ未コミット差分に混ざるため機械復元ができなかった)。復元したら JSONL に `working_tree_polluted` を記録する。

   **汚染を検出したラウンドの検査結果は fatal の有無に関わらず全て破棄し、同じ観点で 1 回やり直す。** 並列に走った他の観点が変異後のコードを読んでいた可能性があり、そのラウンドの結果は「fatal なし」も「fatal あり」も信用できない — 前者をそのまま通せば検査していないコードをコミットへ通すことになり、後者をそのまま修正ラウンドへ載せれば**変異が原因の偽の fatal を実装者に直させる**ことになる (実在しない不具合を追わせるので必ず空回りする)。やり直しの spawn は `phase_spawns` に計上するが `phase_fix_round` は進めない (修正ラウンドではないため)。**同一フェーズで 2 回目の汚染を検出したらエスカレ停止する** (`working_tree_polluted`。並列実行と変異が構造的に噛み合っていない状態なので、3 回目を試す価値が無い)

severity: low/medium の findings は修正せず JSONL に `event_type: review_low` で記録する。**転記は `jq` で結果 JSON から JSONL へ直接流し込み、`message` を含む本文も入れる** — HTML レポートのレビュー残課題セクションが `message` を表示するため、落とすと「どのファイルの何行目か」しか残らず読めない。**main のコンテキスト規律に反しない**のは、`jq` の出力を標準出力に流さずファイルへ直行させるから (main が読むのは射影した `{severity, rule, file, line}` だけで、本文は main を経由せずに JSONL へ入る)。

##### 4.2e: テストゲート + コミット (main)

コミット前に **main が `full_test_command` を Bash で直接実行し、exit code 0 を確認する** (自己申告ではなく実行結果で判定)。implementer にはフェーズスコープのテストしか実行させていないので、全体スイートの実行はここが初回になる。

全体スイートを main が実行する理由は、main の cache write が 1 時間 TTL で長時間の実行に耐えるため (subagent は 5 分 TTL なので、長いスイートを subagent 内で回すと自分のコンテキストを失効させる)。ただし **Bash の 600 秒上限は主体によらず効く** (実測: `swift test` が 608〜614 秒で上限に張り付いた事例が失効 29 件の主因)。`full_test_command` が 600 秒を超えるプロジェクトでは `run_in_background: true` で起動してポーリングする。**タイムアウトした実行は「未検証」として `verification_skipped` に記録し、成功扱いにしない**。

- 失敗 → `test_gate_retry += 1` し、失敗出力 (末尾 30 行) を 4.2a の「fix ブリーフ」と同じスキーマで `<SCRATCH_DIR>/test-failure-<test_gate_retry>.json` に書いて `mode: fix` の implementer に渡す (main は実装差分を読まない)。`test_gate_retry > 3` で `tests_failing_before_commit` でエスカレ停止。**`test_gate_retry` は `phase_fix_round` とは別カウンタ**にする (検査ラウンドを使い切ったフェーズでもテストゲートの再試行が残るように)。この経路の implementer 起動も**通常のラウンドと同じ扱い**にする:
  - `report_path` は `<SCRATCH_DIR>/impl-report-testgate-<test_gate_retry>.json` (修正ラウンドの `impl-report-fix-<round>.json` と衝突させない。カウンタが別なので番号が重なる)。**`spawn` 記録の `context.round` には文字列 `"tg<test_gate_retry>"` を入れる** (4.2e 手順 4 の突合が成果物のファイル名と 1:1 で対応するようにするため)
  - `model` は `test_gate_retry` が 1 なら `opus`、2 以降は `fable` (「修正ラウンドのモデル昇格」と同じ考え方)
  - 起動の直前に `spawn` を記録し、**報告を受けたら「ラウンドごとのコミット」に従ってコミットする** (コミットしないと作業ツリーが非クリーンなまま次の手順へ進み、4.2c の clean 前提と 4.2d 手順 8 の汚染検知がどちらも壊れる)
  - fix がテストに触れた場合は、修正ラウンドと同じく review-adversarial (`mode: weakening_only` 以上) を 1 回起動してから最終コミットへ進む

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

続けて**テスト弱体化の機械検知**を行う (reward hacking 対策。review-tdd の LLM 判定に頼らず、編集権限の外で機械判定する)。検知コマンド (テストファイル削除の検出 + skip/only/ignore 追加の検出) は [references/phase-execution.md](./references/phase-execution.md) の `## 4.2e: テスト弱体化検知コマンド` 節を Read してから実行する (この節を読まず近似コマンドで代替すると、言語別 skip/ignore パターンの見落としにより test_weakening 検知が漏れるリスクがある)。

ヒットした場合、その削除・skip が TODO.md / DESIGN_DETAIL_APP.md にトレースできる意図的な変更 (設計変更で仕様ごと削除等) か確認し、トレースできなければ `test_weakening_detected` でエスカレ停止する (パス扱いしない)。

緑を確認したら、以下を **main が**この順で行う:

1. **TODO.md の該当フェーズを `- [x]` に更新する** (issue タイトルの識別子で `### フェーズ<識別子>:` 見出しを引き当てる)。**直後の手順 2 のフェーズ最終コミットに含める** (チェックだけ先に入ってコミットが無い状態を作らない。Step 0 手順 3 の再入突合はこの前提で「チェック済みだがコミット無し = 未完了」と判定する)
2. **フェーズ最終コミットを打つ**。実装はラウンドごとに入っているので、このコミットが載せるのは TODO.md の更新と、どのラウンドにも含まれなかった残りだけになる。
   - subject は `<emoji> <type>: [phase-<識別子>][STRUCTURAL|BEHAVIORAL] <要約>`。**`[STRUCTURAL]` / `[BEHAVIORAL]` を付けるのはこのコミットだけ**で、フェーズ全体の動作変更の有無を表す (途中のラウンドコミットには付けない → 「ラウンドごとのコミット」)
   - 本文に `Fixes #<issue 番号>` を入れる
   - **`rules/core/commit.md` の条件をフェーズ単位で満たすのはこのコミットである。** 本ステップ冒頭の全体スイートと DoD がここまでに緑になっているためで、途中で全体スイートが落ちた場合はその修正が新しいラウンドのコミットとして積まれ、緑になってから最終コミットを打つ
   - **コミットは必ず main が行う** — 形式を機械検証する commit-msg-guard hook は親にしか効かないため。ただし hook が実際に検証するのは `$GHQ_ROOT/github.com/skanehira/` 配下のリポジトリで作業しているときだけで、それ以外では fail-open で素通りする。push はしない (ユーザ手動)
3. **RUN_FACTS.md を更新する** (書式と規則は [references/phase-context.md](./references/phase-context.md) の `## RUN_FACTS.md`)。implementer 報告の `report_path` から `jq` で引いて「完了フェーズの成果物」「累積 design_decisions」「既知の落とし穴」に追記する。**この更新がフェーズ間の文脈再注入を代替する**ので省略しない (省略すると次フェーズの implementer がプロジェクトの作り方を探索し直す)。追記後にファイルサイズを測り、**4096 バイトを超えていたら最新 3 フェーズ以外の「完了フェーズの成果物」行を要約に畳む**。JSONL に `event_type: run_facts_updated` (context に `sections` / `bytes`) を記録する
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
5. **JSONL に `event_type: impl_done` を記録する** (context: `phase` / `summary` / `commit_sha` / `phase_fix_round` / `phase_spawns` / `review_outputs`)。これが issue 完了の唯一のイベントで、`prev_phase_summary` (次フェーズの PHASE_CONTEXT) と HTML レポートのフェーズタイムラインがこれを読む
6. implementer 報告の `verification_skipped` / `design_decisions` / `open_questions` / `spec_lookups` / `self_review` を `report_path` から `jq` で JSONL に転記する (`verification_skipped` は Step 5.6 の未検証項目集約に合流する)。**転記は 1 回の Bash 実行で全件を流し込む** — コマンドは [references/phase-execution.md](./references/phase-execution.md) の `## 4.2e: implementer 報告の JSONL 一括転記` 節を使う (項目ごとに Bash を呼ぶと main の往復がフェーズあたり 30 回近く増える)
7. **当該 issue を close する** (`gh issue close <N> --comment "DoD がすべて通過したため close する"`)
8. **親 issue の自動 close sweep** を回す (下記)

**手順 7 を 8 より後ろに回さない。** ある UC の最後の子を閉じた後に sweep を回さないと、その親を閉じる契機が二度と来ない (それ以前の子なら次の子の close で sweep が再走して自己修復する)。親は Step 1 / Step 2 / 4.2c のいずれでも `uc-tracking` として除外されるため、open のまま残っても誰も気付かない。

**親 issue の自動 close sweep**

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

##### フェーズ内エスカレ条件まとめ

| 条件                                                                                                             | reason                                       |
| ---------------------------------------------------------------------------------------------------------------- | -------------------------------------------- |
| 修正ラウンド 3 回でも fatal 残存 (guard 違反 / review high のいずれも)                                           | `phase_fix_exceeded`                         |
| 検査 agent が結果を返せない (未検証をパス扱いにしない)                                                           | `guard_agent_failed` / `review_agent_failed` |
| implementer の報告が読めない / 実装が実在しない (`files_changed` が空) が 3 回続いた                             | `phase_fix_exceeded` (原因は `impl_report_invalid`)  |
| `phase_spawns > 33` または `run_spawns > run_spawns_budget` (Step 3 のカウンタ規定)                              | `spawn_budget_exceeded`                      |
| テストゲート 3 回不通過                                                                                          | `tests_failing_before_commit`                |
| 自己免除の抽出が成立しない (report はあるが配列が得られない)                                                     | `exemptions_extract_failed`                  |
| `design_overview_break` 検知 (実装・修正中いずれでも、commit 前に停止)                                           | `design_overview_break` (P3)                 |
| テストファイル削除 / skip 追加 / assertion の弱体化・空虚化が設計にトレースできない (4.2e の機械検知 / 4.2c の review-adversarial 検知 / implementer の `test_weakening_suspected` 報告のいずれも) | `test_weakening_detected`                    |

#### Step 4.6: 設計乖離の判定 (P1 / P2 / P3)

implementer 報告 (`mode: implement` / `mode: fix` 双方) の `deviation_signals` を main が `report_path` から `jq` で集め、P 値に分類する。**implementer は自分で JSONL を書けないので、この転記が Step 4.6 の唯一の入力になる** (逐次モードでも main は実装過程を見ていない)。design 整合の判定は review findings の `dimension: "quality"` かつ `rule: "design_mismatch"` 系エントリも使う。

**シグナル元と分類対応**:

| シグナル元                                                                          | type                    | 分類                | 対処                                                           |
| ----------------------------------------------------------------------------------- | ----------------------- | ------------------- | -------------------------------------------------------------- |
| implementer 報告                                                                    | `todo_minor`            | P1 (TODO 軽微)      | 下記「P1 動的修正」へ                                          |
| implementer 報告 / review-quality の design 整合 finding (severity: medium)         | `design_detail_gap`     | P2 (詳細設計の不足) | 下記「P2 動的修正」へ                                          |
| implementer 報告の `design_overview_break`                                          | `design_overview_break` | P3 (概要設計の破綻) | エスカレ停止 (Step 4.2 内で検知した時点で commit 前に停止済み) |

**review-quality の `design_mismatch` が high の場合は、4.2d の fatal として修正ラウンドで処理する** (review-* の high は fatal の定義に入るため)。**同じ finding を 4.6 で P3 のエスカレ停止にも回さない** — 両方に載せると「修正ラウンドを起動する」と「即座に停止する」という排他的な処方が同時に成立してしまう。**設計そのものが破綻しているという判断は implementer の `deviation_signals` の `design_overview_break` からのみ入る** (実装しようとして初めて分かる性質のもので、差分を外から見るレビューが単独で決めることではない)。修正ラウンドで直せなかった high は通常どおり `phase_fix_exceeded` で停止し、そこで人間が設計の問題かを判断する。

**シグナル無しの場合**: Step 2 に戻って次の issue を選ぶ。

**集約のしかた**: 同一 phase 内で同種シグナルが複数回記録された場合、`scope` + `what` で重複排除してから処理 (1 件のシグナルとして扱う)。

##### P1 動的修正

1. `p1_fixes_in_phase += 1`。`p1_fixes_in_phase > 2` なら本シグナルを P2 (design_detail_gap) として扱い、P2 動的修正フローに切り替える (以降のステップは実行しない)
2. TODO.md の該当フェーズ周辺を Edit
3. ログに「P1 fix: <変更内容の 1 行サマリ>」を残す (JSONL は `event_type: p1_fix`)
4. **当該フェーズにタスクを足す場合は、TODO.md だけでなく issue 本文も更新する。** Step 4.6 は 4.2e で issue を close した**後**に走るので、その issue は既に closed であり、**実装指示の実体は TODO.md ではなく issue 本文である** (PHASE_CONTEXT の `phase_tasks` は `gh issue view` から作る)。TODO.md だけ直しても実装器には届かない。手順は `gh issue reopen <N>` → `gh issue edit <N> --body-file` で `## 実装タスク` に追記 → ラベルを `ready` に戻す → Step 2 の抽出をやり直す。**フェーズを跨ぐ追加なら新フェーズを TODO.md に挿入し、続けて「新フェーズの issue 化」を実行する** (下記の共通手順。close 済み issue を再利用するより見通しがよいので、迷ったらこちら)。挿入する見出しには `<!-- deps: ... -->` と `<!-- goals: ... -->` を必ず付け、**`docs/USECASES.md` がある構成では `<!-- ucs: ... -->` も付ける**。メタ情報 5 項目 (ゴール / DoD / 参照 docs / 変更想定ファイル / 非スコープ) も書く (判定基準は `../dev-spec/references/todo-generation.md` の「フェーズ依存の宣言」「対応ゴールの宣言」「対応ユースケースの宣言」「各フェーズが持つメタ情報」)。`ucs` を落とすと、次に `/dev-spec` を再実行したときフェーズ 10.5 の監査が `phase_meta_missing` (high) で差し戻す
5. **編集した `docs/TODO.md` をコミットする** (下記「動的修正のコミット」)

##### 動的修正のコミット

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

##### P2 動的修正

1. `p2_fixes_total += 1`。**回数では止めない** — 詳細設計の不足は実装しないと分からないことが多く、回数が増えること自体は異常ではない。代わりに**何をどう変えたかを後から追える形で残す**責任を負う (手順 6 のコミット / 手順 7 の JSONL / Step 6 の完了サマリ / HTML レポートのセクション 4 の 4 つが揃って初めて「確認できる」状態になる)。設計の前提そのものが崩れている場合は回数に関わらず P3 (`design_overview_break`) として停止する — これは回数ではなくシグナルの種類で判定する
2. DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md の該当側 (境界基準: 変更に IaC・コンソール操作・環境設定変更が要るなら INFRA) のセクションを Edit
3. **受入基準ガード**: Edit 直後に goals_sha を再計算 (Step 1 のコマンド) し、承認スタンプの値と照合する。不一致 = 受入基準 (ゴール / 検証手順行) を触った P2 であり、実装者による自己適用は禁止。Edit を revert せず `acceptance_criteria_change` でエスカレ停止する (「受入基準の変更が必要になった。dev-spec フェーズ 9 → 11 で再承認せよ」と通知。実装ガイド・スキーマ等の追記はハッシュ対象外なので通過する)
4. **再生成の前にフェーズ見出しのスナップショットを取る** (再生成後では「前」の状態が失われ、増えたフェーズを特定できない)。そのうえで `../dev-spec/references/todo-generation.md` を Read し、その手順に従ってメインループで TODO.md を再生成する (ステップ 2〜3 を既存の TODO.md に対して適用し、完了済みフェーズのチェック状態は保つ)。**フェーズ見出しの `deps` / `goals` / (USECASES.md がある構成では) `ucs` の宣言を落とさない** — 再生成で `ucs` が消えると、次の `/dev-spec` 実行でフェーズ 12.0 がフラット判定に落ち、親 issue が作られなくなる

   ```bash
   rg -o '^### フェーズ[^:]*' docs/TODO.md | sort -u > $RUN_DIR/phases-before.txt   # 再生成の前に取る
   # ... TODO.md を再生成 ...
   rg -o '^### フェーズ[^:]*' docs/TODO.md | sort -u > $RUN_DIR/phases-after.txt
   comm -13 $RUN_DIR/phases-before.txt $RUN_DIR/phases-after.txt                        # 増えたフェーズ
   ```

5. **増えたフェーズがあれば、その各件に「新フェーズの issue 化」を実行する** (下記の共通手順)。closed の issue はそのまま完了扱いを維持する
6. **編集した設計書 (`DESIGN_DETAIL_APP.md` / `_INFRA.md`) と `docs/TODO.md` をコミットする** (上記「動的修正のコミット」)
7. ログに「P2 fix: <更新セクション>」を残す (JSONL は `event_type: p2_fix`)。**`context` には `section` (更新したセクション名) / `what` (何をどう変えたか 1 行) / `why` (実装から判明した事実) / `commit_sha` (手順 6 のコミット) / `p2_fixes_total` (この時点の通算) を入れる** — 停止しない代わりに、ユーザーが後から「設計のどこが実装に合わせて書き換わったか」を追える唯一の記録になる
8. 当該フェーズの再実行か次フェーズへ進むかを判定: 再生成後の TODO.md で **当該フェーズ内に新規の未完了タスク (`- [ ]`) が追加されていれば、P1 手順 4 と同じく issue を reopen して本文の `## 実装タスク` を更新し、`ready` に戻してから Step 2 の抽出をやり直す** (issue が既に closed で、実装指示の実体は issue 本文であるため。TODO.md だけ直しても実装器には届かない)。既存タスクが全て完了済みのまま (詳細設計の記述を補っただけで実装側の追加作業が無い) なら次フェーズへ進む
9. ユーザに対する通知は「DESIGN_DETAIL_APP.md (または _INFRA.md) / TODO.md を更新しました (詳細はログ参照)」程度 (dev-impl は止まらない)

##### 新フェーズの issue 化 (P1 / P2 / Step 5.5 の共通手順)

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
3. **`run_spawns_budget` を `max(現在値, run_spawns + その時点の open issue 数 (`uc-tracking` を除く) × 8)` で再計算する** (Step 3 のカウンタ規定)。issue が増えたのに上限が据え置きだと、正当な実装の途中で `spawn_budget_exceeded` に当たる。**手順 4 の記録より前に行う** (再計算した値を `phase_added` に載せるため)
4. **JSONL に `event_type: phase_added` を記録する** (`context`: `phase` / `issue_number` / `parent_number` (紐付けた親。フラット構成なら省略) / `origin` (`p1` / `p2` / `goal_unmet`) / `run_spawns_budget` (手順 3 で再計算した値))
5. **Step 2 の issue 抽出を再実行**して、追加したフェーズを着手対象に含める

**紐付けの差集合**

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

##### P3 検出時

エスカレ停止 (後述の「エスカレ停止時の挙動」へ)。

シグナル処理が終わったら Step 2 に戻って次の issue を選ぶ (コミットは Step 4.2e で実行済み)。

### Step 5: ゴール達成判定 + 未達対応ループ

Step 4 のフェーズループを抜けた時点で「全 TODO 消化」は完了している。ここから DESIGN.md のゴールが**実際に達成されているか**を機械判定する。

**まず 4.2e の「親 issue の自動 close sweep」を無条件で 1 回回す。** 4.2e の sweep は子を close した直後にしか走らないため、前回の run が最後の子を close した後 sweep の前に落ちた場合や、人間が最後の子を手で閉じた場合は、Step 1 が `OPEN=0` を見て Step 5 へ直行し、閉じ忘れた親を誰も閉じない。ここで 1 回流せばその取りこぼしが回収できる (冪等なので閉じるべき親が無ければ何もしない)。

#### Step 5.1: ゴール一覧抽出

DESIGN.md の「ゴール」セクションを Read してゴール一覧を抽出 (例: `G1, G2, ...`)。抽出コマンド例: `rg -n '^- G[0-9]+:|^G[0-9]+:' docs/DESIGN.md`。

ゴール定義は Step 1 の構造ゲートで存在を保証済み。万一この時点で抽出できない場合は `goals_missing` でエスカレ停止する (**skip しない** — ゴール判定を省くと完了条件が「全 TODO 消化」という作業量ベースの自己申告になるため)。

#### Step 5.2: 第三者監査の並列起動

自動系ゴールの検証は**メインループが自分で実行しない** (実装者本人による自己判定を避ける)。`PRODUCT_MODE=cli` の場合は `review-spec-compliance` (mode: post-impl、G_E2E も自動系ゴールとして実行) を単独起動する。`webapp` / `unknown` の場合は `review-spec-compliance` と `review-product-readiness` (G_E2E) を**同一メッセージ内の複数 Agent tool_use として並列起動**する。起動する agent はすべて `model: opus` を明示する。起動コードは [references/goal-audit.md](./references/goal-audit.md) の `## 5.2: 監査 agent の並列起動` 節を Read してから実行する (この節を読まず近似の prompt で起動すると、`docs は自分で全文 Read すること` 等の指示や `output_path` / `holdout_enabled` / `product_mode` の欠落により第三者監査の独立性が落ちる)。

**G_E2E の判定**:
- **webapp / unknown**: review-product-readiness が判定。**まず `rule: dev_server_unavailable` が無いことを確認する** — あれば実機を 1 度も触れていないので、high が 0 件でも **achieved にしてはならない**。`verification_skipped` (source: `dev_server_unavailable`) を記録して手動 pending に落とす (この rule は medium で返るため、severity だけを見る判定では素通りする)。dev サーバが動いたうえでナビ系 findings (`nav_unreachable` 等) の severity: high が 0 件 → achieved、1 件以上 → unmet。**dev_server が推定できない場合も判定不能** = `verification_skipped` を記録して手動 pending に落とす (achieved 扱いにしない)
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
| `holdout_test_failed` (high)                                                 | 監査 agent が TODO.md に無いエッジケースを生成して落としたもの。**未達対応ループへ回す** (`holdout_enabled` を有効にした run でのみ出る。実装の穴なので直せる) |
| medium / low のみ                                                            | JSONL 記録 + POST_MVP.md へ転記 (Step 5.6)。status `partial` 判定に反映                                                                         |
| agent エラー / JSON 解釈不能                                                 | `review_agent_failed` でエスカレ停止 (未検証をパス扱いにしない)                                                                                 |

#### Step 5.4: 結果分岐

**上から順に評価し、最初に当てはまった行の対処を採る** (複数に当てはまりうるため、順序が意味を持つ):

| # | 状況                                                    | 対処                   |
| - | ------------------------------------------------------- | ---------------------- |
| 1 | `verification_tampered` が 1 件以上                     | 即エスカレ停止 (5.3 の表。修正ループなし) |
| 2 | unmet ゴール、または**修正可能な** high findings (`unimplemented_api` / `schema_drift` / `infra_missing` / `goal_result_mismatch` / `holdout_test_failed`) が 1 件以上 | Step 5.5 の未達対応ループへ |
| 3 | 残る high が**修正対象外のものだけ** (`vacuous_verification`) で、ゴールは achieved か手動 pending | **Step 6 へ**。当該ゴールを手動 pending に落とし、`status` は `partial`。完了サマリに人間確認要求として明示する |
| 4 | 全ゴール achieved (or 手動 pending のみ) かつ high 0 件 | Step 6 へ (完了サマリ、`status` は 5.6 の判定に従う) |

**3 行目を落とさない。** `vacuous_verification` は 5.3 で「自動修正させない = 未達対応ループに載せない」と定めているので、これが残ったまま「high が 0 件でない」を理由に 2 行目へ送ると、**直しようのない finding で `goal_loop` を空に消費し、3 周で必ず停止する**。

#### Step 5.5: 未達対応ループ

`goal_loop += 1`。`goal_loop > 2` なら P3 として停止 (エスカレ)。

それ以外:

1. 未達ゴール・修正可能な high finding (`unimplemented_api` / `schema_drift` / `infra_missing` / `holdout_test_failed`) ごとに **`docs/TODO.md` にフェーズを追記し、Step 4.6 の「新フェーズの issue 化」を実行する** (issue 作成・親への紐付け・`phase_added` の記録・Step 2 の再抽出まで、手順はすべてそこに集約してある)。本ステップ固有の中身は次のとおり:

   - **`## DoD`**: 未達を検出した検証コマンドをそのまま入れる
   - **`## 対応ゴール`**: その未達ゴールの識別子を書く
   - **フェーズ内容**: 「G2 が未達。検証コマンド `<cmd>` が exit code != 0。失敗ログ: `<evidence>`。これを満たす実装を追加する」(findings 由来は `message` + `fix_proposal` を使う)
   - **`<!-- ucs: ... -->` の決め方**: **未達ゴール (`G<n>`) から UC への対応表はどの成果物にも無い**ので TODO.md から引く — そのゴールを `goals` に含むフェーズの `ucs` を採り、複数あって一致しなければ `none` (横断) に倒す

   TODO.md への追記を省かない (issue の生成元と実体が食い違わないようにするため。判定基準は `../dev-spec/references/todo-generation.md` の「各フェーズが持つメタ情報」)。

2. Step 4 のフェーズループに戻る (新規追加フェーズだけが pending)
3. 完了後、Step 5.1 に戻って再判定 (Step 5.2 の監査 agent も**再起動**する。前回結果の使い回しは不可 — 修正が別の乖離を生んでいないかを再監査する)

手動 pending ゴールは Step 6 サマリで「人間確認必要」として明示する (dev-impl は判定せず保留)。

#### Step 5.6: POST_MVP.md の更新と status 判定

Step 5 のゴール判定後、`docs/POST_MVP.md` に **「UI/UX gap」セクション**を書き出す。**`PRODUCT_MODE=cli` の場合は本セクションを省略する** (status 判定の「UI/UX gap 全項目空」条件は自動的に満たされる)。`webapp` では常に書き出す。`unknown` では dev_server 推定が真の場合のみ書き出す (推定できなければ cli と同様に省略)。

##### UI/UX gap セクションの内容

セクションの必須項目テンプレート (未実装画面 / 未実装ナビ経路 / frontend-design 未適用フラグ / a11y 未対応項目 / 視覚的回帰参照) は [references/post-mvp-template.md](./references/post-mvp-template.md) を Read して従う。各項目は **dev-impl が自動でログ / review 結果から収集して埋める** (decisions.jsonl / review-product-readiness の findings / G_E2E 判定結果から)。

##### 未検証項目の集約

**実行しなかった検証は「成功」と区別できるよう必ず可視化する** (沈黙は成功に見えるため)。以下の事象は発生時に JSONL へ `event_type: verification_skipped` を記録し、ここで集約して Step 6 サマリに列挙する。**集約は `context.source` で分類して並べる** (値と context の形は [references/logging.md](./references/logging.md) の `verification_skipped` の `source` 表が正):

**集約の対象は [references/logging.md](./references/logging.md) の `verification_skipped` の `source` 表が正**で、ここでは列挙し直さない (2 箇所に列挙を持つと片方だけが更新されて取りこぼす)。`source` ごとにまとめ、それぞれ「何を検証しなかったか」と「なぜか」を 1 行で書く。

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

**サマリを出したら JSONL に `event_type: run_done` を 1 件だけ記録する** (context: `status` = `done` / `partial`、`phases_completed`、`goal_summary`)。**Step 0 の再入判定はこのイベントの有無だけを見る**ので、書き忘れると次回の起動が完了済みの run を「未完了」と誤認して再入モードに入る。

サマリー生成前に、記載する各主張 (フェーズ完了数・ゴール達成状況・動的修正回数・受入監査結果) を本セッションの実際のツール実行結果 (`git log`、`decisions.jsonl`、review agent の出力 JSON) と突き合わせる。裏付けが取れない主張は記載しない、または「未確認」と明記する。テンプレートは [references/notification-template.md](./references/notification-template.md) の `## 完了サマリ (Step 6)` 節を Read し、全フィールドを埋めて出力する。

### Step 7: HTML レポート生成

dev-impl 終了時 (Step 6 完了後、またはエスカレ停止時) に `docs/dev-impl-reports/${run_id}.html` を生成する。

実装詳細とテンプレ関数は [references/report-template.md](./references/report-template.md) を参照。

生成手順:

1. JSONL ログ (`~/.claude/logs/dev-impl/${run_id}/decisions.jsonl`) を Read
2. テンプレ関数 (single-page Tailwind CDN HTML) でレポート HTML を組み立て
3. `mkdir -p docs/dev-impl-reports/` で出力先確保
4. Write で `docs/dev-impl-reports/${run_id}.html` に書き出し
5. `git add docs/dev-impl-reports/${run_id}.html` してコミット (HTML レポートは履歴管理する): `git commit` する。**本文には `rules/core/commit.md` が全コミットに要求するフッタ (`🤖 Generated with ...` と `Co-Authored-By: ...`) を必ず入れる** — 本スキルが打つコミットは例外なくこの規約に従う (subject の形式だけは commit-msg-guard が機械検証するが、フッタは検証されないので落としやすい)

レポート内容: ヘッダー (run_id / SHA / 所要時間) / 全体サマリ / フェーズタイムライン / 動的修正詳細 (P1/P2/P3) / レビュー残課題 (low/medium) / 実装ノート (設計判断 / 未解決の質問) / POC_NEEDED 残存状況 (pending non-blocker) / ゴール達成判定 / 受入監査結果 (spec_compliance findings) / フッター。

## エスカレ停止時の挙動

停止条件 (**この一覧が停止理由の網羅リストである**。本文で新しい停止理由を使うときは必ずここと下のラベル表の両方に載せる — どちらかに無いと、停止後のラベル状態と再開方法が未定義になる):

- Step 4.2 のフェーズ内エスカレ条件 (`phase_fix_exceeded` / `guard_agent_failed` / `review_agent_failed` / `spawn_budget_exceeded` / `tests_failing_before_commit` / `working_tree_polluted` / `exemptions_extract_failed`)
- P3 検出 (DESIGN.md 概要レベルの再設計必要 = `design_overview_break`)
- `goal_loop > 2` (ゴール達成判定 → 未達対応の 3 周回でも未達ゴール残存)
- 必須ドキュメント (DESIGN.md / DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md / TODO.md) 欠如 (`docs_missing`)
- `blocker=true` の POC_NEEDED マーカーが残存 (`poc_marker_unresolved`。dev-spec フェーズ 5 で解決してから再実行)
- Step 1 構造ゲートの欠落 (`design_not_approved` / `approval_stale` / `goals_missing` / `verification_missing`)
- Step 1 の GitHub 前提条件が解決できない (`github_prereq_failed` = `gh` が使えない / issue が未生成) / issue の取得が `$LIMIT` に張り付いた (`issue_list_truncated` = 一部の issue が見えていない)
- Step 2 で着手できない (`dependency_blocked` = 依存の循環か駐車待ち / `issue_incomplete` = ラベルの無い未完成 issue)
- テスト弱体化が設計にトレースできない (`test_weakening_detected`)
- P2 動的修正が受入基準 (ゴール / 検証手順行) を変更した (`acceptance_criteria_change`。dev-spec フェーズ 9 → 11 で再承認)
- 受入監査が受入基準の改変を検知 (`verification_tampered`。P3 扱い、修正ループなし)

**`impl_timeout` はここに含めない** — implementer が応答しない issue は `needs-human` で駐車して**次の issue に進む**ので、run は停止しない (4.2a の表)。

停止時の処理:

1. **ラウンドのコミットはそのまま残す。** フェーズ範囲のテストは緑で、「ラウンドごとのコミット」の条件を満たしているため履歴に置いてよい。**フェーズ最終コミット (4.2e) は打たず、TODO.md の `- [x]` 化もしない** — 全体スイートと DoD を通っていないので、そのフェーズは完了していない。作業ツリーは clean のはずで、非クリーンなら 4.2d 手順 8 の汚染なので `git restore` で戻してから停止する。**issue のラベルを停止理由で振り分ける**:

   **上から順に評価し、最初に当てはまった行を採る** (`verification_tampered` のように複数行の記述に当てはまりうる理由があるため、順序が意味を持つ):

   | # | 停止理由 | ラベル | 再開のしかた |
   | - | --- | --- | --- |
   | 1 | **着手中の issue が無い時点での停止** — Step 1 / 1.5 / 2 の停止 (`docs_missing` / `design_not_approved` / `approval_stale` / `goals_missing` / `verification_missing` / `poc_marker_unresolved` / `github_prereq_failed` / `issue_list_truncated` / `dependency_blocked` / `issue_incomplete`) と Step 5 系の停止 (`goal_loop > 2` / `verification_tampered` / `acceptance_criteria_change`) | ラベル操作は行わない (対象の issue が無い) | JSONL の `p3_escalate` を駐車マーカーとし、**Step 0 手順 4 が再入時にユーザーへ確認してから再開する** |
   | 2 | 人間の判断が要るもの (P3 = `design_overview_break` / `test_weakening_detected` / `working_tree_polluted` / `exemptions_extract_failed` / **決定的な** `guard_agent_failed` / `review_agent_failed`) | **`needs-human` を貼り `in-progress` を外す** | 人間が対応した後、次の `/dev-impl` 起動時に Step 0 が確認してラベルを `ready` に戻す |
   | 3 | 再実行で解決しうるもの (`phase_fix_exceeded` / `spawn_budget_exceeded` / `tests_failing_before_commit` / **一過性の** `guard_agent_failed` / `review_agent_failed`) | `in-progress` のまま | `/dev-impl` の再実行で Step 2 が再開対象として拾う |

   **agent 失敗の「一過性」と「決定的」の区別は 4.2d 手順 1 に従う** (タイムアウト・JSON 破損は一過性、`TOO_MANY_FILES` / `NO_DESIGN_DOCS` / スキーマ不適合 / `diff_command_failed` / `unchecked_files` 非空 / `adjudicated` 不足 と 2 回連続の失敗は決定的)。決定的な失敗を再実行側に入れると、同じ入力で同じ停止を繰り返すだけで人間に渡る経路が無くなる。

   人間の判断が要る側で `in-progress` のままにしてはならない。**再実行がそのまま同じ状態から再開してしまい、人間が何もしていないのに前進したように見える**ため。
2. 停止理由を `~/.claude/logs/dev-impl.log` と JSONL (`event_type: p3_escalate`) と stdout 全てに詳細出力
3. HTML レポート (Step 7) を生成 → コミット (停止時もレポートだけは残す)
4. ユーザに通知 (通知内容もログ・review agent の出力から裏付けが取れる事実のみを記載する)。テンプレートは [references/notification-template.md](./references/notification-template.md) の `## エスカレ停止通知` 節を Read し、全フィールドを埋めて出力する (Read せず記憶から近似文面を出すと、最終成功 commit SHA や完了フェーズ数など裏付け必須フィールドが欠落し停止理由の追跡性が落ちる)。

## 既存プロジェクトでの注意

- 既存のコミット history と dev-impl のコミット粒度を混ぜたくない場合は、dev-impl 起動前に専用の作業ブランチを切ることを推奨 (dev-impl 自体は起動ブランチの切替を行わない)
- `bypassPermissions` モード推奨 (途中で permission prompt が出ると dev-impl が止まるため)
- launchd / cron などからヘッドレス実行する場合は `claude -p` 経由で、`--allowedTools` に `Bash,Read,Edit,Write,Glob,Grep,Agent,Skill` を渡す。**headless では AskUserQuestion を使わない** (答える人間がいないため、質問した時点でループが死ぬ)。エスカレ時は停止理由を stdout と JSONL に出力し、darwin なら `terminal-notifier` で通知して終了する。**AskUserQuestion を使う箇所は 3 つあり、headless ではいずれも同じ扱いにする** — Step 0 手順 2 (中断フェーズを取り込むか捨てるか)、Step 0 手順 4 (Step 5 系停止からの再開)、`needs-human` 駐車の解除。どれも「確認せず `p3_escalate` を出力して終了し、人間の対話セッションでの再開を待つ」とする (勝手に「取り込む」「解決済み」を選ぶと、人間が何もしていないのに前進したように見える)

## 範囲外 (やらないこと)

- 設計の合意 (DESIGN.md / DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md 生成) → `/dev-spec`
- TODO.md の初期生成 → `/dev-spec` (フェーズ 10)
- GitHub issue の初期生成 → `/dev-spec` (フェーズ 12)。dev-impl は既にある issue を実装するだけで、着手対象の issue を自分では作らない (例外は Step 4.6 の新フェーズ追加 (P1 / P2) と Step 5 のゴール未達対応。いずれも Step 4.6「新フェーズの issue 化」を通る)
- 並列実装 → 行わない (issue を 1 件ずつ逐次に処理する)
- git push → ユーザー手動
- ブランチ切替・PR 作成 → ユーザー手動 (or `/workflow-create-draft-pr`)
- 動作検証 (実 UI / API テスト) → ユーザーが DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md の検証手順に従って実施

## 関連スキル / agent

### 内部呼び出し (subagent)

- **dev-impl-implementer**: フェーズ 1 本を TDD で実装する葉の agent (Step 4.2a `mode: implement` は `model: opus`、Step 4.2d `mode: fix` はラウンド 1 が `opus` でラウンド 2 以降が `fable`。いずれも明示)。`tools` に `Agent` を持たないため子 subagent を起動できず、5 分 TTL のキャッシュ失効を構造的に避ける。フェーズスコープのテストのみ実行し、コミット・`docs/` 編集・全体スイート実行はしない。全文報告を `report_path` に Write し、SendMessage では要約だけを返す (規約の全文は `claude/agents/dev-impl-implementer.md`)
- **tech-investigation**: 実装中に新たな技術検証が必要になった場合の個別呼び出しのみ (起動前の PoC は dev-spec フェーズ 5 の責務)
- **architecture-guard**: Clean Arch / DDD 境界違反検出、機械判定 (Step 4.2c の fan-out に毎フェーズ含める、haiku)
- **fix-lsp-warnings**: Lua/Neovim の LSP 警告修正 (Step 4.2b、haiku)。修正する agent なので検査 fan-out には混ぜず単独・逐次で走らせる
- **review-tdd / review-quality / review-product-readiness**: Step 4.2c から `model: opus` 明示で並列起動 (観点 gating・起動条件は Step 4.2c 参照)。review-quality は rules 準拠 + アーキテクチャ heuristic を統合。review-product-readiness は実機 chrome-devtools MCP 操作で UX 横断項目 (ナビ到達 / ErrorBoundary / 空状態 / loading / SEO meta / 404 / logout) を検査 (Step 5.2 の G_E2E 判定も担当)
- **review-adversarial**: Step 4.2c から `model: sonnet` 明示で並列起動する敵対的レビュワー。3 レンズ (A: エッジケース/エラーパスを能動的に攻撃し実際に実行して落とす、B: テスト弱体化・トートロジー化・アサーションの空虚化・skip 隠蔽の意味論検知、C: PHASE_CONTEXT を信用せず `docs_dir` の TODO.md から当該フェーズの節を自分で読み直し、その完了主張に反証を試みる) で検査。**毎フェーズは `mode: weakening_only` (レンズ B のみ) で走り、消費型資源・認証・テスト差分なしの大量実装・最後の issue のフェーズだけ `mode: full` (A+B+C) に上げる** (Step 4.2c の mode 決定表)。機械スキップ述語 (Step 4.2c 参照) を満たせば skip 可。`test_weakened` / `vacuous_assertion` / `skip_added` / `tautological_test` は severity と confidence に関わらず修正ラウンドに乗せず、トレース確認の経路に直結する (詳細は Step 4.2d)

- **review-spec-compliance**: Step 5.2 から `model: opus` 明示で起動する第三者受入監査 (mode: post-impl)。承認ハッシュの独立照合・自動系ゴール検証コマンドの独立再実行・成果物全体 ↔ 詳細設計の突合・検証コマンドの空虚性検査。PHASE_CONTEXT 抜粋は渡さず docs を自分で全文 Read させる (被監査者が編纂した入力を信用しない)。`PRODUCT_MODE=cli` では G_E2E 検証コマンドの実行もこの agent が担当する (review-product-readiness は起動しないため)
- **security-guidance プラグイン**: セキュリティレビューはこのプラグイン (Edit/Write 時の pattern 検知 + Stop hook の LLM diff review) に委譲。自作 subagent は持たない

**空虚テスト検出の分担**: review-tdd の `vacuous_negative_assertion` は**新規に書かれたテストそのものの空虚性**を、review-adversarial レンズ B の `vacuous_assertion` は**基準時点 (PHASE_START_SHA) からの空虚化**を見る。同一フェーズで両者が同種の指摘を上げることがあるが、検査している次元が違うため統合しない (統合するとどちらか一方の次元が検査されなくなる)。

**全ての subagent に作業ディレクトリ (`repo_dir`) を絶対パスで渡す。** subagent の Bash は呼び出しごとに cwd が親のものへ戻るため、渡さないと検査対象・編集対象が意図したディレクトリにならず、空差分で素通りする。

**全テストゲート / コミット / issue のラベル操作と close / RUN_FACTS 更新 / decisions.jsonl は必ず main が行う** (commit-msg-guard hook は親にしか効かないため)。

### 内部呼び出し (skill)

なし。P2 動的修正時の TODO 再生成は `../dev-spec/references/todo-generation.md` を Read してメインループで直営する (Skill ツール経由ではモデル指定が効かないため、skill 呼び出しは増やさない)。

(手動レビュー用の `workflow-review` skill と `workflow-commit` skill は dev-impl からは呼ばない。相当の処理は Step 4.2d / 4.2e が担う)

### 連携 hook

- **commit-msg-guard hook (`claude/hooks/commit-msg-guard.ts`)**: main が打つ**すべてのコミット**の subject 形式を PreToolUse(Bash) で機械検証する (4.2a / 4.2b / 4.2d のラウンドコミット、4.2e のフェーズ最終コミット、4.6 の動的修正コミット、Step 7 のレポートコミット)。検証するのは `<emoji> <type>: <subject>` の形と emoji / type の対応だけで、`[phase-<識別子>]` prefix や `[STRUCTURAL]` / `[BEHAVIORAL]` は検証対象外 (それらは本スキルと `rules/core/commit.md` の規約であって hook は見ない)。検証が働くのは `$GHQ_ROOT/github.com/skanehira/` 配下で作業しているときだけで、それ以外のリポジトリでは fail-open
- **agent-spawn-guard hook (`claude/hooks/agent-spawn-guard.ts`)**: PreToolUse(Agent) で、`MANDATED_MODEL` に登録された agent (dev-impl-implementer / architecture-guard / fix-lsp-warnings / review-*) の **model 未指定を deny** する。加えて review-spec-compliance の prompt に必須フィールドが揃っているかを検証する。無効化は `AGENT_SPAWN_GUARD=off`

### 前段 / 後段

- **dev-spec**: 前段。設計ループ (要件整理 〜 PoC 検証 〜 設計書 〜 TODO 生成)。承認ゲートで本スキルの起動方法を案内する
- **workflow-create-draft-pr**: 後段 (任意)。PR 作成はユーザーが手動で起動する
