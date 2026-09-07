---
name: dev-impl
description: 実装ループ。/dev-spec が作成した GitHub issue (ゴール / 設計参照 / DoD / 非スコープ / 依存の thin 構成) を入力に、依存順に「implementer subagent → 統合レビュー → 修正 ≤2 ラウンド → PR → DoD ローカル実行 → merge → close」で自律実装するオーケストレーター。前提を満たすプロジェクトでは同じ依存レベルの issue を worktree で最大 3 並列に流す (merge は直列)。子が全完了した親 (tracking) issue はその場で close し、取りこぼしは run 終了時に回収する。進捗は issue コメントに残し、詰まった issue は needs-human で駐車して次へ進む。人間の介入はエスカレーション時のみ。issue 作成後にユーザーが直接起動し、エスカレーション回答後の再開も本スキルの再実行で行う。「実装ループを開始」「issue を順に実装して」「残りタスクを自動で実装」などで起動。
argument-hint: "[issue 番号の絞り込み、省略時は ready 全件]"
model: opus
allowed-tools: Read, Edit, Write, Glob, Grep, Bash, Agent
---

# dev-impl — 実装ループ

`ready` ラベルの open issue を依存順に最後まで自律的に実装するオーケストレーター。実装の指示はすべて issue 本文と参照 docs (docs/design/DESIGN.md / docs/design/features/) から取る — **issue が自己完結しているので、親が文脈を編纂して渡すことはしない**。

親 (このセッション) は薄いオーケストレーターに徹する: issue の順序管理 / subagent の起動 / コミット・PR・merge / issue のラベル・コメント操作。実装は implementer、検査は review-impl が fresh context で行う。

## モデル方針

| 役割 | 実行 | モデル |
| --- | --- | --- |
| オーケストレーション (本ループ) | メインセッション | opus (frontmatter 指定。Skill ツール経由起動では効かないため、ユーザーが直接起動する) |
| 実装 | `dev-impl-implementer` subagent | `model: "opus"` 明示 |
| レビュー | `review-impl` subagent | `model: "opus"` 明示 |
| コミット実行・巨大出力のテスト実行 (E2E 等) | subagent | `model: "haiku"` (`~/.claude/rules/core/orchestration.md`「委譲の判断」。メッセージ起草・対象ファイルの判断は親が行い、実行だけを委譲する) |

## Step 0: 前提チェック

```bash
REPO_DIR=$(git rev-parse --show-toplevel)
REPO_SLUG=$(gh repo view --json nameWithOwner -q .nameWithOwner)
DEFAULT=$(git symbolic-ref --short refs/remotes/origin/HEAD | sed 's|origin/||')
rg -n 'POC_NEEDED:.*blocker=true' docs/design/DESIGN.md docs/design/features/ 2>/dev/null
```

- git / gh が解決できない → 停止して案内する
- `POC_NEEDED: ... blocker=true` が 1 件以上 → 実装に入らず、`/dev-spec` のフェーズ 5 (PoC 検証) への差し戻しを案内して停止する (未検証の技術前提の上に実装しない)
- ラベル 4 種を冪等に用意する (dev-spec を経ずに用意された issue でも 2.1 のラベル操作が失敗しないように。コマンドは `~/.claude/skills/dev-spec/references/issue-template.md`「ラベルの用意」と同一)
- **docs が push 済みか確認する**: ローカルに `docs/design/DESIGN.md` があるのに `git log origin/$DEFAULT -1 -- docs/design/DESIGN.md docs/design/features/` が空なら、ブランチ基点 (origin) に設計 docs が無い。docs を含むコミットの push を人間に依頼して停止する (2.1 のブランチは origin から切るため、push されていないと implementer が docs を読めない)
- `docs/design/DESIGN.md` が無い構成でも、issue が自己完結していれば続行してよい (issue の DoD に実行コマンドが揃っていることが条件)

作業ログ用のディレクトリを作る: `SCRATCH=<scratchpad>/dev-impl-$(date +%Y%m%d-%H%M%S)` (report JSON の置き場。git 管理外)。保留レビュー項目のチェックリストは **`docs/PENDING_REVIEW.html`** に置く (リポジトリ内。issue のコミットに含めて merge されるため、別マシン・別セッション・後続 run にも引き継がれる。追記は 2.3、確認案内は Step 3)。

## Step 1: issue の収集と着手順

```bash
gh issue list --repo "$REPO_SLUG" --state open --label ready --json number,title,body --limit 200
gh issue list --repo "$REPO_SLUG" --state open --label in-progress --json number,title,body --limit 200
```

取得件数が limit に達したら limit を上げて再取得する (無音の取りこぼしは実装漏れになる)。

- 各 issue の `## 依存` 節から `Depends on #<番号>` を読み、トポロジカル順に並べる。依存先が open のままの issue は、依存先が close されるまで着手しない
- `needs-human` の issue は着手しない
- `$ARGUMENTS` で issue 番号が指定されていれば、その issue (と未完了の依存先) だけを対象にする
- `tracking` ラベルの親 issue (ユースケース単位のトラッキング) は実装対象にしない
- あわせて**依存レベル**を求める。依存が無い issue を L0、それ以外は「依存先のレベルの最大値 + 1」とする。同じレベルの issue は互いに依存しないので同時に着手してよい (2.0 の並列実行が使う)。**着手順はトポロジカル順のまま**で、レベルは「どこまで同時に走らせてよいか」の判定にだけ使う (レベルを優先度に読み替えて順序を組み替えない)

**`in-progress` が残っている、または対象 issue に残置ブランチ `issue-<N>` がある場合は前回の中断・駐車からの復帰。** その issue の状態を確認して再開位置を決める (needs-human から `ready` に戻された issue はラベルでは区別できないため、ブランチの有無で検出する):

| 状態 (`gh pr list --repo "$REPO_SLUG" --head issue-<N>` と、`git fetch origin` 後の `git branch --list issue-<N>` / `git branch -r --list "origin/issue-<N>"`) | 再開位置 |
| --- | --- |
| PR が open | 2.4 の DoD 実行 → merge から (PR は再作成しない)。レビュー未実施が疑われる場合は 2.3 から |
| ブランチのみ残存 (ローカルまたは origin、PR なし) | ブランチへ switch し (origin のみに在る場合は `git switch issue-<N>` が追跡ブランチを作る)、`BASE_SHA=$(git merge-base origin/$DEFAULT HEAD)` で基準を復元して 2.2 から。implementer の prompt に「ブランチに前回の差分がある。既存差分を前提に続きから実装せよ」を 1 行追加する |
| どちらも無い | 最初から (2.1 から) |

実装途中の**未コミット**差分はマシンローカルで、別マシンには引き継げない。ブランチも push されるまではマシンローカル (2.6 の駐車時は WIP を退避して push を試みる)。別マシンで再開して残置ブランチが origin に無い場合、その issue は最初からやり直しになる — これは仕様で、issue 単位が再開の粒度である。ローカルと origin の両方にブランチが在る場合は fetch 後に ahead/behind を確認し、behind ならローカルを origin に合わせ (`git switch -C "issue-<N>" "origin/issue-<N>"`)、ahead なら push してから続行する。

## Step 2: issue ごとの実装サイクル

対象 issue をトポロジカル順に、次のサイクルで消化する。**同じ依存レベルの issue は最大 3 件まで並列に走らせる** (2.0)。並列の前提が満たせないプロジェクトでは 1 件ずつになる。

### 2.0 並列実行の可否と枠組み

直列実行では実装ループの経過時間が消化コストの総和になる。同一レベルの issue は互いに依存しないので、実装とレビューは同時に走らせてよい。**ただし merge は必ず 1 件ずつ直列に行う** (2.4 手順 4)。並列で merge するとデフォルトブランチが競合し、後続の rebase が連鎖する。

**並列にしてよいのは、プロジェクトが次の 2 つを満たすときだけ。** 満たさなければ**並列度 1** で回す (誤った green を出すより遅い方がよい):

1. `docs/design/DESIGN.md`「開発・検証コマンド」に **worktree セットアップ手順**が書かれている (依存インストールなど、チェックアウト直後の作業ツリーで DoD を実行可能にする手順)
2. テスト・E2E が**固定ポートを共有しない**こと。dev server を起動する検証がある場合、ポートを外から指定でき、指定したポートで起動できなければ失敗する (既存サーバに相乗りしない) 契約になっていること。**相乗りする設定 (Playwright の `reuseExistingServer: true` + 固定 `baseURL` など) のまま並列にすると、別の worktree のサーバに対してテストが通り、静かに誤った green を出す**

満たす場合、レベルごとに次の手順で流す:

```bash
# スロット s (0 始まり、最大 3) に issue N を割り当てる
WT="$REPO_DIR/.claude/worktrees/issue-$N"
git -C "$REPO_DIR" worktree add -b "issue-$N" "$WT" "origin/$DEFAULT"
```

worktree には git 管理外のファイル (`.env` 系・ローカル設定) が無いので、そのままでは DoD が実行できない。**リポジトリルートの `.worktreeinclude` に列挙されたものを複製する。** これは Claude Code が worktree を作るときにも使うファイルで、書式は `.gitignore` と同じ (1 行 1 パターン、`#` はコメント)。**複製されるのは gitignored なファイルだけ**で、追跡されているファイルは対象にならない。用意するのは人間か、プロジェクトを scaffold したスキル。無ければ何も複製しない (その場合は前提 1 のセットアップ手順が代わりを果たす必要がある):

```
# .worktreeinclude の例
.dev.vars
.env.local
```

依存ディレクトリ (`node_modules` 等) は容量が大きいのでここに列挙せず、前提 1 のセットアップ手順でインストールする。

- **`.claude/worktrees/` が `.gitignore` に無いプロジェクトでは並列にしない**。worktree を作った時点で親の作業ツリーが dirty になり、2.1 の clean チェックが全 issue で失敗する。並列を使うなら先に `.gitignore` へ追加する (それ自体を 1 コミットにしてよい)
- ポートは**スロット番号から決めて implementer に渡す** (例: 基準ポート + s × 10)。渡し方はプロジェクトの worktree セットアップ手順に従う
- issue が終わったら `git -C "$REPO_DIR" worktree remove "$WT"` で片付ける。駐車 (2.6) した issue の worktree は、WIP を push したうえで削除する (残すと次回の clean チェックに掛かる)

### 2.1 着手

以下の `$WORK_DIR` は、直列実行なら `$REPO_DIR`、並列実行なら 2.0 で作った worktree のパス。**implementer・review-impl には `repo_dir` としてこの `$WORK_DIR` を渡す** (どちらも絶対パスで受ける契約なので、直列・並列で指示の形は変わらない)。

1. `git -C "$WORK_DIR" status --porcelain` が空であることを確認する。残骸があれば停止して人間に報告する (前作業の未コミット差分の上に実装しない)
2. ブランチを origin のデフォルトブランチ最新から切り、基準 SHA を控える。並列実行では 2.0 の `worktree add -b` で既にブランチが作られているので `switch` は行わず、`fetch` と `BASE_SHA` の取得だけを行う:

```bash
git -C "$REPO_DIR" fetch origin
git -C "$WORK_DIR" switch -c "issue-$N" "origin/$DEFAULT"   # 直列実行のみ
BASE_SHA=$(git -C "$WORK_DIR" rev-parse HEAD)
```

3. 作業ツリーが `issue-$N` に乗ってからラベルとコメントを更新する (先にラベルを変えると、失敗時に `in-progress` だけが残る):

```bash
gh issue edit "$N" --repo "$REPO_SLUG" --remove-label ready --add-label in-progress
gh issue comment "$N" --repo "$REPO_SLUG" --body "実装を開始します (dev-impl)"
```

### 2.2 実装 (implementer subagent)

```javascript
Agent({
  description: "issue #<N> の実装",
  subagent_type: "dev-impl-implementer",
  model: "opus",
  prompt: `mode: implement
repo_dir: <WORK_DIR>
issue_number: <N>
report_path: <SCRATCH>/impl-<N>.json`
})
```

**検収**: report JSON を読み、`status: done` は `test_result.exit_code = 0`・`dod_result.exit_code = 0`・`self_review.checklist_applied = true` を満たすときだけ done と扱う (満たさない報告は失敗ブリーフとして `mode: fix` で差し戻す)。

分岐:

- `done` (検収済み) → 2.3 へ
- `escalate` / `failed` (`contract_break` / `spec_insufficient` / `tests_failing`。`test_weakening_suspected` は fix 時のみ発生) → 2.6 へ (report の summary にある試行記録を issue コメントに使う)
- **subagent がエラー、または report JSON が無い・パース不能** → 同条件で 1 回だけ再起動する。再失敗なら 2.6 へ

### 2.3 レビュー (review-impl subagent、修正 ≤ 2 ラウンド)

```javascript
Agent({
  description: "issue #<N> のレビュー",
  subagent_type: "review-impl",
  model: "opus",
  prompt: `repo_dir: <WORK_DIR>
base_sha: <BASE_SHA>       // 2.1 で控えた値
issue_number: <N>
focus: all
previous_findings_path: <SCRATCH>/review-<N>-r<前ラウンド>.json   // r2 以降のみ。初回は行ごと省く
report_path: <SCRATCH>/review-<N>-r<ラウンド>.json`
})
```

**レビューと修正の回数はこう数える。初回レビューを r1 とし、レビューのたびに 1 ずつ増やす** (この採番は hook が修正ラウンド数の判定に使うので、r0 から始めると 3 回目の修正が素通しになる)。レビューは r1 (実装直後) / r2 (fix 1 回目の後) / r3 (fix 2 回目の後) の最大 3 回、`mode: fix` は r1 と r2 の findings に対する最大 2 回。「最大 2 ラウンド」が数えているのは **fix の回数**であって review の回数ではない。`previous_findings_path` は r2 と r3 の 2 回渡ることになる。

`previous_findings_path` を渡すと、レビュワーは「前ラウンドの指摘が閉じたか」に加えて「同じ壊れ方が別の箇所へ転移していないか」を検査する (review-impl の検査項目 5)。渡さないと fresh context のレビュワーは前ラウンドの存在を知らないため、修正が作った同型の穴を次の周まで見逃す。**再開 run で前 run の review JSON が SCRATCH に無い場合は渡さない** (SCRATCH は run ごとに新規作成されるため)。その場合は項目 5 が働かないことを完了コメントに記す。

**`checked` の検収**: findings の件数を見る前に `checked` を確認する。次のいずれかなら検査が成立していないので、指示を明確化して 1 回再実行し、再発なら 2.6 へ (「何も検出できない検証の実行は検証ではない」):

- `tests_run: false`
- UI に触れる差分なのに `e2e` が理由の無い `skipped`
- `previous_findings_path` を渡したのに `previous_findings` が `none` (検査項目 5 の未実施) または `unreadable(...)` (パスの渡し間違い — この場合はパスを直して再実行する)

review JSON が無い・パース不能の場合も同様に 1 回再起動 → 再失敗で 2.6。**検収の失敗による再実行は同じ `report_path` を上書きする** (r 番号を進めない。r 番号は fix ラウンドの判定と `previous_findings_path` の選択に使われるので、実際には行われていない fix を 1 回数えてしまう)。

findings の分岐:

- **high / medium が 0 件** → 2.4 へ (low は完了コメントに「報告のみ」として記載)
- **high / medium がある** → implementer を `mode: fix` (`findings_path` に review JSON を指定) で起動して修正させ、レビューを再実行する。**このループは最大 2 ラウンド (固定)**。2 ラウンド後に **high が残る → 2.6**。**medium だけが残る → `docs/PENDING_REVIEW.html` に追記して 2.4 へ進む** (下記「保留レビュー項目の記録」)。この上限は `~/.claude/hooks/fix-round-guard.ts` が機械検証しており、3 回目の `mode: fix` 起動は `findings_path` のラウンド番号から検知されて deny される (`findings_path` の命名規約を守っている限り、ラウンド数の管理は自制に頼らない)。**deny されたら 2.2 の「1 回だけ再起動」を適用しない** — 同条件では必ず再び deny される。deny メッセージが示すとおり、high が残っていれば 2.6、medium だけなら `docs/PENDING_REVIEW.html` に追記して 2.4 へ進む。人間が明示的に継続を指示した場合に限り `FIX_ROUND_GUARD=off` で解除できる
- **`category: test-weakening` の finding** → implementer に直させず親が裁定する: 弱体化が事実なら該当テストを基準時点の強度に戻す修正だけを親が直接行う (最小差分。再レビューは不要 — 2.4 の全体テストが検証する。ラウンド数にも数えない)。誤検出なら根拠を review JSON に追記して次へ進む。
  **裁定した finding には、その review JSON の該当 finding へ `"adjudication": {"verdict": "false_positive|fixed_by_parent", "rationale": "<根拠の一文>"}` を足す。** この JSON は次ラウンドで `previous_findings_path` としてレビュワーに渡るため、印を付けないと裁定済みの指摘が「未解消」として再計上され、同じ指摘で駐車に落ちる (レビュワー側は `adjudication` の付いた finding を残存判定の対象外にする規約)

#### 保留レビュー項目の記録

2 ラウンドで解消しなかった medium は、これ以上修正もエスカレーションもせず**ユーザーの事後確認に回す**。`docs/PENDING_REVIEW.html` (無ければ作成) に issue ごとの節として追記する — 各 finding はチェックボックス付きの 1 項目で、severity / category / `file:line` / summary / evidence / fix_hint をまとめる。外部依存の無い自己完結の静的 HTML とし、全 issue が同じファイルに追記し続ける。issue ごとの節は issue 番号の見出しで分離し、rebase 等でこのファイルがコンフリクトしたら**両方の節を残す (union)** 解決にする。**追記分は 2.4 手順 1 で本 issue のコミットに含める** (`docs_updates` と同じ経路で merge され、リポジトリで持ち回られる)。

### 2.4 コミット・PR・merge

1. **コミット**: 変更を論理単位で Conventional Commit (`~/.claude/rules/core/commit.md`。STRUCTURAL / BEHAVIORAL 分離) にする。メッセージ起草とステージ対象の決定は親、実行は Haiku subagent に委譲してよい (モデル方針の表)。implementer の `docs_updates` (乖離補正) と、2.3 で追記した `docs/PENDING_REVIEW.html` も同じ issue の**コミット列**に含める (関心事分離に従い docs は独立コミットでよい)
2. **全体テスト**: プロジェクトのテストスイート全体と lint を実行し green を確認する (巨大出力になる場合は Haiku subagent に実行だけ委譲し、pass/fail 件数と失敗の要点を受け取る)
3. **PR**: `git push -u origin "issue-$N"` してから作成する (再開で PR が既にあればスキップ)。push が失敗したら (前 run の同名 remote ブランチ残骸等)、原因を確認して解消できなければ 2.6 へ:

```bash
gh pr create --repo "$REPO_SLUG" --title "<issue タイトル>" --body "$(cat <<'EOF'
Closes #<N>

## 変更の要約
<implementer の summary>

## 検証
- テスト: <全体テストの結果 (passed/failed 件数)>
- レビュー: review-impl <ラウンド数> 周、high 0 件 (low <k> 件・未解消 medium <m> 件は merge 後の issue コメントに記載。medium 0 件ならその旨)
- DoD: merge 前にローカルで全コマンドを実行し、green を確認してから merge する

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

4. **DoD のローカル実行 → merge**: issue の `## DoD` のコマンドを PR ブランチ上でそのまま実行し、**全て exit code 0 であることを確認してから** merge する (CI は使わない — 判定はこのローカル実行が兼ねる)。DoD が 1 つでも失敗したら merge しない → 2.6 へ:

```bash
gh pr merge --repo "$REPO_SLUG" --squash --delete-branch
```

**並列実行でも merge はここで 1 件ずつ直列に行う。** 同時に merge するとデフォルトブランチが競合し、残りの worktree がまとめて rebase 待ちになる。他の issue が実装・レビュー中でも、merge の順番待ちだけを直列化すればよい。merge した issue の worktree は 2.0 の手順で削除する。

merge がコンフリクトで失敗したら (駐車 → 再開の間や、並列の先行 merge でデフォルトブランチが進んだ場合)、`git -C "$WORK_DIR" rebase origin/$DEFAULT` を試み、**その作業ツリーで全体テストの green を確認してから** push し直す (先行 merge の内容と組み合わせて壊れていないかは、rebase 後に実行するまで分からない)。解消できなければ 2.6 へ。

### 2.5 完了処理

merge により `Closes #N` で issue は自動 close される (されていなければ `gh issue close` する)。完了コメントを 1 件残す:

```
実装完了 (dev-impl)
- 変更: <summary と主要ファイル>
- テスト: <2.4 の全体テストの件数>、DoD: green
- レビュー: <ラウンド数> 周 (low の報告: <あれば列挙、なければ「なし」>)
- 未解消 medium: <各 1 行で `file:line` + summary。なければ「なし」> (evidence・fix_hint は `docs/PENDING_REVIEW.html` に記録)
- 設計判断・docs 更新: <design_decisions / docs_updates の要約、なければ「なし」>
```

親 (tracking issue) を逆引きし、その親の子が全て完了していれば親も close する。API の挙動の正本は `~/.claude/skills/dev-spec/references/issue-template.md`「親への紐付け」の実測表:

```bash
gh api "repos/$REPO_SLUG/issues/$N/parent" \
  --jq '"\(.number)\t\(.state)\t\(.sub_issues_summary.completed)/\(.sub_issues_summary.total)"' 2>&1
```

| 結果 | 動作 |
| --- | --- |
| 出力に `(HTTP 404)` を含む (親に紐付いていない子) | close はしない。**正常系** (`gh` は非ゼロで終了しエラー行を出すが、エラーとして扱わない)。ただし dev-spec の紐付け漏れの兆候なので、番号を控えて Step 3 の最終報告に載せる |
| `state` が open (小文字) かつ `completed == total` | close する |
| `completed < total` (残り子がある) | 親は open のまま次へ進む |
| それ以外の失敗 (403・5xx・`gh` が sub-issues API 非対応など) | 親 close をスキップし、番号を控えて Step 3 の最終報告に載せる (404 と同じ扱いに丸めない) |

```bash
gh issue close "<親番号>" --repo "$REPO_SLUG" --comment "この親 issue の sub-issue がすべて完了したため close する (dev-impl)"
```

`sub_issues_summary` は API 側が数える値なので、自前で子を列挙して数え直さない (取りこぼしによる誤 close を避ける)。merge 直後は `Closes #N` の自動 close が非同期で、最後の子でも `completed` が古い値のことがある — **再試行はしない**。取りこぼしは Step 3 の掃き掃除が回収する。

次の issue へ進む (Step 2 の先頭へ)。

### 2.6 エスカレーション (needs-human 駐車)

解消できない issue (2 ラウンド後の high 残存 / `escalate` / DoD 失敗 / テスト red / subagent の再失敗 / push・merge の解消不能) は、まず**未コミットの作業をブランチへ WIP コミットとして退避し、`git push -u origin "issue-$N"` を試みる** (push 失敗は続行してよいが、その場合ブランチはマシンローカルに残る旨を駐車コメントに書く)。コミット条件 (全テスト green) は merge されるコミットの規律であり、この退避コミットは merge しない駐車ブランチ上の記録なので例外とする — 退避しないと作業ツリーが dirty のまま残り、次の issue の 2.1 (clean チェック) と run 停止時の Step 3 (デフォルトブランチへの switch) が成立しない。**並列実行ではこの退避を worktree の中で行い、push まで済ませてから 2.0 の手順で worktree を削除する** (残すと親の作業ツリーが dirty のままになる)。退避後:

```bash
gh issue edit "$N" --repo "$REPO_SLUG" --remove-label in-progress --add-label needs-human
gh issue comment "$N" --repo "$REPO_SLUG" --body "<状況: 何を試し、何が起き、何が残っているか (implementer の summary の試行記録を含める)。未 merge の保留 medium があればその summary も列挙 (PENDING_REVIEW.html への追記が merge されていないため)。人間に決めてほしいこと。ブランチ issue-$N (と PR があれば PR) は未 merge のまま残置>"
```

ブランチと open PR は merge せず残す (人間が差分を確認でき、再開時に再利用できる)。**その issue に依存しない次の issue へ進む。**

**run 全体を停止するのは次の 2 つだけ**: (1) 残りの全 issue が未解消 issue に依存してブロックされた (2) `contract_break` の内容が後続 issue の前提を崩し、進めるとやり直しになる。停止時は未解消 issue の一覧と理由をまとめて報告する — このときも Step 3 の手順 2 (docs/PENDING_REVIEW.html の open と確認促し) を実行する (merge 済み issue の保留 medium を停止で失わない)。

## Step 3: 終了処理

1. **tracking issue の掃き掃除**: 2.5 の随時 close で取りこぼした親 (駐車していた issue が後から解消された場合や、過去 run が残した親) を回収する。open な `tracking` issue を全件走査し、子が 1 件以上あってその全てが完了しているものを close する。判定は 2.5 と同じく `sub_issues_summary` を使う (子を自前で列挙しない):

```bash
for P in $(gh issue list --repo "$REPO_SLUG" --state open --label tracking --limit 200 --json number --jq '.[].number'); do
  SUMMARY=$(gh api "repos/$REPO_SLUG/issues/$P" --jq '"\(.sub_issues_summary.completed) \(.sub_issues_summary.total)"') \
    || { echo "#$P 判定不能"; continue; }
  COMPLETED=${SUMMARY% *}; TOTAL=${SUMMARY#* }
  if [ "$TOTAL" -eq 0 ]; then
    echo "#$P 子ゼロ"
  elif [ "$COMPLETED" -eq "$TOTAL" ]; then
    gh issue close "$P" --repo "$REPO_SLUG" --comment "この親 issue の sub-issue がすべて完了したため close する (dev-impl)"
  else
    echo "#$P 子が残っている ($COMPLETED/$TOTAL)"
  fi
done
```

`TOTAL -eq 0` の分岐を外さない — 子が 1 件も紐付いていない親 (dev-spec の紐付けが途中で落ちた場合) まで close してしまうため。「子ゼロ」「子が残っている」「判定不能」の 3 種の出力をそのまま最終報告の 3 区分に使う。

**この走査は `tracking` ラベルの open issue を repo 全件対象にする。** dev-spec 由来でない手作りの `tracking` issue がある repo では、close 前に対象一覧を提示して人間に確認する。

2. デフォルトブランチへ戻って `git pull` し、`docs/PENDING_REVIEW.html` が存在すれば `open` で開いて (macOS。非 macOS ではパスを提示するだけでよい)、最終報告の先頭で「実装は完了したが、未解消 medium <n> 件のチェックが必要」とユーザーに確認を促す (過去 run の未消化分も累積している)。対応要と判断した項目は新しい issue にするか直接の修正依頼で対応し、確認が済んだ項目はユーザーがチェックリストから消す (手動編集または修正依頼。通常のコミットで反映)
3. 最終報告 (会話で 1 回だけ。run レポート文書は作らない):
   - 実装した issue と PR の一覧
   - close した親 (tracking) issue と、open のまま残した親 (子が残っている / 子ゼロ / 判定不能の別に)
   - 2.5 で親 close を判定できなかった子 issue の番号 (親に紐付いていない 404 の子と、API 失敗の子を分けて)
   - 保留レビュー項目 (未解消 medium) の件数とチェックリストのパス
   - `needs-human` で駐車した issue と、人間がすべき決定
   - 実装中の設計判断・docs 更新の要約

## エスカレーション回答後の再開

人間が `needs-human` の issue に回答したら、**回答の内容を issue 本文 (該当節の書き換え) または参照 docs に反映してから**、ラベルを `ready` に戻して本スキルを再実行する — implementer は issue 本文と docs しか読まないため、コメントに書かれただけの回答は実装に届かない。docs 側を変えた場合は push も行う (Step 0 の確認に掛かる)。Step 1 の収集が駐車 issue を拾い直し、残置ブランチ・PR があれば続きから実装する。チェックリスト (`docs/PENDING_REVIEW.html`) はリポジトリで持ち回るため、再開 run・別マシンでも累積した保留 medium がそのまま引き継がれる。

## 参照ルール

- コミット規約: `~/.claude/rules/core/commit.md` / 委譲の判断: `~/.claude/rules/core/orchestration.md`
- implementer・review-impl の入出力契約は各 agent 定義 (`~/.claude/agents/dev-impl-implementer.md` / `review-impl.md`) が正本

## 関連スキル・エージェント

- **dev-spec**: 上流の設計ループ。issue の生成元
- **dev-impl-implementer** (subagent): 実装の葉。issue と docs を直読する
- **review-impl** (subagent): 統合レビュワー (テスト品質 / 設計準拠 / コード品質 / E2E。2 周目以降は前ラウンド指摘の再発・転移)
