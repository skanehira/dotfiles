{ lib, pkgs, ... }:

# Vite+ (vp) の bootstrap install: ~/.vite-plus/bin/vp が無ければ公式 installer を実行。
# 以後の更新は vp 自身の self-update に任せる (claude.nix / rustup.nix / deno.nix と
# 同じパターン)。
#
# nixpkgs に vite-plus は無く、packages.nix が使う ryoppippi/nix-vite-plus overlay は
# aarch64-linux の installCheckPhase で SIGABRT になりビルドできない。公式 installer は
# linux-arm64-gnu のビルド済みバイナリを取得するので proot Debian ではこちらを使う。
#
# PATH に curl を載せておかないと installer が内部で curl を再帰的に呼ぶ際に落ちる
# (Linux の HM activation は PATH が最小。claude.nix と同じ理由)。
#
# VP_NODE_MANAGER=no: installer は Node のバージョンマネージャを入れるか対話で聞く。
# activation には TTY が無いので、上流が CI / devcontainer 用に用意しているこの
# 環境変数でプロンプトを飛ばす。Node は packages-android.nix の nodejs_24 で入る。
#
# installer は ~/.zshrc / ~/.bashrc / ~/.bash_profile / ~/.profile に env の source を
# 追記しようとするが、これらは HM が nix store への read-only symlink として管理して
# いるので失敗する。installer 側は失敗を集計して報告するだけで異常終了しない
# (append_source_to_file の戻り値を握り潰す実装) ため activation は止まらない。
# PATH は下の sessionPath で通すので追記は不要。
{
  home.activation.bootstrapVitePlus = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -x "$HOME/.vite-plus/bin/vp" ]; then
      echo "Bootstrapping Vite+..." >&2
      run sh -c 'export PATH=${pkgs.curl}/bin:$PATH VP_NODE_MANAGER=no && ${pkgs.curl}/bin/curl -fsSL https://vite.plus | bash'
    fi
  '';

  # installer が shim を置く先。env.nix の sessionPath と merge される
  home.sessionPath = [ "$HOME/.vite-plus/bin" ];
}
