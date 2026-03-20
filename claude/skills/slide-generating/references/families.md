# Family/Variant HTMLテンプレートパターン

## コンテンツ生成の原則

- 1スライド1メッセージ。箇条書きは3〜5項目上限。テキスト過多なら分割
- 見出しは短く、インパクトのある表現にする
- 画像プレースホルダーには適切なサイズとalt属性を指定する

## 厳守ルール

- **カラーコードの直書き禁止**: すべての色は `var(--color-*)` を使う。`#3B82F6`, `text-blue-300` 等のハードコード禁止
- **白テキストは `text-white` のみ例外**: 暗い背景（cover, section-divider）上の白テキストのみ `text-white` を許可
- **Tailwindのカラーユーティリティ禁止**: `text-blue-500`, `bg-gray-100` 等は使わない。すべて `style="color: var(--color-*)"` で書く

## 共通パーツ

全variant共通の構造。各variantテンプレートでは **{CONTENT}** 部分のみ記載する。

### 通常スライド（白背景）

```html
<section class="slide" data-slide="{N}" data-family="{family}" data-variant="{variant}">
  <div class="w-[1920px] h-[1080px] relative overflow-hidden p-20"
       style="background: var(--color-bg)">
    <!-- ヘッダー: ロゴ -->
    <div class="absolute top-16 left-20">
      <img src="assets/logo.svg" alt="ロゴ" class="h-10" />
    </div>
    <!-- コンテンツ領域 -->
    <div class="mt-24">
      {CONTENT}
    </div>
    <!-- フッター -->
    <div class="absolute bottom-8 left-20 text-sm" style="color: var(--color-text-muted)">
      <span class="mr-4">{N}</span><span>{セクション名}</span>
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
<h2 class="text-[52px] font-bold mb-4" style="color: var(--color-accent)">見出し</h2>
```

**サブテキスト:**
```html
<p class="text-[24px] mb-12" style="color: var(--color-text-muted)">サブテキスト</p>
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
<span class="inline-block px-4 py-2 rounded-full text-[16px] font-bold text-white"
      style="background: var(--color-accent)">ラベル</span>
```

**画像キャプション（スクリーンショット等の補足ラベル）:**

画像の**上部中央**に配置する。absoluteで浮かせるのではなく、画像とセットでflex-colにまとめる。

```html
<div class="relative flex flex-col items-center">
  <span class="text-[14px] font-bold px-4 py-1 rounded-full text-white mb-3"
        style="background: var(--color-primary)">キャプション</span>
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
  <p class="text-[32px] mt-8 font-medium text-white/60">サブタイトル</p>
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

### big-number（通常スライドを使用、p-20なし、flex中央配置）

```html
<div class="text-center px-20">
  <p class="text-[28px] font-bold mb-4" style="color: var(--color-accent)">ラベル</p>
  <p class="text-[200px] font-black leading-none" style="color: var(--color-text)">
    1,200<span class="text-[80px]">社</span>
  </p>
  <p class="text-[28px] mt-8" style="color: var(--color-text-muted)">補足説明</p>
</div>
```

### quote（通常スライド、背景 `--color-bg-alt`）

```html
<div class="px-40 max-w-[1400px]">
  <span class="text-[160px] leading-none font-black absolute -top-4 -left-4 opacity-10"
        style="color: var(--color-accent)">&ldquo;</span>
  <blockquote class="text-[48px] font-medium leading-relaxed" style="color: var(--color-text)">
    引用テキスト
  </blockquote>
  <div class="mt-12 flex items-center gap-6">
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
  <img src="assets/logo.svg" alt="ロゴ" class="h-24 mx-auto mb-12" />
  <h2 class="text-[56px] font-bold" style="color: var(--color-text)">CTA / タグライン</h2>
  <p class="text-[28px] mt-6" style="color: var(--color-text-muted)">連絡先</p>
</div>
```

---

## 2. Single-Column Family

### bullet-list

```html
<h2 class="text-[52px] font-bold mb-4" style="color: var(--color-accent)">見出し</h2>
<p class="text-[24px] mb-12" style="color: var(--color-text-muted)">サブテキスト</p>
<ul class="space-y-8">
  <li class="flex items-start gap-6">
    <span class="w-3 h-3 rounded-full mt-3 shrink-0" style="background: var(--color-accent)"></span>
    <div>
      <p class="text-[32px] font-bold" style="color: var(--color-text)">項目タイトル</p>
      <p class="text-[24px] mt-2" style="color: var(--color-text-muted)">補足説明</p>
    </div>
  </li>
  <!-- 3〜5項目推奨 -->
</ul>
```

### text-block

```html
<h2 class="text-[52px] font-bold mb-8" style="color: var(--color-accent)">見出し</h2>
<h3 class="text-[36px] font-bold mb-8" style="color: var(--color-text)">サブ見出し</h3>
<div class="text-[26px] leading-relaxed space-y-6 max-w-[1400px]" style="color: var(--color-text)">
  <p>本文テキスト。</p>
</div>
```

---

## 3. Split Family

### text-image

通常スライドの `p-20` を外し、`flex` レイアウトに変更。

```html
<!-- 左: テキスト（55%） -->
<div class="w-[55%] p-20 pt-32 flex flex-col justify-center">
  <h2 class="text-[48px] font-bold mb-6" style="color: var(--color-accent)">見出し</h2>
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
<h2 class="text-[48px] font-bold mb-12" style="color: var(--color-accent)">見出し</h2>
<div class="flex gap-20">
  <div class="flex-1">
    <h3 class="text-[32px] font-bold mb-6" style="color: var(--color-text)">左カラム</h3>
    <p class="text-[24px] leading-relaxed" style="color: var(--color-text)">テキスト</p>
  </div>
  <div class="flex-1">
    <h3 class="text-[32px] font-bold mb-6" style="color: var(--color-text)">右カラム</h3>
    <p class="text-[24px] leading-relaxed" style="color: var(--color-text)">テキスト</p>
  </div>
</div>
```

### comparison

```html
<h2 class="text-[48px] font-bold mb-12" style="color: var(--color-accent)">比較テーマ</h2>
<div class="flex gap-12">
  <!-- Before -->
  <div class="flex-1 rounded-2xl p-12" style="background: var(--color-bg-alt)">
    <span class="inline-block px-4 py-2 rounded-full text-[18px] font-bold text-white mb-8"
          style="background: var(--color-text-muted)">Before</span>
    <h3 class="text-[32px] font-bold mb-6" style="color: var(--color-text)">既存の方法</h3>
    <ul class="space-y-4 text-[24px]" style="color: var(--color-text)">
      <li>課題点</li>
    </ul>
  </div>
  <!-- After -->
  <div class="flex-1 rounded-2xl p-12 border-2"
       style="background: var(--color-bg); border-color: var(--color-accent)">
    <span class="inline-block px-4 py-2 rounded-full text-[18px] font-bold text-white mb-8"
          style="background: var(--color-accent)">After</span>
    <h3 class="text-[32px] font-bold mb-6" style="color: var(--color-text)">提案する方法</h3>
    <ul class="space-y-4 text-[24px]" style="color: var(--color-text)">
      <li>メリット</li>
    </ul>
  </div>
</div>
```

### qa

```html
<h2 class="text-[48px] font-bold mb-12" style="color: var(--color-accent)">よくあるご質問</h2>
<div class="flex gap-20">
  <div class="flex-1">
    <div class="flex items-start gap-4 mb-4">
      <span class="text-[40px] font-black" style="color: var(--color-accent)">Q</span>
      <p class="text-[28px] font-bold mt-1" style="color: var(--color-text)">質問</p>
    </div>
    <div class="flex items-start gap-4 mt-6">
      <span class="text-[40px] font-black" style="color: var(--color-text-muted)">A</span>
      <p class="text-[24px] mt-2 leading-relaxed" style="color: var(--color-text)">回答</p>
    </div>
  </div>
  <!-- Q&A 2を同様に -->
</div>
```

---

## 4. Grid Family

### cards

```html
<h2 class="text-[48px] font-bold mb-4" style="color: var(--color-accent)">見出し</h2>
<p class="text-[24px] mb-12" style="color: var(--color-text-muted)">補足説明</p>
<!-- 2〜4カラムに調整可能 -->
<div class="grid grid-cols-3 gap-10">
  <div class="rounded-2xl p-10" style="background: var(--color-bg-alt)">
    <!-- アイコンボックス（共通部品参照） -->
    <div class="w-16 h-16 rounded-xl flex items-center justify-center mb-6 text-white"
         style="background: var(--color-accent)"><!-- SVG --></div>
    <h3 class="text-[28px] font-bold mb-4" style="color: var(--color-text)">タイトル</h3>
    <p class="text-[22px] leading-relaxed" style="color: var(--color-text-muted)">説明</p>
  </div>
  <!-- 他カード同様 -->
</div>
```

### logos

```html
<h2 class="text-[48px] font-bold mb-12" style="color: var(--color-accent)">導入企業</h2>
<div class="flex gap-12">
  <div class="flex-1">
    <!-- バッジ（共通部品参照） -->
    <span class="inline-block px-4 py-2 rounded-full text-[16px] font-bold text-white mb-8"
          style="background: var(--color-accent)">カテゴリ名</span>
    <div class="grid grid-cols-2 gap-6">
      <div class="h-24 rounded-xl flex items-center justify-center px-6"
           style="background: var(--color-bg-alt)">
        <img src="https://placehold.jp/200x60" alt="企業名" class="max-h-12 max-w-full object-contain" />
      </div>
    </div>
  </div>
</div>
```

### team-members

```html
<h2 class="text-[48px] font-bold mb-4" style="color: var(--color-accent)">チームメンバー</h2>
<p class="text-[24px] mb-16" style="color: var(--color-text-muted)">補足テキスト</p>
<div class="grid grid-cols-4 gap-12">
  <div class="text-center">
    <div class="w-48 h-48 rounded-full mx-auto mb-6 overflow-hidden"
         style="background: linear-gradient(135deg, var(--color-primary), var(--color-accent))">
      <img src="https://placehold.jp/192x192" alt="名前" class="w-full h-full object-cover" />
    </div>
    <p class="text-[24px] font-bold" style="color: var(--color-text)">名前</p>
    <p class="text-[18px]" style="color: var(--color-accent)">English Name</p>
    <p class="text-[18px] mt-2" style="color: var(--color-text-muted)">役職</p>
  </div>
  <!-- 3〜4名推奨 -->
</div>
```

---

## 5. Sequence Family

### steps

```html
<h2 class="text-[52px] font-bold mb-4" style="color: var(--color-accent)">導入の流れ</h2>
<p class="text-[24px] mb-16" style="color: var(--color-text-muted)">補足説明</p>
<div class="flex items-start gap-6">
  <div class="flex-1 text-center">
    <div class="w-20 h-20 rounded-full flex items-center justify-center mx-auto text-[32px] font-black text-white"
         style="background: var(--color-accent)">1</div>
    <h3 class="text-[26px] font-bold mt-6 mb-4" style="color: var(--color-text)">ステップ名</h3>
    <p class="text-[20px]" style="color: var(--color-text-muted)">説明</p>
  </div>
  <!-- 矢印コネクタ（共通部品参照） -->
  <!-- 3〜5ステップ推奨 -->
</div>
```

### timeline

```html
<div class="flex gap-20">
  <div class="w-[35%]">
    <h2 class="text-[48px] font-bold mb-6" style="color: var(--color-accent)">沿革</h2>
    <p class="text-[24px] leading-relaxed" style="color: var(--color-text)">説明テキスト</p>
  </div>
  <div class="flex-1 relative">
    <div class="absolute left-6 top-0 bottom-0 w-0.5" style="background: var(--color-accent)"></div>
    <div class="space-y-10">
      <div class="flex items-start gap-8 relative">
        <div class="w-12 h-12 rounded-full shrink-0 flex items-center justify-center z-10 text-white text-[14px] font-bold"
             style="background: var(--color-accent)">&bull;</div>
        <div>
          <p class="text-[22px] font-bold" style="color: var(--color-accent)">2020年</p>
          <p class="text-[22px] font-bold mt-1" style="color: var(--color-text)">イベント名</p>
          <p class="text-[18px] mt-1" style="color: var(--color-text-muted)">説明</p>
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
<h2 class="text-[48px] font-bold mb-12" style="color: var(--color-accent)">料金プラン</h2>
<div class="flex gap-12">
  <!-- プランカード（全カード同じ構造にする） -->
  <div class="flex-1 rounded-2xl p-12 border-2"
       style="border-color: var(--color-border); background: var(--color-bg)">
    <div class="text-center">
      <p class="text-[24px] font-bold" style="color: var(--color-accent)">プラン名</p>
      <p class="text-[72px] font-black mt-6" style="color: var(--color-text)">
        ¥10,000<span class="text-[24px] font-normal" style="color: var(--color-text-muted)">/月</span>
      </p>
    </div>
    <hr class="my-10" style="border-color: var(--color-border)" />
    <ul class="space-y-5 text-[24px]" style="color: var(--color-text)">
      <li class="flex items-center gap-4">
        <span style="color: var(--color-accent)">&#10003;</span> 機能1
      </li>
    </ul>
  </div>
  <!-- 他プランも同じ構造で -->
</div>
```

### feature-comparison

```html
<h2 class="text-[48px] font-bold mb-12" style="color: var(--color-accent)">機能比較</h2>
<table class="w-full text-[22px]">
  <thead>
    <tr style="border-bottom: 2px solid var(--color-border)">
      <th class="text-left py-5 font-bold" style="color: var(--color-text); width: 30%">機能</th>
      <th class="text-center py-5 font-bold" style="color: var(--color-text-muted)">競合A</th>
      <th class="text-center py-5 font-bold" style="color: var(--color-accent)">自社</th>
    </tr>
  </thead>
  <tbody>
    <tr style="border-bottom: 1px solid var(--color-border)">
      <td class="py-5 font-medium" style="color: var(--color-text)">機能名</td>
      <td class="text-center py-5" style="color: var(--color-text-muted)">&#10005;</td>
      <td class="text-center py-5 font-bold" style="color: var(--color-accent)">&#10003;</td>
    </tr>
    <!-- 5〜8行推奨 -->
  </tbody>
</table>
```

---

## 7. Diagram Family

### flow

```html
<h2 class="text-[48px] font-bold mb-4" style="color: var(--color-accent)">処理フロー</h2>
<p class="text-[24px] mb-12" style="color: var(--color-text-muted)">補足説明</p>
<div class="flex items-center justify-center gap-4">
  <!-- 塗りノード -->
  <div class="px-10 py-6 rounded-xl text-center min-w-[200px] text-white"
       style="background: var(--color-accent)">
    <p class="text-[22px] font-bold">入力</p>
  </div>
  <!-- 矢印コネクタ（共通部品参照） -->
  <!-- 枠線ノード -->
  <div class="px-10 py-6 rounded-xl text-center min-w-[200px] border-2"
       style="background: var(--color-bg-alt); border-color: var(--color-accent)">
    <p class="text-[22px] font-bold" style="color: var(--color-text)">処理</p>
  </div>
</div>
```

### org-chart

```html
<h2 class="text-[48px] font-bold mb-12" style="color: var(--color-accent)">組織図</h2>
<div class="flex flex-col items-center">
  <!-- ルートノード（塗り） -->
  <div class="px-10 py-4 rounded-xl text-center text-white"
       style="background: var(--color-accent)">
    <p class="text-[22px] font-bold">部門名</p>
  </div>
  <!-- コネクタ -->
  <div class="w-0.5 h-10" style="background: var(--color-text-muted)"></div>
  <!-- 子ノード -->
  <div class="flex gap-10 relative">
    <div class="absolute top-0 left-[25%] right-[25%] h-0.5"
         style="background: var(--color-text-muted)"></div>
    <div class="flex flex-col items-center">
      <div class="w-0.5 h-6" style="background: var(--color-text-muted)"></div>
      <div class="px-8 py-4 rounded-xl text-center border-2" style="border-color: var(--color-accent)">
        <p class="text-[20px] font-bold" style="color: var(--color-accent)">チーム名</p>
        <p class="text-[16px] mt-1" style="color: var(--color-text-muted)">サブ情報</p>
      </div>
    </div>
  </div>
</div>
```
