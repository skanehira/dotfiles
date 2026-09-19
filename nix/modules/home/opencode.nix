{
  config,
  lib,
  dotfilesRoot,
  ...
}:

{
  # 設定は dotfiles repo への直接 symlink (mkOutOfStoreSymlink) で扱う。
  # claude.nix と同じ方針で、編集が drs 不要で即反映される (live edit)。
  #
  # symlink するのはファイル単位にする。~/.config/opencode/ には opencode 自身が書く領域
  # (skills/ / node_modules / package.json) が同居しており、ディレクトリごと貼ると
  # dotfiles に流れ込むため。
  #
  # baseURL には自宅 LAN の mDNS 名 (spark-head.local) を書いてある。これは素の
  # opencode を打ったときの既定値で、ocsp 経由の起動では ocsp が到達する方
  # (LAN / Tailscale) を選んで OPENCODE_CONFIG_CONTENT で上書きする。
  # IP を書けば接続あたり約 210ms 速いが、このリポジトリは公開なので置かない
  # (IP を使いたいマシンは CCSP_LAN_HOST に入れる)。
  # vLLM が認証を要求しないので API キーは持たない (詳細は
  # agents/rules/infra/dgx-spark.md)。
  home.file.".config/opencode/opencode.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/agents/bindings/opencode/opencode.json";

  # tui.json は keybinds / theme の設定ファイルで、TUI 側の theme 切り替えなど
  # opencode 自身の書き込みも repo 側の working tree に反映される (live edit)。
  home.file.".config/opencode/tui.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/agents/bindings/opencode/tui.json";

  # グローバル指示は OpenCode 専用の文書を symlink で配る。共通の正本 agents/AGENTS.md を
  # 参照し、Claude 綴りの語彙を OpenCode の語彙へ読み替える規約を書いてある。
  #
  # このファイルを置くと ~/.claude/CLAUDE.md は自動では読まれなくなる。OpenCode は
  # ~/.config/opencode/AGENTS.md → ~/.claude/CLAUDE.md の順に探して最初の 1 つで
  # break するため (packages/opencode/src/session/instruction.ts)。配る文書側に
  # 「正本を Read せよ」と書いてあるので、共通ハーネスはそこから届く。
  home.file.".config/opencode/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/agents/bindings/opencode/AGENTS.md";

  # subagent だけは symlink で共有できない (OpenCode は description / mode の別スキーマを
  # 要求し、正本の frontmatter をそのまま読めない)。codex.nix の syncCodexSubagents と
  # 同じスクリプトを opencode 形式で回す。変換元から消えた .md はスクリプト側が prune する。
  # deno を使うので bootstrapDeno の後に置く。
  home.activation.syncOpencodeSubagents = lib.hm.dag.entryAfter [ "bootstrapDeno" ] ''
    if [ -x "$HOME/.deno/bin/deno" ]; then
      run "$HOME/.deno/bin/deno" run --allow-read --allow-write \
        "${dotfilesRoot}/agents/scripts/sync-subagents.ts" \
        "${dotfilesRoot}/agents/subagents" "$HOME/.config/opencode/agents" opencode
    else
      warnEcho "deno が無いので ~/.config/opencode/agents の同期をスキップした"
    fi
  '';
}
