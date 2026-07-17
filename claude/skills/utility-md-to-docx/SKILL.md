---
name: utility-md-to-docx
description: Markdown 文書から Word（.docx）を生成する。macOS Pages で開いても表の分断・巨大空白・見出しの孤立が起きない検証済みパターン（python-docx）と、Pages 自動書き出しによるレンダリング検証ループを提供。「mdをdocxにして」「Wordファイルを作って」「docxで納品したい」「チェックリストをWordにして」などのリクエストで起動。
argument-hint: "[入力.md] [出力.docx]"
---

# /utility-md-to-docx

Markdown を元に、**レンダリング検証まで込みで** Word（.docx）を作る。

単純な変換ツール（pandoc 等）を使わない理由: 生成した docx を macOS Pages で開くと、
`keepNext` や `pageBreakBefore` プロパティが「表が見出しから分離して次ページへ飛ぶ」
「ページの大半が空白になる」誤レイアウトを引き起こす（実測で確認済み）。本スキルは
この落とし穴を回避したビルダーを書き、実レンダリングで確認してから完了とする。

前提: python-docx（venv に `pip install python-docx`）。レンダリング検証は macOS + Pages。

## 手順

### 1. 入力 md の構造把握

対象の Markdown を Read し、docx で表現する要素を洗い出す:

- 見出し階層（#, ##, ###）
- 表（列数・想定列幅・行数。長い表か 1 ページに収まる表か）
- 箇条書き・注記（※〜）・コードブロックの有無
- 記入欄（チェック欄・署名欄など、受領者が書き込むセル）の有無

### 2. ビルダースクリプトを書く

`assets/docx_helpers.py` を作業ディレクトリにコピーし、それを import する
Python スクリプトとして文書ごとのビルダーを書く（汎用変換器は書かない。
文書の意図に合わせた列幅・改ページはコード化するのが確実）。

```python
from docx import Document
from docx_helpers import (
    setup_a4, add_heading, add_body, add_bullet, make_table,
    add_page_break, finalize,
)

doc = Document()
content_width = setup_a4(doc)  # A4 + マージン明示。戻り値はコンテンツ幅(cm)

add_heading(doc, "1. 目的")
add_body(doc, "本書は……")
make_table(
    doc,
    headers=["No", "項目", "確認観点", "チェック"],
    col_widths_cm=[1.0, 4.0, 10.0, 2.0],  # 合計 ≤ content_width
    rows=[["1", "…", "…", ""]],
)
finalize(doc, "出力先.docx")
```

**禁止事項**（詳細と実測根拠 → [references/pages-compat.md](references/pages-compat.md)）:

| 禁止 | 代わりに使う |
|---|---|
| `paragraph_format.keep_with_next` | 使わない。見出しの孤立は手順 4 のループで調整 |
| `paragraph_format.page_break_before` | `add_page_break()`（改ページ文字 `w:br` の独立段落） |
| `w:trHeight` の手動 append | `set_row_height()`（python-docx API のみ） |
| セル幅だけ設定して列幅未設定 | `make_table()`（tblGrid と tcW を一致させる） |
| `cell.vertical_alignment` 後の `w:shd` append | `set_cell_text(bg=...)`（正しい要素順で処理） |

### 3. ビルドとスキーマ検証

```bash
venv/bin/python builder.py
```

生成後、document-skills:docx プラグインの validate.py でスキーマ検証する
（パスは `~/.claude/plugins/cache/**/skills/docx/scripts/office/validate.py` を find で解決。
`defusedxml` `lxml` が venv に必要）。PASSED になるまで次へ進まない。

### 4. レンダリング検証ループ（必須・スキップ不可）

スキーマ検証だけでは**ページ割りの問題は検出できない**。Pages で実際に書き出して確認する:

1. `open -a Pages && sleep 3` で Pages を起動
2. AppleScript で docx → PDF 書き出し（スクリプトは [references/pages-compat.md](references/pages-compat.md) の「レンダリング検証の手順」節）
3. `qpdf --show-npages` でページ数を取得し、抜粋 PDF を Read で目視
4. 次を確認する:
   - 見出しと直後の表が同じページにあるか（分離していないか）
   - ページに不自然な巨大空白がないか
   - 見出しがページ末尾に孤立していないか
   - 複数ページにまたがる表でヘッダー行が再表示されているか
5. 見出しの孤立があれば、その見出しに `page_break_before=True` を付けて 1→4 を再実行
6. すべて解消するまで反復（通常 1〜3 周で収束）

Pages の起動エラー（-609 / -1712）への対処も references/pages-compat.md に記載。

### 5. 完了報告

- 出力パス・ページ数
- レンダリング検証の結果（何周で収束したか、調整した改ページ位置）
- md と docx の二重管理になる場合はその旨（どちらが編集元かを明示）

## 原因不明のレイアウト問題に遭遇したら

推測で直さない。疑わしい要素を 1 つずつ無効化したバリアント docx を作り、
それぞれ Pages で書き出して**ページ数の変化**で犯人を機械判定する
（[references/pages-compat.md](references/pages-compat.md) の「二分探索」節）。

## 境界（対象外）

- 汎用の md→docx 一括変換（pandoc 相当）は提供しない。文書ごとにビルダーを書く
- md→PDF は対象外（Chrome headless + print.css の別パイプラインを使う）
- Windows/Word 環境でのレンダリング検証は対象外（Pages でのみ検証。Word は
  keepNext 等を正しく解釈するため、Pages で正常なら Word でも概ね安全）
