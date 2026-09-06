#!/usr/bin/env python3
"""HF キャッシュのシャードが揃っているか検証する。

サイズ一致だけでは不十分なので、model.safetensors.index.json の weight_map から
必要なシャードを列挙し、symlink を辿った実体が存在して非ゼロであることを確認する。

使い方 (両ノードで同じものを実行して突き合わせる):
    python3 verify_shards.py models--nvidia--Qwen3.8-Flash-Next-NVFP4

欠落があれば exit 1。
"""
import glob
import json
import os
import sys


def main() -> int:
    if len(sys.argv) < 2:
        print("使い方: verify_shards.py <HF キャッシュのモデルディレクトリ名>", file=sys.stderr)
        return 2

    base = os.path.expanduser(f"~/.cache/huggingface/hub/{sys.argv[1]}")
    if not os.path.isdir(base):
        print(f"  モデルディレクトリが無い: {base}")
        return 1

    snaps = glob.glob(os.path.join(base, "snapshots", "*"))
    if not snaps:
        print("  snapshot が無い")
        return 1
    snap = snaps[0]

    idx = os.path.join(snap, "model.safetensors.index.json")
    if os.path.exists(idx):
        need = sorted(set(json.load(open(idx))["weight_map"].values()))
    else:
        # 単一シャードのモデルは index を持たない
        need = sorted(os.path.basename(p) for p in glob.glob(os.path.join(snap, "*.safetensors")))
        if not need:
            print("  index も safetensors も見つからない")
            return 1

    missing, total = [], 0
    for name in need:
        real = os.path.realpath(os.path.join(snap, name))
        if not os.path.exists(real) or os.path.getsize(real) == 0:
            missing.append(name)
        else:
            total += os.path.getsize(real)

    files = sum(len(f) for _, _, f in os.walk(base))
    incomplete = len(glob.glob(os.path.join(base, "blobs", "*.incomplete")))

    print(f"  必要 {len(need)} / 揃い {len(need) - len(missing)} / 欠落 {len(missing)}")
    print(f"  重み合計 {total / 1e9:.1f} GB / ファイル数 {files} / 未完了 {incomplete}")
    for m in missing[:5]:
        print(f"    欠落: {m}")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
