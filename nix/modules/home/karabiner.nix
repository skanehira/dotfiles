{ config, lib, pkgs, dotfilesRoot, ... }:

let
  # goku は既存の karabiner.json を update する設計のため、最低限 profile "Default" が必要
  # 初回 (まだ karabiner.json が無い) のとき活性化スクリプトで配置する
  karabinerJsonStub = pkgs.writeText "karabiner.stub.json" ''
    {
      "profiles": [
        { "name": "Default", "selected": true, "complex_modifications": { "rules": [] } }
      ]
    }
  '';
  # dotfiles の karabiner.edn を直接 goku に読ませる (GOKU_EDN_CONFIG_FILE 経由)。
  # ~/.config/karabiner.edn を生成しないことで、$HOME 側の管理ファイルが 1 つ減る
in
{
  # Goku: EDN DSL で書いた karabiner.edn を karabiner.json に変換するツール
  home.packages = [ pkgs.goku ];

  # switch 時に goku を実行して karabiner.json を再生成
  # Karabiner-Elements は karabiner.json を watch しており、書き換え後に自動で reload する
  home.activation.runGoku = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p ${config.xdg.configHome}/karabiner
    if [ ! -f ${config.xdg.configHome}/karabiner/karabiner.json ]; then
      run install -m 644 ${karabinerJsonStub} ${config.xdg.configHome}/karabiner/karabiner.json
    fi
    run env GOKU_EDN_CONFIG_FILE=${dotfilesRoot}/karabiner/karabiner.edn ${pkgs.goku}/bin/goku
  '';
}
