{
  config,
  lib,
  dotfilesRoot,
  ...
}:

# herdr 設定。~/.config/herdr/config.toml へ mkOutOfStoreSymlink で symlink し
# 編集即反映 (drs 不要)。herdr 本体は packages.nix (flake input) で導入済み。
{
  home.file.".config/herdr/config.toml".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/herdr/config.toml";

  # プラグインは宣言的に管理できない (実測: config.toml は plugin_action で参照するだけで
  # インストール手段が無く、`herdr --default-config` にも plugin セクションが無い。HM の
  # programs.herdr も enable/package/settings のみ)。`herdr plugin install` が唯一の非対話
  # 導入経路で、stdin が非対話のときは --yes が必須 ("remote plugin install requires --yes
  # when stdin is not interactive")。
  # 導入済みなら skip する (再 install は documented な refresh 経路 = 再ダウンロードに
  # なるため)。ネットワーク断などで失敗しても activation は止めない (codex.nix と同じ扱い)。
  home.activation.installHerdrPlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if ! command -v herdr >/dev/null 2>&1; then
      warnEcho "herdr が無いのでプラグインの導入をスキップした"
    else
      for entry in \
        persiyanov.reviewr:persiyanov/herdr-reviewr \
        chmarax.herdr-nvim:ChmaraX/herdr-nvim
      do
        plugin_id="''${entry%%:*}"
        repo="''${entry#*:}"
        if herdr plugin list --plugin "$plugin_id" 2>/dev/null | grep -qF "$plugin_id"; then
          continue
        fi
        run herdr plugin install "$repo" --yes \
          || warnEcho "herdr plugin install $repo に失敗した (ネットワーク断など)"
      done
    fi
  '';
}
