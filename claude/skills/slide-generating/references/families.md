# Family/Variant HTMLテンプレートパターン

## コンテンツ生成の原則

- 1スライド1メッセージ。箇条書きは3〜5項目上限。テキスト過多なら分割
- 見出しは短く、インパクトのある表現にする
- 画像プレースホルダーには適切なサイズとalt属性を指定する

## 厳守ルール

- **カラーコードの直書き禁止**: すべての色は `var(--color-*)` を使う。`#3B82F6`, `text-blue-300` 等のハードコード禁止
- **白テキストは `text-white` のみ例外**: 暗い背景（cover, section-divider）上の白テキストのみ `text-white` を許可
- **Tailwindのカラーユーティリティ禁止**: `text-blue-500`, `bg-gray-100` 等は使わない。すべて `style="color: var(--color-*)"` で書く
- **Tailwindのスペーシングユーティリティ禁止**: `p-20`, `gap-12`, `mb-8` 等は使わない。すべて `style` 属性で `var(--spacing-*)` CSS変数を使う

## 垂直バランスルール

通常スライド（白背景）のコンテンツ領域は `display: flex; flex-direction: column` で構成される。各 variant の {CONTENT} は以下の構造に従うこと:

```html
<!-- 見出し部分（上部固定） -->
<h2>見出し</h2>
<p>サブテキスト</p>

<!-- メインコンテンツ（垂直中央配置） -->
<div style="margin-top: auto; margin-bottom: auto">
  <!-- カード群、テーブル、ステップ、ダイアグラム等 -->
</div>
```

**必須**: メインコンテンツ（見出し以外の主要部分）のラッパー要素に `margin-top: auto; margin-bottom: auto` を適用する。これにより見出し下〜フッター上の余白が均等になり、コンテンツが垂直中央に配置される。

**例外**: split.text-image のような全幅レイアウト、hero family（cover/section-divider/closing）は独自のレイアウトを持つためこのルールは適用しない。

## ベースラインテンプレートと Spatial Style

以下の各 family/variant の HTML は**ベースライン実装**である。構造（何をどこに配置するか）の参考として使い、視覚的な表現は `visual-guidelines.md` で定義された Spatial Style に応じて変形すること。

**変形の例:**

- **split（angled エッジ）**: `w-1/3 + w-2/3` の直線分割を `clip-path: polygon(...)` で斜めカットに変形
- **grid（floating 奥行き）**: カードに `box-shadow: 0 12px 40px rgba(0,0,0,0.12)` + `transform: translateY(-4px)` を追加
- **split（curved エッジ）**: 分割パネルに `border-radius: 0 40px 40px 0` を適用
- **grid（dense 密度）**: `gap` を縮小し、パディングを `3rem` に変更

ベースラインの CSS 値（比率、gap、padding 等）は固定ではない。Spatial Style と全体のトーンに合わせて調整すること。ただし、コンテンツの可読性は維持する（テキスト領域の最小幅 500px、フォントサイズは `quality-checklist.md` の階層に従う）。

## 共通パーツ

全variant共通の構造。各variantテンプレートでは **{CONTENT}** 部分のみ記載する。

### 通常スライド（白背景）

```html
<section class="slide" data-slide="{N}" data-family="{family}" data-variant="{variant}">
  <div class="w-[1920px] h-[1080px] relative overflow-hidden"
       style="background: var(--color-bg); padding: var(--spacing-slide-padding)">
    <!-- ヘッダー: ロゴ -->
    <div class="absolute top-16 left-20">
      <img src="assets/logo.svg" alt="ロゴ" class="h-10" />
    </div>
    <!-- コンテンツ領域（垂直バランス: 見出し上部固定 + メインコンテンツ垂直中央） -->
    <div style="margin-top: var(--spacing-gap-lg); display: flex; flex-direction: column; height: calc(100% - 6rem)">
      {CONTENT}
      <!--
        垂直バランスルール:
        - 見出し + サブテキストは通常通り上部に配置
        - メインコンテンツ（カード群・テーブル・ステップ等）のラッパーに
          style="margin-top: auto; margin-bottom: auto" を適用して垂直中央配置
        - これにより見出し下の余白とフッター上の余白が均等になる
      -->
    </div>
    <!-- フッター -->
    <div class="absolute bottom-8 left-20 text-sm" style="color: var(--color-text-muted)">
      <span style="margin-right: var(--spacing-gap-sm)">{N}</span><span>{セクション名}</span>
    </div>
    <div class="absolute bottom-8 right-8 text-sm" style="color: var(--color-text-muted)">
      &copy; {会社名}
    </div>
  </div>
</section>
```

### 暗い背景スライド（cover, section-divider）

```html
<section class="slide" data-slide="{N}" data-family="hero" data-variant="{variant}">
  <div class="w-[1920px] h-[1080px] relative overflow-hidden"
       style="background: linear-gradient(135deg, var(--color-primary), var(--color-accent))">
    {CONTENT}
    <div class="absolute bottom-8 right-8 text-white/30 text-sm">&copy; {会社名}</div>
  </div>
</section>
```

### 共通部品

**見出し:**
```html
<h2 class="text-[52px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-sm)">見出し</h2>
```

**サブテキスト:**
```html
<p class="text-[24px]" style="color: var(--color-text-muted); margin-bottom: var(--spacing-gap-lg)">サブテキスト</p>
```

**アイコンボックス:**
```html
<div class="w-16 h-16 rounded-xl flex items-center justify-center text-white"
     style="background: var(--color-accent)">
  <!-- SVGアイコン -->
</div>
```

**バッジ/ラベル:**
```html
<span class="inline-block rounded-full text-[16px] font-bold text-white"
      style="background: var(--color-accent); padding: var(--spacing-gap-sm) var(--spacing-gap-sm)">ラベル</span>
```

**画像キャプション（スクリーンショット等の補足ラベル）:**

画像の**上部中央**に配置する。absoluteで浮かせるのではなく、画像とセットでflex-colにまとめる。

```html
<div class="relative flex flex-col items-center">
  <span class="text-[14px] font-bold rounded-full text-white"
        style="background: var(--color-primary); padding: 0.25rem var(--spacing-gap-sm); margin-bottom: var(--spacing-gap-sm)">キャプション</span>
  <img src="screenshot.png" alt="説明" class="rounded-xl shadow-2xl object-contain"
       style="max-width: 880px; max-height: 620px;" />
</div>
```

**矢印コネクタ:**
```html
<svg width="40" height="24" viewBox="0 0 40 24" fill="none">
  <path d="M28 0L40 12L28 24M0 12H38" stroke="var(--color-text-muted)" stroke-width="2"/>
</svg>
```

---

## 1. Hero Family

以下は **{CONTENT}** 部分のみ記載。共通パーツの「暗い背景スライド」または「通常スライド」で囲む。

### cover（暗い背景スライドを使用）

```html
<!-- 装飾SVG -->
<div class="absolute top-0 right-0 w-[800px] h-full pointer-events-none opacity-10">
  <svg viewBox="0 0 800 1080" fill="none">
    <circle cx="500" cy="200" r="350" fill="var(--color-bg)" />
    <circle cx="650" cy="700" r="250" fill="var(--color-text-muted)" />
  </svg>
</div>
<!-- メインコンテンツ -->
<div class="absolute bottom-32 left-20 max-w-[1200px]">
  <h1 class="text-[96px] font-black leading-[1.1] tracking-tight text-white">タイトル</h1>
  <p class="text-[32px] font-medium text-white/60" style="margin-top: var(--spacing-gap-md)">サブタイトル</p>
</div>
```

### section-divider（暗い背景スライドを使用）

```html
<div class="absolute top-12 right-20">
  <span class="text-[280px] font-black text-white/20 leading-none">{番号}</span>
</div>
<div class="absolute bottom-32 left-20">
  <h2 class="text-[120px] font-black text-white leading-none">{セクション名}</h2>
</div>
```

### big-number（通常スライドを使用、padding なし、flex中央配置）

```html
<div class="text-center" style="padding: 0 var(--spacing-slide-padding)">
  <p class="text-[28px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-sm)">ラベル</p>
  <p class="text-[200px] font-black leading-none" style="color: var(--color-text)">
    1,200<span class="text-[80px]">社</span>
  </p>
  <p class="text-[28px]" style="color: var(--color-text-muted); margin-top: var(--spacing-gap-md)">補足説明</p>
</div>
```

### quote（通常スライド、背景 `--color-bg-alt`）

```html
<div class="max-w-[1400px]" style="padding: 0 var(--spacing-slide-padding)">
  <span class="text-[160px] leading-none font-black absolute -top-4 -left-4 opacity-10"
        style="color: var(--color-accent)">&ldquo;</span>
  <blockquote class="text-[48px] font-medium leading-relaxed" style="color: var(--color-text)">
    引用テキスト
  </blockquote>
  <div class="flex items-center" style="margin-top: var(--spacing-gap-lg); gap: var(--spacing-gap-sm)">
    <img src="https://placehold.jp/80x80" alt="著者" class="w-16 h-16 rounded-full object-cover" />
    <div>
      <p class="text-[24px] font-bold" style="color: var(--color-text)">著者名</p>
      <p class="text-[20px]" style="color: var(--color-text-muted)">肩書き</p>
    </div>
  </div>
</div>
```

### closing（通常スライド、flex中央配置）

```html
<div class="text-center">
  <img src="assets/logo.svg" alt="ロゴ" class="h-24 mx-auto" style="margin-bottom: var(--spacing-gap-lg)" />
  <h2 class="text-[56px] font-bold" style="color: var(--color-text)">CTA / タグライン</h2>
  <p class="text-[28px]" style="color: var(--color-text-muted); margin-top: var(--spacing-gap-sm)">連絡先</p>
</div>
```

---

## 2. Single-Column Family

### bullet-list

```html
<!-- 見出し + サブテキスト（共通部品参照） -->
<h2 class="text-[52px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-sm)">見出し</h2>
<p class="text-[24px]" style="color: var(--color-text-muted); margin-bottom: var(--spacing-gap-lg)">サブテキスト</p>
<ul style="display: flex; flex-direction: column; gap: var(--spacing-gap-md)">
  <li class="flex items-start" style="gap: var(--spacing-gap-sm)">
    <span class="w-3 h-3 rounded-full shrink-0" style="background: var(--color-accent); margin-top: 0.75rem"></span>
    <div>
      <p class="text-[32px] font-bold" style="color: var(--color-text)">項目タイトル</p>
      <p class="text-[24px]" style="color: var(--color-text-muted); margin-top: 0.5rem">補足説明</p>
    </div>
  </li>
  <!-- 3〜5項目推奨 -->
</ul>
```

### text-block

```html
<!-- 見出し + サブテキスト（共通部品参照） -->
<h2 class="text-[52px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-md)">見出し</h2>
<h3 class="text-[36px] font-bold" style="color: var(--color-text); margin-bottom: var(--spacing-gap-md)">サブ見出し</h3>
<div class="text-[26px] leading-relaxed max-w-[1400px]" style="color: var(--color-text); display: flex; flex-direction: column; gap: var(--spacing-gap-sm)">
  <p>本文テキスト。</p>
</div>
```

---

## 3. Split Family

### text-image

通常スライドの padding を外し、`flex` レイアウトに変更。

```html
<!-- 左: テキスト（55%） -->
<div class="w-[55%] flex flex-col justify-center" style="padding: var(--spacing-slide-padding); padding-top: 8rem">
  <!-- 見出し + サブテキスト（共通部品参照） -->
  <h2 class="text-[48px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-sm)">見出し</h2>
  <p class="text-[26px] leading-relaxed" style="color: var(--color-text)">説明テキスト</p>
</div>
<!-- 右: 画像（45%） -->
<div class="w-[45%] relative">
  <img src="https://placehold.jp/864x1080" alt="説明画像" class="w-full h-full object-cover" />
</div>
```

反転: `flex-row-reverse` を親divに追加。

### two-column

```html
<!-- 見出し + サブテキスト（共通部品参照） -->
<h2 class="text-[48px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-lg)">見出し</h2>
<div class="flex" style="gap: var(--spacing-gap-lg)">
  <div class="flex-1">
    <h3 class="text-[32px] font-bold" style="color: var(--color-text); margin-bottom: var(--spacing-gap-sm)">左カラム</h3>
    <p class="text-[24px] leading-relaxed" style="color: var(--color-text)">テキスト</p>
  </div>
  <div class="flex-1">
    <h3 class="text-[32px] font-bold" style="color: var(--color-text); margin-bottom: var(--spacing-gap-sm)">右カラム</h3>
    <p class="text-[24px] leading-relaxed" style="color: var(--color-text)">テキスト</p>
  </div>
</div>
```

### comparison

```html
<!-- 見出し + サブテキスト（共通部品参照） -->
<h2 class="text-[48px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-lg)">比較テーマ</h2>
<div class="flex" style="gap: var(--spacing-gap-lg)">
  <!-- Before -->
  <div class="flex-1 rounded-2xl" style="background: var(--color-bg-alt); padding: var(--spacing-gap-lg)">
    <span class="inline-block rounded-full text-[18px] font-bold text-white"
          style="background: var(--color-text-muted); padding: var(--spacing-gap-sm) var(--spacing-gap-sm); margin-bottom: var(--spacing-gap-md)">Before</span>
    <h3 class="text-[32px] font-bold" style="color: var(--color-text); margin-bottom: var(--spacing-gap-sm)">既存の方法</h3>
    <ul class="text-[24px]" style="color: var(--color-text); display: flex; flex-direction: column; gap: var(--spacing-gap-sm)">
      <li>課題点</li>
    </ul>
  </div>
  <!-- After -->
  <div class="flex-1 rounded-2xl border-2"
       style="background: var(--color-bg); border-color: var(--color-accent); padding: var(--spacing-gap-lg)">
    <span class="inline-block rounded-full text-[18px] font-bold text-white"
          style="background: var(--color-accent); padding: var(--spacing-gap-sm) var(--spacing-gap-sm); margin-bottom: var(--spacing-gap-md)">After</span>
    <h3 class="text-[32px] font-bold" style="color: var(--color-text); margin-bottom: var(--spacing-gap-sm)">提案する方法</h3>
    <ul class="text-[24px]" style="color: var(--color-text); display: flex; flex-direction: column; gap: var(--spacing-gap-sm)">
      <li>メリット</li>
    </ul>
  </div>
</div>
```

### qa

```html
<!-- 見出し + サブテキスト（共通部品参照） -->
<h2 class="text-[48px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-lg)">よくあるご質問</h2>
<div class="flex" style="gap: var(--spacing-gap-lg)">
  <div class="flex-1">
    <div class="flex items-start" style="gap: var(--spacing-gap-sm); margin-bottom: var(--spacing-gap-sm)">
      <span class="text-[40px] font-black" style="color: var(--color-accent)">Q</span>
      <p class="text-[28px] font-bold" style="color: var(--color-text); margin-top: 0.25rem">質問</p>
    </div>
    <div class="flex items-start" style="gap: var(--spacing-gap-sm); margin-top: var(--spacing-gap-sm)">
      <span class="text-[40px] font-black" style="color: var(--color-text-muted)">A</span>
      <p class="text-[24px] leading-relaxed" style="color: var(--color-text); margin-top: 0.5rem">回答</p>
    </div>
  </div>
  <!-- Q&A 2を同様に -->
</div>
```

---

## 4. Grid Family

### cards

```html
<!-- 見出し + サブテキスト（共通部品参照） -->
<h2 class="text-[48px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-sm)">見出し</h2>
<p class="text-[24px]" style="color: var(--color-text-muted); margin-bottom: var(--spacing-gap-lg)">補足説明</p>
<!-- 2〜4カラムに調整可能 -->
<div class="grid grid-cols-3" style="gap: var(--spacing-gap-md)">
  <div class="rounded-2xl" style="background: var(--color-bg-alt); padding: var(--spacing-gap-md)">
    <!-- アイコンボックス（共通部品参照） -->
    <div class="w-16 h-16 rounded-xl flex items-center justify-center text-white"
         style="background: var(--color-accent); margin-bottom: var(--spacing-gap-sm)"><!-- SVG --></div>
    <h3 class="text-[28px] font-bold" style="color: var(--color-text); margin-bottom: var(--spacing-gap-sm)">タイトル</h3>
    <p class="text-[22px] leading-relaxed" style="color: var(--color-text-muted)">説明</p>
  </div>
  <!-- 他カード同様 -->
</div>
```

### logos

```html
<!-- 見出し + サブテキスト（共通部品参照） -->
<h2 class="text-[48px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-lg)">導入企業</h2>
<div class="flex" style="gap: var(--spacing-gap-lg)">
  <div class="flex-1">
    <!-- バッジ（共通部品参照） -->
    <span class="inline-block rounded-full text-[16px] font-bold text-white"
          style="background: var(--color-accent); padding: var(--spacing-gap-sm) var(--spacing-gap-sm); margin-bottom: var(--spacing-gap-md)">カテゴリ名</span>
    <div class="grid grid-cols-2" style="gap: var(--spacing-gap-sm)">
      <div class="h-24 rounded-xl flex items-center justify-center"
           style="background: var(--color-bg-alt); padding: 0 var(--spacing-gap-sm)">
        <img src="https://placehold.jp/200x60" alt="企業名" class="max-h-12 max-w-full object-contain" />
      </div>
    </div>
  </div>
</div>
```

### team-members

```html
<!-- 見出し + サブテキスト（共通部品参照） -->
<h2 class="text-[48px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-sm)">チームメンバー</h2>
<p class="text-[24px]" style="color: var(--color-text-muted); margin-bottom: var(--spacing-gap-lg)">補足テキスト</p>
<div class="grid grid-cols-4" style="gap: var(--spacing-gap-lg)">
  <div class="text-center">
    <div class="w-48 h-48 rounded-full mx-auto overflow-hidden"
         style="background: linear-gradient(135deg, var(--color-primary), var(--color-accent)); margin-bottom: var(--spacing-gap-sm)">
      <img src="https://placehold.jp/192x192" alt="名前" class="w-full h-full object-cover" />
    </div>
    <p class="text-[24px] font-bold" style="color: var(--color-text)">名前</p>
    <p class="text-[18px]" style="color: var(--color-accent)">English Name</p>
    <p class="text-[18px]" style="color: var(--color-text-muted); margin-top: 0.5rem">役職</p>
  </div>
  <!-- 3〜4名推奨 -->
</div>
```

---

## 5. Sequence Family

### steps

```html
<!-- 見出し + サブテキスト（共通部品参照） -->
<h2 class="text-[52px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-sm)">導入の流れ</h2>
<p class="text-[24px]" style="color: var(--color-text-muted); margin-bottom: var(--spacing-gap-lg)">補足説明</p>
<div class="flex items-start" style="gap: var(--spacing-gap-sm)">
  <div class="flex-1 text-center">
    <div class="w-20 h-20 rounded-full flex items-center justify-center mx-auto text-[32px] font-black text-white"
         style="background: var(--color-accent)">1</div>
    <h3 class="text-[26px] font-bold" style="color: var(--color-text); margin-top: var(--spacing-gap-sm); margin-bottom: var(--spacing-gap-sm)">ステップ名</h3>
    <p class="text-[20px]" style="color: var(--color-text-muted)">説明</p>
  </div>
  <!-- 矢印コネクタ（共通部品参照） -->
  <!-- 3〜5ステップ推奨 -->
</div>
```

### timeline

```html
<div class="flex" style="gap: var(--spacing-gap-lg)">
  <div class="w-[35%]">
    <!-- 見出し + サブテキスト（共通部品参照） -->
    <h2 class="text-[48px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-sm)">沿革</h2>
    <p class="text-[24px] leading-relaxed" style="color: var(--color-text)">説明テキスト</p>
  </div>
  <div class="flex-1 relative">
    <div class="absolute left-6 top-0 bottom-0 w-0.5" style="background: var(--color-accent)"></div>
    <div style="display: flex; flex-direction: column; gap: var(--spacing-gap-md)">
      <div class="flex items-start relative" style="gap: var(--spacing-gap-md)">
        <div class="w-12 h-12 rounded-full shrink-0 flex items-center justify-center z-10 text-white text-[14px] font-bold"
             style="background: var(--color-accent)">&bull;</div>
        <div>
          <p class="text-[22px] font-bold" style="color: var(--color-accent)">2020年</p>
          <p class="text-[22px] font-bold" style="color: var(--color-text); margin-top: 0.25rem">イベント名</p>
          <p class="text-[18px]" style="color: var(--color-text-muted); margin-top: 0.25rem">説明</p>
        </div>
      </div>
    </div>
  </div>
</div>
```

---

## 6. Table Family

### pricing

並列カードは**全て同じ構造**にすること（バッジ・ボーダー色・パディング等を揃える）。
`max-w-*` で幅を制限する場合は `mx-auto` で中央配置すること。

```html
<!-- 見出し + サブテキスト（共通部品参照） -->
<h2 class="text-[48px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-lg)">料金プラン</h2>
<div class="flex" style="gap: var(--spacing-gap-lg)">
  <!-- プランカード（全カード同じ構造にする） -->
  <div class="flex-1 rounded-2xl border-2"
       style="border-color: var(--color-border); background: var(--color-bg); padding: var(--spacing-gap-lg)">
    <div class="text-center">
      <p class="text-[24px] font-bold" style="color: var(--color-accent)">プラン名</p>
      <p class="text-[72px] font-black" style="color: var(--color-text); margin-top: var(--spacing-gap-sm)">
        ¥10,000<span class="text-[24px] font-normal" style="color: var(--color-text-muted)">/月</span>
      </p>
    </div>
    <hr style="border-color: var(--color-border); margin: var(--spacing-gap-md) 0" />
    <ul class="text-[24px]" style="color: var(--color-text); display: flex; flex-direction: column; gap: var(--spacing-gap-sm)">
      <li class="flex items-center" style="gap: var(--spacing-gap-sm)">
        <span style="color: var(--color-accent)">&#10003;</span> 機能1
      </li>
    </ul>
  </div>
  <!-- 他プランも同じ構造で -->
</div>
```

### feature-comparison

```html
<!-- 見出し + サブテキスト（共通部品参照） -->
<h2 class="text-[48px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-lg)">機能比較</h2>
<table class="w-full text-[22px]">
  <thead>
    <tr style="border-bottom: 2px solid var(--color-border)">
      <th class="text-left font-bold" style="color: var(--color-text); width: 30%; padding: var(--spacing-gap-sm) 0">機能</th>
      <th class="text-center font-bold" style="color: var(--color-text-muted); padding: var(--spacing-gap-sm) 0">競合A</th>
      <th class="text-center font-bold" style="color: var(--color-accent); padding: var(--spacing-gap-sm) 0">自社</th>
    </tr>
  </thead>
  <tbody>
    <tr style="border-bottom: 1px solid var(--color-border)">
      <td class="font-medium" style="color: var(--color-text); padding: var(--spacing-gap-sm) 0">機能名</td>
      <td class="text-center" style="color: var(--color-text-muted); padding: var(--spacing-gap-sm) 0">&#10005;</td>
      <td class="text-center font-bold" style="color: var(--color-accent); padding: var(--spacing-gap-sm) 0">&#10003;</td>
    </tr>
    <!-- 5〜8行推奨 -->
  </tbody>
</table>
```

---

## 7. Diagram Family

### flow

```html
<!-- 見出し + サブテキスト（共通部品参照） -->
<h2 class="text-[48px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-sm)">処理フロー</h2>
<p class="text-[24px]" style="color: var(--color-text-muted); margin-bottom: var(--spacing-gap-lg)">補足説明</p>
<div class="flex items-center justify-center" style="gap: var(--spacing-gap-sm)">
  <!-- 塗りノード -->
  <div class="rounded-xl text-center min-w-[200px] text-white"
       style="background: var(--color-accent); padding: var(--spacing-gap-sm) var(--spacing-gap-md)">
    <p class="text-[22px] font-bold">入力</p>
  </div>
  <!-- 矢印コネクタ（共通部品参照） -->
  <!-- 枠線ノード -->
  <div class="rounded-xl text-center min-w-[200px] border-2"
       style="background: var(--color-bg-alt); border-color: var(--color-accent); padding: var(--spacing-gap-sm) var(--spacing-gap-md)">
    <p class="text-[22px] font-bold" style="color: var(--color-text)">処理</p>
  </div>
</div>
```

### org-chart

```html
<!-- 見出し + サブテキスト（共通部品参照） -->
<h2 class="text-[48px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-lg)">組織図</h2>
<div class="flex flex-col items-center">
  <!-- ルートノード（塗り） -->
  <div class="rounded-xl text-center text-white"
       style="background: var(--color-accent); padding: var(--spacing-gap-sm) var(--spacing-gap-md)">
    <p class="text-[22px] font-bold">部門名</p>
  </div>
  <!-- コネクタ -->
  <div class="w-0.5 h-10" style="background: var(--color-text-muted)"></div>
  <!-- 子ノード -->
  <div class="flex relative" style="gap: var(--spacing-gap-md)">
    <div class="absolute top-0 left-[25%] right-[25%] h-0.5"
         style="background: var(--color-text-muted)"></div>
    <div class="flex flex-col items-center">
      <div class="w-0.5 h-6" style="background: var(--color-text-muted)"></div>
      <div class="rounded-xl text-center border-2" style="border-color: var(--color-accent); padding: var(--spacing-gap-sm) var(--spacing-gap-md)">
        <p class="text-[20px] font-bold" style="color: var(--color-accent)">チーム名</p>
        <p class="text-[16px]" style="color: var(--color-text-muted); margin-top: 0.25rem">サブ情報</p>
      </div>
    </div>
  </div>
</div>
```

### cycle（循環関係: 2-4要素の円形/四角形サイクル）

```html
<!-- 見出し + サブテキスト（共通部品参照） -->
<h2 class="text-[48px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-sm)">サイクル名</h2>
<p class="text-[24px]" style="color: var(--color-text-muted); margin-bottom: var(--spacing-gap-lg)">補足説明</p>
<div class="flex items-center justify-center" style="gap: var(--spacing-gap-md)">
  <!-- ノード1 -->
  <div class="w-48 h-48 rounded-full flex flex-col items-center justify-center text-white text-center"
       style="background: var(--color-accent)">
    <p class="text-[20px] font-bold">PLAN</p>
    <p class="text-[14px] opacity-80" style="margin-top: 0.25rem">計画</p>
  </div>
  <!-- 矢印（共通部品の矢印コネクタ使用） -->
  <!-- ノード2 -->
  <div class="w-48 h-48 rounded-full flex flex-col items-center justify-center border-2 text-center"
       style="border-color: var(--color-accent)">
    <p class="text-[20px] font-bold" style="color: var(--color-accent)">DO</p>
    <p class="text-[14px]" style="color: var(--color-text-muted); margin-top: 0.25rem">実行</p>
  </div>
  <!-- 以降のノードも同様 -->
</div>
```

4要素以上は四角ノードで配置。2x2グリッドにして矢印で接続する。

### matrix（2x2マトリクス: SWOT、ポジショニング）

```html
<!-- 見出し + サブテキスト（共通部品参照） -->
<h2 class="text-[48px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-sm)">マトリクスタイトル</h2>
<p class="text-[24px]" style="color: var(--color-text-muted); margin-bottom: var(--spacing-gap-md)">補足説明</p>
<div class="relative">
  <!-- 軸ラベル -->
  <div class="absolute -top-8 left-1/2 -translate-x-1/2 text-[18px] font-bold"
       style="color: var(--color-text-muted)">軸ラベル上</div>
  <div class="absolute -left-8 top-1/2 -translate-y-1/2 -rotate-90 text-[18px] font-bold"
       style="color: var(--color-text-muted)">軸ラベル左</div>
  <!-- 2x2グリッド -->
  <div class="grid grid-cols-2 max-w-[900px] mx-auto" style="gap: var(--spacing-gap-sm)">
    <div class="rounded-xl" style="background: var(--color-bg-alt); padding: var(--spacing-gap-md)">
      <h3 class="text-[24px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-sm)">象限1</h3>
      <p class="text-[18px]" style="color: var(--color-text-muted)">説明テキスト</p>
    </div>
    <div class="rounded-xl" style="background: var(--color-bg-alt); padding: var(--spacing-gap-md)">
      <h3 class="text-[24px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-sm)">象限2</h3>
      <p class="text-[18px]" style="color: var(--color-text-muted)">説明テキスト</p>
    </div>
    <div class="rounded-xl" style="background: var(--color-bg-alt); padding: var(--spacing-gap-md)">
      <h3 class="text-[24px] font-bold" style="color: var(--color-text); margin-bottom: var(--spacing-gap-sm)">象限3</h3>
      <p class="text-[18px]" style="color: var(--color-text-muted)">説明テキスト</p>
    </div>
    <div class="rounded-xl" style="background: var(--color-bg-alt); padding: var(--spacing-gap-md)">
      <h3 class="text-[24px] font-bold" style="color: var(--color-text); margin-bottom: var(--spacing-gap-sm)">象限4</h3>
      <p class="text-[18px]" style="color: var(--color-text-muted)">説明テキスト</p>
    </div>
  </div>
</div>
```

### venn（ベン図: 重なり・共通領域）

```html
<!-- 見出し + サブテキスト（共通部品参照） -->
<h2 class="text-[48px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-sm)">ベン図タイトル</h2>
<p class="text-[24px]" style="color: var(--color-text-muted); margin-bottom: var(--spacing-gap-lg)">補足説明</p>
<div class="relative flex items-center justify-center" style="height: 500px">
  <!-- 円A -->
  <div class="absolute w-[380px] h-[380px] rounded-full flex items-center justify-center opacity-20"
       style="background: var(--color-accent); left: calc(50% - 260px)"></div>
  <div class="absolute text-[24px] font-bold" style="color: var(--color-text); left: calc(50% - 220px)">
    要素A
  </div>
  <!-- 円B -->
  <div class="absolute w-[380px] h-[380px] rounded-full flex items-center justify-center opacity-20"
       style="background: var(--color-secondary); left: calc(50% - 120px)"></div>
  <div class="absolute text-[24px] font-bold" style="color: var(--color-text); left: calc(50% + 100px)">
    要素B
  </div>
  <!-- 重なり部分ラベル -->
  <div class="absolute text-[20px] font-bold text-center"
       style="color: var(--color-accent)">
    共通領域
  </div>
</div>
```

3円の場合は3つの円を三角形に配置する。

### pyramid（ピラミッド/じょうろ: 階層的な大小関係）

```html
<!-- 見出し + サブテキスト（共通部品参照） -->
<h2 class="text-[48px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-sm)">ピラミッドタイトル</h2>
<p class="text-[24px]" style="color: var(--color-text-muted); margin-bottom: var(--spacing-gap-lg)">補足説明</p>
<div class="flex flex-col items-center max-w-[800px] mx-auto" style="gap: var(--spacing-gap-sm)">
  <!-- 最上段（最小） -->
  <div class="w-[30%] rounded-lg text-center text-white"
       style="background: var(--color-accent); padding: var(--spacing-gap-sm) 0">
    <p class="text-[20px] font-bold">頂点</p>
    <p class="text-[14px] opacity-80">少数・最重要</p>
  </div>
  <!-- 中段 -->
  <div class="w-[55%] rounded-lg text-center border-2"
       style="border-color: var(--color-accent); padding: var(--spacing-gap-sm) 0">
    <p class="text-[20px] font-bold" style="color: var(--color-accent)">中間層</p>
    <p class="text-[14px]" style="color: var(--color-text-muted)">中程度</p>
  </div>
  <!-- 最下段（最大） -->
  <div class="w-[80%] rounded-lg text-center"
       style="background: var(--color-bg-alt); padding: var(--spacing-gap-sm) 0">
    <p class="text-[20px] font-bold" style="color: var(--color-text)">基盤層</p>
    <p class="text-[14px]" style="color: var(--color-text-muted)">多数・基礎</p>
  </div>
</div>
```

じょうろ型（逆ピラミッド）は width の順序を反転させる。TAM-SAM-SOM は同心円パターンも可。

### tree（ツリー図: 分解・分類の階層構造）

```html
<!-- 見出し + サブテキスト（共通部品参照） -->
<h2 class="text-[48px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-lg)">ツリータイトル</h2>
<div class="flex flex-col items-center">
  <!-- ルート -->
  <div class="rounded-xl text-center text-white"
       style="background: var(--color-accent); padding: var(--spacing-gap-sm) var(--spacing-gap-lg)">
    <p class="text-[24px] font-bold">全体</p>
  </div>
  <div class="w-0.5 h-8" style="background: var(--color-text-muted)"></div>
  <!-- 第1レベル分岐 -->
  <div class="flex relative" style="gap: var(--spacing-gap-lg)">
    <div class="absolute top-0 left-[15%] right-[15%] h-0.5"
         style="background: var(--color-text-muted)"></div>
    <!-- 分岐ノード -->
    <div class="flex flex-col items-center">
      <div class="w-0.5 h-6" style="background: var(--color-text-muted)"></div>
      <div class="rounded-xl text-center border-2"
           style="border-color: var(--color-accent); padding: var(--spacing-gap-sm) var(--spacing-gap-md)">
        <p class="text-[18px] font-bold" style="color: var(--color-accent)">分類A</p>
      </div>
      <div class="w-0.5 h-6" style="background: var(--color-text-muted)"></div>
      <!-- 第2レベル（テキストリスト） -->
      <div class="text-[16px]" style="color: var(--color-text-muted); display: flex; flex-direction: column; gap: 0.5rem">
        <p>・項目1</p>
        <p>・項目2</p>
      </div>
    </div>
    <div class="flex flex-col items-center">
      <div class="w-0.5 h-6" style="background: var(--color-text-muted)"></div>
      <div class="rounded-xl text-center border-2"
           style="border-color: var(--color-accent); padding: var(--spacing-gap-sm) var(--spacing-gap-md)">
        <p class="text-[18px] font-bold" style="color: var(--color-accent)">分類B</p>
      </div>
      <div class="w-0.5 h-6" style="background: var(--color-text-muted)"></div>
      <div class="text-[16px]" style="color: var(--color-text-muted); display: flex; flex-direction: column; gap: 0.5rem">
        <p>・項目3</p>
        <p>・項目4</p>
      </div>
    </div>
  </div>
</div>
```

ツリーの深さは最大3レベルまでに抑える。横幅が足りない場合は横型（左→右）に変形する。
