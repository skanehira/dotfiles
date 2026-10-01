{ config, username, ... }:

{
  # Homebrew 4.x 以降、サードパーティ tap からの cask 読み込みは明示的な `brew trust`
  # が必要になった。`homebrew bundle` の前に流すため preActivation で実行する。
  # activation script は root で走るので sudo -u でユーザーに落としてから brew を叩く。
  # (brew は root 実行を拒否する。-H は HOME をユーザーホームに切り替えて trust の
  # 永続データを正しい場所に保存するため)
  # brew の場所は config.homebrew.prefix で解決 (aarch64=/opt/homebrew,
  # x86_64=/usr/local を nix-darwin が引いてくれる)。
  system.activationScripts.preActivation.text = ''
    if [ -x ${config.homebrew.prefix}/bin/brew ]; then
      sudo -u ${username} -H ${config.homebrew.prefix}/bin/brew trust arto-app/tap || true
    fi
  '';

  # Arto.app は未署名で quarantine 属性が付くため、cask install 後に剥がす
  system.activationScripts.postActivation.text = ''
    if [ -d /Applications/Arto.app ]; then
      /usr/bin/xattr -dr com.apple.quarantine /Applications/Arto.app || true
    fi
  '';

  # Homebrew declarative 管理
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "uninstall";
    };

    # サードパーティ tap
    taps = [
      "arto-app/tap"
    ];

    # brews:
    # - cask の依存になりやすいコア formula (暗黙依存だけだと cask 依存リンクが
    #   切れた時に巻き添え削除されるので保険として固定)
    # - nixpkgs 未収録の CLI ツール
    brews = [
      # cask 依存の保険
      "ca-certificates"
      "openssl@3"
      # gcloud-cli (cask) が依存する python。bundle cleanup は cask の依存を最新の cask 定義から
      # 引くので、定義だけが新しい python へ進むと (upgrade = false のため installed は古いまま)
      # installed が使う python が削除候補になり、brew uninstall に拒否されて drs が警告を出す。
      # gcloud-cli を upgrade して receipt の python が変わったら、ここも合わせて書き換える
      "python@3.14"
      "aqua"
    ];

    # GUI アプリ・macOS 専用 CLI
    casks = [
      "1password"
      "1password-cli"
      "arto-app/tap/arto"
      "codex"
      "discord"
      "drawio"
      "font-cica"
      "gcloud-cli"
      "karabiner-elements"
      "keycastr"
      "orbstack"
      "ppsspp-emulator" # PSP emulator GUI (formula 版 ppsspp は nixpkgs 未対応のため cask 利用)
      "session-manager-plugin"
      "slack"
      "tableplus"
      "transmission"
      "vlc"
      "wezterm@nightly"
      "xquartz"
      "tailscale-app"
      "zoom"
      "claude"
      "codex-app"
      "stablyai/orca/orca"
    ];
  };
}
