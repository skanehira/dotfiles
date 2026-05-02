{ ... }:

{
  programs.wezterm = {
    enable = true;

    # シェル統合は明示的に無効 (現状の挙動を維持)
    enableBashIntegration = false;
    enableZshIntegration = false;

    # Lua は別ファイルで保持し、エディタの lua_ls 補完を活用する
    # 編集後 drs で /nix/store にコピーされ ~/.config/wezterm/wezterm.lua の symlink が更新される
    extraConfig = builtins.readFile ../../../wezterm/wezterm.lua;
  };
}
