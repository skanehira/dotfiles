{ username, ... }:

# Linux (Home Manager standalone) 用のエントリポイント。
# 共通 base (home.nix) に Linux 用の home path を足す。
# karabiner は mac 専用なので import しない。
{
  imports = [
    ./home.nix
  ];

  home.username = username;
  home.homeDirectory = "/home/${username}";
}
