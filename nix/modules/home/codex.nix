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

  # ~/.codex/skills/ also holds Codex CLI-managed content (skill-installer 導入分、
  # .system/ の組み込みスキル) なので、~/.claude/skills 同様のディレクトリ全体 symlink はできない。
  # claude/skills/ 配下の各スキルだけを個別 symlink し、削除されたスキルの残骸は prune する。
  home.activation.linkCodexSkills = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    codex_skills_dir="$HOME/.codex/skills"
    claude_skills_dir="${dotfilesRoot}/claude/skills"

    run mkdir -p "$codex_skills_dir"

    if [ -d "$claude_skills_dir" ]; then
      for skill_path in "$claude_skills_dir"/*/; do
        [ -d "$skill_path" ] || continue
        skill_name="$(basename "$skill_path")"
        run ln -sfn "$skill_path" "$codex_skills_dir/$skill_name"
      done
    fi

    for link in "$codex_skills_dir"/*; do
      [ -L "$link" ] || continue
      target="$(readlink "$link")"
      case "$target" in
        "$claude_skills_dir"/*)
          [ -e "$link" ] || run rm -f "$link"
          ;;
      esac
    done
  '';

  home.file = {
    ".codex/AGENTS.md".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/codex/AGENTS.md";
  };
}
