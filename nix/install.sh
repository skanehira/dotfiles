#!/bin/bash
set -euo pipefail

# nix-darwin の初回 bootstrap
# - sudo 必須（system 領域への書き込み）
# - sudo の secure_path には /nix が含まれないため、絶対パスで nix を呼ぶ
# - root には experimental-features が設定されていないので --extra-experimental-features で明示
# - bootstrap 後は nix-darwin の system.nix が /etc/nix/nix.conf に書き込むので、
#   user-level (~/.config/nix/nix.conf) は不要

# script 自身の path を基準に flake を解決する。
# bootstrap.sh からの exec (cwd=dotfiles root) と手動 `cd nix && bash ./install.sh`
# (cwd=nix) の両方で同じ flake を指せる
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

sudo /nix/var/nix/profiles/default/bin/nix \
    --extra-experimental-features 'nix-command flakes' \
    run nix-darwin -- switch --flake "$SCRIPT_DIR#skanehira"
