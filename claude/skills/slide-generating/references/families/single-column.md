# Single-Column Family

## bullet-list

```javascript
S(n, 'single-column', 'bullet-list', `
  ${H('見出し')}
  ${Sub('サブテキスト')}
  ${VC(`
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
  `)}
`, {sec: 'セクション名'})
```

## text-block

```javascript
S(n, 'single-column', 'text-block', `
  ${H('見出し')}
  <h3 class="text-[36px] font-bold" style="color: var(--color-text); margin-bottom: var(--spacing-gap-md)">サブ見出し</h3>
  <div class="text-[26px] leading-relaxed max-w-[1400px]" style="color: var(--color-text); display: flex; flex-direction: column; gap: var(--spacing-gap-sm)">
    <p>本文テキスト。</p>
  </div>
`, {sec: 'セクション名'})
```
