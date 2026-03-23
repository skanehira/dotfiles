# Hero Family

以下は各variantの **content** 引数のみ記載。

## cover（D() を使用）

```javascript
D(1, 'cover', `
  <div class="absolute top-0 right-0 w-[800px] h-full pointer-events-none opacity-10">
    <svg viewBox="0 0 800 1080" fill="none">
      <circle cx="500" cy="200" r="350" fill="var(--color-bg)" />
      <circle cx="650" cy="700" r="250" fill="var(--color-text-muted)" />
    </svg>
  </div>
  <div class="absolute bottom-32 left-20 max-w-[1200px]">
    <h1 class="text-[96px] font-black leading-[1.1] tracking-tight text-white">タイトル</h1>
    <p class="text-[32px] font-medium text-white/60" style="margin-top: var(--spacing-gap-md)">サブタイトル</p>
  </div>
`)
```

## section-divider（D() を使用）

```javascript
D(2, 'section-divider', `
  <div class="absolute top-12 right-20">
    <span class="text-[280px] font-black text-white/20 leading-none">{番号}</span>
  </div>
  <div class="absolute bottom-32 left-20">
    <h2 class="text-[120px] font-black text-white leading-none">{セクション名}</h2>
  </div>
`)
```

## big-number（S() + VC() を使用）

```javascript
S(n, 'hero', 'big-number', VC(`
  <div class="text-center" style="padding: 0 var(--spacing-slide-padding)">
    <p class="text-[28px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-sm)">ラベル</p>
    <p class="text-[200px] font-black leading-none" style="color: var(--color-text)">
      1,200<span class="text-[80px]">社</span>
    </p>
    <p class="text-[28px]" style="color: var(--color-text-muted); margin-top: var(--spacing-gap-md)">補足説明</p>
  </div>
`))
```

## quote（S() + VC() を使用、背景 `--color-bg-alt`）

```javascript
S(n, 'hero', 'quote', VC(`
  <div class="max-w-[1400px]" style="padding: 0 var(--spacing-slide-padding)">
    <span class="text-[160px] leading-none font-black absolute -top-4 -left-4 opacity-10" style="color: var(--color-accent)">&ldquo;</span>
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
`), {bg: 'var(--color-bg-alt)'})
```

## closing（S() + VC() を使用）

```javascript
S(n, 'hero', 'closing', VC(`
  <div class="text-center">
    <img src="${_L}" alt="ロゴ" class="h-24 mx-auto" style="margin-bottom: var(--spacing-gap-lg)" />
    <h2 class="text-[56px] font-bold" style="color: var(--color-text)">CTA / タグライン</h2>
    <p class="text-[28px]" style="color: var(--color-text-muted); margin-top: var(--spacing-gap-sm)">連絡先</p>
  </div>
`))
```
