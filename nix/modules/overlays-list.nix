# nixpkgs に適用する overlay の素のリスト。
# nix-darwin (modules/overlays.nix 経由) と Home Manager standalone (flake.nix の
# homeManagerConfiguration の pkgs= に直接渡す) の両方から共有される single source。
{ inputs }:

[
  # neovim を stable から nightly に置換
  inputs.neovim-nightly-overlay.overlays.default
  # vite-plus (nixpkgs 未収録) を pkgs.vite-plus として追加
  inputs.nix-vite-plus.overlays.default
]
