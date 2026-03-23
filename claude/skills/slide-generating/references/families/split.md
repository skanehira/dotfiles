# Split Family

## text-image（SFlex() を使用）

```javascript
SFlex(n, 'split', 'text-image', `
  <div class="w-[55%] flex flex-col justify-center" style="padding: var(--spacing-slide-padding); padding-top: 8rem">
    <h2 class="text-[48px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-sm)">見出し</h2>
    <p class="text-[26px] leading-relaxed" style="color: var(--color-text)">説明テキスト</p>
  </div>
  <div class="w-[45%] relative">
    <img src="https://placehold.jp/864x1080" alt="説明画像" class="w-full h-full object-cover" />
  </div>
`, {sec: 'セクション名'})
```

反転: 2つのdivの順序を入れ替え。

## two-column

```javascript
S(n, 'split', 'two-column', `
  <h2 class="text-[48px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-lg)">見出し</h2>
  ${VC(`
    <div class="flex" style="gap: var(--spacing-gap-lg)">
      <div class="flex-1">
        <h3 class="text-[32px] font-bold" style="color: var(--color-text); margin-bottom: var(--spacing-gap-sm)">左カラム</h3>
        <p class="text-[24px] leading-relaxed" style="color: var(--color-text)">テキスト</p>
      </div>
      <div class="flex-1">
        <h3 class="text-[32px] font-bold" style="color: var(--color-text); margin-bottom: var(--spacing-gap-sm)">右カラム</h3>
        <p class="text-[24px] leading-relaxed" style="color: var(--color-text)">テキスト</p>
      </div>
    </div>
  `)}
`, {sec: 'セクション名'})
```

## comparison

```javascript
S(n, 'split', 'comparison', `
  <h2 class="text-[48px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-lg)">比較テーマ</h2>
  ${VC(`
    <div class="flex" style="gap: var(--spacing-gap-lg)">
      <div class="flex-1 rounded-2xl" style="background: var(--color-bg-alt); padding: var(--spacing-gap-lg)">
        ${Badge('Before', {bg: 'var(--color-text-muted)'})}
        <h3 class="text-[32px] font-bold" style="color: var(--color-text); margin-top: var(--spacing-gap-md); margin-bottom: var(--spacing-gap-sm)">既存の方法</h3>
        <ul class="text-[24px]" style="color: var(--color-text); display: flex; flex-direction: column; gap: var(--spacing-gap-sm)">
          <li>課題点</li>
        </ul>
      </div>
      <div class="flex-1 rounded-2xl border-2" style="background: var(--color-bg); border-color: var(--color-accent); padding: var(--spacing-gap-lg)">
        ${Badge('After')}
        <h3 class="text-[32px] font-bold" style="color: var(--color-text); margin-top: var(--spacing-gap-md); margin-bottom: var(--spacing-gap-sm)">提案する方法</h3>
        <ul class="text-[24px]" style="color: var(--color-text); display: flex; flex-direction: column; gap: var(--spacing-gap-sm)">
          <li>メリット</li>
        </ul>
      </div>
    </div>
  `)}
`, {sec: 'セクション名'})
```

## qa

```javascript
S(n, 'split', 'qa', `
  <h2 class="text-[48px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-lg)">よくあるご質問</h2>
  ${VC(`
    <div class="flex" style="gap: var(--spacing-gap-lg)">
      <div class="flex-1">
        <div class="flex items-start" style="gap: var(--spacing-gap-sm); margin-bottom: var(--spacing-gap-sm)">
          <span class="text-[40px] font-black" style="color: var(--color-accent)">Q</span>
          <p class="text-[28px] font-bold" style="color: var(--color-text); margin-top: 0.25rem">質問</p>
        </div>
        <div class="flex items-start" style="gap: var(--spacing-gap-sm); margin-top: var(--spacing-gap-sm)">
          <span class="text-[40px] font-black" style="color: var(--color-text-muted)">A</span>
          <p class="text-[24px] leading-relaxed" style="color: var(--color-text); margin-top: 0.5rem">回答</p>
        </div>
      </div>
      <!-- Q&A 2を同様に -->
    </div>
  `)}
`, {sec: 'セクション名'})
```

## capture-zoom（キャプチャ拡大: 画像の一部を拡大表示）

```javascript
SFlex(n, 'split', 'capture-zoom', `
  <!-- 左55%: 全体画像+ハイライト枠 -->
  <div class="w-[55%] flex items-center justify-center relative" style="padding: var(--spacing-slide-padding); padding-top: 8rem">
    <div class="relative">
      <img src="https://placehold.jp/880x560" alt="全体画像" class="rounded-xl" style="max-width: 100%; max-height: 560px; object-fit: contain" />
      <!-- 拡大箇所のハイライト枠（位置・サイズは対象に合わせて調整） -->
      <div class="absolute" style="top: 20%; left: 55%; width: 35%; height: 40%; border: 3px dashed var(--color-accent); border-radius: 8px"></div>
    </div>
  </div>
  <!-- 右45%: 拡大画像+説明テキスト -->
  <div class="w-[45%] flex flex-col justify-center" style="padding: var(--spacing-slide-padding); padding-top: 8rem">
    <div class="rounded-xl overflow-hidden border-2" style="border-color: var(--color-accent); margin-bottom: var(--spacing-gap-md)">
      <img src="https://placehold.jp/640x400" alt="拡大部分" class="w-full object-cover" />
    </div>
    <h3 class="text-[28px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-sm)">注目ポイント</h3>
    <p class="text-[22px] leading-relaxed" style="color: var(--color-text)">拡大部分の説明テキスト。ここに注目すべき詳細を記載する。</p>
  </div>
`, {sec: 'セクション名'})
```

左に全体画像、右に拡大部分のクローズアップ+説明テキスト。全体画像の拡大箇所に破線枠のハイライト（absolute配置のdiv、border-dashed）を重ねる。
