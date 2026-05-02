{ ... }:

{
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    # 内側の引用符は single quote。HM の sessionVariables は値を double quote で囲むので
    # double quote ネストを避ける必要がある
    defaultCommand = "rg --files --hidden --follow --glob '!.git/*'";
    defaultOptions = [
      "--layout=reverse"
      "--inline-info"
      "--exit-0"
      "-m"
      "--preview 'bat  --color=always --style=header,grid --line-range :100 {}'"
    ];
  };
}
