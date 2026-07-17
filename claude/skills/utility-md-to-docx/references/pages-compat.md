# macOS Pages 互換の落とし穴（実測に基づく詳細）

python-docx で生成した docx を macOS Pages で開いたとき、Word では問題にならない
OOXML 機能が誤レイアウトを起こす。以下はすべて実文書（納品ドキュメント）で発生し、
バリアントを 1 要素ずつ切り替えた二分探索レンダリングで因果を確認したもの。

## 目次

1. 禁止 1: `keepNext`
2. 禁止 2: `pageBreakBefore` プロパティ
3. 必須 1: ページサイズの明示（A4）
4. 必須 2: `tblGrid` とセル幅 `tcW` の一致
5. 必須 3: `trHeight` を二重に入れない
6. 必須 4: `w:shd` は `w:vAlign` より前
7. 必須 5: `w:zoom` に `w:percent` 属性
8. 見出しの孤立（orphan）への対処
9. レンダリング検証の手順（Pages 自動書き出し）
10. 二分探索によるレイアウト問題の切り分け

## 禁止 1: `keepNext`（`paragraph_format.keep_with_next`）

- **症状**: 見出しに付けると、Pages が見出し以降のブロック（見出し + 表 + 次の見出し + 表 …）
  を過剰に連結した keep 単位とみなし、丸ごと次ページへ送る。元のページには本文の後に
  巨大な空白（ページの 7〜8 割）が残る。
- **切り分け結果**: cantSplit・tblHeader・trHeight を外しても症状は消えず、
  keepNext を外した場合のみ解消（ページ数 7→6 で機械判定）。
- **Word との差**: Word は keepNext を「次の段落の先頭行と同ページ」とだけ解釈するので
  問題にならない。Pages 側の実装差。

## 禁止 2: `pageBreakBefore` プロパティ（`paragraph_format.page_break_before`）

- **症状**: 直後に表がある段落（見出し）に付けると、Pages は見出しを新ページに置いた上で
  **表をさらにその次のページへ送る**。結果「見出しだけのページ」ができる。
- **代替**: 改ページ文字 `w:br type="page"` を独立段落として挿入する
  （`docx_helpers.add_page_break()`）。この方式では症状は出ない。

## 必須 1: ページサイズの明示（A4）

python-docx の既定テンプレートは US Letter（12240×15840 twips）。日本語文書は
A4 前提で表幅（コンテンツ幅 17〜18cm）を設計するため、ページを明示しないと
幅計算とページ割りが狂う。`docx_helpers.setup_a4()` を必ず呼ぶ。

## 必須 2: `tblGrid` とセル幅 `tcW` の一致

セル幅（`cell.width`）だけ設定して列幅（`table.columns[i].width`）を設定しないと、
tblGrid は均等割りで生成され、tcW との不一致が生まれる。この不一致は Pages の
表配置計算を狂わせる一因になる。`docx_helpers.make_table()` は両方を設定する。

## 必須 3: `trHeight` を二重に入れない

`row.height = Cm(x)` のあとに手動で `w:trHeight` 要素を append すると、trPr 内に
trHeight が 2 個並ぶ。python-docx の API（`row.height` + `row.height_rule`）だけを使う。

## 必須 4: `w:shd`（セル背景）は `w:vAlign` より前

`cell.vertical_alignment` を設定した後に `w:shd` を append すると OOXML の要素順序
違反になり、スキーマ検証（validate.py）に落ちる。`docx_helpers.set_cell_text(bg=...)`
は正しい順序で処理する。

## 必須 5: `w:zoom` に `w:percent` 属性

settings.xml の `w:zoom` 要素は percent 属性が無いとスキーマ検証に落ちる。
`docx_helpers.finalize()` が保存時に補う。

## 見出しの孤立（orphan）への対処

keepNext を使えないため、コンテンツ量によっては見出しがページ末尾に孤立する。
対処は「レンダリングして確認 → 孤立した見出しに `page_break_before=True` を指定」
の反復のみ。機械的に事前判定はできない（フォントメトリクスに依存するため）。

**本文を増減させたら必ず再レンダリングして孤立を確認し直すこと。**
改ページ指定は以前のコンテンツ量に合わせたものなので、位置の見直しが要る。

## レンダリング検証の手順（Pages 自動書き出し）

Word が無い macOS 環境では、Pages を AppleScript で操作して PDF を書き出し検証する。

```bash
# Pages が起動していないと -609 (接続が無効) になるため必ず先に起動する
open -a Pages && sleep 3

osascript <<'EOF'
with timeout of 60 seconds
    set inFile to POSIX file "/absolute/path/to/文書.docx"
    set outFile to POSIX file "/absolute/path/to/render.pdf"
    tell application "Pages"
        set theDoc to open inFile
        delay 1
        export theDoc to outFile as PDF
        close theDoc saving no
    end tell
end timeout
EOF

qpdf --show-npages render.pdf   # ページ数（回帰の機械判定に使える）
```

- 初回はユーザーの画面に自動化許可ダイアログが出ることがある（承認してもらう）
- `-609 接続が無効` → Pages 未起動。`open -a Pages && sleep 3` してから再実行
- `-1712 AppleEvent タイムアウト` → Pages がダイアログでブロックされている。
  `pkill -f Pages.app` で強制終了 → 再起動してやり直す
- 特定ページだけ確認したいときは `qpdf --pages in.pdf 3-5 -- in.pdf excerpt.pdf` で
  抜粋してから Read で目視する（全ページ読み込みよりコンテキストを節約できる）

## 二分探索によるレイアウト問題の切り分け

原因不明のページ割り問題は、推測せず疑わしい要素（keepNext / cantSplit / tblHeader /
trHeight / 改ページ）を 1 つずつ無効化したバリアント docx を作り、それぞれ Pages で
書き出して**ページ数の変化**で判定する。ページ数は `qpdf --show-npages` で機械取得
できるので、目視前の一次スクリーニングとして安価。
