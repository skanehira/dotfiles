---
name: slide-generating
description: テキスト入力からWebベースのプレゼンテーションスライド（HTML + Tailwind CSS + JS）を生成する。カンファレンス登壇やセールス資料として使えるレベルの品質を目指す。「スライドを作って」「プレゼン資料を作成」「デッキを生成」「/slide-generator」、既存のスライドHTMLの修正依頼で起動する。
metadata:
  short-description: Webスライド生成
---

# Slide Generator

テキスト入力から高品質なWebベースのプレゼンテーションスライドを生成するスキル。

## 出力仕様

- **形式**: 単一HTMLファイル（Tailwind CDN + インラインCSS/JS）
- **サイズ**: 各スライド 1920px x 1080px（16:9）
- **画像**: プレースホルダーは `https://placehold.jp/` を使用。実画像は `assets/` ディレクトリに配置
- **フォント**: Google Fonts CDN（Noto Sans JP をデフォルト日本語フォントとして使用）
- **テーマ**: CSS変数によるテーマトークン管理。指定がなければ白黒ベースのデフォルトテーマ

## ワークフロー

### Step 1: 入力受付

ユーザーから以下のいずれかの形式で入力を受け取る：

**A. 自由テキスト**（例: 「自社紹介資料を作って。会社名はXXで、事業内容は...」）
- AIが内容を解析し、スライド構成を自動提案する

**B. 構造化テキスト**（例: markdownアウトライン形式）
- ユーザーが指定した構成に従ってスライドを生成する

入力受付時に以下も確認する：
- テーマの指定があるか（カラー、フォント等）
- 画像素材の有無（assets/ディレクトリにあるか）
- スライド枚数の目安

### Step 2: 構成提案

ユーザーに以下の形式でスライド構成を提案し、承認を得る：

```
## スライド構成案

 | #   | Family   | Variant         | タイトル            | ビジュアル要素            |
 | --- | -------- | ---------       | ---------           | ---------------           |
 | 1   | hero     | cover           | 会社名 + タグライン | グラデーション背景 + ロゴ |
 | 2   | hero     | section-divider | About               | グラデーション背景        |
 | 3   | split    | text-image      | 会社概要            | 右にオフィス写真          |
 | ... | ...      | ...             | ...                 | ...                       |

### 画像素材について
- 用意が必要: ロゴ、写真等（ユーザーが用意）
- 自動生成: SVGアイコン、グラデーション、装飾

この構成でよろしいですか？修正があればお知らせください。
```

**重要**: ユーザーの承認を得てからStep 3に進むこと。

**ビジュアル提案ルール** (`references/visual-guidelines.md` 参照):
構成提案時に、各スライドに適切なビジュアル要素を提案すること。テキストのみのスライドが3枚以上連続しないよう注意する。

### Step 3: HTML生成

承認された構成に基づいて単一HTMLファイルを生成する。

**生成ルール:**

1. `references/families.md` のHTMLテンプレートパターンに従うこと
2. `references/theme.md` のテーマトークンシステムを適用すること
3. `references/navigation.md` のナビゲーションJSを組み込むこと
4. 全スライドを1つのHTMLファイルに含めること
5. 各スライドは `<section class="slide">` で囲むこと
6. Tailwind CDN をインラインで読み込むこと
7. 画像が指定されていない場合は placehold.jp を使用すること

**HTMLの全体構造:**

```html
<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{プレゼンタイトル}</title>
  <script src="https://cdn.tailwindcss.com"></script>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link href="https://fonts.googleapis.com/css2?family=Noto+Sans+JP:wght@400;500;700;900&display=swap" rel="stylesheet">
  <style>
    /* テーマトークン（references/theme.md 参照） */
    :root { ... }
    /* スライド基本スタイル */
    /* 印刷用スタイル */
    /* ナビゲーションスタイル */
  </style>
</head>
<body>
  <div id="slide-container">
    <section class="slide" data-slide="1" data-family="hero" data-variant="cover">
      <!-- スライド内容 -->
    </section>
    <!-- 以降のスライド -->
  </div>

  <!-- ナビゲーションUI -->
  <div id="slide-nav">...</div>

  <script>
    /* ナビゲーションJS（references/navigation.md 参照） */
  </script>
</body>
</html>
```

**コンテンツ生成の原則:** 「1スライド1メッセージ」、箇条書きは3〜5項目上限、テキスト過多なら分割する。詳細は `references/families.md` 冒頭の共通ルールを参照。

### Step 4: 品質レビュー

chrome-devtools MCPを使用してスクリーンショットベースのレビューを実施する。

**レビュー手順:**

1. 生成したHTMLをブラウザで開く（`mcp__chrome-devtools__navigate_page` を使用）
2. ビューポートを 1920x1080 に設定（`mcp__chrome-devtools__resize_page` を使用）
3. サンプリング方式でスクリーンショットを撮影：
   - カバースライド（1枚目）
   - セクション区切り（1枚）
   - 使用した各familyから1枚ずつ
   - 合計5〜7枚程度
4. `references/quality-checklist.md` の基準に従ってレビュー
   - **構造レベル**（配置・余白・アラインメント）だけでなく、**コンテンツレベル**（画像の見切れ・テキストの途切れ・情報の欠落）まで検証すること
   - 特に画像を含むスライドでは、スクショと元画像を見比べて重要情報が切れていないか確認する
5. 問題があれば自動修正し、該当スライドのみ再スクショで確認

**スライド移動方法:**
- `mcp__chrome-devtools__evaluate_script` で `navigateToSlide(n)` を実行してスライドを移動
- 移動後に `mcp__chrome-devtools__take_screenshot` でスクリーンショットを撮影

### Step 5: PDF出力（ユーザーが要求した場合のみ）

Playwrightを使用してPDF出力する。

**依存パッケージ**: `playwright-core`（未インストールの場合は `npm install playwright-core` を実行）

```bash
npx playwright-core install chromium 2>/dev/null
node -e "
const { chromium } = require('playwright-core');
(async () => {
  try {
    const browser = await chromium.launch();
    const page = await browser.newPage();
    await page.goto('file://' + require('path').resolve('{HTMLファイルパス}'));
    await page.waitForLoadState('networkidle');
    await page.pdf({
      path: '{出力PDFパス}',
      width: '1920px',
      height: '1080px',
      printBackground: true,
      landscape: true
    });
    await browser.close();
    console.log('PDF出力完了: {出力PDFパス}');
  } catch (err) {
    console.error('PDF出力エラー:', err.message);
    process.exit(1);
  }
})();
"
```

## レイアウトシステム

### Family + Variant 方式

7つのfamilyで全スライドパターンをカバーする。各familyの詳細なHTMLテンプレートは `references/families.md` を参照。

| Family            | Variant            | 用途                                 |
| ----------------- | ------------------ | ------------------------------------ |
| **hero**          | cover              | カバー（タイトル+サブタイトル+ロゴ） |
|                   | section-divider    | セクション区切り（番号+名前）        |
|                   | closing            | CTA、連絡先、QRコード                |
|                   | big-number         | KPI、大きな数字+説明                 |
|                   | quote              | 引用テキスト+出典                    |
| **single-column** | bullet-list        | 見出し+箇条書き                      |
|                   | text-block         | 見出し+本文                          |
| **split**         | text-image         | テキスト+画像（左右配置）            |
|                   | two-column         | 2カラムテキスト                      |
|                   | comparison         | Before/After、左右対比               |
|                   | qa                 | Q&A形式                              |
| **grid**          | cards              | カード2〜4枚横並び                   |
|                   | logos              | ロゴ一覧（カテゴリ別）               |
|                   | team-members       | メンバー紹介（丸写真+名前）          |
| **sequence**      | steps              | ステップ/プロセス                    |
|                   | timeline           | 年表・時系列                         |
| **table**         | pricing            | 料金表                               |
|                   | feature-comparison | 機能比較表                           |
| **diagram**       | flow               | フローチャート                       |
|                   | org-chart          | 組織図・階層図                       |

### Family選択の判断基準

- **1つのメッセージを大きく伝える** → hero
- **テキストを順番に伝える** → single-column
- **2つの要素を並べる** → split
- **3つ以上の要素を並べる** → grid
- **順序・流れを見せる** → sequence
- **構造化データを見せる** → table
- **関係性を見せる** → diagram

## 参照ファイル

- `references/families.md` - family/variant別の具体的なHTMLテンプレートパターン
- `references/theme.md` - テーマトークンシステムとデフォルトテーマ定義
- `references/navigation.md` - スライドナビゲーションのJS実装
- `references/visual-guidelines.md` - ビジュアル提案ルール（アイコン、画像、装飾の判断基準）
- `references/quality-checklist.md` - 品質レビューのチェックリスト
