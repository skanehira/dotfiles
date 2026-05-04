{ lib, pkgs, username, dotfilesRoot, ... }:

{
  programs.zsh.shellAliases = {
    # git
    g = "git";
    gs = "git status";
    gl = "git log";
    # ls
    ls = "lsd";
    ll = "lsd -la";
    # editor
    v = "nvim";
    # k8s
    k = "kubectl";
    # terraform
    t = "terraform";
    # rust
    c = "cargo";
  } // lib.optionalAttrs pkgs.stdenv.isDarwin {
    # nix-darwin 切替 (mac)
    # noglob を前置して zsh の EXTENDED_GLOB が flake URL の `#` をグロブと
    # 解釈するのを防ぐ (`nix#user` が "nix の繰り返し + user" として展開されエラーになる)
    drs = "noglob sudo darwin-rebuild switch --flake ${dotfilesRoot}/nix#${username}";
  } // lib.optionalAttrs pkgs.stdenv.isLinux {
    # Home Manager standalone 切替 (Linux)
    hms = "noglob home-manager switch --flake ${dotfilesRoot}/nix#${username}";
  };
}
