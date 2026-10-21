{ lib, pkgs, ... }:

{
  # rustup の bootstrap install: ~/.cargo/bin/rustup が無ければ公式 installer を実行
  # 既存マシンでは no-op、新規マシンでは drs 一発で rustup と stable toolchain がセットアップ
  # 以後の更新は `rustup self update` および `rustup update` の self-update に委ねる
  # (Nix では toolchain version を pin しない。複数 toolchain 切替・rust-toolchain.toml
  #  との連携は rustup の責任範囲とする)
  #
  # sh.rustup.rs は公式 installer (https://rustup.rs)。--no-modify-path で zsh の
  # PATH 設定 (~/.cargo/env を envExtra で source 済) と衝突しないようにする。
  # PATH に curl を載せておかないと、installer 内部で curl を再帰的に呼ぶ際に落ちる
  # (Linux の HM activation は PATH が最小。claude.nix と同じ理由)
  # NIX_SSL_CERT_FILE を明示する理由は deno.nix と同じ
  home.activation.bootstrapRustup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -x "$HOME/.cargo/bin/rustup" ]; then
      echo "Bootstrapping rustup..." >&2
      run sh -c 'export PATH=${pkgs.curl}/bin:$PATH NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt &&${pkgs.curl}/bin/curl --proto "=https" --tlsv1.2 -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path'
    fi
  '';
}
