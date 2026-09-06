{ config, ... }:

# 全プロファイル (darwin / 通常 Linux / Android) に共通する Home Manager の土台。
# module の import は含めない。「どのツールを入れるか」はプロファイル側
# (home.nix / home-android.nix) の決定であり、ここは HM 自体の前提だけを持つ。
{
  # dotfiles repo の絶対 path を全モジュールで共有する。
  # mkOutOfStoreSymlink は Nix 評価時の path ではなく実機の絶対 path を要求するため
  # $HOME ベースで構築する。home-darwin.nix / home-linux.nix / home-android.nix を
  # 経由して karabiner.nix / wezterm.nix からも参照可能。
  _module.args.dotfilesRoot = "${config.home.homeDirectory}/dev/github.com/skanehira/dotfiles";

  # 初回セットアップ時の Home Manager リリース。互換性維持のため変更しない
  home.stateVersion = "25.05";

  programs.home-manager.enable = true;
}
