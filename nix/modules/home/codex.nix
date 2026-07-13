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
