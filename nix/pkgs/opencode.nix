# OpenCode V2 (ターミナル用コーディングエージェント)。nixpkgs の opencode は V1 (1.18.x) のため
# 自前 derivation。V2 は npm の @opencode/cli-<platform> に bun でコンパイル済みの単一バイナリ
# (bin/opencode) を同梱しているので、tarball を展開して置くだけで済む。ローカルビルドが
# 走らないので、proot でビルドできない Android プロファイルでも使える。
#
# Linux 版は /lib64/ld-linux-*.so を interpreter に持つ glibc の動的リンクで、非 NixOS の
# Ubuntu / Debian ではそのまま動く (patchelf しない)。
#
# 更新手順:
#   1. npm view @opencode/cli version で最新 version を確認
#   2. version を書き換え、各 platform の hash を
#      npm view @opencode/cli-<platform>@<version> dist.integrity の値に差し替える
{
  stdenvNoCC,
  fetchurl,
  lib,
}:

let
  version = "2.0.22";

  # nix の system → npm の platform 名と tarball の integrity
  sources = {
    aarch64-darwin = {
      platform = "darwin-arm64";
      hash = "sha512-NNg1VCCTWSfLlNKpRb4RA6IE7H67ZBLBYmfIWjP3CxR9NPtdROQFCL8lpPf+Tz2Qje4Bb27sQOLWanYyNT/9dQ==";
    };
    x86_64-linux = {
      platform = "linux-x64";
      hash = "sha512-DlV1qgEDDnVqpTWMPqv7tCHCcXodzZBFaMcxjsiYdY6E5gHH2Q68JfasVksyQ1nu6m1887WQKGhOsepE+oKyYw==";
    };
    aarch64-linux = {
      platform = "linux-arm64";
      hash = "sha512-t/yuu9Dqd/M44dFH95bphu7ikO6FATMQuVk/91QBnCMzsP8zVrXU7zAxD1wVLpYYUDqIonEmi80XETlFqx7chw==";
    };
  };

  source =
    sources.${stdenvNoCC.hostPlatform.system}
      or (throw "opencode: ${stdenvNoCC.hostPlatform.system} 向けの V2 バイナリを宣言していない");
in
stdenvNoCC.mkDerivation {
  pname = "opencode";
  inherit version;

  src = fetchurl {
    url = "https://registry.npmjs.org/@opencode/cli-${source.platform}/-/cli-${source.platform}-${version}.tgz";
    inherit (source) hash;
  };

  # bun --compile のバイナリは実行ファイルの末尾にアプリ本体を抱えている。
  # 既定の fixup (strip / patchelf) はこれを壊して起動不能にするので無効化する
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/opencode $out/bin/opencode
    runHook postInstall
  '';

  meta = {
    description = "AI coding agent for the terminal (V2)";
    homepage = "https://opencode.ai";
    license = lib.licenses.mit;
    mainProgram = "opencode";
    platforms = builtins.attrNames sources;
  };
}
