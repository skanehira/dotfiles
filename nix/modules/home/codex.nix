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

  # ハーネスを Codex の語彙でコンパイルして配る。subagent は書式変換も要る
  # (Claude は Markdown + frontmatter、Codex は TOML)。生成物は git 管理しない。
  #
  # スキルの配布先を ~/.agents/skills から ~/.codex/skills (skill root r0) へ移したのは、
  # ~/.agents/skills を OpenCode も探索し、どちらも探索を止める手段が無いため (実測:
  # OpenCode の skills.paths は追加専用、Codex の skip_host_skill_discovery は roots を
  # 変えない)。同じディレクトリにランタイム別の生成物は置けない。
  #
  # 旧 symlink の撤去 (linkGeneration) より後に走らせる。先に走ると生成物を旧 symlink
  # 越しに正本へ書き込んでしまう (生成器側でも出力先を検査して例外にしている)。
  home.activation.buildCodexHarness = lib.hm.dag.entryAfter [ "linkGeneration" "bootstrapDeno" ] ''
    if [ ! -x "$HOME/.deno/bin/deno" ]; then
      warnEcho "deno が無いので Codex 向けハーネスの生成をスキップした"
    else
      run "$HOME/.deno/bin/deno" run --allow-read --allow-write --allow-env \
        "${dotfilesRoot}/agents/scripts/build-harness.ts" --runtime codex \
        --dotfiles-root "${dotfilesRoot}" --vocabulary "${dotfilesRoot}/agents/vocabulary.json" \
        --base "${dotfilesRoot}/agents/rules" \
        --overlay "${dotfilesRoot}/agents/bindings/codex/overlay/rules" \
        --out "$HOME/.agents/rules/codex"
      run "$HOME/.deno/bin/deno" run --allow-read --allow-write --allow-env \
        "${dotfilesRoot}/agents/scripts/build-harness.ts" --runtime codex \
        --dotfiles-root "${dotfilesRoot}" --vocabulary "${dotfilesRoot}/agents/vocabulary.json" \
        --base "${dotfilesRoot}/agents/skills" \
        --overlay "${dotfilesRoot}/agents/bindings/codex/overlay/skills" \
        --out "$HOME/.codex/skills"
      run "$HOME/.deno/bin/deno" run --allow-read --allow-write --allow-env \
        "${dotfilesRoot}/agents/scripts/build-harness.ts" --runtime codex \
        --dotfiles-root "${dotfilesRoot}" --vocabulary "${dotfilesRoot}/agents/vocabulary.json" \
        --base "${dotfilesRoot}/agents/subagents" \
        --overlay "${dotfilesRoot}/agents/bindings/codex/overlay/subagents" \
        --out "$HOME/.codex/agents" --subagent-format codex
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

  home.file = {
    ".codex/AGENTS.md".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/agents/bindings/codex/AGENTS.md";
  };
}
