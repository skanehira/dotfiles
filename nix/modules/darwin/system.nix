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
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [
      "@admin"
      username
    ];
  };

  # /nix/store 肥大化対策。日曜 3 時に 14 日より古い世代を GC + ハードリンク最適化。
  # launchd 経由で走るので drs を忘れがちなマシンでも自動回収される。
  nix.gc = {
    automatic = true;
    interval = {
      Weekday = 0;
      Hour = 3;
      Minute = 0;
    };
    options = "--delete-older-than 14d";
  };
  nix.optimise.automatic = true;

  # macOS GUI 設定の最小限の宣言化。Dock / Finder などの好みが分かれる部分は
  # 手動運用のまま残し、ここではキー入力と trackpad の "動作" 系のみ管理する。
  system.defaults = {
    NSGlobalDomain = {
      # キーリピート速度 (System Settings の最速より速くできる)
      # InitialKeyRepeat: リピート開始までの遅延 (単位 15ms。15 → ~225ms)
      InitialKeyRepeat = 10;
      # KeyRepeat: 1 文字あたりの間隔 (単位 15ms。2 → ~30ms)
      KeyRepeat = 1;
      # 長押しでアクセント記号メニューを出すデフォルト挙動を無効化し、
      # vim 等のキーリピートを優先する
      ApplePressAndHoldEnabled = false;
    };
    # トラックパッドのタップでクリック (物理クリック不要)
    trackpad.Clicking = true;
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
