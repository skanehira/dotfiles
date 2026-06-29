{
  lib,
  pkgs,
  username,
  dotfilesRoot,
  ...
}:

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

    initContent =
      builtins.readFile ../../../zsh/zshrc
      + ''

        # tirith: シェル実行前に homograph URL / pipe-to-shell 等の脅威を検査
        eval "$(tirith init --shell zsh)"
      ''
      + lib.optionalString pkgs.stdenv.isDarwin ''

        # OpenShift Local (crc): oc を遅延初期化
        # `crc oc-env` 実行は ~560ms と重く、login shell 起動時に毎回払うのは割に合わない。
        # 出力は実質 PATH 追加 1 行なので、shim 関数で初回 oc 呼び出し時にだけ eval する。
        if [ -x /usr/local/bin/crc ] && [ -x "$HOME/.crc/bin/oc/oc" ]; then
          oc() {
            unfunction oc
            eval "$(/usr/local/bin/crc oc-env)"
            oc "$@"
          }
        fi
      '';

    # ~/.zprofile に追記する内容 (login shell 起動時に評価される)
    # platform 分岐は Nix 評価時に解決され、対象 OS の文字列だけが残る
    profileExtra =
      lib.optionalString pkgs.stdenv.isDarwin ''
        export SHELL=/bin/zsh
        eval "$(/opt/homebrew/bin/brew shellenv)"
      ''
      + lib.optionalString pkgs.stdenv.isLinux ''
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

  programs.zsh.shellAliases = {
    # git
    g = "git";
    gs = "git status";
    gl = "git log";
    # ls
    ls = "lsd";
    ll = "lsd -la";
    # editor
    v = "nvim";
    # k8s
    k = "kubectl";
    # terraform
    t = "terraform";
    # rust
    c = "cargo";
  }
  // lib.optionalAttrs pkgs.stdenv.isDarwin {
    # nix-darwin 切替 (mac)。nh が内部で darwin-rebuild を sudo 実行し、
    # 自動で nom 経由のビルド進捗 + 適用前後の diff を表示する。
    # 設定名は nh の -c (home) / -H (darwin) で明示する。nh 4.x は INSTALLABLE の
    # `#ATTRPATH` を素の flake 属性として解決し (homeConfigurations /
    # darwinConfigurations を前置しない) `<flake>#<configname>` では引けないため。
    # -c/-H なら hostname 依存の自動検出に頼らず configname を直接選べる。
    # noglob: zsh の EXTENDED_GLOB がパス中のメタ文字を展開するのを防ぐ保険。
    drs = "noglob nh darwin switch ${dotfilesRoot}/nix -H ${username}";
  }
  // lib.optionalAttrs pkgs.stdenv.isLinux {
    # Home Manager standalone 切替 (Linux)
    hms = "noglob nh home switch ${dotfilesRoot}/nix -c ${username}";
  };

  # ~/.config/zsh/functions/ 配下にカスタム関数ファイルを配置
  # zshrc 側の `source ~/.config/zsh/functions/*.zsh` ループで読み込まれる
  home.file = {
    ".config/zsh/functions/ghq-fzf.zsh".source = ../../../zsh/functions/ghq-fzf.zsh;
    ".config/zsh/functions/tmuxpopup.zsh".source = ../../../zsh/functions/tmuxpopup.zsh;
    ".config/zsh/functions/gss.zsh".source = ../../../zsh/functions/gss.zsh;
  };
}
