# Formula Family

## equation（数式表現: A = B/C）

```javascript
S(n, 'formula', 'equation', `
  ${H('数式タイトル')}
  ${Sub('補足説明')}
  ${VC(`
    <div class="flex items-center justify-center" style="gap: var(--spacing-gap-lg)">
      <!-- 左: 名前 -->
      <div class="text-center">
        <p class="text-[20px] font-bold" style="color: var(--color-text-muted)">Unit Economics</p>
        <p class="text-[64px] font-bold" style="color: var(--color-accent)">LTV</p>
      </div>
      <!-- 中央: = -->
      <p class="text-[72px] font-bold" style="color: var(--color-text-muted)">=</p>
      <!-- 右: 分数 -->
      <div class="flex flex-col items-center">
        <p class="text-[48px] font-bold" style="color: var(--color-accent)">ARPU</p>
        <div class="w-full h-[3px]" style="background: var(--color-text-muted); margin: var(--spacing-gap-sm) 0"></div>
        <p class="text-[48px] font-bold" style="color: var(--color-secondary)">Churn Rate</p>
      </div>
    </div>
    <!-- 補足説明 -->
    <div class="flex justify-center" style="gap: var(--spacing-gap-lg); margin-top: var(--spacing-gap-lg)">
      <div class="text-center">
        <p class="text-[18px] font-bold" style="color: var(--color-accent)">ARPU</p>
        <p class="text-[16px]" style="color: var(--color-text-muted)">平均顧客単価</p>
      </div>
      <div class="text-center">
        <p class="text-[18px] font-bold" style="color: var(--color-secondary)">Churn Rate</p>
        <p class="text-[16px]" style="color: var(--color-text-muted)">月次解約率</p>
      </div>
    </div>
  `)}
`, {sec: 'セクション名'})
```

## multiply（掛け算: A x B）

```javascript
S(n, 'formula', 'multiply', `
  ${H('掛け算タイトル')}
  ${Sub('補足説明')}
  ${VC(`
    <div class="flex items-center justify-center" style="gap: var(--spacing-gap-lg)">
      <!-- 要素A -->
      <div class="flex flex-col items-center">
        <div class="w-40 h-40 rounded-full flex items-center justify-center text-white" style="background: var(--color-accent)">
          ${IC('<!-- SVG -->')}
        </div>
        <p class="text-[28px] font-bold" style="color: var(--color-text); margin-top: var(--spacing-gap-sm)">要素A</p>
        <p class="text-[18px]" style="color: var(--color-text-muted)">説明テキスト</p>
      </div>
      <!-- x 記号 -->
      <p class="text-[72px] font-bold" style="color: var(--color-text-muted)">&times;</p>
      <!-- 要素B -->
      <div class="flex flex-col items-center">
        <div class="w-40 h-40 rounded-full flex items-center justify-center text-white" style="background: var(--color-secondary)">
          ${IC('<!-- SVG -->')}
        </div>
        <p class="text-[28px] font-bold" style="color: var(--color-text); margin-top: var(--spacing-gap-sm)">要素B</p>
        <p class="text-[18px]" style="color: var(--color-text-muted)">説明テキスト</p>
      </div>
    </div>
    <!-- 結果 -->
    <div class="text-center" style="margin-top: var(--spacing-gap-lg)">
      <div class="inline-block rounded-xl" style="background: var(--color-bg-alt); padding: var(--spacing-gap-sm) var(--spacing-gap-lg)">
        <p class="text-[24px] font-bold" style="color: var(--color-accent)">結果の説明テキスト</p>
      </div>
    </div>
  `)}
`, {sec: 'セクション名'})
```

## addition（足し算: A + B → C）

```javascript
S(n, 'formula', 'addition', `
  ${H('足し算タイトル')}
  ${Sub('補足説明')}
  ${VC(`
    <div class="flex items-center justify-center" style="gap: var(--spacing-gap-md)">
      <!-- カードA -->
      <div class="rounded-2xl text-center" style="background: var(--color-bg-alt); padding: var(--spacing-gap-md) var(--spacing-gap-lg)">
        <div style="margin-bottom: var(--spacing-gap-sm)">${IC('<!-- SVG -->')}</div>
        <p class="text-[28px] font-bold" style="color: var(--color-text)">要素A</p>
        <p class="text-[18px]" style="color: var(--color-text-muted); margin-top: var(--spacing-gap-sm)">説明テキスト</p>
      </div>
      <!-- + 記号 -->
      <p class="text-[72px] font-bold" style="color: var(--color-text-muted)">+</p>
      <!-- カードB -->
      <div class="rounded-2xl text-center" style="background: var(--color-bg-alt); padding: var(--spacing-gap-md) var(--spacing-gap-lg)">
        <div style="margin-bottom: var(--spacing-gap-sm)">${IC('<!-- SVG -->')}</div>
        <p class="text-[28px] font-bold" style="color: var(--color-text)">要素B</p>
        <p class="text-[18px]" style="color: var(--color-text-muted); margin-top: var(--spacing-gap-sm)">説明テキスト</p>
      </div>
      <!-- → 記号 -->
      <p class="text-[48px] font-bold" style="color: var(--color-accent)">&rarr;</p>
      <!-- 結果カード -->
      <div class="rounded-2xl text-center text-white" style="background: linear-gradient(135deg, var(--color-primary), var(--color-accent)); padding: var(--spacing-gap-md) var(--spacing-gap-lg)">
        <p class="text-[32px] font-bold">結果C</p>
        <p class="text-[18px] opacity-80" style="margin-top: var(--spacing-gap-sm)">結果の説明</p>
      </div>
    </div>
  `)}
`, {sec: 'セクション名'})
```
