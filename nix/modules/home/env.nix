{
  config,
  lib,
  pkgs,
  ...
}:

{
  # ログインシェルで設定する環境変数 (HM が hm-session-vars.sh を生成)
  home.sessionVariables = {
    EDITOR = "nvim";
    # nh が flake path 引数を省略しても解決できるようにする
    NH_FLAKE = "${config.home.homeDirectory}/dev/github.com/skanehira/dotfiles/nix";
    LANG = "en_US.UTF-8";
    LC_CTYPE = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
    GHQ_ROOT = "$HOME/dev";
    GOPATH = "$HOME/go";
    GOBIN = "$HOME/go/bin";
    RUSTUP_HOME = "$HOME/.rustup";
    HOMEBREW_INSTALL_CLEANUP = "1";
    # Linux の Node 24.22.1 未満は内蔵 CA に emSign ECC Root CA - G3 が残るため、
    # CVE-2026-111943 対策としてシステムの CA バンドルを使う。
    # mac は更新済みの内蔵 CA を使う。このフラグは Claude の CA 選択にも影響する。
    NODE_OPTIONS = lib.mkIf (
      pkgs.stdenv.hostPlatform.isLinux && lib.versionOlder pkgs.nodejs_24.version "24.22.1"
    ) "--use-openssl-ca";
    CHROME_BUNDLE_IDENTIFIER = "com.vivaldi.Vivaldi";
    # 1Password 参照（実値ではなく vault path、commit 安全）
    CF_TOKEN_1P_REF = "op://Personal/Cloudflare Token/credential";
    CF_ACCOUNT_1P_REF = "op://Personal/Cloudflare Token/account_id";
    # zsh `time` builtin の表示書式 (先頭の \n\n と末尾 \n はオリジナルのまま)
    TIMEFMT = ''


      ========================
      Program : %J
      CPU     : %P
      user    : %*Us
      system  : %*Ss
      total   : %*Es
      ========================
    '';
  };

  # PATH 追加 (HM が ~/.zprofile に PATH= の export を入れる)
  home.sessionPath = [
    "/usr/local/bin"
    "$HOME/go/bin"
    "$HOME/.deno/bin"
    "$HOME/.local/bin"
  ];
}
