{ username, ... }:

{
  # Codex の system レイヤー (/etc/codex/config.toml)。Codex はこの層に書き込まないので、
  # ~/.codex/config.toml を Codex 自身の可変状態 (project trust / notices 等) に明け渡せる。
  # 文字列パスなので nix store にコピーされず、dotfiles 直接 symlink として live edit できる。
  environment.etc."codex/config.toml".source =
    "/Users/${username}/dev/github.com/skanehira/dotfiles/agents/bindings/codex/config.toml";
}
