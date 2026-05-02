{ config, lib, pkgs, ... }:

let
  # dotfiles repo の絶対 path。mkOutOfStoreSymlink は Nix 評価時の path ではなく
  # 実機の path を要求するため、$HOME ベースで構築する
  dotfiles = "${config.home.homeDirectory}/dev/github.com/skanehira/dotfiles";
in
{
  # Bootstrap install: ~/.local/bin/claude が無い時のみ Anthropic 公式インストーラを実行
  # 既存マシンでは no-op、新規マシンでは drs 一発で claude がセットアップされる
  # 以後の更新は `claude update` の self-update に任せる (Nix で version pin しない方針)
  #
  # claude.ai/install.sh は downloads.claude.ai/claude-code-releases/bootstrap.sh に
  # リダイレクトされる Anthropic 公式の bootstrap スクリプト。
  # PATH に curl を載せておかないと、install.sh が内部で curl/wget を再帰的に呼ぶ際に
  # 「Either curl or wget is required」で落ちる (Linux の HM activation は PATH が最小)
  home.activation.bootstrapClaudeCode = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -x "$HOME/.local/bin/claude" ]; then
      echo "Bootstrapping Claude Code..." >&2
      run sh -c 'export PATH=${pkgs.curl}/bin:$PATH && ${pkgs.curl}/bin/curl -fsSL https://claude.ai/install.sh | bash'
    fi
  '';

  # 設定は dotfiles repo への直接 symlink (mkOutOfStoreSymlink) で扱う
  # → skills/rules/hooks/CLAUDE.md の編集が drs 不要で即反映される (live edit)
  # 通常の home.file.X.source = ./path だと /nix/store にコピーされ drs 必須になる
  home.file = {
    ".claude/CLAUDE.md".source     = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/CLAUDE.md";
    ".claude/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/settings.json";
    ".claude/agents".source        = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/agents";
    ".claude/hooks".source         = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/hooks";
    ".claude/rules".source         = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/rules";
    ".claude/skills".source        = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/skills";
  };
}
