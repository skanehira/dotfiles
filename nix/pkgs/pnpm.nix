# pnpm (JavaScript のパッケージマネージャ)。nixpkgs の pnpm は上流の最新版に追いついていない
# ため自前 derivation。v12 は Rust 製で、GitHub リリースの pnpm-<platform>.tar.gz にビルド済みの
# バイナリ (pnpm) と、それが実行時に使う JS 資産 (dist/) が入っているので、展開して置くだけで
# 済む。ローカルビルドが走らないので、proot でビルドできない Android プロファイルでも使える。
#
# Linux 版は /lib64/ld-linux-*.so を interpreter に持つ glibc の動的リンクで、非 NixOS の
# Ubuntu / Debian ではそのまま動く (patchelf しない)。
#
# 更新手順:
#   1. gh release view -R pnpm/pnpm で最新 version を確認
#   2. version を書き換え、各 platform の hash を
#      nix hash file --sri pnpm-<platform>.tar.gz (リリースの資産を落としたもの) の値に差し替える
{
  stdenvNoCC,
  fetchurl,
  installShellFiles,
  makeWrapper,
  lib,
}:

let
  version = "12.23.0";

  # nix の system → リリース資産の platform 名と tarball の hash
  sources = {
    aarch64-darwin = {
      platform = "darwin-arm64";
      hash = "sha256-UrsxS/DUiSj8FRJszOQqoZknXikBi+8RKgSuis3KrxQ=";
    };
    x86_64-linux = {
      platform = "linux-x64";
      hash = "sha256-tRXinyrBrcD75jFzQUpmgoJ7r/JPF+etNHaCG97yNqw=";
    };
    aarch64-linux = {
      platform = "linux-arm64";
      hash = "sha256-3QP3YWYl/48T2VL2QfCGSiMA1z0KdRpoJzdhW9n5p6I=";
    };
  };

  source =
    sources.${stdenvNoCC.hostPlatform.system}
      or (throw "pnpm: ${stdenvNoCC.hostPlatform.system} 向けのバイナリを宣言していない");
in
stdenvNoCC.mkDerivation {
  pname = "pnpm";
  inherit version;

  src = fetchurl {
    url = "https://github.com/pnpm/pnpm/releases/download/v${version}/pnpm-${source.platform}.tar.gz";
    inherit (source) hash;
  };

  # tarball は最上位に pnpm と dist/ を直接置く。既定の unpack は唯一のディレクトリ (dist/)
  # を sourceRoot に選んでしまうので、展開先そのものを使う
  sourceRoot = ".";

  nativeBuildInputs = [
    installShellFiles
    makeWrapper
  ];

  # Linux 版を patchelf せずに非 NixOS で動かすため、fixup は丸ごと無効化する
  dontFixup = true;

  # dist/ は配布物どおりバイナリの隣に置く。dist/ を PATH の bin に混ぜないよう 2 つを libexec に
  # まとめ、bin には実体を exec する wrapper を置く (実行ファイルの位置が libexec 側になる)。
  # pnpx / pn / pnx は nixpkgs 版と同じ
  installPhase = ''
    runHook preInstall
    mkdir -p $out/libexec/pnpm
    cp -r pnpm dist $out/libexec/pnpm/
    makeWrapper $out/libexec/pnpm/pnpm $out/bin/pnpm
    makeWrapper $out/libexec/pnpm/pnpm $out/bin/pnpx --add-flags dlx
    ln -s $out/bin/pnpm $out/bin/pn
    ln -s $out/bin/pnpx $out/bin/pnx
  ''
  # 補完はバイナリを実行して生成する。Linux 版は patchelf していないので、/lib64 の無い
  # ビルドの sandbox では起動できない。生成は darwin だけで行う
  + lib.optionalString stdenvNoCC.hostPlatform.isDarwin ''
    for sh in bash fish zsh; do
      $out/libexec/pnpm/pnpm completion $sh > pnpm.$sh
    done
    installShellCompletion pnpm.{bash,fish,zsh}
  ''
  + ''
    runHook postInstall
  '';

  meta = {
    description = "Fast, disk space efficient package manager for JavaScript";
    homepage = "https://pnpm.io/";
    changelog = "https://github.com/pnpm/pnpm/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "pnpm";
    platforms = builtins.attrNames sources;
  };
}
