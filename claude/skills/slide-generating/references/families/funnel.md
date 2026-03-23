# Funnel Family

既存の diagram.pyramid を拡張するリッチ版。`clip-path: polygon(...)` で台形を作り、ファネル図形を表現する。

## funnel

逆三角形ファネル + 左ラベル + 右説明テキスト。中央にファネル図形（幅が段階的に縮小）、左にラベル、右に各段の説明テキスト。

```javascript
S(n, 'funnel', 'funnel', `
  ${H('ファネル分析')}
  ${Sub('各段階の詳細')}
  ${VC(`
    <div class="flex flex-col items-center" style="gap: var(--spacing-gap-sm)">
      <!-- 段1（最上段・最も幅広） -->
      <div class="flex items-center w-full max-w-[1200px]" style="gap: var(--spacing-gap-md)">
        <p class="text-[20px] font-bold text-right" style="color: var(--color-text-muted); width: 140px">潜在層</p>
        <div class="flex-1 text-center text-white" style="width: 90%; clip-path: polygon(3% 0, 97% 0, 93% 100%, 7% 100%); background: var(--color-accent); padding: var(--spacing-gap-sm) 0">
          <p class="text-[22px] font-bold">10,000人</p>
        </div>
        <p class="text-[18px]" style="color: var(--color-text); width: 280px">広告・SNSからの流入</p>
      </div>
      <!-- 段2 -->
      <div class="flex items-center w-full max-w-[1200px]" style="gap: var(--spacing-gap-md)">
        <p class="text-[20px] font-bold text-right" style="color: var(--color-text-muted); width: 140px">準顕在層</p>
        <div class="flex-1 text-center text-white" style="width: 70%; clip-path: polygon(5% 0, 95% 0, 90% 100%, 10% 100%); background: var(--color-secondary); padding: var(--spacing-gap-sm) 0; max-width: 75%; margin: 0 auto">
          <p class="text-[22px] font-bold">3,000人</p>
        </div>
        <p class="text-[18px]" style="color: var(--color-text); width: 280px">資料DL・問い合わせ</p>
      </div>
      <!-- 段3 -->
      <div class="flex items-center w-full max-w-[1200px]" style="gap: var(--spacing-gap-md)">
        <p class="text-[20px] font-bold text-right" style="color: var(--color-text-muted); width: 140px">顕在層</p>
        <div class="flex-1 text-center text-white" style="width: 50%; clip-path: polygon(8% 0, 92% 0, 85% 100%, 15% 100%); background: var(--color-primary); padding: var(--spacing-gap-sm) 0; max-width: 55%; margin: 0 auto">
          <p class="text-[22px] font-bold">500人</p>
        </div>
        <p class="text-[18px]" style="color: var(--color-text); width: 280px">商談・デモ実施</p>
      </div>
      <!-- 段4（最下段・最も幅狭） -->
      <div class="flex items-center w-full max-w-[1200px]" style="gap: var(--spacing-gap-md)">
        <p class="text-[20px] font-bold text-right" style="color: var(--color-text-muted); width: 140px">成約</p>
        <div class="flex-1 text-center text-white" style="width: 30%; clip-path: polygon(10% 0, 90% 0, 80% 100%, 20% 100%); background: var(--color-accent); padding: var(--spacing-gap-sm) 0; max-width: 35%; margin: 0 auto">
          <p class="text-[22px] font-bold">100人</p>
        </div>
        <p class="text-[18px]" style="color: var(--color-text); width: 280px">契約・導入</p>
      </div>
    </div>
  `)}
`, {sec: 'セクション名'})
```

## funnel-bar

ファネル + 右端の縦バー。ファネル本体の右側に `writing-mode: vertical-rl` の縦テキストバーを配置。

```javascript
S(n, 'funnel', 'funnel-bar', `
  ${H('マーケティングファネル')}
  ${Sub('各フェーズの推移')}
  ${VC(`
    <div class="flex" style="gap: var(--spacing-gap-md)">
      <!-- ファネル本体 -->
      <div class="flex-1 flex flex-col items-center" style="gap: var(--spacing-gap-sm)">
        <div class="text-center text-white" style="width: 90%; clip-path: polygon(3% 0, 97% 0, 93% 100%, 7% 100%); background: var(--color-accent); padding: var(--spacing-gap-sm) 0">
          <p class="text-[22px] font-bold">認知</p>
          <p class="text-[16px] opacity-80">10,000</p>
        </div>
        <div class="text-center text-white" style="width: 70%; clip-path: polygon(5% 0, 95% 0, 90% 100%, 10% 100%); background: var(--color-secondary); padding: var(--spacing-gap-sm) 0">
          <p class="text-[22px] font-bold">興味</p>
          <p class="text-[16px] opacity-80">5,000</p>
        </div>
        <div class="text-center text-white" style="width: 50%; clip-path: polygon(8% 0, 92% 0, 85% 100%, 15% 100%); background: var(--color-primary); padding: var(--spacing-gap-sm) 0">
          <p class="text-[22px] font-bold">検討</p>
          <p class="text-[16px] opacity-80">1,500</p>
        </div>
        <div class="text-center text-white" style="width: 35%; clip-path: polygon(10% 0, 90% 0, 80% 100%, 20% 100%); background: var(--color-accent); padding: var(--spacing-gap-sm) 0">
          <p class="text-[22px] font-bold">成約</p>
          <p class="text-[16px] opacity-80">300</p>
        </div>
      </div>
      <!-- 縦バー -->
      <div class="flex items-center justify-center rounded-xl text-white" style="background: var(--color-accent); width: 60px; writing-mode: vertical-rl; text-orientation: mixed; padding: var(--spacing-gap-md) 0">
        <p class="text-[20px] font-bold tracking-widest">コンバージョン率 3%</p>
      </div>
    </div>
  `)}
`, {sec: 'セクション名'})
```
