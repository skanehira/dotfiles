#!/usr/bin/env python3
"""Qwen-Image-2.1 の diffusers 形式の重みを ComfyUI が読む単一ファイル形式へ変換する。

mflux が読む `~/.cache/huggingface/hub/models--Qwen--Qwen-Image-2.1` の shard を
結合して `--base-directory` 配下の `models/` へ置く。キーのリネームは行わない
(ComfyUI 側のローダが `model.language_model.` → `model.` の置換と `fused_mlp` の
自動判定を行うため)。VAE だけはキー体系が別なので Comfy-Org から取得する。

ComfyUI の venv の python で実行する:

    ~/.local/share/comfyui/venv/bin/python comfyui/merge-weights.py

出力が既にあれば skip する。作り直すときは --force を付ける。
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

# 変換の対象。(diffusers 側のサブディレクトリ, shard 名の接頭辞, 出力先, 期待するキー数)
TARGETS = [
    ("transformer", "diffusion_pytorch_model", "diffusion_models/qwen_image_2.1_bf16.safetensors", 297),
    ("text_encoder", "model", "text_encoders/qwen3vl_8b_bf16.safetensors", 750),
]

# VAE は diffusers 版と ComfyUI 版でキー名が違う (decoder.conv_in.* / conv1.*) ので取得する
VAE_REPO = "Comfy-Org/Qwen-Image-2.1"
VAE_FILE = "vae/qwen_image_2.1_vae_bf16.safetensors"
VAE_DEST = "vae/qwen_image_2.1_vae_bf16.safetensors"
VAE_SIZE = 675509688


def find_snapshot() -> Path:
    """HF キャッシュ内の Qwen-Image-2.1 の snapshot を 1 つに特定する。"""
    base = Path.home() / ".cache/huggingface/hub/models--Qwen--Qwen-Image-2.1/snapshots"
    if not base.is_dir():
        sys.exit(f"HF キャッシュが無い: {base}")
    snapshots = sorted(p for p in base.iterdir() if p.is_dir())
    if len(snapshots) != 1:
        sys.exit(f"snapshot が {len(snapshots)} 件ある (1 件を想定): {[p.name for p in snapshots]}")
    return snapshots[0]


def merge(src_dir: Path, prefix: str, dest: Path, expected_keys: int) -> None:
    """shard を結合して 1 ファイルに書き出す。"""
    from safetensors import safe_open
    from safetensors.torch import save_file

    shards = sorted(src_dir.glob(f"{prefix}-*-of-*.safetensors"))
    if not shards:
        sys.exit(f"shard が見つからない: {src_dir}/{prefix}-*-of-*.safetensors")

    print(f"[{dest.name}] {len(shards)} shard を結合する", flush=True)
    tensors = {}
    for shard in shards:
        with safe_open(shard, framework="pt") as f:
            for key in f.keys():
                if key in tensors:
                    sys.exit(f"キーが shard 間で重複している: {key}")
                tensors[key] = f.get_tensor(key)
        print(f"  {shard.name}: 累計 {len(tensors)} キー", flush=True)

    if len(tensors) != expected_keys:
        sys.exit(f"キー数が想定と違う: {len(tensors)} (想定 {expected_keys})")

    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".tmp")
    save_file(tensors, tmp, metadata={"format": "pt"})
    tmp.rename(dest)
    print(f"  -> {dest} ({dest.stat().st_size / 2**30:.2f} GiB)", flush=True)


def fetch_vae(dest: Path) -> None:
    """ComfyUI 版の VAE を取得する。"""
    from huggingface_hub import hf_hub_download

    # xet の受信バッファがメモリを食う問題を避けて HTTP のストリーム書き込みにする
    # (実測: xet はダウンロード分をディスクへ書かずに RSS を増やし続けた)
    os.environ["HF_HUB_DISABLE_XET"] = "1"

    print(f"[{dest.name}] {VAE_REPO} から取得する", flush=True)
    path = Path(hf_hub_download(VAE_REPO, VAE_FILE))
    size = path.stat().st_size
    if size != VAE_SIZE:
        sys.exit(f"VAE のサイズが想定と違う: {size} B (想定 {VAE_SIZE} B)")

    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.is_symlink() or dest.exists():
        dest.unlink()
    dest.symlink_to(path.resolve())
    print(f"  -> {dest} -> {path.resolve()}", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--models-dir",
        type=Path,
        default=Path.home() / ".local/share/comfyui/models",
        help="ComfyUI の models ディレクトリ (既定: ~/.local/share/comfyui/models)",
    )
    parser.add_argument("--force", action="store_true", help="出力が既にあっても作り直す")
    args = parser.parse_args()

    snapshot = find_snapshot()
    print(f"snapshot: {snapshot}", flush=True)

    for subdir, prefix, rel_dest, expected_keys in TARGETS:
        dest = args.models_dir / rel_dest
        if dest.exists() and not args.force:
            print(f"[{dest.name}] 既にあるので skip ({dest.stat().st_size / 2**30:.2f} GiB)", flush=True)
            continue
        merge(snapshot / subdir, prefix, dest, expected_keys)

    vae_dest = args.models_dir / VAE_DEST
    if vae_dest.exists() and not args.force:
        print(f"[{vae_dest.name}] 既にあるので skip", flush=True)
    else:
        fetch_vae(vae_dest)

    print("完了", flush=True)


if __name__ == "__main__":
    main()
