# TypeSpec language server (Mason の tsp_server と同等品)。
# nixpkgs 未収録。@typespec/compiler npm package が tsp-server バイナリを提供するが
# 17 個の runtime 依存が tarball には含まれないため、FOD (fixed-output derivation) で
# `npm install --omit=dev` を走らせて node_modules を vendoring する。
{ stdenv, fetchurl, nodejs, cacert, makeWrapper, lib }:

let
  pname = "tsp-server";
  version = "1.11.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@typespec/compiler/-/compiler-${version}.tgz";
    hash = "sha256-ikyDIhonL3CXNxverZMHvCsDS3Bg2aX2pYUF/rw6gps=";
  };

  # FOD: outputHash を固定して network access を許可しつつ deps を取得。
  # package-lock.json が tarball に無いので buildNpmPackage は使えない (代わりに
  # outputHash で再現性を確保する form を取る)
  npmDeps = stdenv.mkDerivation {
    name = "${pname}-deps-${version}";
    inherit src;
    nativeBuildInputs = [ nodejs cacert ];

    buildPhase = ''
      runHook preBuild
      export HOME=$(mktemp -d)
      npm install --omit=dev --no-audit --no-fund --legacy-peer-deps --ignore-scripts --prefix .
      runHook postBuild
    '';

    installPhase = ''
      mkdir -p $out
      cp -r node_modules $out/
    '';

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-poVVoS2RtxenJ66CXw0w+U/0tGeSCTI6u9wmbppbGAg=";
  };
in

stdenv.mkDerivation {
  inherit pname version src;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    # ${pname}/ 配下に押し込むことで、他の node ベース LSP と
    # `lib/package.json` などが競合するのを防ぐ (home.packages の buildEnv 対策)
    mkdir -p $out/lib/${pname} $out/bin
    cp -r * $out/lib/${pname}/
    cp -r ${npmDeps}/node_modules $out/lib/${pname}/

    makeWrapper ${nodejs}/bin/node $out/bin/tsp-server \
      --add-flags $out/lib/${pname}/cmd/tsp-server.js

    # tsp 本体も同梱 (Mason は tsp-server だけだが、cli はあった方が便利)
    makeWrapper ${nodejs}/bin/node $out/bin/tsp \
      --add-flags $out/lib/${pname}/cmd/tsp.js

    runHook postInstall
  '';

  meta = {
    description = "TypeSpec language server";
    homepage = "https://github.com/microsoft/typespec";
    license = lib.licenses.mit;
    mainProgram = "tsp-server";
    platforms = lib.platforms.unix;
  };
}
