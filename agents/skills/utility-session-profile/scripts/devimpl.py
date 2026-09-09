#!/usr/bin/env python3
"""dev-impl の run から、issue ごとのフェーズ内訳とレビュー収束を集計する (層 B)。

一次ソースは collect.py が拾った Agent 呼び出しの契約キー
(mode / issue_number / report_path / findings_path) と、対応する subagent の span。
オーケストレータが打刻ファイルを残すかどうかは dev-impl の契約ではないので、
そこには依存しない。timing.tsv があれば merge のように subagent を spawn しない
イベントの補完にだけ使う。

使い方:
    devimpl.py --data data.json -o ext.json
"""
import argparse
import collections
import datetime
import glob
import json
import os
import re
import subprocess
import sys

# フェーズの並びは、実際に現れたラウンド数から組む。dev-impl のレビューは r1 と r2 の
# 最大 2 回だが、上限を守らせる機械ゲートは無く、実測で r4 まで入った run がある。固定の
# 一覧にすると超過分が図からも合計からも黙って消え、超過そのものが見えなくなる。
def phase_order(max_round):
    keys = ["impl"]
    for k in range(1, max(max_round, 1) + 1):
        keys += [f"r{k}", f"fix{k}"]
    return keys + ["tail", "wait"]


def phase_label(key):
    if key == "impl":
        return "実装"
    if key.startswith("r"):
        return f"レビュー r{key[1:]}"
    if key.startswith("fix"):
        return f"修正 {key[3:]}"
    return {"tail": "テスト・コミット", "wait": "merge 待ち"}[key]


# 色は活動の種類だけを表す。ラウンド番号はバーのラベルが持つので、色の濃淡には持たせない
# (薄い色に落とすと彩度が下がり、配色の検証を通らなくなる)。凡例はこの単位で畳む。
def phase_family(key):
    if key.startswith("r") and key != "impl":
        return "レビュー"
    if key.startswith("fix"):
        return "修正"
    return phase_label(key)


def parse_time(value):
    return datetime.datetime.fromisoformat(re.sub(r"\.\d+Z$", "Z", value).replace("Z", "+00:00"))


def round_of(path):
    """review-<N>-r<K>.json から K を取る。取れなければ None。"""
    if not path:
        return None
    found = re.search(r"-r(\d+)\.json$", path)
    return int(found.group(1)) if found else None


def phase_of(spawn):
    """1 つの Agent 呼び出しが、どの issue のどのフェーズかを決める。

    契約キーを優先し、無いものだけエージェント名で補う。名前はオーケストレータが
    自由に付けられるので契約ではなく、あくまでフォールバック。
    """
    contract = spawn.get("contract") or {}
    issue = contract.get("issue_number")
    name = spawn.get("name") or ""
    if not issue:
        found = re.search(r"\b(\d{2,})\b", name)
        issue = found.group(1) if found else None
    if not issue:
        return None, None

    mode = contract.get("mode")
    if mode == "implement":
        return issue, "impl"
    if mode == "fix":
        # fix が直すのは「渡された findings のラウンド」。r1 の指摘を直すのが fix1。
        k = round_of(contract.get("findings_path")) or round_of(contract.get("report_path"))
        if k is None:
            found = re.search(r"-r(\d+)$", name)
            k = int(found.group(1)) if found else 1
        return issue, f"fix{k}"
    if spawn.get("subagent_type") == "review-impl" or contract.get("focus"):
        k = round_of(contract.get("report_path"))
        if k is None:
            found = re.search(r"-r(\d+)$", name)
            k = int(found.group(1)) if found else 1
        return issue, f"r{k}"
    # 実装でもレビューでも修正でもないが issue が特定できている spawn は、テスト実行や
    # コミットの代行。dev-impl はこれらのエージェント名を契約で決めていないので、
    # まず「契約キーで他のフェーズに当たらなかったこと」で判別し、契約キーすら無い
    # spawn だけを名前で補う (下の re.match)。名前は run ごとに変わるので後段に置く。
    if contract.get("issue_number"):
        return issue, "tail"
    if re.match(r"^(commit|dod|verify|test|full-?test)", name):
        return issue, "tail"
    return None, None


def load_findings(scratch_dir):
    """対象 run の SCRATCH にある review-<N>-r<K>.json から findings を集計する。

    無ければ空を返す。レビュー収束の節はこれが空なら描かない。
    """
    rounds, findings = [], []
    if not scratch_dir or not os.path.isdir(scratch_dir):
        return rounds, findings
    for path in sorted(glob.glob(os.path.join(scratch_dir, "review-*.json"))):
        stem = os.path.basename(path)[len("review-"):-len(".json")]
        if "-r" not in stem:
            continue
        issue, round_no = stem.rsplit("-r", 1)
        try:
            doc = json.load(open(path))
        except (json.JSONDecodeError, OSError):
            continue
        items = doc.get("findings") or []
        severities = collections.Counter(item.get("severity") for item in items)
        checked = doc.get("checked") or {}
        rounds.append({
            "issue": issue,
            "round": int(round_no) if round_no.isdigit() else 0,
            "high": severities.get("high", 0),
            "medium": severities.get("medium", 0),
            "low": severities.get("low", 0),
            "e2e": (checked.get("e2e") or "")[:30],
            "previous": checked.get("previous_findings"),
            "files": sorted({item.get("file") for item in items if item.get("file")}),
        })
        for item in items:
            findings.append({
                "issue": issue,
                "round": int(round_no) if round_no.isdigit() else 0,
                "severity": item.get("severity"),
                "category": item.get("category"),
                "file": item.get("file"),
                "summary": (item.get("summary") or "")[:200],
                "recurrence_of": item.get("recurrence_of"),
            })
    rounds.sort(key=lambda r: (int(r["issue"]) if r["issue"].isdigit() else 0, r["round"]))
    return rounds, findings


def load_timing(scratch_dir):
    """打刻ファイルがあれば読む。merge / PR など subagent を伴わない事象の補完に使う。"""
    if not scratch_dir:
        return {}
    path = os.path.join(scratch_dir, "timing.tsv")
    if not os.path.isfile(path):
        return {}
    events = collections.defaultdict(list)
    for line in open(path, errors="replace"):
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 3:
            continue
        try:
            events[parts[1]].append((parse_time(parts[0]), parts[2]))
        except ValueError:
            continue
    return {issue: sorted(items) for issue, items in events.items()}


def issue_dependencies(cwd, issues):
    """GitHub の issue 本文から `Depends on #N` を読み、依存レベルを求める。

    対象は「着手した issue」だけでなく、そこから依存関係で連結している issue 全体。
    未着手の後続まで含めないと、残りに何段あるかが見えず、段数がボトルネックだという
    判断ができない。連結成分に限るので、無関係な過去 issue は引き込まない。

    gh が無い・未認証・ネットワークが無い環境では空を返し、依存段の節を落とす。
    """
    if not cwd or not os.path.isdir(cwd) or not issues:
        return {}, {}, {}
    try:
        slug = subprocess.run(["gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"],
                              capture_output=True, text=True, timeout=30, cwd=cwd)
        if slug.returncode != 0 or not slug.stdout.strip():
            return {}, {}, {}
        repo = slug.stdout.strip()
        # 上限は 1 リポジトリの issue 数として十分に大きい値。到達したら依存グラフが
        # 欠けたまま段数が出るので、黙って切らずに警告する。
        limit = 1000
        listed = subprocess.run(
            ["gh", "issue", "list", "--repo", repo, "--state", "all", "--limit", str(limit),
             "--json", "number,title,state,body,labels"],
            capture_output=True, text=True, timeout=120, cwd=cwd)
        if listed.returncode != 0:
            return {}, {}, {}
        rows = json.loads(listed.stdout)
        if len(rows) >= limit:
            print(f"警告: issue を {limit} 件で打ち切った。依存グラフが欠けている可能性がある",
                  file=sys.stderr)
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError):
        return {}, {}, {}

    all_deps, all_meta = {}, {}
    for row in rows:
        number = row["number"]
        all_deps[number] = sorted({int(n) for n in re.findall(r"Depends on #(\d+)", row.get("body") or "")})
        all_meta[number] = {"title": row["title"], "state": row["state"],
                            "labels": [label["name"] for label in row.get("labels", [])]}

    # 着手した issue から、依存の両方向へ辿って連結成分を作る。
    reverse = collections.defaultdict(set)
    for node, parents in all_deps.items():
        for parent in parents:
            reverse[parent].add(node)
    seed = [int(i) for i in issues if str(i).isdigit() and int(i) in all_deps]
    seen, queue = set(seed), list(seed)
    while queue:
        node = queue.pop()
        for neighbor in list(all_deps.get(node, [])) + list(reverse.get(node, [])):
            if neighbor in all_deps and neighbor not in seen:
                seen.add(neighbor)
                queue.append(neighbor)

    deps = {n: [d for d in all_deps[n] if d in seen] for n in seen}
    meta = {n: all_meta[n] for n in seen}

    level, visiting = {}, set()
    def depth(node):
        if node in level:
            return level[node]
        if node in visiting:  # 依存の循環。0 に倒して段の計算を続ける
            return 0
        visiting.add(node)
        parents = [d for d in deps.get(node, []) if d in deps]
        level[node] = 0 if not parents else 1 + max(depth(p) for p in parents)
        visiting.discard(node)
        return level[node]
    for node in deps:
        depth(node)
    return deps, level, meta


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--data", required=True, help="collect.py が出した data.json")
    parser.add_argument("-o", "--out", default="ext.json", help="出力先 (既定 ext.json)")
    parser.add_argument("--no-github", action="store_true", help="依存グラフの取得を行わない")
    parser.add_argument("--scratch", help="対象 run の SCRATCH を明示指定する (自動検出を上書き)")
    parser.add_argument("--no-timing", action="store_true",
                        help="打刻ファイル (timing.tsv) を無視する。契約キーだけで復元できることの確認に使う")
    args = parser.parse_args()

    data = json.load(open(args.data))
    detection = data.get("devimpl") or {}
    if not detection.get("detected"):
        sys.exit("dev-impl の run ではない (Agent 呼び出しに mode / issue_number が無い)")

    scratch = args.scratch or detection.get("scratch_dir")
    agents_by_name = {a["name"]: a for a in data.get("agents", [])}
    # 名前を付けずに spawn された agent は name で引けないので、tool_use の id でも引けるようにする。
    agents_by_use = {a["tool_use_id"]: a for a in data.get("agents", []) if a.get("tool_use_id")}
    session_start = parse_time(data["start"])

    # spawn の契約からフェーズを決め、対応する subagent の span を所要時間にする。
    phases = collections.defaultdict(dict)
    unmatched = []
    unphased = []
    for spawn in data.get("spawns", []):
        issue, phase = phase_of(spawn)
        agent = agents_by_name.get(spawn.get("name")) or agents_by_use.get(spawn.get("tool_use_id"))
        if not issue or not phase:
            # 契約キーが無く、どのフェーズにも寄せられない spawn (merge 競合の解消・
            # 事前調査など)。黙って捨てるとフェーズ合計から時間が消えるので、名前と
            # 分数を残して読み手が差を説明できるようにする。
            if agent:
                span = (parse_time(agent["end"]) - parse_time(agent["start"])).total_seconds() / 60
                unphased.append({"name": spawn.get("name"), "min": round(span, 1)})
            continue
        if not agent:
            unmatched.append(spawn.get("name"))
            continue
        start, end = parse_time(agent["start"]), parse_time(agent["end"])
        minutes = (end - start).total_seconds() / 60
        offset = (start - session_start).total_seconds() / 60
        end_offset = (end - session_start).total_seconds() / 60
        existing = phases[issue].get(phase)
        if existing:
            # 同じ issue の同じフェーズに複数のエージェントが並ぶことがある。テストと
            # コミットは常に複数 (コミット・DoD 実行・rebase 後検証) で、実装やレビューでも
            # やり直しで 2 本目が出る。上書きすると 1 本目の時間が黙って消える。
            # 時間の合計 (min) と、時間軸上の位置 (offset_min / end_min) は別物として持つ。
            # エージェントの間に親の判断時間が挟まると、合計は実際の占有幅より短くなる。
            existing["min"] = round(existing["min"] + minutes, 1)
            existing["offset_min"] = min(existing["offset_min"], round(offset, 1))
            existing["end_min"] = max(existing["end_min"], round(end_offset, 1))
            existing["agent"] += f", {agent['name']}"
        else:
            phases[issue][phase] = {
                "min": round(minutes, 1),
                "offset_min": round(offset, 1),
                "end_min": round(end_offset, 1),
                "agent": agent["name"],
            }

    timing = {} if args.no_timing else load_timing(scratch)
    for issue, events in timing.items():
        # merge の成立で尾は終わり。complete (issue の close やコメント) はその後の
        # 後片付けなので、merged が無いときの代替に留める。
        ends = [t for t, name in events if name == "merged"] or \
               [t for t, name in events if name == "complete"]
        if not ends:
            continue
        # tail (代行エージェントの実行時間) は打刻の有無によらず span から出す。打刻は
        # 「代行が終わってから merge が成立するまでの待ち」を足すためだけに使う。
        # 打刻で tail を置き換えると、打刻の有無で tail の意味が変わってしまう。
        tail = phases[issue].get("tail")
        tail_end_min = tail["end_min"] if tail else None
        if tail_end_min is None:
            continue
        wait_min = (ends[-1] - session_start).total_seconds() / 60 - tail_end_min
        if wait_min > 0:
            phases[issue]["wait"] = {
                "min": round(wait_min, 1),
                "offset_min": round(tail_end_min, 1),
                "end_min": round(tail_end_min + wait_min, 1),
                "agent": "timing.tsv (merge 成立まで)",
            }

    # 実際に現れた最大ラウンドで並びを決める。上限超過が図から消えないようにする。
    seen_rounds = [int(m.group(1)) for keys in phases.values() for k in keys
                   if (m := re.match(r"^(?:r|fix)(\d+)$", k))]
    order = phase_order(max(seen_rounds) if seen_rounds else 2)

    issues = []
    for issue in sorted(phases, key=lambda x: int(x) if str(x).isdigit() else 0):
        bars = [{"k": key, "x": phases[issue][key]["offset_min"],
                 "w": round(phases[issue][key]["end_min"] - phases[issue][key]["offset_min"], 1),
                 "m": phases[issue][key]["min"]}
                for key in order if key in phases[issue]]
        if not bars:
            continue
        first_start = min(b["x"] for b in bars)
        last_end = max(b["x"] + b["w"] for b in bars)
        events = timing.get(issue, [])
        merged = [t for t, name in events if name in ("merged", "complete")]
        issues.append({
            "issue": int(issue) if str(issue).isdigit() else issue,
            "bars": bars,
            "phases": {k: phases[issue][k]["min"] for k in phases[issue]},
            "cycle_min": round(last_end - first_start, 1),
            "done": bool(merged) or "tail" in phases[issue],
        })

    phase_totals = collections.Counter()
    for entry in issues:
        for key, minutes in entry["phases"].items():
            phase_totals[key] += minutes

    rounds, findings = load_findings(scratch)
    by_issue_round = {(r["issue"], r["round"]): r for r in rounds}
    for entry in rounds:
        first = by_issue_round.get((entry["issue"], 1))
        entry["repeat_files"] = (sum(1 for f in entry["files"] if first and f in first["files"])
                                 if entry["round"] > 1 else None)

    severity_categories = collections.Counter((f["severity"], f["category"]) for f in findings)
    late_high = [f for f in findings if f["severity"] == "high" and f["round"] > 1]

    issue_numbers = [str(e["issue"]) for e in issues]
    if args.no_github:
        deps, level, meta = {}, {}, {}
    else:
        deps, level, meta = issue_dependencies(data.get("cwd"), issue_numbers)

    levels = collections.defaultdict(list)
    for node, lv in sorted(level.items()):
        levels[lv].append(node)
    cycles = {e["issue"]: e["cycle_min"] for e in issues}
    critical = []
    for lv, members in sorted(levels.items()):
        measured = [cycles[n] for n in members if n in cycles]
        critical.append({"level": lv, "issues": members,
                         "max_cycle": round(max(measured), 1) if measured else 0,
                         "measured": len(measured), "total": len(members)})
    # 1 件でも実測できた段は合計に入れる。全件完了した段だけに絞ると、進行中の段が
    # 落ちて合計が実測経過と合わなくなる。
    critical_sum = round(sum(c["max_cycle"] for c in critical if c["max_cycle"] > 0), 1)

    ext = {
        "scratch_dir": scratch,
        "phase_order": [k for k in order if phase_totals.get(k)],
        "phase_labels": {k: phase_label(k) for k in order},
        "phase_families": {k: phase_family(k) for k in order},
        "phase_totals": {k: round(v, 1) for k, v in phase_totals.items()},
        "issues": issues,
        "rounds": rounds,
        "findings_n": len(findings),
        "sev_cat": [{"severity": s, "category": c, "n": n}
                    for (s, c), n in severity_categories.most_common()],
        "late_high": late_high,
        "levels": {str(k): v for k, v in sorted(levels.items())},
        "deps": {str(k): v for k, v in deps.items()},
        "issue_meta": {str(k): v for k, v in meta.items()},
        "critical": critical,
        "critical_sum": critical_sum,
        "unmatched_spawns": unmatched,
        "unphased_spawns": sorted(unphased, key=lambda x: -x["min"]),
        "unphased_min": round(sum(x["min"] for x in unphased), 1),
        "timing_used": bool(timing),
    }
    with open(args.out, "w") as handle:
        json.dump(ext, handle, ensure_ascii=False, indent=1)

    print(f"wrote {args.out}")
    print(f"  scratch   {scratch} (findings {len(findings)} 件 / review {len(rounds)} 周)")
    print(f"  issues    {len(issues)} 件  phase_totals={dict(ext['phase_totals'])}")
    print(f"  合計      {round(sum(phase_totals.values()), 1)} min  "
          f"(実測経過 {data['elapsed_min']} min)")
    if critical:
        print(f"  依存段    {len(critical)} 段  クリティカルパス {critical_sum} min")
    else:
        print("  依存段    取得できず (gh が無い / 未認証 / issue 本文に Depends on が無い)")
    print(f"  timing.tsv {'併用' if timing else '無し (契約キーのみで復元)'}")
    if unphased:
        names = ", ".join(x["name"] for x in ext["unphased_spawns"][:5])
        print(f"  フェーズ外 {len(unphased)} 本 {ext['unphased_min']} min  "
              f"(契約キーが無く合計に入らない: {names}{' ほか' if len(unphased) > 5 else ''})")
    if unmatched:
        print(f"  span 無し  {len(unmatched)} 本 (spawn はあるが subagent のログが無い)")
    if unmatched:
        print(f"  注意      subagent ログに対応が無い spawn {len(unmatched)} 件: {unmatched[:5]}")


if __name__ == "__main__":
    main()
