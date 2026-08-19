---
name: dev-impl
description: 実装ループ。/dev-spec が作成した GitHub issue を入力に、依存順に 1 件ずつレビュー・コミット込みで自律実装するオーケストレーター。実装の指示は issue 本文 (ゴール / DoD / 参照 docs / 変更想定ファイル / 非スコープ) から取り、完了したら close する。人間の介入はエスカレ条件 (概要設計の破綻 P3 等) のみ。dev-spec の承認ゲート通過後にユーザーが直接起動する。エスカレーション回答後の再開も本スキルの再実行で行う。「実装ループを開始」「issue を順に実装して」「残りタスクを自動で実装」などで起動。
argument-hint: "[docs ディレクトリパス、省略時は docs/]"
model: opus
allowed-tools: Read, Edit, Write, Glob, Bash, Skill, Agent, AskUserQuestion
---

# dev-impl — 実装ループ

承認済みの設計 + TODO を入力に、TODO.md の全フェーズを最後まで自律的に実装するオーケストレーター。`dev-spec` の下流ステージ (= 設計と TODO が固まった後) を機械的に消化する役割。

人間の介入は **エスカレ条件** (検査 → 修正の周回が 3 回でも fatal 残存 / P3 検出など) でのみ発生する。それ以外は止まらず最後まで走る。

## モデル方針

- 本スキルは frontmatter で `model: opus` を指定している。モデル切り替えが効くのは**ユーザーが `/dev-impl` を直接起動したターンだけ** (Skill ツール経由の起動では適用されない)。エスカレーションに回答した後の再開も `/dev-impl` の再実行で行う (TODO.md の `- [x]` 状態から途中再開できるため、再実行で override が再適用される)
- **Agent ツールの呼び出しには例外なく `model` を明示する。** 未指定だと agent 定義の frontmatter ではなく**親のセッションモデルを継承**するため、最上位 tier のセッションでは haiku 指定の agent まで最上位単価で走る。

| subagent | model | 根拠 |
| --- | --- | --- |
| dev-impl-implementer (4.2a `mode: implement`) | `opus` | フェーズ 1 本を TDD で完結させる実装器 |
| dev-impl-implementer (4.2d `mode: fix`) | `opus` | fatal findings の修正。実装と同じ判断力を要する |
| architecture-guard (4.2c) | `haiku` | レイヤ境界違反の検出は機械的・宣言的な判定でモデル性能に依存しない |
| fix-lsp-warnings (4.2b) | `haiku` | LSP が出した警告を規則どおりに潰す機械作業 |
| tech-investigation (Step 1.5 の個別呼び出し) | `opus` | 検証範囲の設計を自分で行う探索的な調査 |
| review-adversarial (4.2c) | `sonnet` | 下記のとおり実測で opus の優位が確認できず、同額でより多くのターンを回せる sonnet が有利 |
| review-tdd / review-quality / review-product-readiness (4.2c) | `opus` | 設計意図とテストの対応づけなど、規約の機械照合に還元されない判断を含む |
| review-spec-compliance (5.2) | `opus` | 承認ハッシュ照合と成果物 ↔ 詳細設計の突合を伴う受入監査 |

- **review-adversarial が `sonnet` である理由**: 同一セッション・同一フェーズ群での直接比較 (2026-08 のセッションログ実測) で、opus は 20 spawn・2.55 ドル/spawn で high 3 件 (0.15 件/spawn)、sonnet は 21 spawn・2.51 ドル/spawn で high 19 件 (0.90 件/spawn) だった。**1 spawn あたりの金額はほぼ同一で、単価が 1/5 の sonnet は同じ予算で 3.8 倍のターンを回せるため、実際に壊して確かめる本 agent の作業様式と噛み合う**。sonnet の findings は空虚ではなく、TOCTOU 並行削除を実際に再現し修正前ロジックで 20/20 再現するところまで確認する等、実行証拠を伴っていた。この 1 点で CLAUDE.md の原則「実行器のモデル ≤ 検証器のモデル」を満たさなくなるが、当該原則は「検証が実行より弱いと骨抜きになる」ことを避けるための代理指標であり、**検出力の実測が代理指標に優先する**。切り替え後は high 検出件数の推移を監視し、opus 時の 0.15 件/spawn を下回り続けるようなら opus に戻す。

### フェーズ実装を subagent に委譲する理由 (CLAUDE.md の原則に対する dev-impl 限定の例外)

CLAUDE.md「委譲の判断」は**逐次実装の subagent 委譲を禁止**している (固定費と報告往復で総トークン・時間とも増えるため)。dev-impl はこの原則の**唯一の例外**で、issue 1 件ずつの逐次実装であっても implementer subagent に出す。CLAUDE.md 本体は変更しないので、他のタスクでは従来どおりメインループ直営で実装する。

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

起動時に `run_id = $(date '+%Y%m%d-%H%M%S')` と `START_SHA=$(git rev-parse HEAD)` (run 全体の開始 SHA。フェーズごとに再代入される `PHASE_START_SHA` とは別スコープ) を発行し、**リアルタイム監視用の 1 行テキストログ** (`~/.claude/logs/dev-impl.log`) と**事後振り返り用の構造化 JSONL** (`~/.claude/logs/dev-impl/${run_id}/decisions.jsonl`) を並走させる。各ステップの「開始 / 完了 / 動的修正 / エスカレ」発生時に両方へ同期して書き込む (1 行ログ = summary のみ、JSONL = summary + context を構造化)。終了時に JSONL から HTML レポート (Step 7) を生成する。`START_SHA` は Step 5.2 の監査 agent 呼び出しと Step 6 / エスカレ通知のテンプレート (references/goal-audit.md, references/notification-template.md) から参照される。

書式・JSONL スキーマ・書き込みコマンド・実行ログの範例は [references/logging.md](./references/logging.md) を Read して従う。

## 実行手順

### Step 0: 再入チェック (エスカレ後の再開対応)

`~/.claude/logs/dev-impl/` の最新 run の decisions.jsonl を確認し、**同一プロジェクトで未完了の run** があれば再入モードで動く。判定は 2 条件の AND:

- `event_type: start` の `context.repo_root` が現在の `git rev-parse --show-toplevel` と一致する (このディレクトリは全プロジェクト共通なので、パスで絞らないと他プロジェクトの run を拾う)
- 完了イベント (Step 6 の完了サマリ出力時に記録する `done`) が無い (最後が `p3_escalate` 等)

1. **run_id とカウンタを引き継ぐ** (新規発行しない)。decisions.jsonl から `p2_fixes_total` / `goal_loop` / `run_spawns` の現在値を復元する — 再実行のたびにカウンタが 0 に戻ると発散上限 (Step 3) が実質無効化されるため。
2. **working tree の突合**: `git status --porcelain` が非クリーンなら前回停止時の残骸。**逐次モードでも implementer が main の working tree で直接編集するため、停止時の未コミット実装はここに残る**。内容を確認し、AskUserQuestion で「続きとして取り込む / `git restore` で捨ててフェーズをやり直す」を確認する (再入時 1 回だけの人間確認)
   - 何が実装されたかは `~/.claude/logs/dev-impl/<前回の run_id>/reviews/phase-<識別子>/impl-report.json` に残っているので、判断材料としてこれを `jq` で読む (`summary` / `files_changed` / `test_result`)
   - 捨てる場合は 3 段階で行う。**`git reset` + `git restore` だけでは実装ファイルが残る** — 新規実装フェーズの成果物は全て未追跡で、intent-to-add (`git add -N`、Step 4.2c) 済みのファイルも `git reset` 後は未追跡に戻るだけでディスクに残り、`git restore` は未追跡ファイルを削除しないため (実測確認済み):

     ```bash
     git reset                                  # intent-to-add を解除
     git restore .                              # 追跡済みファイルの変更を戻す
     git clean -fd <implementer 報告の files_changed のパス>   # 未追跡の実装を削除
     ```

     `git clean -fd` は**必ずパスを指定する** (無条件だと `docs/.dev-impl/` や他の作業ファイルまで消える)。対象パスは前回 run の `impl-report.json` の `files_changed` から取る。
4. **TODO チェックの突合**: 最終フェーズコミット (decisions.jsonl の直近フェーズ done イベントの SHA) 以降に `- [x]` 化されたタスクがあれば、そのフェーズは「チェック済みだが未コミット」= 未完了として pending に戻す (`- [x]` は実行器の自己申告なので、コミットと突き合わせて初めて完了扱いにする)

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
REPO_ROOT=$(git rev-parse --show-toplevel)
REPO_SLUG=$(gh repo view --json nameWithOwner -q .nameWithOwner)
OPEN=$(gh issue list --repo "$REPO_SLUG" --state open --limit 200 --json number --jq 'length')
```

`OPEN` が 0 で、かつ closed issue も 0 件なら **issue が未生成**である (`/dev-spec` のフェーズ 12 が走っていない)。`OPEN` が 0 で closed が 1 件以上なら**全 issue 完了済み**なので、Step 5 (ゴール達成判定) から再開する。

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
| ゴール定義              | `rg -n '^- G[0-9]+:\|^G[0-9]+:' docs/DESIGN.md` が 1 件以上                                             | `goals_missing`: 「dev-spec フェーズ 9 でゴールを定義してから再実行」                                                                                                                             |
| ゴール ↔ 検証手順の 1:1 | 抽出した各 `G<n>` に対応する `G<n> 検証` 行が DESIGN_DETAIL_APP.md または DESIGN_DETAIL_INFRA.md にある | `verification_missing`: 欠落ゴール ID を列挙して dev-spec フェーズ 9 へ差し戻し                                                                                                                   |
| G_E2E (必須・モード非依存) | `PRODUCT_MODE` が `cli`/`webapp` なら常に必須。`unknown` は Web プロダクト判定 (phase-context.md の dev_server 判定と同じ基準) が真なら必須 | `verification_missing` (同上)                                                                                                                                                                     |

承認ハッシュの再計算コマンド (dev-spec 11.3 の生成と同一定義。P2 ガードでも使う):

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

**実装の単位は GitHub issue** であり、TODO.md は参照しない (issue はフェーズ 12 が TODO.md から転記したもので、実装中の状態の原本は GitHub の側にある)。

```bash
gh issue list --repo "$REPO_SLUG" --state open  --limit 200 --json number,title,labels,body > /tmp/dev-impl-open.json
gh issue list --repo "$REPO_SLUG" --state closed --limit 200 --json number --jq '[.[].number]' > /tmp/dev-impl-closed.json
```

着手対象の決め方:

| 条件 | 扱い |
| --- | --- |
| `needs-human` ラベルが付いている | **着手しない。** 駐車中の issue であり、ラベルを外すのは人間の回答を得た後 |
| `ready` ラベル | 着手可能な候補 |
| `in-progress` ラベル | 前回の run が中断したもの。**そのまま再開する** (Step 0 の再入チェックで復元した状態を使う) |
| ラベルが無い open issue | フェーズ 12 が作成直後に落ちた未完成の issue。`issue_incomplete` でエスカレ停止し、`/dev-spec` の再実行 (12.3 の突き合わせが冪等に貼り直す) を案内する |

候補のうち、本文の `## 依存` にある **`Depends on #N` の参照先がすべて closed になっているものだけが着手可能**。複数あれば issue 番号の昇順で 1 件選ぶ。

**並列化はしない。** 1 件実装して close し、次の判定に戻る、を繰り返す。フェーズを同時に走らせる wave / worktree fan-out は持たない。

着手可能な issue が 1 件も無いのに open issue が残っている場合は、依存が循環しているか、依存先が `needs-human` で駐車している。どちらかを判別して `dependency_blocked` でエスカレ停止する (JSONL の `context` に残りの issue 番号と各々の未解決依存を残す)。

### Step 3: ループ全体の状態管理

以下の counter を保持して各フェーズで参照する (dev-impl 開始時に 0 で初期化):

| カウンタ                                        | 上限                                                      | 超過時の挙動                                    |
| ----------------------------------------------- | --------------------------------------------------------- | ----------------------------------------------- |
| `p1_fixes_in_phase` (現フェーズ内 P1 修正回数)  | 2 (回)                                                    | P2 として扱う (次のループでは P2 として処理)    |
| `p2_fixes_total` (dev-impl 全体の P2 修正回数)  | 3 (回)                                                    | P3 扱いに昇格してエスカレ停止                   |
| `goal_loop` (ゴール達成判定 → 未達対応の周回数) | 2 (周)                                                    | P3 として停止                                   |
| `run_elapsed_minutes` (run 開始からの経過時間)  | 480 (分 = 8 時間。プロジェクト規模に応じて起動時に調整可) | `time_budget_exceeded` でエスカレ停止 (P3 扱い) |
| `phase_fix_round` (現フェーズの検査 → 修正の周回数) | 3 (回)                                                | `phase_fix_exceeded` でエスカレ停止 (context に guard 由来 / review 由来の内訳を残す) |
| `test_gate_retry` (現フェーズの 4.2e テストゲート再試行回数) | 3 (回)                                       | `tests_failing_before_commit` でエスカレ停止    |
| `phase_spawns` (現フェーズの累計 subagent 起動数) | 24 (回)                                                | `spawn_budget_exceeded` でエスカレ停止          |
| `run_spawns` (run 全体の累計 subagent 起動数)   | pending フェーズ数 × 8 (回)                               | 同上                                            |

スコープ別のリセット時点:

| スコープ | カウンタ | リセット時点 |
| --- | --- | --- |
| issue | `p1_fixes_in_phase` / `phase_fix_round` / `test_gate_retry` / `phase_spawns` | **その issue の Step 4.1 (最初の subagent を起動する前)** |
| run 全体 | `p2_fixes_total` / `goal_loop` / `run_spawns` / `run_elapsed_minutes` | リセットしない。**再入時は Step 0 で decisions.jsonl から復元した値を初期値にする** |

`run_elapsed_minutes` は各フェーズ開始時 (Step 4.1) に計算する (macOS/Linux 両対応)。算出コマンドは [references/phase-execution.md](./references/phase-execution.md) の `## 4.1: run_elapsed_minutes 計算` 節を Read してから実行する (この節を読まず近似コマンドで代替すると、date コマンドの macOS/Linux 分岐が崩れ time budget (`time_budget_exceeded`) が機能しなくなるリスクがある)。

カウンタと findings / deviation_signals の集約は**メインセッションが管理する**。各カウンタの現在値と集約結果は都度 1 行テキストログ + JSONL に書き出して外部化する (コンテキストが長くなり compaction をまたいでも、ログから状態を復元できるように)。

**spawn 予算の意図**:

- 1 フェーズは最小構成でも implementer 1 + architecture-guard 1 + review 1〜4 の subagent を起動する。フェーズ数だけ積み上がるため、上限を機械ゲートとして置く
- 根拠: subagent を最も使ったセッションは 129 spawn でフェーズ単価が最悪 (116.4 ドル / フェーズ、subagent が全体の 66.8%) だった (2026-07 の実測)
- `phase_spawns` の上限 24 の内訳 (最悪ケース): implementer 1 + 検査 5 (guard 1 + review 最大 4) + (fix 1 + 検査 5) × 3 ラウンド = 24
- 中央値の想定は 4 (implementer 1 + guard 1 + review 2)。`run_spawns` の上限係数 8 はこの中央値に修正ラウンド 1 回分を見込んだ値で、**issue が追加される (P1/P2 動的修正・Step 5.5) たびに「その時点の open issue 数 × 8」で再計算する**
- 全 spawn を JSONL に `event_type: spawn` (context に `agent` / `model` / `phase`) で記録し、事後にフェーズ単価と突合できるようにする

### main のコンテキスト規律

**フェーズ実装を implementer に出しても、main がその成果物を読み返せば削減は消える。** 以下を守る:

| 規律 | 内容 |
| --- | --- |
| ソースを Read しない | フェーズの実装内容は implementer の報告要約と review findings 経由でのみ知る |
| `git diff` はパッチ本文を出さない | `--stat` / `--name-only` のみ。フルパッチを main のコンテキストに載せない |
| 検査結果 JSON は射影して読む | 全文 Read せず `jq -c '{ok, skip_reason, dimension, findings: [(.findings // .violations)[]? \| {severity, rule, file, line}]}'` で読む (architecture-guard は `violations` / `skip_reason`、review-* は `findings` / `dimension` を返すので両対応にする)。**fatal 判定に必要なのはこれだけ**で、`message` / `fix_proposal` は修正する implementer (`mode: fix`) が JSON を自分で Read するため main に載せる必要がない (実測: 全文 5,573 バイト = 約 1,400 トークン → 射影 約 60 トークン) |
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

**main が行うこと** (implementer には渡さない): PHASE_CONTEXT と RUN_FACTS の組み立て、事前判定と観点 gating の確定、検査 fan-out の起動と待機、fatal 判定、全テストゲート、テスト弱体化の機械検知、コミット、issue のラベル操作と close、decisions.jsonl への書き込み、Step 4.6 の P1/P2/P3 判定。

**完了判定は main が自分で行う。** implementer の `status: done` を完了根拠にせず、次の 2 つを main が確認する:

- (a) **実装が実在すること** — implementer 報告の `files_changed` に挙がったパスが、実際に `git diff --name-only <PHASE_START_SHA>` + `git ls-files --others --exclude-standard` の結果に現れること。working tree が非空であることだけでは足りない (`.gitignore` 追記や作業ファイルで非空になりうるため)
- (b) **fatal が 0 件であること** — 判定基準は 4.2d の fatal の定義に従う (review-* の high と architecture-guard の high/medium)

何も実装せず `status: done` を返した場合に「差分ゼロ → 全テスト green → `- [x]` 化」まで素通りするのを防ぐための判定。

各 pending フェーズについて以下を順次実行する:

#### Step 4.1: フェーズ開始の SHA を記録

`PHASE_START_SHA=$(git rev-parse HEAD)` を記録する。architecture-guard / review-* が「このフェーズの差分」を判定する基準点。

あわせてフェーズの作業ファイル置き場を作る (implementer の報告 JSON・検査結果 JSON・攻撃スクリプト等の置き場。**リポジトリの外に置く**ことでコミット対象への混入を防ぎ、エスカレ停止後の再入時にも残す):

```bash
SCRATCH_DIR=~/.claude/logs/dev-impl/${run_id}/reviews/phase-<識別子>
mkdir -p "$SCRATCH_DIR"
```


#### Step 4.1.5: PHASE_CONTEXT の組み立て

implementer と検査 subagent (architecture-guard / review-*) は parent のコンテキストを継承しないため、dev-impl が「フェーズ 1 本を実装・検査するのに必要な情報パッケージ」を組み立てて **`docs/.dev-impl/<run_id>/phase-<識別子>-context.md` に Write** する (`<識別子>` はフェーズ見出しの `フェーズ` 直後からコロンまでの文字列。`1` だけでなく `4-a` のような接尾辞付きもある)。subagent には prompt にこのファイルの絶対パスだけを渡し、各 agent が必要な節を自分で Read する (1 フェーズあたり implementer 1 + 検査 subagent 最大 5 への同一内容の重複埋め込みを避けるため)。**このファイルが implementer にとってフェーズの唯一の入力になる**ので、抜粋の不足はそのまま実装の質に出る。

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

- 起動時に `phase_spawns += 1` / `run_spawns += 1` し、JSONL に `event_type: spawn` を記録する
- 報告受領時に JSONL へ `event_type: impl_report` (context に要約 JSON + `report_path`) を記録する。**報告要約は main のコンテキストに載るが、全文 JSON は載せない** (P1/P2/P3 判定と JSONL 転記に必要なフィールドは `jq` で `report_path` から直接引く)
- `status: failed` の場合は `reason` に応じて分岐する:

| `reason` | 対処 |
| --- | --- |
| `design_overview_break` | **即エスカレ停止** (P3、commit しない) |
| `test_weakening_suspected` | 4.2e と同じトレース確認を main が行い、トレース不能なら `test_weakening_detected` でエスカレ停止 |
| `tests_failing` / `spec_insufficient` | 下記「fix ブリーフ」を書いて `mode: fix` で再起動する (4.2d の修正ラウンドと同じ扱い。`phase_fix_round` を共有する) |

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

**報告が読めない場合**: `report_path` が不在・`jq` でパース不能・必須フィールド (`status` / `summary` / `files_changed` / `test_result`) の欠落はいずれも `impl_failed` として扱い、`phase_fix_round += 1` して `mode: implement` で再起動する (fix ではない — 何が実装されたか分からないため)。3 回で `phase_fix_exceeded` でエスカレ停止する。検査 agent の `guard_agent_failed` / `review_agent_failed` と同じく、**パス扱いにしない**。

- implementer が応答しないまま `run_elapsed_minutes` が 30 分進んだら打ち切る (`impl_failed`)。その issue を `needs-human` で駐車して次の issue に移る

##### 実装ノートの受け取り (design_decision / open_question)

implementer 報告の `design_decisions` (設計が沈黙・あいまいな箇所での自律判断) と `open_questions` (確信が持てずユーザの事後確認が必要な選択) を、main が JSONL に `event_type: design_decision` / `open_question` として**`report_path` から `jq` で転記する** (スキーマは [references/logging.md](./references/logging.md) を参照)。ループは止めない。

これらは `deviation_signals` (設計と*矛盾する*変更) とは別物で、混ぜない。同一の判断・質問を後続フェーズが踏襲するだけの場合、implementer は再記録しない規約になっている (RUN_FACTS の「累積 design_decisions」を読むため)。

##### 4.2b: LSP 警告修正 (Lua/Neovim のみ)

`IS_NEOVIM_PLUGIN=true` なら `fix-lsp-warnings` agent を `model: "haiku"` 明示で起動する (対象はフェーズ差分ファイルのみ)。失敗は警告ログのみで継続。修正が入った場合は main が `phase_test_command` を再実行して緑を確認する。

**このステップだけは検査 fan-out に混ぜない。** fix-lsp-warnings は修正する agent なので、レビューと同時に走らせるとレビュー対象のファイルが検査中に書き換わる。

##### 4.2c: 検査 fan-out (main が起動して待つ)

**fan-out の直前に、未追跡ファイルを intent-to-add する**:

```bash
git ls-files -z --others --exclude-standard | xargs -0 -r git add -N
```

dev-impl は 4.2e までコミットしないため、新規実装だけのフェーズは全ファイルが untracked になり `git diff <PHASE_START_SHA>` では見えない。`architecture-guard` は `git ls-files --others` を併用するが検査 agent ごとに扱いが揃っていないので、ここで揃えて全 agent の `git diff <PHASE_START_SHA>` が同じ差分を返すようにする。

gating された観点と `architecture-guard` を**同一メッセージ内の複数 Agent tool_use として並列起動**し、main が全部の完了を待つ。呼び出し方法は [references/phase-execution.md](./references/phase-execution.md) の `## 4.2c: 検査 fan-out の起動` 節を Read してから実行する。

guard を review と同じ fan-out に入れるのは、待ちを 2 回から 1 回に減らすため。guard の違反も review の fatal も同じ修正ラウンド (4.2d) で処理する。

検査 agent も implementer と同じく **30 分応答が無ければ打ち切る**。打ち切った観点は「未検証」として 4.2d 手順 1 の `guard_agent_failed` / `review_agent_failed` で扱う。

**観点 gating (トークン削減の要):**

| タイミング        | 実行観点                                                                                            |
| ----------------- | --------------------------------------------------------------------------------------------------- |
| 毎フェーズ        | architecture-guard (gating 対象外、常に実行) + review-adversarial (下記スキップ述語で skip 可)       |
| テスト差分があるフェーズ (`$TEST_FILE_CHANGED` または `$TEST_CONTENT_CHANGED` が非空) | 上記 + review-tdd                              |
| UI を触るフェーズ (`uiPhase == true`) | 上記 + review-product-readiness (dev_server が無ければ skip)                     |
| 最終フェーズ      | 全観点フル (tdd / quality / product-readiness / adversarial)                                        |

**review-tdd をテスト差分の有無で gating する理由**: review-tdd が判定するのは「書かれたテストの質」なので、テストに差分が無いフェーズには判定対象が存在しない。テストを伴わない実装だけが積まれた場合は、行数 20 超で review-adversarial のスキップ述語が発火せず (下表 #2)、レンズ C (完了主張の反証) がテスト不在を検出するため取りこぼさない。

**`PRODUCT_MODE=cli` では review-product-readiness を一切起動しない** (`uiPhase` が常に `false` のため UI を触るフェーズの行は発火せず、最終フェーズの「全観点フル」からも product-readiness を除外する。cli の G_E2E は Step 5.2 で review-spec-compliance が担当する)。

review-quality (rules 準拠 + アーキテクチャ heuristic 統合) は最終フェーズのみ (機械判定可能な境界違反は毎フェーズ同じ fan-out の architecture-guard が担保するため)。**ただし `$CONSUMABLE_CHANGED` が非空のフェーズ (消費すると無効化される資源 — ローテーション有効な refresh token・nonce・ワンタイムコード・べき等キー・使い捨て署名 URL — を扱う差分) では最終フェーズでなくても起動する**。この種のコードは多重消費・恒久エラー分岐の漏れが復帰不能障害に直結し、architecture-guard の境界検査では検知できないため、最終フェーズまで持ち越さない。

**review-adversarial のスキップ述語 (機械判定、actor の裁量では skip しない):**

算出コマンド (`$CHANGED` / `$LINES` / `$TEST_FILE_CHANGED` / `$TEST_CONTENT_CHANGED` / `$NON_DOC_CHANGED` / `$CI_FILES_CHANGED` / `$CONSUMABLE_CHANGED`) は [references/phase-execution.md](./references/phase-execution.md) の `## 4.2c: 観点 gating 述語の算出コマンド` 節を Read してから実行する (この節を読まず近似コマンドで代替すると、untracked ファイルや言語別インラインテストの検知漏れにより review-adversarial を不当に skip するリスクがある)。判定条件は以下の表に従う。

| # | 条件                                                                                                                                              | 意図                                                                                                                                                 |
| - | ------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1 | `$TEST_FILE_CHANGED` と `$TEST_CONTENT_CHANGED` がともに空                                                                                        | テスト変更時はレンズ B 必須。ファイル名 + 差分内容の 2 層、tracked/untracked 両方で判定 (言語別の具体パターンは phase-execution.md の実コマンドが正) |
| 2 | `$LINES` ≤ 20 (`$NON_DOC_CHANGED` が空、つまり `.md` / `docs/` のみの差分なら行数不問で skip 可)                                                  | typo・軽微修正の機械近似                                                                                                                             |
| 3 | `$CI_FILES_CHANGED` が空 (CI・ビルド/テスト設定 `.github/`, `*config*`, `package.json`, `Cargo.toml`, `go.mod`, `Makefile`, `justfile`, `deno.json` 等の変更なし) | 検証器設定の改変は必ず監査                                                                                                                           |
| 4 | 最終フェーズでない                                                                                                                                | 最終フェーズは全観点フル                                                                                                                             |

全条件が真の場合のみ skip 可 (skip は権利であって義務ではない。1 つでも「実行」と出れば actor はスキップできない)。skip 時は JSONL に `event_type: verification_skipped`、`context: {target: "review-adversarial", changed_files: $CHANGED, changed_lines: $LINES, criteria_result: {...}}` を記録する (Step 5.6 の未検証項目集約に自動合流させ、沈黙スキップを構造的に不可能にするため)。

述語は各修正ラウンドの fan-out 直前に評価するが、遷移は **skip → 実行 の一方向のみ許可する** (一度「実行」と判定されたら以降のラウンドでは再評価せず必ず実行し続ける。「実行 → skip」への降格は禁止)。初回評価で skip だった場合のみ、次のラウンドで再評価する。これにより、初回 skip 後の修正でテストが追加・弱体化されるケースを取りこぼさない。

各 Agent 呼び出しには **「モデル方針」の表どおり `model` を明示**する。呼び出し時の model 指定は agent 定義側のデフォルトより優先され、**未指定にすると親のセッションモデルを継承してしまう** (`agent-spawn-guard` hook が未指定を deny する)。**review-adversarial には PHASE_CONTEXT の path を渡さない** — fresh context 監査のため、phase_name / phase_start_sha / repo_dir / docs_dir / dev_server / scratch_dir / output_path のみを渡す。

##### 4.2d: fatal 判定と修正ラウンド (最大 3)

main は各 agent の結果 JSON を「main のコンテキスト規律」の `jq` 射影で読む。

1. いずれかの agent が結果を返せない → その観点は「未検証」。**パス扱いにせず** `guard_agent_failed` (architecture-guard) / `review_agent_failed` (review-*) でエスカレ停止する。high 0 件と同一視しない。該当するのは次のいずれか:
   - agent がエラー終了した、または 30 分応答しない (implementer と同じ打ち切り基準)
   - `output_path` の JSON が実在しない、`jq` でパースできない
   - **スキーマ不適合**: architecture-guard は `ok` が読めない、review-* は `findings` が配列として読めない
   - architecture-guard が `skip_reason: "diff_command_failed"` を返した (差分が取れておらず検査が成立していない。**修正ラウンドに乗せない** — 実装を直しても解消しない性質のため)
2. **fatal の定義**: review-* の severity: high、または architecture-guard の `violations` のうち severity が high / medium のもの。fatal 0 件 → 4.2e へ
3. fatal あり → `phase_fix_round += 1` する。**この時点で `phase_fix_round > 3` なら fix を起動せず `phase_fix_exceeded` でエスカレ停止**する (JSONL の context に guard 由来 / review 由来の内訳を残す)
4. **`mode: fix` の `dev-impl-implementer` を `model: "opus"` 明示で起動**する。渡すのは `findings_paths` (fatal を含む結果 JSON の絶対パスの配列) / `phase_context_path` / `repo_dir` / `report_path`。main は findings の本文を読まないし、修正内容を指示しない (fixer が JSON を自分で Read する)。**fixer が直す対象は「review-* の high」と「architecture-guard の high/medium」**で、fatal の定義と一致させてある (guard の medium が誰にも直されず空回りするのを防ぐため)
5. 修正完了後、**gating された全観点 + architecture-guard を再 fan-out する** (修正は別観点を壊しうるため、fatal だった観点だけに絞らない)。4.2c に戻る
6. 修正中に `design_overview_break` を検知 → 即エスカレ停止 (commit しない)
7. review-adversarial の `test_weakened` / `vacuous_assertion` / `skip_added` (confidence: high) は**修正ラウンドに乗せない**。弱体化を実装者自身に直させると骨抜きの温床になるため、4.2e と同じトレース確認 (TODO.md / DESIGN_DETAIL_APP.md に意図的な変更としてトレースできるか) を main が行い、トレース不能なら `test_weakening_detected` でエスカレ停止する。`dev-impl-implementer` 側もこれらの finding を渡されたら修正せず `test_weakening_suspected` で停止する規約になっている (二重の歯止め)
8. review-adversarial の `working_tree_polluted` を検知したら、main が `git status --porcelain` で実際の汚染有無を確認し、汚染があれば restore する

severity: low/medium の findings は修正せず JSONL に `event_type: review_low` で記録する (射影で読んだ `{severity, rule, file, line}` と結果 JSON のパスだけを記録し、本文は転記しない)。

##### 4.2e: テストゲート + コミット (main)

コミット前に **main が `full_test_command` を Bash で直接実行し、exit code 0 を確認する** (自己申告ではなく実行結果で判定)。implementer にはフェーズスコープのテストしか実行させていないので、全体スイートの実行はここが初回になる。

全体スイートを main が実行する理由は、main の cache write が 1 時間 TTL で長時間の実行に耐えるため (subagent は 5 分 TTL なので、長いスイートを subagent 内で回すと自分のコンテキストを失効させる)。ただし **Bash の 600 秒上限は主体によらず効く** (実測: `swift test` が 608〜614 秒で上限に張り付いた事例が失効 29 件の主因)。`full_test_command` が 600 秒を超えるプロジェクトでは `run_in_background: true` で起動してポーリングする。**タイムアウトした実行は「未検証」として `verification_skipped` に記録し、成功扱いにしない**。

- 失敗 → `test_gate_retry += 1` し、失敗出力 (末尾 30 行) を 4.2a の「fix ブリーフ」と同じスキーマで `<SCRATCH_DIR>/test-failure-<test_gate_retry>.json` に書いて `mode: fix` の implementer に `findings_paths` として渡す (main は実装差分を読まない)。`test_gate_retry > 3` で `tests_failing_before_commit` でエスカレ停止。**`test_gate_retry` は `phase_fix_round` とは別カウンタ**にする (検査ラウンドを使い切ったフェーズでもテストゲートの再試行が残るように)

続けて**テスト弱体化の機械検知**を行う (reward hacking 対策。review-tdd の LLM 判定に頼らず、編集権限の外で機械判定する)。検知コマンド (テストファイル削除の検出 + skip/only/ignore 追加の検出) は [references/phase-execution.md](./references/phase-execution.md) の `## 4.2e: テスト弱体化検知コマンド` 節を Read してから実行する (この節を読まず近似コマンドで代替すると、言語別 skip/ignore パターンの見落としにより test_weakening 検知が漏れるリスクがある)。

ヒットした場合、その削除・skip が TODO.md / DESIGN_DETAIL_APP.md にトレースできる意図的な変更 (設計変更で仕様ごと削除等) か確認し、トレースできなければ `test_weakening_detected` でエスカレ停止する (パス扱いしない)。

緑を確認したら、以下を **main が**この順で行う:

1. **TODO.md の該当フェーズを `- [x]` に更新する**。実装と同じコミットに含める (チェックだけ先に入ってコミットが無い状態を作らない。Step 0 手順 4 の再入突合はこの前提で「チェック済みだがコミット無し = 未完了」と判定する)
2. **コミットする**。`rules/core/commit.md` に従う (関心事分割 / STRUCTURAL・BEHAVIORAL 分離)。**コミットは必ず main が行う** — 形式を機械検証する commit-msg-guard hook は親にしか効かないため。ただし hook が実際に検証するのは `$GHQ_ROOT/github.com/skanehira/` 配下のリポジトリで作業しているときだけで、それ以外では fail-open で素通りする。push はしない (ユーザ手動)
3. **RUN_FACTS.md を更新する** (書式と規則は [references/phase-context.md](./references/phase-context.md) の `## RUN_FACTS.md`)。implementer 報告の `report_path` から `jq` で引いて「完了フェーズの成果物」「累積 design_decisions」「既知の落とし穴」に追記する。**この更新がフェーズ間の文脈再注入を代替する**ので省略しない (省略すると次フェーズの implementer がプロジェクトの作り方を探索し直す)。追記後にファイルサイズを測り、**4096 バイトを超えていたら最新 3 フェーズ以外の「完了フェーズの成果物」行を要約に畳む**。JSONL に `event_type: run_facts_updated` (context に `sections` / `bytes`) を記録する
4. **JSONL に `event_type: impl_done` を記録する** (context: `phase` / `summary` / `commit_sha` / `phase_fix_round` / `phase_spawns` / `review_outputs`)。これがフェーズ完了の唯一のイベントで、`prev_phase_summary` (次フェーズの PHASE_CONTEXT) と HTML レポートのフェーズタイムラインがこれを読む
5. implementer 報告の `verification_skipped` / `design_decisions` / `open_questions` / `spec_lookups` を `report_path` から `jq` で JSONL に転記する (`verification_skipped` は Step 5.6 の未検証項目集約に合流する)

##### フェーズ内エスカレ条件まとめ

| 条件                                                                                                             | reason                                       |
| ---------------------------------------------------------------------------------------------------------------- | -------------------------------------------- |
| 修正ラウンド 3 回でも fatal 残存 (guard 違反 / review high のいずれも)                                           | `phase_fix_exceeded`                         |
| 検査 agent が結果を返せない (未検証をパス扱いにしない)                                                           | `guard_agent_failed` / `review_agent_failed` |
| implementer が 30 分応答しない / 実装が実在しない                                                                | `impl_failed`                                |
| `phase_spawns > 16` または `run_spawns > pending フェーズ数 × 8`                                                 | `spawn_budget_exceeded`                      |
| テストゲート 3 回不通過                                                                                          | `tests_failing_before_commit`                |
| `design_overview_break` 検知 (実装・修正中いずれでも、commit 前に停止)                                           | `design_overview_break` (P3)                 |
| テストファイル削除 / skip 追加 / assertion の弱体化・空虚化が設計にトレースできない (4.2e の機械検知 / 4.2c の review-adversarial 検知 / implementer の `test_weakening_suspected` 報告のいずれも) | `test_weakening_detected`                    |

#### Step 4.6: 設計乖離の判定 (P1 / P2 / P3)

implementer 報告 (`mode: implement` / `mode: fix` 双方) の `deviation_signals` を main が `report_path` から `jq` で集め、P 値に分類する。**implementer は自分で JSONL を書けないので、この転記が Step 4.6 の唯一の入力になる** (逐次モードでも main は実装過程を見ていない)。design 整合の判定は review findings の `dimension: "quality"` かつ `rule: "design_mismatch"` 系エントリも使う。

**シグナル元と分類対応**:

| シグナル元                                                                          | type                    | 分類                | 対処                                                           |
| ----------------------------------------------------------------------------------- | ----------------------- | ------------------- | -------------------------------------------------------------- |
| implementer 報告                                                                    | `todo_minor`            | P1 (TODO 軽微)      | 下記「P1 動的修正」へ                                          |
| implementer 報告 / review-quality の design 整合 finding (severity: medium 以上)    | `design_detail_gap`     | P2 (詳細設計の不足) | 下記「P2 動的修正」へ                                          |
| implementer 報告 / review-quality の design 整合 finding (severity: high)           | `design_overview_break` | P3 (概要設計の破綻) | エスカレ停止 (Step 4.2 内で検知した時点で commit 前に停止済み) |

**シグナル無しの場合**: 次の pending フェーズへ進む。

**集約のしかた**: 同一 phase 内で同種シグナルが複数回記録された場合、`scope` + `what` で重複排除してから処理 (1 件のシグナルとして扱う)。

##### P1 動的修正

1. `p1_fixes_in_phase += 1`。`p1_fixes_in_phase > 2` なら本シグナルを P2 (design_detail_gap) として扱い、P2 動的修正フローに切り替える (以降のステップは実行しない)
2. TODO.md の該当フェーズ周辺を Edit
3. ログに「P1 fix: <変更内容の 1 行サマリ>」を残す (JSONL は `event_type: p1_fix`)
4. 残タスクが当該フェーズ内なら継続、フェーズを跨ぐ追加なら新フェーズを挿入して以降のループに含める (挿入する見出しには `<!-- deps: ... -->` と `<!-- goals: ... -->` を必ず付け、メタ情報 5 項目 (ゴール / DoD / 参照 docs / 変更想定ファイル / 非スコープ) も書く。判定基準は `../dev-spec/references/todo-generation.md` の「フェーズ依存の宣言」「対応ゴールの宣言」「各フェーズが持つメタ情報」)

##### P2 動的修正

1. `p2_fixes_total += 1`。`p2_fixes_total > 3` なら本シグナルを P3 (design_overview_break) として扱い、エスカレ停止する (以降のステップは実行しない)
2. DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md の該当側 (境界基準: 変更に IaC・コンソール操作・環境設定変更が要るなら INFRA) のセクションを Edit
3. **受入基準ガード**: Edit 直後に goals_sha を再計算 (Step 1 のコマンド) し、承認スタンプの値と照合する。不一致 = 受入基準 (ゴール / 検証手順行) を触った P2 であり、実装者による自己適用は禁止。Edit を revert せず `acceptance_criteria_change` でエスカレ停止する (「受入基準の変更が必要になった。dev-spec フェーズ 9 → 11 で再承認せよ」と通知。実装ガイド・スキーマ等の追記はハッシュ対象外なので通過する)
4. `../dev-spec/references/todo-generation.md` を Read し、その手順に従ってメインループで TODO.md を再生成する (差分更新モード)
5. Step 2 の issue 抽出を再実行して着手対象を更新する。closed の issue はそのまま完了扱いを維持する
6. ログに「P2 fix: <更新セクション>」を残す (JSONL は `event_type: p2_fix`)
7. 当該フェーズの再実行 (Step 4.2 から) か次フェーズへ進むかを判定: 再生成後の TODO.md で **当該フェーズ内に新規の未完了タスク (`- [ ]`) が追加されていれば Step 4.2 から再実行**、既存タスクが全て完了済みのまま (詳細設計の記述を補っただけで実装側の追加作業が無い) なら次フェーズへ進む
8. ユーザに対する通知は「DESIGN_DETAIL_APP.md (または _INFRA.md) / TODO.md を更新しました (詳細はログ参照)」程度 (dev-impl は止まらない)

##### P3 検出時

エスカレ停止 (後述の「エスカレ停止時の挙動」へ)。

シグナル処理が終わったら次の pending フェーズへ進む (コミットは Step 4.2e で実行済み)。

### Step 5: ゴール達成判定 + 未達対応ループ

Step 4 のフェーズループを抜けた時点で「全 TODO 消化」は完了している。ここから DESIGN.md のゴールが**実際に達成されているか**を機械判定する。

#### Step 5.1: ゴール一覧抽出

DESIGN.md の「ゴール」セクションを Read してゴール一覧を抽出 (例: `G1, G2, ...`)。抽出コマンド例: `rg -n '^- G[0-9]+:|^G[0-9]+:' docs/DESIGN.md`。

ゴール定義は Step 1 の構造ゲートで存在を保証済み。万一この時点で抽出できない場合は `goals_missing` でエスカレ停止する (**skip しない** — ゴール判定を省くと完了条件が「全 TODO 消化」という作業量ベースの自己申告になるため)。

#### Step 5.2: 第三者監査の並列起動

自動系ゴールの検証は**メインループが自分で実行しない** (実装者本人による自己判定を避ける)。`PRODUCT_MODE=cli` の場合は `review-spec-compliance` (mode: post-impl、G_E2E も自動系ゴールとして実行) を単独起動する。`webapp` / `unknown` の場合は `review-spec-compliance` と `review-product-readiness` (G_E2E) を**同一メッセージ内の複数 Agent tool_use として並列起動**する。起動する agent はすべて `model: opus` を明示する。起動コードは [references/goal-audit.md](./references/goal-audit.md) の `## 5.2: 監査 agent の並列起動` 節を Read してから実行する (この節を読まず近似の prompt で起動すると、`docs は自分で全文 Read すること` 等の指示や `output_path` / `holdout_enabled` / `product_mode` の欠落により第三者監査の独立性が落ちる)。

**G_E2E の判定**:
- **webapp / unknown**: review-product-readiness が判定。ナビ系 findings (`nav_unreachable` 等) の severity: high が 0 件 → achieved、1 件以上 → unmet。**dev_server が推定できない場合は判定不能** = `verification_skipped` を記録して手動 pending に落とす (achieved 扱いにしない)
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
| medium / low のみ                                                            | JSONL 記録 + POST_MVP.md へ転記 (Step 5.6)。status `partial` 判定に反映                                                                         |
| agent エラー / JSON 解釈不能                                                 | `review_agent_failed` でエスカレ停止 (未検証をパス扱いにしない)                                                                                 |

#### Step 5.4: 結果分岐

| 状況                                                    | 対処                   |
| ------------------------------------------------------- | ---------------------- |
| 全ゴール achieved (or 手動 pending のみ) かつ high 0 件 | Step 6 へ (完了サマリ) |
| unmet ゴール or 修正可能な high findings が 1 件以上    | 未達対応ループへ       |

#### Step 5.5: 未達対応ループ

`goal_loop += 1`。`goal_loop > 2` なら P3 として停止 (エスカレ)。

それ以外:

1. 未達ゴール・修正可能な high finding (`unimplemented_api` / `schema_drift` / `infra_missing`) ごとに **GitHub issue を新規作成する** (`gh issue create --label ready`)。本文の節構造は dev-spec のフェーズ 12 と同じ (`## ゴール` / `## DoD` / `## 参照すべき docs` / `## 変更が想定されるファイル` / `## 非スコープ` / `## 実装タスク` / `## 依存`) にし、**`## DoD` には未達を検出した検証コマンドをそのまま入れる**。あわせて `docs/TODO.md` にも同じフェーズを追記する (issue の生成元と実体が食い違わないようにするため。判定基準は `../dev-spec/references/todo-generation.md` の「各フェーズが持つメタ情報」)
   - フェーズ内容は「G2 が未達。検証コマンド `<cmd>` が exit code != 0。失敗ログ: `<evidence>`。これを満たす実装を追加する」(findings 由来は `message` + `fix_proposal` を使う)
   - JSONL に `event_type: phase_added` で記録
2. Step 4 のフェーズループに戻る (新規追加フェーズだけが pending)
3. 完了後、Step 5.1 に戻って再判定 (Step 5.2 の監査 agent も**再起動**する。前回結果の使い回しは不可 — 修正が別の乖離を生んでいないかを再監査する)

手動 pending ゴールは Step 6 サマリで「人間確認必要」として明示する (dev-impl は判定せず保留)。

#### Step 5.6: POST_MVP.md の更新と status 判定

Step 5 のゴール判定後、`docs/POST_MVP.md` に **「UI/UX gap」セクション**を書き出す。**`PRODUCT_MODE=cli` の場合は本セクションを省略する** (status 判定の「UI/UX gap 全項目空」条件は自動的に満たされる)。`webapp` では常に書き出す。`unknown` では dev_server 推定が真の場合のみ書き出す (推定できなければ cli と同様に省略)。

##### UI/UX gap セクションの内容

セクションの必須項目テンプレート (未実装画面 / 未実装ナビ経路 / frontend-design 未適用フラグ / a11y 未対応項目 / 視覚的回帰参照) は [references/post-mvp-template.md](./references/post-mvp-template.md) を Read して従う。各項目は **dev-impl が自動でログ / review 結果から収集して埋める** (decisions.jsonl / review-product-readiness の findings / G_E2E 判定結果から)。

##### 未検証項目の集約

**実行しなかった検証は「成功」と区別できるよう必ず可視化する** (沈黙は成功に見えるため)。以下の事象は発生時に JSONL へ `event_type: verification_skipped` (context に対象と理由) を記録し、ここで集約して Step 6 サマリに列挙する:

- dev_server が推定できず skip した review-product-readiness / G_E2E 検証
- fix-lsp-warnings の失敗 (警告残存のまま継続した場合)
- 手動 pending のゴール
- implementer 報告の `verification_skipped` (Step 4.2e 手順 5 で転記済みのもの)
- `full_test_command` が Bash の 600 秒上限でタイムアウトした実行 (Step 4.2e)

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

サマリー生成前に、記載する各主張 (フェーズ完了数・ゴール達成状況・動的修正回数・受入監査結果) を本セッションの実際のツール実行結果 (`git log`、`decisions.jsonl`、review agent の出力 JSON) と突き合わせる。裏付けが取れない主張は記載しない、または「未確認」と明記する。テンプレートは [references/notification-template.md](./references/notification-template.md) の `## 完了サマリ (Step 6)` 節を Read し、全フィールドを埋めて出力する。

### Step 7: HTML レポート生成

dev-impl 終了時 (Step 6 完了後、またはエスカレ停止時) に `docs/dev-impl-reports/${run_id}.html` を生成する。

実装詳細とテンプレ関数は [references/report-template.md](./references/report-template.md) を参照。

生成手順:

1. JSONL ログ (`~/.claude/logs/dev-impl/${run_id}/decisions.jsonl`) を Read
2. テンプレ関数 (single-page Tailwind CDN HTML) でレポート HTML を組み立て
3. `mkdir -p docs/dev-impl-reports/` で出力先確保
4. Write で `docs/dev-impl-reports/${run_id}.html` に書き出し
5. `git add docs/dev-impl-reports/${run_id}.html` してコミット (HTML レポートは履歴管理する): `git commit -m "📝 docs: dev-impl ${run_id} 実行レポート"`

レポート内容: ヘッダー (run_id / SHA / 所要時間) / 全体サマリ / フェーズタイムライン / 動的修正詳細 (P1/P2/P3) / レビュー残課題 (low/medium) / 実装ノート (設計判断 / 未解決の質問) / POC_NEEDED 残存状況 (pending non-blocker) / ゴール達成判定 / 受入監査結果 (spec_compliance findings) / フッター。

## エスカレ停止時の挙動

停止条件:
- Step 4.2 のフェーズ内エスカレ条件 (`phase_fix_exceeded` / `guard_agent_failed` / `review_agent_failed` / `impl_failed` / `spawn_budget_exceeded` / `tests_failing_before_commit`)
- P3 検出 (DESIGN.md 概要レベルの再設計必要)
- `p2_fixes_total > 3` (P3 扱いに昇格)
- `goal_loop > 2` (ゴール達成判定 → 未達対応の 3 周回でも未達ゴール残存)
- `run_elapsed_minutes > 480` (`time_budget_exceeded`。試行回数の上限だけでなく経過時間でも打ち切る)
- 必須ドキュメント (DESIGN.md / DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md / TODO.md) 欠如
- `blocker=true` の POC_NEEDED マーカーが残存 (`poc_marker_unresolved`。dev-spec フェーズ 5 で解決してから再実行)
- Step 1 構造ゲートの欠落 (`design_not_approved` / `approval_stale` / `goals_missing` / `verification_missing`)
- テスト弱体化が設計にトレースできない (`test_weakening_detected`)
- P2 動的修正が受入基準 (ゴール / 検証手順行) を変更した (`acceptance_criteria_change`。dev-spec フェーズ 9 → 11 で再承認)
- 受入監査が受入基準の改変を検知 (`verification_tampered`。P3 扱い、修正ループなし)

停止時の処理:

1. 当該 issue の変更は**コミットしない** (緑状態でないため。working tree は残す)。**issue のラベルを停止理由で振り分ける**:

   | 停止理由 | ラベル | 再開のしかた |
   | --- | --- | --- |
   | 再実行で解決しうるもの (`phase_fix_exceeded` / `impl_failed` / `guard_agent_failed` / `review_agent_failed` / `spawn_budget_exceeded` / `tests_failing_before_commit` / `time_budget_exceeded`) | `in-progress` のまま | `/dev-impl` の再実行で Step 2 が再開対象として拾う |
   | 人間の判断が要るもの (P3 / `design_not_approved` / `approval_stale` / `goals_missing` / `verification_missing` / `poc_marker_unresolved` / `acceptance_criteria_change` / `test_weakening_detected` / `verification_tampered` / `dependency_blocked`) | **`needs-human` を貼り `in-progress` を外す** | 人間が対応した後、次の `/dev-impl` 起動時に Step 0 が確認してラベルを `ready` に戻す |

   人間の判断が要る側で `in-progress` のままにしてはならない。**再実行がそのまま同じ状態から再開してしまい、人間が何もしていないのに前進したように見える**ため。
2. 停止理由を `~/.claude/logs/dev-impl.log` と JSONL (`event_type: p3_escalate`) と stdout 全てに詳細出力
3. HTML レポート (Step 7) を生成 → コミット (停止時もレポートだけは残す)
4. ユーザに通知 (通知内容もログ・review agent の出力から裏付けが取れる事実のみを記載する)。テンプレートは [references/notification-template.md](./references/notification-template.md) の `## エスカレ停止通知` 節を Read し、全フィールドを埋めて出力する (Read せず記憶から近似文面を出すと、最終成功 commit SHA や完了フェーズ数など裏付け必須フィールドが欠落し停止理由の追跡性が落ちる)。

## 既存プロジェクトでの注意

- 既存のコミット history と dev-impl のコミット粒度を混ぜたくない場合は、dev-impl 起動前に専用の作業ブランチを切ることを推奨 (dev-impl 自体は起動ブランチの切替を行わない)
- `bypassPermissions` モード推奨 (途中で permission prompt が出ると dev-impl が止まるため)
- launchd / cron などからヘッドレス実行する場合は `claude -p` 経由で、`--allowedTools` に `Bash,Read,Edit,Write,Glob,Grep,Agent,Skill` を渡す。**headless では AskUserQuestion を使わない** (答える人間がいないため、質問した時点でループが死ぬ)。エスカレ時は停止理由を stdout と JSONL に出力し、darwin なら `terminal-notifier` で通知して終了する。Step 0 の再入確認 (working tree の扱い) も headless では確認せず「そのまま停止を継続」とし、人間の対話セッションでの再開を待つ

## 範囲外 (やらないこと)

- 設計の合意 (DESIGN.md / DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md 生成) → `/dev-spec`
- TODO.md の初期生成 → `/dev-spec` (フェーズ 10)
- GitHub issue の初期生成 → `/dev-spec` (フェーズ 12)。dev-impl は既にある issue を実装するだけで、着手対象の issue を自分では作らない (例外は Step 5 のゴール未達対応)
- 並列実装 → 行わない (issue を 1 件ずつ逐次に処理する)
- git push → ユーザー手動
- ブランチ切替・PR 作成 → ユーザー手動 (or `/workflow-create-draft-pr`)
- 動作検証 (実 UI / API テスト) → ユーザーが DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md の検証手順に従って実施

## 関連スキル / agent

### 内部呼び出し (subagent)

- **dev-impl-implementer**: フェーズ 1 本を TDD で実装する葉の agent (Step 4.2a `mode: implement` / Step 4.2d `mode: fix`、`model: opus` 明示)。`tools` に `Agent` を持たないため子 subagent を起動できず、5 分 TTL のキャッシュ失効を構造的に避ける。フェーズスコープのテストのみ実行し、コミット・`docs/` 編集・全体スイート実行はしない。全文報告を `report_path` に Write し、SendMessage では要約だけを返す (規約の全文は `claude/agents/dev-impl-implementer.md`)
- **tech-investigation**: 実装中に新たな技術検証が必要になった場合の個別呼び出しのみ (起動前の PoC は dev-spec フェーズ 5 の責務)
- **architecture-guard**: Clean Arch / DDD 境界違反検出、機械判定 (Step 4.2c の fan-out に毎フェーズ含める、haiku)
- **fix-lsp-warnings**: Lua/Neovim の LSP 警告修正 (Step 4.2b、haiku)。修正する agent なので検査 fan-out には混ぜず単独・逐次で走らせる
- **review-tdd / review-quality / review-product-readiness**: Step 4.2c から `model: opus` 明示で並列起動 (観点 gating・起動条件は Step 4.2c 参照)。review-quality は rules 準拠 + アーキテクチャ heuristic を統合。review-product-readiness は実機 chrome-devtools MCP 操作で UX 横断項目 (ナビ到達 / ErrorBoundary / 空状態 / loading / SEO meta / 404 / logout) を検査 (Step 5.2 の G_E2E 判定も担当)
- **review-adversarial**: Step 4.2c から `model: sonnet` 明示で並列起動する敵対的レビュワー。3 レンズ (A: エッジケース/エラーパスを能動的に攻撃し実際に実行して落とす、B: テスト弱体化・トートロジー化・アサーションの空虚化・skip 隠蔽の意味論検知、C: PHASE_CONTEXT を信用せず issue 本文の完了主張に反証を試みる) で検査。機械スキップ述語 (Step 4.2c 参照) を満たせば skip 可。`test_weakened` / `vacuous_assertion` / `skip_added` (confidence: high) は修正ラウンドに乗せず即エスカレ判定に直結する (詳細は Step 4.2d)

- **review-spec-compliance**: Step 5.2 から `model: opus` 明示で起動する第三者受入監査 (mode: post-impl)。承認ハッシュの独立照合・自動系ゴール検証コマンドの独立再実行・成果物全体 ↔ 詳細設計の突合・検証コマンドの空虚性検査。PHASE_CONTEXT 抜粋は渡さず docs を自分で全文 Read させる (被監査者が編纂した入力を信用しない)。`PRODUCT_MODE=cli` では G_E2E 検証コマンドの実行もこの agent が担当する (review-product-readiness は起動しないため)
- **security-guidance プラグイン**: セキュリティレビューはこのプラグイン (Edit/Write 時の pattern 検知 + Stop hook の LLM diff review) に委譲。自作 subagent は持たない

**空虚テスト検出の分担**: review-tdd の `vacuous_negative_assertion` は**新規に書かれたテストそのものの空虚性**を、review-adversarial レンズ B の `vacuous_assertion` は**基準時点 (PHASE_START_SHA) からの空虚化**を見る。同一フェーズで両者が同種の指摘を上げることがあるが、検査している次元が違うため統合しない (統合するとどちらか一方の次元が検査されなくなる)。

**全ての subagent に作業ディレクトリ (`repo_dir`) を絶対パスで渡す。** subagent の Bash は呼び出しごとに cwd が親のものへ戻るため、渡さないと検査対象・編集対象が意図したディレクトリにならず、空差分で素通りする。

**全テストゲート / コミット / issue のラベル操作と close / RUN_FACTS 更新 / decisions.jsonl は必ず main が行う** (commit-msg-guard hook は親にしか効かないため)。

### 内部呼び出し (skill)

なし。P2 動的修正時の TODO 再生成は `../dev-spec/references/todo-generation.md` を Read してメインループで直営する (Skill ツール経由ではモデル指定が効かないため、skill 呼び出しは増やさない)。

(手動レビュー用の `workflow-review` skill と `workflow-commit` skill は dev-impl からは呼ばない。相当の処理は Step 4.2d / 4.2e が担う)

### 連携 hook

- **commit-msg-guard hook (`claude/hooks/commit-msg-guard.ts`)**: Step 4.2e のコミット subject 形式を PreToolUse(Bash) で機械検証する。検証が働くのは `$GHQ_ROOT/github.com/skanehira/` 配下で作業しているときだけで、それ以外のリポジトリでは fail-open
- **agent-spawn-guard hook (`claude/hooks/agent-spawn-guard.ts`)**: PreToolUse(Agent) で、`MANDATED_MODEL` に登録された agent (dev-impl-implementer / architecture-guard / fix-lsp-warnings / review-*) の **model 未指定を deny** する。加えて review-spec-compliance の prompt に必須フィールドが揃っているかを検証する。無効化は `AGENT_SPAWN_GUARD=off`

### 前段 / 後段

- **dev-spec**: 前段。設計ループ (要件整理 〜 PoC 検証 〜 設計書 〜 TODO 生成)。承認ゲートで本スキルの起動方法を案内する
- **workflow-create-draft-pr**: 後段 (任意)。PR 作成はユーザーが手動で起動する
