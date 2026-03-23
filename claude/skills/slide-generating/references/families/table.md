# Table Family

## pricing

並列カードは**全て同じ構造**にすること（バッジ・ボーダー色・パディング等を揃える）。`max-w-*` で幅を制限する場合は `mx-auto` で中央配置すること。

```javascript
S(n, 'table', 'pricing', `
  ${H('料金プラン')}
  ${VC(`
    <div class="flex" style="gap: var(--spacing-gap-lg)">
      <!-- プランカード（全カード同じ構造にする） -->
      <div class="flex-1 rounded-2xl border-2" style="border-color: var(--color-border); background: var(--color-bg); padding: var(--spacing-gap-lg)">
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
  `)}
`, {sec: 'セクション名'})
```

## feature-comparison

```javascript
S(n, 'table', 'feature-comparison', `
  ${H('機能比較')}
  ${VC(`
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
  `)}
`, {sec: 'セクション名'})
```

## data-table（汎用データテーブル: 定義リスト型）

```javascript
S(n, 'table', 'data-table', `
  ${H('項目一覧タイトル')}
  ${VC(`
    <table class="w-full text-[22px]" style="border-collapse: collapse; max-width: 1200px; margin: 0 auto">
      <tbody>
        <tr style="border-bottom: 1px solid var(--color-border)">
          <td class="font-bold" style="color: var(--color-text); background: var(--color-bg-alt); width: 30%; padding: var(--spacing-gap-sm) var(--spacing-gap-md)">項目名A</td>
          <td style="color: var(--color-text); padding: var(--spacing-gap-sm) var(--spacing-gap-md)">値の説明テキスト</td>
        </tr>
        <tr style="border-bottom: 1px solid var(--color-border)">
          <td class="font-bold" style="color: var(--color-text); background: var(--color-bg-alt); padding: var(--spacing-gap-sm) var(--spacing-gap-md)">項目名B</td>
          <td style="color: var(--color-text); padding: var(--spacing-gap-sm) var(--spacing-gap-md)">値の説明テキスト</td>
        </tr>
        <tr style="border-bottom: 1px solid var(--color-border)">
          <td class="font-bold" style="color: var(--color-text); background: var(--color-bg-alt); padding: var(--spacing-gap-sm) var(--spacing-gap-md)">項目名C</td>
          <td style="color: var(--color-text); padding: var(--spacing-gap-sm) var(--spacing-gap-md)">値の説明テキスト</td>
        </tr>
        <!-- 必要に応じて行を追加 -->
      </tbody>
    </table>
  `)}
`, {sec: 'セクション名'})
```

左カラムにラベル（太字、bg-alt背景）、右カラムに値。table要素で実装。導入条件、仕様一覧など項目名+値の繰り返しに使う。

## overlap（重複テーブル: 共有ヘッダー）

```javascript
S(n, 'table', 'overlap', `
  ${H('重複テーブルタイトル')}
  ${VC(`
    <table class="w-full text-[22px]" style="border-collapse: collapse; max-width: 1200px; margin: 0 auto">
      <thead>
        <tr>
          <th class="text-center text-white font-bold" style="background: var(--color-accent); padding: var(--spacing-gap-sm) var(--spacing-gap-md); width: 50%">カテゴリA</th>
          <th class="text-center text-white font-bold" style="background: var(--color-accent); padding: var(--spacing-gap-sm) var(--spacing-gap-md); width: 50%">カテゴリB</th>
        </tr>
      </thead>
      <tbody>
        <tr style="border-bottom: 1px solid var(--color-border)">
          <td style="color: var(--color-text); padding: var(--spacing-gap-sm) var(--spacing-gap-md)">カテゴリA専用の項目</td>
          <td style="color: var(--color-text); padding: var(--spacing-gap-sm) var(--spacing-gap-md)">カテゴリB専用の項目</td>
        </tr>
        <tr style="border-bottom: 1px solid var(--color-border)">
          <td style="color: var(--color-text); padding: var(--spacing-gap-sm) var(--spacing-gap-md)">カテゴリA専用の項目</td>
          <td style="color: var(--color-text); padding: var(--spacing-gap-sm) var(--spacing-gap-md)">カテゴリB専用の項目</td>
        </tr>
        <!-- カテゴリをまたぐ項目 -->
        <tr style="border-bottom: 1px solid var(--color-border)">
          <td colspan="2" class="text-center font-bold" style="color: var(--color-accent); background: var(--color-bg-alt); padding: var(--spacing-gap-sm) var(--spacing-gap-md)">両カテゴリ共通の項目</td>
        </tr>
        <tr style="border-bottom: 1px solid var(--color-border)">
          <td style="color: var(--color-text); padding: var(--spacing-gap-sm) var(--spacing-gap-md)">カテゴリA専用の項目</td>
          <td style="color: var(--color-text); padding: var(--spacing-gap-sm) var(--spacing-gap-md)">カテゴリB専用の項目</td>
        </tr>
      </tbody>
    </table>
  `)}
`, {sec: 'セクション名'})
```

2列のヘッダー（カテゴリ）の下に、ヘッダーをまたぐ項目がある場合のテーブル。colspanを使って1つの項目が複数カテゴリにまたがることを表現する。
