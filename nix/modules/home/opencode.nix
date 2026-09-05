{ config, dotfilesRoot, ... }:

{
  # 設定は dotfiles repo への直接 symlink (mkOutOfStoreSymlink) で扱う。
  # claude.nix と同じ方針で、編集が drs 不要で即反映される (live edit)。
  #
  # symlink するのは opencode.json 1 枚だけにする。~/.config/opencode/ には
  # opencode 自身が書く領域 (tui.json / skills/ / node_modules / package.json)
  # が同居しており、ディレクトリごと貼ると dotfiles に流れ込むため。
  #
  # 接続先 (Spark の baseURL) は設定に直書きせず、opencode の {file:...} 置換で
  # ~/.config/opencode/spark-base-url から読む。このリポジトリは公開なので IP を
  # 置けないため。ccsp が CCSP_LAN_HOST で同じ問題を回避しているのと対応する。
  # 新しいマシンではこのファイルと /tmp/spark.key を手で作る
  # (詳細は claude/rules/infra/dgx-spark.md)。
  home.file.".config/opencode/opencode.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/opencode/opencode.json";
}
