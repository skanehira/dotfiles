{
  description = "skanehira's macOS / Linux configuration (nix-darwin + Home Manager)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-vite-plus.url = "github:ryoppippi/nix-vite-plus";
    version-lsp = {
      url = "github:skanehira/version-lsp";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    screen-capture-mcp-server = {
      url = "github:skanehira/screen-capture-mcp-server";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # nix-index の事前生成 DB を毎週取得する HM モジュール + comma を提供。
    # これにより `,` で未インストールの CLI を一時実行できる。
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    google-workspace-cli = {
      url = "github:googleworkspace/cli";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    herdr = {
      url = "github:ogulcancelik/herdr";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      nixpkgs,
      home-manager,
      nix-darwin,
      ...
    }:
    let
      # 既定の所有者名。mac (nix-darwin の primaryUser / users.users /
      # darwinConfigurations のキー) と Linux の名前付き homeConfigurations
      # (skanehira / skanehira-aarch64) がこれを使う。複数 mac で同じ設定が走る前提で固定。
      # 恒久的に所有者名を変える場合のみここを直す。skanehira 以外でも activate したい
      # Linux マシン (CI / 検証箱など) は下の linuxUsers に足す。
      username = "skanehira";

      # Linux (HM standalone) で homeConfigurations を生やすユーザー一覧。
      # $USER を動的に読む impure 方式は nh / home-manager が pure 評価で flake output を
      # 引く (--impure を渡さない) ため `hms` 等で output が見えず壊れる。よって pure に
      # 列挙する。ログインユーザーが skanehira でないマシンはここにそのユーザー名を足す。
      linuxUsers = [
        username
        "ubuntu"
      ];

      # Linux 側 (Home Manager standalone) のエントリビルダ。
      # nix-darwin と違い HM standalone は module system 経由で nixpkgs.overlays /
      # nixpkgs.config を設定できないので、import nixpkgs に直接渡す。
      # overlays は modules/overlays-list.nix で nix-darwin と共有。
      mkLinuxHome =
        { system, username }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            inherit system;
            overlays = import ./modules/overlays-list.nix { inherit inputs; };
            config.allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) [ "terraform" ];
          };
          extraSpecialArgs = { inherit username inputs; };
          modules = [ ./home-linux.nix ];
        };
    in
    {
      darwinConfigurations.${username} = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        specialArgs = { inherit username inputs; };
        modules = [
          ./modules/overlays.nix
          ./darwin.nix
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            # 既存ファイル衝突時に *.hm-backup へ退避してから symlink を張る。
            # 初回 bootstrap で claude/install.sh などが先に置いた dotfiles 直
            # symlink と HM の mkOutOfStoreSymlink が同 path を要求するケースで
            # activation が止まらないようにする
            home-manager.backupFileExtension = "hm-backup";
            home-manager.extraSpecialArgs = { inherit username inputs; };
            home-manager.users.${username} = import ./home-darwin.nix;
          }
        ];
      };

      # Home Manager standalone (非 NixOS Linux 想定。Ubuntu/Arch 等)
      # 使い方: nix run home-manager/master -- switch --flake .#skanehira
      # (別ユーザーは上の linuxUsers に足すと .#<user> / .#<user>-aarch64 が生える)
      homeConfigurations = builtins.listToAttrs (
        builtins.concatMap (u: [
          {
            name = u;
            value = mkLinuxHome {
              system = "x86_64-linux";
              username = u;
            };
          }
          {
            name = "${u}-aarch64";
            value = mkLinuxHome {
              system = "aarch64-linux";
              username = u;
            };
          }
        ]) linuxUsers
      );

      # 自前 derivation (nixpkgs 未収録 LSP)。`packages.nix` からも callPackage で
      # 参照されるが、ここに出すことで `nix build .#tsp-server` 等で個別 build できる
      packages =
        nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ]
          (
            system:
            let
              pkgs = import nixpkgs { inherit system; };
            in
            {
              tsp-server = pkgs.callPackage ./pkgs/tsp-server.nix { };
              gh-actions-language-server = pkgs.callPackage ./pkgs/gh-actions-language-server.nix { };
            }
          );

      # `nix fmt` で呼ばれるフォーマッター。RFC 166 準拠の公式 nixfmt の
      # treefmt ラッパー。引数なし `nix fmt` で repo 内 .nix を再帰的に整形する。
      # (素の nixfmt は stdin 待ちになるため `nix fmt` 単体で使えない)
      formatter = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ] (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
