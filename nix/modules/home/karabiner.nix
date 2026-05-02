{ config, lib, pkgs, ... }:

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
in
{
  # Goku: EDN DSL で書いた karabiner.edn を karabiner.json に変換するツール
  home.packages = [ pkgs.goku ];

  # ~/.config/karabiner.edn に EDN を配置 (goku のデフォルト読み込み先)
  home.file.".config/karabiner.edn".source = ../../../karabiner/karabiner.edn;

  # switch 時に goku を実行して karabiner.json を再生成
  # Karabiner-Elements は karabiner.json を watch しており、書き換え後に自動で reload する
  home.activation.runGoku = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p ${config.xdg.configHome}/karabiner
    if [ ! -f ${config.xdg.configHome}/karabiner/karabiner.json ]; then
      run install -m 644 ${karabinerJsonStub} ${config.xdg.configHome}/karabiner/karabiner.json
    fi
    run ${pkgs.goku}/bin/goku
  '';
}
