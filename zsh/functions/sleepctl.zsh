# 蓋を閉じても処理を継続する状態 (pmset disablesleep) を切り替える。
# on/off のパスワードレス実行は nix/modules/darwin/sleepctl.nix の
# sudoers NOPASSWD ルール前提。sudoers と引数を完全一致させること。
# 蓋閉じ時の画面消灯は launchd agent (org.nixos.sleepctl-watcher) が行う。
function sleepctl() {
  case "$1" in
    on)
      sudo /usr/bin/pmset -a disablesleep 1 && echo "sleepctl: on (蓋を閉じても処理を継続)"
      ;;
    off)
      sudo /usr/bin/pmset -a disablesleep 0 && echo "sleepctl: off (通常のスリープ動作)"
      ;;
    status)
      # SleepDisabled 行は未設定時に存在しないことがあるため値 1 のみ on 扱い
      if [[ "$(pmset -g | awk '$1 == "SleepDisabled" { print $2 }')" == "1" ]]; then
        echo "on"
      else
        echo "off"
      fi
      ;;
    *)
      echo "usage: sleepctl {on|off|status}" >&2
      return 1
      ;;
  esac
}
