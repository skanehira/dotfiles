# Grid Family

## cards

```javascript
S(n, 'grid', 'cards', `
  ${H('見出し')}
  ${Sub('補足説明')}
  ${VC(`
    <!-- 2〜4カラムに調整可能 -->
    <div class="grid grid-cols-3" style="gap: var(--spacing-gap-md)">
      <div class="rounded-2xl" style="background: var(--color-bg-alt); padding: var(--spacing-gap-md)">
        <div style="margin-bottom: var(--spacing-gap-sm)">${IC('<!-- SVG -->')}</div>
        <h3 class="text-[28px] font-bold" style="color: var(--color-text); margin-bottom: var(--spacing-gap-sm)">タイトル</h3>
        <p class="text-[22px] leading-relaxed" style="color: var(--color-text-muted)">説明</p>
      </div>
      <!-- 他カード同様 -->
    </div>
  `)}
`, {sec: 'セクション名'})
```

## logos

```javascript
S(n, 'grid', 'logos', `
  ${H('導入企業')}
  ${VC(`
    <div class="flex" style="gap: var(--spacing-gap-lg)">
      <div class="flex-1">
        <div style="margin-bottom: var(--spacing-gap-md)">${Badge('カテゴリ名')}</div>
        <div class="grid grid-cols-2" style="gap: var(--spacing-gap-sm)">
          <div class="h-24 rounded-xl flex items-center justify-center" style="background: var(--color-bg-alt); padding: 0 var(--spacing-gap-sm)">
            <img src="https://placehold.jp/200x60" alt="企業名" class="max-h-12 max-w-full object-contain" />
          </div>
        </div>
      </div>
    </div>
  `)}
`, {sec: 'セクション名'})
```

## team-members

```javascript
S(n, 'grid', 'team-members', `
  ${H('チームメンバー')}
  ${Sub('補足テキスト')}
  ${VC(`
    <div class="grid grid-cols-4" style="gap: var(--spacing-gap-lg)">
      <div class="text-center">
        <div class="w-48 h-48 rounded-full mx-auto overflow-hidden" style="background: linear-gradient(135deg, var(--color-primary), var(--color-accent)); margin-bottom: var(--spacing-gap-sm)">
          <img src="https://placehold.jp/192x192" alt="名前" class="w-full h-full object-cover" />
        </div>
        <p class="text-[24px] font-bold" style="color: var(--color-text)">名前</p>
        <p class="text-[18px]" style="color: var(--color-accent)">English Name</p>
        <p class="text-[18px]" style="color: var(--color-text-muted); margin-top: 0.5rem">役職</p>
      </div>
      <!-- 3〜4名推奨 -->
    </div>
  `)}
`, {sec: 'セクション名'})
```

## team-member-1（1名紹介: 写真+プロフィール詳細）

```javascript
SFlex(n, 'grid', 'team-member-1', `
  <!-- 左: 大きな写真 -->
  <div class="w-[40%] h-full">
    <img src="https://placehold.jp/768x1080" alt="名前" class="w-full h-full object-cover" />
  </div>
  <!-- 右: プロフィール詳細 -->
  <div class="w-[60%] flex flex-col justify-center" style="padding: var(--spacing-slide-padding)">
    <p class="text-[56px] font-bold" style="color: var(--color-text); margin-bottom: var(--spacing-gap-sm)">山田 太郎</p>
    <p class="text-[24px]" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-lg)">代表取締役CEO / Co-Founder</p>
    <!-- 経歴テーブル -->
    <table class="text-[20px] w-full" style="border-collapse: collapse">
      <tr>
        <td class="font-bold align-top" style="color: var(--color-text-muted); padding: var(--spacing-gap-sm) var(--spacing-gap-md) var(--spacing-gap-sm) 0; width: 120px; border-bottom: 1px solid var(--color-bg-alt)">2010</td>
        <td style="color: var(--color-text); padding: var(--spacing-gap-sm) 0; border-bottom: 1px solid var(--color-bg-alt)">東京大学工学部卒業</td>
      </tr>
      <tr>
        <td class="font-bold align-top" style="color: var(--color-text-muted); padding: var(--spacing-gap-sm) var(--spacing-gap-md) var(--spacing-gap-sm) 0; border-bottom: 1px solid var(--color-bg-alt)">2010</td>
        <td style="color: var(--color-text); padding: var(--spacing-gap-sm) 0; border-bottom: 1px solid var(--color-bg-alt)">株式会社XXX入社、エンジニアとして従事</td>
      </tr>
      <tr>
        <td class="font-bold align-top" style="color: var(--color-text-muted); padding: var(--spacing-gap-sm) var(--spacing-gap-md) var(--spacing-gap-sm) 0; border-bottom: 1px solid var(--color-bg-alt)">2015</td>
        <td style="color: var(--color-text); padding: var(--spacing-gap-sm) 0; border-bottom: 1px solid var(--color-bg-alt)">当社を共同創業</td>
      </tr>
      <tr>
        <td class="font-bold align-top" style="color: var(--color-text-muted); padding: var(--spacing-gap-sm) var(--spacing-gap-md) var(--spacing-gap-sm) 0">2020</td>
        <td style="color: var(--color-text); padding: var(--spacing-gap-sm) 0">代表取締役CEO就任</td>
      </tr>
    </table>
  </div>
`, {sec: 'セクション名'})
```

## team-member-2（2名紹介: 横並び2カラム）

```javascript
S(n, 'grid', 'team-member-2', `
  ${H('経営チーム')}
  ${VC(`
    <div class="grid grid-cols-2" style="gap: var(--spacing-gap-lg)">
      <!-- メンバー1 -->
      <div class="flex" style="gap: var(--spacing-gap-md)">
        <div class="w-48 h-48 rounded-2xl overflow-hidden flex-shrink-0">
          <img src="https://placehold.jp/192x192" alt="名前" class="w-full h-full object-cover" />
        </div>
        <div>
          <p class="text-[28px] font-bold" style="color: var(--color-text)">山田 太郎</p>
          <p class="text-[18px]" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-sm)">代表取締役CEO</p>
          <p class="text-[18px] leading-relaxed" style="color: var(--color-text-muted)">東京大学卒。XXX社を経て2015年に当社を共同創業。プロダクト開発と事業戦略を統括。</p>
        </div>
      </div>
      <!-- メンバー2 -->
      <div class="flex" style="gap: var(--spacing-gap-md)">
        <div class="w-48 h-48 rounded-2xl overflow-hidden flex-shrink-0">
          <img src="https://placehold.jp/192x192" alt="名前" class="w-full h-full object-cover" />
        </div>
        <div>
          <p class="text-[28px] font-bold" style="color: var(--color-text)">鈴木 花子</p>
          <p class="text-[18px]" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-sm)">取締役CTO</p>
          <p class="text-[18px] leading-relaxed" style="color: var(--color-text-muted)">京都大学大学院修了。YYY社のリードエンジニアを経て2015年に当社を共同創業。技術基盤を統括。</p>
        </div>
      </div>
    </div>
  `)}
`, {sec: 'セクション名'})
```

## achievement-metric（導入実績: 数値押し出し）

```javascript
S(n, 'grid', 'achievement-metric', `
  ${H('導入実績')}
  ${Sub('補足説明')}
  ${VC(`
    <div class="grid grid-cols-3" style="gap: var(--spacing-gap-md)">
      <div class="rounded-2xl" style="background: var(--color-bg-alt); padding: var(--spacing-gap-md)">
        <h3 class="text-[24px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-md)">業界名A</h3>
        <div class="flex items-center" style="gap: var(--spacing-gap-sm); margin-bottom: var(--spacing-gap-sm)">
          <div>
            <p class="text-[16px]" style="color: var(--color-text-muted)">Before</p>
            <p class="text-[32px] font-bold" style="color: var(--color-text-muted)">40%</p>
          </div>
          <svg width="32" height="24" viewBox="0 0 32 24" fill="none"><path d="M0 12H28M28 12L20 4M28 12L20 20" stroke="var(--color-text-muted)" stroke-width="2"/></svg>
          <div>
            <p class="text-[16px]" style="color: var(--color-accent)">After</p>
            <p class="text-[48px] font-black" style="color: var(--color-accent)">92%</p>
          </div>
        </div>
        <p class="text-[16px]" style="color: var(--color-text-muted)">改善ポイントの説明</p>
      </div>
      <div class="rounded-2xl" style="background: var(--color-bg-alt); padding: var(--spacing-gap-md)">
        <h3 class="text-[24px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-md)">業界名B</h3>
        <div class="flex items-center" style="gap: var(--spacing-gap-sm); margin-bottom: var(--spacing-gap-sm)">
          <div>
            <p class="text-[16px]" style="color: var(--color-text-muted)">Before</p>
            <p class="text-[32px] font-bold" style="color: var(--color-text-muted)">120h</p>
          </div>
          <svg width="32" height="24" viewBox="0 0 32 24" fill="none"><path d="M0 12H28M28 12L20 4M28 12L20 20" stroke="var(--color-text-muted)" stroke-width="2"/></svg>
          <div>
            <p class="text-[16px]" style="color: var(--color-accent)">After</p>
            <p class="text-[48px] font-black" style="color: var(--color-accent)">30h</p>
          </div>
        </div>
        <p class="text-[16px]" style="color: var(--color-text-muted)">改善ポイントの説明</p>
      </div>
      <!-- 3枚目のカードも同構造 -->
    </div>
  `)}
`, {sec: 'セクション名'})
```

3カラムのグリッド。各カードに業界名ヘッダー+Before指標→After指標の矢印付き比較。数値を大きく、上昇/下降を色で示す（改善方向=accent色、改善前=text-muted色）。

## achievement-award（導入実績: 月桂冠/No.1バッジ）

```javascript
S(n, 'grid', 'achievement-award', `
  ${H('受賞実績')}
  ${Sub('補足説明')}
  ${VC(`
    <div class="grid grid-cols-3" style="gap: var(--spacing-gap-md); margin-bottom: var(--spacing-gap-lg)">
      <div class="rounded-2xl text-center" style="background: var(--color-bg-alt); padding: var(--spacing-gap-md)">
        <svg width="120" height="80" viewBox="0 0 120 80" fill="none" class="mx-auto" style="margin-bottom: var(--spacing-gap-sm)">
          <path d="M20 70C25 50 35 30 55 20" stroke="var(--color-accent)" stroke-width="2" fill="none"/>
          <path d="M100 70C95 50 85 30 65 20" stroke="var(--color-accent)" stroke-width="2" fill="none"/>
          <ellipse cx="30" cy="55" rx="6" ry="10" fill="none" stroke="var(--color-accent)" stroke-width="1.5" transform="rotate(-20 30 55)"/>
          <ellipse cx="90" cy="55" rx="6" ry="10" fill="none" stroke="var(--color-accent)" stroke-width="1.5" transform="rotate(20 90 55)"/>
          <ellipse cx="38" cy="40" rx="6" ry="10" fill="none" stroke="var(--color-accent)" stroke-width="1.5" transform="rotate(-10 38 40)"/>
          <ellipse cx="82" cy="40" rx="6" ry="10" fill="none" stroke="var(--color-accent)" stroke-width="1.5" transform="rotate(10 82 40)"/>
        </svg>
        <p class="text-[56px] font-black" style="color: var(--color-accent)">No.1</p>
        <p class="text-[20px] font-bold" style="color: var(--color-text); margin-top: var(--spacing-gap-sm)">受賞項目名</p>
        <p class="text-[16px]" style="color: var(--color-text-muted); margin-top: 0.25rem">2024年度</p>
      </div>
      <div class="rounded-2xl text-center" style="background: var(--color-bg-alt); padding: var(--spacing-gap-md)">
        <svg width="120" height="80" viewBox="0 0 120 80" fill="none" class="mx-auto" style="margin-bottom: var(--spacing-gap-sm)">
          <path d="M20 70C25 50 35 30 55 20" stroke="var(--color-accent)" stroke-width="2" fill="none"/>
          <path d="M100 70C95 50 85 30 65 20" stroke="var(--color-accent)" stroke-width="2" fill="none"/>
          <ellipse cx="30" cy="55" rx="6" ry="10" fill="none" stroke="var(--color-accent)" stroke-width="1.5" transform="rotate(-20 30 55)"/>
          <ellipse cx="90" cy="55" rx="6" ry="10" fill="none" stroke="var(--color-accent)" stroke-width="1.5" transform="rotate(20 90 55)"/>
          <ellipse cx="38" cy="40" rx="6" ry="10" fill="none" stroke="var(--color-accent)" stroke-width="1.5" transform="rotate(-10 38 40)"/>
          <ellipse cx="82" cy="40" rx="6" ry="10" fill="none" stroke="var(--color-accent)" stroke-width="1.5" transform="rotate(10 82 40)"/>
        </svg>
        <p class="text-[56px] font-black" style="color: var(--color-accent)">No.1</p>
        <p class="text-[20px] font-bold" style="color: var(--color-text); margin-top: var(--spacing-gap-sm)">受賞項目名</p>
        <p class="text-[16px]" style="color: var(--color-text-muted); margin-top: 0.25rem">2024年度</p>
      </div>
      <!-- 3-4枚目のカードも同構造 -->
    </div>
    <!-- 下部ロゴ一覧 -->
    <div class="flex items-center justify-center" style="gap: var(--spacing-gap-lg)">
      <div class="h-16 rounded-xl flex items-center justify-center" style="background: var(--color-bg-alt); padding: 0 var(--spacing-gap-md)">
        <img src="https://placehold.jp/160x40" alt="メディア名" class="max-h-10 max-w-full object-contain" />
      </div>
      <div class="h-16 rounded-xl flex items-center justify-center" style="background: var(--color-bg-alt); padding: 0 var(--spacing-gap-md)">
        <img src="https://placehold.jp/160x40" alt="メディア名" class="max-h-10 max-w-full object-contain" />
      </div>
      <div class="h-16 rounded-xl flex items-center justify-center" style="background: var(--color-bg-alt); padding: 0 var(--spacing-gap-md)">
        <img src="https://placehold.jp/160x40" alt="メディア名" class="max-h-10 max-w-full object-contain" />
      </div>
    </div>
  `)}
`, {sec: 'セクション名'})
```

3-4カラムのグリッド。各カードに受賞項目名+大きな「No.1」または数値+SVG月桂冠装飾。下部にロゴ一覧。月桂冠はSVGで左右の茎と葉を描画する。
