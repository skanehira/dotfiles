# nixpkgs に対する変更（既存パッケージの上書き / 新規パッケージ追加）を集約。
# overlays は「pkgs 集合を入力 → 変更後の集合を返す関数」の集まり。
# このモジュールは nix-darwin と home-manager 両方の pkgs を共有設定する。
{ inputs, ... }:

{
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (inputs.nixpkgs.lib.getName pkg) [ "terraform" ];

  nixpkgs.overlays = [
    # neovim を stable から nightly に置換
    inputs.neovim-nightly-overlay.overlays.default
    # vite-plus (nixpkgs 未収録) を pkgs.vite-plus として追加
    inputs.nix-vite-plus.overlays.default
  ];
}
