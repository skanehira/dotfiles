#!/usr/bin/env python3
"""Markdown の文書から、過程の記述・検証の経緯・長い文・別の節との重複を見つける。

usage: doc_check.py [--base <git ref>] <file>...

  --base を付けると、<git ref> から追加・変更した行だけを検査する (既存の文書の改訂向け)。
  未追跡のファイルは全行を検査する。

過程の記述・検証の経緯・長い文は error、重複は warning として 1 行ずつ出す。
exit code: error が 1 件でもあれば 1、無ければ 0、使い方の誤りは 2。
"""
import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

FENCE_RE = re.compile(r"^\s*(```|~~~)")
INLINE_CODE_RE = re.compile(r"`[^`\n]*`")
LINK_RE = re.compile(r"!?\[([^\]]*)\]\([^)]*\)")
HTML_COMMENT_RE = re.compile(r"<!--.*?-->", re.S)
JP_RE = re.compile(r"[぀-ヿ一-鿿]")

# 経緯を残すこと自体が目的の文書。過程と検証の経緯は検査しない
RECORD_DOC_RE = re.compile(r"DESIGN_NOTES|CHANGELOG|HISTORY|議事録|(^|/)adr/", re.I)
EXEMPT_SECTION_RE = re.compile(r"依拠する外部事実|変更履歴")

# 「以前の」「旧版」「変えた」のような広い語は業務の記述 (「以前のコード」「旧版の結果」) に当たるので使わない
_NOT_AFTER = r"(?!ら|い|とき|時|場合|後|あと|うえ|上で|もの|状態|まま|差分|箇所|ところ|行|ファイル)"
PROCESS_RES = [re.compile(p) for p in [
    r"以前は|当初は|当初の|もともと|元々は|かつては|これまでは|従来は",
    r"旧(方式|実装|設計|構成|配布|生成器|来|運用|名称|名)(?!前)",
    r"(に|へ)(変更|移行|切り替え|置き換え|改名|統合)(した|しました|され(た|ました)|済み)" + _NOT_AFTER,
    r"(切り替えた|切り替えました)" + _NOT_AFTER,
    r"(?<![突])(やめた|やめました|廃止した|廃止された|廃止済み|撤去した|撤去済み|見送った|取り下げた)" + _NOT_AFTER,
    r"撤回",
    r"(だった|であった|ていた|ていました)(が|けど|ものの)",
    r"から[^。、]{1,25}へ(変更し|移行し|切り替え|置き換え)(た|ました)",
    r"経緯|変遷",
    r"20\d\d-\d\d(-\d\d)?\s*(に|の|時点|以降|現在)[^。]{0,40}?(した|された|だった|ていた|確認|実測|計測|測)",
]]
# 「」の中は、規則が禁止例として引用した語や文 (「以前は〜だったが」) なので、過程の記述として数えない
QUOTED_RE = re.compile(r"「[^」]*」|『[^』]*』")
# 過程の語そのものを定義・説明する文書 (このスキルと documentation.md) が付ける印
SKIP_PROCESS_MARK = "<!-- doc-check: skip-process -->"
VERIFICATION_RE = re.compile(r"確かめていない|確かめてはおらず|確認していない|未確認|未実測|(推測|推論)で(、|ある|あり|しか)|検証していない")

LONG_SENTENCE_CHARS = 100
DUPLICATE_JACCARD = 0.6
DUPLICATE_MIN_CHARS = 25

LABELS = {"process": "過程の記述", "verification": "検証の経緯", "long": "長い文", "duplicate": "別の節と重複"}
ERROR_KINDS = {"process", "verification", "long"}


@dataclass
class Finding:
    line: int
    kind: str
    text: str
    note: str = ""


def classify_lines(text):
    """(行番号, 種類, 整えた本文, 節の見出し) を返す。種類: code / table / heading / list / prose / blank / front"""
    text = HTML_COMMENT_RE.sub(lambda m: "\n" * m.group(0).count("\n"), text)
    lines = text.split("\n")
    out, in_code, prev_blank, last_kind, section = [], False, True, "blank", ""
    in_front = bool(lines) and lines[0].strip() == "---"
    for i, raw in enumerate(lines, 1):
        if in_front:
            out.append((i, "front", raw, section))
            if i > 1 and raw.strip() == "---":
                in_front = False
            continue
        if FENCE_RE.match(raw):
            in_code = not in_code
            out.append((i, "code", raw, section))
            continue
        if in_code:
            out.append((i, "code", raw, section))
            continue
        s = raw.strip()
        cleaned = LINK_RE.sub(r"\1", INLINE_CODE_RE.sub("〔C〕", raw))
        if not s:
            kind = "blank"
        elif s.startswith("|"):
            kind = "table"
        elif s.startswith("#"):
            kind = "heading"
            section = s.lstrip("#").strip()
        elif re.match(r"^\s*([-*+]|\d+\.)\s", raw):
            kind = "list"
        elif raw.startswith(("    ", "\t")) and prev_blank and last_kind not in ("list", "indent"):
            kind = "code"  # 空行の後で、箇条書きの続きではない 4 字下げのコードブロック
        else:
            kind = "prose"
        if kind != "blank":
            last_kind = "indent" if (raw.startswith("  ") and last_kind in ("list", "indent") and kind != "code") else kind
        prev_blank = kind == "blank"
        out.append((i, kind, cleaned, section))
    return out


def sentences_of(cleaned):
    body = re.sub(r"^\s*([-*+]|\d+\.)\s+", "", cleaned)
    return [frag.strip() + "。" for frag in body.split("。")[:-1] if JP_RE.search(frag)]


def check_text(text, name, only_lines=None):
    record_doc = bool(RECORD_DOC_RE.search(name)) or SKIP_PROCESS_MARK in text
    findings, dup_pool = [], []
    for ln, kind, cleaned, section in classify_lines(text):
        if kind not in ("prose", "list", "table", "heading"):
            continue
        target = only_lines is None or ln in only_lines
        stripped = cleaned.strip()
        exempt = record_doc or bool(EXEMPT_SECTION_RE.search(section))
        unquoted = QUOTED_RE.sub("", cleaned)
        if target and not exempt:
            if any(rx.search(unquoted) for rx in PROCESS_RES):
                findings.append(Finding(ln, "process", stripped))
            elif VERIFICATION_RE.search(unquoted):
                findings.append(Finding(ln, "verification", stripped))
        if kind in ("prose", "list"):
            for s in sentences_of(cleaned):
                if target and len(s) > LONG_SENTENCE_CHARS:
                    findings.append(Finding(ln, "long", stripped, f"{len(s)} 字"))
                key = re.sub(r"〔C〕|\s|\*\*", "", s)
                if len(key) >= DUPLICATE_MIN_CHARS:
                    dup_pool.append((ln, section, {key[i:i + 3] for i in range(len(key) - 2)}, stripped))
    for j, (ln, sec, grams, stripped) in enumerate(dup_pool):
        if only_lines is not None and ln not in only_lines:
            continue
        for ln0, sec0, grams0, _ in dup_pool[:j]:
            if sec0 != sec and len(grams & grams0) / len(grams | grams0) >= DUPLICATE_JACCARD:
                findings.append(Finding(ln, "duplicate", stripped, f"L{ln0}"))
                break
    return sorted(findings, key=lambda f: (f.line, f.kind))


def added_lines(path, base):
    """base から追加・変更した行番号の集合。未追跡なら None (全行)。"""
    cwd = str(path.parent)
    tracked = subprocess.run(["git", "-C", cwd, "ls-files", "--error-unmatch", str(path)],
                             capture_output=True).returncode == 0
    if not tracked:
        return None
    diff = subprocess.run(["git", "-C", cwd, "diff", "-U0", base, "--", str(path)],
                          capture_output=True, text=True, check=True).stdout
    lines = set()
    for m in re.finditer(r"^@@ -\S+ \+(\d+)(?:,(\d+))? @@", diff, re.M):
        start, count = int(m.group(1)), int(m.group(2) or 1)
        lines.update(range(start, start + count))
    return lines


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--base")
    ap.add_argument("files", nargs="+")
    args = ap.parse_args(argv)
    errors = warnings = 0
    for f in args.files:
        path = Path(f).resolve() if args.base else Path(f)
        only = added_lines(path, args.base) if args.base else None
        for fd in check_text(path.read_text(), str(path), only):
            note = f" ({fd.note})" if fd.note else ""
            print(f"{f}:{fd.line}: [{fd.kind}] {LABELS[fd.kind]}{note}: {fd.text}")
            if fd.kind in ERROR_KINDS:
                errors += 1
            else:
                warnings += 1
    print(f"error {errors} 件 / warning {warnings} 件", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
