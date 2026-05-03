{ username, ... }:

# macOS 用の Home Manager エントリポイント。
# 共通 base (home.nix) に、mac 専用 module と darwin 用の home path を足す。
{
  imports = [
    ./home.nix
    ./modules/home/karabiner.nix
    ./modules/home/wezterm.nix
  ];

  home.username = username;
  home.homeDirectory = "/Users/${username}";
}
