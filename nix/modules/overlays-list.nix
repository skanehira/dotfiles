# nixpkgs に適用する overlay の素のリスト。
# nix-darwin (modules/overlays.nix 経由) と Home Manager standalone (flake.nix の
# homeManagerConfiguration の pkgs= に直接渡す) の両方から共有される single source。
{ inputs }:

[
  # vite-plus (nixpkgs 未収録) を pkgs.vite-plus として追加
  inputs.nix-vite-plus.overlays.default
  # screen-capture-mcp-server (nixpkgs 未収録、darwin only) を pkgs.screen-capture-mcp-server として追加。
  # overlay 自体は darwin かどうかでガードされているため Linux (HM standalone) 評価も安全
  inputs.screen-capture-mcp-server.overlays.default
]
