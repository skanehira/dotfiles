{ config, dotfilesRoot, ... }:

{
  # Neovim 本体は packages.nix の `neovim` (nixpkgs-unstable の stable release) で管理
  # 設定ファイルは dotfiles repo へ直接 symlink (mkOutOfStoreSymlink)
  # → vim/lua/* の編集が drs 不要で即反映 (live edit)
  # lazy.nvim はそのまま動作 (HM の plugins 機構は使わない)
  home.file = {
    ".config/nvim/init.lua".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/vim/init.lua";
    ".config/nvim/lua".source      = config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/vim/lua";
    ".config/nvim/after".source    = config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/vim/after";
  };
}
