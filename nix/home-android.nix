{ config, username, ... }:

# Android (Termux + proot-distro Debian) 用の Home Manager エントリポイント。
# 通常の Linux (home-linux.nix) とは別プロファイルにする。proot は RAM が数 GB で
# binary cache に無いものをローカルビルドできず、ストレージも Termux のアプリ内領域に
# 載るため、フルセット (home.nix) は完走しないため。
# セットアップ手順は docs/android-dev-setup.md。
#
# home.nix から意図的に外した module と理由:
#   codex.nix   — Codex は使わない (要件外)
#   rustup.nix  — Rust は書かない。toolchain の DL が重い
#   herdr.nix   — 本体が flake input の Rust + Zig ビルドで cache が無い
#   packages.nix — フルセット。packages-android.nix で置き換える
#   nix-index   — DB を毎週 fetch するのでストレージを食う
{
  imports = [
    ./home-core.nix

    ./modules/home/claude.nix
    # agents/bindings/claude/settings.json の hook 2 本が `deno run` で起動するので、
    # Claude Code を使う以上 deno は外せない (bootstrap は公式 installer を curl するだけ)
    ./modules/home/deno.nix
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

  # single-user の Nix installer は ~/.profile に nix.sh の source 行を書くが、
  # このプロファイルは programs.bash を有効にするので HM が ~/.profile を丸ごと
  # 置き換え、その行が消える。hm-session-vars.sh が export する PATH は
  # home.sessionPath だけなので、明示的に profile の bin を足さないと switch 後の
  # 再ログインで nix / nh / nvim / tmux が一斉に引けなくなる。
  # 通常 Linux プロファイルは programs.bash を持たず ~/.profile を触らないため
  # この問題が出ず、env.nix にもこのパスは無い。
  home.sessionPath = [ "${config.home.profileDirectory}/bin" ];

  # Home Manager standalone は chsh を実行せず、proot-distro のユーザーは
  # 初期シェルが bash のまま。そこで bash から zsh へ引き渡す。
  #
  # 対話判定は HM が生成する .bashrc 冒頭の `[[ $- == *i* ]] || return` に任せる
  # (initExtra はその後ろに置かれるので、非対話 bash ではここまで到達しない)。
  # 自前で `[ -t 1 ]` を足すと、stdout をリダイレクトした対話シェルで zsh に
  # 移れなくなるだけで、守れる範囲は増えない。
  #
  # -l を付けるのは HM が PATH と sessionVariables を .zprofile に書くため。
  # zsh が未導入のときに exec して端末を失わないよう、実行可能性だけ確認する。
  programs.bash = {
    enable = true;
    initExtra = ''
      if [ -x "${config.home.profileDirectory}/bin/zsh" ]; then
        exec "${config.home.profileDirectory}/bin/zsh" -l
      fi
    '';
  };
}
