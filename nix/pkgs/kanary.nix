# Kanary (macOS 音声入力アプリ)。Homebrew cask 未収録のため自前 derivation。
# アプリ内蔵の Sparkle 自動更新 (SUFeedURL: https://cdn.kanary.download/appcast.xml) は
# nix store が read-only のため機能しない。
#
# 更新手順:
#   1. https://cdn.kanary.download/appcast.xml で最新 version を確認
#   2. version を書き換え、hash を lib.fakeHash にして build → エラーの got 値を反映
{
  stdenvNoCC,
  fetchurl,
  unzip,
}:

stdenvNoCC.mkDerivation rec {
  pname = "kanary";
  version = "3.3.3";

  src = fetchurl {
    url = "https://cdn.kanary.download/releases/Kanary-${version}.zip";
    hash = "sha256-98Q46q6qAH6fA4oJ12XYffDOF+TGIBTIN8G+QomUkG4=";
  };

  nativeBuildInputs = [ unzip ];

  # zip 直下に Kanary.app と __MACOSX が並ぶため単一 root の自動検出が効かない
  sourceRoot = ".";

  # Developer ID 署名済みの .app。strip / patchShebangs 等の fixup は署名を壊すため無効化
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/Applications
    cp -R Kanary.app $out/Applications/
    runHook postInstall
  '';

  meta = {
    description = "AI voice dictation app for macOS";
    homepage = "https://kanary.download";
    platforms = [ "aarch64-darwin" ];
  };
}
