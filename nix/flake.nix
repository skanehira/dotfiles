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
    neovim-nightly-overlay = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-vite-plus.url = "github:ryoppippi/nix-vite-plus";
    version-lsp = {
      url = "github:skanehira/version-lsp";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ nixpkgs, home-manager, nix-darwin, ... }:
    let
      # マシン共通の所有者名。複数 mac で同じ設定が走る前提で固定
      # (将来 user 変更時はここ 1 箇所のみ書き換え)
      username = "skanehira";

      # Linux 側 (Home Manager standalone) のエントリビルダ。
      # nix-darwin と違い HM standalone は module system 経由で nixpkgs.overlays /
      # nixpkgs.config を設定できないので、import nixpkgs に直接渡す。
      # overlays は modules/overlays-list.nix で nix-darwin と共有。
      mkLinuxHome = system: home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          inherit system;
          overlays = import ./modules/overlays-list.nix { inherit inputs; };
          config.allowUnfreePredicate = pkg:
            builtins.elem (nixpkgs.lib.getName pkg) [ "terraform" ];
        };
        extraSpecialArgs = { inherit username inputs; };
        modules = [ ./home-linux.nix ];
      };
    in {
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
            home-manager.extraSpecialArgs = { inherit username inputs; };
            home-manager.users.${username} = import ./home-darwin.nix;
          }
        ];
      };

      # Home Manager standalone (非 NixOS Linux 想定。Ubuntu/Arch 等)
      # 使い方: nix run home-manager/master -- switch --flake .#skanehira
      homeConfigurations = {
        "${username}"          = mkLinuxHome "x86_64-linux";
        "${username}-aarch64"  = mkLinuxHome "aarch64-linux";
      };

      # 自前 derivation (nixpkgs 未収録 LSP)。`packages.nix` からも callPackage で
      # 参照されるが、ここに出すことで `nix build .#tsp-server` 等で個別 build できる
      packages = nixpkgs.lib.genAttrs
        [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ]
        (system:
          let pkgs = import nixpkgs { inherit system; }; in {
            tsp-server                 = pkgs.callPackage ./pkgs/tsp-server.nix {};
            gh-actions-language-server = pkgs.callPackage ./pkgs/gh-actions-language-server.nix {};
          });
    };
}
