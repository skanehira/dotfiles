---
name: utility-dev-impl-measure
description: dev-impl の改修効果を before/after で計測する。実行セッションを「改修前 / 改修後 / 除外」に分類し、判定 4 指標 (main 平均コンテキスト / フェーズあたり main リクエスト数 / 子待ち subagent の TTL 失効 / phase_fix_round 平均) を出して合否と次アクションを提示する。「dev-impl の計測をして」「改修効果を測って」「before/after を比較して」「dev-impl 重くなってない?」などで起動。
argument-hint: "[セッション ID。省略時は改修後の全セッション]"
allowed-tools: Read, Bash
model: opus
---

# utility-dev-impl-measure — dev-impl の効果計測

dev-impl の Step 4 改修 (フェーズ実装を葉の subagent へ隔離、2026-08-01) が効いているかを、改修前と同じ方法で測る。

**手順と判定基準の正は `~/.claude/handoff/dev-impl-refactor/MEASUREMENT.md`** (種別: 手順書)。本スキルはその実行体で、判断を伴う「分類の妥当性確認」と「逸脱の原因追跡」だけを担う。数値の定義・baseline の固定値・分類規則の根拠は MEASUREMENT.md 側にあるので、ここでは繰り返さない。

## Step 0: 前提確認

```bash
TOOLKIT=~/.claude/handoff/dev-impl-refactor
test -f "$TOOLKIT/MEASUREMENT.md" && test -d "$TOOLKIT/analysis" && echo TOOLKIT_OK
```

`TOOLKIT_OK` が出なければ**ここで止める**。「計測 toolkit (`~/.claude/handoff/dev-impl-refactor/`) が見つかりません。別マシンか、ディレクトリが失われています」とユーザーに伝える。この toolkit は dotfiles 管理外 (ローカルのみ) なので、マシンを移ると存在しない。

## Step 1: 手順書を読む

`$TOOLKIT/MEASUREMENT.md` を Read する。**近似で代替しない** — 分類規則には偽陽性を避けるための具体的な根拠があり、記憶で組み立てると 2026-08-08 に実測で確認済みの落とし穴 (dotfiles セッションの誤検出 / `agent_listing_delta` による偽陽性) を踏む。

## Step 2: セッションの洗い出しと分類

```bash
mkdir -p ~/.claude/logs/dev-impl-measure
cd ~/.claude/handoff/dev-impl-refactor/analysis
python3 inventory.py ~/.claude/logs/dev-impl-measure/inventory.json >/dev/null
python3 classify_runs.py ~/.claude/logs/dev-impl-measure/inventory.json \
  --json ~/.claude/logs/dev-impl-measure/groups.json
```

**出力先は固定パスにする** (`mktemp -d` を使わない)。Bash はツール呼び出しごとにシェルが作り直されるため**シェル変数が次の呼び出しに引き継がれず**、一時ディレクトリのパスを Step 3 で参照できなくなる。

分類結果を目で確認する。**改修後に分類されたセッションの `project` が妥当か**を見る (dotfiles や無関係なリポジトリが混ざっていないか)。おかしければ MEASUREMENT.md §3 の規則と突き合わせ、判断をユーザーに提示してから進む。

**改修後が 0 件なら計測せずに終了する。** 「dev-impl を新構造で実走したセッションがまだありません。実走してから再度 `/utility-dev-impl-measure` を実行してください」と伝える。無理に改修前だけを測っても意味がない。

## Step 3: 判定指標の算出

改修後の各セッションについて実行する。`$ARGUMENTS` でセッション ID が指定されていればそれだけを対象にする。

`decisions.jsonl` の場所は transcript から run_id を引いて解決する (再入した run では複数出るので**最後のものを使う**):

```bash
cd ~/.claude/handoff/dev-impl-refactor/analysis
SESSION=<session_id>   # 1 回の Bash 呼び出しの中で完結させる (変数は次の呼び出しに残らない)
TRANSCRIPT=$(python3 -c "
import json
g=json.load(open('$HOME/.claude/logs/dev-impl-measure/groups.json'))
print([e['path'] for e in g['after'] if e['session_id'].startswith('$SESSION')][0])")
RUN_ID=$(rg -o 'dev-impl/[0-9]{8}-[0-9]{6}' "$TRANSCRIPT" | sort -u | tail -1 | cut -d/ -f2)
DECISIONS=~/.claude/logs/dev-impl/${RUN_ID}/decisions.jsonl
test -f "$DECISIONS" || echo "DECISIONS_MISSING"

python3 run_metrics.py "$SESSION" --decisions "$DECISIONS"
```

`decisions.jsonl` が見つからない場合は `--phases <フェーズ数>` で代替する (フェーズ数は当該プロジェクトの `docs/TODO.md` の `### フェーズ` 見出し数)。その場合は**指標 4 が出ない**ので、報告に「未測定」と明示する。

## Step 4: 合否の判定と報告

MEASUREMENT.md §5 の判定ラインと照合し、次の形で報告する:

| # | 指標 | 改修前 | 今回 | 判定 |
| - | --- | ---: | ---: | --- |
| 1 | main 平均コンテキスト | 443,863〜515,258 tok | | 合格 < 250,000 tok |
| 2 | フェーズあたり main リクエスト数 | 94.0 回 | | 合格 < 40 回 |
| 3 | 子待ち subagent の TTL 失効 | 32 件 | | 合格 0 件 |
| 4 | `phase_fix_round` 平均 | (改修前は未集計) | | 合格 < 1.0 回 |

複数セッションある場合は 1 行ずつ出し、末尾に平均を添える。**フェーズ単価は参考値として併記してよいが、合否には使わない** (プロジェクト規模に依存するため)。

## Step 5: 逸脱の原因追跡

不合格の指標があれば、対応する追跡先を提示する (原因の断定はせず、どこを見れば分かるかを示す):

| 不合格の指標 | まず見るもの | 想定される原因 |
| --- | --- | --- |
| 1 (コンテキストが下がらない) | `run_metrics.py` の main requests と、transcript 内の `Read` / `git diff` の使われ方 | SKILL.md「main のコンテキスト規律」が守られていない (main がソースや findings 本文を読んでいる) |
| 2 (往復が減らない) | `decisions.jsonl` の `spawn` イベント数 / フェーズ | 検査 fan-out が 1 回にまとまっていない、修正ラウンドが多い |
| 3 (TTL 失効が出る) | `spike_probe.py <session_id>` の `spawned_children` | implementer が子 subagent を起動している = 葉性が壊れている。`agents/dev-impl-implementer.md` の `tools` に `Agent` が混入していないか確認する |
| 4 (修正ラウンドが多い) | `decisions.jsonl` の `fix_dispatch` の `fatal_summary` と、当該 run の RUN_FACTS.md | PHASE_CONTEXT / RUN_FACTS がフェーズ間の文脈を代替できていない (PLAN.md §6 リスク 1) |

副次的に見る値 (合否には使わないが悪化していたら原因を追う) は MEASUREMENT.md §5 の末尾を参照する。

## 範囲外 (やらないこと)

- スクリプトの改変 — `inventory.py` / `analyze.py` / `residency.py` は baseline を出したときと同一である必要がある。改変が要ると判断したら、その旨をユーザーに提示して判断を仰ぐ
- 改修の是非の判断・ロールバックの実行 — 数値と追跡先を出すところまで。巻き戻すかはユーザーの決定
- 計測結果の HTML レポート化 — 依頼があれば別途 (`analysis/gen_report.py` が改修前レポートの生成器)

## 関連

- `~/.claude/handoff/dev-impl-refactor/MEASUREMENT.md` — 手順・分類規則・baseline・判定ラインの正
- `~/.claude/handoff/dev-impl-refactor/HANDOFF.md` — 改修前の分析全文と棄却済み案
- `~/.claude/handoff/dev-impl-refactor/PLAN.md` — 改修計画とリスク・打ち切り基準
- `~/.claude/handoff/dev-impl-refactor/U0-FINDINGS.md` — 改修後 1 フェーズの spike 実測
