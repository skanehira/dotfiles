# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

- 種別: プロジェクト運用ガイド

## Repository Overview

dotfiles リポジトリ。macOS は **Nix (nix-darwin + Home Manager)**、Linux は **Home Manager standalone (非 NixOS)** で宣言的管理。設定ファイルは `home.file` × `mkOutOfStoreSymlink` で dotfiles 直接 symlink としてバインドし、live edit を維持する。

## Installation

### 初回セットアップ (macOS 新マシン)

```bash
# clone 先は ~/dev/github.com/skanehira/dotfiles 固定
# (nix/home-core.nix の dotfilesRoot がこの path を literal で持ち、各 module の
#  mkOutOfStoreSymlink と darwin/codex.nix の environment.etc がそれを参照するため)
mkdir -p ~/dev/github.com/skanehira
cd ~/dev/github.com/skanehira
git clone https://github.com/skanehira/dotfiles.git
cd dotfiles

# Nix install + nix-darwin 適用
bash ./bootstrap.sh
```

`bootstrap.sh` は (1) Nix 未導入時のみ公式 installer を実行し、(2) `nix-daemon` の socket が無ければ `launchctl load` し、(3) `nix/install.sh` 経由で `sudo nix run nix-darwin -- switch --flake .#skanehira` を回す。途中で Nix installer の y/n プロンプトと `sudo` (Touch ID / パスワード) が要求される。既存マシンでは Nix install を skip するので idempotent。

### 初回セットアップ (Linux 新マシン、非 NixOS)

```bash
# Nix インストール (multi-user; systemd 不在の container では --no-daemon に切り替える)
sh <(curl -L https://nixos.org/nix/install) --daemon

# experimental-features を nix.conf に永続化
# (`nix run home-manager/master` はネストした nix 呼び出しが走るため、
#  コマンドラインの --extra-experimental-features では伝播せず disabled エラーになる)
mkdir -p ~/.config/nix
echo 'experimental-features = nix-command flakes' > ~/.config/nix/nix.conf

mkdir -p ~/dev/github.com/skanehira
cd ~/dev/github.com/skanehira
git clone https://github.com/skanehira/dotfiles.git

cd dotfiles/nix
nix run home-manager/master -- switch --flake ".#skanehira"
```

aarch64 マシンは `.#skanehira` を `.#skanehira-aarch64` に置換する。Linux 専用 bootstrap script は用意していない (上記コマンドを手で叩く)。

activation 中に `modules/home/codex.nix` が `sudo` で `/etc/codex/config.toml` を `agents/bindings/codex/config.toml` へ symlink する (Home Manager standalone には `/etc` を宣言する option が無いため。`codex.nix` を import しない `-android` は対象外)。`sudo` が使えない環境では警告と手動コマンドが表示されるだけで activation は失敗しない。

`linuxUsers` に列挙したユーザーごとに 3 つの output が生える。用途で選ぶ。

| output | system | 入口 | 用途 |
| --- | --- | --- | --- |
| `.#<user>` | x86_64-linux | `home-linux.nix` | 通常の Linux (Ubuntu container / サーバー) |
| `.#<user>-aarch64` | aarch64-linux | `home-linux.nix` | 同上の arm 版 |
| `.#<user>-android` | aarch64-linux | `home-android.nix` | Android の Termux + proot-distro Debian |

ログインユーザーが `skanehira` でないマシン (CI / 検証箱など) では、`flake.nix` の `linuxUsers` にそのユーザー名を足してから `.#<ユーザー名>` を指定する (`ubuntu` は既に列挙済みなので `.#ubuntu` がそのまま使える)。`$USER` を動的に読む impure 方式は `nh` / `home-manager` が pure 評価で output を引くため `hms` 等で壊れる。よって pure に列挙する。

### 初回セットアップ (Android / Galaxy Z Fold 8 Ultra)

Snapdragon 機は Android 標準の Linux ターミナル (AVF = Android Virtualization Framework) を起動できないので、Termux + proot-distro Debian を使う。手順とその根拠は `docs/android-dev-setup.md` にまとめてある。通常の Linux とは以下が違う。

- Nix は single-user (`--no-daemon`)。proot に systemd が無いため
- `~/.config/nix/nix.conf` に `sandbox = false` が要る。proot は user namespace を作れないため
- proot 内のユーザー名は `skanehira` にする (`linuxUsers` に既にあるので flake の変更が要らない)
- 適用は `.#skanehira-android`。フルセットではなく軽量プロファイルが当たる

### 設定変更を反映

```bash
# macOS
drs   # alias: noglob nh darwin switch ~/dev/.../nix -H skanehira

# Linux (Home Manager standalone)
hms   # alias: noglob nh home switch ~/dev/.../nix -c <configName>
```

両 alias は `zsh.nix` の `programs.zsh.shellAliases` で OS 別に `lib.optionalAttrs` 分岐済 (darwin=drs / linux=hms)。手動でフルコマンドを叩くより楽。

設定名は `nh` の `-H` (darwin) / `-c` (home) で**明示**する。`nh` 4.x は `<flake>#name` の `#name` を素の flake 属性として解決し (`darwinConfigurations` / `homeConfigurations` を前置しない) `#name` では引けないため。

`hms` の `-c` には **flake の attr 名そのもの** (`configName`) が入る。`flake.nix` の `mkLinuxHome` が output 名と同じ文字列を `extraSpecialArgs` で `zsh.nix` に渡し、`zsh.nix` がそれを alias に埋める。したがって aarch64 では `-c skanehira-aarch64`、Android では `-c skanehira-android` になる。ここに username を埋めると aarch64 機でも `-c skanehira` を渡すことになり、x86_64 用の config を掴んで失敗する。

### Linux 動作確認 (Ubuntu container、ad-hoc)

container 関連ファイルは repo に置かない (検証用途のみ)。下記を mac から直接叩く:

```bash
docker run --rm -it --platform linux/amd64 \
  -v ~/dev/github.com/skanehira/dotfiles:/dotfiles:ro \
  ubuntu:24.04 bash -c '
    set -e
    apt-get update -qq
    apt-get install -y -qq curl xz-utils sudo git ca-certificates locales
    locale-gen en_US.UTF-8
    useradd -ms /bin/bash skanehira
    echo "skanehira ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
    su - skanehira -c "
      curl -L https://nixos.org/nix/install | sh -s -- --no-daemon
      mkdir -p ~/.config/nix
      echo experimental-features = nix-command flakes > ~/.config/nix/nix.conf
      mkdir -p ~/dev/github.com/skanehira
      cp -r /dotfiles ~/dev/github.com/skanehira/dotfiles
      cd ~/dev/github.com/skanehira/dotfiles/nix
      ~/.nix-profile/bin/nix --extra-experimental-features \"nix-command flakes\" \
        run home-manager/master -- switch --flake .#skanehira
      exec zsh
    "
  '
```

aarch64 検証は `--platform linux/arm64` + flake target を `.#skanehira-aarch64` に変える。

## Directory Structure

### Nix 管理（中核）

- **nix/** — flake-based config（最も重要）
  - `flake.nix` — inputs, outputs (`darwinConfigurations.skanehira` + `homeConfigurations` = `linuxUsers` × 3 プロファイル。現在は `skanehira` / `ubuntu` の 2 ユーザーで 6 output + `packages` + `formatter`)
  - `home-core.nix` — 全プロファイル共通の土台 (dotfilesRoot / stateVersion / programs.home-manager)。module の import は持たない
  - `home.nix` — フルセットのプロファイル (mac と通常 Linux が共有)
  - `home-darwin.nix` — mac 用エントリ (home.nix + mac 専用 3 module (karabiner / wezterm / mac-app-util-icons) + `homeDirectory = /Users/...`)
  - `home-linux.nix` — 通常 Linux 用エントリ (home.nix + `homeDirectory = /home/...`)
  - `home-android.nix` — Android (Termux + proot) 用エントリ (home-core.nix + 軽量 module のみ)
  - `darwin.nix` — nix-darwin imports のみ
  - `modules/home/` — Home Manager modules（CLI パッケージ、env、git、gh、zsh、fzf、direnv、tmux、wezterm、karabiner 等）
  - `modules/darwin/` — nix-darwin modules（system、homebrew、codex、sleepctl）
  - `modules/overlays.nix` — nix-darwin 用 overlays モジュール (overlays-list.nix を消費)
  - `modules/overlays-list.nix` — overlay の素のリスト (mac/Linux 両側で共有)
  - `install.sh` — mac bootstrap 用（一度限り）
  - `pkgs/` — nixpkgs 未収録ツールの自前 derivation (tsp-server / gh-actions-language-server / kanary)

### Nix 補助

- **zsh/** — `programs.zsh.initContent` から `builtins.readFile` で取り込まれる残置ファイル
  - `zshrc` — bindkey 群 + 関数 source loop
  - `functions/*.zsh` — カスタム zsh 関数 7 本。`ghq-fzf` / `gss` / `tmuxpopup` の 3 本と、DGX Spark 系の `claude-deepseek` (`ccsp` / `ccds`) / `codex-spark` (`cxsp`) / `spark-common` の 3 本、mac 専用の `sleepctl`
- **karabiner/** — Karabiner-Elements 設定 (Goku DSL)
  - `karabiner.edn` — EDN で書いたルール、switch 時に goku が `~/.config/karabiner/karabiner.json` を生成
- **wezterm/** — WezTerm 設定（`mkOutOfStoreSymlink` で dotfiles 直接 symlink、live edit 可能）
  - `wezterm.lua` — `programs.wezterm.extraConfig` は使わず直接 symlink する。Lua の編集体験 (lua_ls) を保ち、`drs` 無しで反映するため
- **tmux/** — tmux 設定（`mkOutOfStoreSymlink` で dotfiles 直接 symlink、live edit 可能）
  - `tmux.conf` — 編集即反映、`prefix + r` で reload。`drs` 不要
  - プラグインの run-shell だけは nix store path 解決のため Nix 生成の `~/.config/tmux/plugins.conf` 経由
- **agents/** — AI エージェント共通のハーネス正本（両ランタイムが同じ実体を読む。配布は正本への symlink が基本で live edit 可能）
  - `AGENTS.md` / `rules/` / `skills/` / `subagents/` は正本への symlink なので編集即反映。例外はスキルの追加・削除と subagent の変更で、`drs` / `hms` が要る (どれがどれかは「live edit の範囲」の表を参照)
  - `hooks/` / `scripts/` / `knowledge-profile.md` と `bindings/` の各ファイルも直 symlink
  - 配布先と構成は「AI エージェントのハーネス (agents/)」節を参照
- **agents/bindings/codex/** — Codex 固有の設定 (ハーネス本体は `agents/` 直下)
  - `config.toml` — git 管理する Codex 共通設定。Codex の system レイヤー `/etc/codex/config.toml` として dotfiles 直接 symlink され、CLI / ChatGPT.app 内 Codex を含む全クライアントに読まれる (live edit 可能)
  - `config.toml` に hooks は書いていない。このハーネスは機械ゲートを 1 本も持たないので移植すべきものが無い。将来 Codex へ hook を配るときの置き場とレイヤーごとの発火差は `AGENTS.md` の「hooks を追加するときの置き場」節にある
  - `AGENTS.md` — Codex のグローバル指示。`~/.codex/AGENTS.md` へ symlink され、共通の正本 (`~/.claude/CLAUDE.md`) を読む指示と Claude 綴りの読み替え表を持つ
  - `~/.codex/config.toml` (user レイヤー) は dotfiles で管理しない。Codex 自身が `[projects.*]` trust / `[notice]` / `/model` の選択 / `notify` / `[plugins.*]` を書き込む可変状態で、ここにあるキーは system レイヤー (`/etc/codex/config.toml`) の同名キーより優先され続ける。`[mcp_servers.*]` は両レイヤーに現れる。全マシン共通のサーバ (context7 / chrome-devtools) は `config.toml` で配り、マシン固有のものは Codex が user レイヤーに書く
  - 旧方式 (Home Manager が `~/.codex/config.toml` を生成) を使っていたマシンでは、`drs` / `hms` 後に 1 回だけ `~/.codex/config.toml` から重複するキーを手で削除する。残さないと `/etc` 側の値が遮蔽される
  - 配布の確認: `readlink -f /etc/codex/config.toml` が dotfiles の `agents/bindings/codex/config.toml` に解決すること
  - **プラグインだけは宣言的に管理できない。** `config.toml` に `[marketplaces.*]` を書くと空ディレクトリを見に行って失敗し、`[plugins.*]` を書いても `not installed` のまま。`codex.nix` の activation が `codex plugin marketplace add` と `codex plugin add` を冪等に流す (対象は Claude 側と同じ 6 本: document-skills / frontend-design / ui-ux-pro-max / compact-plus / archify / slide-plugin)。Claude 形式の `.claude-plugin/marketplace.json` をそのまま読むので、リポジトリ側に Codex 用のマニフェストは要らない
- **vim/** — Neovim 設定（`mkOutOfStoreSymlink` で dotfiles 直接 symlink、live edit 可能）
  - `init.lua` / `lua/` / `after/` — 編集即反映、`drs` 不要
  - `.luarc.json` — lua_ls の dotfiles 内 lua 編集用設定 (track 対象)
- **herdr/** — herdr (コーディングエージェント用のターミナル多重化) の設定
  - `config.toml` — `herdr.nix` が `~/.config/herdr/config.toml` へ mkOutOfStoreSymlink する
  - **プラグインだけは宣言的に管理できない。** `config.toml` は `type = "plugin_action"` で参照するのみで、宣言的に導入する手段は無い (実測: herdr 0.7.4、2026-09-11。`herdr --default-config` にも plugin セクションが無く、HM の `programs.herdr` も enable/package/settings の 3 オプションのみ)。導入状態は `~/.config/herdr/` 配下の herdr 所有ファイルにあり、Nix 管理外
  - `herdr.nix` の activation が、未導入時のみ `herdr plugin install <owner>/<repo> --yes` を流す。対象は `persiyanov/herdr-reviewr` (id: `persiyanov.reviewr`) と `ChmaraX/herdr-nvim` (id: `chmarax.herdr-nvim`) の 2 本。導入判定は `herdr plugin list --plugin <id>` の出力 grep で、非対話では `--yes` が必須。導入済みへの再実行は再ダウンロードになるため skip するので、更新は手動で同じ install を流す (refresh 経路)。失敗しても activation は警告のみで止まらない (`herdr plugin list` で確認できる)。撤去は自動でやらず、リストから外しても残る (`herdr plugin uninstall` を手で流す)。`chmarax.herdr-nvim` は Neovim 側の `vim/lua/plugins/ai/herdr-nvim.lua` と対で動く
- **リポジトリ直下** — `AGENTS.md` (このリポジトリで作業する agent 向けの repo スコープ指示。グローバル指示の正本 `agents/AGENTS.md` とは別物) / `bootstrap.sh` (mac 初回セットアップの入口) / `README.md` / `.github/workflows/nix-check.yml` (nix/** の push で flake check と fmt を回す CI)
- **docs/** — Nix 設定だけでは伝わらない環境固有の手順書
  - `android-dev-setup.md` — Galaxy Z Fold 8 Ultra を Termux + proot-distro Debian で開発端末にする手順と制約

## Nix モジュール構成（詳細）

```
nix/
├── flake.nix              ← inputs + darwinConfigurations + homeConfigurations + packages + formatter
├── flake.lock
├── home-core.nix          ← 全プロファイル共通の土台 (module の imports は持たない)
├── home.nix               ← フルセット (home-core.nix + 全 module の imports)
├── home-darwin.nix        ← home.nix + karabiner / wezterm / mac-app-util-icons + homeDirectory=/Users/...
├── home-linux.nix         ← home.nix + homeDirectory=/home/...
├── home-android.nix       ← home-core.nix + 軽量 module + homeDirectory=/home/...
├── darwin.nix             ← imports modules/darwin/
├── install.sh             ← mac bootstrap
├── pkgs/                  ← 自前 derivation (tsp-server / gh-actions-language-server / kanary)
└── modules/
    ├── overlays.nix       ← nix-darwin 用 module (overlays-list.nix を nixpkgs.overlays に流す)
    ├── overlays-list.nix  ← overlay の素のリスト (HM standalone の pkgs= からも参照)
    ├── home/
    │   ├── claude.nix    — Claude Code (bootstrap install + ハーネス正本と Claude 固有の設定を symlink)
    │   ├── codex.nix     — Codex 向けの symlink (~/.codex/AGENTS.md) + スキルの個別 symlink (linkAgentSkills) と subagent の TOML 変換 (syncCodexSubagents) + プラグイン導入 (activation)。Linux のみ /etc/codex/config.toml を sudo で symlink
    │   ├── deno.nix      — bootstrap-install (~/.deno/bin/deno 不在時のみ公式 installer 実行)
    │   ├── direnv.nix    — programs.direnv + nix-direnv
    │   ├── env.nix       — sessionVariables / sessionPath
    │   ├── fzf.nix       — programs.fzf (default command/options, zsh integration)
    │   ├── gh.nix        — programs.gh (GitHub CLI)
    │   ├── git.nix       — programs.git (LFS, alias, difftastic)
    │   ├── herdr.nix     — herdr の config.toml を mkOutOfStoreSymlink で live edit + プラグイン導入 (activation。mac / 通常 Linux のみ。home-android.nix は import しない)
    │   ├── karabiner.nix — goku で karabiner.edn → karabiner.json (mac only。home-darwin.nix からのみ import)
    │   ├── mac-app-util-icons.nix — .app の trampoline アイコン調整 (mac only)
    │   ├── neovim.nix    — vim/{init.lua,lua,after} を mkOutOfStoreSymlink で live edit
    │   ├── packages.nix  — home.packages 群（言語ランタイム / LSP / CLI を 13 カテゴリで宣言、約 100 件。vite-plus / nvtop / libreoffice-bin / terminal-notifier / screen-capture-mcp-server / kanary は darwin only）
    │   ├── packages-android.nix — Android 用の明示リスト (18 エントリ。binary cache から取れる軽量なものだけ)
    │   ├── rustup.nix    — bootstrap-install (~/.cargo/bin/rustup 不在時のみ公式 installer 実行)
    │   ├── tmux.nix      — tmux/tmux.conf を mkOutOfStoreSymlink で live edit。plugins.conf のみ Nix 生成 (resurrect + themepack)
    │   ├── vite-plus-bootstrap.nix — bootstrap-install (~/.vite-plus/bin/vp 不在時のみ公式 installer 実行。Android のみ import)
    │   ├── wezterm.nix   — programs.wezterm (extraConfig は wezterm.lua を readFile)
    │   └── zsh.nix       — programs.zsh (history, completion, prompt、homebrew/linuxbrew 分岐済) + shellAliases (drs/hms を OS 別 lib.optionalAttrs。hms の -c には configName が入る)
    └── darwin/
        ├── codex.nix     — /etc/codex/config.toml を agents/bindings/codex/config.toml へ symlink (environment.etc)
        ├── homebrew.nix  — declarative brews / casks
        ├── sleepctl.nix  — 蓋閉じ監視デーモン (disablesleep 中に蓋を閉じたら pmset displaysleepnow を 1 回打つ)
        └── system.nix    — users, nix.settings, Touch ID, primaryUser
```

### 重要な設計判断

- **設定の key**: ホスト名は使わない。複数マシンで同じ設定が走る前提。`darwinConfigurations` の key は username (`skanehira`)、`homeConfigurations` の key は `configName` (username にプロファイル接尾辞を足したもの。`skanehira` / `skanehira-aarch64` / `skanehira-android`)。
- **system 値**: darwin は `aarch64-darwin` 固定 (Apple Silicon)。Linux は `skanehira` (x86_64-linux)、`skanehira-aarch64` (aarch64-linux)、`skanehira-android` (aarch64-linux) の 3 出力。
- **モジュール共有**: `home-core.nix` が全プロファイル共通の土台 (dotfilesRoot / stateVersion / programs.home-manager) で、module の import は持たない。「どのツールを入れるか」はプロファイル側の決定なので、`home.nix` (フルセット) と `home-android.nix` (軽量) がそれぞれ import 一覧を持つ。`home-darwin.nix` / `home-linux.nix` は `home.nix` に homeDirectory を足す wrapper。mac 専用 module は `karabiner.nix` / `wezterm.nix` / `mac-app-util-icons.nix` で `home-darwin.nix` からだけ import。`tmux.nix` / `zsh.nix` は内部で `lib.optionalString isDarwin/isLinux` 分岐済。
- **Android を別プロファイルにする理由**: proot は RAM が数 GB でストレージも Termux のアプリ内領域に載り、binary cache に無いものをローカルビルドできない。フルセットは完走しないため、`packages-android.nix` に軽量なものを 19 エントリだけ明示列挙する (`programs.git` 等が足す分と HM 内部を含めて `home.packages` は 34 件)。規模の差は下表のとおり。neovim は nightly overlay ではなく nixpkgs の stable を使う。

  | プロファイル (aarch64-linux) | ローカルビルド | fetch 件数 | ダウンロード | 展開後 |
  | --- | --- | --- | --- | --- |
  | `skanehira-android` | 46 件 (全て HM の設定生成と wrapper。コンパイルなし) | 325 | 542.4 MiB | 1.9 GiB |
  | `skanehira-aarch64` (フルセット) | 693 件 (neovim nightly / terraform / herdr 等のコンパイルを含む) | 1545 | 3.5 GiB | 13.0 GiB |

  計測条件: 2026-09-06、mac (aarch64-darwin) から `nix build --dry-run` を両者連続実行。Claude Code / Deno / Vite+ は activation 時に公式インストーラを走らせるので、この数値には含まれない。fetch 件数は実行マシンの nix store に既にある分を除いた値なので、まっさらな端末では増える。
- **overlays の共有**: `modules/overlays-list.nix` が overlay の素のリストを export し、nix-darwin (`modules/overlays.nix` 経由) と HM standalone (`flake.nix` の `import nixpkgs` 経由) の両方から参照される。
- **Homebrew**: GUI app (cask) と CLI のうち (a) cask の依存になるコア formula、(b) nixpkgs 未収録 (例: `aqua`) のみ管理 (mac only)。それ以外の CLI ツールは Nix 管理。`brews` には `ca-certificates` / `openssl@3` を保険として (cask 依存リンクが切れた時の巻き添え削除を防止)、`aqua` を nixpkgs 未収録の CLI として明示宣言。`onActivation.cleanup = "uninstall"` で宣言外は drs 時に自動撤去。
- **Touch ID for sudo**: `security.pam.services.sudo_local.touchIdAuth + reattach` で tmux 内含めて指紋認証 (mac only)。

## sudo の扱い（重要）

このマシンでは `pam_tid` (Touch ID) + `pam_reattach` (tmux 対応) が `/etc/pam.d/sudo_local` に設定済み。

### ⚠️ `sudo -n` (`--non-interactive`) は使わない

`-n` フラグは PAM 認証を**完全にスキップ**する。Touch ID プロンプトすら出ない。代わりに「a password is required」エラーで即終了する。

```bash
# ❌ Touch ID が呼ばれず失敗する
sudo -n darwin-rebuild switch ...

# ✅ Touch ID ダイアログが出て指紋で通せる（TTY なし環境でも OK）
sudo darwin-rebuild switch ...
```

スクリプトや Claude Code の Bash ツールから `sudo` を呼ぶときも同様。`-n` を付けないことで PAM が GUI 認証ダイアログを発火させ、ユーザの指紋で認証できる。

## Nix daemon のトラブルシュート (macOS)

`drs` が下記で即落ちする場合、`nix-daemon` (launchd) が落ちている。

```
error: cannot connect to socket at '/nix/var/nix/daemon-socket/socket': Connection refused
```

### 状態確認

```bash
# nix-daemon が launchctl にロードされているか (PID が出ていれば起動中)
sudo launchctl list | grep org.nixos.nix-daemon

# daemon 経由で nix store に疎通するか
nix store info
```

`sudo launchctl list` に `org.nixos.nix-daemon` の行が無い、または PID 列が `-` ならデーモンは未起動。

### 復旧手順

```bash
sudo launchctl load /Library/LaunchDaemons/org.nixos.nix-daemon.plist
```

ロード後、再度 `sudo launchctl list | grep nix-daemon` で PID が振られていれば OK。`drs` をリトライできる。

### 補足

- plist 本体は Determinate Systems の Nix installer が `/Library/LaunchDaemons/org.nixos.nix-daemon.plist` に配置している。`darwin-rebuild` ではなく Nix installer の所有物。
- 一度 `load` すれば再起動後も自動起動する想定。再発する場合は plist の `KeepAlive` が無効化されていないか、`nix-darwin` 側で `nix.enable = false` 相当の設定が混入していないか (`nix/modules/darwin/system.nix`) を確認する。
- `/Library/LaunchDaemons/systems.determinate.nix-installer.nix-hook.plist` は別物 (Determinate の post-install hook)。混同しない。

## Neovim Configuration

### Structure
- `vim/lua/plugins/` — lazy.nvim プラグイン設定
- `vim/lua/settings/` — 基本設定（options.lua, keymaps.lua, lsp.lua, autocmd.lua, disable.lua）
- `vim/lua/modules/` — カスタムモジュール（AI, markdown）
- `vim/after/lsp/` — LSP 個別設定 (denols, rust_analyzer, lua_ls, nixd, tsgo, version_ls, yamlls)

### Key Paths
- ghq リポジトリ: `$HOME/dev`
- Go バイナリ: `$HOME/go/bin`
- Deno バイナリ: `$HOME/.deno/bin`

### Neovim 本体

フルセット (mac / 通常 Linux) は `neovim-nightly-overlay` の **nightly ビルド**を使う。binary cache が無く更新時は手元でビルドする。アップデートは `nix flake update neovim-nightly-overlay`。

Android プロファイルだけは `pkgs.neovim` (nixpkgs-unstable の **stable release**、`cache.nixos.org` 経由でビルド済) を使う。proot で nightly をビルドできないため。こちらのアップデートは `nix flake update nixpkgs`。

## AI エージェントのハーネス (agents/)

グローバル指示・ルール・スキル・subagent の正本は `agents/` に 1 セットだけ置き、**両ランタイムが同じ実体を読む**。Claude Code は正本への symlink を読む。Codex も同じ symlink 先を読み、Claude 綴りの語彙を自分の語彙へ**読み替える** (`agents/bindings/codex/AGENTS.md` の読み替え表)。例外は subagent だけで、Codex が TOML しか読めないため書式変換したものを配る。

```
agents/
├── AGENTS.md            ← グローバル指示の正本 (`~/.claude/CLAUDE.md` へ symlink)
├── rules/               ← core/ backend/ frontend/ infra/
├── skills/              ← 43 本 (うち 1 本は Codex への配布から除外、11 本は wondelai/skills からの vendor)
├── subagents/           ← 4 本 (Claude Code 形式が正本。Codex へは書式変換して配る)
├── hooks/               ← herdr-agent-state.sh のみ (herdr 本体の配布物。自作ゲートは無い)
├── scripts/             ← sync-subagents.ts (Codex の TOML 変換) / subagent-format.ts / mutate-check.ts ほか
├── knowledge-profile.md ← utility-doc-reading が読み書きする
└── bindings/            ← ランタイム固有
    ├── claude/          ← settings.json / keybindings.json / settings.{deepseek,spark}.json
    └── codex/           ← AGENTS.md (Codex のグローバル指示) / config.toml
```

### 配布先

| 要素 | Claude Code | Codex | 方式 |
| --- | --- | --- | --- |
| グローバル指示 | `~/.claude/CLAUDE.md` ← `agents/AGENTS.md` | `~/.codex/AGENTS.md` ← `agents/bindings/codex/AGENTS.md` | symlink (live edit) |
| ルール | `~/.claude/rules/` ← `agents/rules/` | `~/.claude/rules/` を絶対パスで直接 Read | symlink (live edit) |
| スキル | `~/.claude/skills/` ← `agents/skills/` | `~/.agents/skills/<name>` ← `agents/skills/<name>` (個別 symlink) | symlink (追加・削除は `drs` / `hms`) |
| subagent | `~/.claude/agents/` ← `agents/subagents/` | `~/.codex/agents/*.toml` (書式変換) | symlink (Codex のみ `drs` / `hms`) |

**Codex は skill root を 2 つ持つ。** 実セッションログの `### Skill roots` で `r0` = `~/.codex/skills` / `r1` = `~/.agents/skills` を確認しており (Codex 0.154)、公式ドキュメントは「symlinked skill folders を追跡する」と明記している。共有に `r1` を使うのは、`~/.agents/skills` に他ツールが入れたスキルが同居するため (`archify` / `find-skills` / `gws-*` / `terminal-browser` の 9 本)。ディレクトリごとの symlink は使えないので 1 スキルずつ張る。

**`~/.codex/skills` はもう配布先ではない。** ここに dotfiles 由来の実体が残っていると同名スキルが `r0` と `r1` に二重に列挙される (Codex は同名スキルをマージしない)。移行時に消す (→「配布方式の移行」節)。`.system` と plugin 由来のものは Codex の所有物なので触らない。

### Codex の subagent 変換 (agents/scripts/sync-subagents.ts)

subagent は 2 者で唯一**書式変換が避けられない**要素である (Claude は Markdown + frontmatter、Codex は TOML)。`agents/scripts/sync-subagents.ts` が `agents/subagents/*.md` を `~/.codex/agents/<name>.toml` へ書き、変換元が消えた `.toml` は prune する。変換そのもの (frontmatter の parse と TOML 生成) は `agents/scripts/subagent-format.ts` が持つ。

`drs` / `hms` の activation `syncCodexSubagents` が呼ぶ。手で流し直すときは次の 1 本。

```bash
./agents/scripts/sync-subagents.ts agents/subagents ~/.codex/agents
```

- **prune の対象**: 先頭に `# generated by ...` を持つファイルだけ。他ツールが置いた `.toml` は残る
- **deno が無いとき**: 警告してスキップし activation は成功する (前回の `.toml` が残る)
- **失敗の見え方**: frontmatter の `name` / `description` 欠落、本文に `'''` を含む場合は exit 1 で `drs` / `hms` ごと止まる

テストはこう回す。CI では回していないので、`agents/scripts/` を触ったら自分で実行する。

```bash
deno test --allow-env --allow-run --allow-read --allow-write agents/
```

### スキルの配布先の限定 (Codex への配布から除外)

スキルは既定で両ランタイムへ配られる (同じ実体への symlink)。Codex に配らないスキルは `nix/modules/home/codex.nix` の `claude_only_skills` に列挙する。宣言しているのは `utility-session-profile` の 1 本だけで、これは Claude Code のセッションログ (`~/.claude/projects/` 配下の `*.jsonl`) しか読まないため。

- **除外の単位**: スキルのディレクトリ単位。`references/` や `scripts/` だけが取り残されることはない
- **反映**: activation `linkAgentSkills` が `drs` / `hms` で走る。Codex 側の symlink が撤去され、Claude 側には残る
- **他ツールの同居**: `~/.agents/skills` に同名の実体があるときは symlink を張らず警告する (`ln -sfn` は既存ディレクトリの中にリンクを作ってしまうため)。手で退避してから再実行する
- **`SKILL.md` の frontmatter では宣言しない**: 以前は `metadata.runtimes` を生成器が読んでいたが、生成をやめたので読む側が無い

### live edit の範囲

**本文の編集は `drs` / `hms` を待たずに反映される。** `drs` / `hms` が要るのは次の 2 つだけ。

| 対象 | 反映 | 理由 |
| --- | --- | --- |
| `AGENTS.md` / `rules/` / `skills/` / `subagents/` の本文 | 即反映 | 正本への symlink |
| `hooks/` `scripts/` `knowledge-profile.md` | 即反映 | 正本への symlink (`knowledge-profile.md` は `utility-doc-reading` が書き込む) |
| `bindings/claude/settings.json` `keybindings.json` / `bindings/codex/AGENTS.md` `config.toml` | 即反映 | 正本への symlink |
| スキルの追加・削除 | `drs` / `hms` | `~/.agents/skills/<name>` の symlink を張り直す activation (`linkAgentSkills`) が要る |
| subagent の変更・追加 | `drs` / `hms` | `~/.codex/agents/*.toml` の再変換 (`syncCodexSubagents`) が要る |
| `~/.claude/skills/` への第三者の書き込み | 即反映 (副作用あり) | 正本への symlink なので、他ツールが置いたディレクトリは dotfiles の `agents/skills/` (git 作業ツリー) に落ち、`linkAgentSkills` が Codex へも配る |

### 開発ワークフローのスキル

```
/dev-spec (設計ループ) → 承認ゲート (人間が起動) → /dev-impl (実装ループ)
```

詳細は `agents/skills/README.md` を参照 (タスク規模別の入口・モデル方針を含む)。主要スキル：
- `/dev-spec` — 設計ループ (ユーザーストーリー → ... → PoC 検証 → `docs/design/DESIGN.md` 1 枚 + `docs/design/features/` → GitHub issue をユースケース単位の親子 2 階層で生成 → 人間が確認)
- `/dev-impl` — 実装ループ (`ready` ラベルの open issue を依存順に自律実装、`model: opus`)
- `/dev-impl-quick` — 軽量実装ループ (docs 不要。依頼文をタスク分解して直営 TDD → review-impl → タスク単位コミット)
- `/workflow-review` (レビュー) / `/workflow-commit` (コミット) / `/workflow-create-draft-pr` (Draft PR) / `/workflow-debate` (壁打ち)

### hooks (agents/hooks/)

**deny する自作 hook は 1 本も無い。** `agents/hooks/` に置いてあるのは herdr 本体が配布する `herdr-agent-state.sh` の 1 本だけで、これは deny するゲートではなく herdr へセッション状態を渡すスクリプトである。

hook 以外の機械的な強制は 1 つだけ残っている。`agents/subagents/dev-impl-implementer.md` の `tools` から `Agent` を除いて**葉性を構造的に強制**している (subagent には親の hooks が届かず、指示文では違反を検出できないため)。

| ファイル | 起動元 | 役割 |
| --- | --- | --- |
| `herdr-agent-state.sh` | Claude Code の `settings.json` の SessionStart (`~/.claude/hooks/` 経由) | herdr にセッション状態を渡す。herdr 本体が配布するファイルで mac の絶対パスが埋まっており、Linux では発火しない |

`~/.claude/hooks` の symlink はこの 1 本のためだけにある。ディレクトリごと消すと herdr の SessionStart が絶対パスで参照できなくなる。

**deny する自作ゲートは 2 ランタイムのどれにも配っていない。**自分で書いた hook として Claude Code に配っているのは上表の herdr 連携 1 本だけである。Codex は移植すべきものが無い。

**プラグイン由来の hook はこれとは別にある。** compact-plus が Claude Code に 7 件 (UserPromptSubmit / PreCompact / PostCompact / SessionStart)、Codex に 7 件を登録する (Claude 側は `agents/bindings/claude/settings.json` の `enabledPlugins`、Codex 側は `codex.nix` の activation が入れる)。どちらもコンパクション補助で deny するゲートではないが、「hook が 1 件も無い」わけではない。

hook を追加したくなったときの置き場は次のとおり。

| ランタイム | 置き場 |
| --- | --- |
| Claude Code | スクリプトを `agents/hooks/` に置き、`agents/bindings/claude/settings.json` の `hooks` に `$GHQ_ROOT` 経由の絶対パスで登録する。`~/.claude/hooks` の symlink は経由しない (`GHQ_ROOT` は `nix/modules/home/env.nix` が `$HOME/dev` に設定する) |
| Codex | `agents/bindings/codex/config.toml`。レイヤーごとの発火差は `agents/bindings/codex/AGENTS.md` の「hooks を追加するときの置き場」節にある |

`settings.json` の登録は全 13 件で、上表の 1 本以外は**外部ツール orca が書き込んだ 12 件**である (12 イベントに 1 件ずつ)。orca の分は `~/.orca/agent-hooks/claude-hook.sh` が無ければ空の `{}` を返すだけで、このマシンには `~/.orca` が存在しないので全件 no-op になっている。

#### 機械ゲートを置いていない規律

以下は hook で強制せず、記述による自律遵守に委ねている。**破っても止まらないことを承知したうえでの設計判断**であり、設計思想は `agents/rules/core/references/loop-engineering.md` にある。

| 規律 | 正本 | 破られたときに何が起きるか | 事後に気づく手段 |
| --- | --- | --- | --- |
| コミット規約 (`<emoji> <type>: <subject>`) | `agents/rules/core/commit.md` | 形式の揃わないコミットが履歴に残る。push 前なら `git commit --amend` で直せる | `git log -1 --pretty=%s` を型と照合する (commit.md が手順として規定) |
| dev-impl の修正ラウンド上限 (1 周) | `agents/skills/dev-impl/SKILL.md` | 収束しない issue に時間とトークンが溶ける。**実測で 22 issue 中 6 件が 3 周目以降に入り、超過分だけで 5.7h を消費したことがある** | issue の完了コメントに残る「review-impl の周回数」 |
| 実装系ルールの遅延参照 | `agents/AGENTS.md`「実装時」 | TDD やテスト方針を知らないまま実装が進む | **無い**。リマインドも事後検出もしない |
| subagent 起動時の `model` 明示 | `agents/rules/core/orchestration.md` | 未指定だと agent 定義の frontmatter ではなく親のセッションモデルを継承する。検証器が実行器より弱くなりうる | **無い**。セッションのログを人が読むしかない |
| utility-doc-audit の起動経路 (ユーザー起動と `/workflow-design-notes` の落とし込みのみ) | `agents/skills/utility-doc-audit/SKILL.md` | 普段の作業で監査が自発起動し、観点サブエージェントの fan-out 分のトークンを消費する | **無い**。`disable-model-invocation` を使わない判断のため、SKILL.md の description と本文の記述が唯一の抑止 |

### subagents (agents/subagents/)

正本は Claude Code 形式 (Markdown + frontmatter) で、`~/.claude/agents/` へは symlink で配る。Codex へは `agents/scripts/sync-subagents.ts` が TOML へ書式変換して `~/.codex/agents/*.toml` に置く (→「Codex の subagent 変換」節)。生成物は git 管理しない。

| 配布先 | 形式 |
| --- | --- |
| `~/.claude/agents/*.md` | 正本と同じ形式 |
| `~/.codex/agents/*.toml` | `name` / `description` / `developer_instructions` の 3 キー |

**落とすキーが 2 つある。** `tools` は Codex に対応キーが無い。`model` は Codex では実モデル名が要り alias が使えないため、世代交代に追従できるよう生成物には書かない (固定するなら `agents/bindings/codex/config.toml` の `[agents] default_subagent_model` に 1 箇所だけ書く。現状は未設定で、Codex 側の subagent は親のモデルを継承する)。`context: fork` に相当する概念は Codex に無い。読み替えの正本は `agents/bindings/codex/AGENTS.md` の「3 者で表現できない subagent の属性」節。

### 配布

`drs` (mac) / `hms` (Linux) が `nix/modules/home/{claude,codex}.nix` を適用する。専用のインストールスクリプトは無い。`claude.nix` が Claude Code 向けの symlink を、`codex.nix` が Codex 向けの symlink と activation (`linkAgentSkills` / `syncCodexSubagents` / `installCodexPlugins`、Linux では加えて `linkCodexSystemConfig`) を持つ。Android (`home-android.nix`) は `codex.nix` を import しないので Codex 向けだけが行われない。

**配布の確認**:

```bash
readlink -f ~/.claude/CLAUDE.md ~/.claude/rules ~/.claude/skills ~/.claude/agents   # dotfiles の agents/ に解決する
readlink -f ~/.codex/AGENTS.md                    # agents/bindings/codex/AGENTS.md に解決する
readlink -f ~/.agents/skills/dev-impl             # agents/skills/dev-impl に解決する
ls ~/.codex/agents                                # subagent 4 本の .toml がある
ls ~/.agents/skills | grep -c utility-session-profile || :   # 0 (Codex への配布から除外されている)
readlink -f /etc/codex/config.toml                # agents/bindings/codex/config.toml に解決する
```

### 配布方式の移行 (生成方式 → symlink)

生成方式で配った実体が残っていると Home Manager の `checkLinkTargets` が `Existing file '$targetPath' is in the way ... will be moved to '$targetPath.hm-backup'` を出して**退避**する (`home-manager.backupFileExtension = "hm-backup"` を `flake.nix` で設定済み。実機の例: `~/.claude/settings.json.hm-backup`)。拒否はされないが、ディレクトリは丸ごと退避されるので、放置すると `~/.claude/skills.hm-backup` のような大きな残骸が残る。**同居物を巻き込まないため、消すのは各ディレクトリの `.harness-manifest.json` に載っているパスだけ**にする。

```bash
for m in ~/.claude/rules ~/.claude/skills ~/.claude/agents ~/.codex/skills ~/.codex/agents; do
  [ -f "$m/.harness-manifest.json" ] || continue
  jq -r '.paths[]' "$m/.harness-manifest.json" | while read -r p; do rm -rf "$m/$p"; done
  rm -f "$m/.harness-manifest.json"
  find "$m" -type d -empty -delete   # manifest はファイル単位なので空になった親を掃除する
done
rm -f ~/.claude/CLAUDE.md ~/.codex/AGENTS.md
rm -rf ~/.agents/rules
drs   # または hms
```

manifest の `paths` は**ファイル単位**の相対パスなので、削除しただけでは入れ物のディレクトリが残る (`~/.claude/skills/dev-spec/references` のような空の殻)。上の `find -type d -empty -delete` がそれを消し、ディレクトリ全体が空になれば `~/.claude/rules` のように消えて HM が symlink を作り直す。

`~/.agents/skills` の他ツール由来スキル (`archify` / `find-skills` / `gws-*` / `terminal-browser`) と `~/.codex/skills/.system` は触らない。`~/.codex/skills` に dotfiles 由来の実体が残ると同名スキルが `r0` と `r1` に二重に列挙されるので、`ls ~/.codex/skills` で残っていないか確認する。

`~/.claude/skills` はディレクトリごと symlink するため、manifest 外の同居エントリは HM の退避で `~/.claude/skills.hm-backup` へ移る。生かしたいものがあれば手で戻す (ただし戻すと第三者のデータが dotfiles の git 作業ツリーに入る)。

### 解消しない非対称

- **呼び出し例の引数の形**は Claude Code のスキーマのまま。Codex はツール名を読み替えても、`request_user_input({ questions: [...] })` の引数構造までは翻訳されない。Codex のツールスキーマを実測する手段が無く、推測で書くと誤った例を配ることになるため。`agents/bindings/codex/AGENTS.md` にその旨を明記してある
- **rules の自動展開**は Claude Code 固有。`paths:` frontmatter による条件付きロードも Claude Code だけの機構で、Codex はグローバル指示から「Read せよ」と指示された分しかコンテキストに入らない。2 者で「同じルールが同じタイミングで効く」ことまでは保証していない

## Working with This Repository

### 既存設定の変更（Nix 管理側）

1. `nix/modules/home/*.nix` または `nix/modules/darwin/*.nix` を編集
2. `nix fmt` で整形する（`nix/**` への push で CI が `nix fmt -- --ci` と `nix flake check --all-systems --no-build` を回すので、崩れたまま push すると master で fail する）
3. `git add` で staging（flake は tracked file しか見ない）
4. `drs` (mac) / `hms` (Linux) で適用（`nh` が darwin-rebuild / home-manager を起動。mac は Touch ID 経由の sudo）

### 新規ツール追加

- CLI: `modules/home/packages.nix` に追記。Android でも使うなら `modules/home/packages-android.nix` にも足す (別リストなので自動では入らない)
- 設定ファイル: `programs.<tool>` モジュールがあれば使う、無ければ `home.file.*` で配置
- macOS GUI app: `modules/darwin/homebrew.nix` の `casks` に追記
