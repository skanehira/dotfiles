{ ... }:

{
  # Homebrew declarative 管理
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "uninstall";
    };

    # brews:
    # - cask の依存になりやすいコア formula (暗黙依存だけだと cask 依存リンクが
    #   切れた時に巻き添え削除されるので保険として固定)
    # - nixpkgs 未収録の CLI ツール
    brews = [
      # cask 依存の保険
      "ca-certificates"
      "openssl@3"
      "sqlite"
      "aqua"
    ];

    # GUI アプリ・macOS 専用 CLI
    casks = [
      "1password-cli"
      "codex"
      "discord"
      "drawio"
      "font-cica"
      "gcloud-cli"
      "karabiner-elements"
      "keycastr"
      "orbstack"
      "ppsspp-emulator"  # PSP emulator GUI (formula 版 ppsspp は nixpkgs 未対応のため cask 利用)
      "session-manager-plugin"
      "tableplus"
      "transmission"
      "vlc"
      "xquartz"
      "tailscale-app"
    ];
  };
}
