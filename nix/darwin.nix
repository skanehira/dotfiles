{ ... }:

{
  imports = [
    ./modules/darwin/homebrew.nix
    ./modules/darwin/system.nix
    ./modules/darwin/sleepctl.nix
    ./modules/darwin/codex.nix
    ./modules/darwin/agent-loop.nix
  ];
}
