{ config, dotfilesRoot, ... }:

{
  # 設定は dotfiles repo への直接 symlink (mkOutOfStoreSymlink) で扱う。
  # claude.nix と同じ方針で、編集が drs 不要で即反映される (live edit)。
  #
  # symlink するのは opencode.json と tui.json の 2 枚だけにする。~/.config/opencode/ には
  # opencode 自身が書く領域 (skills/ / node_modules / package.json)
  # が同居しており、ディレクトリごと貼ると dotfiles に流れ込むため。
  # tui.json は keybinds / theme の設定ファイルで、TUI 側の theme 切り替えなど
  # opencode 自身の書き込みも repo 側の working tree に反映される (live edit)。
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

  home.file.".config/opencode/tui.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/agents/bindings/opencode/tui.json";

  # グローバル指示の正本を OpenCode にも配る。OpenCode は AGENTS.md を優先し、
  # 無いときだけ ~/.claude/CLAUDE.md にフォールバックする。明示的に置いて経路を 1 本にする。
  home.file.".config/opencode/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/agents/AGENTS.md";
}
