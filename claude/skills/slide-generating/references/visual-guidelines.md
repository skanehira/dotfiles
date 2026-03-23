# ビジュアルガイドライン

## 原則

- **テキストのみのスライドが3枚以上連続してはならない**
- 各スライドに最低1つのビジュアル要素（画像、アイコン、図、装飾）を検討する
- 「文字で説明できる」と「視覚的に伝わる」は別。後者を優先する

## Spatial Style（空間スタイル）

レイアウト構造（family）とは別に、スライド全体の空間的な表現を決定する。Spatial Style は Step 1.5 のデザイン方向性から導出し、デッキ全体に一貫して適用する。

### 5つのプロパティ

| プロパティ | 選択肢                                      | 説明                       |
| ---------- | ------------------------------------------- | -------------------------- |
| **エッジ** | straight / angled / curved                  | 分割線・境界の形状         |
| **密度**   | dense / balanced / airy                     | 要素間の余白の取り方       |
| **角丸**   | sharp (0) / soft (8-12px) / round (16-24px) | カード・ボックスの角の処理 |
| **奥行き** | flat / layered / floating                   | 影・重なり・立体感の程度   |
| **装飾**   | geometric / organic / minimal / textured    | 装飾要素の方向性           |

### トーンから Spatial Style への導出例

| トーン                 | エッジ   | 密度     | 角丸  | 奥行き   | 装飾      |
| ---------------------- | -------- | -------- | ----- | -------- | --------- |
| 尖ったテック感         | angled   | dense    | sharp | layered  | geometric |
| 温かみのある信頼感     | curved   | airy     | round | flat     | organic   |
| 重厚な格調             | straight | balanced | soft  | layered  | minimal   |
| 遊び心のあるカジュアル | curved   | balanced | round | floating | organic   |
| 洗練された緊張感       | straight | airy     | sharp | flat     | minimal   |

**これらは例示であり、そのままコピーしない。** トーンのニュアンスに合わせて各プロパティを個別に判断する。

### Spatial Style の適用方法

family のベースライン HTML テンプレート（`families.md`）に対して、spatial style のプロパティに応じた変形を適用する。

**エッジ処理の例:**

```css
/* straight（デフォルト） */
.divider { border-left: 2px solid var(--color-border); }

/* angled — clip-path で斜めカット */
.panel-left { clip-path: polygon(0 0, 100% 0, 85% 100%, 0 100%); }
.panel-right { clip-path: polygon(15% 0, 100% 0, 100% 100%, 0 100%); }

/* curved — border-radius で曲線分割 */
.panel { border-radius: 0 40px 40px 0; overflow: hidden; }
```

**奥行き処理の例:**

```css
/* flat */
.card { background: var(--color-bg-alt); }

/* layered */
.card { background: var(--color-bg-alt); box-shadow: 0 4px 24px rgba(0,0,0,0.08); }

/* floating */
.card {
  background: var(--color-bg-alt);
  box-shadow: 0 12px 40px rgba(0,0,0,0.12);
  transform: translateY(-4px);
}
```

**密度の調整:**

```css
/* dense */
:root { --spacing-slide-padding: 3rem; --spacing-gap-md: 1rem; }

/* balanced（標準） */
:root { --spacing-slide-padding: 5rem; --spacing-gap-md: 1.5rem; }

/* airy */
:root { --spacing-slide-padding: 7rem; --spacing-gap-md: 2.5rem; }
```

## スライドタイプ別ビジュアル判断基準

### 必ずビジュアルを入れるべきスライド

| 状況                     | semantic_pattern | 推奨ビジュアル                                  |
| ------------------------ | ---------------- | ----------------------------------------------- |
| プロダクト・サービス紹介 | evidence         | スクリーンショット、デバイスモックアップ        |
| 人物紹介・チーム紹介     | page-role        | 顔写真（丸切り抜き）                            |
| Before/After・比較       | compare          | 左右にアイコンまたは図解                        |
| 数字・KPI                | data-viz         | big-number variant + 補助的なチャートやアイコン |
| プロセス・フロー         | process          | sequence variant のステップにアイコン           |
| デモ・実演               | evidence         | 画面スクリーンショット or 操作画面              |
| 会社紹介                 | page-role        | オフィス写真、ロゴ                              |
| 循環関係                 | cycle            | diagram.cycle でノード接続                      |
| 階層・分類               | hierarchy        | diagram.pyramid / tree / org-chart              |
| 要素の重なり             | relationship     | diagram.venn                                    |
| 4象限分析                | compare          | diagram.matrix                                  |

### テキストのみで良いスライド

| 状況                 | semantic_pattern | 理由                                  |
| -------------------- | ---------------- | ------------------------------------- |
| 目次・アジェンダ     | page-role        | 構造自体がビジュアル（番号 + 見出し） |
| 引用・キーメッセージ | page-role        | テキストの「大きさ」がビジュアル要素  |
| Q&A                  | page-role        | Q/Aのアイコンレターが視覚的アクセント |

### アイコンで補強すべきスライド

テキスト箇条書きが3項目以上ある場合、各項目にアイコンを付ける。

## SVGアイコンの生成

画像素材がない場合、SVGインラインアイコンで代替する。以下のパターンを使用：

```html
<!-- シンプルな丸アイコン + テキスト -->
<div class="w-14 h-14 rounded-xl flex items-center justify-center text-2xl"
     style="background: var(--color-accent); color: white">
  <!-- 絵文字 or SVGアイコン -->
  <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
    <!-- パスデータ -->
  </svg>
</div>
```

### よく使うアイコンパターン

| 概念               | SVG or 表現                  |
| ------------------ | ---------------------------- |
| スピード・速い     | 矢印 → / ロケット            |
| 遅い・問題         | 時計 / ×マーク               |
| 人物               | 円形ヘッド + 肩              |
| チーム             | 複数人物                     |
| 設定・カスタマイズ | ギアアイコン                 |
| コード・技術       | `</>` テキスト or ターミナル |
| ドキュメント       | 紙アイコン                   |
| チャット・対話     | 吹き出し                     |
| チェック・完了     | チェックマーク ✓             |
| 成長・向上         | 右肩上がり矢印               |
| セキュリティ       | 盾                           |
| お金・コスト       | 円マーク ¥                   |
| 検索               | 虫眼鏡                       |
| 学習・教育         | 本 / 帽子                    |
| サポート           | ヘッドセット / ライフブイ    |

アイコンはstroke-based（線画）スタイルで統一する。fill-basedと混在させない。

## 装飾要素

Spatial Style の「装飾」プロパティに応じて、適切な装飾パターンを選択する。**同じ装飾パターンを毎回使わないこと。**

### geometric（幾何学）

直線、三角形、六角形などの幾何学的な形状：

```html
<!-- 斜線ストライプ -->
<div class="absolute inset-0 opacity-[0.03] pointer-events-none"
     style="background: repeating-linear-gradient(45deg, var(--color-accent), var(--color-accent) 1px, transparent 1px, transparent 40px)">
</div>

<!-- ドットグリッド -->
<div class="absolute inset-0 opacity-[0.05] pointer-events-none"
     style="background: radial-gradient(circle, var(--color-accent) 1px, transparent 1px); background-size: 30px 30px">
</div>

<!-- 三角形アクセント -->
<div class="absolute top-0 right-0 opacity-10 pointer-events-none">
  <svg width="400" height="400" viewBox="0 0 400 400" fill="none">
    <polygon points="400,0 400,400 0,0" fill="var(--color-accent)" />
  </svg>
</div>
```

### organic（有機的）

曲線、波形、ブロブなどの自然な形状：

```html
<!-- 波形ボーダー -->
<div class="absolute bottom-0 left-0 w-full opacity-10 pointer-events-none">
  <svg viewBox="0 0 1920 200" fill="none" preserveAspectRatio="none" class="w-full h-[200px]">
    <path d="M0,100 C320,20 640,180 960,100 C1280,20 1600,180 1920,100 L1920,200 L0,200 Z" fill="var(--color-accent)" />
  </svg>
</div>

<!-- ブロブ形状 -->
<div class="absolute -top-20 -right-20 opacity-[0.06] pointer-events-none">
  <svg width="500" height="500" viewBox="0 0 500 500" fill="none">
    <path d="M250,50 C350,20 450,100 430,200 C460,300 380,420 280,440 C180,460 60,380 50,280 C40,180 150,80 250,50Z" fill="var(--color-accent)" />
  </svg>
</div>
```

### minimal（最小限）

装飾を極力排し、線や余白で空間を構成：

```html
<!-- 単一の縦線アクセント -->
<div class="absolute top-20 left-16 w-[3px] h-[200px]"
     style="background: var(--color-accent); opacity: 0.3">
</div>

<!-- 水平区切り線 -->
<div class="w-24 h-[2px] mt-4 mb-8" style="background: var(--color-accent)"></div>
```

### textured（テクスチャ）

ノイズ、グレイン、紙の質感などの表面的なテクスチャ：

```html
<!-- ノイズオーバーレイ（CSS filter） -->
<div class="absolute inset-0 opacity-[0.03] pointer-events-none mix-blend-multiply"
     style="background: url('data:image/svg+xml,%3Csvg viewBox=%220 0 256 256%22 xmlns=%22http://www.w3.org/2000/svg%22%3E%3Cfilter id=%22n%22%3E%3CfeTurbulence type=%22fractalNoise%22 baseFrequency=%220.9%22 numOctaves=%224%22 stitchTiles=%22stitch%22/%3E%3C/filter%3E%3Crect width=%22256%22 height=%22256%22 filter=%22url(%23n)%22 opacity=%220.5%22/%3E%3C/svg%3E'); background-size: 256px 256px">
</div>
```

### グラデーション背景（cover / section-divider用）

テーマトークンの `--color-primary` と `--color-accent` を使用。角度やカラーストップはトーンに合わせて変える：

```css
/* 斜めグラデーション */
background: linear-gradient(135deg, var(--color-primary), var(--color-accent));

/* ラジアルグラデーション */
background: radial-gradient(ellipse at 30% 50%, var(--color-accent), var(--color-primary));

/* 多段グラデーション */
background: linear-gradient(160deg, var(--color-primary) 0%, var(--color-secondary) 50%, var(--color-accent) 100%);
```

### Diagram Family のビジュアル適用ルール

diagram family（flow, org-chart, cycle, matrix, venn, pyramid, tree）は構造的な図であるため、装飾の適用に注意が必要。

**Spatial Style 適用:**
- **エッジ**: diagram のノード形状に適用。sharp → 角張ったノード、round → 丸いノード
- **奥行き**: flat → ノードに影なし、layered → ノードに `box-shadow` 追加、floating → ノードに大きな影 + `translateY`
- **装飾**: diagram スライドでは**背景装飾を控えめにする**（opacity を通常の半分以下）。図自体がビジュアル要素なので装飾過多を避ける
- **密度**: ノード間の gap と padding に反映。dense → コンパクト、airy → 余白大

**グラデーション背景:**
- diagram family は原則**白背景（--color-bg）**で使用する
- cover/section-divider 以外でグラデーション背景を使わない（図の視認性が下がるため）
- ノードの塗り色には `--color-accent` と `--color-bg-alt` を使い分ける

## 画像プレースホルダーの使い方

ユーザーが実画像を持っていない場合、placehold.jp でサイズと用途を明示する：

```html
<!-- スクリーンショット用 -->
<img src="https://placehold.jp/30/e2e8f0/64748b/800x500.png?text=Demo+Screenshot"
     alt="デモ画面" class="rounded-xl shadow-lg" />

<!-- 人物写真用 -->
<img src="https://placehold.jp/30/e2e8f0/64748b/200x200.png?text=Photo"
     alt="メンバー名" class="w-48 h-48 rounded-full object-cover" />

<!-- ロゴ用 -->
<img src="https://placehold.jp/30/e2e8f0/64748b/200x60.png?text=Logo"
     alt="ロゴ" class="h-12" />
```

placehold.jpパラメータ:
- `/30/背景色/文字色/幅x高さ.png?text=テキスト`
- 背景色は `e2e8f0`（gray-200相当）を標準で使用
- テキストにはプレースホルダーの用途を明記する

### 装飾選択マトリクス

Spatial Style の装飾プロパティと family の組み合わせで推奨される装飾パターン:

| family               | geometric                | organic      | minimal      | textured           |
| -------------------- | ------------------------ | ------------ | ------------ | ------------------ |
| hero (cover/divider) | 三角形アクセント         | 波形+ブロブ  | 縦線+水平線  | ノイズオーバーレイ |
| split                | 斜線ストライプ（分割側） | 曲線分割線   | 単一縦線     | —                  |
| grid                 | ドットグリッド（背景）   | ブロブ（角） | —            | ノイズ（カード内） |
| sequence             | 矢印+直線コネクタ        | 曲線コネクタ | 直線のみ     | —                  |
| table                | ヘッダー幾何学パターン   | —            | 罫線のみ     | —                  |
| diagram              | —                        | —            | —            | —                  |
| single-column        | ドットグリッド           | ブロブ（隅） | アクセント線 | ノイズ             |

**diagram family は装飾を追加しない**（図自体がビジュアル要素のため）。
**「—」は該当パターンを推奨しない**ことを示す。

## 収束禁止ルール

- **フォント**: 毎回異なるフォントペアを選択する。Noto Sans JP + Inter/Lato のような「安全な組み合わせ」に収束しない
- **カラー**: 毎回異なるパレットを設計する。gray + blue-500 をデフォルトにしない
- **装飾**: 同じ装飾パターンを繰り返し使わない。geometric → organic → textured と変化をつける
- **Spatial Style**: 同じプロパティの組み合わせに収束しない
- **グラデーション角度**: 毎回 135deg にしない。角度、種類（linear/radial/conic）を変える

**判断基準**: 「前回と同じでよいか？」と自問し、答えが Yes なら意図的に別の選択をする。

## 構成提案時のチェックリスト

構成を提案する前に以下を確認：

- [ ] テキストのみスライドが3枚以上連続していないか
- [ ] プロダクト紹介スライドにスクショ/モックアップがあるか
- [ ] 比較スライドにアイコンまたは図解があるか
- [ ] 箇条書き3項目以上のスライドにアイコンが付いているか
- [ ] cover / section-divider にグラデーションまたは装飾があるか
- [ ] 必要な画像素材をユーザーに明示しているか
- [ ] Spatial Style が全スライドに一貫して適用されているか
