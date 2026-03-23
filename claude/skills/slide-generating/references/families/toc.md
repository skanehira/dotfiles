# TOC Family

## list

シンプルなリスト型目次。番号 + 項目名 + ページ番号を罫線区切りで表示。

```javascript
S(n, 'toc', 'list', `
  ${H('目次')}
  ${VC(`
    <div class="max-w-[1200px] mx-auto">
      <div class="flex items-baseline" style="padding: var(--spacing-gap-sm) 0; border-bottom: 1px solid var(--color-border)">
        <span class="text-[28px] font-bold" style="color: var(--color-accent); width: 3rem">01</span>
        <span class="text-[28px] font-medium flex-1" style="color: var(--color-text)">セクション名</span>
        <span class="text-[22px]" style="color: var(--color-text-muted)">03</span>
      </div>
      <div class="flex items-baseline" style="padding: var(--spacing-gap-sm) 0; border-bottom: 1px solid var(--color-border)">
        <span class="text-[28px] font-bold" style="color: var(--color-accent); width: 3rem">02</span>
        <span class="text-[28px] font-medium flex-1" style="color: var(--color-text)">セクション名</span>
        <span class="text-[22px]" style="color: var(--color-text-muted)">08</span>
      </div>
      <!-- 項目数に応じて追加 -->
    </div>
  `)}
`, {sec: '目次'})
```

## grouped

見出し付きグループ目次。セクション名ブロック + 項目リストでグループ化。

```javascript
S(n, 'toc', 'grouped', `
  ${H('目次')}
  ${VC(`
    <div class="flex max-w-[1400px] mx-auto" style="gap: var(--spacing-gap-lg)">
      <div class="flex-1">
        <div style="margin-bottom: var(--spacing-gap-md)">
          <p class="text-[24px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-sm)">Part 1 — セクション名</p>
          <div style="display: flex; flex-direction: column; gap: 0.5rem; padding-left: var(--spacing-gap-md)">
            <div class="flex items-baseline" style="gap: var(--spacing-gap-sm)">
              <span class="text-[20px]" style="color: var(--color-text-muted)">01</span>
              <span class="text-[22px]" style="color: var(--color-text)">項目名</span>
            </div>
            <div class="flex items-baseline" style="gap: var(--spacing-gap-sm)">
              <span class="text-[20px]" style="color: var(--color-text-muted)">02</span>
              <span class="text-[22px]" style="color: var(--color-text)">項目名</span>
            </div>
          </div>
        </div>
      </div>
      <div class="flex-1">
        <div style="margin-bottom: var(--spacing-gap-md)">
          <p class="text-[24px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-sm)">Part 2 — セクション名</p>
          <div style="display: flex; flex-direction: column; gap: 0.5rem; padding-left: var(--spacing-gap-md)">
            <div class="flex items-baseline" style="gap: var(--spacing-gap-sm)">
              <span class="text-[20px]" style="color: var(--color-text-muted)">03</span>
              <span class="text-[22px]" style="color: var(--color-text)">項目名</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  `)}
`, {sec: '目次'})
```

## circle

円型目次。横並びの丸の中にセクション番号と名前を配置。ウェビナー向け視認性重視。

```javascript
S(n, 'toc', 'circle', `
  ${H('目次')}
  ${Sub('本日のアジェンダ')}
  ${VC(`
    <div class="flex items-center justify-center" style="gap: var(--spacing-gap-lg)">
      <div class="w-52 h-52 rounded-full flex flex-col items-center justify-center text-center text-white" style="background: var(--color-accent)">
        <p class="text-[40px] font-black leading-none">01</p>
        <p class="text-[20px] font-medium" style="margin-top: var(--spacing-gap-sm)">セクション名</p>
      </div>
      <div class="w-52 h-52 rounded-full flex flex-col items-center justify-center text-center border-2" style="border-color: var(--color-accent)">
        <p class="text-[40px] font-black leading-none" style="color: var(--color-accent)">02</p>
        <p class="text-[20px] font-medium" style="color: var(--color-text); margin-top: var(--spacing-gap-sm)">セクション名</p>
      </div>
      <div class="w-52 h-52 rounded-full flex flex-col items-center justify-center text-center border-2" style="border-color: var(--color-accent)">
        <p class="text-[40px] font-black leading-none" style="color: var(--color-accent)">03</p>
        <p class="text-[20px] font-medium" style="color: var(--color-text); margin-top: var(--spacing-gap-sm)">セクション名</p>
      </div>
      <!-- 3〜5セクション推奨 -->
    </div>
  `)}
`, {sec: '目次'})
```
