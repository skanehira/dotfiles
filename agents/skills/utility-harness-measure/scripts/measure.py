#!/usr/bin/env python3
"""ハーネス改訂の効果を claude -p で計測する。

サブコマンド:
  estimate  実行前の費用見積もり
  run       シナリオを N 回実行して events.jsonl を保存する
  check     各回の有効性 (実モデル・上限停止・エラー) を判定する
  grade     有効な回を匿名化して採点し、対照を検証して集計する

トピック (計測対象の規定 1 件) のディレクトリ構成は SKILL.md を参照。
"""

import argparse
import concurrent.futures
import datetime
import json
import os
import random
import re
import subprocess
import sys
from pathlib import Path

# 正式 ID。世代交代したらここだけを更新する
MODEL_IDS = {
    "opus": "claude-opus-5-5",
    "sonnet": "claude-sonnet-5-5",
    "haiku": "claude-haiku-5-5",
    "fable": "claude-fable-5-1",
}
DEFAULT_MODEL = MODEL_IDS["opus"]
COST_PER_RUN_USD = (3, 6)
RANK = {"haiku": 1, "sonnet": 2, "opus": 3, "fable": 4, "mythos": 4}
USAGE_LIMIT_MARKERS = ("hit your session limit", "usage limit")
# 子に渡す環境変数。認証は HOME 経由 (キーチェーン) で通るので、トークン類は渡さない
CHILD_ENV_KEYS = ("PATH", "HOME", "USER", "LOGNAME", "SHELL", "LANG", "LC_ALL", "TMPDIR", "TERM")


def child_env(environ):
    return {k: environ[k] for k in CHILD_ENV_KEYS if k in environ}


def normalize_model(name):
    return re.sub(r"\[[^\]]*\]$", "", name)


def model_rank(model_id):
    for family, rank in RANK.items():
        if family in model_id:
            return rank
    raise ValueError(f"モデルの格が判定できない: {model_id}")


def pinned_settings(exec_model):
    """子の claude が使う別名をすべて正式 ID に固定する settings。

    ユーザー設定の env が別名を別モデルに解決していても、--settings の env が優先される。
    子は bypassPermissions で動くので、サンドボックスで HOME 配下 (~/.claude や dotfiles の
    正本) への書き込みを塞ぐ。作業ディレクトリと一時ディレクトリへの書き込みは通る。
    """
    return {
        "sandbox": {"enabled": True, "autoAllowBashIfSandboxed": True,
                    "allowUnsandboxedCommands": False},
        # 空文字で advisor ツールを無効にする。ユーザー設定の advisorModel が生きていると、
        # 子が advisor を呼んだ回に別モデルが modelUsage へ混ざり、実行モデルを照合できなくなる
        "advisorModel": "",
        "env": {
            "ANTHROPIC_MODEL": exec_model,
            "ANTHROPIC_DEFAULT_OPUS_MODEL": MODEL_IDS["opus"],
            "ANTHROPIC_DEFAULT_SONNET_MODEL": MODEL_IDS["sonnet"],
            "ANTHROPIC_DEFAULT_HAIKU_MODEL": MODEL_IDS["haiku"],
        }
    }


def allowed_models(exec_model):
    return {exec_model, MODEL_IDS["opus"], MODEL_IDS["sonnet"], MODEL_IDS["haiku"]}


def read_events(path):
    events = []
    for line in Path(path).read_text().splitlines():
        line = line.strip()
        if line:
            events.append(json.loads(line))
    return events


def _results(events):
    return [e for e in events if e.get("type") == "result"]


def final_message(events):
    """読み手に届く全文。バックグラウンドタスクで再開した回は result が複数あるので順に連結する。"""
    return "\n\n---\n\n".join(r.get("result", "") for r in _results(events))


def check_run(events, exec_model, allowed):
    results = _results(events)
    if not results:
        return (False, "result イベントが無い (途中で止まった)")
    last = results[-1]
    text = last.get("result") or ""
    if any(m in text for m in USAGE_LIMIT_MARKERS):
        return (False, "使用量の上限で停止")
    if last.get("is_error"):
        return (False, f"エラーで終了: {text[:80]}")
    used = {normalize_model(m) for r in results for m in (r.get("modelUsage") or {})}
    unexpected = sorted(used - allowed)
    if unexpected:
        return (False, f"想定外のモデル: {', '.join(unexpected)}")
    if exec_model not in used:
        return (False, f"実行モデル {exec_model} が使われていない")
    return (True, "ok")


def parse_grader_output(raw):
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        raise ValueError(f"採点の出力が読めない: {raw.strip()[:200]}") from None
    events = data if isinstance(data, list) else [data]
    results = _results(events)
    if not results:
        raise ValueError("採点の出力に result イベントが無い")
    text = re.sub(r"^```[a-z]*\s*|\s*```$", "", (results[-1].get("result") or "").strip())
    try:
        scores = json.loads(text)
    except json.JSONDecodeError:
        raise ValueError(f"採点の出力が読めない: {text[:200]}") from None
    models = sorted({normalize_model(m) for m in results[-1].get("modelUsage") or {}})
    return (scores, models)


def validate_controls(scores, key, expected):
    errors = []
    for sid, source in sorted(key.items()):
        if not source.startswith("control:"):
            continue
        name = source.split(":", 1)[1]
        if sid not in scores:
            errors.append(f"対照 {name} の採点が無い")
            continue
        for item, want in expected["controls"][name].items():
            got = scores[sid].get(item)
            if got != want:
                errors.append(f"対照 {name} の {item}: 期待 {want} / 実際 {got}")
    return errors


def blind_assign(items, seed):
    shuffled = list(items)
    random.Random(seed).shuffle(shuffled)
    return {f"X{i:02d}": src for i, src in enumerate(shuffled, start=1)}


def aggregate(scores, key, expected):
    groups = {}
    for sid, source in key.items():
        if source.startswith("control:"):
            continue
        label, run = source.split("/", 1)
        scenario = run.rsplit("-", 1)[0]
        groups.setdefault((label, scenario), []).append(scores[sid])
    rows = []
    for (label, scenario), runs in sorted(groups.items()):
        totals, full = [], 0
        counts = {item: 0 for item in expected["items"]}
        for s in runs:
            vals = [(s.get(i) or 0) if s.get("has_decision") else 0 for i in expected["items"]]
            totals.append(sum(vals))
            full += all(v == expected["max"] for v in vals)
            for item, v in zip(expected["items"], vals):
                counts[item] += v == expected["max"]
        rows.append({"label": label, "scenario": scenario, "runs": len(runs),
                     "full": full, "mean": round(sum(totals) / len(totals), 1),
                     "max_counts": counts})
    return rows


# ---- CLI -------------------------------------------------------------------

def scenarios_of(topic, names):
    root = Path(topic) / "scenarios"
    found = sorted(p.name for p in root.iterdir() if (p / "prompt.txt").exists())
    if not names:
        return found
    missing = [n for n in names if n not in found]
    if missing:
        sys.exit(f"シナリオが無い: {', '.join(missing)} (あるもの: {', '.join(found)})")
    return names


def harness_revision():
    root = Path.home() / ".claude" / "rules"
    repo = root.resolve()
    try:
        top = subprocess.run(["git", "-C", str(repo), "rev-parse", "--show-toplevel"],
                             capture_output=True, text=True, check=True).stdout.strip()
        rev = subprocess.run(["git", "-C", top, "rev-parse", "HEAD"],
                             capture_output=True, text=True, check=True).stdout.strip()
        dirty = subprocess.run(["git", "-C", top, "status", "--porcelain", "agents"],
                               capture_output=True, text=True, check=True).stdout.strip()
        return {"repo": top, "rev": rev, "agents_dirty": bool(dirty)}
    except (subprocess.CalledProcessError, FileNotFoundError):
        return {"repo": None, "rev": None, "agents_dirty": None}


def cmd_estimate(args):
    n = len(scenarios_of(args.topic, args.scenario)) * args.n
    lo, hi = COST_PER_RUN_USD
    print(f"実行回数: {n} 回 / 費用の目安: {lo * n}〜{hi * n} USD (1 回 {lo}〜{hi} USD)")


def run_one(topic, label, scenario, i, model):
    sdir = Path(topic) / "scenarios" / scenario
    rdir = Path(topic) / "results" / label / f"{scenario}-{i}"
    rdir.mkdir(parents=True)
    repo = rdir / "repo"
    prompt = (sdir / "prompt.txt").read_text().strip()
    meta = {"label": label, "scenario": scenario, "index": i, "model": model,
            "started": datetime.datetime.now().isoformat(timespec="seconds"),
            "harness": harness_revision(), "prompt": prompt, "exit": None}
    # check が途中で落ちた回も判定できるよう、実行前に書いておく
    (rdir / "meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2))
    setup = subprocess.run(["bash", str(sdir / "setup.sh"), str(repo)],
                           stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    if setup.returncode != 0:
        return rdir.name, f"setup.sh が失敗: {setup.stderr.strip()[-200:]}"
    cmd = ["claude", "-p", prompt, "--model", model,
           "--settings", json.dumps(pinned_settings(model)),
           "--permission-mode", "bypassPermissions",
           "--output-format", "stream-json", "--verbose", "--no-session-persistence"]
    with open(rdir / "events.jsonl", "w") as out, open(rdir / "stderr.txt", "w") as err:
        proc = subprocess.run(cmd, cwd=repo, stdin=subprocess.DEVNULL, stdout=out, stderr=err,
                              env=child_env(os.environ))
    meta["exit"] = proc.returncode
    (rdir / "meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2))
    return rdir.name, proc.returncode


def cmd_run(args):
    ldir = Path(args.topic) / "results" / args.label
    if ldir.exists():
        sys.exit(f"ラベル {args.label} の結果が既にある。別のラベルを使う: {ldir}")
    jobs = [(s, i) for s in scenarios_of(args.topic, args.scenario) for i in range(1, args.n + 1)]
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.parallel) as pool:
        futs = [pool.submit(run_one, args.topic, args.label, s, i, args.model) for s, i in jobs]
        for f in concurrent.futures.as_completed(futs):
            name, code = f.result()
            print(f"{name} exit={code}", flush=True)


def cmd_check(args):
    ldir = Path(args.topic) / "results" / args.label
    validity = {}
    for rdir in sorted(p for p in ldir.iterdir() if p.is_dir()):
        if not (rdir / "meta.json").exists() or not (rdir / "events.jsonl").exists():
            validity[rdir.name] = {"valid": False, "reason": "meta.json か events.jsonl が無い",
                                   "model": None, "cost_usd": 0}
            print(f"{rdir.name:<24} INVALID meta.json か events.jsonl が無い")
            continue
        meta = json.loads((rdir / "meta.json").read_text())
        events = read_events(rdir / "events.jsonl")
        ok, reason = check_run(events, meta["model"], allowed_models(meta["model"]))
        cost = sum(r.get("total_cost_usd") or 0 for r in _results(events)[-1:])
        validity[rdir.name] = {"valid": ok, "reason": reason, "model": meta["model"],
                               "cost_usd": round(cost, 2)}
        (rdir / "final.txt").write_text(final_message(events))
        print(f"{rdir.name:<24} {'valid  ' if ok else 'INVALID'} {reason} (cost {cost:.2f} USD)")
    (ldir / "validity.json").write_text(json.dumps(validity, ensure_ascii=False, indent=2))
    n_ok = sum(v["valid"] for v in validity.values())
    print(f"有効 {n_ok} / {len(validity)} 回")


def build_grader_prompt(rubric, expected, samples):
    items = ", ".join(f'"{i}": 0〜{expected["max"]}' for i in expected["items"])
    fmt = ("\n\n## 出力\nツールは使わず、JSON だけを出力する (コードフェンス不要)。形式:\n"
           f'{{"<サンプル ID>": {{"has_decision": true, {items}, "why": "最も低い項目の理由 1 行"}}, ...}}\n'
           "判断を求める箇所が無いサンプルは has_decision を false にし、項目をすべて null にする。"
           "各サンプルは独立に評価し、サンプル間で情報を補わない。\n")
    body = "".join(f"\n===== サンプル {sid} 開始 =====\n{text}\n===== サンプル {sid} 終了 =====\n"
                   for sid, text in samples)
    return rubric + fmt + body


def cmd_grade(args):
    topic = Path(args.topic)
    expected = json.loads((topic / "expected.json").read_text())
    sources, texts, exec_models = [], {}, set()
    for label in args.labels:
        vpath = topic / "results" / label / "validity.json"
        if not vpath.exists():
            sys.exit(f"先に check を実行する: {label}")
        for run, v in json.loads(vpath.read_text()).items():
            if v["valid"]:
                src = f"{label}/{run}"
                sources.append(src)
                texts[src] = (topic / "results" / label / run / "final.txt").read_text()
                exec_models.add(v["model"])
    for name in expected["controls"]:
        src = f"control:{name}"
        sources.append(src)
        texts[src] = (topic / "controls" / f"{name}.txt").read_text()
    weaker = [m for m in exec_models if model_rank(m) > model_rank(args.model)]
    if weaker and not args.allow_weaker_grader:
        sys.exit(f"採点モデル {args.model} が実行モデル {', '.join(weaker)} より弱い。"
                 "--model で同格以上を指定する")
    seed = args.seed if args.seed is not None else random.randrange(1 << 30)
    key = blind_assign(sources, seed)
    gdir = topic / "grades" / datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    gdir.mkdir(parents=True)
    (gdir / "key.json").write_text(json.dumps({"seed": seed, "labels": args.labels,
                                               "grader": args.model, "key": key},
                                              ensure_ascii=False, indent=2))
    prompt = build_grader_prompt((topic / "rubric.md").read_text(), expected,
                                 [(sid, texts[src]) for sid, src in sorted(key.items())])
    (gdir / "prompt.txt").write_text(prompt)
    proc = subprocess.run(
        ["claude", "-p", prompt, "--model", args.model,
         "--settings", json.dumps(pinned_settings(args.model)),
         "--permission-mode", "dontAsk", "--output-format", "json", "--no-session-persistence"],
        cwd=gdir, stdin=subprocess.DEVNULL, capture_output=True, text=True,
        env=child_env(os.environ))
    (gdir / "raw.json").write_text(proc.stdout)
    try:
        scores, models = parse_grader_output(proc.stdout)
    except ValueError as e:
        detail = f"{e}\n終了コード {proc.returncode} / stderr: {proc.stderr.strip()[-300:]}"
        (gdir / "INVALID.txt").write_text(detail + "\n")
        print("採点は無効:\n" + detail)
        sys.exit(2)
    (gdir / "scores.json").write_text(json.dumps(scores, ensure_ascii=False, indent=2))
    errors = []
    if models != [args.model]:
        errors.append(f"採点モデルが想定と違う: {models}")
    missing = sorted(set(key) - set(scores))
    if missing:
        errors.append(f"採点が無いサンプル: {', '.join(missing)}")
    errors += validate_controls(scores, key, expected)
    if errors:
        (gdir / "INVALID.txt").write_text("\n".join(errors) + "\n")
        print("採点は無効:\n" + "\n".join(errors))
        sys.exit(2)
    rows = aggregate(scores, key, expected)
    report = render_report(rows, scores, key, expected, args.model)
    (gdir / "report.md").write_text(report)
    print(report)
    print(f"保存先: {gdir}")


def render_report(rows, scores, key, expected, grader):
    items = expected["items"]
    lines = [f"採点モデル: {grader} / 対照: 期待どおり / 満点は 1 回あたり "
             f"{expected['max'] * len(items)} 点", "",
             "| ラベル | シナリオ | 有効回数 | 全項目満点 | 平均点 | " +
             " | ".join(f"{i} 満点" for i in items) + " |",
             "| --- | --- | --- | --- | --- | " + " | ".join("---" for _ in items) + " |"]
    for r in rows:
        lines.append(f"| {r['label']} | {r['scenario']} | {r['runs']} | {r['full']} | {r['mean']} | " +
                     " | ".join(str(r["max_counts"][i]) for i in items) + " |")
    lines += ["", "回ごとの点と最も低い項目の理由:", ""]
    for sid, src in sorted(key.items(), key=lambda kv: kv[1]):
        if src.startswith("control:"):
            continue
        s = scores[sid]
        vals = " ".join(f"{i}={s.get(i)}" for i in items)
        lines.append(f"- {src}: {vals}. {s.get('why', '')}")
    return "\n".join(lines) + "\n"


def require_claude():
    if subprocess.run(["sh", "-c", "command -v claude"], capture_output=True).returncode != 0:
        sys.exit("claude コマンドが見つからない。Claude Code の CLI を PATH に入れる")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    for name in ("estimate", "run"):
        s = sub.add_parser(name)
        s.add_argument("--topic", required=True)
        s.add_argument("--scenario", action="append", help="省略時は全シナリオ")
        s.add_argument("--n", type=int, default=3)
        if name == "run":
            s.add_argument("--label", required=True)
            s.add_argument("--model", default=DEFAULT_MODEL)
            s.add_argument("--parallel", type=int, default=3)
    s = sub.add_parser("check")
    s.add_argument("--topic", required=True)
    s.add_argument("--label", required=True)
    s = sub.add_parser("grade")
    s.add_argument("--topic", required=True)
    s.add_argument("--labels", nargs="+", required=True)
    s.add_argument("--model", default=DEFAULT_MODEL)
    s.add_argument("--seed", type=int)
    s.add_argument("--allow-weaker-grader", action="store_true")
    args = p.parse_args()
    if args.cmd in ("run", "grade"):
        require_claude()
    {"estimate": cmd_estimate, "run": cmd_run, "check": cmd_check, "grade": cmd_grade}[args.cmd](args)


if __name__ == "__main__":
    main()
