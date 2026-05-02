{ lib, pkgs, ... }:

let
  # jimeh/tmux-themepack は nixpkgs に無いので mkTmuxPlugin で取り込む
  # 最後の master commit (2019-12-22) で固定
  themepack = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "themepack";
    rtpFilePath = "themepack.tmux";
    version = "unstable-2019-12-22";
    src = pkgs.fetchFromGitHub {
      owner = "jimeh";
      repo = "tmux-themepack";
      rev = "7c59902f64dcd7ea356e891274b21144d1ea5948";
      hash = "sha256-c5EGBrKcrqHWTKpCEhxYfxPeERFrbTuDfcQhsUAbic4=";
    };
  };
in
{
  programs.tmux = {
    enable = true;
    prefix = "C-s";
    terminal = "xterm-256color";
    escapeTime = 1;
    baseIndex = 1;
    keyMode = "vi";

    # h/j/k/l でペイン移動、H/J/K/L でリサイズ (-r) を HM が提供
    customPaneNavigationAndResize = true;

    plugins = [
      { plugin = pkgs.tmuxPlugins.resurrect; }
      {
        plugin = themepack;
        extraConfig = ''
          set -g @themepack 'powerline/double/blue'
          set -g @themepack-status-left-area-middle-format "#(basename #{pane_current_path})"
          set -g @themepack-status-left-area-right-format "#(cd #{pane_current_path}; git rev-parse --abbrev-ref HEAD)"
          set -g @themepack-status-right-area-middle-format "%Y/%m/%d"
        '';
      }
    ];

    # tmux/tmux.conf 本体 + プラットフォーム別 conf を Nix 評価時に連結
    extraConfig =
      builtins.readFile ../../../tmux/tmux.conf
      + lib.optionalString pkgs.stdenv.isDarwin (builtins.readFile ../../../tmux/tmux.conf.mac)
      + lib.optionalString pkgs.stdenv.isLinux  (builtins.readFile ../../../tmux/tmux.conf.linux);
  };
}
