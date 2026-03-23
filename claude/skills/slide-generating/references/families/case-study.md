# Case Study Family

## photo-text（写真+テキスト事例）

```javascript
SFlex(n, 'case-study', 'photo-text', `
  <!-- 左: 写真 -->
  <div class="w-[45%] h-full relative">
    <img src="https://placehold.jp/864x1080" alt="事例写真" class="w-full h-full object-cover" />
    <div class="absolute inset-0" style="background: linear-gradient(to right, transparent 70%, var(--color-bg) 100%)"></div>
  </div>
  <!-- 右: テキスト -->
  <div class="w-[55%] flex flex-col justify-center" style="padding: var(--spacing-slide-padding)">
    ${Badge('導入事例')}
    <h2 class="text-[44px] font-bold" style="color: var(--color-text); margin-top: var(--spacing-gap-md); margin-bottom: var(--spacing-gap-sm)">株式会社サンプル</h2>
    <p class="text-[20px]" style="color: var(--color-text-muted); margin-bottom: var(--spacing-gap-lg)">担当者名 / 役職名</p>
    <!-- 課題 -->
    <div style="margin-bottom: var(--spacing-gap-md)">
      <p class="text-[18px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-sm)">課題</p>
      <p class="text-[20px] leading-relaxed" style="color: var(--color-text)">導入前に抱えていた課題の説明テキスト。具体的な数値や状況を記載。</p>
    </div>
    <!-- 成果 -->
    <div>
      <p class="text-[18px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-sm)">成果</p>
      <div class="flex" style="gap: var(--spacing-gap-md)">
        <div>
          <p class="text-[40px] font-bold" style="color: var(--color-accent)">300%</p>
          <p class="text-[16px]" style="color: var(--color-text-muted)">売上向上</p>
        </div>
        <div>
          <p class="text-[40px] font-bold" style="color: var(--color-secondary)">50%</p>
          <p class="text-[16px]" style="color: var(--color-text-muted)">コスト削減</p>
        </div>
      </div>
    </div>
  </div>
`, {sec: 'セクション名'})
```

## metric-cards（KPIカード事例）

```javascript
S(n, 'case-study', 'metric-cards', `
  ${H('導入事例')}
  ${Sub('各社の導入効果をご紹介します')}
  ${VC(`
    <div class="grid grid-cols-3" style="gap: var(--spacing-gap-md)">
      <!-- 事例カード1 -->
      <div class="rounded-2xl" style="background: var(--color-bg-alt); padding: var(--spacing-gap-md)">
        <p class="text-[24px] font-bold" style="color: var(--color-text); margin-bottom: var(--spacing-gap-md)">株式会社A</p>
        <div style="margin-bottom: var(--spacing-gap-sm)">
          <p class="text-[16px]" style="color: var(--color-text-muted)">指標名</p>
          <div class="flex items-baseline" style="gap: var(--spacing-gap-sm); margin-top: 0.25rem">
            <span class="text-[18px]" style="color: var(--color-text-muted)">Before</span>
            <span class="text-[24px] font-bold" style="color: var(--color-text-muted)">120件/月</span>
            <span class="text-[20px]" style="color: var(--color-accent)">&rarr;</span>
            <span class="text-[18px]" style="color: var(--color-text-muted)">After</span>
            <span class="text-[28px] font-bold" style="color: var(--color-accent)">450件/月</span>
          </div>
        </div>
        <div>
          <p class="text-[16px]" style="color: var(--color-text-muted)">指標名2</p>
          <div class="flex items-baseline" style="gap: var(--spacing-gap-sm); margin-top: 0.25rem">
            <span class="text-[18px]" style="color: var(--color-text-muted)">Before</span>
            <span class="text-[24px] font-bold" style="color: var(--color-text-muted)">40%</span>
            <span class="text-[20px]" style="color: var(--color-accent)">&rarr;</span>
            <span class="text-[18px]" style="color: var(--color-text-muted)">After</span>
            <span class="text-[28px] font-bold" style="color: var(--color-accent)">92%</span>
          </div>
        </div>
      </div>
      <!-- 事例カード2 -->
      <div class="rounded-2xl" style="background: var(--color-bg-alt); padding: var(--spacing-gap-md)">
        <p class="text-[24px] font-bold" style="color: var(--color-text); margin-bottom: var(--spacing-gap-md)">株式会社B</p>
        <div style="margin-bottom: var(--spacing-gap-sm)">
          <p class="text-[16px]" style="color: var(--color-text-muted)">指標名</p>
          <div class="flex items-baseline" style="gap: var(--spacing-gap-sm); margin-top: 0.25rem">
            <span class="text-[18px]" style="color: var(--color-text-muted)">Before</span>
            <span class="text-[24px] font-bold" style="color: var(--color-text-muted)">8時間</span>
            <span class="text-[20px]" style="color: var(--color-accent)">&rarr;</span>
            <span class="text-[18px]" style="color: var(--color-text-muted)">After</span>
            <span class="text-[28px] font-bold" style="color: var(--color-accent)">30分</span>
          </div>
        </div>
        <div>
          <p class="text-[16px]" style="color: var(--color-text-muted)">指標名2</p>
          <div class="flex items-baseline" style="gap: var(--spacing-gap-sm); margin-top: 0.25rem">
            <span class="text-[18px]" style="color: var(--color-text-muted)">Before</span>
            <span class="text-[24px] font-bold" style="color: var(--color-text-muted)">月20件</span>
            <span class="text-[20px]" style="color: var(--color-accent)">&rarr;</span>
            <span class="text-[18px]" style="color: var(--color-text-muted)">After</span>
            <span class="text-[28px] font-bold" style="color: var(--color-accent)">月80件</span>
          </div>
        </div>
      </div>
      <!-- 事例カード3 -->
      <div class="rounded-2xl" style="background: var(--color-bg-alt); padding: var(--spacing-gap-md)">
        <p class="text-[24px] font-bold" style="color: var(--color-text); margin-bottom: var(--spacing-gap-md)">株式会社C</p>
        <div style="margin-bottom: var(--spacing-gap-sm)">
          <p class="text-[16px]" style="color: var(--color-text-muted)">指標名</p>
          <div class="flex items-baseline" style="gap: var(--spacing-gap-sm); margin-top: 0.25rem">
            <span class="text-[18px]" style="color: var(--color-text-muted)">Before</span>
            <span class="text-[24px] font-bold" style="color: var(--color-text-muted)">60%</span>
            <span class="text-[20px]" style="color: var(--color-accent)">&rarr;</span>
            <span class="text-[18px]" style="color: var(--color-text-muted)">After</span>
            <span class="text-[28px] font-bold" style="color: var(--color-accent)">98%</span>
          </div>
        </div>
        <div>
          <p class="text-[16px]" style="color: var(--color-text-muted)">指標名2</p>
          <div class="flex items-baseline" style="gap: var(--spacing-gap-sm); margin-top: 0.25rem">
            <span class="text-[18px]" style="color: var(--color-text-muted)">Before</span>
            <span class="text-[24px] font-bold" style="color: var(--color-text-muted)">¥500万</span>
            <span class="text-[20px]" style="color: var(--color-accent)">&rarr;</span>
            <span class="text-[18px]" style="color: var(--color-text-muted)">After</span>
            <span class="text-[28px] font-bold" style="color: var(--color-accent)">¥50万</span>
          </div>
        </div>
      </div>
    </div>
  `)}
`, {sec: 'セクション名'})
```
