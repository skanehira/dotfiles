{
  config,
  dotfilesRoot,
  ...
}:

# herdr 設定。~/.config/herdr/config.toml へ mkOutOfStoreSymlink で symlink し
# 編集即反映 (drs 不要)。herdr 本体は packages.nix (flake input) で導入済み。
{
  home.file.".config/herdr/config.toml".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/herdr/config.toml";
}
