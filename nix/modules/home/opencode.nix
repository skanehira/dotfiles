{ config, dotfilesRoot, ... }:

{
  # 設定は dotfiles repo への直接 symlink (mkOutOfStoreSymlink) で扱う。
  # claude.nix と同じ方針で、編集が drs 不要で即反映される (live edit)。
  #
  # symlink するのは opencode.json 1 枚だけにする。~/.config/opencode/ には
  # opencode 自身が書く領域 (tui.json / skills/ / node_modules / package.json)
  # が同居しており、ディレクトリごと貼ると dotfiles に流れ込むため。
  #
  # 接続先は ccsp と同じ mDNS 名 (spark-head.local) を直接書いてある。IP を書けば
  # 接続あたり約 210ms 速いが、このリポジトリは公開なので置かない。
  # vLLM が認証を要求しないので API キーは持たない (詳細は
  # claude/rules/infra/dgx-spark.md)。
  home.file.".config/opencode/opencode.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/opencode/opencode.json";
}
