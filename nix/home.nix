{ config, ... }:

# クロスプラットフォームな Home Manager の共通 base。
# karabiner.nix のような macOS 専用 module と、username / homeDirectory の
# プラットフォーム依存値は home-darwin.nix / home-linux.nix で設定する。
{
  imports = [
    ./modules/home/aliases.nix
    ./modules/home/claude.nix
    ./modules/home/deno.nix
    ./modules/home/direnv.nix
    ./modules/home/env.nix
    ./modules/home/fzf.nix
    ./modules/home/git.nix
    ./modules/home/neovim.nix
    ./modules/home/packages.nix
    ./modules/home/rustup.nix
    ./modules/home/tmux.nix
    ./modules/home/zsh.nix
  ];

  # dotfiles repo の絶対 path を全モジュールで共有する。
  # mkOutOfStoreSymlink は Nix 評価時の path ではなく実機の絶対 path を要求するため
  # $HOME ベースで構築する。home-darwin.nix / home-linux.nix を経由して
  # karabiner.nix / wezterm.nix からも参照可能。
  _module.args.dotfilesRoot =
    "${config.home.homeDirectory}/dev/github.com/skanehira/dotfiles";

  # 初回セットアップ時の Home Manager リリース。互換性維持のため変更しない
  home.stateVersion = "25.05";

  programs.home-manager.enable = true;
}
