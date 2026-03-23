---
name: slide-generating
description: テキスト入力からWebベースのプレゼンテーションスライド（HTML + Tailwind CSS + JS）を生成する。カンファレンス登壇やセールス資料として使えるレベルの品質を目指す。「スライドを作って」「プレゼン資料を作成」「デッキを生成」「/slide-generator」、既存のスライドHTMLの修正依頼で起動する。
metadata:
  short-description: Webスライド生成
---

# Slide Generator

テキスト入力から高品質なWebベースのプレゼンテーションスライドを生成するスキル。

## 出力仕様

- **形式**: 単一HTMLファイル（Tailwind CDN + テンプレート関数によるJS動的生成）
- **サイズ**: 各スライド 1920px x 1080px（16:9）
- **画像**: プレースホルダーは `https://placehold.jp/` を使用。実画像は `assets/` ディレクトリに配置
- **フォント**: Google Fonts CDN（デザイン方向性に基づいて選択。候補は `references/theme.md` 参照）
- **テーマ**: CSS変数によるテーマトークン管理。デザイン方向性（Step 1.5）から導出

## ワークフロー

### Step 1: 入力受付

ユーザーから以下のいずれかの形式で入力を受け取る：

**A. 自由テキスト**（例: 「自社紹介資料を作って。会社名はXXで、事業内容は...」）
- AIが内容を解析し、スライド構成を自動提案する

**B. 構造化テキスト**（例: markdownアウトライン形式）
- ユーザーが指定した構成に従ってスライドを生成する

入力受付時に以下も確認する：
- 画像素材の有無（assets/ディレクトリにあるか）
- スライド枚数の目安

### Step 1.5: デザイン方向性

コンテンツの内容を把握したら、ビジュアルの方向性を確定する。以下を**自由記述**でヒアリングする（選択肢は提示しない）。

1. **トーン**: このプレゼンの「空気感」を一言で
   - 例を求められた場合のみ提示: 洗練された緊張感、温かみのある信頼感、尖ったテック感、重厚な格調、遊び心のあるカジュアルさ
2. **差別化**: このスライドを見た人が一番覚えていることは何か
3. **参照イメージ**（任意）: 好きなブランド、Webサイト、雑誌のテイスト

ヒアリング結果から以下を導出する:
- **フォントペア**: トーンに合った日本語 + ラテンフォントを選択（`references/theme.md` の候補リスト参照）
- **カラーパレット**: トーンから固有のパレットを設計（`references/theme.md` の導出ルール参照）
- **Spatial Style**: トーンに合った空間表現を決定（`references/visual-guidelines.md` 参照）

**Step 1.5 の出力（後続ステップへの入力）:**
- フォントペア（JP + ラテン）
- カラーパレット（8つの CSS 変数値）
- Spatial Style（エッジ/密度/角丸/奥行き/装飾の5プロパティ）
- deck_profile（business-pitch / conference-talk / internal-study）

これらは Step 1.75 での family/variant 選択と、Step 3 での HTML 生成に直接使用される。

導出結果をユーザーに提示し、承認を得てから Step 2 に進む。

**収束禁止**: 前回の生成と同じフォント・カラー・Spatial Style の組み合わせを使わないこと。毎回異なるデザインを生成する。ユーザーが過去のスライドを共有した場合はそれを参照して異なる方向を提案する。初回生成時は theme.md のテーマ例と異なるパレットを選ぶこと。

### Step 1.75: Semantic Diagnosis

構成を提案する前に、各スライドのコンテンツを分析し、最適なレイアウトを意味的関係から導出する。`references/semantic-patterns.md` を参照すること。

**各スライドについて以下の順序で判定する:**

1. **message_role を確定**: cover / section / explain / proof / close
2. **semantic_pattern を判定**: message_role が page-role（cover/section/close）なら hero.* を使用。それ以外は以下のフローで判定:
   - 数値データを見せたい → **data-viz**
   - スクリーンショット/事例/ロゴで裏付け → **evidence**
   - 要素間に関係がない（同格の羅列）→ **parallel**
   - 対比・違いを見せる → **compare**
   - 順序・手順を見せる → **process**
   - 循環する関係 → **cycle**
   - 上下・分解・段階 → **hierarchy**
   - 重なり・包含・相互作用 → **relationship**
3. **entity_count を数える**: 並べる要素の数（1 / 2 / 3 / 4+）
4. **evidence_type を特定**: text / metric / chart / screenshot / logo / icon

**判定結果から family/variant を決定する。** `semantic-patterns.md` の選択フローと entity_count 調整表に従うこと。

**deck_profile による重み付け:**

Step 1 のヒアリングで用途が判明している場合、deck_profile（`business-pitch` / `conference-talk` / `internal-study`）に応じて推奨パターンの優先度を調整する。詳細は `semantic-patterns.md` の Deck Profile セクション参照。

**Spatial Style の適用:**

family/variant 確定後、Step 1.5 で決定した Spatial Style に応じてベースラインテンプレートを変形する。変形ルールは `references/families.md` の「ベースラインテンプレートと Spatial Style」セクション、および `references/visual-guidelines.md` の「Spatial Style の適用方法」セクション参照。

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

1. `references/families.md` のテンプレート関数とvariantパターンに従うこと
2. `references/theme.md` のテーマトークンシステム（「HTMLへの組み込み」セクション）を適用すること
3. `references/navigation.md` のナビゲーションJSを組み込むこと
4. 全スライドを1つのHTMLファイルに含めること
5. テンプレート関数（`S()`, `D()`, `SFlex()`, `H()`, `Sub()`, `VC()` 等）を定義し、スライドを動的に生成すること
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
  <!-- Step 1.5 で選択したフォントの Google Fonts リンクをここに挿入 -->
  <style>
    /* テーマトークン（references/theme.md 参照） */
    :root { ... }
    /* スライド基本スタイル */
    /* 印刷用スタイル */
  </style>
</head>
<body>
  <div id="slide-container"></div>

  <!-- ナビゲーションUI（references/navigation.md 参照） -->
  <div id="slide-nav">...</div>

  <script>
    /* テンプレート関数（references/families.md 参照） */
    const _C = '{会社名}';
    const _L = 'assets/logo.svg';
    function S(n, fam, v, content, o={}) { /* ... */ }
    function D(n, v, content, o={}) { /* ... */ }
    function SFlex(n, fam, v, content, o={}) { /* ... */ }
    function H(t) { /* ... */ }
    function Sub(t) { /* ... */ }
    function VC(c) { /* ... */ }
    function IC(svg) { /* ... */ }
    function Badge(t, o={}) { /* ... */ }
    function Arr() { /* ... */ }
    function Cap(label, src, alt, o={}) { /* ... */ }

    /* スライド生成 */
    document.getElementById('slide-container').innerHTML = [
      D(1, 'cover', `...`),
      D(2, 'section-divider', `...`),
      S(3, 'grid', 'cards', `${H('...')} ${Sub('...')} ${VC(`...`)}`, {sec: '...'}),
      SFlex(4, 'split', 'text-image', `...`, {sec: '...'}),
      // ...
    ].join('');
  </script>

  <script>
    /* ナビゲーションJS（references/navigation.md 参照） */
    /* ※ スライド生成後に実行されるよう、別の script ブロックに配置 */
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
3. サンプリング方式でスクリーンショットを撮影（優先度順）：
   - **優先1**: カバースライド（1枚目）、セクション区切り（1枚）
   - **優先2**: split 系（text-image or comparison）と grid.cards から各1枚
   - **優先3**: sequence.steps or timeline から1枚
   - **優先4**: diagram 系（使用した variant から1枚）
   - 合計 5〜8枚。未使用の family はスキップ
4. `references/quality-checklist.md` の基準に従ってレビュー
   - **構造レベル**（配置・余白・アラインメント）だけでなく、**コンテンツレベル**（画像の見切れ・テキストの途切れ・情報の欠落）まで検証すること
   - 特に画像を含むスライドでは、スクショと元画像を見比べて重要情報が切れていないか確認する
5. 問題があれば自動修正し、該当スライドのみ再スクショで確認

**スライド移動方法:**
- `mcp__chrome-devtools__evaluate_script` で `navigateToSlide(n)` を実行してスライドを移動
- 移動後に `mcp__chrome-devtools__take_screenshot` でスクリーンショットを撮影

### Step 5: PDF出力（ユーザーが要求した場合のみ）

Playwrightを使用してPDF出力する。`playwright-core`は共有キャッシュ（`~/.cache/slide-pdf/`）にインストールするため、プロジェクトの`node_modules`を汚染しない。

```bash
# 共有キャッシュにplaywright-coreをインストール（初回のみ）
SLIDE_PDF_CACHE="$HOME/.cache/slide-pdf"
if [ ! -d "$SLIDE_PDF_CACHE/node_modules/playwright-core" ]; then
  npm install --prefix "$SLIDE_PDF_CACHE" playwright-core
  npx --prefix "$SLIDE_PDF_CACHE" playwright-core install chromium
fi

# PDF生成
NODE_PATH="$SLIDE_PDF_CACHE/node_modules" node -e "
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
      printBackground: true
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
|                   | cycle              | 循環関係（PDCA、ビジネスサイクル）    |
|                   | matrix             | 2x2マトリクス（SWOT、ポジショニング）|
|                   | venn               | ベン図（重なり・共通領域）            |
|                   | pyramid            | ピラミッド/じょうろ（TAM-SAM-SOM）    |
|                   | tree               | ツリー図（分解・分類）                |

### Family選択の判断基準

- **1つのメッセージを大きく伝える** → hero
- **テキストを順番に伝える** → single-column
- **2つの要素を並べる** → split
- **3つ以上の要素を並べる** → grid
- **順序・流れを見せる** → sequence
- **構造化データを見せる** → table
- **関係性を見せる** → diagram
- **意味的関係からの選択** → `references/semantic-patterns.md` の選択フローも参照

## 参照ファイル

- `references/families.md` - family/variant別の具体的なHTMLテンプレートパターン
- `references/theme.md` - テーマトークンシステムとデフォルトテーマ定義
- `references/navigation.md` - スライドナビゲーションのJS実装
- `references/visual-guidelines.md` - ビジュアル提案ルール（アイコン、画像、装飾の判断基準）
- `references/semantic-patterns.md` - 意味パターン分類と family/variant マッピング
- `references/quality-checklist.md` - 品質レビューのチェックリスト
