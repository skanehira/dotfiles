# Ranking Family

## bar-ranking

横バーランキング。左に順位番号（大きく）+ 項目名、右に横バー（width比例）+ 数値。1位のバーを `--color-accent`、2位以降を `--color-bg-alt` で差別化。

```javascript
S(n, 'ranking', 'bar-ranking', `
  ${H('人気機能ランキング')}
  ${Sub('2024年度 利用率調査')}
  ${VC(`
    <div class="max-w-[1200px] mx-auto" style="display: flex; flex-direction: column; gap: var(--spacing-gap-md)">
      <!-- 1位（アクセントカラー） -->
      <div class="flex items-center" style="gap: var(--spacing-gap-md)">
        <p class="text-[48px] font-black" style="color: var(--color-accent); width: 60px; text-align: right">1</p>
        <p class="text-[24px] font-bold" style="color: var(--color-text); width: 180px">機能A</p>
        <div class="flex-1 relative" style="height: 44px">
          <div class="absolute inset-y-0 left-0 rounded-r-lg" style="width: 100%; background: var(--color-accent)"></div>
        </div>
        <p class="text-[24px] font-bold" style="color: var(--color-accent); width: 80px">92%</p>
      </div>
      <!-- 2位以降（控えめカラー） -->
      <div class="flex items-center" style="gap: var(--spacing-gap-md)">
        <p class="text-[48px] font-black" style="color: var(--color-text-muted); width: 60px; text-align: right">2</p>
        <p class="text-[24px] font-bold" style="color: var(--color-text); width: 180px">機能B</p>
        <div class="flex-1 relative" style="height: 44px">
          <div class="absolute inset-y-0 left-0 rounded-r-lg" style="width: 78%; background: var(--color-bg-alt)"></div>
        </div>
        <p class="text-[24px] font-bold" style="color: var(--color-text); width: 80px">78%</p>
      </div>
      <div class="flex items-center" style="gap: var(--spacing-gap-md)">
        <p class="text-[48px] font-black" style="color: var(--color-text-muted); width: 60px; text-align: right">3</p>
        <p class="text-[24px] font-bold" style="color: var(--color-text); width: 180px">機能C</p>
        <div class="flex-1 relative" style="height: 44px">
          <div class="absolute inset-y-0 left-0 rounded-r-lg" style="width: 65%; background: var(--color-bg-alt)"></div>
        </div>
        <p class="text-[24px] font-bold" style="color: var(--color-text); width: 80px">65%</p>
      </div>
      <div class="flex items-center" style="gap: var(--spacing-gap-md)">
        <p class="text-[48px] font-black" style="color: var(--color-text-muted); width: 60px; text-align: right">4</p>
        <p class="text-[24px] font-bold" style="color: var(--color-text); width: 180px">機能D</p>
        <div class="flex-1 relative" style="height: 44px">
          <div class="absolute inset-y-0 left-0 rounded-r-lg" style="width: 52%; background: var(--color-bg-alt)"></div>
        </div>
        <p class="text-[24px] font-bold" style="color: var(--color-text); width: 80px">52%</p>
      </div>
      <!-- 5位以降も同様 -->
    </div>
  `)}
`, {sec: 'セクション名'})
```

## table-ranking

テーブル型ランキング。順位/項目名/数値の3列テーブル。1位の行をハイライト。

```javascript
S(n, 'ranking', 'table-ranking', `
  ${H('売上ランキング')}
  ${Sub('2024年度 上半期')}
  ${VC(`
    <table class="w-full text-[24px] max-w-[1200px] mx-auto">
      <thead>
        <tr style="border-bottom: 2px solid var(--color-border)">
          <th class="text-center font-bold" style="color: var(--color-text-muted); width: 80px; padding: var(--spacing-gap-sm) 0">順位</th>
          <th class="text-left font-bold" style="color: var(--color-text-muted); padding: var(--spacing-gap-sm) 0">項目名</th>
          <th class="text-right font-bold" style="color: var(--color-text-muted); width: 160px; padding: var(--spacing-gap-sm) 0">数値</th>
        </tr>
      </thead>
      <tbody>
        <!-- 1位（ハイライト行） -->
        <tr class="rounded-lg" style="background: var(--color-bg-alt); border-bottom: 1px solid var(--color-border)">
          <td class="text-center font-black" style="color: var(--color-accent); padding: var(--spacing-gap-sm) 0; font-size: 32px">1</td>
          <td class="font-bold" style="color: var(--color-text); padding: var(--spacing-gap-sm) 0">項目A</td>
          <td class="text-right font-bold" style="color: var(--color-accent); padding: var(--spacing-gap-sm) 0">¥12,000万</td>
        </tr>
        <!-- 2位以降 -->
        <tr style="border-bottom: 1px solid var(--color-border)">
          <td class="text-center font-bold" style="color: var(--color-text-muted); padding: var(--spacing-gap-sm) 0">2</td>
          <td class="font-medium" style="color: var(--color-text); padding: var(--spacing-gap-sm) 0">項目B</td>
          <td class="text-right font-bold" style="color: var(--color-text); padding: var(--spacing-gap-sm) 0">¥8,500万</td>
        </tr>
        <tr style="border-bottom: 1px solid var(--color-border)">
          <td class="text-center font-bold" style="color: var(--color-text-muted); padding: var(--spacing-gap-sm) 0">3</td>
          <td class="font-medium" style="color: var(--color-text); padding: var(--spacing-gap-sm) 0">項目C</td>
          <td class="text-right font-bold" style="color: var(--color-text); padding: var(--spacing-gap-sm) 0">¥6,200万</td>
        </tr>
        <tr style="border-bottom: 1px solid var(--color-border)">
          <td class="text-center font-bold" style="color: var(--color-text-muted); padding: var(--spacing-gap-sm) 0">4</td>
          <td class="font-medium" style="color: var(--color-text); padding: var(--spacing-gap-sm) 0">項目D</td>
          <td class="text-right font-bold" style="color: var(--color-text); padding: var(--spacing-gap-sm) 0">¥4,800万</td>
        </tr>
        <!-- 行を追加 -->
      </tbody>
    </table>
  `)}
`, {sec: 'セクション名'})
```
