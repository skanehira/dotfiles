# Chart Family

Chart.jsを使わず、HTML/CSSだけで描画するチャート。

## bar-vertical

縦棒グラフ。flexで棒を横並び、各棒は `height: XX%` で高さ制御。棒の上にラベルと値。X軸にカテゴリ名。

```javascript
S(n, 'chart', 'bar-vertical', `
  ${H('月別売上推移')}
  ${Sub('2024年度 上半期')}
  ${VC(`
    <div class="max-w-[1200px] mx-auto">
      <div class="flex items-end justify-center" style="height: 420px; gap: var(--spacing-gap-md)">
        <div class="flex flex-col items-center" style="gap: var(--spacing-gap-sm)">
          <p class="text-[18px] font-bold" style="color: var(--color-text)">120</p>
          <div class="rounded-t-lg" style="width: 80px; height: 60%; background: var(--color-accent)"></div>
          <p class="text-[18px]" style="color: var(--color-text-muted)">1月</p>
        </div>
        <div class="flex flex-col items-center" style="gap: var(--spacing-gap-sm)">
          <p class="text-[18px] font-bold" style="color: var(--color-text)">180</p>
          <div class="rounded-t-lg" style="width: 80px; height: 90%; background: var(--color-accent)"></div>
          <p class="text-[18px]" style="color: var(--color-text-muted)">2月</p>
        </div>
        <div class="flex flex-col items-center" style="gap: var(--spacing-gap-sm)">
          <p class="text-[18px] font-bold" style="color: var(--color-text)">150</p>
          <div class="rounded-t-lg" style="width: 80px; height: 75%; background: var(--color-secondary)"></div>
          <p class="text-[18px]" style="color: var(--color-text-muted)">3月</p>
        </div>
        <div class="flex flex-col items-center" style="gap: var(--spacing-gap-sm)">
          <p class="text-[18px] font-bold" style="color: var(--color-text)">200</p>
          <div class="rounded-t-lg" style="width: 80px; height: 100%; background: var(--color-accent)"></div>
          <p class="text-[18px]" style="color: var(--color-text-muted)">4月</p>
        </div>
        <!-- 棒を追加 -->
      </div>
      <div style="border-top: 2px solid var(--color-border)"></div>
    </div>
  `)}
`, {sec: 'セクション名'})
```

## bar-horizontal

横棒グラフ。各行にラベル + 棒（`width: XX%`）+ 値。ランキングや比較に適する。

```javascript
S(n, 'chart', 'bar-horizontal', `
  ${H('カテゴリ別売上')}
  ${Sub('2024年度実績')}
  ${VC(`
    <div class="max-w-[1200px] mx-auto" style="display: flex; flex-direction: column; gap: var(--spacing-gap-md)">
      <div class="flex items-center" style="gap: var(--spacing-gap-md)">
        <p class="text-[22px] font-medium text-right" style="color: var(--color-text); width: 140px">カテゴリA</p>
        <div class="flex-1 relative" style="height: 40px">
          <div class="absolute inset-y-0 left-0 rounded-r-lg" style="width: 85%; background: var(--color-accent)"></div>
        </div>
        <p class="text-[22px] font-bold" style="color: var(--color-text); width: 80px">850万</p>
      </div>
      <div class="flex items-center" style="gap: var(--spacing-gap-md)">
        <p class="text-[22px] font-medium text-right" style="color: var(--color-text); width: 140px">カテゴリB</p>
        <div class="flex-1 relative" style="height: 40px">
          <div class="absolute inset-y-0 left-0 rounded-r-lg" style="width: 65%; background: var(--color-secondary)"></div>
        </div>
        <p class="text-[22px] font-bold" style="color: var(--color-text); width: 80px">650万</p>
      </div>
      <div class="flex items-center" style="gap: var(--spacing-gap-md)">
        <p class="text-[22px] font-medium text-right" style="color: var(--color-text); width: 140px">カテゴリC</p>
        <div class="flex-1 relative" style="height: 40px">
          <div class="absolute inset-y-0 left-0 rounded-r-lg" style="width: 45%; background: var(--color-primary)"></div>
        </div>
        <p class="text-[22px] font-bold" style="color: var(--color-text); width: 80px">450万</p>
      </div>
      <!-- 行を追加 -->
    </div>
  `)}
`, {sec: 'セクション名'})
```

## pie-simple

簡易円グラフ。`conic-gradient` で円グラフを描画。2-4項目向け。凡例を右に配置。

```javascript
S(n, 'chart', 'pie-simple', `
  ${H('売上構成比')}
  ${Sub('2024年度')}
  ${VC(`
    <div class="flex items-center justify-center" style="gap: var(--spacing-gap-lg)">
      <!-- 円グラフ本体 -->
      <div class="rounded-full" style="width: 380px; height: 380px; background: conic-gradient(var(--color-accent) 0% 45%, var(--color-secondary) 45% 75%, var(--color-primary) 75% 90%, var(--color-bg-alt) 90% 100%)"></div>
      <!-- 凡例 -->
      <div style="display: flex; flex-direction: column; gap: var(--spacing-gap-md)">
        <div class="flex items-center" style="gap: var(--spacing-gap-sm)">
          <div class="w-5 h-5 rounded" style="background: var(--color-accent)"></div>
          <p class="text-[22px] font-medium" style="color: var(--color-text)">サービスA</p>
          <p class="text-[22px] font-bold" style="color: var(--color-accent)">45%</p>
        </div>
        <div class="flex items-center" style="gap: var(--spacing-gap-sm)">
          <div class="w-5 h-5 rounded" style="background: var(--color-secondary)"></div>
          <p class="text-[22px] font-medium" style="color: var(--color-text)">サービスB</p>
          <p class="text-[22px] font-bold" style="color: var(--color-secondary)">30%</p>
        </div>
        <div class="flex items-center" style="gap: var(--spacing-gap-sm)">
          <div class="w-5 h-5 rounded" style="background: var(--color-primary)"></div>
          <p class="text-[22px] font-medium" style="color: var(--color-text)">サービスC</p>
          <p class="text-[22px] font-bold" style="color: var(--color-primary)">15%</p>
        </div>
        <div class="flex items-center" style="gap: var(--spacing-gap-sm)">
          <div class="w-5 h-5 rounded" style="background: var(--color-bg-alt); border: 1px solid var(--color-border)"></div>
          <p class="text-[22px] font-medium" style="color: var(--color-text)">その他</p>
          <p class="text-[22px] font-bold" style="color: var(--color-text-muted)">10%</p>
        </div>
      </div>
    </div>
  `)}
`, {sec: 'セクション名'})
```
