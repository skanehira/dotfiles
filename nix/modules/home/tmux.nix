{ config, pkgs, dotfilesRoot, ... }:

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
  # tmux 本体は packages.nix で導入する。
  # 設定ファイルは dotfiles repo へ直接 symlink (mkOutOfStoreSymlink)
  # → tmux/tmux.conf の編集が drs 不要で即反映 (live edit)。
  # プラグインの run-shell 行だけは nix store path を要するため、
  # plugins.conf として Nix 側で生成し tmux.conf 末尾から source-file で読み込む。
  home.file = {
    ".config/tmux/tmux.conf".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/tmux/tmux.conf";

    ".config/tmux/plugins.conf".text = ''
      run-shell ${pkgs.tmuxPlugins.resurrect.rtp}
      run-shell ${themepack.rtp}
    '';
  };
}
