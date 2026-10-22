# nodejs.org の公式配布バイナリ (mac 用)。nixpkgs の nodejs_24 は使わない。
# nixpkgs の cc-wrapper は aarch64 で -mno-omit-leaf-frame-pointer を無条件に付けるため、
# DeepSeek Harness (dsh) が使う node-addon-require-builtin の照合 (Node の
# PrincipalRealm::builtin_module_require() が `ldr x0, [x0, #imm]; ret` の 2 命令である前提)
# に通らず、dsh が起動しない。フラグを打ち消したローカルビルドは通るが、Node の版が上がる
# たびに手元でビルドとテストが走る。公式版は Xcode の clang でビルドされ、照合に通る。
#
# 更新手順:
#   1. https://nodejs.org/dist/index.json で v24 系の最新 version を確認
#   2. version を書き換え、https://nodejs.org/dist/v<version>/SHASUMS256.txt の
#      node-v<version>-darwin-arm64.tar.gz の値を `nix hash convert --hash-algo sha256 --to sri <hex>`
#      で変換して hash に入れる
{
  stdenvNoCC,
  fetchurl,
  lib,
}:

let
  version = "24.22.1";

  sources = {
    aarch64-darwin = {
      platform = "darwin-arm64";
      hash = "sha256-icaCWT12zUQjP6U7FWMmTn3py7GJytFpE1xbT637wKc=";
    };
  };

  source =
    sources.${stdenvNoCC.hostPlatform.system}
      or (throw "nodejs-bin: ${stdenvNoCC.hostPlatform.system} 向けのバイナリを宣言していない");
in
stdenvNoCC.mkDerivation {
  pname = "nodejs-bin";
  inherit version;

  src = fetchurl {
    url = "https://nodejs.org/dist/v${version}/node-v${version}-${source.platform}.tar.gz";
    inherit (source) hash;
  };

  # 公式バイナリは署名済み。既定の fixup (strip) は署名を壊すので無効化する。
  # npm / npx / corepack の shebang は `#!/usr/bin/env node` のまま PATH の node を使う
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -R bin include lib share $out/
    runHook postInstall
  '';

  meta = {
    description = "Node.js official prebuilt binary";
    homepage = "https://nodejs.org";
    license = lib.licenses.mit;
    mainProgram = "node";
    platforms = builtins.attrNames sources;
  };
}
