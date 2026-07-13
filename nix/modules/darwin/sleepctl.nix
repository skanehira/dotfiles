{ pkgs, username, ... }:

let
  # 蓋閉じ監視デーモン。
  # disablesleep 中は蓋を閉じても内蔵ディスプレイが点いたままになるため、
  # 閉じ遷移を検知して pmset displaysleepnow (root 不要) を 1 回だけ打つ。
  # disablesleep=0 の間は 5 秒間隔の状態確認だけ行う (実質 no-op)。
  # 状態源は pmset の実状態のみなので、手動 pmset で切り替えても追従する。
  watcher = pkgs.writeShellScript "sleepctl-watcher" ''
    fired=0
    while :; do
      # SleepDisabled 行は未設定のマシンでは出力されないことがあるため
      # 「行があり値が 1」のときだけ有効と判定する
      if [ "$(/usr/bin/pmset -g | /usr/bin/awk '$1 == "SleepDisabled" { print $2 }')" != "1" ]; then
        fired=0
        /bin/sleep 5
        continue
      fi

      # AppleClamshellCausesSleep という似た名前のキーが同居しているので
      # キー名は引用符込みの完全一致でパースする
      state=$(/usr/sbin/ioreg -r -k AppleClamshellState -d 1 \
        | /usr/bin/awk -F' = ' '$1 ~ /"AppleClamshellState"$/ { print $2 }')

      if [ "$state" = "Yes" ]; then
        # 閉じ遷移につき 1 回だけ発火
        if [ "$fired" = "0" ]; then
          /usr/bin/pmset displaysleepnow
          fired=1
        fi
      else
        fired=0
      fi
      /bin/sleep 0.25
    done
  '';
in
{
  # sleepctl on/off をパスワードなしで通すための sudoers ルール。
  # 引数完全一致で disablesleep の 1/0 のみに限定する。
  security.sudo.extraConfig = ''
    ${username} ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0
  '';

  # Label は org.nixos.sleepctl-watcher になる
  launchd.user.agents.sleepctl-watcher = {
    serviceConfig = {
      ProgramArguments = [ "${watcher}" ];
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
    };
  };
}
