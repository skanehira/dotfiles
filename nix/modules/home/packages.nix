{ lib, pkgs, ... }:

let
  # 言語ランタイム / コンパイラ (バージョンは明示ピン)
  languageRuntimes = with pkgs; [
    bun
    go_1_26
    nodejs_24
    uv
    zig
  ];

  # パッケージマネージャ
  packageManagers = with pkgs; [
    cargo-binstall
    pnpm_10
    yarn  # classic 1.22.x（後継は yarn-berry）
  ];

  # Build / 開発ライブラリ
  buildTools = with pkgs; [
    cmake
    libpq          # PostgreSQL client library
    luarocks
    pkg-config
    sqlc
  ] ++ lib.optionals pkgs.stdenv.isDarwin [
    # ryoppippi/nix-vite-plus overlay (vp コマンド)。aarch64-linux では installCheckPhase
    # で SIGABRT になり build 失敗 (上流側の問題)。Linux 対応が必要になったら overlay 側
    # の修正か doCheck=false の wrap を検討
    vite-plus
  ];

  # Lint / Format
  linters = with pkgs; [
    actionlint
    golangci-lint
    luaPackages.luacheck
    reviewdog
    shellcheck
    stylua
  ];

  # Git / GitHub Actions
  gitTools = with pkgs; [
    act            # GitHub Actions ローカル実行
    difftastic
    gh
    ghq
    git-filter-repo
    pinact         # GitHub Actions の SHA pin
  ];

  # クラウド / インフラ
  cloudTools = with pkgs; [
    awscli2
    k9s
    kubernetes-helm
    supabase-cli
    terraform
  ];

  # ネットワーク / API
  networkTools = with pkgs; [
    grpcurl
    jwt-cli
    websocat
  ];

  # モダン CLI
  modernCli = with pkgs; [
    bat
    dua
    duckdb
    htop
    jq
    lsd
    tree
    yazi
    just           # コマンドランナー
  ];

  # メディア / ファイル
  mediaTools = with pkgs; [
    ffmpeg
    libsixel       # SIXEL 画像プロトコル
    poppler        # PDF レンダリング
  ];

  # エディタ / TUI
  editors = with pkgs; [
    neovim         # nightly overlay 経由で master を取得
    slides         # markdown TUI presentation
  ];

  # システムユーティリティ
  systemUtils = with pkgs; [
    gnupg
    graphviz
    rclone
  ] ++ lib.optionals pkgs.stdenv.isDarwin [
    terminal-notifier  # macOS notification API。Linux では notify.ts 側で no-op
  ];

  # LSP servers (Mason 廃止、全て Nix declarative 管理)。
  # vim/lua/plugins/lsp/lspconfig.lua の vim.lsp.enable(servers) で起動される。
  # mason の名前 → nixpkgs attr の対応は CLAUDE.md 参照。
  lspServers = with pkgs; [
    typescript-language-server          # ts_ls
    vue-language-server                 # vue_ls
    lua-language-server                 # lua_ls
    vscode-langservers-extracted        # eslint + jsonls (1 パッケージで両方提供)
    graphql-language-service-cli        # graphql (graphql-lsp バイナリ)
    bash-language-server                # bashls
    yaml-language-server                # yamlls
    vim-language-server                 # vimls
    marksman                            # marksman (markdown)
    taplo                               # taplo (TOML)
    clang-tools                         # clangd 同梱
    terraform-ls                        # terraformls
    biome                               # biome
    oxlint                              # oxlint
    zls                                 # zls (Zig)
    regols                              # regols (OPA Rego)
    gopls                               # gopls
    buf                                 # buf_ls (`buf beta lsp`)
    rust-analyzer                       # rust_analyzer
  ];
in
{
  # HM module 経由で導入されているもの (ここには書かない):
  # - programs.direnv.enable      → direnv + nix-direnv
  # - programs.fzf.enable         → fzf
  # - programs.zsh.autosuggestion → zsh-autosuggestions
  home.packages =
    languageRuntimes
    ++ packageManagers
    ++ buildTools
    ++ linters
    ++ gitTools
    ++ cloudTools
    ++ networkTools
    ++ modernCli
    ++ mediaTools
    ++ editors
    ++ systemUtils
    ++ lspServers;
}
