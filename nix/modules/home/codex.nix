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

  # スキルの配布先は `~/.agents/skills/`。Codex と OpenCode の両方がここを直接読む
  # (実測: 同じスキルが Codex の $skill 起動と `opencode agent list` の双方に出る)。
  # Codex の公式ドキュメントが user scope として挙げるのもこのパスで、旧来使っていた
  # `$CODEX_HOME/skills` はソースコメントが deprecated と呼ぶ。
  #
  # ~/.agents/skills/ には他ツール (vercel の skills CLI 等) が入れた実体も同居するため、
  # ディレクトリ全体の symlink はできない。agents/skills/ 配下の各スキルだけを個別 symlink し、
  # 削除されたスキルの残骸は prune する。同名の実体があるときは上書きせず警告する
  # (`ln -sfn` は既存ディレクトリの *中* にリンクを作ってしまうため)。
  home.activation.linkAgentSkills = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    agent_skills_dir="$HOME/.agents/skills"
    src_skills_dir="${dotfilesRoot}/agents/skills"

    run mkdir -p "$agent_skills_dir"

    if [ -d "$src_skills_dir" ]; then
      for skill_path in "$src_skills_dir"/*/; do
        [ -d "$skill_path" ] || continue
        skill_name="$(basename "$skill_path")"
        dest="$agent_skills_dir/$skill_name"
        if [ -e "$dest" ] && [ ! -L "$dest" ]; then
          warnEcho "skipping $dest: 同名の実体があるため symlink を張らない (手で退避してから再実行する)"
          continue
        fi
        run ln -sfn "$skill_path" "$dest"
      done
    fi

    for link in "$agent_skills_dir"/*; do
      [ -L "$link" ] || continue
      target="$(readlink "$link")"
      case "$target" in
        "$src_skills_dir"/*)
          [ -e "$link" ] || run rm -f "$link"
          ;;
      esac
    done

    # 旧配布先 (~/.codex/skills) に残った dotfiles 由来の symlink を撤去する。
    # 残すと Codex が同じスキルを 2 回列挙する (同名スキルはマージされない仕様)。
    # 改名前の claude/skills/ を指すリンクも対象にする (このディレクトリはもう存在しない)。
    codex_skills_dir="$HOME/.codex/skills"
    if [ -d "$codex_skills_dir" ]; then
      for link in "$codex_skills_dir"/*; do
        [ -L "$link" ] || continue
        target="$(readlink "$link")"
        case "$target" in
          "$src_skills_dir"/* | "${dotfilesRoot}"/claude/skills/*)
            run rm -f "$link"
            ;;
        esac
      done
    fi
  '';

  home.file = {
    ".codex/AGENTS.md".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/codex/AGENTS.md";
  };
}
