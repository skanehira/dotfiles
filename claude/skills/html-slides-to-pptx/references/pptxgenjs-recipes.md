# pptxgenjs 実装レシピ (HTML スライド 1920×1080 → 13.333×7.5in)

実測で検証済みの換算値・実装パターン・落とし穴集。`example/` は実際に 46 枚を変換した参照実装 (ダークターミナルテーマ)。

## 単位換算

| 変換 | 式 | 例 |
|---|---|---|
| px → inch | `px / 144` | 96px パディング → 0.667in |
| フォント px → pt | `px / 2` | 64px タイトル → 32pt |
| 全角換算幅 | 全角=1 / 半角(ASCII)=0.55 | チップ幅の見積りに使用 |

- 行数見積り: `ceil(全角換算幅 / floor(ボックス幅in × 144 / フォントpx))` (`example/pptx-theme.mjs` の `estLines`)
- CSS `color-mix()` 相当は RGB 線形補間で自作 (`mix()`)。pptxgenjs の `fill.transparency` は重なり順に依存するため、地色に混ぜた不透明色の方が安定

## 実装パターン

- **shape + text 複合**: `slide.addText(runs, { shape: "roundRect", rectRadius, fill, line, ... })` で「枠付きテキストボックス」を 1 要素で作れる (カード・チップ・バッジ)。テキスト inset は `margin` (単位 pt)
- **run 配列**: `[{ text, options: { color, bold, fontFace, breakLine, paraSpaceAfter } }]`。段落区切りは `breakLine: true`、段落間隔は `paraSpaceAfter` (pt)。`<em>`/`<b>`/`<span class="mono">` は run の色・太字・フォント切替に写像する (`example/pptx-helpers.mjs` の `parseInline`)
- **テーブル**: `addTable(rows, { colW: [..], rowH })`。セル罫線は `border: [top, right, bottom, left]` の 4 要素配列。「下線のみ」は bottom 以外を `{ type: "none" }`
- **レイアウトは y カーソル方式**: 固定高ブロック (term/表/パネル/チップ) は内容から高さを計算、可変ブロック (カードグリッド等、CSS の flex:1 相当) は `(残り高さ - ギャップ) / 可変ブロック数` で配分 (`example/pptx-helpers.mjs` の `renderSlide`)
- **参照スクリーンショット**: playwright で原本 HTML を viewport 1920×1080・deviceScaleFactor 2 で開き、`document.fonts.ready` を待ってから 1 枚ずつ撮る。スライド送りはデッキ依存 (ArrowRight キーが多い)。Web 用ナビ UI (ページカウンター等) は `addStyleTag` で `display: none` にしてから撮る

## 落とし穴 (実測で踏んだもの)

1. **非 active スライドの innerText**: `display: none` のスライドは innerText の改行が落ちて全要素が連結される。テキスト抽出前に全スライドへ表示用 class を付与する (verify-content.mjs は対応済み)
2. **タイトル下マージン**: ボックス高さ基準で詰めると視覚的に潰れる (glyph はボックスより小さい)。glyph 下端から 60px 相当 (≥ 0.42in) を確保する。実測ではこの余白不足だけで視覚 QA の medium 指摘が 5 件集中した
3. **チップ状要素の幅**: 全角換算幅 × 0.19in + 固定分で見積り、スライド本文幅でキャップする。狭いと 1 文字だけの孤立折り返しが起きる
4. **カード内の描画順**: HTML の出現順 (例: リード文 → 箇条書き) を保持する。部品種別ごとの固定順で描くと文意が変わる
5. **ソース改行由来のスペース**: HTML ソースのタグ内改行は半角スペース 1 個として描画される。原文をコピーする際に落とすと網羅照合で差分になる (逆に、照合が検出してくれる)
6. **フォント埋め込み不可**: pptx (pptxgenjs) はフォントを埋め込めない。Web フォント前提のデザインは、開く環境に存在するフォント (Consolas / 游ゴシック等) への置換をユーザに必ず確認する
7. **PowerPoint 実機との差**: LibreOffice レンダリングは QA 用の近似。開く環境のフォントメトリクスで折り返し位置は変わりうるため、完了報告に明記する
