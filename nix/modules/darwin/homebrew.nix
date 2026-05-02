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

    # cask の依存になりやすいコア formula を明示宣言。
    # 暗黙の依存だけだと cask 依存リンクが切れた時に巻き添えで消されるので保険として固定する。
    brews = [
      "ca-certificates"
      "openssl@3"
      "sqlite"
    ];

    # GUI アプリ・macOS 専用 CLI
    casks = [
      "1password-cli"
      "calibre"
      "chatgpt-atlas"
      "codex"
      "cursor"
      "discord"
      "drawio"
      "font-cica"
      "gcloud-cli"
      "gstreamer-runtime"
      "karabiner-elements"
      "keycastr"
      "openmtp"
      "orbstack"
      "ppsspp-emulator"  # PSP emulator GUI (formula 版 ppsspp は nixpkgs 未対応のため cask 利用)
      "session-manager-plugin"
      "tableplus"
      "transmission"
      "vlc"
      "wine-stable"
      "xquartz"
      "zap"
      "zulu@17"
    ];
  };
}
