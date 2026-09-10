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
  - `functions/*.zsh` — カスタム zsh 関数 7 本。`ghq-fzf` / `gss` / `tmuxpopup` の 3 本と、DGX Spark 系の `claude-deepseek` (`ccsp` / `ccds`) / `opencode-spark` (`ocsp`) / `spark-common` の 3 本、mac 専用の `sleepctl`
- **karabiner/** — Karabiner-Elements 設定 (Goku DSL)
  - `karabiner.edn` — EDN で書いたルール、switch 時に goku が `~/.config/karabiner/karabiner.json` を生成
- **wezterm/** — WezTerm 設定（`mkOutOfStoreSymlink` で dotfiles 直接 symlink、live edit 可能）
  - `wezterm.lua` — `programs.wezterm.extraConfig` は使わず直接 symlink する。Lua の編集体験 (lua_ls) を保ち、`drs` 無しで反映するため
- **tmux/** — tmux 設定（`mkOutOfStoreSymlink` で dotfiles 直接 symlink、live edit 可能）
  - `tmux.conf` — 編集即反映、`prefix + r` で reload。`drs` 不要
  - プラグインの run-shell だけは nix store path 解決のため Nix 生成の `~/.config/tmux/plugins.conf` 経由
- **agents/** — AI エージェント共通のハーネス正本（ランタイムごとにコンパイルして配る。一部だけ直接 symlink で live edit 可能）
  - `AGENTS.md` / `rules/` / `skills/` / `subagents/` はランタイムごとにコンパイルして配るので、編集の反映に `drs` / `hms` (または生成器の手動実行) が要る
  - `hooks/` / `scripts/` / `knowledge-profile.md` と `bindings/` の**一部ファイル**は直 symlink なので編集即反映 (どれが symlink かは「live edit の範囲」の表を参照)
  - `bindings/*/overlay/` は生成器の**入力**であって配布物ではない。編集の反映には `drs` / `hms` が要る
  - 配布先と構成は「AI エージェントのハーネス (agents/)」節を参照
- **agents/bindings/codex/** — Codex 固有の設定 (ハーネス本体は `agents/` 直下)
  - `config.toml` — git 管理する Codex 共通設定。Codex の system レイヤー `/etc/codex/config.toml` として dotfiles 直接 symlink され、CLI / ChatGPT.app 内 Codex を含む全クライアントに読まれる (live edit 可能)
  - `config.toml` に hooks は書いていない。このハーネスは機械ゲートを 1 本も持たないので移植すべきものが無い。将来 Codex へ hook を配るときの置き場とレイヤーごとの発火差は `overlay/AGENTS.md` の「hooks を追加するときの置き場」節にある
  - `overlay/AGENTS.md` — 共通の正本にマージして `~/.codex/AGENTS.md` を生成するための Codex 固有の節
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
    │   ├── harness.nix   — ハーネスを Claude Code / OpenCode 向けにコンパイルして配る + 旧方式が張った ~/.agents/skills の symlink を撤去 (Android でも要るので codex.nix には置かない)
    │   ├── claude.nix    — Claude Code (bootstrap install + Claude 固有の設定と hooks/scripts を symlink。ハーネスの生成は harness.nix)
    │   ├── codex.nix     — Codex 向けハーネスの生成 (AGENTS.md / rules / skills / agents) + プラグイン導入 (activation)。Linux のみ /etc/codex/config.toml を sudo で symlink
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
    │   ├── opencode.nix  — OpenCode (opencode.json / tui.json を mkOutOfStoreSymlink。ハーネスの生成は harness.nix)
    │   ├── packages.nix  — home.packages 群（言語ランタイム / LSP / CLI を 13 カテゴリで宣言、約 100 件。vite-plus / nvtop / libreoffice-bin / terminal-notifier / screen-capture-mcp-server / kanary は darwin only）
    │   ├── packages-android.nix — Android 用の明示リスト (19 エントリ。binary cache から取れる軽量なものだけ)
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

グローバル指示・ルール・スキル・subagent の正本は `agents/` に 1 セットだけ置き、**ランタイムごとにコンパイルして配る**。読み手は自分の語彙で書かれた完成品だけを読む。

本文はランタイム中立の語彙 (`{{@ask-user}}` 等) で書き、`agents/vocabulary.json` が各ランタイムの実語へ展開する。語彙では吸収できないランタイム固有の記述は `agents/bindings/<runtime>/overlay/` に**節単位**で置く。見出しが base と一致すればその節を配下ごと差し替え、**一致しなければ末尾に追加する**(削除はできない)。現行の overlay は 9 節すべてが追加側で、差し替えは 1 件も使っていない。一致させたい節は見出しを 1 バイトも変えない。

```
agents/
├── AGENTS.md            ← グローバル指示の base
├── rules/               ← core/ backend/ frontend/ infra/
├── skills/              ← 29 本 (うち 1 本は配布先を Claude Code に限定)
├── subagents/           ← 4 本 (Claude Code 形式が正本)
├── vocabulary.json      ← 中立語彙 → 3 ランタイムの実語 (19 件)
├── hooks/               ← herdr-agent-state.sh のみ (herdr 本体の配布物。自作ゲートは無い)
├── scripts/             ← build-harness.ts (生成器) / subagent-format.ts / mutate-check.ts ほか
├── knowledge-profile.md ← utility-doc-reading が読み書きする
└── bindings/            ← ランタイム固有
    ├── claude/          ← settings.json / keybindings.json / settings.{deepseek,spark}.json
    ├── codex/           ← config.toml / overlay/
    └── opencode/        ← opencode.json / tui.json / overlay/
```

**Claude 向けの overlay は置かない。** base をそのまま出すことで「Claude 向け生成物 = 中立化前の base」が成立し、語彙置換が可逆であることを byte 比較で検証できる。

### 配布先

| 要素 | Claude Code | Codex | OpenCode |
| --- | --- | --- | --- |
| グローバル指示 | `~/.claude/CLAUDE.md` | `~/.codex/AGENTS.md` | `~/.config/opencode/AGENTS.md` |
| ルール | `~/.claude/rules/` | `~/.agents/rules/codex/` | `~/.agents/rules/opencode/` |
| スキル (既定。`metadata.runtimes` で限定可。→「スキルの配布先の限定 (metadata.runtimes)」節) | `~/.claude/skills/` | `~/.codex/skills/` | `~/.config/opencode/skills/` |
| subagent | `~/.claude/agents/` | `~/.codex/agents/*.toml` | `~/.config/opencode/agents/*.md` |

**`~/.agents/skills/` は使わない。** Codex と OpenCode の両方がこのディレクトリを探索し、**どちらも探索を止める手段が無い** (OpenCode の `skills.paths` は追加専用、Codex の `skip_host_skill_discovery` は skill roots を変えない。いずれも実測)。ランタイム別の生成物を置けないので、他ツールが入れたスキルの領域として空けてある。

OpenCode は `~/.claude/skills` も探索する。`nix/modules/home/env.nix` の `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1` で切ってある。**この変数が効いていないと、同名スキルのどちらが採用されるかが実行ごとに変わる** (実測: 3 回の実行で採用元が 6 / 2 / 6 件と割れた)。`drs` / `hms` の後は**ターミナルを開き直す**。`hm-session-vars.sh` に再読込ガードがあり、既存のターミナルには新しい変数が入らない。

### 生成器 (agents/scripts/build-harness.ts)

`drs` / `hms` の activation が呼ぶ。**全ランタイム分を流すには `drs` / `hms` を使う** (生成の呼び出しが 12 回、旧 symlink の撤去が 1 回あり、`harness.nix` と `codex.nix` が持っている)。

1 ランタイムの 1 要素だけを手で流し直すこともできる。ルールを 1 行直したときはこれが速い。

```bash
./agents/scripts/build-harness.ts --runtime claude --dotfiles-root "$PWD" \
  --vocabulary agents/vocabulary.json \
  --base agents/rules --overlay agents/bindings/claude/overlay/rules \
  --out ~/.claude/rules
```

`--base` にファイルを渡すと単一ファイルモードになる (グローバル指示用)。引数なしで実行すると使い方が出る。

処理は **overlay の節マージ → 語彙の置換**の順。逆順だと overlay の見出しキーをランタイム語彙で書くことになり、キーがランタイムごとに変わってしまう (見出しにプレースホルダを含むファイルが 4 本ある)。

安全機構が 5 つある。

- **出力先の検査**: symlink または正本配下に解決する出力先を拒否する。activation は旧 symlink の撤去 (`linkGeneration`) より前に走りうるため、素直に書くと生成物を旧 symlink 越しに `agents/` 自身へ書き込んで正本を壊す
- **出力先の中の旧 symlink の撤去**: 書き込みの前に、出力ディレクトリ直下の「正本配下に解決する symlink」を撤去する。出力先の検査はルートしか見ないので、旧方式が張った `~/.codex/skills/<name>` のような個別リンクが 1 段残っていると `mkdir -p` と `rename` がそれを辿り、生成物を正本へ書き戻す (実測: リンクを残したまま生成すると `agents/skills/<name>/SKILL.md` がランタイム語彙版で上書きされる)。dotfiles 外を指す symlink には触れない
- **staging → rename**: 生成は出力先の隣で行い、閉包チェックを通ってから移す。途中で失敗しても配布先が半端な状態で残らない
- **manifest による prune**: 撤去対象は各出力ディレクトリ直下の `.harness-manifest.json` に載っているものだけ (出力先からの相対パスを `paths` 配列で持つ)。配布先には他ツールが置いたスキルが同居するので、拡張子やマーカー行では選別できない。裏を返すと、manifest に載っていないものは配布をやめても残る
- **空になった親の掃除**: prune でディレクトリが空になったら、出力ディレクトリの手前まで遡って空の親も消す (空の殻が残ると `ls` でスキルが配られているように見える)。他ツールのファイルが 1 つでも残っているディレクトリは空にならないので消えない

未定義のプレースホルダが残っていると例外で止まる。deno が無ければ警告してスキップし activation は成功する (生成物は前回のまま残る)。

生成器と subagent 変換のテストはこう回す。**権限フラグを省くと 29 件が落ちる** (一時ディレクトリの作成やサブプロセス起動を使うため)。CI では回していないので、`agents/scripts/` を触ったら自分で実行する。

```bash
deno test --allow-env --allow-run --allow-read --allow-write agents/
```

#### スキルの配布先の限定 (metadata.runtimes)

スキルは既定で 3 ランタイムすべてに配られる。1 つのランタイムでしか動かないスキルは `SKILL.md` の frontmatter で配布先を宣言する。宣言しているのは `utility-session-profile` の 1 本だけで、これは Claude Code のセッションログ (`~/.claude/projects/` 配下の `*.jsonl`) しか読まないため。

```yaml
---
name: utility-session-profile
description: Claude Code の特定セッションのログから所要時間の内訳を集計し...
metadata:
  runtimes: claude
---
```

- **値の書式**: カンマ区切りのランタイム名。取りうるのは `claude` / `codex` / `opencode` の 3 つで、複数書くなら `claude, codex` の形にする。この 3 つは `agents/vocabulary.json` の各エントリが持つランタイム側のキー (トップレベルのキーは `ask-user` などの中立語彙 19 件のほう) から引いている
- **書き方の制約**: 生成器は YAML パーサを持たず、`metadata:` を単独行で書いたときのそのブロックの中の最初の `runtimes:` 行だけを読む。リスト形式 (`- claude`)・インラインマップ (`metadata: {runtimes: claude}`)・空値 (`runtimes:`)・トップレベルや `metadata` 以外のキーの配下に置いたものは、いずれも**例外で止める**。読めない書き方を素通しすると限定が黙って効かなくなり、空値を「ランタイム 0 個」と解釈すると全ランタイムから外れて prune が配布済みのスキルを消すため、解釈できないものはすべて落とす
- **値の中は見ない**: 値を持つキーの配下は「値の続き」として読み飛ばす。折り返した `description` の継続行が `runtimes:` で始まっても宣言とは見なさない (`dev-spec` と `fullstack-app-builder` の `description` は実際に折り返しを持つ)。ここを見てしまうと、限定を宣言していないスキルが生成全体を止める
- **`metadata` の下に置く理由**: `metadata` は「自前ツールが SKILL.md から読む自由な map で、Claude Code は中身に作用しない」と公式ドキュメント (https://code.claude.com/docs/en/skills.md) が定義した唯一の置き場である。トップレベルに未知キーを置いたときの Claude Code の挙動は公式に明記が無く、Agent Skills spec 経由のパッケージング (claude.ai へのアップロード) では `metadata` 以外の未知キーがハードエラーになる
- **適用の単位**: 除外は**ディレクトリ単位**で効く。スキル配下の `references/` や `scripts/` だけが配布先に取り残されることはない
- **判定の入口**: 「`--base` 直下のディレクトリが `SKILL.md` を持つか」で決まるので、rules と subagents のツリーには何も起きない
- **ランタイム名の検証**: `claud` のような typo は例外で止める。検証は `agents/vocabulary.json` を引くので、`--vocabulary` を渡さずに手で流した場合は検証できず、宣言のあるスキルに当たった時点で例外にする (素通しさせない)
- **例外の見え方**: いずれも exit 1 で `drs` / `hms` ごと止まる。落ちるのは staging を作る前なので配布先は前回のまま無傷で、直して流し直せば戻る
- **後から限定したとき**: 配布済みのスキルに `metadata.runtimes` を足すと、宣言から外れたランタイム向けの次の生成で prune が撤去する。手で消す必要はない。ただし撤去はそのランタイム向けの生成が走ったときに効くので、1 ランタイムだけ手で流し直しても足りず `drs` / `hms` が要る

### live edit の範囲

**ルール・スキル・subagent・グローバル指示は生成物になったので、編集しても `drs` / `hms` (または生成器の手動実行) まで反映されない。**

symlink のまま残しているのは次のものだけ。

| 対象 | 理由 |
| --- | --- |
| `hooks/` `scripts/` | コードで語彙の置換対象が無い |
| `bindings/claude/settings.json` `keybindings.json` | Claude 固有で他ランタイムは読まない |
| `bindings/codex/config.toml` | `/etc/codex/config.toml` の system レイヤーとして配る |
| `bindings/opencode/opencode.json` `tui.json` | OpenCode 固有で他ランタイムは読まない |
| `knowledge-profile.md` | `utility-doc-reading` が**書き込む**。生成物にすると毎回上書きされる |

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

**deny する自作ゲートは 3 ランタイムのどれにも配っていない。**自分で書いた hook として Claude Code に配っているのは上表の herdr 連携 1 本だけである。Codex は移植すべきものが無く、OpenCode はシェル hooks 自体を持たない (JS プラグイン API はコマンドに stdin を渡さず stdout も解釈しないため deny するゲートに使えない)。

**プラグイン由来の hook はこれとは別にある。** compact-plus が Claude Code に 7 件 (UserPromptSubmit / PreCompact / PostCompact / SessionStart)、Codex に 7 件を登録する (Claude 側は `agents/bindings/claude/settings.json` の `enabledPlugins`、Codex 側は `codex.nix` の activation が入れる)。どちらもコンパクション補助で deny するゲートではないが、「hook が 1 件も無い」わけではない。

hook を追加したくなったときの置き場は次のとおり。

| ランタイム | 置き場 |
| --- | --- |
| Claude Code | スクリプトを `agents/hooks/` に置き、`agents/bindings/claude/settings.json` の `hooks` に `$GHQ_ROOT` 経由の絶対パスで登録する。`~/.claude/hooks` の symlink は経由しない (`GHQ_ROOT` は `nix/modules/home/env.nix` が `$HOME/dev` に設定する) |
| Codex | `agents/bindings/codex/config.toml`。レイヤーごとの発火差は `agents/bindings/codex/overlay/AGENTS.md` の「hooks を追加するときの置き場」節にある |
| OpenCode | 不可 (シェル hooks を持たない) |

`settings.json` の登録は全 13 件で、上表の 1 本以外は**外部ツール orca が書き込んだ 12 件**である (12 イベントに 1 件ずつ)。orca の分は `~/.orca/agent-hooks/claude-hook.sh` が無ければ空の `{}` を返すだけで、このマシンには `~/.orca` が存在しないので全件 no-op になっている。

#### 機械ゲートを置いていない規律

以下は hook で強制せず、記述による自律遵守に委ねている。**破っても止まらないことを承知したうえでの設計判断**であり、設計思想は `agents/rules/core/references/loop-engineering.md` にある。

| 規律 | 正本 | 破られたときに何が起きるか | 事後に気づく手段 |
| --- | --- | --- | --- |
| コミット規約 (`<emoji> <type>: <subject>`) | `agents/rules/core/commit.md` | 形式の揃わないコミットが履歴に残る。push 前なら `git commit --amend` で直せる | `git log -1 --pretty=%s` を型と照合する (commit.md が手順として規定) |
| dev-impl の修正ラウンド上限 (1 周) | `agents/skills/dev-impl/SKILL.md` | 収束しない issue に時間とトークンが溶ける。**実測で 22 issue 中 6 件が 3 周目以降に入り、超過分だけで 5.7h を消費したことがある** | issue の完了コメントに残る「review-impl の周回数」 |
| 実装系ルールの遅延参照 | `agents/AGENTS.md`「実装時」 | TDD やテスト方針を知らないまま実装が進む | **無い**。リマインドも事後検出もしない |
| subagent 起動時の `model` 明示 | `agents/rules/core/orchestration.md` | 未指定だと agent 定義の frontmatter ではなく親のセッションモデルを継承する。検証器が実行器より弱くなりうる | **無い**。セッションのログを人が読むしかない |

### subagents (agents/subagents/)

正本は Claude Code 形式 (Markdown + frontmatter)。3 者で唯一**書式変換が避けられない**要素で、`agents/scripts/subagent-format.ts` の変換関数を `build-harness.ts` が語彙置換の後に呼ぶ (順序が逆だと TOML の中身に置換をかけることになる)。生成物は git 管理しない。

| 配布先 | 形式 |
| --- | --- |
| `~/.claude/agents/*.md` | 正本と同じ形式 (語彙だけ展開) |
| `~/.codex/agents/*.toml` | `name` / `description` / `developer_instructions` の 3 キー |
| `~/.config/opencode/agents/*.md` | `description` + `mode: subagent` の frontmatter |

**落とすキーが 3 つある。** `tools` は Codex に対応キーが無く、OpenCode は真偽値マップで意味が反転する。`model` は Codex では実モデル名が要り alias が使えないため、世代交代に追従できるよう生成物には書かない (固定するなら `agents/bindings/codex/config.toml` の `[agents] default_subagent_model` に 1 箇所だけ書く。現状は未設定で、Codex 側の subagent は親のモデルを継承する)。`context: fork` に相当する概念はどちらにも無い。

変換が失敗すると (frontmatter の `name` / `description` 欠落、本文に `'''` を含む) exit 1 で `drs` / `hms` ごと止まる。

### 配布

`drs` (mac) / `hms` (Linux) が `nix/modules/home/{harness,claude,codex,opencode}.nix` を適用する。専用のインストールスクリプトは無い。`harness.nix` が Claude Code と OpenCode 向けを、`codex.nix` が Codex 向けを生成する。Android (`home-android.nix`) は `codex.nix` を import しないので Codex 向けだけが行われない。

生成は `linkGeneration` と `bootstrapDeno` の後に走る。旧 symlink の撤去を待たないと正本を壊すためで、DAG の依存関係で保証している。

**配布の確認**:

```bash
# 生成でしか作られない manifest を見る (ls だと他ツールのスキルが同居していて判定できない)
ls ~/.claude/skills/.harness-manifest.json ~/.codex/skills/.harness-manifest.json \
   ~/.config/opencode/skills/.harness-manifest.json
ls ~/.codex/agents ~/.config/opencode/agents                     # subagent 4 本の生成物がある
# 配布先を限定したスキルが宣言どおりか (claude は 1 以上、codex / opencode は 0)
for m in ~/.claude ~/.codex ~/.config/opencode; do
  printf '%s: ' "$m"
  jq -r '.paths[]' "$m/skills/.harness-manifest.json" | grep -c '^utility-session-profile/' || :
done
rg -F '{{@' ~/.codex/AGENTS.md || echo 'プレースホルダの残骸なし'  # -F が要る ({ は正規表現で構文エラー)
readlink -f /etc/codex/config.toml                               # agents/bindings/codex/config.toml に解決する
echo $OPENCODE_DISABLE_CLAUDE_CODE_SKILLS                        # 1 (空ならターミナルを開き直す)
```

### 生成物から symlink へ戻すとき

`~/.claude/{CLAUDE.md,rules,skills,agents}` などが実ファイル化した後に、生成を使わない世代へ戻すと Home Manager の `checkLinkTargets` が `Existing file ... is in the way` で拒否する。戻すときは実ファイルを手で消してから適用する。

**先に退避が要る。** `~/.codex/skills` と `~/.config/opencode/skills` には他ツールが入れたスキルが、`~/.claude/agents` には人が置いた subagent が同居しうる。生成物だけを消したいなら各ディレクトリの `.harness-manifest.json` に載っているパスを消す。下記は**同居物ごと消す**手順である。

```bash
rm -rf ~/.claude/{CLAUDE.md,rules,skills,agents} \
       ~/.codex/{AGENTS.md,skills,agents} \
       ~/.config/opencode/{AGENTS.md,skills,agents} \
       ~/.agents/rules
drs   # または hms
```

### コンパイルでも解消しない非対称

- **呼び出し例の引数の形**は Claude Code のスキーマのまま。ツール名は展開されるが、`request_user_input({ questions: [...] })` の引数構造までは翻訳していない。Codex と OpenCode のツールスキーマを実測する手段が無く、推測で書くと誤った例を配ることになるため。各ランタイム向けの生成物にその旨を明記してある
- **rules の自動展開**は Claude Code 固有。`paths:` frontmatter による条件付きロードも Claude Code だけの機構で、Codex と OpenCode はグローバル指示から「Read せよ」と指示された分しかコンテキストに入らない。3 者で「同じルールが同じタイミングで効く」ことまでは保証していない

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
