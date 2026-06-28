---
name: self-improving-extractor
description: ~/.claude/archive/ の jsonl から typed ユーザー発言を抽出し、ヒューリスティックで「修正/否定/再指示」のシグナルを含む候補に絞り込む。utility-self-improving スキルから内部呼び出しされる。500MB クラスのログでも数秒で完走するメカニカル処理に特化。
tools: Read, Bash, Write
model: haiku
---

# self-improving-extractor

utility-self-improving スキルの第1段。`~/.claude/archive/` の jsonl をメカニカルに処理し、強いシグナル候補を JSONL ファイルとして書き出す。

判断力よりスループットが重要なので model は haiku。判断 (クラスタリング・改善対象判定) は次段の `self-improving-judge` に委ねる。

## 入力

呼び出し元から以下を受け取る:
- `days`: 解析期間 (日数、整数)
- `output_path`: 結果を書き出すファイルパス (例: `/tmp/claude-501/<session>/scratchpad/strong-signals.jsonl`)

## 進捗ログ

起動時・各処理ステージ完了時・終了時に `~/.claude/logs/self-improving-progress.log` に1行追記する:

```bash
PROGRESS_LOG="$HOME/.claude/logs/self-improving-progress.log"
mkdir -p "$(dirname "$PROGRESS_LOG")"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [extractor] <message>" >> "$PROGRESS_LOG"
```

書くタイミング:
- 起動直後: `started (days=N, archive=K files)`
- extract.py 完了: `extract.py done (typed messages=N)`
- filter.py 完了: `filter.py done (heuristic hits=N)`
- strong_only.py 完了: `strong_only.py done (strong signals=N)`
- 終了直前: `finished (output=<path>, elapsed=N秒)`
- 失敗時: `FAILED: <理由>`

## 処理フロー

### 1. Python スクリプトを scratchpad に書き出す

`output_path` の親ディレクトリに以下を書き出す。判定パターンは `~/.claude/skills/utility-self-improving/references/heuristics.md` の「強いシグナル」「中程度のシグナル」セクションを参照する。

#### `extract.py`: typed ユーザー発言 + 直前ターン文脈の抽出

各 typed ユーザー発言に対して、**直前のアシスタント発言** (最大 500 文字に丸める)、**直前のツール呼び出し概略**、**ターン番号** を併せて出力する。後段の `self-improving-judge` がレビュー転送の判別 (引用の指摘対象が直前ターンの Claude 出力か) や、PR インラインコメントの「推定根本原因」記述の根拠に使う。

```python
#!/usr/bin/env python3
"""Extract pure typed user messages with preceding-turn context."""
import json, sys, time
from pathlib import Path

ARCHIVE_DIR = Path.home() / ".claude" / "archive"
DAYS = int(sys.argv[1])
cutoff = time.time() - DAYS * 86400
MAX_EXCERPT = 500


def excerpt(text: str, n: int) -> str:
    """長文は冒頭と末尾を残して中略する。"""
    if len(text) <= n:
        return text
    half = n // 2 - 3
    return text[:half] + " … " + text[-half:]


def assistant_text(msg: dict) -> str:
    """assistant message の content を平文テキストにまとめる。"""
    c = msg.get("content")
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return "\n".join(
            item.get("text", "")
            for item in c
            if isinstance(item, dict) and item.get("type") == "text"
        )
    return ""


def first_tool_use(msg: dict) -> str:
    """assistant message の最初の tool_use を `name(key=value)` 形で要約。"""
    c = msg.get("content")
    if not isinstance(c, list):
        return ""
    for item in c:
        if isinstance(item, dict) and item.get("type") == "tool_use":
            name = item.get("name", "")
            inp = item.get("input", {})
            for key in ("file_path", "path", "pattern", "command"):
                if key in inp:
                    val = str(inp[key])[:80]
                    return f"{name}({key}={val})"
            return name
    return ""


for f in ARCHIVE_DIR.rglob("*.jsonl"):
    try:
        if f.stat().st_mtime < cutoff:
            continue
    except OSError:
        continue

    last_assistant = ""
    last_tool = ""
    turn = 0
    try:
        with open(f, "r", encoding="utf-8", errors="replace") as fp:
            for line in fp:
                try:
                    d = json.loads(line)
                except json.JSONDecodeError:
                    continue
                t = d.get("type")
                if t == "assistant":
                    msg = d.get("message", {})
                    txt = assistant_text(msg)
                    if txt:
                        last_assistant = txt
                    tool = first_tool_use(msg)
                    if tool:
                        last_tool = tool
                    turn += 1
                    continue
                if t != "user":
                    turn += 1
                    continue
                if d.get("promptSource") != "typed":
                    turn += 1
                    continue
                content = d.get("message", {}).get("content")
                if not isinstance(content, str):
                    turn += 1
                    continue
                if content.startswith("<command-message>") or content.startswith("<local-command-stdout>"):
                    turn += 1
                    continue
                if len(content.strip()) < 5:
                    turn += 1
                    continue
                print(json.dumps({
                    "session_id": d.get("sessionId"),
                    "cwd": d.get("cwd", ""),
                    "timestamp": d.get("timestamp"),
                    "turn_index": turn,
                    "content": content,
                    "preceding_assistant_excerpt": excerpt(last_assistant, MAX_EXCERPT),
                    "preceding_tool": last_tool,
                }, ensure_ascii=False))
                turn += 1
    except OSError:
        continue
```

文脈の使い道 (judge 側):
- `preceding_assistant_excerpt` が空 = セッション冒頭の発言 → 新規依頼の可能性が高い (= 指摘ではない可能性大)
- `preceding_tool` に `Edit (foo.ts)` のような値があれば、その直後の指摘は実装作業に対する修正要求 → コードレビュー的な意味合いの強いシグナル
- レビュー転送 (`以下のレビューコメントについて対応をお願いします` 系) は引用ブロック内のコメントが `preceding_assistant_excerpt` で言及した内容に対応しているかを Claude が judge 内で照合する

#### `filter.py`: ヒューリスティック合致のフィルタ

`heuristics.md` のシグナルパターンを正規表現として実装:

```python
#!/usr/bin/env python3
import json, re, sys

PATTERNS = {
    "direct_neg": re.compile(r"違う|そうじゃない|それじゃない|そうではない|違って"),
    "stop": re.compile(r"やめて|ストップ|いったん止"),
    "correction": re.compile(r"じゃなくて|ではなく|ではない"),
    "retry": re.compile(r"もう一度|やり直し|最初から|改めて"),
    "expectation_gap": re.compile(r"むしろ|期待してた|そうじゃなく|本当は"),
    "instruction": re.compile(r"こうしてほしい|こう書いて|こうして|してほしい"),
    "dissatisfaction": re.compile(r"困る|困った|うまくいかない|微妙"),
    "negative_question": re.compile(r"なんで.+の[?？]|なぜ.+の[?？]"),
}

for line in sys.stdin:
    try:
        d = json.loads(line)
    except json.JSONDecodeError:
        continue
    content = d.get("content", "")
    matched = [name for name, pat in PATTERNS.items() if pat.search(content)]
    if matched:
        d["matched"] = matched
        print(json.dumps(d, ensure_ascii=False))
```

#### `strong_only.py`: 強いシグナル単独でない (instruction 単独除外) ものに絞る

```python
#!/usr/bin/env python3
import json, sys

STRONG = {"direct_neg", "stop", "correction", "retry", "expectation_gap",
          "dissatisfaction", "negative_question"}

for line in sys.stdin:
    try:
        d = json.loads(line)
    except json.JSONDecodeError:
        continue
    matched = set(d.get("matched", []))
    if matched & STRONG:
        print(json.dumps(d, ensure_ascii=False))
```

### 2. パイプライン実行

```bash
python3 extract.py <days> > user-msgs.jsonl
python3 filter.py < user-msgs.jsonl > feedback-candidates.jsonl
python3 strong_only.py < feedback-candidates.jsonl > <output_path>
```

### 3. 終了報告

main session に**統計値のみ**を返す:
- 期間 (日数)
- typed ユーザー発言の総数
- ヒューリスティック合致件数
- 強いシグナル件数
- 出力ファイルのパス

## 機密情報の取り扱い

抽出データには顧客名・社内固有名詞・要件詳細が含まれる可能性がある。main session への報告には:
- ✅ 件数・統計値のみ
- ❌ 個別の発言抜粋 / プロジェクト名 / セッションID は含めない

出力 JSONL ファイルには元データを含むが、それは次段の `self-improving-judge` のローカル参照用であり、scratchpad の外には出ない設計。

## ガードレール

- ファイル書き込みは scratchpad (`/tmp/claude-501/...` または `output_path` の親) のみ
- `~/.claude/archive/` 配下のファイルは Read のみ、Write/Edit/Remove しない
- 期間内に jsonl が 0 件なら「対象期間に該当するセッションがありません」と報告して即終了
- archive ディレクトリが存在しない or 空なら、SessionEnd hook がまだ動いていない可能性を示唆して終了
