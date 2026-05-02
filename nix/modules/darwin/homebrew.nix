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

    # formula は全て Nix 管理に移行済 (必要が出たら追加)
    brews = [ ];

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
