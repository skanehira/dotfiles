{
  config,
  lib,
  pkgs,
  dotfilesRoot,
  ...
}:

{
  # Codex の共通設定は /etc/codex/config.toml (system レイヤー) に置く。~/.codex/config.toml は
  # Codex 自身が書く可変状態 (project trust / notices 等) に明け渡すので HM では触らない。
  # mac は nix-darwin の environment.etc (modules/darwin/codex.nix) が張る。Home Manager standalone
  # の Linux には /etc を宣言する option が無いので、activation 内で sudo により symlink を張る。
  home.activation.linkCodexSystemConfig = lib.mkIf pkgs.stdenv.hostPlatform.isLinux (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      codex_system_config="/etc/codex/config.toml"
      codex_config_src="${dotfilesRoot}/codex/config.toml"

      if [ "$(readlink "$codex_system_config" 2>/dev/null)" != "$codex_config_src" ]; then
        if command -v sudo >/dev/null 2>&1 \
          && run sudo mkdir -p /etc/codex \
          && run sudo ln -sfn "$codex_config_src" "$codex_system_config"; then
          :
        else
          warnEcho "could not link $codex_system_config; run manually:"
          warnEcho "  sudo mkdir -p /etc/codex && sudo ln -sfn \"$codex_config_src\" \"$codex_system_config\""
        fi
      fi
    ''
  );

  # subagent は書式変換が避けられない (Claude は Markdown + frontmatter、Codex は TOML)。
  # 正本 agents/subagents/*.md から ~/.codex/agents/*.toml を生成する。生成物は
  # git 管理せず、正本から消えた subagent の .toml はスクリプト側が撤去する。
  # deno を使うので bootstrapDeno の後に置く。
  home.activation.syncCodexSubagents = lib.hm.dag.entryAfter [ "bootstrapDeno" ] ''
    if [ -x "$HOME/.deno/bin/deno" ]; then
      run "$HOME/.deno/bin/deno" run --allow-read --allow-write \
        "${dotfilesRoot}/agents/scripts/sync-subagents.ts" \
        "${dotfilesRoot}/agents/subagents" codex "$HOME/.codex/agents"
    else
      warnEcho "deno が無いので ~/.codex/agents の生成をスキップした"
    fi
  '';

  home.file = {
    ".codex/AGENTS.md".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/codex/AGENTS.md";
  };
}
