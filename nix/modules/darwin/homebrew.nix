{ ... }:

{
  # Homebrew declarative 管理
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "none";  # 初期は破壊しない、安定後 "uninstall" に
    };

    # 残す formula (Nix 移行困難 / Darwin ビルド失敗)
    brews = [
      "gnupg"
      "ppsspp"
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
