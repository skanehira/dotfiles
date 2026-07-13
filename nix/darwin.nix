{ ... }:

{
  imports = [
    ./modules/darwin/homebrew.nix
    ./modules/darwin/system.nix
    ./modules/darwin/sleepctl.nix
  ];
}
