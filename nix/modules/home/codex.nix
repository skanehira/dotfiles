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
      codex_config_src="${dotfilesRoot}/agents/bindings/codex/config.toml"

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

  # グローバル指示は Codex 専用の文書を symlink で配る。共通の正本 agents/AGENTS.md を
  # 参照し、Claude 綴りの語彙を Codex の語彙へ読み替える規約を書いてある。
  home.file.".codex/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/agents/bindings/codex/AGENTS.md";

  # スキルは Claude と同一の正本を ~/.agents/skills/<name> へ個別 symlink する。Codex は
  # skill root r0 (~/.codex/skills) と r1 (~/.agents/skills) の両方を探索し、symlink を
  # 追跡する (実測: セッションログの `### Skill roots`)。r1 を使うのは他ツールが入れた
  # スキルと同居させるためで、ディレクトリごとの symlink は使えない。
  #
  # claude 専用スキルは除外する。以前は SKILL.md の metadata.runtimes を生成器が読んで
  # いたが、生成をやめたのでこのリストが唯一の宣言になる。
  #
  # ~/.codex/skills に残る dotfiles 由来の symlink は撤去する。残すと同じスキルが r0 と
  # r1 の両方に現れる (Codex は同名スキルをマージしない)。
  home.activation.linkAgentSkills = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    agent_skills_dir="$HOME/.agents/skills"
    src_skills_dir="${dotfilesRoot}/agents/skills"
    # utility-session-profile: Claude Code のセッションログしか読まない
    # synced: Claude Code が marketplace から同期するキャッシュ (SKILL.md を直下に持たず
    #         Codex のスキルとしては機能しない)。.gitignore 済みだがディレクトリは実在する
    claude_only_skills="utility-session-profile synced"

    run mkdir -p "$agent_skills_dir"

    for skill_path in "$src_skills_dir"/*/; do
      [ -d "$skill_path" ] || continue
      skill_name="$(basename "$skill_path")"
      case " $claude_only_skills " in
        *" $skill_name "*) continue ;;
      esac
      dest="$agent_skills_dir/$skill_name"
      if [ -e "$dest" ] && [ ! -L "$dest" ]; then
        warnEcho "skipping $dest: 同名の実体があるため symlink を張らない (手で退避してから再実行する)"
        continue
      fi
      run ln -sfn "$skill_path" "$dest"
    done

    for link in "$agent_skills_dir"/*; do
      [ -L "$link" ] || continue
      target="$(readlink "$link")"
      case "$target" in
        "$src_skills_dir"/*)
          skill_name="$(basename "$link")"
          # リンク切れに加えて、除外リストに入ったスキルの既存 symlink も外す
          # (リストを変えたときに古いリンクが残らないようにする)
          stale=0
          [ -e "$link" ] || stale=1
          case " $claude_only_skills " in
            *" $skill_name "*) stale=1 ;;
          esac
          if [ "$stale" = 1 ]; then
            run rm -f "$link"
          fi
          ;;
      esac
    done

    codex_skills_dir="$HOME/.codex/skills"
    if [ -d "$codex_skills_dir" ]; then
      for link in "$codex_skills_dir"/*; do
        [ -L "$link" ] || continue
        target="$(readlink "$link")"
        case "$target" in
          "$src_skills_dir"/*) run rm -f "$link" ;;
        esac
      done
    fi
  '';

  # subagent だけは symlink で共有できない (Codex は TOML を要求し、Markdown +
  # frontmatter の正本を読めない)。書式変換の 1 本だけ deno で回す。変換元から消えた
  # .toml はスクリプト側が prune する。deno を使うので bootstrapDeno の後に置く。
  home.activation.syncCodexSubagents = lib.hm.dag.entryAfter [ "bootstrapDeno" ] ''
    if [ -x "$HOME/.deno/bin/deno" ]; then
      run "$HOME/.deno/bin/deno" run --allow-read --allow-write \
        "${dotfilesRoot}/agents/scripts/sync-subagents.ts" \
        "${dotfilesRoot}/agents/subagents" "$HOME/.codex/agents"
    else
      warnEcho "deno が無いので ~/.codex/agents の同期をスキップした"
    fi
  '';

  # プラグインの導入。marketplace もインストールも宣言では効かない (実測: config.toml に
  # [marketplaces.*] を書くと空ディレクトリを見に行って "marketplace root does not contain
  # a supported manifest" で失敗し、[plugins.*] を書いても "not installed" のまま)。
  # `codex plugin marketplace add` がリポジトリを取得し、`codex plugin add` が
  # インストールする。どちらも冪等なので毎回流す。
  #
  # 自分のリポジトリ 2 本は clone 先がマシンごとに変わるのでローカルパスで登録する。
  # いずれも Claude 形式 (.claude-plugin/marketplace.json) だが Codex がそのまま読む。
  # ネットワークやリポジトリの不在で失敗しても activation は止めない。
  home.activation.installCodexPlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if ! command -v codex >/dev/null 2>&1; then
      warnEcho "codex が無いのでプラグインの導入をスキップした"
    else
      for source in \
        anthropics/skills \
        anthropics/claude-plugins-official \
        nextlevelbuilder/ui-ux-pro-max-skill \
        u-ichi/compact-plus
      do
        run codex plugin marketplace add "$source" \
          || warnEcho "codex plugin marketplace add $source に失敗した (ネットワーク断など)"
      done

      for repo in misty-lantern slide-plugin; do
        repo_path="$HOME/dev/github.com/skanehira/$repo"
        [ -d "$repo_path" ] || continue
        run codex plugin marketplace add "$repo_path" \
          || warnEcho "codex plugin marketplace add $repo_path に失敗した"
      done

      for plugin in \
        document-skills@anthropic-agent-skills \
        frontend-design@claude-plugins-official \
        ui-ux-pro-max@ui-ux-pro-max-skill \
        compact-plus@compact-plus \
        archify@misty-lantern \
        slide-plugin@slide-plugin
      do
        run codex plugin add "$plugin" \
          || warnEcho "codex plugin add $plugin に失敗した"
      done
    fi
  '';

}
