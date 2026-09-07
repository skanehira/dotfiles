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
  # 接続先は ccsp と同じ mDNS 名 (spark-head.local) を直接書いてある。IP を書けば
  # 接続あたり約 210ms 速いが、このリポジトリは公開なので置かない。
  # vLLM が認証を要求しないので API キーは持たない (詳細は
  # claude/rules/infra/dgx-spark.md)。
  home.file.".config/opencode/opencode.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/opencode/opencode.json";

  home.file.".config/opencode/tui.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/opencode/tui.json";
}
