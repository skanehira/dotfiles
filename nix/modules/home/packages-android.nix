{ pkgs, ... }:

# Android (Termux + proot-distro Debian) 用のパッケージ集合。
# packages.nix (フルセット) とは意図的に別リストにする。proot は
# (1) RAM が数 GB で nodejs 等のローカルビルドが OOM で落ちる
# (2) ストレージが Termux のアプリ内領域に載る
# (3) 評価もビルドも遅い
# ため、「binary cache から fetch できる軽量なものだけ」を明示列挙する方針。
# 増やすときは cache.nixos.org に無いもの (flake input のツール類・neovim
# nightly・自前 derivation) を入れないこと。
let
  # 要件そのもの。git / gh は programs.git / programs.gh が入れるのでここには書かない
  core = with pkgs; [
    nodejs_24
    pnpm
    opencode # ターミナル用コーディングエージェント (Claude Code は claude.nix が bootstrap)
  ];

  # 共有設定 (zsh / tmux / neovim) が参照するので、無いと設定が壊れるもの
  sharedConfigDeps = with pkgs; [
    # neovim は nixpkgs の stable release。packages.nix の nightly overlay は
    # binary cache が無く proot でビルドできない
    neovim
    tmux
    ghq # zsh/functions/ghq-fzf.zsh
    nh # zsh.nix の hms alias
    tirith # zsh.nix の initContent が `tirith init --shell zsh` を無条件で eval する
    tree-sitter # nvim-treesitter main が parser compile に要求
  ];

  # 日常的に使う軽量 CLI
  modernCli = with pkgs; [
    bat
    fd
    jq
    lsd
    ripgrep
    tree
  ];

  # LSP は cache がある軽量なものだけ。clang-tools 等の大物は入れない
  lspServers = with pkgs; [
    typescript-go # tsgo
    lua-language-server # lua_ls
    nixd # nixd
  ];
in
{
  home.packages = core ++ sharedConfigDeps ++ modernCli ++ lspServers;
}
