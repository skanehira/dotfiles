#!/usr/bin/env python3
"""data.json (+ ext.json) と narrative.json をテンプレートへ流し込み、HTML を 1 枚出す。

図表はデータから、散文は narrative から描く。narrative.sections に無いキーの節は
描かれないので、層 B が取れないセッションではその節を narrative から省けばよい。

使い方:
    render.py --data data.json --narrative narrative.json -o report.html
    render.py --data data.json --ext ext.json --narrative narrative.json -o report.html
"""
import argparse
import json
import os
import re
import sys

TEMPLATE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "template.html")

# narrative.sections に置けるキー。テンプレート側の section() 呼び出しと対応する。
KNOWN_SECTIONS = ["verdict", "timeline", "critical", "breakdown", "review", "cost", "incidents", "optimize"]


def esc(text):
    """<title> に入れる前のエスケープ。title はプレーンテキスト扱いと文書で約束している。"""
    return (str(text).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def embed(value):
    """JSON を <script type="application/json"> に安全に埋める。

    エスケープしないと、文字列値に含まれる </script> でパースが切れる。
    """
    return (json.dumps(value, ensure_ascii=False, separators=(",", ":"))
            .replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026"))


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--data", required=True, help="collect.py の出力")
    parser.add_argument("--ext", help="devimpl.py の出力 (層 B。無くてよい)")
    parser.add_argument("--narrative", required=True, help="分析の散文を書いた JSON")
    parser.add_argument("--template", default=TEMPLATE, help="テンプレート HTML")
    parser.add_argument("-o", "--out", default="report.html", help="出力先")
    args = parser.parse_args()

    data = json.load(open(args.data))
    ext = json.load(open(args.ext)) if args.ext else None
    narrative = json.load(open(args.narrative))

    if not narrative.get("title"):
        sys.exit("narrative.json に title が無い")
    sections = narrative.get("sections") or {}
    unknown = [k for k in sections if k not in KNOWN_SECTIONS]
    if unknown:
        sys.exit(f"narrative.sections に未知のキー: {unknown}\n置けるのは {KNOWN_SECTIONS}")

    # 節を描くのに要る材料が空なら、見出しだけの節が出るので先に止める。
    # ext があっても中身が空のことがある (gh を使わなければ依存段は取れない)。
    empty = []
    for key, source, field in (("critical", ext, "critical"), ("review", ext, "rounds"),
                               ("incidents", narrative, "incidents"),
                               ("optimize", narrative, "fixes")):
        if key in sections and not (source or {}).get(field):
            empty.append(f"{key} (材料の {field} が空)")
    # タイムラインの帯は issue 単位 (層 B) かエージェント単位 (層 A2) のどちらかで描く。
    # subagent が 0 本で層 B も無いセッションでは、描くものが何も無い。
    if "timeline" in sections and not (ext or {}).get("issues") and not data.get("agents"):
        empty.append("timeline (issue もエージェントも無い)")
    if empty:
        sys.exit("材料が無いのに節が指定されている: " + ", ".join(empty)
                 + "\nnarrative.sections から該当キーを消すか、材料を揃えてから実行する")

    template = open(args.template).read()
    for placeholder, value in (("__TITLE__", None), ("__DATA__", data),
                               ("__EXT__", ext), ("__NARRATIVE__", narrative)):
        if template.count(placeholder) != 1:
            sys.exit(f"テンプレートの {placeholder} が 1 個ではない: {args.template}")
        replacement = esc(narrative["title"]) if placeholder == "__TITLE__" else embed(value)
        template = template.replace(placeholder, replacement)

    with open(args.out, "w") as handle:
        handle.write(template)

    # 埋め込んだ JSON が本当に読めるかを、書き出した現物で確かめる。
    written = open(args.out).read()
    for element_id in ("d-data", "d-ext", "d-narrative"):
        found = re.search(rf'<script type="application/json" id="{element_id}">(.*?)</script>',
                          written, re.S)
        if not found:
            sys.exit(f"{element_id} のブロックが壊れている")
        json.loads(found.group(1))

    drawn = [k for k in KNOWN_SECTIONS if k in sections]
    print(f"wrote {args.out} ({os.path.getsize(args.out) // 1024} KB)")
    print(f"  title    {narrative['title']}")
    print(f"  sections {len(drawn)} 節: {', '.join(drawn)}")
    print(f"  layers   A{'2' if data.get('agent_n') else '1'}"
          + (" + B" if ext else "") + f"  (agents {data.get('agent_n', 0)} 本)")
    missing = [k for k in KNOWN_SECTIONS if k not in sections]
    if missing:
        print(f"  未使用   {', '.join(missing)} (narrative に無いので描かない)")


if __name__ == "__main__":
    main()
