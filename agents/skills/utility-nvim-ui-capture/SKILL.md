---
name: utility-nvim-ui-capture
description: Neovim プラグインの UI を、rtty のブラウザターミナルに表示してヘッドレス Chromium でスクリーンショットを撮る。ghost で rtty を起動し、撮影後に止める。float window のレイアウト・ハイライト・タイトルの折り返し・列幅・ラベルピルなどを GitHub などの参照 UI と比較するときに使う。「Neovim の UI をスクショで確認して」「ブラウザで Neovim を操作してキャプチャして」「rtty で画面を確認して」「プラグインの画面を撮って」「UI のギャップを確認して」などで起動。macOS + rtty + ghost + Playwright 前提。
allowed-tools: Bash, Read
---

# Neovim プラグイン UI のスクリーンショット確認 (rtty + ブラウザ)

Neovim プラグインの UI (float window、ハイライト、列幅、折り返し、選択状態、ラベルピル) を、**rtty のブラウザターミナル**に表示して**ページ全体**をキャプチャし、GitHub などの参照 UI と比較する。

デスクトップや WezTerm のウィンドウは撮らない。rtty が `nvim` を PTY で動かし、xterm.js のページを配信する。ghost で rtty をバックグラウンド起動し、Playwright のヘッドレス Chromium でそのページを撮り、撮影後に rtty を止める。画面収録やアクセシビリティの権限は要らない。

## 前提

- macOS
- rtty (`go install github.com/skanehira/rtty@latest`。PATH、`$HOME/go/bin/rtty`、または `RTTY_BIN`)
- ghost が PATH にある
- node / npm (Playwright は初回に `~/.cache/nvim-ui-capture/playwright` へ自動インストール。Chromium は `~/Library/Caches/ms-playwright` のキャッシュを使う)
- 検証対象の Neovim を**絶対パス**で指定する。github.nvim は 0.10.4 (0.13.0-nightly は `create_spec.lua` の端末チャネル検証が落ちる)
- 実 API は使わない。fixture と fake `gh` で決定的なデータにする

## フォント

ブラウザのターミナルは xterm.js なので、**Neovim が描く文字をカバーするフォント**を渡す必要がある。特に:

- Nerd Font のアイコン (U+F0000 台)
- ラベルピルの丸いキャップ (Powerline、U+E0B6 / U+E0B4)
- 罫線 (U+2500–257F) と日本語

フォントが足りないと、その文字だけ**空白や □** になる。スクリーンショットの文字欠けに気づいたら、まずフォントを疑う。

既定は `--font "Cica"` / `--font-size 15` (ユーザーの WezTerm 設定に合わせた値)。Cica は Nerd Font 互換で、U+E0B6 / U+E0B4 / U+F013 / 日本語を含む。別のフォントを使うときは `--font` で指定する。Chromium から見えないフォント (アプリ同梱など) は `~/Library/Fonts` にコピーする。

## 手順

### 1. 最小の init.lua を作る

`references/init-template.lua` をコピーし、プラグインのパス・setup・UI を開く関数・キー操作を埋める。

- `-u` で起動するので、ユーザーの設定は読み込まれない
- `rtp` にプラグインを追加し、`termguicolors`、`laststatus`、`showtabline`、`colorscheme` を設定する
- UI は起動 150ms 後に開く。選択状態を写したいときは 1200ms 後にキーを送る
- fake `gh` を使うときは、スクリプトの `--path` で PATH を渡すか、init の先頭で `vim.env.PATH` に足す

### 2. fixture を用意する

`references/fake-gh.md` の形で、`gh` を PATH の先頭に置いた偽物に差し替える。GraphQL の応答を fixture から返し、実データ・レート制限・副作用を避ける。

### 3. キャプチャする

スキルのベースディレクトリから:

```bash
scripts/nvim-ui-capture.sh \
  --init /tmp/nvim-ui-capture/init.lua \
  --out /tmp/nvim-ui-capture/board.png \
  --nvim /tmp/nvim-macos-arm64/bin/nvim \
  --path /tmp/nvim-ui-capture/bin \
  --wait 2.5 \
  --headless
```

スクリプトは次を行う:

1. `ghost run` で `rtty run "nvim -u init.lua" -p PORT -a localhost --font Cica --font-size 15` をバックグラウンド起動する
2. `http://localhost:PORT/` が応答するまで待つ
3. Playwright のヘッドレス Chromium でページを開き、キーを送り、**ページ全体**を撮る
4. `ghost stop` で rtty を止める (`trap EXIT` なので失敗時も止まる)
5. 出力パス・URL・ビューポート・画像サイズ・rtty の状態を表示する

ブラウザ側では、キャンバス描画の 1px の横線を避けるため **DOM レンダラーを強制**する。フォントの読み込みを待ち、ターミナルを**再フィット**して PTY のサイズを合わせ、**最下部までスクロール**してから撮る。

`ghost run` には `-e TERM=xterm-256color -e COLORTERM=truecolor` を渡す。呼び出し元の `TERM` が `dumb` のままだと、nvim は全画面のカーソル制御を行わず行単位で描画し、画面がスクロールバックに積もって上に前の画面が写る。

出力の `captured:` のパスを `read_image` で確認する。`--dry-run` で実行するコマンドだけを確認できる。`--verbose` で進捗を出す。

### 4. 詳細を確認する

全体を見て、必要なら crop する。`sips -c` は**高さ→幅**の順:

```bash
sips -c 420 640 /tmp/nvim-ui-capture/board.png \
  --out /tmp/nvim-ui-capture/card.png
```

これは画像の中央を切り出す。位置を指定したいときはスクリプトの `--crop WxH+X+Y` を使い、結果を `read_image` で確認する (sips の `--cropOffset` は中央からの相対なので、思った位置とずれることがある)。

参照 UI と次を比較する:

- タイトルが省略されず、必要な行数で折り返されているか
- 列幅がウィンドウに収まり、右側に余白がないか
- float のボーダーが従来どおりか
- 選択列・選択カードの強調が参照 UI と合っているか
- ラベル、アバター、進捗、関連 PR が表示されているか
- 色 (背景・枠線・文字・選択色) が参照 UI と合っているか

### 5. 反復する

UI を直したら、**毎回新しいセッション**でキャプチャする。同じ URL を使い回すと、前の状態やスクロール位置が残る。変更前後を比較するときは、同じサイズ・同じ選択状態・同じデータで撮る。

## トラブルシューティング

- **文字が欠ける・□ になる**: フォントがグリフを持っていない。`--font` で Nerd Font / Powerline 対応のフォントを指定する。Cica は既定で対応済み
- **横線が入る**: キャンバス描画の継ぎ目。スクリプトが DOM レンダラーを強制するので、古い版のスクリプトを使っていないか確認する
- **下部が崩れる・上がスクロールバック**: `TERM=dumb` のまま nvim が起動すると、カーソル位置制御をせず行単位で描画し、画面が下に積もって前の画面が上に写る。スクリプトは `ghost run -e TERM=xterm-256color` を渡す。自分で rtty を起動するときも `TERM` を確認する。それでも崩れるときは `--wait` を増やす
- **rtty が見つからない**: `go install github.com/skanehira/rtty@latest`。`RTTY_BIN` でも指定できる
- **ghost が見つからない**: PATH を確認する
- **ポートが使われている**: スクリプトが 10000–10099 の空きポートにフォールバックする
- **Playwright が無い**: 初回は自動インストール。Chromium が無いときは `npx playwright install chromium`
- **Chromium の起動が遅い / タイムアウトする**: マシンの負荷が高い。負荷が下がってから再実行する
- **Neovim のバージョン違いで落ちる**: 検証対象のバージョンを `--nvim` で絶対パス指定する

## チェックリスト

- [ ] rtty + ghost + ヘッドレス Chromium で撮った
- [ ] 撮影後に rtty が止まっている (`rtty: ... (stopped)`)
- [ ] ページ全体 (ターミナル) を撮った
- [ ] 文字欠けがない (フォントがグリフを持つ)
- [ ] 画面下部が切れていない・スクロールバックが写っていない
- [ ] タイトルが省略されず折り返されている
- [ ] 列幅がウィンドウに収まり、右側に余白がない
- [ ] float のボーダーが従来どおり
- [ ] 選択列・選択カードが参照 UI と一致
- [ ] ラベル・アバター・進捗・関連 PR が表示される
- [ ] 変更前後を同じ条件で撮った
