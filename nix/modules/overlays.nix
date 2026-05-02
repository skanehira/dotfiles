# nix-darwin / Home Manager (useGlobalPkgs) 共通の nixpkgs 設定。
# overlay の実体は modules/overlays-list.nix に切り出し、Linux 側 (HM standalone)
# でも `import nixpkgs { overlays = ...; }` で再利用できるようにしてある。
{ inputs, ... }:

{
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (inputs.nixpkgs.lib.getName pkg) [ "terraform" ];

  nixpkgs.overlays = import ./overlays-list.nix { inherit inputs; };
}
