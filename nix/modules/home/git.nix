{ ... }:

{
  programs.git = {
    enable = true;
    lfs.enable = true;
    settings = {
      user = {
        name = "skanehira";
        email = "kanehira.sho@techlead-it.com";
      };
      core = {
        quotepath = false;
        precomposeunicode = true;
      };
      commit.verbose = true;
      color.status = {
        added = "green";
        changed = "red";
        untracked = "yellow";
        unmerged = "magenta";
      };
      status.showUntrackedFiles = "all";
      pull.rebase = true;
      push = {
        default = "current";
        autoSetupRemote = true;
      };
      rebase.autostash = true;
      init.defaultBranch = "main";
      diff.tool = "difftastic";
      difftool.prompt = false;
      difftool.difftastic.cmd = ''difft "$LOCAL" "$REMOTE"'';
      pager.difftool = true;
    };
  };
}
