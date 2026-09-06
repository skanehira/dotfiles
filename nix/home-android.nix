{ username, ... }:

# Android (Termux + proot-distro Debian) 用の Home Manager エントリポイント。
# 通常の Linux (home-linux.nix) とは別プロファイルにする。proot は RAM が数 GB で
# binary cache に無いものをローカルビルドできず、ストレージも Termux のアプリ内領域に
# 載るため、フルセット (home.nix) は完走しないため。
# セットアップ手順は docs/android-dev-setup.md。
#
# home.nix から意図的に外した module と理由:
#   codex.nix   — Codex は使わない (要件外)
#   deno.nix    — 要件外。必要になったら公式 installer を bootstrap する
#   rustup.nix  — Rust は書かない。toolchain の DL が重い
#   herdr.nix   — 本体が flake input の Rust + Zig ビルドで cache が無い
#   packages.nix — フルセット。packages-android.nix で置き換える
#   nix-index   — DB を毎週 fetch するのでストレージを食う
{
  imports = [
    ./home-core.nix

    ./modules/home/claude.nix
    ./modules/home/direnv.nix
    ./modules/home/env.nix
    ./modules/home/fzf.nix
    ./modules/home/gh.nix
    ./modules/home/git.nix
    ./modules/home/neovim.nix
    ./modules/home/opencode.nix
    ./modules/home/packages-android.nix
    ./modules/home/tmux.nix
    ./modules/home/vite-plus-bootstrap.nix
    ./modules/home/zsh.nix
  ];

  home.username = username;
  home.homeDirectory = "/home/${username}";

  # Home Manager standalone は chsh を実行せず、proot-distro のユーザーは
  # 初期シェルが bash のまま。対話シェルのときだけ zsh へ引き渡す。
  # -l を付けるのは HM が PATH と sessionVariables を .zprofile に書くため。
  programs.bash = {
    enable = true;
    initExtra = ''
      if [ -z "$ZSH_VERSION" ] && [ -t 1 ] && [ -x "$HOME/.nix-profile/bin/zsh" ]; then
        exec "$HOME/.nix-profile/bin/zsh" -l
      fi
    '';
  };
}
