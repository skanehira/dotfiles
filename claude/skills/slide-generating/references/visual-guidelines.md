# ビジュアルガイドライン

## 原則

- **テキストのみのスライドが3枚以上連続してはならない**
- 各スライドに最低1つのビジュアル要素（画像、アイコン、図、装飾）を検討する
- 「文字で説明できる」と「視覚的に伝わる」は別。後者を優先する

## スライドタイプ別ビジュアル判断基準

### 必ずビジュアルを入れるべきスライド

| 状況 | 推奨ビジュアル |
|------|---------------|
| プロダクト・サービス紹介 | スクリーンショット、デバイスモックアップ |
| 人物紹介・チーム紹介 | 顔写真（丸切り抜き） |
| Before/After・比較 | 左右にアイコンまたは図解 |
| 数字・KPI | big-number variant + 補助的なチャートやアイコン |
| プロセス・フロー | sequence variant のステップにアイコン |
| デモ・実演 | 画面スクリーンショット or 操作画面 |
| 会社紹介 | オフィス写真、ロゴ |

### テキストのみで良いスライド

| 状況 | 理由 |
|------|------|
| 目次・アジェンダ | 構造自体がビジュアル（番号 + 見出し） |
| 引用・キーメッセージ | テキストの「大きさ」がビジュアル要素 |
| Q&A | Q/Aのアイコンレターが視覚的アクセント |

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

| 概念 | SVG or 表現 |
|------|------------|
| スピード・速い | 矢印 → / ロケット |
| 遅い・問題 | 時計 / ×マーク |
| 人物 | 円形ヘッド + 肩 |
| チーム | 複数人物 |
| 設定・カスタマイズ | ギアアイコン |
| コード・技術 | `</>` テキスト or ターミナル |
| ドキュメント | 紙アイコン |
| チャット・対話 | 吹き出し |
| チェック・完了 | チェックマーク ✓ |
| 成長・向上 | 右肩上がり矢印 |
| セキュリティ | 盾 |
| お金・コスト | 円マーク ¥ |
| 検索 | 虫眼鏡 |
| 学習・教育 | 本 / 帽子 |
| サポート | ヘッドセット / ライフブイ |

アイコンはstroke-based（線画）スタイルで統一する。fill-basedと混在させない。

## 装飾要素

### グラデーション背景（cover / section-divider用）

テーマトークンの `--color-primary` と `--color-accent` を使用：

```css
background: linear-gradient(135deg, var(--color-primary), var(--color-accent));
```

白黒テーマの場合は控えめに：
```css
background: linear-gradient(135deg, #111827, #1F2937);
```

### 装飾SVG（背景に配置する有機的な曲線）

大きな半透明のSVG形状をスライド右側に配置して視覚的な奥行きを出す：

```html
<div class="absolute top-0 right-0 w-[600px] h-full opacity-5 pointer-events-none">
  <svg viewBox="0 0 600 1080" fill="none">
    <circle cx="400" cy="300" r="300" fill="var(--color-accent)" />
    <circle cx="500" cy="700" r="200" fill="var(--color-primary)" />
  </svg>
</div>
```

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

## 構成提案時のチェックリスト

構成を提案する前に以下を確認：

- [ ] テキストのみスライドが3枚以上連続していないか
- [ ] プロダクト紹介スライドにスクショ/モックアップがあるか
- [ ] 比較スライドにアイコンまたは図解があるか
- [ ] 箇条書き3項目以上のスライドにアイコンが付いているか
- [ ] cover / section-divider にグラデーションまたは装飾があるか
- [ ] 必要な画像素材をユーザーに明示しているか
