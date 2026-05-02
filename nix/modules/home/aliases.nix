{ username, ... }:

{
  programs.zsh.shellAliases = {
    # nix-darwin
    # noglob を前置して zsh の EXTENDED_GLOB が flake URL の `#` をグロブと
    # 解釈するのを防ぐ (`nix#user` が "nix の繰り返し + user" として展開されエラーになる)
    drs = "noglob sudo darwin-rebuild switch --flake ~/dev/github.com/skanehira/dotfiles/nix#${username}";
    # git
    g = "git";
    gs = "git status";
    gl = "git log";
    lg = "lazygit";
    # ls
    ls = "lsd";
    ll = "lsd -la";
    # editor
    v = "nvim";
    # k8s
    k = "kubectl";
    # docker
    d = "docker compose";
    # terraform
    t = "terraform";
    # rust
    c = "cargo";
    crun = "cargo run --quiet";
    # claude
    ccc = "claude";
  };
}
