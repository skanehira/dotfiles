# Company Profile Family

## standard（SFlex() を使用）

ロゴ+定義リスト型。左にロゴ、右に会社名/所在地/代表/設立/事業のテーブル。

```javascript
SFlex(n, 'company-profile', 'standard', `
  <div class="w-[40%] flex items-center justify-center" style="background: var(--color-bg-alt)">
    <img src="${_L}" alt="ロゴ" class="max-w-[280px]" />
  </div>
  <div class="w-[60%] flex flex-col justify-center" style="padding: var(--spacing-slide-padding); padding-top: 8rem">
    <h2 class="text-[48px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-lg)">会社概要</h2>
    <table class="text-[24px] w-full">
      <tbody>
        <tr style="border-bottom: 1px solid var(--color-border)">
          <td class="font-bold" style="color: var(--color-text-muted); width: 30%; padding: var(--spacing-gap-sm) 0">会社名</td>
          <td style="color: var(--color-text); padding: var(--spacing-gap-sm) 0">株式会社サンプル</td>
        </tr>
        <tr style="border-bottom: 1px solid var(--color-border)">
          <td class="font-bold" style="color: var(--color-text-muted); padding: var(--spacing-gap-sm) 0">所在地</td>
          <td style="color: var(--color-text); padding: var(--spacing-gap-sm) 0">東京都渋谷区</td>
        </tr>
        <tr style="border-bottom: 1px solid var(--color-border)">
          <td class="font-bold" style="color: var(--color-text-muted); padding: var(--spacing-gap-sm) 0">代表</td>
          <td style="color: var(--color-text); padding: var(--spacing-gap-sm) 0">代表者名</td>
        </tr>
        <tr style="border-bottom: 1px solid var(--color-border)">
          <td class="font-bold" style="color: var(--color-text-muted); padding: var(--spacing-gap-sm) 0">設立</td>
          <td style="color: var(--color-text); padding: var(--spacing-gap-sm) 0">2020年1月</td>
        </tr>
        <tr>
          <td class="font-bold" style="color: var(--color-text-muted); padding: var(--spacing-gap-sm) 0">事業内容</td>
          <td style="color: var(--color-text); padding: var(--spacing-gap-sm) 0">事業の説明</td>
        </tr>
      </tbody>
    </table>
  </div>
`, {sec: '会社概要'})
```

## text-only

テキストのみ定義リスト型。ロゴなし、項目名+値の2列テーブル。項目が多い場合向け。

```javascript
S(n, 'company-profile', 'text-only', `
  ${H('会社概要')}
  ${VC(`
    <table class="text-[24px] w-full max-w-[1200px] mx-auto">
      <tbody>
        <tr style="border-bottom: 1px solid var(--color-border)">
          <td class="font-bold" style="color: var(--color-text-muted); width: 25%; padding: var(--spacing-gap-sm) 0">会社名</td>
          <td style="color: var(--color-text); padding: var(--spacing-gap-sm) 0">株式会社サンプル</td>
        </tr>
        <tr style="border-bottom: 1px solid var(--color-border)">
          <td class="font-bold" style="color: var(--color-text-muted); padding: var(--spacing-gap-sm) 0">所在地</td>
          <td style="color: var(--color-text); padding: var(--spacing-gap-sm) 0">東京都渋谷区</td>
        </tr>
        <tr style="border-bottom: 1px solid var(--color-border)">
          <td class="font-bold" style="color: var(--color-text-muted); padding: var(--spacing-gap-sm) 0">代表</td>
          <td style="color: var(--color-text); padding: var(--spacing-gap-sm) 0">代表者名</td>
        </tr>
        <tr style="border-bottom: 1px solid var(--color-border)">
          <td class="font-bold" style="color: var(--color-text-muted); padding: var(--spacing-gap-sm) 0">設立</td>
          <td style="color: var(--color-text); padding: var(--spacing-gap-sm) 0">2020年1月</td>
        </tr>
        <tr style="border-bottom: 1px solid var(--color-border)">
          <td class="font-bold" style="color: var(--color-text-muted); padding: var(--spacing-gap-sm) 0">資本金</td>
          <td style="color: var(--color-text); padding: var(--spacing-gap-sm) 0">1,000万円</td>
        </tr>
        <tr style="border-bottom: 1px solid var(--color-border)">
          <td class="font-bold" style="color: var(--color-text-muted); padding: var(--spacing-gap-sm) 0">従業員数</td>
          <td style="color: var(--color-text); padding: var(--spacing-gap-sm) 0">50名</td>
        </tr>
        <tr>
          <td class="font-bold" style="color: var(--color-text-muted); padding: var(--spacing-gap-sm) 0">事業内容</td>
          <td style="color: var(--color-text); padding: var(--spacing-gap-sm) 0">事業の説明</td>
        </tr>
      </tbody>
    </table>
  `)}
`, {sec: '会社概要'})
```

## with-clients

会社概要+導入企業ロゴ入り。上半分に概要テーブル、下半分にロゴグリッド。

```javascript
S(n, 'company-profile', 'with-clients', `
  ${H('会社概要')}
  ${VC(`
    <div style="display: flex; flex-direction: column; gap: var(--spacing-gap-lg)">
      <table class="text-[22px] w-full max-w-[1200px] mx-auto">
        <tbody>
          <tr style="border-bottom: 1px solid var(--color-border)">
            <td class="font-bold" style="color: var(--color-text-muted); width: 25%; padding: var(--spacing-gap-sm) 0">会社名</td>
            <td style="color: var(--color-text); padding: var(--spacing-gap-sm) 0">株式会社サンプル</td>
          </tr>
          <tr style="border-bottom: 1px solid var(--color-border)">
            <td class="font-bold" style="color: var(--color-text-muted); padding: var(--spacing-gap-sm) 0">設立</td>
            <td style="color: var(--color-text); padding: var(--spacing-gap-sm) 0">2020年1月</td>
          </tr>
          <tr>
            <td class="font-bold" style="color: var(--color-text-muted); padding: var(--spacing-gap-sm) 0">事業内容</td>
            <td style="color: var(--color-text); padding: var(--spacing-gap-sm) 0">事業の説明</td>
          </tr>
        </tbody>
      </table>
      <div>
        <p class="text-[22px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-sm)">導入企業</p>
        <div class="grid grid-cols-4" style="gap: var(--spacing-gap-sm)">
          <div class="h-20 rounded-xl flex items-center justify-center" style="background: var(--color-bg-alt); padding: 0 var(--spacing-gap-sm)">
            <img src="https://placehold.jp/160x48" alt="企業名" class="max-h-10 max-w-full object-contain" />
          </div>
          <div class="h-20 rounded-xl flex items-center justify-center" style="background: var(--color-bg-alt); padding: 0 var(--spacing-gap-sm)">
            <img src="https://placehold.jp/160x48" alt="企業名" class="max-h-10 max-w-full object-contain" />
          </div>
          <div class="h-20 rounded-xl flex items-center justify-center" style="background: var(--color-bg-alt); padding: 0 var(--spacing-gap-sm)">
            <img src="https://placehold.jp/160x48" alt="企業名" class="max-h-10 max-w-full object-contain" />
          </div>
          <div class="h-20 rounded-xl flex items-center justify-center" style="background: var(--color-bg-alt); padding: 0 var(--spacing-gap-sm)">
            <img src="https://placehold.jp/160x48" alt="企業名" class="max-h-10 max-w-full object-contain" />
          </div>
          <!-- ロゴ数に応じて追加 -->
        </div>
      </div>
    </div>
  `)}
`, {sec: '会社概要'})
```
