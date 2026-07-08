{
  config,
  lib,
  pkgs,
  dotfilesRoot,
  ...
}:

{
  # ~/.codex/config.toml contains mutable local project trust state, so it is
  # generated from the tracked base file instead of being symlinked directly.
  home.activation.mergeCodexConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    config_file="$HOME/.codex/config.toml"

    run ${pkgs.python3}/bin/python3 \
      "${dotfilesRoot}/codex/scripts/merge-config.py" \
      "${dotfilesRoot}/codex/config.base.toml" \
      "$config_file"
  '';

  home.file = {
    ".codex/AGENTS.md".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/codex/AGENTS.md";
  };
}
