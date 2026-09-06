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
{
  home.activation.bootstrapVitePlus = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -x "$HOME/.vite-plus/bin/vp" ]; then
      echo "Bootstrapping Vite+..." >&2
      run sh -c 'export PATH=${pkgs.curl}/bin:$PATH && ${pkgs.curl}/bin/curl -fsSL https://vite.plus | bash'
    fi
  '';

  # installer が shim を置く先。env.nix の sessionPath と merge される
  home.sessionPath = [ "$HOME/.vite-plus/bin" ];
}
