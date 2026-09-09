#!/usr/bin/env python3
"""セッションログから時間の内訳を集計する (層 A1 + A2)。

入力はセッションの JSONL 1 本。同じ場所に <session-id>/subagents/ があれば
subagent ごとの時間分解と並列度も出す (層 A2)。無ければその節は空になる。

出力 JSON の構造は references/log-format.md を参照。

使い方:
    collect.py <session.jsonl> -o data.json
    collect.py <session-id の先頭 8 文字> -o data.json   # 全プロジェクト横断で解決
"""
import argparse
import collections
import datetime
import glob
import json
import os
import re
import sys

PROJECTS = os.path.expanduser("~/.claude/projects")

# Bash コマンドの分類。上から順に最初に当たったものを採る (e2e は test より先)。
COMMAND_CATEGORIES = [
    ("e2e", re.compile(r"test:e2e|playwright")),
    ("mutation", re.compile(r"mutate-check|mutate[-_.]|mut-\w")),
    ("test", re.compile(r"\bvitest\b|\bpytest\b|\bjest\b|test:worker|\bgo test\b|cargo test|npm test|vp test")),
    ("check", re.compile(r"\blint\b|\bfmt\b|\btsc\b|type-?check|check:ui|vp check|\bruff\b|\beslint\b")),
    ("build", re.compile(r"\bbuild\b|\bcompile\b")),
    ("vcs", re.compile(r"(^|[\s;&|])(git|gh|jj)\s")),
    ("search", re.compile(r"(^|[\s;&|])(rg|grep|find|ls|fd)\s")),
]

# dev-impl が subagent の prompt に載せる契約キー (dev-impl スキルの SKILL.md が定める)。
CONTRACT_KEYS = ["mode", "repo_dir", "issue_number", "report_path", "findings_path", "base_sha", "focus"]


def parse_time(value):
    """Z 終端 (ログ) と +00:00 終端 (自前の isoformat) の両方を受ける。"""
    return datetime.datetime.fromisoformat(re.sub(r"\.\d+Z$", "Z", value).replace("Z", "+00:00"))


def parse_time_or_none(value):
    """ログ由来の時刻。読めなければ None を返す。

    1 行の書式違反でセッション全体の集計が落ちないようにする。ログの type も書式も
    増減するので、読めないものは黙って捨てて残りを数える。
    """
    try:
        return parse_time(value)
    except (ValueError, TypeError):
        return None


def read_jsonl(path):
    with open(path, errors="replace") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                continue  # 書き込み途中の行 (進行中セッション) は捨てる


def classify(tool_name, command):
    if tool_name != "Bash":
        return {"Read": "read", "Edit": "edit", "Write": "edit", "NotebookEdit": "edit"}.get(tool_name, "other")
    for name, pattern in COMMAND_CATEGORIES:
        if pattern.search(command):
            return name
    return "other"


def walk_records(records):
    """1 本のログから、ツール呼び出し・モデル待ち時間・トークンを取り出す。

    モデル待ちは「tool_result を受けてから次の assistant レコードが出るまで」の合計。
    ツール時間を個別に足し上げると、同一ターンで並列に走った呼び出しを二重に数えて
    wall を超えてしまうため、ツール時間は wall - model の引き算で出す。
    """
    uses, results = {}, {}
    model_seconds, turns, out_tokens, context_sum = 0.0, 0, 0, 0
    latencies, models = [], collections.Counter()
    context_series = []
    pending_user_ts = None
    # 1 つのモデル応答が text と tool_use で複数レコードに分かれ、どれも同じ
    # message.id と同じ usage を持つ。レコードを数えるとターン数もトークン数も
    # ブロック数ぶん膨らむので、message.id の初出だけを数える。
    counted_messages = set()

    for record in records:
        if not record.get("timestamp"):
            continue
        ts = parse_time_or_none(record["timestamp"])
        if ts is None:
            continue
        message = record.get("message") or {}
        content = message.get("content")

        if record.get("type") == "assistant":
            if pending_user_ts is not None:
                gap = (ts - pending_user_ts).total_seconds()
                model_seconds += gap
                latencies.append(gap)
                pending_user_ts = None
            usage = message.get("usage") or {}
            message_id = message.get("id")
            first_block = message_id is None or message_id not in counted_messages
            if message_id is not None:
                counted_messages.add(message_id)
            if first_block:
                turns += 1
                out_tokens += usage.get("output_tokens", 0)
                context = usage.get("input_tokens", 0) + usage.get("cache_read_input_tokens", 0)
                context_sum += context
                context_series.append({"t": ts.isoformat(), "ctx": context})
                if message.get("model"):
                    models[message["model"]] += 1
            if isinstance(content, list):
                for block in content:
                    if block.get("type") == "tool_use":
                        command = (block.get("input") or {}).get("command", "") or ""
                        uses[block["id"]] = (ts, block.get("name", ""), command, block.get("input") or {})
        elif record.get("type") == "user":
            pending_user_ts = ts
            if isinstance(content, list):
                for block in content:
                    if block.get("type") == "tool_result":
                        results[block.get("tool_use_id")] = ts

    seconds_by_cat, calls_by_cat, longest = collections.Counter(), collections.Counter(), []
    for use_id, (ts, name, command, _) in uses.items():
        category = classify(name, command)
        calls_by_cat[category] += 1
        if use_id in results:
            seconds = (results[use_id] - ts).total_seconds()
            seconds_by_cat[category] += seconds
            longest.append({"sec": round(seconds, 1), "tool": name,
                            "cmd": re.sub(r"\s+", " ", command or "")[:160]})
    longest.sort(key=lambda item: -item["sec"])

    latencies.sort()
    return {
        "uses": uses,
        "turns": turns,
        "model_seconds": model_seconds,
        "out_tokens": out_tokens,
        "context_avg": round(context_sum / turns) if turns else 0,
        "context_series": context_series,
        "seconds_by_cat": {k: round(v, 1) for k, v in seconds_by_cat.items()},
        "calls_by_cat": dict(calls_by_cat),
        "longest": longest,
        "latency_p50": round(latencies[len(latencies) // 2], 1) if latencies else 0,
        "latency_max": round(latencies[-1], 1) if latencies else 0,
        "models": dict(models),
    }


def collect_agents(subagent_dir):
    """subagents/ の各ログを 1 本ずつ分解する。無ければ空リストを返す。"""
    agents = []
    for meta_path in sorted(glob.glob(os.path.join(subagent_dir, "*.meta.json"))):
        log_path = meta_path[: -len(".meta.json")] + ".jsonl"
        if not os.path.exists(log_path):
            continue
        try:
            with open(meta_path) as handle:
                meta = json.load(handle)
        except (json.JSONDecodeError, OSError):
            # 読めない .meta.json は、その 1 本を落として残りを集計する。
            continue
        records = list(read_jsonl(log_path))
        stamped = [r for r in records if r.get("timestamp")]
        if not stamped:
            continue
        times = [t for t in (parse_time_or_none(r["timestamp"]) for r in stamped) if t]
        if not times:
            continue
        start, end = min(times), max(times)
        walked = walk_records(records)
        wall = (end - start).total_seconds()
        name = agent_name(meta, meta_path)
        agents.append({
            "name": name,
            # 種別は agentType から取る。名前付き spawn では "impl-104" のように対象まで
            # 入るので数字以降を落とし、名前なし spawn では "general-purpose" がそのまま残る。
            "kind": agent_kind(meta.get("agentType") or name),
            "requested_model": meta.get("model"),
            "agent_type": meta.get("customAgentType") or meta.get("agentType"),
            "tool_use_id": meta.get("toolUseId"),
            "description": meta.get("description"),
            "start": start.isoformat(),
            "end": end.isoformat(),
            "wall_s": round(wall, 1),
            "model_s": round(walked["model_seconds"], 1),
            "tool_s": round(max(wall - walked["model_seconds"], 0), 1),
            "turns": walked["turns"],
            "out_tokens": walked["out_tokens"],
            "ctx_avg": walked["context_avg"],
            "tool_seconds_by_cat": walked["seconds_by_cat"],
            "tool_calls_by_cat": walked["calls_by_cat"],
            "models": walked["models"],
            "longest_calls": walked["longest"][:3],
        })
    return agents


def agent_name(meta, meta_path):
    """エージェントの表示名を決める。

    name を付けずに spawn された agent (meta に name が無い) では description を使い、
    それも無ければファイル名の識別子に落とす。ファイル名は名前付きなら
    agent-a<name>-<16 桁 hex>.meta.json、名前なしなら agent-a<hex>.meta.json。
    """
    if meta.get("name"):
        return meta["name"]
    if meta.get("description"):
        text = re.sub(r"\s+", " ", meta["description"]).strip()
        return text[:28] + ("…" if len(text) > 28 else "")
    base = os.path.basename(meta_path)[: -len(".meta.json")]
    named = re.match(r"^agent-a(.+)-[0-9a-f]{16}$", base)
    return named.group(1) if named else base


def agent_kind(name):
    """エージェント名から種別を取り出す (impl-104 → impl、review-104-r1 → review)。

    dev-impl に限らず「<種別>-<対象>-<ラウンド>」の命名が多いので、最初に現れる
    数字以降を落とす。数字を含まない名前はそのまま種別として扱う。
    """
    return re.sub(r"[-_]\d.*$", "", name)


def concurrency(workers):
    """1 分刻みで、同時に走っていたエージェントの本数を数える。

    刻みを 1 分にしたのは、エージェントの寿命が分オーダー (数分〜数十分) で、
    秒刻みにしても形が変わらないまま系列だけが 60 倍になるため。
    """
    spans = [(parse_time(a["start"]), parse_time(a["end"])) for a in workers]
    if not spans:
        return {"hist": {}, "avg": 0, "series": [], "window_min": 0}
    low = min(s for s, _ in spans)
    high = max(e for _, e in spans)
    histogram, series = collections.Counter(), []
    cursor = low
    while cursor <= high:
        count = sum(1 for s, e in spans if s <= cursor < e)
        histogram[count] += 1
        series.append({"t": cursor.isoformat(), "n": count})
        cursor += datetime.timedelta(minutes=1)
    window = (high - low).total_seconds() / 60
    busy = sum(level * minutes for level, minutes in histogram.items())
    return {"hist": {str(k): v for k, v in sorted(histogram.items())},
            "avg": round(busy / window, 2) if window else 0,
            "series": series,
            "window_min": round(window, 1)}


def extract_spawns(uses):
    """メインループの Agent 呼び出しを、prompt の契約キーごと取り出す。

    dev-impl は subagent の prompt に mode / issue_number / report_path を載せる契約なので、
    ここから層 B のフェーズ構造がそのまま復元できる。打刻ファイルには依存しない。
    """
    spawns = []
    for use_id, (ts, name, _, tool_input) in sorted(uses.items(), key=lambda item: item[1][0]):
        if name != "Agent":
            continue
        prompt = tool_input.get("prompt") or ""
        keys = {}
        for key in CONTRACT_KEYS:
            found = re.search(rf"^{key}:\s*(\S+)", prompt, re.M)
            if found:
                keys[key] = found.group(1)
        spawns.append({
            "t": ts.isoformat(),
            "tool_use_id": use_id,
            "name": tool_input.get("name"),
            "model": tool_input.get("model"),
            "subagent_type": tool_input.get("subagent_type"),
            "description": tool_input.get("description"),
            "contract": keys,
        })
    return spawns


def detect_devimpl(spawns):
    """dev-impl の run かどうかを、契約キーの同居で判定する。

    report_path の dirname が対象 run の SCRATCH。複数出たら最頻のものを採る
    (再開 run では前回の SCRATCH が混ざることがある)。
    """
    issues, dirs = set(), collections.Counter()
    for spawn in spawns:
        contract = spawn["contract"]
        path = contract.get("report_path") or contract.get("findings_path")
        if path:
            dirs[os.path.dirname(path)] += 1
        if contract.get("issue_number"):
            issues.add(contract["issue_number"])
    has_phases = any(s["contract"].get("mode") and s["contract"].get("issue_number") for s in spawns)
    scratch = dirs.most_common(1)[0][0] if dirs else None
    return {
        "detected": bool(has_phases and issues),
        "scratch_dir": scratch,
        "scratch_exists": bool(scratch and os.path.isdir(scratch)),
        "issues": sorted(issues, key=lambda x: int(x) if x.isdigit() else 0),
        "candidates": [{"dir": d, "n": n} for d, n in dirs.most_common(5)],
    }


def resolve_session(argument):
    """JSONL のパス、またはセッション ID の先頭一致を全プロジェクト横断で解決する。"""
    if os.path.isfile(argument):
        return [argument]
    matches = sorted(glob.glob(os.path.join(PROJECTS, "*", f"{argument}*.jsonl")))
    return matches


def project_dir_name(cwd):
    """セッションの cwd から ~/.claude/projects 配下のディレクトリ名を作る。

    区切りの / だけでなく、英数以外はすべてハイフンになる。`github.com` のドットを
    残すと実在しない名前になり、対象プロジェクトが見つからず全件一覧に落ちる。
    実在する 70 ディレクトリすべてが英数とハイフンだけで構成されていることを確認済み。
    """
    return re.sub(r"[^A-Za-z0-9]", "-", cwd)


def list_sessions(cwd, limit):
    """最近のセッションを新しい順に出す。

    シェルの ls に頼らないのは、対話シェルで別コマンドに割り当てられていたり、
    -t / -S や date -r の挙動が OS で違ったりして、環境ごとに壊れるため。
    """
    project = os.path.join(PROJECTS, project_dir_name(cwd)) if cwd else None
    scope = [project] if project and os.path.isdir(project) else sorted(
        d for d in glob.glob(os.path.join(PROJECTS, "*")) if os.path.isdir(d))
    if project and not os.path.isdir(project):
        print(f"(このディレクトリに対応するプロジェクトが無い。全プロジェクトから出す)", file=sys.stderr)

    rows = []
    for directory in scope:
        for path in glob.glob(os.path.join(directory, "*.jsonl")):
            session_id = os.path.basename(path)[: -len(".jsonl")]
            subagents = glob.glob(os.path.join(directory, session_id, "subagents", "*.jsonl"))
            rows.append({
                "path": path,
                "id": session_id,
                "project": os.path.basename(directory),
                "mtime": os.path.getmtime(path),
                "size_kb": os.path.getsize(path) // 1024,
                "subagents": len(subagents),
            })
    rows.sort(key=lambda r: -r["mtime"])
    for row in rows[:limit]:
        when = datetime.datetime.fromtimestamp(row["mtime"]).strftime("%m/%d %H:%M")
        print(f"{row['id'][:8]}  {when}  {row['size_kb']:>7,} KB  subagents={row['subagents']:<4}"
              f"{row['project'][:44]}")
    if not rows:
        print("セッションが見つからない", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("session", nargs="?",
                        help="セッション JSONL のパス、またはセッション ID の先頭")
    parser.add_argument("-o", "--out", default="data.json", help="出力先 (既定 data.json)")
    parser.add_argument("--list", action="store_true",
                        help="最近のセッションを新しい順に出して終わる")
    parser.add_argument("--cwd", default=os.getcwd(),
                        help="--list のとき、どの cwd のセッションを出すか")
    parser.add_argument("--limit", type=int, default=10, help="--list の表示件数")
    args = parser.parse_args()

    if args.list:
        list_sessions(args.cwd, args.limit)
        return
    if not args.session:
        parser.error("セッションを指定する (一覧は --list)")

    matches = resolve_session(args.session)
    if not matches:
        sys.exit(f"セッションが見つからない: {args.session}")
    if len(matches) > 1:
        print("複数一致した。1 つに絞って指定する:", file=sys.stderr)
        for path in matches:
            print(f"  {path}", file=sys.stderr)
        sys.exit(2)
    main_path = matches[0]

    session_id = os.path.basename(main_path)[: -len(".jsonl")]
    session_dir = main_path[: -len(".jsonl")]
    project = os.path.basename(os.path.dirname(main_path))

    records = list(read_jsonl(main_path))
    stamped = [r for r in records if r.get("timestamp")]
    if not stamped:
        sys.exit(f"タイムスタンプを持つレコードが無い: {main_path}")
    times = [t for t in (parse_time_or_none(r["timestamp"]) for r in stamped) if t]
    if not times:
        sys.exit(f"読める時刻を持つレコードが 1 件も無い: {path}")
    first, last = min(times), max(times)
    cwd = next((r.get("cwd") for r in records if r.get("cwd")), None)
    version = next((r.get("version") for r in records if r.get("version")), None)

    walked = walk_records(records)
    spawns = extract_spawns(walked["uses"])
    agents = collect_agents(os.path.join(session_dir, "subagents"))

    # 並列度は「働いているエージェント」だけを数える。実行だけを代行する短命な
    # エージェント (テスト実行・コミット) を混ぜると、山が実態より高く見える。
    # 判別は名前ではなく要求モデルで行う。orchestration.md が機械実行を haiku へ
    # 委譲すると定めているためで、エージェント名は run ごとに変わりうる。
    # 除外は種別ではなくエージェント 1 本ずつで判定する。同じ種別を haiku と opus の
    # 両方で spawn した run では、種別で括ると働いている側まで一緒に落ちる。
    workers = [a for a in agents if a.get("requested_model") != "haiku"]
    conc = concurrency(workers) if workers else {"hist": {}, "avg": 0, "series": [], "window_min": 0}

    totals = {}
    for kind in sorted({a["kind"] for a in agents}):
        members = [a for a in agents if a["kind"] == kind]
        totals[kind] = {
            "n": len(members),
            "wall_min": round(sum(a["wall_s"] for a in members) / 60, 1),
            "model_min": round(sum(a["model_s"] for a in members) / 60, 1),
            "tool_min": round(sum(a["tool_s"] for a in members) / 60, 1),
            "turns": sum(a["turns"] for a in members),
        }

    command_totals = collections.Counter()
    command_by_kind = collections.defaultdict(collections.Counter)
    for category, count in walked["calls_by_cat"].items():
        command_totals[category] += count
        command_by_kind[category]["main"] += count
    for agent in agents:
        for category, count in agent["tool_calls_by_cat"].items():
            command_totals[category] += count
            command_by_kind[category][agent["kind"]] += count

    data = {
        "snapshot": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "session": session_id,
        "project": project,
        "cwd": cwd,
        "version": version,
        "start": first.isoformat(),
        "last": last.isoformat(),
        "elapsed_min": round((last - first).total_seconds() / 60, 1),
        "main": {
            "turns": walked["turns"],
            "model_min": round(walked["model_seconds"] / 60, 1),
            "out_tokens": walked["out_tokens"],
            "ctx_max": max((c["ctx"] for c in walked["context_series"]), default=0),
            "ctx_series": walked["context_series"][::10],  # 10 ターンおき。形は保ちつつ JSON を小さくする
            "latency_p50": walked["latency_p50"],
            "latency_max": walked["latency_max"],
            "models": walked["models"],
            "tool_seconds_by_cat": walked["seconds_by_cat"],
            "tool_calls_by_cat": walked["calls_by_cat"],
            "longest": walked["longest"][:15],
        },
        "agents": agents,
        "agent_totals": totals,
        "agent_n": len(agents),
        "work_min": round(sum(a["wall_s"] for a in agents) / 60, 1),
        "concurrency": conc,
        "commands": [{"cat": cat, "total": total, "by_kind": dict(command_by_kind[cat].most_common())}
                     for cat, total in command_totals.most_common()],
        "longest_calls": sorted(
            [{"agent": "main", **c} for c in walked["longest"][:10]]
            + [{"agent": a["name"], **c} for a in agents for c in a["longest_calls"]],
            key=lambda item: -item["sec"])[:15],
        "spawns": spawns,
        "devimpl": detect_devimpl(spawns),
    }

    with open(args.out, "w") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=1)

    print(f"wrote {args.out}")
    print(f"  session   {session_id[:8]}  project={project}")
    print(f"  window    {first.isoformat()} .. {last.isoformat()}  ({data['elapsed_min']} min)")
    print(f"  main      turns={walked['turns']}  ctx_max={data['main']['ctx_max']}  "
          f"model={data['main']['model_min']}min")
    print(f"  agents    {len(agents)} 本  work={data['work_min']}min  "
          f"concurrency avg={conc['avg']} hist={conc['hist']}")
    if totals:
        print("  by kind   " + "  ".join(f"{k}={v['wall_min']}min/{v['n']}" for k, v in totals.items()))
    dev = data["devimpl"]
    if dev["detected"]:
        print(f"  dev-impl  検出。issue {len(dev['issues'])} 件  scratch={dev['scratch_dir']} "
              f"(存在={dev['scratch_exists']})")
        print("            → devimpl.py で層 B を集計できる")
    else:
        print("  dev-impl  未検出 (層 B はスキップ)")


if __name__ == "__main__":
    main()
