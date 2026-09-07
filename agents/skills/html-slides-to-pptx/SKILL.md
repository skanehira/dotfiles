---
name: html-slides-to-pptx
description: "単一 HTML のスライドデッキ (Claude Design 等で作成したもの) を、テキスト編集可能なネイティブ PowerPoint (.pptx) に再構築する。pptxgenjs でテキストボックス・図形・表として組み直し、テキスト網羅照合 + 視覚 QA で原本との一致を保証する。「スライドのHTMLをパワポにして」「HTMLをpptxに変換して」「編集可能なパワポにして」などのリクエストで起動。見た目の再現だけでよい場合 (スクリーンショットを画像スライドとして貼る方式で足りる) や、既存 pptx の言語変換 (pptx-translator) は対象外。"
argument-hint: "[HTMLファイルまたはディレクトリ]"
---

# HTML スライド → 編集可能 pptx 変換

## 方式 (重要な前提)

任意 HTML の全自動変換は行わない。**デッキごとに Claude がレンダラを書き起こすメソッドスキル**である:

1. 原本 HTML のレイアウト部品を棚卸しし、部品ごとの pptxgenjs レンダラ (theme 定数 + 部品関数 + デッキデータ) をスクラッチパッドに実装する
2. 正しさは 2 つの機械検証で担保する: **テキスト網羅照合** (原本の全可視テキストが pptx に含まれるか) と**視覚 QA** (レンダリング画像を原本スクリーンショットと subagent が照合)

実装の具体例・換算値・落とし穴は [references/pptxgenjs-recipes.md](references/pptxgenjs-recipes.md) と [references/example/](references/example/) (実際に 46 枚を変換した参照実装) にある。**実装前に必ず recipes を Read すること**。

## 前提

- スクラッチパッドで `npm install playwright pptxgenjs` (playwright の chromium が未取得なら `npx playwright install chromium`)
- 視覚 QA 用に `soffice` (LibreOffice) と `pdftoppm` (poppler) が必要。無ければユーザに導入方法を確認する (この環境では nix 管理: `nix/modules/home/packages.nix` の mediaTools に `libreoffice-bin` / `poppler-utils`)

## 手順

### 1. 分析

- 原本 HTML の構造を確認: JS データ駆動 (スライド定義の配列 + テンプレート関数) か、静的 DOM か。データ駆動ならその配列が移植元になる
- レイアウト部品 (カード・表・ターミナル風ボックス・対比リスト等) を棚卸しし、部品 × 使用スライドの一覧を作る
- playwright で原本の参照スクリーンショットを全枚数分撮る (recipes の「参照スクリーンショット」参照)。後の視覚 QA の比較対象になる

### 2. ユーザ確認 (AskUserQuestion)

- **フォント**: pptx はフォント埋め込み不可。原本が Web フォントなら置換先を確認する (推奨: 等幅 → Consolas、日本語 → 游ゴシック。Office 標準搭載で配布先でも崩れない)
- **出力先**: pptx の配置場所

### 3. 網羅照合を RED で用意 (TDD)

[scripts/verify-content.mjs](scripts/verify-content.mjs) をスクラッチパッドにコピーし、pptx 生成前に実行して RED を確認する:

```bash
node verify-content.mjs <出力予定の deck.pptx> <原本1.html> [原本2.html ...]
```

### 4. 実装

recipes と example を参照しながら、スクラッチパッドに以下を実装する:

- `pptx-theme.mjs` — 原本 CSS の色・寸法を写した定数と換算ヘルパー
- `pptx-helpers.mjs` — 部品レンダラ (y カーソル方式の縦積み + flex 配分)
- `deck-*.mjs` — 原本のスライドデータの移植 (テキストは一字一句コピーする。言い換え・省略をすると網羅照合が落ちる)
- `build-pptx.mjs` — ビルドエントリ

### 5. 検証ループ (最低 1 サイクル)

1. `node build-pptx.mjs` → verify-content.mjs が green になるまで修正
2. [scripts/render-pptx.sh](scripts/render-pptx.sh) で pptx を PNG 連番化:
   ```bash
   bash render-pptx.sh <deck.pptx> <出力dir> [dpi]
   ```
3. 視覚 QA を subagent (model: opus, fresh eyes) にデッキ単位で並列 fan-out。レンダリング PNG と手順 1 の参照スクリーンショットを 1 枚ずつ照合させ、「はみ出し / 重なり / 欠落 / 色・配置の乖離 / 余白の偏り」を深刻度付きで報告させる (「問題があると仮定して探せ。0 件なら見方が甘い」と指示する)
4. high/medium の指摘は根本原因単位でまとめて修正し、再ビルド → 該当スライドの再レンダリングで解消を確認する。修正がレイアウト定数なら回帰テスト化を検討 (例: pptx XML の shape 座標からタイトル下余白を検証)

### 6. 完了報告

4 点形式 (変更の要約 / 動作確認結果 / 既知の残骸 / 次にユーザがする決定) で報告し、必ず以下を含める:

- 編集可能なことの確認方法 (PowerPoint で開いてテキストをクリック)
- フォント注意: LibreOffice での QA は近似であり、開く環境のフォントで折り返し位置が変わりうること

## スクリプト一覧

| スクリプト | 役割 |
|---|---|
| [scripts/verify-content.mjs](scripts/verify-content.mjs) | 原本 HTML の全可視テキストが pptx の段落に含まれるかの網羅照合 (デッキ非依存) |
| [scripts/render-pptx.sh](scripts/render-pptx.sh) | pptx → PDF → PNG 連番 (soffice + pdftoppm)。視覚 QA の入力を作る |
| [references/example/](references/example/) | 参照実装一式 (theme / helpers / デッキデータ例 / ビルドエントリ) |
