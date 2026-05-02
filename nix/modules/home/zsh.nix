{ lib, pkgs, ... }:

{
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    defaultKeymap = "viins";

    # ~/.zshenv に追記する内容 (非対話シェル含めて常に評価される)
    envExtra = ''
      # PATH の重複を抑止 (zsh 配列ユニーク化)
      typeset -gU PATH
      . "$HOME/.cargo/env"
    '';

    history = {
      path = "$HOME/.zsh_history";
      size = 1000;
      save = 1000;
      append = true;
    };

    # compinit を 24h に 1 回だけフル実行、それ以外は -C で security check skip
    # (デフォルトの compinit ~380ms → ~13ms に短縮)
    completionInit = ''
      setopt EXTENDED_GLOB
      autoload -Uz compinit
      # ~/.zcompdump(#qN.mh+24): N=null_glob, .=通常ファイル, mh+24=mtime 24時間以上前
      if [[ -n ~/.zcompdump(#qN.mh+24) ]]; then
        compinit       # 24h 以上経過 → cache 再生成 (重い)
      else
        compinit -C    # それ以外 → 既存 cache を信じて security check skip (軽い)
      fi
    '';

    initContent = builtins.readFile ../../../zsh/zshrc;

    # ~/.zprofile に追記する内容 (login shell 起動時に評価される)
    # platform 分岐は Nix 評価時に解決され、対象 OS の文字列だけが残る
    profileExtra = lib.optionalString pkgs.stdenv.isDarwin ''
      export SHELL=/bin/zsh
      eval "$(/opt/homebrew/bin/brew shellenv)"
    '' + lib.optionalString pkgs.stdenv.isLinux ''
      export SHELL=/usr/bin/zsh
      brew=/home/linuxbrew/.linuxbrew/bin/brew
      if [ -f "$brew" ]; then
        eval "$($brew shellenv)"
      fi
    '';

    localVariables = {
      # プロンプト: 赤username@緑hostname BOLD黄パス\n$
      PROMPT = "%F{red}%n%f@%F{green}%m%f %F{yellow}%B%3~%b%f\n$ ";
    };
  };

  # ~/.config/zsh/functions/ 配下にカスタム関数ファイルを配置
  # zshrc 側の `source ~/.config/zsh/functions/*.zsh` ループで読み込まれる
  home.file = {
    ".config/zsh/functions/ghq-fzf.zsh".source = ../../../zsh/functions/ghq-fzf.zsh;
    ".config/zsh/functions/tmuxpopup.zsh".source = ../../../zsh/functions/tmuxpopup.zsh;
    ".config/zsh/functions/gss.zsh".source = ../../../zsh/functions/gss.zsh;
  };
}
