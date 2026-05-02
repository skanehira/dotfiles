{ lib, pkgs, ... }:

let
  # jimeh/tmux-themepack は nixpkgs に無いので mkTmuxPlugin で取り込む
  # 最後の master commit (2019-12-22) で固定
  themepack = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "themepack";
    rtpFilePath = "themepack.tmux";
    version = "unstable-2019-12-22";
    src = pkgs.fetchFromGitHub {
      owner = "jimeh";
      repo = "tmux-themepack";
      rev = "7c59902f64dcd7ea356e891274b21144d1ea5948";
      hash = "sha256-c5EGBrKcrqHWTKpCEhxYfxPeERFrbTuDfcQhsUAbic4=";
    };
  };
in
{
  programs.tmux = {
    enable = true;
    prefix = "C-s";
    terminal = "xterm-256color";
    escapeTime = 1;
    baseIndex = 1;
    keyMode = "vi";

    # h/j/k/l でペイン移動、H/J/K/L でリサイズ (-r) を HM が提供
    customPaneNavigationAndResize = true;

    plugins = [
      { plugin = pkgs.tmuxPlugins.resurrect; }
      {
        plugin = themepack;
        extraConfig = ''
          set -g @themepack 'powerline/double/blue'
          set -g @themepack-status-left-area-middle-format "#(basename #{pane_current_path})"
          set -g @themepack-status-left-area-right-format "#(cd #{pane_current_path}; git rev-parse --abbrev-ref HEAD)"
          set -g @themepack-status-right-area-middle-format "%Y/%m/%d"
        '';
      }
    ];

    extraConfig = ''
      # config ファイルリロード (HM の XDG 出力先)
      bind r source-file ~/.config/tmux/tmux.conf \; display "LOADING CONFIGURATION FILE"

      # ウィンドウを閉じた際に番号を詰める
      set -g renumber-windows on

      # ステータスバーを 1 秒毎に描画し直す
      set-option -g status-interval 1

      # prefix + m でペインの zoom in/zoom out
      bind -T prefix m resize-pane -Z

      # \ でペインを縦分割、^ で同じ pane の cwd で新規ウィンドウ
      bind \\ split-window -h -c '#{pane_current_path}'
      bind ^ new-window -c '#{pane_current_path}'

      # - でペインを横分割
      bind - split-window -v -c '#{pane_current_path}'

      # c でセッション名を入力して新しいセッションを作成
      bind c command-prompt -p "session name:" "new-session -s '%%'"

      # C-q で popup をトグル
      bind -n C-q run-shell "zsh -c 'source ~/.zshrc; tmuxpopup'"

      # ステータスバー上部
      set-option -g status-position top

      # imgcat 等の画像表示を許可
      set -g allow-passthrough on
    '' + lib.optionalString pkgs.stdenv.isDarwin ''
      # macOS: pbcopy でクリップボードにコピー
      bind-key -T copy-mode-vi v send-keys -X begin-selection
      bind-key -T copy-mode-vi V send -X select-line
      bind-key -T copy-mode-vi C-v send -X rectangle-toggle
      bind-key -T copy-mode-vi y send-keys -X copy-pipe "pbcopy"
      bind-key -T copy-mode-vi Enter send-keys -X copy-pipe-and-cancel "pbcopy"
    '' + lib.optionalString pkgs.stdenv.isLinux ''
      # Linux: xsel でクリップボードにコピー
      bind-key -T copy-mode-vi y send -X copy-pipe-and-cancel "xsel -ip && xsel -op | xsel -ib"
      bind-key -T copy-mode-vi Enter send -X copy-pipe-and-cancel "xsel -ip && xsel -op | xsel -ib"
      bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "xsel -ip && xsel -op | xsel -ib"
      bind-key -T prefix ] run "xsel -o | tmux load-buffer - && tmux paste-buffer"
      bind-key -T copy-mode-vi v send-keys -X begin-selection
      bind-key -T copy-mode-vi V send -X select-line
      bind-key -T copy-mode-vi C-v send -X rectangle-toggle
    '';
  };
}
