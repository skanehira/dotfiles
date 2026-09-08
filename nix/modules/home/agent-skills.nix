{ lib, dotfilesRoot, ... }:

{
  # スキルの配布先は `~/.agents/skills/`。Codex と OpenCode の両方がここを直接読む
  # (実測: 同じスキルが Codex の $skill 起動と `opencode agent list` の双方に出る)。
  # Codex の公式ドキュメントが user scope として挙げるのもこのパスで、旧来使っていた
  # `$CODEX_HOME/skills` はソースコメントが deprecated と呼ぶ。
  #
  # Codex 専用ではないので codex.nix には置かない。Android プロファイルは codex.nix を
  # import しないが OpenCode は使うため、そこに置くと Android でスキルが 1 本も
  # 配られなくなる (env.nix の OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1 と重なると
  # OpenCode から全スキルが消える)。
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
}
