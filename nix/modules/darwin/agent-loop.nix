{ username, ... }:

let
  home = "/Users/${username}";
  # 文字列パスなので nix store にコピーされず、dotfiles のスクリプトを直接動かす (live edit)
  script = "${home}/dev/github.com/skanehira/dotfiles/agents/scripts/agent-loop.ts";
in
{
  # agent-loop: 10 分おきに対象のリポジトリの issue を見回り、仕事の種類ごとに Claude Code を
  # バックグラウンドで起動する (agents/scripts/agent-loop.ts の冒頭に仕組みがある)。
  # 対象の一覧は dotfiles の外の ~/.config/agent-loop/repos.yaml に置く。無ければ何もしない。
  # Label は org.nixos.agent-loop になる
  launchd.user.agents.agent-loop = {
    serviceConfig = {
      ProgramArguments = [
        "${home}/.deno/bin/deno"
        "run"
        "--allow-env"
        "--allow-run"
        "--allow-read"
        "--allow-write"
        script
      ];
      StartInterval = 600;
      RunAtLoad = true;
      ProcessType = "Background";
      # launchd の既定の PATH には gh / claude / deno が無い
      EnvironmentVariables = {
        HOME = home;
        PATH = builtins.concatStringsSep ":" [
          "${home}/.local/bin"
          "${home}/.deno/bin"
          "/etc/profiles/per-user/${username}/bin"
          "/run/current-system/sw/bin"
          "/usr/bin"
          "/bin"
          "/usr/sbin"
          "/sbin"
        ];
      };
      StandardOutPath = "${home}/Library/Logs/agent-loop.log";
      StandardErrorPath = "${home}/Library/Logs/agent-loop.log";
    };
  };
}
