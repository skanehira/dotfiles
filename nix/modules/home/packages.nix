{
  inputs,
  lib,
  pkgs,
  ...
}:

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
    pnpm
    yarn # classic 1.22.x（後継は yarn-berry）
  ];

  # Build / 開発ライブラリ
  buildTools =
    with pkgs;
    [
      binutils # readelf / objdump / nm / strings 等。Linux ELF 解析にも使う
      cmake
      libpq
      luarocks
      pkg-config
      sqlc
      sqlite # sqlite3 CLI + libsqlite3
      tree-sitter # CLI; nvim-treesitter main が parser compile に要求
      cargo-zigbuild
    ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
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
    nixfmt
    reviewdog
    shellcheck
    stylua
    selene
  ];

  # Git / GitHub Actions
  # gh は programs.gh.enable が pkgs.gh を home.packages に追加するためここでは宣言しない
  gitTools = with pkgs; [
    act
    difftastic
    ghq
    git-filter-repo
    pinact
  ];

  # クラウド / インフラ
  cloudTools =
    with pkgs;
    [
      awscli2
      k9s
      kubernetes-helm
      supabase-cli
      terraform
    ]
    ++ [
      inputs.google-workspace-cli.packages.${pkgs.stdenv.hostPlatform.system}.default # gws (flake input)
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
    ripgrep
    dua
    duckdb
    htop
    nvtopPackages.full # nvtop: GPU モニタ TUI (darwin=Apple GPU / linux=全 GPU backend)
    jq
    lsd
    tree
    just
    tokei
    jnv
    nh # darwin-rebuild / home-manager の上位ラッパー (nom 出力 + diff 表示 + GC 統合)
    nix-sweep
    nix-output-monitor # nom: drs / nix build の進捗を見やすく可視化
    mdbook
    fd
    stripe-cli
  ];

  # メディア / ファイル
  mediaTools = with pkgs; [
    ffmpeg
    ghostscript # gs; PDF の再生成による圧縮 (画像ダウンサンプル + フォント統合)
    libreoffice-bin # pptx/docx のヘッドレス PDF 変換 (スライド視覚 QA 用)
    libsixel # SIXEL 画像プロトコル
    poppler-utils # PDF レンダリング + pdftoppm 等の CLI (lib は poppler-glib を内包)
    qpdf
    yt-dlp
  ];

  # エディタ / TUI
  editors = with pkgs; [
    # neovim HEAD (master) の nightly ビルド (v0.13.0-nightly 系)。binary cache が無く
    # 更新時は手元でビルドする (経緯と実測値は flake.nix の input 定義のコメント)。
    # wrapNeovim されない素の neovim-unwrapped なので python3 / ruby provider は付かない。
    # overlay 経由の pkgs.neovim ではなく packages.default を直参照する (overlay 適用時に
    # treesitter の hash mismatch が起きうると upstream README が注意している)。
    # 更新: nix flake update neovim-nightly-overlay
    inputs.neovim-nightly-overlay.packages.${pkgs.stdenv.hostPlatform.system}.default
    # vime.vim (neovim の日本語 IME プラグイン) が FFI で叩く libanthy。全 OS 共通で nix 管理。
    # nixpkgs の anthy は 9100h だが anthy-unicode と ABI 互換なので vime から使える。
    anthy
    slides # markdown TUI presentation
    tmux # 設定は modules/home/tmux.nix で mkOutOfStoreSymlink により live edit
  ];

  # システムユーティリティ
  systemUtils =
    with pkgs;
    [
      gnupg
      graphviz
      rclone
      tirith # shell security guard (homograph URL / pipe-to-shell 等を実行前にブロック)
    ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
      terminal-notifier # macOS notification API (codex notify で使用)
    ];

  # AI
  aiUtils =
    with pkgs;
    [
      ollama
    ]
    ++ [
      inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default # AI agent multiplexer TUI (flake input)
    ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
      screen-capture-mcp-server # Claude Code 用画面キャプチャ MCP サーバー
    ];

  # LSP servers (Mason 廃止、全て Nix declarative 管理)。
  # vim/lua/plugins/lsp/lspconfig.lua の vim.lsp.enable(servers) で起動される。
  # mason の名前 → nixpkgs attr の対応は CLAUDE.md 参照。
  lspServers =
    with pkgs;
    [
      typescript-go # tsgo (`tsgo --lsp --stdio`)
      lua-language-server # lua_ls
      vscode-langservers-extracted # eslint + jsonls (1 パッケージで両方提供)
      graphql-language-service-cli # graphql (graphql-lsp バイナリ)
      bash-language-server # bashls
      yaml-language-server # yamlls
      vim-language-server # vimls
      marksman # marksman (markdown)
      taplo # taplo (TOML)
      clang-tools # clangd 同梱
      terraform-ls # terraformls
      biome # biome
      oxlint # oxlint
      zls # zls (Zig)
      regols # regols (OPA Rego)
      gopls # gopls
      buf # buf_ls (`buf beta lsp`)
      nixd # nixd (Nix)
    ]
    ++ [
      # nixpkgs 未収録の自前 derivation
      (pkgs.callPackage ../../pkgs/tsp-server.nix { }) # tsp_server
      (pkgs.callPackage ../../pkgs/gh-actions-language-server.nix { }) # gh_actions_ls
      inputs.version-lsp.packages.${pkgs.stdenv.hostPlatform.system}.default # version_ls (flake input)
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
    ++ lspServers
    ++ aiUtils;
}
