---
name: utility-self-improving
description: 過去のClaude Codeセッション履歴 (~/.claude/archive/) を解析し、ユーザーが繰り返し指摘したパターン (3回以上観測) を抽出して、dotfilesリポ (~/dev/github.com/skanehira/dotfiles) のClaude設定 (CLAUDE.md/rules/skills/agents/hooks) を改善するDraft PRを自動作成するスキル。「過去履歴から改善を抽出」「自己改善」「セッション履歴を分析してPRを作成」「/utility-self-improving」「最近の指摘をrulesに反映したい」「Claude設定を自動改善」「ハーネスを継続改善」などのリクエストで起動する。引数で解析期間 (日数) を指定可能、省略時は直近7日。Mac Studio 上の launchd から `claude -p` 経由で週次自動実行することを想定している。ユーザーが繰り返し同じ指摘をしている気配がするとき、Claude のハーネスを育てたいとき、設定の磨き込みをしたいときには必ずこのスキルを使うこと。
allowed-tools: Read, Edit, Write, Glob, Bash, Agent
---

# utility-self-improving

## 目的

Claude Code を日常的に使うなかで、ユーザーが**繰り返し**指摘する内容を過去セッション履歴 (`~/.claude/archive/*.jsonl`) から自動抽出し、dotfilesリポにある Claude 設定 (`CLAUDE.md` / `rules/` / `skills/` / `agents/` / `hooks/`) の改善 Draft PR を作成する。

**なぜ「繰り返し」だけを対象にするか**: 一回限りの指摘 (場面依存の好み・気分・誤読) を恒久ルール化すると、誤った"反省"が積み上がり Claude の挙動が硬直化する。**3回以上**の観測閾値は、偶発的な指摘とパターン化した不満を切り分けるための実効的なフィルタである。閾値を緩めるとノイズが増え、厳しくすると改善機会を逃す。3 は経験則として保守側に置いている。

**なぜ自動マージしないか**: ヒューリスティック抽出も主題クラスタリングも判定誤りを含む。誤った"反省"を恒久ルールにすると逆効果になるため、Draft PR で人間レビューを必ず挟む。スキルの責務は「候補を提示すること」であって「決定すること」ではない。

## 起動

```
/utility-self-improving [日数]
```

- `日数` 省略時: 直近 **7 日**
- 例: `/utility-self-improving 14` で直近 14 日、`/utility-self-improving 30` で直近 30 日

なぜ 7 日か: launchd で週次自動実行する運用 (毎週日曜 05:00) に合わせて、観測対象を直近 7 日に絞る。Mac Studio で `claude -p` が定期的に起動して、その週分の指摘を解析・PR 化する。手動で実行する場合は、観測閾値 (3 セッション以上) を満たすかどうかは履歴の濃さ次第なので、引数で `14` や `30` に広げてよい。

引数の解析:

```bash
DAYS="${1:-7}"
# 数値以外は弾く
if ! [[ "$DAYS" =~ ^[0-9]+$ ]]; then
  echo "Error: 日数は正の整数で指定してください"; exit 1
fi
```

## 前提

- dotfilesリポは `~/dev/github.com/skanehira/dotfiles` に clone 済み
- `gh` CLI が認証済み (`gh auth status` で確認)
- `~/.claude/archive/` 配下に jsonl が archive されている (`settings.json` の SessionEnd hook + `claude/hooks/archive-transcript.ts` が各セッション終了時に自動コピー、保持期間 90 日。同時に古いファイルは自動削除されるため掃除不要)
- 作業前に dotfilesリポが clean な状態である (uncommitted な変更があれば中断して報告)

**なぜ `~/.claude/projects/` を直接見ないのか**: 公式は jsonl 形式を「内部形式、将来変更あり」と明言しており、claude-history-sync の bisync 進行中だと中途半端な行を読む可能性もある。SessionEnd hook で確定済みのファイルを `~/.claude/archive/` に immutable コピーすることで、解析対象の安定性と整合性を確保する。

## アーキテクチャ

main session が orchestrator、重い処理は subagent に分担:

| 段階 | 担当 | model | 役割 |
|---|---|---|---|
| § 2 抽出 | `self-improving-extractor` subagent | haiku | jsonl の機械的処理。Python スクリプトで強いシグナル候補を絞り込み |
| § 3 判定 | `self-improving-judge` subagent | sonnet | クラスタリング + 改善対象判定。言語理解と分類が要 |
| § 1 § 4-7 | main session | (呼び出し元と同じ) | 前提チェック・git/gh 操作・PR 文面生成 |

subagent はそれぞれ fresh context で起動するため、main セッションは大量の jsonl 内容や個別の発言を context に積まずに済む (機密情報の漏出リスクと token cost の両方を抑える)。

## 進捗ログの記録 (実行中の状況可視化)

launchd や `claude -p` 経由で実行される場合、`stdout` は完了時に 1 度だけ書かれるため、実行中の状況がほぼ見えない。これを補うため、**`~/.claude/logs/self-improving-progress.log`** に主要マイルストーンを追記する。

### 書き込みルール

main session も subagent も、以下のタイミングで Bash で 1 行追記する:

```bash
PROGRESS_LOG="$HOME/.claude/logs/self-improving-progress.log"
mkdir -p "$(dirname "$PROGRESS_LOG")"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [<role>] <message>" >> "$PROGRESS_LOG"
```

`<role>` は `main` / `extractor` / `judge`。`<message>` は段階名と要点を 1 行で。

### マイルストーン

| Role | タイミング | メッセージ例 |
|---|---|---|
| main | § 1 開始/完了 | `§ 1 前提チェック完了 (archive: N files, dotfiles: clean)` |
| main | § 2 extractor 起動前/復帰後 | `§ 2 extractor 復帰 (typed=761, strong=46)` |
| main | § 3 judge 起動前/復帰後 | `§ 3 judge 復帰 (clusters_adopted=N, rule_audit=M)` |
| main | § 4 ブランチ作成・各クラスタ反映 | `§ 4 cluster 1/3 applied (CLAUDE.md L11)` |
| main | § 5 コミット完了ごと | `§ 5 commit (SHA short)` |
| main | § 6 PR 作成 | `§ 6 PR #N created (draft)` |
| main | § 7 インラインコメント完了 | `§ 7 inline comment posted (line N)` |
| main | § 8 rule-audit PR 作成 or skip | `§ 8 rule-audit PR skipped (all previously_reported)` |
| main | 全工程完了 | `全工程完了 (PR=#N or なし)` |

### 失敗時の書き込み

例外発生・中断時にも `[<role>] FAILED: <理由>` を書く。これがあれば「どこで止まったか」が `tail -f` で即わかる。

## 処理フロー

全体は次の 7 段階。途中で失敗したらロールバックして報告する。半端な PR を残さない。**各段階の境界で進捗ログを書く** (詳細は前章)。

### 1. 前提チェック

```bash
# archive ディレクトリ
test -d ~/.claude/archive && find ~/.claude/archive -name "*.jsonl" -type f -mtime -${DAYS} | head -1

# dotfiles リポの状態
(cd ~/dev/github.com/skanehira/dotfiles && git status --porcelain)
```

- archive が存在しない or 空: 「SessionEnd hook (`claude/hooks/archive-transcript.ts`) が動作してから再実行してください」と報告して終了。エラー扱いではない
- dotfiles リポが dirty: 中断して人間に対応を依頼

### 2. 指摘の抽出 (subagent 委譲)

`Agent` ツールで **`self-improving-extractor`** (model: haiku) を起動する。

入力:
- `days`: 解析期間 (引数)
- `output_path`: scratchpad 配下の `strong-signals.jsonl`

extractor が担当する処理:
1. `~/.claude/archive/` の jsonl 走査
2. `promptSource: "typed"` な純粋ユーザー発言の抽出
3. `<command-message>` や `<local-command-stdout>` で始まる発言の除外
4. `heuristics.md` のシグナルパターンに合致する候補のフィルタ
5. 強いシグナル (direct_neg / stop / correction / retry / expectation_gap / dissatisfaction / negative_question) を含むものだけ残す

extractor は Python スクリプトを scratchpad に書き出して `python3` で実行する。500MB 級のログでも数秒で完走するメカニカル処理。main session は extractor が返す**統計値だけ**を受け取る (件数・期間)。生データは scratchpad の jsonl に残し、context には載せない。

詳細は `~/.claude/agents/self-improving-extractor.md` を参照。

### 3. クラスタリングと改善対象判定 (subagent 委譲)

`Agent` ツールで **`self-improving-judge`** (model: sonnet) を起動する。

入力:
- `input_path`: extractor が書き出した `strong-signals.jsonl`
- `output_path`: scratchpad 配下の `clusters.json`

judge が担当する処理:
1. `(session_id, content)` でデデュープ
2. 引用ブロック内のレビューコメントを `heuristics.md` の判別基準で取り扱う (Claude 出力へのレビュー → 学習対象、顧客資料の貼り付け → 除外)
3. 主題ごとのクラスタリング (Claude の言語理解で判断)
4. 観測セッション数 3 件未満は skipped へ
5. 上位 5 件採用、観測数の多い順にソート
6. `classification.md` のフローで各クラスタの更新対象を決定
7. 機密情報を含まない `clusters.json` を出力 (プロジェクト名・セッションID・発言抜粋は持ち込まない)

main session は judge の `clusters.json` を Read で読み込み、§ 4 以降に進む。

詳細は `~/.claude/agents/self-improving-judge.md` を参照。

### 4. 変更の適用

`clusters.json` の `clusters_adopted` を順に処理する:

- 作業ディレクトリ: `~/dev/github.com/skanehira/dotfiles`
- `git checkout master && git pull --ff-only origin master` で最新化
- ブランチ作成: `chore/self-improvement-YYYY-MM-DD`
  - 同名ブランチが既に存在する場合は `-2`, `-3` のサフィックスを付ける
- 各クラスタについて:
  1. `target_file` を Read で読む
  2. `anchor` (既存テキスト) を Edit ツールの old_string の手がかりにする
  3. `anchor` を含む行の直後に `proposed_addition` を挿入

既存テキストとの整合性に注意: 重複・矛盾が出ないようにマージする (judge が一定の整合を見ているが、main 側で再確認)。

### 5. コミット

`/workflow-commit` を呼び出すか、直接 Conventional Commit 形式で commit する。

- **複数クラスタは複数コミットに分割** (1クラスタ = 1コミット)。後段のインラインコメントを hunk 単位で付けやすくするため
- メッセージ例: `📝 docs(claude): avoid 'any' type in TypeScript edits`
- body には観測回数 (匿名化済み) と観測パターンの類型を含める。**プロジェクト名・セッションID・ユーザーの生の発言抜粋・コード引用は含めない** (§ 7「機密情報の取り扱い」と同じ原則。コミットメッセージも `git log` で永続化されるため同等)

### 6. Draft PR 作成

`/workflow-create-draft-pr` を呼び出して PR を作成する。

- ターゲットブランチ: `master`
- **必ず Draft で作成** (`gh pr create --draft`)。直接マージは禁止
- PR 本文テンプレート:

```markdown
## 解析サマリ

| 項目 | 値 |
|---|---|
| 解析期間 | YYYY-MM-DD ~ YYYY-MM-DD |
| 対象セッション数 | N |
| 抽出された指摘の総数 | M |
| クラスタ数 (3回以上) | K |
| PR採用件数 | J / K |

## 採用クラスタ

1. **<クラスタ名1>** (N回観測) → `<更新対象ファイル>`
2. **<クラスタ名2>** (M回観測) → `<更新対象ファイル>`
...

## 確認方法

各 hunk のインラインコメントに観測根拠を記載しています。誤った"反省"を採用していないか確認してから ready for review に切り替えてください。
```

### 7. インラインコメントの追加

PR 作成後、各 hunk に `gh api` 経由でインラインコメントを追加する。

```bash
gh api -X POST \
  /repos/skanehira/dotfiles/pulls/<PR番号>/comments \
  -f body="<コメント本文>" \
  -f commit_id="<コミットSHA>" \
  -f path="<ファイルパス>" \
  -F line=<行番号> \
  -f side=RIGHT
```

**コメント本文の必須要素**:

```markdown
**観測回数**: N セッション (M 個の異なる作業対象)

**観測パターン**:
<指摘の類型を抽象化した記述。具体的な依頼内容・引用・固有名詞は含めない>

**推定根本原因**:
<なぜユーザーが繰り返し指摘したのか、観察された行動の要約>
```

これは「自動学習が誤っていないか」を人間がレビューするための判断材料である。観測根拠が無いと、ユーザーが PR を見ても採否を判断できない。`observation_pattern` と `estimated_root_cause` は judge が生成した `clusters.json` の同名フィールドをそのまま使う。

**機密情報の取り扱い (絶対遵守)**:

PR コメント・コミットメッセージ・PR 本文はすべて GitHub に永続化され、リポジトリへのアクセス権を持つ第三者が閲覧可能。dotfiles リポジトリは公開設定の可能性があり、解析対象のセッションには顧客名・要件詳細・社内固有名詞・契約情報が含まれることがある。以下は **PR コメント・コミットメッセージ・PR 本文** に絶対に含めない:

- **プロジェクト名・リポジトリ名・組織名** — `owner/repo` 形式の具体名は禁止。「N 個の異なる作業対象」のように匿名化する
- **セッションID (UUID)** — 一意の識別子は GitHub に永続化されるため記載しない (内部処理のメタデータとしては保持してよいが、外に出さない)
- **ユーザーの生の発言抜粋** — 引用ブロック (` > ... `) での発言転載は禁止。発言の内容は **指摘の類型** に抽象化してから記述する
- **コードや設計書の引用** — 機密情報を含むことがあるため一切引用しない
- **ファイルパス・URL・ドメイン名・人名** — 解析対象セッションに出てきたものは記載しない (dotfiles リポ自身のパスは除く)

抽象化の原則: 「観測パターン」セクションでは指摘の **行動カテゴリ** だけ記述する。「ユーザーが具体例の追加を繰り返し指示するパターン」「ユーザーが依頼スコープ外の論点を出した点を繰り返し指摘するパターン」のように、原文や事例固有の文脈は捨てる。judge が生成する `clusters.json` はこの原則に沿って書かれているはずだが、main 側で最終チェックする。

**この制約を守れない場合は、コメントを付けない**。インラインコメントは判断材料の補助であって必須ではない。守れない方が悪い。Draft PR で人間レビュアーがマージ判断する仕組みは残るので、コメント無しでも運用は破綻しない。

行番号の決定: 各コミットの diff から、追加行 (`+`) の最初の行に付ける。ファイル全体の追記なら追加ブロックの先頭行。

### 8. ルール監査 PR (任意、新規 audit があれば)

judge の出力 `clusters.json` の `rule_audit` に **新規** (前回未報告) のエントリが含まれていれば、自己改善 PR とは**別の Draft PR** として「ルール監査 PR」を作成する。

**重複報告の回避**: judge は各 `rule_audit` エントリに `previously_reported: true|false` フィールドを付与する (MEMORY.md と照合し、過去の audit PR で同一内容を報告済みなら `true`)。main session は以下の条件で skip する:

- `rule_audit.duplicates` と `rule_audit.conflicts` の **全エントリ** で `previously_reported: true` → ルール監査 PR を作らない (進捗ログに「§ 8 skipped: all previously_reported」を書く)
- 1 件でも `previously_reported: false` (= 新規検出) があれば PR 作成 → ただし PR 本文には新規分のみ載せる (継続案件は人間が PR #5 のような既存 PR で管理する想定)

これにより週次自動運用で同じ rule_audit PR が毎回立つことを防ぐ。

- ブランチ: `chore/rule-audit-YYYY-MM-DD` (master から派生)
- ターゲット: `master`
- Draft で作成 (人間レビュー必須)
- 本文テンプレート:

```markdown
## ルール監査結果

`/utility-self-improving` の判定段階 (judge subagent) で検出された、既存ルール (CLAUDE.md / rules/) の整理候補。

### 重複候補

| 内容 | 該当ファイル | 提案アクション |
|---|---|---|
| <description> | <files> | <suggested_action> |

### 矛盾候補

| 内容 | 該当ファイル | 補足 |
|---|---|---|
| <description> | <files> | <context> |

## 注意

このPRは**観察結果と提案のみ**です。ルール削除や統合は自動で行いません。各エントリを確認の上、手作業で整理してください (誤検出で重要ルールを消す事故を防ぐため)。
```

このステップは:
- `rule_audit` の `duplicates` と `conflicts` がいずれも空なら**スキップ** (PR を作らない)
- 自己改善 PR とは関心事が違うため**別 PR で出す** (自己改善 = 観測由来の追記、rule-audit = 既存ルールの整理)
- diff はゼロでよい (ファイル変更なし、本文に観察結果を記載するだけ) — `git commit --allow-empty` で空コミットを 1 つ作って push

ルール削除や統合は**自動で行わない**。判断と作業は必ず人間が行う。

## ガードレール (再掲)

- **Draft PR 必須**: 自動マージは絶対にしない
- **観測閾値 3 セッション**: それ未満は skipped ログに残すのみ
- **1 PR あたり最大 5 件**: 認知負荷とレビュー品質のバランス
- **failure-stops-pipeline**: 途中で `gh` がエラー、ブランチ作成失敗、commit 失敗、subagent 失敗のいずれかが起きたらロールバックして報告
- **既存変更の保護**: dotfilesリポに uncommitted な変更があれば最初に中断
- **subagent の責務範囲を守る**: extractor は jsonl 抽出のみ、judge は判定のみ、Edit/commit/PR は main の担当。subagent から git 操作はしない
- **PR が大きすぎる場合の自己抑制**: 1 クラスタの diff が 200 行を超えるなら、それは「ルール追記」ではなく「リファクタ」になっている可能性が高い。スコープを切って分割する

## 出力サマリ

完了時にユーザーへ次を報告する:

```
解析期間: YYYY-MM-DD ~ YYYY-MM-DD
対象セッション数: N
抽出された指摘の総数: M
クラスタ数 (3 セッション以上): K
PR採用件数: J / K
スキップ記録: <scratchpad/self-improvement-skipped-YYYY-MM-DD.jsonl>
PR URL: https://github.com/skanehira/dotfiles/pull/XXX
```

## 失敗時の挙動

| 失敗ケース | 振る舞い |
|---|---|
| archive が空 (SessionEnd hook 未実行) | 報告して終了。エラー扱いではない |
| 3 セッション以上のクラスタが 0 件 | 「学習対象の繰り返しパターンが見つかりませんでした」と報告。skipped ログのパスを案内 |
| dotfilesに uncommitted な変更がある | 中断して人間に対応を依頼 |
| extractor / judge subagent が失敗 | エラー内容を報告して中断。retry はせず、人間の判断を仰ぐ (誤った "成功扱い" を防ぐため) |
| git push 失敗・gh API 失敗 | ローカルブランチは残したまま中断、エラー内容を報告 |
| インラインコメント API がレート制限 | コメント済みのものは残し、未完了分を sleep + retry。3 回失敗で諦めて報告 |

## ドライランモード

破壊的操作なしで動作確認したい場合:

```
/utility-self-improving 7 --dry-run
```

- § 1〜§ 3 (前提チェック・抽出・判定) までは実行
- § 4 以降 (ブランチ作成・コミット・PR 作成・インラインコメント) はスキップ
- 結果サマリと `clusters.json` の内容を標準出力に表示するのみ

これは最初の数回 (スキルの挙動を確かめる段階) で使う。本番運用に乗ったら省略してよい。

## 参考

- 判定ヒューリスティック: `references/heuristics.md`
- 改善対象の振り分け基準 (どのファイルに書くか): `references/classification.md`
- 施策選択ガイド (強制レベル・公式準拠の決定木): `references/treatment-guide.md`
- subagent (extractor): `~/.claude/agents/self-improving-extractor.md`
- subagent (judge): `~/.claude/agents/self-improving-judge.md`
