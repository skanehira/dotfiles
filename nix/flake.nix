{
  description = "skanehira's macOS configuration (nix-darwin + Home Manager)";

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
  };

  outputs = inputs@{ nixpkgs, home-manager, nix-darwin, ... }:
    let
      # マシン共通の所有者名。複数 mac で同じ設定が走る前提で固定
      # (将来 user 変更時はここ 1 箇所のみ書き換え)
      username = "skanehira";
      system = "aarch64-darwin";
    in {
      darwinConfigurations.${username} = nix-darwin.lib.darwinSystem {
        inherit system;
        specialArgs = { inherit username inputs; };
        modules = [
          ./modules/overlays.nix
          ./darwin.nix
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit username; };
            home-manager.users.${username} = import ./home.nix;
          }
        ];
      };
    };
}
