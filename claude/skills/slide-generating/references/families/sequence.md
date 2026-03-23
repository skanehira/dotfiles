# Sequence Family

## steps

```javascript
S(n, 'sequence', 'steps', `
  ${H('導入の流れ')}
  ${Sub('補足説明')}
  ${VC(`
    <div class="flex items-start" style="gap: var(--spacing-gap-sm)">
      <div class="flex-1 text-center">
        <div class="w-20 h-20 rounded-full flex items-center justify-center mx-auto text-[32px] font-black text-white" style="background: var(--color-accent)">1</div>
        <h3 class="text-[26px] font-bold" style="color: var(--color-text); margin-top: var(--spacing-gap-sm); margin-bottom: var(--spacing-gap-sm)">ステップ名</h3>
        <p class="text-[20px]" style="color: var(--color-text-muted)">説明</p>
      </div>
      ${Arr()}
      <!-- 3〜5ステップ推奨 -->
    </div>
  `)}
`, {sec: 'セクション名'})
```

## timeline

```javascript
S(n, 'sequence', 'timeline', `
  <div class="flex" style="gap: var(--spacing-gap-lg)">
    <div class="w-[35%]">
      <h2 class="text-[48px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-sm)">沿革</h2>
      <p class="text-[24px] leading-relaxed" style="color: var(--color-text)">説明テキスト</p>
    </div>
    <div class="flex-1 relative">
      <div class="absolute left-6 top-0 bottom-0 w-0.5" style="background: var(--color-accent)"></div>
      <div style="display: flex; flex-direction: column; gap: var(--spacing-gap-md)">
        <div class="flex items-start relative" style="gap: var(--spacing-gap-md)">
          <div class="w-12 h-12 rounded-full shrink-0 flex items-center justify-center z-10 text-white text-[14px] font-bold" style="background: var(--color-accent)">&bull;</div>
          <div>
            <p class="text-[22px] font-bold" style="color: var(--color-accent)">2020年</p>
            <p class="text-[22px] font-bold" style="color: var(--color-text); margin-top: 0.25rem">イベント名</p>
            <p class="text-[18px]" style="color: var(--color-text-muted); margin-top: 0.25rem">説明</p>
          </div>
        </div>
      </div>
    </div>
  </div>
`, {sec: 'セクション名'})
```

## gantt（ガントチャート型スケジュール）

```javascript
S(n, 'sequence', 'gantt', `
  ${H('スケジュール')}
  ${Sub('補足説明')}
  ${VC(`
    <table class="w-full text-[20px]" style="border-collapse: collapse">
      <thead>
        <tr style="border-bottom: 2px solid var(--color-border)">
          <th class="text-left font-bold" style="color: var(--color-text); width: 22%; padding: var(--spacing-gap-sm) 0">タスク</th>
          <th class="text-left font-bold" style="color: var(--color-text-muted); width: 12%; padding: var(--spacing-gap-sm) 0">担当</th>
          <th class="text-left font-bold" style="color: var(--color-text-muted); width: 16%; padding: var(--spacing-gap-sm) 0">期間</th>
          <th class="font-bold" style="color: var(--color-text-muted); width: 50%; padding: var(--spacing-gap-sm) 0">進捗</th>
        </tr>
      </thead>
      <tbody>
        <tr style="border-bottom: 1px solid var(--color-border)">
          <td class="font-medium" style="color: var(--color-text); padding: var(--spacing-gap-sm) 0">要件定義</td>
          <td style="color: var(--color-text-muted); padding: var(--spacing-gap-sm) 0">チームA</td>
          <td style="color: var(--color-text-muted); padding: var(--spacing-gap-sm) 0">1月〜2月</td>
          <td style="padding: var(--spacing-gap-sm) 0">
            <div class="relative h-8 rounded-full" style="background: var(--color-bg-alt)">
              <div class="absolute top-0 left-0 h-full rounded-full" style="background: var(--color-accent); width: 30%"></div>
            </div>
          </td>
        </tr>
        <tr style="border-bottom: 1px solid var(--color-border)">
          <td class="font-medium" style="color: var(--color-text); padding: var(--spacing-gap-sm) 0">設計</td>
          <td style="color: var(--color-text-muted); padding: var(--spacing-gap-sm) 0">チームB</td>
          <td style="color: var(--color-text-muted); padding: var(--spacing-gap-sm) 0">2月〜4月</td>
          <td style="padding: var(--spacing-gap-sm) 0">
            <div class="relative h-8 rounded-full" style="background: var(--color-bg-alt)">
              <div class="absolute top-0 h-full rounded-full" style="background: var(--color-secondary); width: 40%; left: 15%"></div>
            </div>
          </td>
        </tr>
        <tr style="border-bottom: 1px solid var(--color-border)">
          <td class="font-medium" style="color: var(--color-text); padding: var(--spacing-gap-sm) 0">実装</td>
          <td style="color: var(--color-text-muted); padding: var(--spacing-gap-sm) 0">チームC</td>
          <td style="color: var(--color-text-muted); padding: var(--spacing-gap-sm) 0">4月〜8月</td>
          <td style="padding: var(--spacing-gap-sm) 0">
            <div class="relative h-8 rounded-full" style="background: var(--color-bg-alt)">
              <div class="absolute top-0 h-full rounded-full" style="background: var(--color-accent); width: 50%; left: 30%"></div>
            </div>
          </td>
        </tr>
        <tr style="border-bottom: 1px solid var(--color-border)">
          <td class="font-medium" style="color: var(--color-text); padding: var(--spacing-gap-sm) 0">テスト</td>
          <td style="color: var(--color-text-muted); padding: var(--spacing-gap-sm) 0">チームD</td>
          <td style="color: var(--color-text-muted); padding: var(--spacing-gap-sm) 0">8月〜10月</td>
          <td style="padding: var(--spacing-gap-sm) 0">
            <div class="relative h-8 rounded-full" style="background: var(--color-bg-alt)">
              <div class="absolute top-0 h-full rounded-full" style="background: var(--color-secondary); width: 25%; left: 65%"></div>
            </div>
          </td>
        </tr>
        <!-- 行を追加可能 -->
      </tbody>
    </table>
  `)}
`, {sec: 'セクション名'})
```

テーブル型のスケジュール。左カラムにタスク名+担当、中央に日程テキスト、右に簡易バー（width%+left%で開始位置と長さを表現）。バーの位置と幅で期間の重なりを視覚化する。
