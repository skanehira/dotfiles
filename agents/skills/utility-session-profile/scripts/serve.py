#!/usr/bin/env python3
"""生成した HTML を表示確認するためのローカルサーバ。

python3 -m http.server は text/html に charset を付けないため、日本語のページが
CP932 として解釈され、JS のテンプレートリテラルが壊れて描画が止まる。
確認のためだけに charset を明示して配信する。

使い方:
    serve.py [ディレクトリ] [--port 8731]
    → http://127.0.0.1:8731/report.html を開く
"""
import argparse
import functools
import http.server


class Handler(http.server.SimpleHTTPRequestHandler):
    def guess_type(self, path):
        kind = super().guess_type(path)
        if isinstance(kind, tuple):  # Python のバージョンで戻り値の形が違う
            kind = kind[0]
        if kind and kind.startswith("text/"):
            return kind + "; charset=utf-8"
        return kind


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("directory", nargs="?", default=".", help="配信するディレクトリ")
    parser.add_argument("--port", type=int, default=8731)
    args = parser.parse_args()
    http.server.test(HandlerClass=functools.partial(Handler, directory=args.directory),
                     port=args.port, bind="127.0.0.1")


if __name__ == "__main__":
    main()
