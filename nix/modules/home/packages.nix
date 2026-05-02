{ pkgs, ... }:

{
  home.packages = with pkgs; [
    act
    actionlint
    awscli2
    bat
    bun
    cargo-binstall
    cmake
    # 言語ランタイム — バージョンは明示ピン
    go_1_26
    nodejs_24
    pnpm_10
    yarn  # classic 1.22.x（後継は yarn-berry）
    pinact
    poppler
    reviewdog
    supabase-cli
    terraform
    tmux
    uv
    vite-plus  # ryoppippi/nix-vite-plus overlay 経由 (vp コマンド)
    difftastic
    # direnv は programs.direnv.enable で導入
    dua
    duckdb
    ffmpeg
    # fzf は programs.fzf.enable で導入
    gh
    ghq
    git-filter-repo
    golangci-lint
    graphviz
    grpcurl
    htop
    jq
    kubernetes-helm
    libpq
    libsixel
    luarocks
    neovim  # nightly overlay 経由で master を取得
    just
    jwt-cli
    k9s
    lsd
    luaPackages.luacheck
    pkg-config
    rclone
    shellcheck
    slides
    sqlc
    stylua
    terminal-notifier
    tree
    websocat
    yazi
    zig
    # zsh-autosuggestions は programs.zsh.autosuggestion.enable で導入
  ];
}
