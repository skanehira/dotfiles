{ inputs, ... }:

# フルセットのプロファイル (macOS と通常の Linux が共有する base)。
# karabiner.nix のような macOS 専用 module と、username / homeDirectory の
# プラットフォーム依存値は home-darwin.nix / home-linux.nix で設定する。
#
# Android (Termux + proot) は別プロファイル (home-android.nix) を使う。
# proot は RAM とストレージが限られ、binary cache に無いものをビルドできないため、
# ここに並ぶ module のうち軽量なものだけを import する。
{
  imports = [
    ./home-core.nix

    # 事前生成された nix-index DB を毎週取得し、`,` (comma) で未インストール
    # CLI を一時実行できるようにする HM モジュール
    inputs.nix-index-database.homeModules.nix-index

    ./modules/home/claude.nix
    ./modules/home/codex.nix
    ./modules/home/deno.nix
    ./modules/home/direnv.nix
    ./modules/home/env.nix
    ./modules/home/fzf.nix
    ./modules/home/gh.nix
    ./modules/home/git.nix
    ./modules/home/herdr.nix
    ./modules/home/neovim.nix
    ./modules/home/opencode.nix
    ./modules/home/packages.nix
    ./modules/home/rustup.nix
    ./modules/home/tmux.nix
    ./modules/home/zsh.nix
  ];

  # nix-index 本体 (zsh 連携で command-not-found を nix-locate に置換)
  programs.nix-index.enable = true;
  # `, jq foo.json` のように一時的にコマンドを起動できる comma を有効化
  programs.nix-index-database.comma.enable = true;
}
