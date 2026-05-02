{ config, ... }:

let
  # dotfiles repo の絶対 path。mkOutOfStoreSymlink は Nix 評価時の path ではなく
  # 実機の path を要求するため $HOME ベースで構築する
  dotfiles = "${config.home.homeDirectory}/dev/github.com/skanehira/dotfiles";
in
{
  # Neovim 本体は packages.nix の `neovim` (neovim-nightly-overlay 経由) で管理
  # 設定ファイルは dotfiles repo へ直接 symlink (mkOutOfStoreSymlink)
  # → vim/lua/* の編集が drs 不要で即反映 (live edit)
  # lazy.nvim はそのまま動作 (HM の plugins 機構は使わない)
  home.file = {
    ".config/nvim/init.lua".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/vim/init.lua";
    ".config/nvim/lua".source      = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/vim/lua";
    ".config/nvim/after".source    = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/vim/after";
  };
}
