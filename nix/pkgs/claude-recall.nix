# claude-recall (Claude Code セッションを SQLite に保存し、MCP / TUI / Web UI で検索する)。
# nixpkgs 未収録のため自前 derivation。GitHub Releases に platform 別の静的 Go バイナリが
# あるので、それを置くだけで済む (ローカルビルドは走らない)。リリースに同梱の Claude Code
# プラグイン (claude-recall-plugin.tar.gz) は使わない。MCP は `claude mcp add` で直接登録する。
#
# 更新手順:
#   1. gh release view --repo babarot/claude-recall で最新 version を確認
#   2. version を書き換え、各 platform の hash を、同リリースの checksums.txt の hex を
#      nix hash convert --hash-algo sha256 --to sri <hex> で変換した値に差し替える
{
  stdenvNoCC,
  fetchurl,
}:

let
  version = "1.7.2";
  base = "https://github.com/babarot/claude-recall/releases/download/${version}";

  # nix の system → リリースのアセット名と hash
  sources = {
    aarch64-darwin = {
      asset = "claude-recall-darwin-arm64";
      hash = "sha256-ek87Up/wCM8Lj7ATw3eBFen5r5slT64HlQC9wNs/0fc=";
    };
    x86_64-darwin = {
      asset = "claude-recall-darwin-x86_64";
      hash = "sha256-veoikTqDdBESuZOyimXB+0xK1KRXANWgOtYkurMUyxA=";
    };
    aarch64-linux = {
      asset = "claude-recall-linux-arm64";
      hash = "sha256-gzxbaSUZONss8Rl1NJMKdt4xXiJQnRXWiNlC91TCPJs=";
    };
    x86_64-linux = {
      asset = "claude-recall-linux-x86_64";
      hash = "sha256-+9rAQmSM3J/0w1h68kFtUdmTgEAdbmdXUsQJ86zFfpw=";
    };
  };

  source =
    sources.${stdenvNoCC.hostPlatform.system}
      or (throw "claude-recall: ${stdenvNoCC.hostPlatform.system} 向けのバイナリを宣言していない");
in
stdenvNoCC.mkDerivation {
  pname = "claude-recall";
  inherit version;

  src = fetchurl {
    url = "${base}/${source.asset}";
    inherit (source) hash;
  };

  # src はアーカイブではなく実行ファイルそのものなので展開しない
  dontUnpack = true;

  # 静的リンクの Go バイナリ。strip / patchelf は不要
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/recall
    runHook postInstall
  '';

  meta = {
    description = "Searchable archive of Claude Code sessions (CLI, MCP and web UI)";
    homepage = "https://github.com/babarot/claude-recall";
    mainProgram = "recall";
    platforms = builtins.attrNames sources;
  };
}
