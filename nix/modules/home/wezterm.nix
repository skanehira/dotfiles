{ config, dotfilesRoot, ... }:

{
  programs.wezterm = {
    enable = true;

    # シェル統合は明示的に無効 (現状の挙動を維持)
    enableBashIntegration = false;
    enableZshIntegration = false;

    # extraConfig は使わない。lua は dotfiles から直接 symlink して live edit 可能にする
    # (programs.wezterm の他のオプションを活かすため enable 自体は維持)
  };

  # wezterm.lua を dotfiles へ直接 symlink (mkOutOfStoreSymlink)
  # → 編集が drs 不要で即反映 (live edit)。neovim.nix / claude.nix と同じ方針
  home.file.".config/wezterm/wezterm.lua".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/wezterm/wezterm.lua";
}
