# テーマトークンシステム

## CSS変数によるテーマ管理

全スライドのスタイルはCSS変数（テーマトークン）で制御する。ユーザーがテーマを指定した場合はその値を使用し、指定がない場合はデフォルト（白黒ベース）を適用する。

## デフォルトテーマ（白黒ベース）

```css
:root {
  /* カラー */
  --color-primary: #111827;    /* gray-900 - 主要テキスト、強調背景 */
  --color-secondary: #6B7280;  /* gray-500 - 補助要素 */
  --color-accent: #3B82F6;     /* blue-500 - アクセントカラー（見出し、ボタン、強調） */
  --color-bg: #FFFFFF;         /* 白 - メイン背景 */
  --color-bg-alt: #F9FAFB;     /* gray-50 - 代替背景（カード、セクション） */
  --color-text: #111827;       /* gray-900 - メインテキスト */
  --color-text-muted: #6B7280; /* gray-500 - 補足テキスト */
  --color-border: #E5E7EB;     /* gray-200 - ボーダー、区切り線 */

  /* タイポグラフィ */
  --font-heading: 'Noto Sans JP', system-ui, sans-serif;
  --font-body: 'Noto Sans JP', system-ui, sans-serif;

  /* スペーシング */
  --spacing-slide-padding: 5rem;  /* 80px - スライド内側のパディング */
  --spacing-gap-lg: 3rem;         /* 48px - 大きな要素間 */
  --spacing-gap-md: 1.5rem;       /* 24px - 中程度の要素間 */
  --spacing-gap-sm: 0.75rem;      /* 12px - 小さな要素間 */

  /* ボーダー */
  --radius-sm: 0.5rem;    /* 8px */
  --radius-md: 1rem;      /* 16px */
  --radius-lg: 1.5rem;    /* 24px */
  --radius-full: 9999px;  /* 完全な丸 */
}
```

## テーマの適用方法

### HTMLへの組み込み

```html
<style>
  :root {
    --color-primary: #111827;
    --color-secondary: #6B7280;
    --color-accent: #3B82F6;
    --color-bg: #FFFFFF;
    --color-bg-alt: #F9FAFB;
    --color-text: #111827;
    --color-text-muted: #6B7280;
    --color-border: #E5E7EB;
    --font-heading: 'Noto Sans JP', system-ui, sans-serif;
    --font-body: 'Noto Sans JP', system-ui, sans-serif;
    --spacing-slide-padding: 5rem;
    --radius-sm: 0.5rem;
    --radius-md: 1rem;
    --radius-lg: 1.5rem;
    --radius-full: 9999px;
  }

  * {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
  }

  body {
    font-family: var(--font-body);
    background: #000;
    overflow: hidden;
  }

  .slide {
    width: 1920px;
    height: 1080px;
    position: absolute;
    top: 50%;
    left: 50%;
    transform-origin: center center;
    overflow: hidden;
    display: none;
  }

  .slide.active {
    display: block;
  }

  /* 印刷用スタイル */
  @media print {
    body {
      background: white;
      overflow: visible;
    }

    .slide {
      position: relative;
      top: auto;
      left: auto;
      transform: none !important;
      display: block !important;
      break-after: page;
      page-break-after: always;
    }

    #slide-nav,
    #slide-progress {
      display: none !important;
    }

    @page {
      size: 1920px 1080px landscape;
      margin: 0;
    }
  }
</style>
```

## カスタムテーマの例

ユーザーがテーマを指定した場合、`:root` のCSS変数を上書きする。

### 例: 紫グラデーションテーマ（LayerX風）

```css
:root {
  --color-primary: #7C3AED;    /* violet-600 */
  --color-secondary: #A78BFA;  /* violet-400 */
  --color-accent: #7C3AED;     /* violet-600 */
  --color-bg: #FFFFFF;
  --color-bg-alt: #F5F3FF;     /* violet-50 */
  --color-text: #1E1B4B;       /* indigo-950 */
  --color-text-muted: #6D28D9; /* violet-700 の薄い版 */
  --color-border: #DDD6FE;     /* violet-200 */
}
```

section-dividerやcoverスライドで使うグラデーション背景：
```css
.slide[data-variant="section-divider"] > div,
.slide[data-variant="cover"] > div {
  background: linear-gradient(135deg, #7C3AED, #EC4899) !important;
}
```

### 例: ダークテーマ

```css
:root {
  --color-primary: #F9FAFB;
  --color-secondary: #9CA3AF;
  --color-accent: #60A5FA;
  --color-bg: #111827;
  --color-bg-alt: #1F2937;
  --color-text: #F9FAFB;
  --color-text-muted: #9CA3AF;
  --color-border: #374151;
}
```

## テーマ指定時の注意事項

1. **コントラスト比を確認する**: テキストと背景のコントラスト比がWCAG AA基準（4.5:1以上）を満たすこと
2. **アクセントカラーは1色に絞る**: 複数のアクセントカラーを使うと統一感が崩れる
3. **section-dividerの背景**: グラデーションや濃い色を使う場合、テキストは白に切り替える
4. **フォント変更時**: Google Fontsの `<link>` タグも合わせて変更すること
5. **画像の背景色**: team-membersの丸写真背景などもテーマカラーに合わせる
