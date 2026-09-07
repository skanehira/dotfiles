#!/usr/bin/env python3
"""生成後のpptxで、テキスト以外のXML(フォントサイズ・色・罫線・図形位置など
装飾・レイアウト関連の要素すべて)が元のpptxと完全一致しているかを検証する。

<a:t>...</a:t> の中身とXML宣言だけを無視して比較するので、一致していれば
「テキスト文字列以外は一切変更されていない」ことが構造的に保証される。

使い方:
  python verify_decoration.py <original.pptx> <translated.pptx>

差分があるスライドがあれば一覧を表示して exit code 1 を返す。
"""
import os
import re
import sys
import zipfile


def normalize(xml_bytes):
    s = xml_bytes.decode("utf-8")
    s = re.sub(r"^<\?xml[^>]*\?>\s*", "", s)
    # テキスト内容とそれに付随するタグ属性(xml:space等、テキスト長で自動変化しうる)を無視する。
    # 装飾(フォント・色・罫線・位置サイズ)を運ぶ属性はすべて<a:t>の外側(rPr/spPr等)にあるため対象外。
    # <a:t>の中身はテキストのみでXMLタグはネストしない仕様なので [^<]* で安全にマッチを打ち切る
    # (.*? だと空の自己終了タグ<a:t/>を挟んで次の<a:t>...</a:t>まで誤って飲み込むことがある)。
    s = re.sub(r"<a:t[^>]*/>", "<a:t/>", s)
    s = re.sub(r"<a:t[^>]*>[^<]*</a:t>", "<a:t/>", s)
    return s


def main():
    if len(sys.argv) != 3:
        print("usage: verify_decoration.py <original.pptx> <translated.pptx>", file=sys.stderr)
        sys.exit(1)
    orig_path, trans_path = sys.argv[1], sys.argv[2]
    for path in (orig_path, trans_path):
        if not os.path.isfile(path):
            print(f"ERROR: pptxファイルが見つかりません: {path}", file=sys.stderr)
            sys.exit(1)

    zo = zipfile.ZipFile(orig_path)
    zt = zipfile.ZipFile(trans_path)

    names = sorted(n for n in zo.namelist() if re.match(r"ppt/slides/slide\d+\.xml$", n))
    bad = []
    for n in names:
        if n not in zt.namelist():
            bad.append(n)
            continue
        if normalize(zo.read(n)) != normalize(zt.read(n)):
            bad.append(n)

    if bad:
        print(f"NG: {len(bad)}/{len(names)} スライドでテキスト以外の差分が検出されました:")
        for n in bad:
            print(f"  {n}")
        sys.exit(1)
    else:
        print(f"OK: 全{len(names)}スライドでテキスト以外のXMLが完全一致(装飾・レイアウトは無変更)")


if __name__ == "__main__":
    main()
