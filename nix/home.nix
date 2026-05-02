{ username, ... }:

{
  imports = [
    ./modules/home/aliases.nix
    ./modules/home/direnv.nix
    ./modules/home/env.nix
    ./modules/home/fzf.nix
    ./modules/home/git.nix
    ./modules/home/karabiner.nix
    ./modules/home/packages.nix
    ./modules/home/tmux.nix
    ./modules/home/zsh.nix
  ];

  home.username = username;
  home.homeDirectory = "/Users/${username}";

  # 初回セットアップ時の Home Manager リリース。互換性維持のため変更しない
  home.stateVersion = "25.05";

  programs.home-manager.enable = true;
}
