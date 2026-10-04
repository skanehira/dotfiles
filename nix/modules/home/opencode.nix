{
  config,
  lib,
  pkgs,
  dotfilesRoot,
  ...
}:

{
  # 設定は dotfiles repo への直接 symlink (mkOutOfStoreSymlink) で扱う。
  # claude.nix と同じ方針で、編集が drs 不要で即反映される (live edit)。
  # OpenCode V2 の常駐サービスが設定ファイルの変更を検知して読み直す実装はソースにあるが、
  # 反映を実際に確かめてはいない (変更が効いていないように見えたら opencode service restart)。
  #
  # symlink するのはファイル単位にする。~/.config/opencode/ には dotfiles 以外のもの
  # (常駐サービスの service.json、V1 のプラグイン SDK を入れた node_modules など) が
  # 同居しており、ディレクトリごと貼ると dotfiles に流れ込むため。service.json は
  # symlink ではなく下の opencodeServiceConfig activation で hostname だけ管理する。
  #
  # OpenCode は DGX Spark 専用で、接続先は Tailscale の MagicDNS 名 (spark-head) に固定
  # している。自宅 LAN の mDNS 名は使わない。vLLM が認証を要求しないので API キーは
  # 持たない (詳細は agents/rules/infra/dgx-spark.md)。
  home.file.".config/opencode/opencode.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/agents/bindings/opencode/opencode.json";

  # 配信中のモデルだけを有効にして既定に据えるローカルプラグイン。V2 は
  # ~/.config/opencode/plugins/ 直下の *.ts を自動で読み込む。テスト
  # (spark-served_test.ts) は配らない。
  home.file.".config/opencode/plugins/spark-served.ts".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/agents/bindings/opencode/plugins/spark-served.ts";

  # cli.json (keybinds / theme) も symlink で配る。起動しただけでは V2 は書き換えない。
  # ただし TUI でテーマ等を変えると、V2 は一時ファイルを書いて rename で置き換えるので
  # symlink が実ファイルに化け、repo との同期が黙って切れる。設定は repo 側を編集して変える。
  home.file.".config/opencode/cli.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/agents/bindings/opencode/cli.json";

  # グローバル指示は OpenCode 専用の文書を symlink で配る。共通の正本 agents/AGENTS.md を
  # 参照し、Claude 綴りの語彙を OpenCode の語彙へ読み替える規約を書いてある。
  #
  # V2 がグローバル指示として読むのは ~/.config/opencode/AGENTS.md の 1 本だけで、
  # ~/.claude/CLAUDE.md へのフォールバックは無い。配る文書側に「正本を Read せよ」と
  # 書いてあるので、共通ハーネスはそこから届く。
  home.file.".config/opencode/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/agents/bindings/opencode/AGENTS.md";

  # subagent だけは symlink で共有できない (OpenCode は description / mode の別スキーマを
  # 要求し、正本の frontmatter をそのまま読めない)。codex.nix の syncCodexSubagents と
  # 同じスクリプトを opencode 形式で回す。変換元から消えた .md はスクリプト側が prune する。
  # deno を使うので bootstrapDeno の後に置く。
  home.activation.syncOpencodeSubagents = lib.hm.dag.entryAfter [ "bootstrapDeno" ] ''
    if [ -x "$HOME/.deno/bin/deno" ]; then
      run "$HOME/.deno/bin/deno" run --allow-read --allow-write \
        "${dotfilesRoot}/agents/scripts/sync-subagents.ts" \
        "${dotfilesRoot}/agents/subagents" "$HOME/.config/opencode/agents" opencode
    else
      warnEcho "deno が無いので ~/.config/opencode/agents の同期をスキップした"
    fi
  '';

  # 常駐サービスの service.json (hostname / password) は宣言ファイルにせず、hostname だけを
  # ここで上書きする。理由は 2 つ。(1) このファイルには opencode service set が生成した
  # パスワードが入る。repo は PUBLIC なので dotfiles 側に置けない。(2) opencode は
  # service set 時に一時ファイルの rename で書き換える (cli.json と同じ) ので、symlink で
  # 配ると同期が切れる。サーバー起動自体は設定ディレクトリに書かない (serve を隔離した
  # 設定ディレクトリで起動して確認)。既存ファイルを jq で merge し、password など他の
  # キーは温存する。反映に opencode service restart が要る点は cli.json と同じ。
  home.activation.opencodeServiceConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    cfg="$HOME/.config/opencode/service.json"
    mkdir -p "$HOME/.config/opencode"
    if ${pkgs.jq}/bin/jq -e 'type == "object"' "$cfg" >/dev/null 2>&1; then
      run "${pkgs.jq}/bin/jq" '.hostname = "0.0.0.0"' "$cfg" > "$cfg.tmp"
    else
      warnEcho "$cfg が読めないので service.json を新規作成した"
      echo '{"hostname":"0.0.0.0"}' > "$cfg.tmp"
    fi
    run mv "$cfg.tmp" "$cfg"
  '';
}
