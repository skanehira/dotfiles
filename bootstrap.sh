#!/usr/bin/env bash
set -euo pipefail

# 新 Mac セットアップ用 bootstrap
# - clone 後これ 1 本で Nix install → nix-darwin 適用まで完了
# - 既存マシンでは Nix install を skip するので何度叩いても idempotent

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# mkOutOfStoreSymlink は claude.nix / neovim.nix でこの path を直参照する。
# 別 path に clone されると drs は通るが symlink が dangle するので先に検証
EXPECTED_DIR="$HOME/dev/github.com/skanehira/dotfiles"
if [ "$SCRIPT_DIR" != "$EXPECTED_DIR" ]; then
    echo "Error: dotfiles を $EXPECTED_DIR に clone してください" >&2
    echo "  current: $SCRIPT_DIR" >&2
    exit 1
fi

# Nix install (未導入時のみ)。公式 installer は途中で y/n プロンプトが出るので
# 承認する。完全 non-interactive にしたければ Determinate installer に切り替える
if [ ! -e /nix/var/nix/profiles/default/bin/nix ]; then
    echo "==> Installing Nix..." >&2
    sh <(curl -L https://nixos.org/nix/install) --daemon
fi

# daemon が unload 状態なら load する。公式 installer は通常 bootstrap してくれるが
# 別 installer の干渉や手動 unload 等で外れることがあり、その場合 install.sh が
# socket connect で落ちる。socket 不在 ≒ daemon 未起動と判定
if [ ! -S /nix/var/nix/daemon-socket/socket ]; then
    echo "==> Loading nix-daemon..." >&2
    sudo launchctl load -w /Library/LaunchDaemons/org.nixos.nix-daemon.plist
fi

# nix-darwin bootstrap。install.sh は absolute path で nix を叩くので、現 shell
# の PATH に nix が無くても動く (Nix install 直後でも shell 再起動不要)
exec "$SCRIPT_DIR/nix/install.sh"
