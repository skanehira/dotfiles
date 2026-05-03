{ lib, pkgs, ... }:

{
  # Bootstrap install: ~/.deno/bin/deno が無い時のみ Deno 公式インストーラを実行。
  # 既存マシンでは no-op、新規マシンでは drs / hms 一発で deno がセットアップされる。
  # 以後の更新は `deno upgrade` の self-update に任せる (Nix で version pin しない方針、
  # claude.nix / rustup.nix と同じパターン)。
  #
  # deno install.sh は内部で curl と unzip を要求する。HM activation の PATH は
  # Linux で /usr/bin を含まない (実機検証済) ので、export PATH で curl / unzip を
  # 露出させる。claude.nix / rustup.nix と同じ理由
  home.activation.bootstrapDeno = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -x "$HOME/.deno/bin/deno" ]; then
      echo "Bootstrapping deno..." >&2
      run sh -c 'export PATH=${pkgs.curl}/bin:${pkgs.unzip}/bin:$PATH && ${pkgs.curl}/bin/curl -fsSL https://deno.land/install.sh | sh -s -- -y --no-modify-path'
    fi
  '';
}
