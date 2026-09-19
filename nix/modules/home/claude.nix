{
  config,
  lib,
  pkgs,
  dotfilesRoot,
  ...
}:

{
  # Bootstrap install: ~/.local/bin/claude が無い時のみ Anthropic 公式インストーラを実行
  # 既存マシンでは no-op、新規マシンでは drs 一発で claude がセットアップされる
  # 以後の更新は `claude update` の self-update に任せる (Nix で version pin しない方針)
  #
  # claude.ai/install.sh は downloads.claude.ai/claude-code-releases/bootstrap.sh に
  # リダイレクトされる Anthropic 公式の bootstrap スクリプト。
  # PATH に curl を載せておかないと、install.sh が内部で curl/wget を再帰的に呼ぶ際に
  # 「Either curl or wget is required」で落ちる (Linux の HM activation は PATH が最小)
  home.activation.bootstrapClaudeCode = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -x "$HOME/.local/bin/claude" ]; then
      echo "Bootstrapping Claude Code..." >&2
      run sh -c 'export PATH=${pkgs.curl}/bin:$PATH && ${pkgs.curl}/bin/curl -fsSL https://claude.ai/install.sh | bash'
    fi
  '';

  # グローバル指示 / ルール / スキル / subagent も正本 agents/ への直接 symlink。
  # 以前はランタイムごとに語彙をコンパイルして配っていたが、正本の語彙を Claude 綴りに
  # 確定し、Codex は同じ実体を読んで読み替える方式 (agents/bindings/codex/AGENTS.md) に
  # 変えたため symlink に戻した。
  #
  # 直接 symlink (mkOutOfStoreSymlink) にしているのは live edit のため。通常の
  # home.file.X.source = ./path だと /nix/store にコピーされ drs 必須になる。
  home.file = {
    ".claude/CLAUDE.md".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/agents/AGENTS.md";
    ".claude/rules".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/agents/rules";
    ".claude/skills".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/agents/skills";
    # Codex は TOML しか読めない subagent だけ、codex.nix の activation が .toml へ変換する
    ".claude/agents".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/agents/subagents";
    # Claude Code 固有の設定。他ランタイムは読まない
    ".claude/settings.json".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/agents/bindings/claude/settings.json";
    ".claude/keybindings.json".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/agents/bindings/claude/keybindings.json";
    # hooks と scripts は散文ではなくコード。語彙の置換対象が無い
    ".claude/hooks".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/agents/hooks";
    # agent / skill から `~/.claude/scripts/<name>` の形で呼ぶ決定的スクリプト置き場。
    # 検査対象は dotfiles とは別のリポジトリなので、repo 相対では解決できない
    ".claude/scripts".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/agents/scripts";
    # utility-doc-reading が読み書きする。生成物にすると書き込みが毎回上書きされる
    ".claude/knowledge-profile.md".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/agents/knowledge-profile.md";
  };
}
