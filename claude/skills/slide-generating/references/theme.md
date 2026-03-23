# テーマトークンシステム

## CSS変数によるテーマ管理

全スライドのスタイルはCSS変数（テーマトークン）で制御する。テーマは Step 1.5 で決定したデザイン方向性（トーン）から導出する。固定のデフォルトテーマは存在しない。

## Anti-AI-Slop ルール（全体要約）

以下はテーマ設計全体を通じた禁止事項。詳細は各セクション参照。

- **カラー**: `#3B82F6`(blue-500) / gray+blue / 紫グラデーション on 白 禁止
- **JPフォント**: Noto Sans JP をデフォルト自動選択禁止
- **ラテンフォント**: Inter / Roboto / Arial / Lato をデフォルト禁止
- **収束禁止**: 前回の生成と同じフォント・パレットの組み合わせ禁止

## カラーパレットの設計

トーンから3〜4色のパレットを導出する。以下の役割を定義すること：

| トークン             | 役割                   | 導出の考え方                                                         |
| -------------------- | ---------------------- | -------------------------------------------------------------------- |
| `--color-primary`    | 主要テキスト、強調背景 | トーンの「重さ」を表す色。格調なら深い紺、カジュアルなら柔らかい墨色 |
| `--color-secondary`  | 補助要素               | primary の明度違い or 色相をずらした色                               |
| `--color-accent`     | 見出し、ボタン、強調   | トーンの「個性」を表す色。差別化の核。パレット内で最も目立つ色       |
| `--color-bg`         | メイン背景             | 白、オフホワイト、淡色、または暗色（ダークテーマ）                   |
| `--color-bg-alt`     | 代替背景（カード等）   | bg と微差のある色                                                    |
| `--color-text`       | メインテキスト         | bg に対してコントラスト比 4.5:1 以上                                 |
| `--color-text-muted` | 補足テキスト           | text の薄い版                                                        |
| `--color-border`     | ボーダー、区切り線     | bg-alt に近い控えめな色                                              |

**禁止事項:**
- `#3B82F6`（Tailwind blue-500）をアクセントにしない
- gray + blue の組み合わせをデフォルトにしない
- 紫グラデーション on 白背景を使わない
- 前回の生成と同じパレットを使わない

### パレット導出のステップ

1. **bg を決める**: トーンが明るい → 白〜オフホワイト（#faf9f7〜#fff8f0）、暗い → ダーク（#0f0f1a〜#1c1917）
2. **primary を決める**: bg と最も対照的な色。bg が明るければ深い暗色、bg が暗ければ明るいテキスト色
3. **accent を決める**: トーンの「個性」を最も表す色。禁止色（blue-500, 紫）を避け、トーンのキーワードから連想される色相を選ぶ
   - 知的 → 深いグリーン、ティール
   - 温かい → コーラル、テラコッタ、アンバー
   - 格調 → ゴールド、バーガンディ
   - テック → シアン、ネオングリーン
   - カジュアル → オレンジ、イエロー
4. **secondary を決める**: primary と accent の中間的な色、または accent の彩度を落とした色
5. **bg-alt, text-muted, border を導出**: bg から微調整して派生させる
6. **コントラスト検証**: text と bg のコントラスト比が WCAG AA（4.5:1）以上であることを確認

## フォント選択

トーンに合ったフォントペアを選択する。**毎回異なるフォントペアを選ぶこと。**

### トーン別フォント選択ガイド

トーンのキーワードからフォントペアを選ぶ際の判断基準:

| トーンの方向性   | JP フォント     | ラテンフォント | 根拠                                     |
| ---------------- | --------------- | -------------- | ---------------------------------------- |
| 知的・シャープ   | Murecho         | Sora           | 幾何学的な造形が知的印象を与える         |
| 温かい・柔らかい | Zen Maru Gothic | Fraunces       | 丸みのある字形が親しみと温かさを伝える   |
| 格調・高級       | Shippori Mincho | Crimson Pro    | 明朝体+セリフの組み合わせが格式を表現    |
| 大胆・インパクト | Dela Gothic One | Unbounded      | 極太+丸みの太字が強い存在感を出す        |
| クリーン・実務的 | M PLUS 1p       | DM Sans        | ニュートラルで高可読性、ビジネス文書向き |

**判断のステップ:**
1. トーンから「形状の方向性」を判断（幾何学的 / 丸い / 伝統的 / 極太 / ニュートラル）
2. 形状に合う JP フォントを候補リストから選択
3. JP フォントと視覚的に調和するラテンフォントをペアリング
4. heading と body で異なるフォントを使う場合は、同系統の異ウェイトでコントラストをつける

### 日本語フォント候補（Google Fonts）

| フォント            | 特徴                     | 合うトーン           |
| ------------------- | ------------------------ | -------------------- |
| Zen Kaku Gothic New | 現代的で柔らかいゴシック | カジュアル、親しみ   |
| Zen Maru Gothic     | 丸みのあるゴシック       | 温かみ、安心感       |
| M PLUS 1p           | クリーンで読みやすい     | テック、モダン       |
| M PLUS Rounded 1c   | 丸ゴシック、親しみやすい | 教育、ワークショップ |
| Shippori Mincho     | 上品な明朝体             | 格調、高級感、重厚   |
| Klee One            | 手書き感のある教科書体   | 温かみ、ナチュラル   |
| Murecho             | 幾何学的でシャープ       | テック、先進的       |
| Dela Gothic One     | 極太で力強い             | インパクト、大胆     |
| Zen Old Mincho      | 古典的な明朝体           | 伝統、格式           |
| BIZ UDGothic        | ビジネス向け高可読性     | ビジネス、実務的     |
| Noto Sans JP        | ニュートラル             | 中立的な場面のみ     |
| Kosugi Maru         | 小杉丸ゴシック           | 柔らかい、カジュアル |
| Sawarabi Gothic     | 清潔感のあるゴシック     | 清潔、シンプル       |
| Kaisei Decol        | 装飾的な明朝             | 華やか、個性的       |

**禁止事項:**
- Noto Sans JP をデフォルトとして自動選択しない（意図的に選ぶ場合のみ可）
- heading と body に同じフォントを使う場合は、ウェイトで明確に差をつける
- 前回の生成と同じフォントペアを使わない

### ラテンフォント候補（Google Fonts）

| フォント            | 特徴               | 合うトーン           |
| ------------------- | ------------------ | -------------------- |
| Space Mono          | 等幅、テック感     | テック、コーディング |
| DM Sans             | 幾何学的でモダン   | クリーン、モダン     |
| Outfit              | 柔らかい幾何学     | フレンドリー、モダン |
| Sora                | 未来的、幾何学的   | 先進的、テック       |
| Manrope             | 読みやすいモダン   | ビジネス、プロ       |
| Bricolage Grotesque | 個性的なグロテスク | 大胆、クリエイティブ |
| Plus Jakarta Sans   | 洗練されたモダン   | ビジネス、上品       |
| Crimson Pro         | エレガントなセリフ | 格調、高級           |
| Playfair Display    | クラシカルなセリフ | 高級、エディトリアル |
| Fraunces            | 柔らかいセリフ     | 温かみ、個性的       |
| IBM Plex Sans       | 技術的で信頼感     | テック、企業         |
| Unbounded           | 丸みのある太字     | 遊び心、インパクト   |

**禁止事項:**
- Inter, Roboto, Arial をプライマリに使わない
- Lato をデフォルトとして自動選択しない

## HTMLへの組み込み

```css
:root {
  /* カラー — Step 1.5 で導出した値を入れる */
  --color-primary: ;
  --color-secondary: ;
  --color-accent: ;
  --color-bg: ;
  --color-bg-alt: ;
  --color-text: ;
  --color-text-muted: ;
  --color-border: ;

  /* タイポグラフィ — Step 1.5 で選択したフォント */
  --font-heading: , sans-serif;
  --font-body: , sans-serif;

  /* スペーシング — spatial style の密度に応じて調整 */
  --spacing-slide-padding: 5rem;
  --spacing-gap-lg: 3rem;
  --spacing-gap-md: 1.5rem;
  --spacing-gap-sm: 0.75rem;

  /* ボーダー — spatial style の角丸に応じて調整 */
  --radius-sm: 0.5rem;
  --radius-md: 1rem;
  --radius-lg: 1.5rem;
  --radius-full: 9999px;
}
```

基本的なスライド・印刷スタイル:

```css
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

html, body {
  width: 100vw;
  height: 100vh;
  overflow: hidden;
}

body {
  font-family: var(--font-body);
  background: #000;
}

/* slide-container はスライドの位置計算の基準となる。
   明示的にビューポートサイズを指定しないと、
   1920px幅のスライドがドキュメントを広げ、
   left: 50% の基準がずれてスライドが左に偏る。 */
#slide-container {
  position: relative;
  width: 100vw;
  height: 100vh;
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
```

## テーマの例

以下はトーンから導出した例。**そのままコピーしないこと。** 方向性を理解するための参考として使う。

### 例: トーン「重厚な格調」

```css
:root {
  --color-primary: #1a1a2e;
  --color-secondary: #4a4a6a;
  --color-accent: #c4975a;
  --color-bg: #faf8f5;
  --color-bg-alt: #f0ece4;
  --color-text: #1a1a2e;
  --color-text-muted: #6b6b80;
  --color-border: #e0dcd4;
  --font-heading: 'Shippori Mincho', serif;
  --font-body: 'Zen Kaku Gothic New', sans-serif;
}
```

### 例: トーン「尖ったテック感」

```css
:root {
  --color-primary: #0a0a0f;
  --color-secondary: #2a2a3a;
  --color-accent: #00e5a0;
  --color-bg: #0f0f1a;
  --color-bg-alt: #1a1a2a;
  --color-text: #e0e0e8;
  --color-text-muted: #8888a0;
  --color-border: #2a2a3a;
  --font-heading: 'Murecho', sans-serif;
  --font-body: 'M PLUS 1p', sans-serif;
}
```

## テーマ適用時の注意事項

1. **コントラスト比を確認する**: テキストと背景のコントラスト比がWCAG AA基準（4.5:1以上）を満たすこと
2. **アクセントカラーは1色に絞る**: 複数のアクセントカラーを使うと統一感が崩れる
3. **section-dividerの背景**: グラデーションや濃い色を使う場合、テキストは白に切り替える
4. **フォント変更時**: Google Fontsの `<link>` タグも合わせて変更すること
5. **画像の背景色**: team-membersの丸写真背景などもテーマカラーに合わせる
