---
name: dev-impl
description: 実装ループ。/dev-spec が作成した GitHub issue (ゴール / 設計参照 / DoD / 非スコープ / 依存の thin 構成) を入力に、依存順に「implementer subagent → 統合レビュー → 修正 ≤1 ラウンド (high と medium) → 検証 → 動作確認の証跡付き PR → CI pass (CI があれば) → merge → close」で自律実装するオーケストレーター。依存を守ってスコアの高い順 (緊急枠が先頭。スコアの無い issue は後ろ。同じなら番号の小さい順) に着手し、前提を満たすプロジェクトでは着手できる issue を worktree で最大 3 並列に流す (merge は直列)。子が全完了した親 (tracking) issue はその場で close し、取りこぼしは run 終了時に回収する。進捗は issue コメントに残し、詰まった issue は needs-human で駐車して次へ進む。人間の介入はエスカレーション時のみ。issue 作成後にユーザーが直接起動し、エスカレーション回答後の再開も本スキルの再実行で行う。「実装ループを開始」「issue を順に実装して」「残りタスクを自動で実装」などで起動。
argument-hint: "[issue 番号の絞り込み、省略時は ready 全件]"
model: opus
allowed-tools: Read, Edit, Write, Glob, Grep, Bash, Agent, Skill
---

# dev-impl — 実装ループ

- 種別: skill (手順書)

`ready` ラベルの open issue を依存順に最後まで自律的に実装するオーケストレーター。実装の指示はすべて issue 本文と参照 docs (docs/design/DESIGN.md / docs/design/features/) から取る — **issue が自己完結しているので、親が文脈を編纂して渡すことはしない**。

親 (このセッション) は薄いオーケストレーターに徹する: issue の順序管理 / subagent の起動 / コミット・PR・merge / issue のラベル・コメント操作。実装は implementer、検査は review-impl が fresh context で行う。

## モデル方針

| 役割 | 実行 | モデル |
| --- | --- | --- |
| オーケストレーション (本ループ) | メインセッション | opus (frontmatter 指定) |
| 実装 | `dev-impl-implementer` subagent | opus を明示 |
| レビュー | `review-impl` subagent | opus を明示 |
| コミット実行・巨大出力のテスト実行 (E2E 等) | `general-purpose` subagent | haiku を明示 (下記「Haiku への委譲」) |

frontmatter の `model` が効くのは、ユーザーが `/dev-impl` を直接入力して起動した場合だけである。エージェントが自分の判断で起動した場合には効かないので、本スキルはユーザーが直接起動する。

以下の起動手順に出てくる「説明」は、サブエージェントを起動するときに付ける表示用の短いラベルである。起動の可否や渡す内容には影響しない。

### Haiku への委譲

`~/.claude/guidelines/core/orchestration.md`「委譲の判断」に従い、コミットの実行と、出力が巨大になるテスト実行 (E2E 等) だけを Haiku に委譲してよい。委譲するのはコマンドの実行だけで、コミットメッセージの起草・ステージ対象の決定・結果の判定は親が行う。委譲先にはファイルを編集させない。

コミットの実行 (2.4 手順 1) は、**コミット 1 件につき 1 回**、サブエージェント `general-purpose` を起動する (モデル: haiku を明示)。完了を待ってから次の手順 (次のコミットの起動を含む) へ進む。1 issue のコミット列が複数のコミットになるときは、この起動をコミットの数だけ順に繰り返す。

- 説明: `issue #<N> のコミット`
- 次の内容を渡す:

```
repo_dir: <WORK_DIR> (すべてのコマンドを cd <WORK_DIR> && ... の形で実行する)
ステージするファイル: <親が決めたパスの列挙>
コミットメッセージ: <親が起草した全文。改行を含むので HEREDOC でそのまま渡す>
ファイルを編集しない。メッセージを書き換えない。コミット後に git log -1 --pretty=%s の出力とコミットの SHA を返す。コミットが失敗したら、失敗したコマンドと出力をそのまま返す
```

返ってきた結果は親が次のように扱う (委譲先は照合者にならない):

- subject を `~/.claude/guidelines/core/commit.md` の形式と照合する。合わなければ、push 前に親が `git -C "$WORK_DIR" commit --amend` で直す
- コミットが失敗した (pre-commit hook の失敗・ステージ対象が空など) ときは、返された出力を親が読んで原因を直し、もう一度委譲する。直せなければ 2.6 へ

巨大出力のテスト実行 (2.4 手順 2) は、サブエージェント `general-purpose` を起動する (モデル: haiku を明示)。完了を待ってから次の手順へ進む。

- 説明: `issue #<N> の検証`
- 次の内容を渡す:

```
実行するコマンド: cd <WORK_DIR> && <コマンド> (複数あれば 1 行ずつ)
ファイルを編集しない。コマンドごとに exit code と pass/fail 件数を返し、失敗があればテスト名と原因が分かる最小限のエラー引用を添える
```

- 並列実行 (2.0) では、コマンドにスロットのポートを、プロジェクトの worktree セットアップ手順が定める形で含める (例: 環境変数の前置)。ポートを含めないと、並列で走る別の issue の検証とポートが衝突する

## Step 0: 前提チェック

```bash
REPO_DIR=$(git rev-parse --show-toplevel)
REPO_SLUG=$(gh repo view --json nameWithOwner -q .nameWithOwner)
DEFAULT=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
rg -n 'POC_NEEDED:.*blocker=true' docs/design/DESIGN.md docs/design/features/ 2>/dev/null
```

- git / gh が解決できない → 停止して案内する
- 既定ブランチは `git symbolic-ref refs/remotes/origin/HEAD` ではなく GitHub から取る。`origin/HEAD` は clone したときにしか作られず、`gh repo create --source . --push` で作ったリポジトリでは `fatal: ref refs/remotes/origin/HEAD is not a symbolic ref` で空になり、以降の `origin/$DEFAULT` がすべて壊れる
- `POC_NEEDED: ... blocker=true` が 1 件以上 → 実装に入らず、`/dev-spec` のフェーズ 5 (PoC 検証) への差し戻しを案内して停止する (未検証の技術前提の上に実装しない)
- ラベル 4 種を冪等に用意する (dev-spec を経ずに用意された issue でも 2.1 のラベル操作が失敗しないように。コマンドは `~/.claude/skills/dev-spec/references/issue-template.md`「ラベルの用意」と同一)
- **docs が push 済みか確認する**: ローカルに `docs/design/DESIGN.md` があるのに `git log origin/$DEFAULT -1 -- docs/design/DESIGN.md docs/design/features/` が空なら、ブランチ基点 (origin) に設計 docs が無い。docs を含むコミットの push を人間に依頼して停止する (2.1 のブランチは origin から切るため、push されていないと implementer が docs を読めない)。push が済んだら、人間が本スキルを再実行する
- `docs/design/DESIGN.md` が無い構成でも、issue が自己完結していれば続行してよい (issue の DoD に実行コマンドが揃っていることが条件)

作業ログ用のディレクトリを作る: `SCRATCH=<scratchpad>/dev-impl-$(date +%Y%m%d-%H%M%S)` (`<scratchpad>` はこのセッションの scratchpad のディレクトリ。report JSON の置き場で、git 管理外)。

## Step 1: issue の収集と着手順

着手順はスクリプトで計算する。対象 issue を集めて `$SCRATCH/issues.tsv` (スナップショット) に書き、着手順を出す。`$ARGUMENTS` で issue 番号が指定されていれば、番号だけを空白区切りで渡す (例: `42 43`。`#42` と書くとシェルが `#` 以降をコメントとして捨て、全件が対象になる):

```bash
sh ~/.claude/skills/dev-impl/scripts/next-issues.sh collect "$SCRATCH/issues.tsv" <番号...>
```

`next-issues.sh` は、`collect`・`mark`・`order` のどれも clone の中 (`$REPO_DIR` か、その worktree) をカレントディレクトリにして実行する。担当の印を clone の git ディレクトリに置くためで、git リポジトリの外では印を使えず、標準エラーで知らせる。

出力は 1 行に 1 issue のタブ区切りで、行の種類ごとに次のように扱う。終了コードが 0 でなければ、標準エラーの内容を添えて停止する。渡した番号のうち対象にならないもの (closed・needs-human・tracking・ready でない・存在しない・読めない `Depends on` の行がある) は、標準エラーに `#<番号> は対象にならない` と出るので、最終報告に載せる。動いている別のセッションが担当する issue は、標準エラーではなく `claimed` の行に出る。

| 行 | 意味 | 扱い |
| --- | --- | --- |
| `start <番号> <実効スコア>` | 着手できる issue。上から着手順に並ぶ | 上から着手する (2.0 の並列実行では上から枠を埋める)。互いに依存しないので同時に着手してよい。着手の最初に `mark <番号> started` で担当の印を取る (2.1 の手順 0) |
| `wait <番号> <依存先>` | close されていない依存先が残る | 依存先が close されるまで着手しない |
| `cycle <番号>` | 依存が循環している | 着手せず、最終報告に載せる |
| `unknown <番号> <依存先>` | どこにも無い issue に依存している | 着手せず、最終報告に載せる |
| `badline <番号> <行>` | `Depends on` で始まるのに読めない行がある (1 行に複数並べたなど)。対象かどうかに関わらず、open の issue すべてに出る | 着手せず、最終報告に載せる |
| `claimed <番号> <セッション>` | 動いている別の Claude Code のセッション (手元の `/dev-impl` か agent-loop の run) が担当の印を持つ。`collect` の後に印が書かれた issue も、`mark` と `order` が出す | 着手せず (依存元も待たせたまま)、最終報告の「着手できなかった issue」にセッション ID と一緒に載せる |

スクリプトが決めていること (規則の正本はこの節。実装は `next-issues.sh` の先頭のコメントと一致させる):

- **対象**: open で `ready` か `in-progress` が付き、`needs-human` と `tracking` が付かず、読めない `Depends on` の行が無く、動いている別のセッションの担当の印が無い issue。番号を渡したときは、その issue と、まだ終わっていない依存先だけ
- **担当の印**: 同じ issue を 2 つのセッションが実装しないための印で、clone の共通の git ディレクトリ (`git rev-parse --git-common-dir`) の `dev-impl-claims/<番号>` に、Claude Code のプロセスの pid (`CLAUDE_PID`) とセッション ID (`CLAUDE_CODE_SESSION_ID`) を 1 行で書く。clone の直下・各 worktree・agent-loop のどこから見ても同じ場所である
  - `collect` が対象の issue のすべてに取り、`mark <番号> started` も着手のときに取り直し、`mark <番号> closed` が消す。`collect` で取るのは、依存先を待つ issue に印が無いと、依存先が close された直後に別のセッション (agent-loop の run など) がその issue を拾うためである。Claude Code の外では `collect` は印を書けないことを 1 行で知らせる。取るときは印ごとのロック (`dev-impl-claims/.lock-<番号>`。`mkdir` で作る) の中で判定・置き換えをするので、2 つのセッションが同時に取りに来ても片方だけが取れる。動いている別のセッションが持っていれば、印もスナップショットも変えずに終了コード 3 で終わる。`mark <番号> parked` は残す (駐車した issue も、そのセッションが動いている間は対応中として扱う。人が `ready` に戻しても、agent-loop や別のセッションは拾わない)
  - pid のプロセスが動いていて、実行ファイル名 (`ps -o comm=` の先頭の語) が `claude` のときだけ、印を生きているとみなす。Claude Code のプロセスが終われば印は死んだ扱いになり、別のセッションが引き継げる。バックグラウンドのセッション (`claude --bg`) は done になってもプロセスが残るので、`claude stop` するまで印は生きている (agent-loop の run は、agent-loop が片付けで stop する)。pid が別の Claude Code のプロセスに使い回されると、そのプロセスが終わるまで死んだ印も生きて見える (着手しない側に倒れる。`claimed` の行のセッション ID で人が気付ける)
  - 自分の pid の印は自分のもので、着手の妨げにならない
  - agent-loop (dotfiles の `agents/scripts/agent-loop.ts`) も同じ印を読み、生きている印のある issue を実装の仕事に数えない
  - Claude Code の外 (`CLAUDE_PID` が無い) と git リポジトリの外では印を使えず、`collect` と `mark` が標準エラーで知らせる。その場合は、手元で動かしている間 agent-loop を止める
- **依存**: 本文の `Depends on #<番号>` の行。依存先がすべて close された issue が着手できる
- **実効スコア**: 自分と、自分に直接・間接に依存する対象 issue のスコアの最大値 (スコアの低い依存先が後回しになって、スコアの高い issue が塞がれるのを防ぐため)。スコアは本文の `## 優先度` の `スコア <数値>` で、行の先頭が `緊急枠 (` の行があれば、どのスコアよりも高い (`U` と出る。書式は `~/.claude/skills/dev-triage/references/priority.md`「issue への書き方」)。引き継ぐ元は対象 issue に限る (この run で着手できない issue のスコアで順を動かさない)。どこからもスコアを得られない issue (`/dev-spec` が作った issue など) は `-` で、スコアのある issue の後ろに置く
- **着手順**: 前回の run から再開する issue (`in-progress` か、`issue-<番号>` のブランチが手元か origin に残るもの) が先、続いて実効スコアの高い順、同じなら番号の小さい順。`priority.md`「判定の流れ」の「スコアの差が 2 割以内なら同順位として、人が決める」は使わない (実装の途中で人に聞けないので、値と番号で決める)

**issue の状態が変わるたびに、スナップショットに書いて計算し直す。** GitHub から一覧を取り直さない (run の途中で付いた `ready` は拾わない):

```bash
sh ~/.claude/skills/dev-impl/scripts/next-issues.sh mark "$SCRATCH/issues.tsv" <番号> started  # 2.1 の手順 0 で着手する (並列実行で枠を埋め直すとき、実行中の issue を start に出さない)。担当の印を取る。取れなければ終了コード 3
sh ~/.claude/skills/dev-impl/scripts/next-issues.sh mark "$SCRATCH/issues.tsv" <番号> closed   # 2.5 で close を確かめた。担当の印を消す
sh ~/.claude/skills/dev-impl/scripts/next-issues.sh mark "$SCRATCH/issues.tsv" <番号> parked   # 2.6 で needs-human に駐車した。担当の印は残す
```

`mark` も着手順を出し直す。スナップショットを書き換えずに今の着手順を見るときは `sh ~/.claude/skills/dev-impl/scripts/next-issues.sh order "$SCRATCH/issues.tsv"` を使う。

### 前回の中断からの復帰

**`in-progress` が残っている、または対象 issue に残置ブランチ `issue-<N>` がある場合は前回の中断・駐車からの復帰。** その issue の状態を確認して再開位置を決める (needs-human から `ready` に戻された issue はラベルでは区別できないため、ブランチの有無で検出する)。

**動いている別のセッションが担当する issue は、ここまで来ない。** `collect` が担当の印を見て `claimed` に出し、対象から外している (上の「担当の印」)。対象に残った issue は、印が無いか、印の持ち主のセッションが終わっているので、前のセッションの残したものを引き継いでよい。ブランチや worktree の有無、ファイルの更新時刻からは担当者を推し量らない (手元の `/dev-impl` の clone が一時的に別のブランチにいるだけでも、放置されたブランチに見えるため)。

**まず、ブランチ `issue-<N>` を checkout している worktree が残っていないかを確かめる。** 前のセッションが途中で止まると (agent-loop が `blocked` の run を止めたときなど。agent-loop は dotfiles の `agents/scripts/agent-loop.ts` が定期的に起動する run で、使わない環境では関係ない)、未コミットの差分を抱えた worktree が残る。agent-loop の run は `<clone>/.claude/worktrees/<run の名前>` で動くので、その中の `.claude/worktrees/issue-<N>` に残る。このブランチは別の worktree が checkout しているので switch できず、origin にも無いことが多い:

```bash
WT=$(git -C "$REPO_DIR" worktree list --porcelain \
  | awk -v b="branch refs/heads/issue-$N" '/^worktree /{p=substr($0,10)} $0==b{print p}')
```

`WT` が空なら下の再開表へ進む。空でなければ、その worktree を引き継ぐ (下記)。

**引き継ぐときは `WORK_DIR=$WT` とし、新しい worktree を作らず、未コミットの差分も捨てない。** 直列実行でも同じにする (`$REPO_DIR` ではこのブランチへ switch できないため)。そのうえで下の再開表から再開位置を決め、次のように読み替える。

- 「PR が open」の行: worktree を作り直さずに `$WT` を使う
- 「ブランチのみ残存」の行: switch を飛ばし、基準は `BASE_SHA=$(git -C "$WT" merge-base "origin/$DEFAULT" HEAD)` で復元する。implementer に足す行は「ブランチと作業ツリー (未コミットの差分を含む) に前回の差分がある。既存差分を前提に続きから実装せよ」とする
- 後片付け: 2.4 の merge の後は `merge-pr.sh --worktree "$WT"` が消す。2.6 の駐車では、並列実行の worktree と同じく `$WT` を `git -C "$REPO_DIR" worktree remove` で消す

前の run の SCRATCH (review JSON や証跡) は引き継がない。SCRATCH は run ごとに新しく作るため、レビューは r1 から数え直す。

| 状態 (`gh pr list --repo "$REPO_SLUG" --head issue-<N>` と、`git fetch origin` 後の `git branch --list issue-<N>` / `git branch -r --list "origin/issue-<N>"`) | 再開位置 |
| --- | --- |
| PR が open | 2.4 手順 4 (CI ゲートと merge) から。`merge-pr.sh` が PR の番号を引き直すので番号の復元は要らない。**直列実行では、先にブランチ `issue-<N>` へ switch する** (ローカルと origin で食い違えば、下の段落の ahead/behind の手順で合わせる。switch しないと `$WORK_DIR` が既定のブランチのままで、HEAD の照合が誤る)。**並列実行では worktree を作り直して `$WORK_DIR` を再設定してから入る** (rebase 分岐が使う。ブランチ `issue-<N>` が既にあるので `git -C "$REPO_DIR" worktree add "$WT" "issue-<N>"` と `-b` を付けずに作り、2.0 と同じく `.worktreeinclude` の複製と前提 1 のセットアップを行う)。検証は push 前に済んでいる前提なので繰り返さないが、`gh pr view --json headRefOid` と `git -C "$WORK_DIR" rev-parse HEAD` が一致しなければ PR 作成後に差分が足されているので、手順 2 の検証を 1 巡し、push してから CI ゲートを通して merge する (push で CI が新しい HEAD で走り直すため、push より前の CI の結果は使わない)。PR の動作確認の証跡は作成時点のもので、この run では取り直せない (implementer を起動していない)。merge の前に `gh pr comment` で「`<PR 作成時の headRefOid>` 以降の差分は動作確認の証跡を取っていない」と 1 件残す。レビュー未実施が疑われる場合は 2.3 から |
| ブランチのみ残存 (ローカルまたは origin、PR なし) | ブランチへ switch し (origin のみに在る場合は `git switch issue-<N>` が追跡ブランチを作る)、`BASE_SHA=$(git merge-base origin/$DEFAULT HEAD)` で基準を復元して 2.2 から。implementer に渡す内容 (2.2) に「ブランチに前回の差分がある。既存差分を前提に続きから実装せよ」の行を足す |
| どちらも無い | 最初から (2.1 から) |

実装途中の**未コミット**差分はマシンローカルで、別マシンには引き継げない (同じマシンなら、上の手順で worktree ごと引き継ぐ)。ブランチも push されるまではマシンローカル (2.6 の駐車時は WIP を退避して push を試みる)。別マシンで再開して残置ブランチが origin に無い場合、その issue は最初からやり直しになる — これは仕様で、issue 単位が再開の粒度である。ローカルと origin の両方にブランチが在る場合は fetch 後に ahead/behind を確認し、behind ならローカルを origin に合わせ (`git switch -C "issue-<N>" "origin/issue-<N>"`)、ahead なら push してから続行する。

## Step 2: issue ごとの実装サイクル

対象 issue を Step 1 の着手順に、次のサイクルで消化する。**着手できる issue は、着手順の上から最大 3 件まで並列に走らせる** (2.0)。並列の前提が満たせないプロジェクトでは 1 件ずつになる。

### 2.0 並列実行の可否と枠組み

直列実行では実装ループの経過時間が消化コストの総和になる。着手できる issue は互いに依存しないので、実装とレビューは同時に走らせてよい。**ただし merge は必ず 1 件ずつ直列に行う** (2.4 手順 4)。並列で merge するとデフォルトブランチが競合し、後続の rebase が連鎖する。

**並列にしてよいのは、プロジェクトが次の 3 つを満たすときだけ。** 満たさなければ**並列度 1** で回す (誤った green を出すより遅い方がよい):

1. `docs/design/DESIGN.md`「開発・検証コマンド」に **worktree セットアップ手順**が書かれている (依存インストールなど、チェックアウト直後の作業ツリーで DoD を実行可能にする手順)
2. テスト・E2E が**固定ポートを共有しない**こと。dev server を起動する検証がある場合、ポートを外から指定でき、指定したポートで起動できなければ失敗する (既存サーバに相乗りしない) 契約になっていること。**相乗りする設定 (Playwright の `reuseExistingServer: true` + 固定 `baseURL` など) のまま並列にすると、別の worktree のサーバに対してテストが通り、静かに誤った green を出す**。worktree セットアップ手順に、並列で使う基準ポートが書かれていること
3. `.claude/worktrees/` が `.gitignore` にあること。無いと、worktree を作った時点で親の作業ツリーが dirty になり、2.1 の clean チェックが全 issue で失敗する。並列を使うなら先に `.gitignore` へ追加する (それ自体を 1 コミットにしてよい)

満たす場合、空いている枠 (スロット) をすべて、Step 1 の着手順の上から埋めて流す。2.5 の完了処理か 2.6 の駐車で枠が空くたびに、着手できる issue を計算し直し、空いた枠をすべて埋め直す (1 件の merge で複数の issue が着手できるようになることがあるため)。issue を割り当てる前に、2.1 の手順 0 で担当の印を取る。取れなければ (終了コード 3) その issue は割り当てず、着手順の次の issue に移る。印を取れた issue にだけ、次の手順で worktree を作る:

```bash
# スロット s (0 始まり、最大 3) に issue N を割り当てる
# 直前に merge した依存先を含めるため、worktree を切る前に必ず fetch する
git -C "$REPO_DIR" fetch origin
WT="$REPO_DIR/.claude/worktrees/issue-$N"
git -C "$REPO_DIR" worktree add -b "issue-$N" "$WT" "origin/$DEFAULT"
```

worktree には git 管理外のファイル (`.env` 系・ローカル設定) が無いので、そのままでは DoD が実行できない。**リポジトリルートの `.worktreeinclude` に列挙されたものを複製する。** これは Claude Code が worktree を作るときにも使うファイルで、書式は `.gitignore` と同じ (1 行 1 パターン、`#` はコメント)。**複製するのは gitignored なファイルだけ**で、追跡されているファイルと、gitignore されていないファイルは対象にしない。用意するのは人間か、プロジェクトを scaffold したスキル。無ければ何も複製しない (その場合は前提 1 のセットアップ手順が代わりを果たす必要がある)。上の `worktree add` の直後に次を実行する (`git worktree add` は複製しないので、ここで行う):

```bash
if [ -f "$REPO_DIR/.worktreeinclude" ]; then
  git -C "$REPO_DIR" ls-files --others --ignored --exclude-from="$REPO_DIR/.worktreeinclude" |
    while IFS= read -r f; do
      git -C "$REPO_DIR" check-ignore -q -- "$f" || continue   # gitignore されているものだけ
      mkdir -p "$WT/$(dirname "$f")" && cp -p "$REPO_DIR/$f" "$WT/$f"
    done
fi
```

```
# .worktreeinclude の例
.dev.vars
.env.local
```

依存ディレクトリ (`node_modules` 等) は容量が大きいのでここに列挙せず、前提 1 のセットアップ手順でインストールする。

- **ポート**: スロット番号から決めて渡す (worktree セットアップ手順の基準ポート + s × 10)。implementer と review-impl には起動時の `port` の行で渡し (2.2・2.3 の fix を含む)、直列実行では `port` の行ごと省く。Haiku に委譲する検証では、プロジェクトの worktree セットアップ手順が定める形でコマンドに含める (モデル方針「Haiku への委譲」)
- **待ち方**: subagent を起動したら、その issue の subagent の完了だけを待つ。並列で走る他の issue の subagent の起動とは並列でよく、他の issue の進行は待たない
- merge した issue の worktree は、`merge-pr.sh --worktree "$WT"` (2.4 手順 4) が消す。駐車 (2.6) した issue の worktree は、WIP を push したうえで `git -C "$REPO_DIR" worktree remove "$WT"` で削除する (残すと次回の clean チェックに掛かる)

### 2.1 着手

以下の `$WORK_DIR` は、直列実行なら `$REPO_DIR`、並列実行なら 2.0 で作った worktree のパス。**implementer・review-impl には `repo_dir` としてこの `$WORK_DIR` を渡す** (どちらも絶対パスで受ける契約なので、直列・並列で指示の形は変わらない)。

0. 担当の印を取る。ブランチ・worktree・ラベルに触れる前に行う (印を取る前に触ると、同じ issue を取りに来た別のセッションと手順が交錯する)。並列実行では 2.0 で worktree を作る前にここを行う:

```bash
sh ~/.claude/skills/dev-impl/scripts/next-issues.sh mark "$SCRATCH/issues.tsv" "$N" started
```

終了コードが 3 なら、別のセッションが先に印を取っている。この issue には着手せず、出力の着手順で次の issue へ進み、最終報告の「着手できなかった issue」に `claimed` の行のセッション ID と一緒に載せる。0 なら続ける (標準エラーに「担当の印を残せない」と出たら、印は無いまま進むことになるので、最終報告に載せる)

1. `git -C "$WORK_DIR" status --porcelain` が空であることを確認する。残骸があれば run を止めて人間に報告する (前作業の未コミット差分の上に実装しない)。人間は差分を commit か stash してから本スキルを再実行する
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

サブエージェント `dev-impl-implementer` を起動する (モデル: opus を明示)。完了を待ってから次の手順へ進む (待ち方は 2.0)。

- 説明: `issue #<N> の実装`
- 次の内容を渡す:

```
mode: implement
repo_dir: <WORK_DIR>
base_sha: <BASE_SHA>
issue_number: <N>
port: <スロットのポート>
report_path: <SCRATCH>/impl-<N>.json
evidence_dir: <SCRATCH>/evidence-<N>
```

- `port` の行は 2.0 の決まりに従う
- `evidence_dir` は直列・並列のどちらでも渡す。issue ごとに分けるので、並列で走る issue の証跡は混ざらない

**検収**: report JSON を読み、次をすべて満たすときだけ `status: done` を done と扱う。

- `test_result.exit_code = 0`・`dod_result.exit_code = 0`・`self_review.checklist_applied = true`
- `self_review.basic_checks` の 4 つ (`new_behavior` / `removed_behavior` / `touched_specs` / `new_branches`) がすべて空でない。`self_review.change_types` が空でない
- `self_review.change_types` に「その他」がある場合、`self_review.other` の各項目に `summary` / `axes` (`spec` / `layer` / `artifact`) / `answers` (4 問い) が埋まっている
- `sh ~/.claude/skills/dev-impl/scripts/added-comments.sh "$WORK_DIR" "$BASE_SHA"` を親が実行し、出力の `<パス>:<行番号>` が `self_review.comments.kept` の `at` と過不足なく一致する。終了コードが 0 でなければ照合できないので、原因を直して実行し直す
- `evidence.manifest_path` の `manifest.json` があり、その `captured_mode` が今回起動した `mode` と一致し、`screens[].file` と `api[].file` の全パスが実在する (`ls` で確かめる)。実在しないパスを 2.4 手順 3 に渡すと添付が失敗し、本文にローカルのパスが残る。画面と API が両方とも空なら `note` に理由が書かれていること
- UI に触れる issue でプロジェクトが視覚テストを持つ場合は、加えて `ui_evidence.screenshots` が空でないこと (implementer が自分で画像を見た記録)。親は画像を開かない。差分で追加・更新された基準画像は、2.3 の review-impl が検査項目 5 で開いて見る

検収に落ちた報告の扱い:

- **同じ `mode: implement` で 1 回だけ再起動する**。渡す内容に「前回の報告は `<満たさなかった項目>` で検収に落ちた。そこを満たしてから報告せよ」の行を足す。セルフチェックの記録が不足している場合は、`basic_checks` / `change_types` / `other` / `comments.kept` のどこが足りないか (コメントは一致しない行)を具体的に伝える
- `mode: fix` は使わない。`mode: fix` は `findings_path` の JSON の指摘を直す契約なので、findings を伴わない差し戻しでは修正対象が 0 件になる
- **この再起動は 2.3 の fix ラウンドに数えない**。実装の検収であって、レビュー指摘の修正ではないため
- **2 回目の報告も検収に落ちたら 2.6 へ** (数えない代わりの停止条件)

分岐:

- `done` (検収済み) → 2.3 へ
- `escalate` / `failed` (`contract_break` / `spec_insufficient` / `tests_failing`。`test_weakening_suspected` は fix 時のみ発生) → 2.6 へ (report の summary にある試行記録を issue コメントに使う)
- **subagent がエラー、または report JSON が無い・パース不能** → 同条件で 1 回だけ再起動する。再失敗なら 2.6 へ

### 2.3 レビュー (review-impl subagent、修正 ≤ 1 ラウンド)

サブエージェント `review-impl` を起動する (モデル: opus を明示)。完了を待ってから次の手順へ進む (待ち方は 2.0)。

- 説明: `issue #<N> のレビュー`
- 次の内容を渡す:

```
repo_dir: <WORK_DIR>
base_sha: <BASE_SHA>
issue_number: <N>
focus: all
port: <スロットのポート>
previous_findings_path: <SCRATCH>/review-<N>-r1.json
report_path: <SCRATCH>/review-<N>-r<ラウンド>.json
```

- `base_sha` は 2.1 で控えた値を渡す
- `port` の行は 2.0 の決まりに従う
- `previous_findings_path` の行は r2 でだけ渡し、r1 (初回) では行ごと省く

**レビューと修正の回数はこう数える。初回レビューを r1 とし、レビューのたびに 1 ずつ増やす** (この採番が review JSON (`report_path` と `previous_findings_path`) のファイル名に出るので、あとから何周したかを人も自分も数えられる。r0 から始めると 1 周ぶん過少に数えることになる)。レビューは r1 (実装直後) と r2 (fix の後の確認) の**最大 2 回**、`mode: fix` は r1 の findings に対する**最大 1 回**。`previous_findings_path` は r2 の 1 回だけ渡る。

`previous_findings_path` を渡すと、レビュワーは「前ラウンドの指摘が閉じたか」に加えて「同じ壊れ方が別の箇所へ転移していないか」を検査する (review-impl の検査項目 6)。渡さないと fresh context のレビュワーは前ラウンドの存在を知らないため、修正が作った同型の穴を見逃す。**再開 run で前 run の review JSON が SCRATCH に無い場合は渡さない** (SCRATCH は run ごとに新規作成されるため)。その場合は項目 6 が働かないことを、完了コメントの「レビュー:」の行に記す (2.5 の形式)。

**`checked` の検収**: findings の件数を見る前に `checked` を確認する。次のいずれかなら検査が成立していないので、指示を明確化して 1 回再実行し、再発なら 2.6 へ (「何も検出できない検証の実行は検証ではない」):

- `tests_run: false`
- UI に触れる差分なのに `e2e` が理由の無い `skipped`
- 視覚テストを持つプロジェクトの UI に触れる差分なのに `ui_layout` が理由の無い `skipped`
- `previous_findings_path` を渡したのに `previous_findings` が `none` (検査項目 6 の未実施) または `unreadable(...)` (パスの渡し間違い — この場合はパスを直して再実行する)

review JSON が無い・パース不能の場合も同様に 1 回再起動 → 再失敗で 2.6。**検収の失敗による再実行は同じ `report_path` を上書きする** (r 番号を進めない。r 番号は fix 済みか否かの判定と `previous_findings_path` の選択に使われるので、実際には行われていない fix を数えてしまう)。

#### 指摘の扱い

severity ごとに、次のとおり扱う (基準の正本は review-impl の「severity と報告の基準」)。

| severity | 動作 |
| --- | --- |
| `high` | 修正 1 回 → r2 |
| `medium` | 修正 1 回。`high` が無ければ r2 を回さず、2.4 手順 2 の全テストで確かめる |
| `decision` | 直さない。人が決めるまで merge せず、2.6 で駐車する |
| `followup` | 直さない。merge を止めず、issue にする (下記「issue にする指摘」) |

r1 の findings による分岐:

1. **`category: test-weakening` の finding を先に裁定する** (下記)。implementer に渡すと `test_weakening_suspected` で escalate が返り、2.2 の分岐で 2.6 へ落ちて裁定を飛ばしてしまう
2. **`decision` が 1 件以上あれば、fix を起動せずに 2.6 で駐車する** (決まった内容で直し方が変わり、先に直しても無駄になりうるため)
3. 残った `high` と `medium` で分ける:
   - **どちらも 0 件** → 2.4 へ
   - **1 件以上** → implementer を `mode: fix` (`findings_path` に review JSON を指定) で起動し、`high` と `medium` をまとめて直させる。**fix はこの 1 回だけ (固定)**

`high` の有無は裁定の後に数える。`medium` だけの修正を再レビューしないのは、修正が小さく、周回を増やさないためである。

fix は、サブエージェント `dev-impl-implementer` を起動する (モデル: opus を明示)。完了を待ってから次の手順へ進む (待ち方は 2.0)。

- 説明: `issue #<N> の修正`
- 次の内容を渡す:

```
mode: fix
repo_dir: <WORK_DIR>
base_sha: <BASE_SHA>
issue_number: <N>
port: <スロットのポート>
findings_path: <SCRATCH>/review-<N>-r1.json
report_path: <SCRATCH>/impl-<N>-fix.json
evidence_dir: <SCRATCH>/evidence-<N>
```

- `port` の行は 2.0 の決まりに従う
- `findings_path` は、`test-weakening` の裁定の印 (`adjudication`) を書き足した後の r1 の review JSON を指す
- `report_path` は 2.2 の `impl-<N>.json` と別名にする (実装時の報告を上書きしない)

返った report には 2.2 と同じ検収 (`test_result` / `dod_result` の exit code と `self_review`、証跡の `manifest.json`、UI に触れる issue では `ui_evidence`) を当てる。加えて、`findings_result` に、対象の finding (裁定済みを除く `high` と `medium`) が 1 件ずつ過不足なく載っていることを確かめる。fix は `implement` と同じ `evidence_dir` に証跡を取り直すので、検収後の `manifest.json` の `captured_mode` は `fix` になる。

- 検収を通った `done` → r1 に `high` があれば r2 を回す。無ければ 2.4 へ
- `escalate` / `failed` → 2.6 へ
- 検収落ち・subagent のエラー・report JSON が無い・パース不能 → 同じ `mode: fix` で 1 回だけ再起動する。渡す内容と `findings_path` は変えず、検収落ちのときは 2.2 と同じく満たさなかった項目の行を足す。**この再起動は fix ラウンドに数えない** (「fix はこの 1 回だけ」の 1 回は、r1 の findings に対する修正の機会を数える)。再起動後も検収を通った `done` にならなければ 2.6 へ

**r2 に `decision` があれば 2.6 で駐車する。`decision` も high も無ければ 2.4 へ進む。** r2 で新たに出た `medium` は直さない (「issue にする指摘」)。r2 に high がある場合 (r1 の残存か、r2 で新たに出たかを問わない) は、その high の `category` で分岐する。**契約・証跡・検証器が壊れているものだけを駐車し、成果物の内部品質は issue にして先へ進む**:

| `category` | 動作 |
| --- | --- |
| `spec-compliance` | 2.6 で駐車。契約が壊れたまま merge すると、後続 issue がその契約に依存して誤った土台の上に積み上がる |
| `e2e` | 2.6 で駐車。E2E の不在・失敗は「画面が動く証跡が無い」ことを意味する |
| `test-weakening` | 下記の裁定を先に行い、**裁定できないときだけ** 2.6 で駐車する (裁定して直せたら 2.4 へ。再レビューはしない) |
| `test-quality` | issue にして 2.4 へ。実装は契約を満たしており、テストが弱いだけなので後から独立に直せる |
| `code-quality` | issue にして 2.4 へ。動作は正しく、DI 違反などは後から直せる |
| `ui-layout` | issue にして 2.4 へ。契約は満たしており、見た目の崩れは後から独立に直せる |

**駐車する category と issue にする category が混在したら、issue 全体を 2.6 へ駐車する** (issue にするはずだったぶんは駐車コメントに列挙する。壊れた契約を抱えた issue を merge しないことが優先する)。

`test-quality` の high を issue にして merge するのは、no-op に置き換えても通るテスト (`~/.claude/guidelines/core/testing.md` のリトマス試験 B に落ちるもの) を抱えたまま先へ進むことを意味する。**これは意図した受容**なので、完了コメントと最終報告では、high から作った issue を先に出し、ユーザーが気付ける状態にする。

**3 周目に入りたくなったら、それは「収束していない」という信号**なので、上の表に従う。**この上限を強制する機械ゲートは無い。自律遵守する。** 上限は機械ゲートが無い状態で実際に破られる (実測: 22 issue 中 6 件が 3 周目以降に入り、規定超過分だけで 5.7h を消費した)。破らないための手立ては、review JSON のファイル名にあるラウンド番号を毎回自分で読むことだけである。3 周目を回してよいのは、2.6 で駐車して人間の回答を得たうえでスキルを再実行した場合だけである (新しい SCRATCH で r1 から採番し直す)。

**`category: test-weakening` の finding** は、ラウンドを問わず implementer に直させず親が裁定する: 弱体化が事実なら該当テストを基準時点の強度に戻す修正だけを親が直接行う (最小差分。再レビューは不要 — 2.4 の検証が確かめる。ラウンド数にも数えない)。誤検出なら根拠を review JSON に追記して次へ進む。**基準時点の強度に戻すとテストが red になる場合は裁定不能**で、実装が元の契約を満たしていないということなので 2.6 へ駐車する。

**裁定した finding には、その review JSON の該当 finding へ `"adjudication": {"verdict": "false_positive|fixed_by_parent", "rationale": "<根拠の一文>"}` を足す。** r1 の JSON は r2 で `previous_findings_path` としてレビュワーに渡るため、印を付けないと裁定済みの指摘が「未解消」として再計上され、同じ指摘で駐車に落ちる (レビュワー側は `adjudication` の付いた finding を残存判定の対象外にする規約)。

#### issue にする指摘

次の指摘は、この PR では直さず、merge の後に issue にする。

- r1 と r2 の `followup`
- r2 を回したとき: r2 の `medium` (新しく出たものも、r1 から残ったものも) と、r2 に残った `test-quality` / `code-quality` / `ui-layout` の `high`
- r2 を回さなかったとき: fix の `findings_result` が `not_fixed` の `medium`

r1 と r2 の両方にある指摘は、category と summary の中身で突き合わせて 1 件にする (fix で行がずれるので `file:line` では判定しない)。

1 件以上あれば、**PR を作った直後 (2.4 手順 3) に、全文を PR のコメントに 1 件で残す。** 指摘は SCRATCH にしか無く、SCRATCH は次の run に引き継がれないので、途中で止まっても落とさないためである。コメントは `<SCRATCH>/findings-<N>.md` に Write し、`gh pr comment <PR 番号> --repo "$REPO_SLUG" --body-file` で投稿する。同じ PR に以前の `dev-impl-findings` のコメントがあれば、`gh api -X PATCH "repos/$REPO_SLUG/issues/comments/<ID>" -F body=@<SCRATCH>/findings-<N>.md` で置き換える (レビューをやり直さずに再開した run では触らない)。

```markdown
<!-- dev-impl-findings: pending -->
この PR では直さず、merge の後に issue にする指摘。

### 1. [<severity>/<category>] <summary>
- 場所: `<file>:<line>`
- 起きること: <impact>
- 根拠: <evidence>
- 直し方の案: <fix_hint。`not_fixed` なら、直せなかった理由も書く>
- 決めること: <直し方が決まらない `followup` のときだけ。選択肢と、それぞれを選ぶと起きること>
```

issue は、このコメントから作る (2.5 と Step 3)。駐車した issue では作らない。PR のコメントが無い駐車 (PR を作る前に止まったとき) では、駐車のコメントに列挙する (2.6)。

### 2.4 コミット・検証・PR・merge

1. **コミット**: 変更を論理単位で Conventional Commit (`~/.claude/guidelines/core/commit.md`。STRUCTURAL / BEHAVIORAL 分離) にする。メッセージ起草とステージ対象の決定は親、実行は Haiku subagent に委譲してよい (モデル方針「Haiku への委譲」)。implementer の `docs_updates` (乖離補正) も同じ issue の**コミット列**に含める (関心事分離に従い docs は独立コミットでよい)。

   コミットが手順 2 の検証より前に来るのは、検証対象を「積み終えた差分」に固定するためである。`~/.claude/guidelines/core/commit.md` のコミット条件 (全テスト green) は、implementer の `test_result` / `dod_result` が exit 0 であること (2.2 の検収で確認済み) を根拠に満たす。**手順 2 が red だった場合、このコミットは merge されない駐車ブランチ上の記録として扱う** (2.6 の WIP 退避と同じ例外)。

2. **検証 (1 巡)**: 最後のコミットを積んだ後・push の前に、**プロジェクトのテストスイート全体 + lint + フォーマット検査 + issue の `## DoD` のコマンド**をまとめて 1 回実行し、すべて exit code 0 であることを確認する。**CI の有無に関わらずこのローカル検証を行う**。issue の DoD は CI に含まれないのでここでしか検証されず、red のまま push すると CI の実行を 1 回無駄にするためである。CI の結果は手順 4 の CI ゲートで merge の前に待つ。**実行は `$WORK_DIR` で行う** (並列実行では worktree の中。Haiku subagent に委譲する場合は `cd <WORK_DIR> && ...` の形でコマンドを渡さないと別の作業ツリーを検証することになる)。出力が巨大になると実行前に分かっているもの (E2E と、出力が数千行を超えると分かっているスイート) は実行だけ委譲し、pass/fail 件数と失敗の要点を受け取る (起動と渡す内容はモデル方針「Haiku への委譲」)。Bash ツールの上限 (600000 ms = 10 分) を超えうる検証は、委譲先でも同じ上限に当たるので、バックグラウンドで実行して終わりの通知を待ち、exit code で判定する。

   **同じコマンドを二度走らせない。** issue の `## DoD` に並ぶコマンドが `docs/design/DESIGN.md`「開発・検証コマンド」の全体テスト・lint と重複する場合は 1 回だけ実行する。**重複と見なすのは前後の空白を除いた文字列が完全一致するときだけ**で、包含関係 (`deno test src/export/` と `deno test`)・オプション違い・言い換えは重複と見なさず両方実行する (部分集合を「同じ」と読むと DoD の検証をしないまま green を宣言できる)。DESIGN.md が無い構成と、DESIGN.md はあるが「開発・検証コマンド」節が無い構成では、同一性を判定できないので重複排除せず両方実行する。

   **フォーマット検査のコマンド**は次の順で最初に見つかったものを使う:

   1. `docs/design/DESIGN.md`「開発・検証コマンド」に書かれたフォーマット検査
   2. issue の `## DoD` に含まれるフォーマット検査
   3. プロジェクトの設定ファイルからの推定 (下表。複数当たれば全部実行する)
   4. どれも無ければ実行しない。PR 本文の「検証」節と 2.5 の完了コメントに「フォーマット検査: 定義なし (推定不能)」と書いて先へ進む

   | 手がかり | 実行するコマンド |
   | --- | --- |
   | `deno.json` / `deno.jsonc` | `deno fmt --check` |
   | `Cargo.toml` | `cargo fmt --check` |
   | `package.json` の `scripts` に `format:check` か `fmt:check` | `npm run <そのスクリプト名>` |
   | `biome.json` / `biome.jsonc` | `npx biome format .` |
   | `.prettierrc*` | `npx prettier --check .` |
   | `go.mod` | `test -z "$(gofmt -l .)"` |
   | `flake.nix` の `formatter` | `nix fmt -- --ci` |

   **ファイルを書き換えずに差分だけを報告する check 系のコマンドに限る。** 手順 1 でコミット済みなので、書き換える formatter を走らせると整形結果が作業ツリーに残り、コミットにも PR にも乗らない。

   検証の E2E には `E2E_EVIDENCE_DIR` を付けない。証跡は最後に done になった implementer の報告のものを使い、ここでは書き出さない (全 spec が書き出すと他の機能の画像が混ざる)。

   1 つでも失敗したら push も merge もしない → 2.6 へ (「テスト red / DoD 失敗」の駐車)。

3. **PR**: **push は毎回行う** (`git -C "$WORK_DIR" push -u origin "issue-$N"`)。再開でスキップしてよいのは PR の作成だけで、push を飛ばすと再開後に足した差分が PR に載らないまま merge される。push が失敗したら (前 run の同名 remote ブランチ残骸等)、原因を確認して解消できなければ 2.6 へ。

   PR はスキル `workflow-create-pr` の非対話モードで作る。まず本文の下書きを `<SCRATCH>/pr-<N>.md` に Write する。「動作確認」節は書かない (スキルが証跡から足して、`🤖 Generated` の行の直前に入れる)。**先頭行の `Closes #<N>` は必ず書く。** この行で PR が issue の Development に紐づき、merge で issue が close される。紐づいたかはスキルが確かめる:

```markdown
Closes #<N>

## 変更の要約
<implementer の summary>

## 検証
- テスト + lint + フォーマット検査 + DoD: 手順 2 でローカル実行し全て green (<passed/failed 件数>。フォーマット検査が定義なしならその旨)
- レビュー: review-impl <ラウンド数> 周 (直した指摘 <f> 件・issue にする指摘 <k> 件。0 件ならその旨)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

   続けて Skill ツールで `workflow-create-pr` を次の引数で起動する。`--evidence` には、**最後に done になった implementer の報告** (fix を回したなら `impl-<N>-fix.json`) の `evidence.manifest_path` を渡す。`--draft` は渡さない (Draft PR は手順 4 で merge できない):

```
--yes --repo <REPO_SLUG> --repo-dir <WORK_DIR> --base <DEFAULT> --head issue-<N> --title "<issue タイトル>" --body-file <SCRATCH>/pr-<N>.md --evidence <manifest_path>
```

   スキルの最終行で分岐する:

   | 最終行 | 動作 |
   | --- | --- |
   | `PR_CREATED <url>` / `PR_UPDATED <url>` | 「issue にする指摘」(2.3) があれば PR のコメントに残してから、手順 4 へ |
   | `PR_FAILED secret_detected <ファイル>:<行>` | 証跡のマスク漏れ。報告される行は最終本文 (`<SCRATCH>/pr-<N>.md.final.md`) のものなので、その行の内容で `<SCRATCH>/evidence-<N>/api/` を `rg` して元の証跡ファイルを特定する。親がその箇所を `<masked>` にして、同じ引数で 1 回だけ再起動する。再発したら 2.6 へ |
   | `PR_FAILED attach_partial <url>` | PR はできたが本文に画像のローカルパスが残っている。同じ引数で 1 回だけ再起動する (同じ head の PR を更新する)。再発したら 2.6 へ |
   | `PR_FAILED issue_link <url>` | PR はできたが issue の Development に紐づいていない。下書きの先頭行が `Closes #<N>` であることを確かめ、違っていれば直して同じ引数で 1 回だけ再起動する。下書きが正しいか、再発したら merge せずに 2.6 へ (人が issue の画面の Development から紐づける) |
   | それ以外の `PR_FAILED` | 理由を見て直せるもの (引数の渡し間違い) は直して 1 回だけ再起動し、直せなければ 2.6 へ |

4. **CI ゲートと merge**: ローカル検証は手順 2 で済んでいるので、ここでは CI があればその pass を待ってから merge し、後片付けと 2.5 の完了処理までを、スクリプトで行う。`$REPO_DIR` (clone の直下か、agent-loop の run の worktree) で実行し、並列実行と Step 1 で引き継いだ worktree では `--worktree "$WT"` を付ける。スクリプトは実行した場所を `$REPO_DIR` として扱うので、run の worktree を消すことはない。issue の worktree (名前が `issue-<番号>`) の中で `--worktree` なしに実行すると、何も変えずに終了コード 1 で止まる:

```bash
sh ~/.claude/skills/dev-impl/scripts/merge-pr.sh "$N" [--worktree "$WT"]
```

CI を最大 60 分待つので、Bash ツールの上限 (600000 ms) を超えうる。**バックグラウンドで実行し、終わりの通知を待ってから**終了コードで分岐する。CI の待ちは出力が小さいので Haiku に委譲しない。**並列実行でも merge はここで 1 件ずつ直列に行う**: 前の `merge-pr.sh` の終わりの通知を受けるまで、次の `merge-pr.sh` を起動しない。同時に merge するとデフォルトブランチが競合し、残りの worktree がまとめて rebase 待ちになる。他の issue が実装・レビュー中でも、merge の順番待ちだけを直列化すればよい。gh の 1 回の呼び出しが応答しないまま固まった場合はスクリプトの上限が効かない。起動と同時に、上限 + 10 分 (既定では 70 分) で自分を起こす手段を用意する (ランタイムに定期的に起こす機能があればそれを使い、無ければ並列の他の作業の合間に経過時間を確かめる)。その時刻を過ぎても通知が来なければ、バックグラウンドのタスクを止めて 2.6 へ進む。

| 終了コード | 意味 | 動作 |
| --- | --- | --- |
| 0 | merge と完了処理を終えた | 出力の `CI:` の行を 2.5 の完了コメントにそのまま使い、`BRANCH:`・`PARENT:` の行は 2.5 の表と Step 3 の最終報告に回す。2.5 へ |
| 1 | 使い方の誤り、gh か git の失敗。merge の後に PR の状態を取れなかったとき (`MERGE_UNKNOWN:` の行) も 1 | `MERGE_UNKNOWN:` なら同じコマンドを 1 回だけ再実行する。merge 済みなら `ALREADY_MERGED:` の行が出て後片付けと完了処理だけを行い、`CI:` の行は出ないので、完了コメントの CI の欄は 1 回目の出力を使う。2 回目も `MERGE_UNKNOWN:` なら、merge 済みかもしれないので駐車せず、`mark <番号> parked` を書いて依存元を待たせ、Step 3 の最終報告で PR の状態を人に確かめてもらう。`MERGE_UNKNOWN:` 以外は標準エラーを添えて 2.6 へ |
| 10 | `issue-$N` の PR が無い (`NO_PR`) か、PR が issue を close しない (`NOT_LINKED`) | 2.6 へ |
| 11 | CI が失敗した (`CI_FAIL:` の行に check の名前とリンク) | merge せず 2.6 へ。fix のラウンドは回さない。ローカル検証が green で CI だけが red なのは環境差の疑いが強く、どちらを正とするかは人間が決める。駐車コメントに `CI_FAIL:` の行を列挙する |
| 12 | CI が上限 (既定 60 分) までに終わらない (`CI_TIMEOUT`) | merge せず 2.6 へ (CI のタイムアウト) |
| 13 | PR がコンフリクトしていて merge できない (`CONFLICT`。`mergeable` が `CONFLICTING`、または `mergeStateStatus` が `DIRTY` か `BEHIND`) | 下記の rebase 復旧を **1 回だけ**試みる。復旧の後も 13 なら 2.6 へ |
| 14 | merge できない・`MERGED` にならない (`NOT_MERGED`) | 2.6 へ (branch protection・権限・マージキュー・API の遅延など、rebase では解けない原因が疑われる。出力の `mergeable` と `mergeStateStatus` を駐車コメントに書く) |
| 15 | merge は済んだが、issue の close か `in-progress` の除去に失敗した (`MERGED_INCOMPLETE`) | **駐車しない** (merge は済んでいる)。同じコマンドを 1 回だけ再実行する (open の PR が無いので merge 済みの PR を引き直し、`ALREADY_MERGED:` の行を出して後片付けと完了処理だけをやり直す。このとき `CI:` の行は出ないので、完了コメントの CI の欄は最初の実行の出力を使う)。それでも 15 なら、失敗した `ISSUE:`・`LABEL:` の行を Step 3 の最終報告に載せる。どちらの場合も merge は済んでいるので `mark <番号> closed` を書いて次の issue へ進む |
| 16 | PR の HEAD が手元のブランチの HEAD にならない (`HEAD_MISMATCH`) | 手元の HEAD を push したかを確かめる。push していなければ push して 1 回だけ再実行する。push 済みで違うなら、手元に無いコミットが PR にある (人か別の run が push した) ので 2.6 へ |

表に無い終了コード (`sh` が見つからない 127 など) が出たら、標準エラーを添えて 2.6 へ。

スクリプトが守っている規則 (変えるときは `merge-pr.sh` も同じに直す):

- **PR の番号を引き直し、空なら何もしない**: PR は `issue-$N` のブランチから引き直す (手順 3 のスキルが返す URL は会話に残るだけで、再開経路では手順 3 自体を通っていない)。`gh pr merge --repo X "" --squash` は位置引数が空だと**カレントブランチの PR にフォールバックする**ので、別の issue のブランチに居ると無関係な PR を merge しうる
- **PR が issue を close することを merge の直前に確かめる**: 再開経路 (Step 1 の再開表の「PR が open」) は手順 3 を通らず、前の run が作った PR をそのまま merge するため
- **CI を確かめたコミットを merge する**: PR の HEAD (`headRefOid`) が手元のブランチの HEAD に追いつくまで 10 秒おきに最大 12 回待ち、`gh pr merge --match-head-commit` でそのコミットに限って merge する。rebase と force-push の直後や再開経路では、PR の HEAD の反映が遅れることがあり、古いコミットの checks を見て新しいコミットを merge しうるため
- **CI の有無は、PR に登録された checks の件数 (`statusCheckRollup`) で判定する**: `gh pr checks` は checks が 1 件も無い PR で `no checks reported` を出して exit 1 を返し、`--json` を付けても同じなので、exit code では「CI なし」と「CI が fail」を区別できない (gh 2.102.0・2.103.3 で実測)。push の直後は checks の登録が遅れるので、workflow のファイルがあれば 10 秒おきに最大 12 回 (約 2 分) 件数を引く。0 件のままなら CI なし (`paths:` などの条件でこの PR では走らない構成を含む) として、手順 2 のローカル検証を根拠に merge する
- **CI の待ちには上限を設ける**: `gh pr checks --watch` は上限を持たないので使わず、30 秒おきに `bucket` を引き直す。全件が `pass` か `skipping` なら merge、`fail` か `cancel` が 1 件でもあれば (pending が残っていても) 止まる。知らない `bucket` は終わっていないものとして待つ。上限 (`--ci-timeout <分>`、既定 60 分) は、checks の登録を待ち始めてからの経過時間で数え、過ぎても終わらなければ止まる。`gh pr checks` の失敗は 2 回までなら待って引き直し、3 回続いたら止まる。`--required` は付けない (branch protection が必須にした checks だけでなく全 checks を見る)
- **merge の成否は PR の状態が `MERGED` かで判定する**: `--delete-branch` の副作用は gh のバージョンと引数によって変わり、成功しても非ゼロを返す構成がありうる。exit code が非ゼロで `MERGED` でなければ、`mergeable` と `mergeStateStatus` でコンフリクト (13) かそれ以外 (14) かを分ける。exit code が 0 で `MERGED` でなければ、状態を 1 回だけ引き直す
- **merge の後は止めない**: 後片付けと完了処理は、失敗しても最後まで進め、失敗があれば 15 を返す。merge 済みの issue を駐車すると、再実行しても open の PR が無く、完了処理に戻れないため
- **手元のブランチは自分で消す**: `gh pr merge --repo <slug> --delete-branch` はリモートのブランチしか消さない (gh 2.97.0 で実測。`--repo` を指定するとローカル削除の経路を丸ごと無効化する)。残すと Step 1 の再開判定が「中断からの復帰」として誤発火し、次回の `worktree add -b issue-$N` も失敗する。worktree をブランチより先に消し、チェックアウト中なら既定のブランチへ switch してから消す。消せなければ**駐車はせず** (merge は済んでいる) 出力の `BRANCH:` の行を最終報告の残存ブランチに載せる

**終了コード 13 (コンフリクトの疑い) の復旧**: 駐車 → 再開の間や、並列の先行 merge でデフォルトブランチが進んだ場合に起きる。`git -C "$WORK_DIR" fetch origin` で先行 merge を取り込んでから `git -C "$WORK_DIR" rebase origin/$DEFAULT` を試み、**その作業ツリーで手順 2 の検証をもう 1 巡回して green を確認してから** `git -C "$WORK_DIR" push --force-with-lease origin "issue-$N"` で押し直す (rebase 後は履歴が書き変わっており、素の push は non-fast-forward で必ず拒否される)。先行 merge の内容と組み合わせて壊れていないかは、rebase 後に実行するまで分からない。解消できなければ `git -C "$WORK_DIR" rebase --abort` で rebase の前に戻してから 2.6 へ。rebase では動作確認の証跡を取り直さない (この issue 自身の差分は変わらない)。押し直したら `gh pr comment` で「rebase 後の HEAD は `<sha>`。動作確認の証跡は rebase 前の `<sha>` で取ったもの」と 1 件残す。押し直すと CI が新しい HEAD で走り直すので、`merge-pr.sh` をもう一度実行する (PR の HEAD が押し直したコミットに追いつくのを待ち、CI ゲートの最初、checks の登録を待つところからやり直す)。復旧は 1 回までとし、もう一度 13 が出たら 2.6 へ。

### 2.5 完了処理

`merge-pr.sh` (2.4 手順 4) が、merge の後に次を済ませている。出力の行で結果を確かめる:

- **issue の close**: merge の `Closes #N` で自動 close されていなければ close する (`ISSUE:` の行)
- **`in-progress` を外す**: close しても作業中のラベルは自動では外れず、残ると閉じた issue が作業中に見え、`in-progress` で探す再開の判定 (Step 1) にも紛れる (`LABEL:` の行。外せなかったときは終了コード 15 になるので、2.4 の表に従う)
- **親 (tracking issue) の close**: 親を逆引きし、親が open で子がすべて完了していれば close する (`PARENT:` の行)。子の数は API が数える `sub_issues_summary` を使い、自前で子を列挙して数え直さない (取りこぼしによる誤 close を避ける)。merge 直後は `Closes #N` の自動 close が非同期で、最後の子でも完了数が古い値のことがある — **再試行はしない**。取りこぼしは Step 3 の掃き掃除が回収する。API の挙動の正本は `~/.claude/skills/dev-spec/references/issue-template.md`「親への紐付け (GitHub sub-issues API)」の実測表

| `PARENT:` の行 | 動作 |
| --- | --- |
| `#<親> を close した` / `#<親> は open のまま` / `#<親> は close 済み` | 何もしない |
| `なし (親に紐付いていない)` | **正常系**。ただし dev-spec の紐付け漏れの兆候なので、番号を控えて Step 3 の最終報告に載せる |
| `確かめられない (...)` か `#<親> を close できなかった` | 親の close をスキップし、番号を控えて Step 3 の最終報告に載せる (紐付いていない場合と同じ扱いに丸めない。Step 3 の掃き掃除がもう一度判定する) |

`BRANCH:` の行が「消した」「手元に無い」以外 (消せない・残った・確かめられない) なら、その行を Step 3 の最終報告の「消せなかったブランチ・worktree」に載せる。

**PR に `<!-- dev-impl-findings: pending -->` のコメントがあれば、完了コメントの前に、指摘 1 件につき issue を 1 件作る** (SCRATCH の有無や再開かどうかに関わらず、PR のコメントを読んで作る)。dev-triage が指摘ごとに採点するので、束ねない。状態のラベルは付けない (未整理として dev-triage が拾う。agent-loop に登録していないリポジトリでは、人が `/dev-triage` を起動する)。

1. 作成済みの印を調べる: `gh issue list --repo "$REPO_SLUG" --state all --limit 100 --json number,body --jq '.[] | select(.body | contains("dev-impl-finding: PR #<PR 番号>-")) | [.number, (.body | capture("dev-impl-finding: PR #<PR 番号>-(?<n>[0-9]+)").n)] | @tsv'`。印のある通し番号は飛ばす
2. 残りを `gh issue create --repo "$REPO_SLUG" --title "<summary を 1 行にしたもの>" --body-file <ファイル>` で作る。本文は次の形にする

```markdown
<summary。設計書を読んでいない人が分かる文章で書く>

## 起きること
<起きること>

## 決めること
<決めること。無ければ節ごと書かない>

## 根拠
<場所と根拠>

## 直し方の案
<直し方の案>

#<N> の実装 (PR #<PR 番号>) のレビューで見つかり、直さずに merge した指摘。severity は <high|medium|followup>。

<!-- dev-impl-finding: PR #<PR 番号>-<通し番号> -->
```

3. 全件を作れたら、PR のコメントの `pending` を `done` に書き換える。作れなかった指摘があれば `pending` のまま残し、最終報告の「issue にできなかった指摘」に書く (次の run の Step 3 が作り直す)

完了コメントは、中身を知っているエージェントが 1 件残す (`CI:` の行は `merge-pr.sh` の出力をそのまま書く):

```
実装完了 (dev-impl)
- 変更: <summary と主要ファイル>
- テスト + lint + フォーマット検査 + DoD: <2.4 手順 2 で最後に実行した巡の結果 (件数)>、green (フォーマット検査が定義なしならその旨)
- CI: <pass (check 名の列挙) / なし (checks 未登録)>
- レビュー: <ラウンド数> 周 (直した指摘: high <h> 件・medium <m> 件)<前 run の review JSON が無く前ラウンドの指摘を再検査していなければ「(前ラウンドの指摘の再検査なし)」>
- issue にした指摘: <high から先に、各 1 行で `#<作った番号>` + severity + summary。なければ「なし」>
- 設計判断・docs 更新: <design_decisions / docs_updates の要約、なければ「なし」>
```

次の issue へ進む (Step 2 の先頭へ)。次の issue は `sh ~/.claude/skills/dev-impl/scripts/next-issues.sh mark "$SCRATCH/issues.tsv" "$N" closed` が出す着手順で決める (Step 1)。

### 2.6 エスカレーション (needs-human 駐車)

次の解消できない issue を駐車する:

- r2 の後に残った `spec-compliance` / `e2e` の high (fix で `not_fixed` になったものを含む) と、裁定できない `test-weakening`
- r1 か r2 の `decision` (指摘ごとに、起きること・選択肢・それぞれを選ぶと起きることを駐車コメントに書く)
- implementer の `escalate`、DoD の失敗、テストの red、subagent の再失敗
- 直せないコミットの失敗、push の失敗
- 再起動しても `PR_CREATED` / `PR_UPDATED` を返さない PR の作成、issue の Development に紐づかない PR
- `merge-pr.sh` の終了コード 10・11・12・14・16 と、復旧しても 13 のもの、merge の前の 1 (2.4 手順 4 の表)

駐車するときは、まず**未コミットの作業をブランチへ WIP コミットとして退避し、`git push -u origin "issue-$N"` を試みる** (push 失敗は続行してよいが、その場合ブランチはマシンローカルに残る旨を駐車コメントに書く)。コミット条件 (全テスト green) は merge されるコミットの規律であり、この退避コミットは merge しない駐車ブランチ上の記録なので例外とする — 退避しないと作業ツリーが dirty のまま残り、次の issue の 2.1 (clean チェック) と run 停止時の Step 3 (デフォルトブランチへの switch) が成立しない。**並列実行と、Step 1 で引き継いだ worktree では、この退避を worktree の中で行い、push まで済ませてから 2.0 の手順で worktree を削除する** (残すと親の作業ツリーが dirty のままになる)。退避後:

```bash
gh issue edit "$N" --repo "$REPO_SLUG" --remove-label in-progress --add-label needs-human
gh issue comment "$N" --repo "$REPO_SLUG" --body "<状況: 何を試し、何が起き、何が残っているか (implementer の summary の試行記録を含める)。PR がまだ無く「issue にする指摘」(2.3) があれば、その summary と fix_hint も列挙。人間に決めてほしいこと。ブランチ issue-$N (と PR があれば PR) は未 merge のまま残置><!-- dev-impl -->"
```

駐車のコメントには、`~/.claude/skills/dev-triage/references/issue-states.md`「needs-human のコメントに載せる会話の入口」に従って会話の入口を足す (`<!-- dev-impl -->` の前)。

ブランチと open PR は merge せず残す (人間が差分を確認でき、再開時に再利用できる)。**その issue に依存しない次の issue へ進む。** 次の issue は `sh ~/.claude/skills/dev-impl/scripts/next-issues.sh mark "$SCRATCH/issues.tsv" "$N" parked` が出す着手順で決める (Step 1)。

**run 全体を停止するのは次の 2 つだけ**: (1) 残りの全 issue が未解消 issue に依存してブロックされた (2) `contract_break` の内容が後続 issue の前提を崩し、進めるとやり直しになる。

停止時も、未解消 issue の一覧と理由に加えて、Step 3 の手順 2 (作り残しを拾い、作った issue を並べる) を行う。

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
    gh issue close "$P" --repo "$REPO_SLUG" --comment "この親 issue の sub-issue がすべて完了したため close する (dev-impl)" &&
      echo "#$P close した" || echo "#$P close できない"
  else
    echo "#$P 子が残っている ($COMPLETED/$TOTAL)"
  fi
done
```

`TOTAL -eq 0` の分岐を外さない — 子が 1 件も紐付いていない親 (dev-spec の紐付けが途中で落ちた場合) まで close してしまうため。「close した」「close できない」「子ゼロ」「子が残っている」「判定不能」の出力を、そのまま最終報告の区分に使う。

**この走査は `tracking` ラベルの open issue を repo 全件対象にするが、close するのは dev-spec が作った形のタイトルの親だけにする**: `UC-<番号>: ` で始まる、`基盤: UC に属さない共通実装`、` トラッキング` で終わる、のどれか。それ以外の `tracking` (dev-triage や人が付けたもの) は close せず、最終報告に一覧で出して人間の判断を仰ぐ。

2. レビューの指摘から作った issue をまとめる:
   - デフォルトブランチへ戻って `git pull` する (`git fetch origin` のあと `git switch "$DEFAULT" && git pull`。$REPO_DIR が worktree で既定ブランチを別の checkout が使っていて switch できなければ `git switch --detach "origin/$DEFAULT"`)
   - **作り残しを拾う**: `gh pr list --repo "$REPO_SLUG" --state merged --limit 50 --json number,headRefName,comments --jq '.[] | select(.headRefName | startswith("issue-")) | select(any(.comments[]; .body | contains("<!-- dev-impl-findings: pending -->"))) | .number'` に出た PR について、2.5 の手順で issue を作る (merge の後に止まった run・終了コード 15 と `MERGE_UNKNOWN` で 2.5 を通らなかった PR を拾うため)
   - この run で作った issue を、severity (high → followup → medium) ごとに番号とタイトルで最終報告の先頭に出す。0 件なら出さない
   - 直した指摘と issue にした指摘を「早見表にあった種類か」で分ける。早見表 (`dev-impl-implementer.md`「実装後のセルフチェック」) に無かった種類は、次回の早見表に足す候補として最終報告に列挙する (表に足すかは人間が決める)
   - `docs/pending-review/` が残っているリポジトリでは、ファイル数とパスだけを最終報告に 1 行で出す。中身は読まず、ファイルも足さない
3. 最終報告 (会話で 1 回だけ。run レポート文書は作らない):
   - 実装した issue と PR の一覧
   - 着手できなかった issue を理由ごとに: 塞いでいる open の依存先 (番号とラベル。ラベルは `gh issue view <番号> --json labels` で引く)、依存の循環 (`cycle`)、どこにも無い依存先 (`unknown`)、読めない依存の行 (`badline`)、対象にならない番号 (`#<番号> は対象にならない`)、別のセッションが担当中 (`claimed`。セッション ID も書く)
   - close した親 (tracking) issue と、open のまま残した親 (子が残っている / 子ゼロ / 判定不能の別に)
   - 2.5 で親 close を判定できなかった子 issue の番号 (親に紐付いていない 404 の子と、API 失敗の子を分けて)
   - 消せなかったブランチ・worktree (`merge-pr.sh` の `BRANCH:` の行) と、merge の後の処理に失敗した issue (終了コード 15 の 2 回目の `ISSUE:`・`LABEL:` の行)
   - close しなかった、dev-spec の形でないタイトルの `tracking` の親 (手順 1)
   - issue にできなかった指摘 (2.5)
   - `needs-human` で駐車した issue と、人間がすべき決定。報告を読む時点のユーザーは issue の中身を覚えていない前提で、issue ごとに `~/.claude/guidelines/core/collaboration.md`「質問・提案の形式」に従って書く。どの件の話かは issue の番号とタイトルで示す
   - 実装中の設計判断・docs 更新の要約

## エスカレーション回答後の再開

人間が `needs-human` の issue に回答したら、**回答の内容を issue 本文 (該当節の書き換え) または参照 docs に反映してから**、`needs-human` を外して `ready` を付け (`gh issue edit <番号> --remove-label needs-human --add-label ready`。`needs-human` が残ると Step 1 の対象にならない)、本スキルを再実行する — implementer は issue 本文と docs しか読まないため、コメントに書かれただけの回答は実装に届かない。docs 側を変えた場合は push も行う (Step 0 の確認に掛かる)。Step 1 の収集が駐車 issue を拾い直し、残置ブランチ・PR があれば続きから実装する。

## 参照ルール

- コミット規約: `~/.claude/guidelines/core/commit.md` / 委譲の判断: `~/.claude/guidelines/core/orchestration.md`
- implementer・review-impl の入出力契約は各 agent 定義 (`~/.claude/agents/dev-impl-implementer.md` / `review-impl.md`) が正本

## 関連スキル・エージェント

- **dev-spec**: 上流の設計ループ。issue の生成元
- **dev-impl-implementer** (subagent): 実装の葉。issue と docs を直読する
- **review-impl** (subagent): 統合レビュワー (テスト品質 / 設計準拠 / コード品質 / E2E / UI レイアウト。r2 では前ラウンド指摘の再発・転移も)
- **workflow-create-pr**: 2.4 手順 3 で非対話モードで起動する。implementer が集めた証跡を PR 本文の「動作確認」節に載せ、スクリーンショットを添付する。証跡の集め方の正本は同スキルの `references/evidence.md`
