{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # === 言語ランタイム / コンパイラ (バージョンは明示ピン) ===
    bun
    go_1_26
    nodejs_24
    uv
    zig

    # === パッケージマネージャ ===
    cargo-binstall
    pnpm_10
    yarn  # classic 1.22.x（後継は yarn-berry）

    # === Build / 開発ライブラリ ===
    cmake
    libpq          # PostgreSQL client library
    luarocks
    pkg-config
    sqlc
    vite-plus      # ryoppippi/nix-vite-plus overlay (vp コマンド)

    # === Lint / Format ===
    actionlint
    golangci-lint
    luaPackages.luacheck
    reviewdog
    shellcheck
    stylua

    # === Git / GitHub Actions ===
    act            # GitHub Actions ローカル実行
    difftastic
    gh
    ghq
    git-filter-repo
    pinact         # GitHub Actions の SHA pin

    # === クラウド / インフラ ===
    awscli2
    k9s
    kubernetes-helm
    supabase-cli
    terraform

    # === ネットワーク / API ===
    grpcurl
    jwt-cli
    websocat

    # === モダン CLI ===
    bat
    dua
    duckdb
    htop
    jq
    lsd
    tree
    yazi

    # === メディア / ファイル ===
    ffmpeg
    libsixel       # SIXEL 画像プロトコル
    poppler        # PDF レンダリング

    # === エディタ / TUI ===
    neovim         # nightly overlay 経由で master を取得
    slides         # markdown TUI presentation

    # === システムユーティリティ ===
    gnupg
    graphviz
    just           # コマンドランナー
    rclone
    terminal-notifier

    # === HM module で導入済 (リスト不要) ===
    # programs.direnv.enable      — direnv + nix-direnv
    # programs.fzf.enable         — fzf
    # programs.zsh.autosuggestion — zsh-autosuggestions
  ];
}
