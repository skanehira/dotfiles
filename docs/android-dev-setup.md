# Android (Galaxy Z Fold 8 Ultra) を Linux 開発端末にする

- 種別: 手順書
- 対象: Galaxy Z Fold 8 Ultra (Snapdragon 8 Elite Gen 5 / One UI 9)
- 最終更新: 2026-09-06
- 状態: dotfiles 側の Android プロファイルは実装・コミット済み。端末上での実行 (Phase 0 / Phase 1) はまだ誰も試していない

## なぜ Termux + proot なのか

Android 16 以降の標準「Linux ターミナル」(Android Virtualization Framework の Debian VM) は、この端末では使えない。Terminal アプリが要求する non-protected VM を Snapdragon が公開しないため。One UI 8.5 / Android 17 でも Exynos 機限定のままで、Qualcomm は「市場需要が生じたら検討」と述べるにとどまる。

したがって Termux 上の proot-distro Debian を使う。この経路を選ぶ理由は、glibc の aarch64-linux バイナリがそのまま動くこと。Termux 本体は Bionic libc なので、Claude Code (v2.1.113 以降 glibc ネイティブバイナリ) も OpenCode (Bun 製) も直上では起動しない。

| 手段 | 判定 | 判定の条件 |
| --- | --- | --- |
| 標準 Linux ターミナル (AVF) | 使えない | Snapdragon が non-protected VM に非対応。ハードを替えない限り覆らない |
| Termux + proot-distro Debian | **採用** | glibc バイナリが動き、localhost を端末と共有する |
| Termux + nix-on-droid | 不採用 | alpha 品質。`nixOnDroidConfigurations` を別に持つ必要があり本 repo の flake を流用できない |
| Termux 直上 | 不採用 | Claude Code と OpenCode が起動しない |
| Termux + QEMU (TCG) | 保留 | Docker が要ると判明したときだけ再検討する。TCG で 10〜25 倍遅い |

## 前提

| 項目 | 必要なもの |
| --- | --- |
| root | 不要。Termux も proot-distro も一般ユーザーで完結する |
| 空きストレージ | 10 GB 以上を見ておく。Nix ストアだけで数 GB から十数 GB に育つ |
| ネットワーク | Wi-Fi 推奨。Phase 1 の初回 switch で 500 MiB 以上を落とす |
| PC | 任意。手順 2 のプロセスキラー対策が端末の設定だけで効かないときに adb を打つ用途 |
| 所要時間 | Phase 0 が 30 分程度、Phase 1 の初回 switch は回線と発熱しだいで 1 時間以上 |

Docker はこの構成では使えない。proot はホストのカーネルを共有するだけで名前空間を作れないため。コンテナが必要な作業は DGX Spark (`claude/rules/infra/dgx-spark.md`) か VPS へ SSH する。

## Phase 0: 端末 spike

dotfiles を適用する前に、前提が成り立つことを 7 ステップで確かめる。各ステップに期待する出力を書いてあるので、違う結果が出たらそこで止めて記録する。

### 1. Termux を入れる

F-Droid か GitHub Releases 版を使う。Google Play 版は上流 README が experimental (機能不足とバグあり) と明記しているので使わない。

```bash
pkg update -y && pkg install -y proot-distro
```

期待: `proot-distro --version` が版番号を返す。

### 2. プロセスキラーを止める

Android 12 以降の phantom process killer は、アプリが起動した子プロセスが一定数を超えると SIGKILL する。dev サーバーや Claude Code が理由なく落ちる原因になる。

1. 開発者向けオプション → 「子プロセスの制限を無効化」を ON
2. 設定 → アプリ → Termux → バッテリー → 「制限なし」
3. Termux で `termux-wake-lock`

期待: PC がある場合は `adb shell device_config get activity_manager max_phantom_processes` が十分大きい値か `null` を返す。設定が効いていなければ、同じく PC から次を打つ。

```bash
adb shell "/system/bin/device_config put activity_manager max_phantom_processes 2147483647"
```

この設定は OS 更新で戻ることがある。手順 6 の到達性テストでも生存を再確認する。

### 3. Debian を入れる

```bash
proot-distro install debian
proot-distro login debian -- bash -c '
  apt-get update -qq
  apt-get install -y -qq curl xz-utils sudo git ca-certificates locales procps python3 build-essential
  sed -i "s/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/" /etc/locale.gen
  locale-gen
  useradd -ms /bin/bash skanehira
  echo "skanehira ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
'
```

パッケージの選定理由。`python3` は手順 6 の到達性テストで使う。`build-essential` は nvim-treesitter が parser を cc でコンパイルするために要る。`locales` は `/etc/locale.gen` を書き換えてから引数なしで `locale-gen` を呼ぶ。Debian の `locales` はこのファイルで有効化された行だけを生成するため、`locale-gen en_US.UTF-8` だけでは何も作られないことがある。`nix/modules/home/env.nix` が `LANG` と `LC_ALL` に `en_US.UTF-8` を設定するので、生成しないと apt や perl が `setlocale` の警告を出し続ける。

ユーザー名を `skanehira` にするのは、flake の `linuxUsers` に既に入っており追加の変更が要らないため。

期待 (以後のログインコマンドで入り直して確認する):

```bash
proot-distro login debian --user skanehira --shared-tmp
locale -a | grep en_US.utf8     # 1 行返る
cat /etc/debian_version         # リリースを記録しておく
ldd --version | head -1         # glibc 版を記録しておく
```

`--shared-tmp` は Termux 側と `/tmp` を共有する。Claude Code や nix が作る一時ファイルを Termux 側のツールから触れるようにするためで、必須ではない。Debian のリリースと glibc 版を記録しておくのは、手順 5 でバイナリが動かなかったときの切り分けに使うため (proot-distro の Debian は特定リリースに pin されていない)。

### 4. Nix を入れる

proot には systemd がないので、multi-user (`--daemon`) ではなく single-user で入れる。proot は user namespace を作れないため、ビルドサンドボックスも切る。

```bash
sh <(curl -L https://nixos.org/nix/install) --no-daemon
mkdir -p ~/.config/nix
cat > ~/.config/nix/nix.conf <<'EOF'
experimental-features = nix-command flakes
sandbox = false
EOF
. ~/.nix-profile/etc/profile.d/nix.sh
```

`experimental-features` をファイルに書くのは、Phase 1 の `nix run home-manager/master` がネストした nix を呼ぶためで、コマンドラインの `--extra-experimental-features` では伝播しない (CLAUDE.md の Linux 節と同じ理由)。

期待: `nix --version` が版番号を返す。

失敗したときの分岐:

- installer が `/nix` を作れない: root で入り直して用意する。`proot-distro login debian -- bash -c 'mkdir -p /nix && chown skanehira:skanehira /nix'`
- seccomp まわりで落ちる: Termux 側で `PROOT_NO_SECCOMP=1 proot-distro login debian --user skanehira --shared-tmp` として入り直す

### 5. 各ツールが起動するか

ここが最大の未検証点。インストールと版の確認を別行にして、失敗したのがどちらか分かるようにする。

```bash
nix run nixpkgs#hello
nix run nixpkgs#opencode -- --version

curl -fsSL https://claude.ai/install.sh | bash
~/.local/bin/claude --version

VP_NODE_MANAGER=no curl -fsSL https://vite.plus | bash
~/.vite-plus/bin/vp --version
```

`VP_NODE_MANAGER=no` を付けるのは、Vite+ の installer が Node のバージョンマネージャを入れるか対話で聞くため。ここでは Node を Phase 1 の Nix で入れるので断る。

Claude Code のログインはブラウザ自動連携が効かない。表示された URL を Android の Chrome で開き、返ってきたコードを貼る。うまくいかない場合は `claude setup-token` を使う。

### 6. ブラウザから開けるか

ツールチェインとは独立に、ネットワーク到達性だけを先に確かめる。背景実行にして、同じシェルで確認まで続けられるようにする。

```bash
python3 -m http.server 8000 --bind 127.0.0.1 &
echo $!    # PID を控える
```

Chrome で `http://127.0.0.1:8000` を開く。Termux は通常の Android アプリなのでネットワーク名前空間を端末と共有しており、ポート転送の設定は要らない。

画面を消して 10 分待ってから戻り、`pgrep -f http.server` でプロセスが生きているかを見る。死んでいたら手順 2 に戻る。確認できたら `kill %1` で止める。

### 7. 実際の dev サーバー

Node はまだ入っていないので、Phase 0 では nix 経由で借りる。

```bash
nix shell nixpkgs#nodejs_24 --command bash -c '
  ~/.vite-plus/bin/vp create
'
cd <作ったディレクトリ>
nix shell nixpkgs#nodejs_24 --command ~/.vite-plus/bin/vp dev
```

Chrome で `http://127.0.0.1:5173` が開けば Phase 0 は完了。

## Phase 1: dotfiles を適用する

Phase 0 が通ってから実施する。前提が 1 つある。**`.#skanehira-android` を含むコミットが GitHub に push 済みであること**。このリポジトリは push を手動で行う運用なので、mac 側でコミットしただけでは端末から clone しても output が無い。

```bash
mkdir -p ~/dev/github.com/skanehira
cd ~/dev/github.com/skanehira
git clone https://github.com/skanehira/dotfiles.git
cd dotfiles/nix
nix run home-manager/master -- switch -b hm-backup --flake .#skanehira-android
```

`-b hm-backup` は必須。手順 3 の `useradd -m` が `/etc/skel` から `.bashrc` と `.profile` を置いており、このプロファイルは `programs.bash` を有効にするので Home Manager が同じパスを要求する。`-b` が無いと初回から "would be clobbered" で中断する。既存ファイルは `.bashrc.hm-backup` のように退避される。

clone 先を固定するのは、`mkOutOfStoreSymlink` がこのパスを直接参照するため。パスは `nix/home-core.nix` の `dotfilesRoot` が `$HOME` 起点で組み立てており、Claude Code や Neovim の設定 symlink がこれを消費する。

期待: `Activating ...` の行が並び、最後に新しい generation が作られる。

switch のあと、いったんログアウトして入り直し、PATH が生きていることを確認する。

```bash
exit
proot-distro login debian --user skanehira --shared-tmp
command -v nix && command -v nvim && command -v hms
```

Home Manager は `~/.profile` を自分の生成物で置き換えるので、手順 4 の installer が書いた nix.sh の source 行は消える。代わりに `nix/home-android.nix` が `home.sessionPath` に `~/.nix-profile/bin` を足しているため PATH は保たれる。ここで `command -v nix` が空になるようなら、その場は `. ~/.nix-profile/etc/profile.d/nix.sh` で復旧してから報告する。

Phase 0 で入れた Claude Code と Vite+ は再インストールされない。どちらの bootstrap も「バイナリが無いときだけ実行する」条件なので、activation では no-op になる。

以後の設定反映は `hms` で行える。Android プロファイルの `hms` は `-c skanehira-android` を指すように生成されている。

### Android プロファイルに入るもの

`nix/home-android.nix` が入口で、通常の Linux プロファイル (`nix/home-linux.nix`) とは別系統。`cache.nixos.org` に無いパッケージと大物を外し、proot の限られた RAM とストレージで完走することを優先している。

`packages-android.nix` が明示列挙するのは 18 エントリ。これに `programs.git` / `programs.gh` / `programs.zsh` / `programs.fzf` / `programs.direnv` が足す分と Home Manager 内部のものが乗って、`home.packages` は 33 件になる。

- 言語ランタイム: nodejs / pnpm
- エージェント: Claude Code (activation 時に公式インストーラを実行) / OpenCode (nixpkgs)
- Deno: `claude/settings.json` の hook 5 本が `deno run` で起動するので外せない。activation 時に公式インストーラを実行する
- フロントエンド: Vite+ (activation 時に公式インストーラを実行。nixpkgs 未収録で、overlay 版は aarch64-linux でビルドが落ちるため)
- エディタと端末: neovim (nixpkgs の stable。nightly ではない) / tmux
- 軽量 CLI: bat / fd / jq / lsd / ripgrep / tree
- LSP: typescript-go / lua-language-server / nixd
- 共有設定が参照するので外せないもの: tirith (zsh の起動時に無条件で初期化される) / ghq (`ghq-fzf` 関数) / nh (`hms` alias) / tree-sitter (nvim-treesitter の parser ビルド)
- module が入れるもの: git / gh / zsh / fzf / direnv / home-manager

通常の Linux プロファイルに入っていて Android には入れていないもの:

| 分類 | 具体例 | 外した理由 |
| --- | --- | --- |
| binary cache が無い | neovim nightly / terraform / herdr / gws / version-lsp / 自前 LSP (tsp-server, gh-actions-language-server) | proot でコンパイルできない |
| 大物 | ollama / ffmpeg / ghostscript / clang-tools / go / bun / zig / awscli2 / k9s / kubernetes-helm / supabase-cli | ストレージと帯域を食う |
| 要件外 | rustup / codex / nix-index (と `,` コマンド) / その他の linter | Android で使わない。nix-index は DB を毎週 fetch するため特に重い |

必要になったら `nix/modules/home/packages-android.nix` に足す。足す前に `cache.nixos.org` にあるかを `nix build --dry-run` の fetch 側に出るかで確かめる。

### ログインシェル

Home Manager standalone は `chsh` を実行しないので、proot の初期シェルは bash のまま。Android プロファイルは `programs.bash` を有効にし、`.bashrc` の末尾で zsh に exec する。対話判定は Home Manager が `.bashrc` 冒頭に置く `[[ $- == *i* ]] || return` に任せているので、非対話 bash は zsh に切り替わらない。

## 日常運用

2 回目以降は次の流れになる。

```bash
# Termux を開いて
proot-distro login debian --user skanehira --shared-tmp
# .bashrc が zsh に exec するので、そのまま zsh のプロンプトが出る
```

初回だけ済ませておくもの。

- `gh auth login` — `nix/modules/home/gh.nix` が git の credential helper に gh を指定するので、これを通さないと push できない
- Claude Code のログイン — 手順 5 と同じく、URL を Chrome で開いてコードを貼る
- `git config` の署名まわりは mac と同じ設定が `git.nix` 経由で入る

設定を変えたら `hms` を打つ。dotfiles を編集しただけで反映されるもの (Claude Code の設定・Neovim の lua・tmux.conf) は `mkOutOfStoreSymlink` なので `hms` は要らない。

## 既知の制約

| 制約 | 内容 |
| --- | --- |
| Docker | 使えない。proot はカーネルを共有するだけで名前空間を分離しない |
| Nix ストア | Termux のアプリ内領域に置かれる。Termux をアンインストールすると消える。数 GB から十数 GB に膨らむ |
| ビルド速度 | proot は評価もビルドも遅い。キャッシュに無いものはローカルビルドになり実質不可と考える |
| treesitter の parser | nvim-treesitter は parser を cc でコンパイルする。手順 3 で `build-essential` を入れているが、proot でのビルドは遅い。数が多いと待たされる |
| クリップボード | `tmux/tmux.conf` の Linux 分岐は `xsel` を前提としている。proot 内に X が無いので、copy-mode の `y` によるコピーと `prefix + ]` による貼り付けが両方失敗する |
| OpenCode の接続先 | `opencode/opencode.json` は自宅の `spark-head.local` を mDNS で引く。外出先ではモデルに繋がらない |
| Claude Code の SessionStart hook | `claude/settings.json` の 1 本が `/Users/skanehira/...` という mac 固定パス (herdr 用) を指す。Linux では毎回失敗するが、他の hook と Claude Code 本体には影響しない |
| Claude Code の自動更新 | 更新でバイナリが差し替わる。壊れた場合は `nix/modules/home/env.nix` の `home.sessionVariables` に `DISABLE_AUTOUPDATER = "1"` を足して `hms` する |
| Vite+ のシェル設定追記 | installer は `~/.zshrc` などに env の source を追記しようとするが、Home Manager がそれらを read-only symlink として管理しているので失敗する。PATH は `home.sessionPath` で通すので実害はない |
| DeX | この端末は外部ディスプレイ接続時のみ。内蔵画面では使えない |
| 発熱 | 連続ビルドでスロットリングする |

## 依拠する外部事実 (確認日 2026-09-06)

| 事実 | 出典 |
| --- | --- |
| Fold 8 / Fold 8 Ultra は Linux Terminal 非対応 | https://www.androidauthority.com/samsung-galaxy-z-fold-8-flip-8-linux-terminal-support-3688560/ |
| Snapdragon が non-protected VM を欠くのが理由 | https://www.androidauthority.com/snapdragon-chips-android-linux-terminal-3608648/ |
| One UI 8.5 でも Exynos 限定 | https://www.androidauthority.com/samsung-phones-linux-terminal-one-ui-8-5-3652503/ |
| Play 版 Termux は experimental | https://github.com/termux/termux-app |
| proot 上の Nix は sandbox 無効化が必要 | https://wiki.nixos.org/wiki/Nix_Installation_Guide |
| phantom process killer が子プロセスを殺す | https://github.com/termux/termux-app/issues/2366 |
| Claude Code は Linux ARM64 対応 | https://code.claude.com/docs/en/setup |
| Claude Code は glibc 化により Termux 直上で起動しない | https://github.com/anthropics/claude-code/issues/50270 |
| Bun が Android 非対応のため OpenCode の npm 版が入らない | https://github.com/anomalyco/opencode/issues/12515 |
| Vite+ の公式インストーラと `VP_NODE_MANAGER` | https://github.com/voidzero-dev/vite-plus |
| Fold 8 Ultra の DeX は外部ディスプレイのみ | https://sammyguru.com/galaxy-z-fold-8-z-fold-8-ultra-samsung-dex/ |

リポジトリ内の事実は 2026-09-06 に実測した。プロファイルの規模は mac (aarch64-darwin) から `nix build --dry-run` を両プロファイル連続実行して比較しており、数値は CLAUDE.md の「Android を別プロファイルにする理由」に載せてある。

## 端末で初めて分かること (未検証)

- proot 内で Claude Code / OpenCode (Bun) / Vite+ (gnu バイナリ) が起動するか
- proot 内で bind したポートが Android の Chrome から見えるか
- One UI 9 で phantom process killer 対策が効くか
- proot-distro の Debian が配る `/etc/locale.gen` の行形式が `# en_US.UTF-8 UTF-8` か
- 初回 switch が RAM とストレージの制約内で完走するか
