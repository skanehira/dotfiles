{ username, ... }:

{
  # nix-darwin 互換バージョン (互換性維持のため変更しない)
  system.stateVersion = 6;
  system.primaryUser = username;

  # macOS の既存ユーザを nix-darwin に認識させる (HM が home directory を引くため必須)
  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
  };

  # Nix daemon (system) 設定
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "@admin" username ];
  };

  # sudo を Touch ID で通す
  # reattach は tmux/screen セッション内でも Touch ID プロンプトを表示させるために必要
  security.pam.services.sudo_local = {
    touchIdAuth = true;
    reattach = true;
  };

  # zsh をシステムシェルとして認識させる (HM 側でも programs.zsh.enable する)
  programs.zsh.enable = true;
}
