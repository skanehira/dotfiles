{ ... }:

{
  programs.gh = {
    enable = true;

    # git push/pull の認証を gh の token に肩代わりさせる
    # (osxkeychain / 手動 PAT 設定が不要になる)
    gitCredentialHelper.enable = true;

    # ~/.config/gh/config.yml に書き出される項目。hosts.yml (auth token) は
    # 宣言化できないので gh auth login で手動運用のまま。
    # 他のキー (prompt / spinner / accessible_* など) は gh のデフォルトと
    # 一致するため省略 (省略時 gh はデフォルト解釈)
    settings = {
      git_protocol = "https";
      aliases = {
        co = "pr checkout";
      };
    };
  };
}
