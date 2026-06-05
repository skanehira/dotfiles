# TypeSpec language server (Mason の tsp_server と同等品)。
# nixpkgs 未収録。@typespec/compiler npm package が tsp-server / tsp バイナリを提供する。
#
# tarball に package-lock.json が同梱されないため buildNpmPackage がそのままでは使えない。
# 自前生成した prod-only の lockfile (tsp-server-package-lock.json) を postPatch で注入し、
# あわせて package.json から devDependencies を除去して `npm ci` の整合性チェックを通す。
# lockfile はバージョン完全固定なので、上流 npm のパッチ publish に依存せず再現性が保たれる。
#
# lockfile 更新手順:
#   1. compiler-<ver>.tgz を展開し package.json から devDependencies を削除
#   2. npm install --package-lock-only --omit=dev --legacy-peer-deps --ignore-scripts
#   3. 生成された package-lock.json を tsp-server-package-lock.json として保存
#   4. npmDepsHash を lib.fakeHash にして build → エラーの got 値を反映
{
  buildNpmPackage,
  fetchurl,
  jq,
  lib,
}:

buildNpmPackage rec {
  pname = "tsp-server";
  version = "1.11.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@typespec/compiler/-/compiler-${version}.tgz";
    hash = "sha256-ikyDIhonL3CXNxverZMHvCsDS3Bg2aX2pYUF/rw6gps=";
  };

  # devDependencies を除去し prod-only lockfile を注入。
  # この postPatch は buildNpmPackage から内部の fetchNpmDeps にも転送されるため、
  # 依存取得時にも同じ lockfile が参照される。
  postPatch = ''
    ${jq}/bin/jq 'del(.devDependencies)' package.json > package.json.tmp
    mv package.json.tmp package.json
    cp ${./tsp-server-package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-aCfbsFITCCuloBpyu5VAYXOJDgHhsHhAaLuHbPiAW4U=";

  # lockfile は --legacy-peer-deps で生成しているため npm ci も合わせる
  npmFlags = [ "--legacy-peer-deps" ];

  # registry tarball に dist/ がビルド済みで同梱されるためビルド不要
  dontNpmBuild = true;

  meta = {
    description = "TypeSpec language server";
    homepage = "https://github.com/microsoft/typespec";
    license = lib.licenses.mit;
    mainProgram = "tsp-server";
    platforms = lib.platforms.unix;
  };
}
