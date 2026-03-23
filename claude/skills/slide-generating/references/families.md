# Family/Variant テンプレートパターン

## コンテンツ生成の原則

- 1スライド1メッセージ。箇条書きは3〜5項目上限。テキスト過多なら分割
- 見出しは短く、インパクトのある表現にする
- 画像プレースホルダーには適切なサイズとalt属性を指定する

## 厳守ルール

- **カラーコードの直書き禁止**: すべての色は `var(--color-*)` を使う。`#3B82F6`, `text-blue-300` 等のハードコード禁止
- **白テキストは `text-white` のみ例外**: 暗い背景（cover, section-divider）上の白テキストのみ `text-white` を許可
- **Tailwindのカラーユーティリティ禁止**: `text-blue-500`, `bg-gray-100` 等は使わない。すべて `style="color: var(--color-*)"` で書く
- **Tailwindのスペーシングユーティリティ禁止**: `p-20`, `gap-12`, `mb-8` 等は使わない。すべて `style` 属性で `var(--spacing-*)` CSS変数を使う

## 垂直バランスルール

通常スライドのコンテンツ領域は `S()` 関数で自動的に `display: flex; flex-direction: column` が設定される。variant固有のコンテンツは以下の構造で記述すること:

```javascript
S(n, fam, v, `
  ${H('見出し')}
  ${Sub('サブテキスト')}
  ${VC(`<!-- メインコンテンツ（垂直中央配置） -->`)}
`)
```

**必須**: メインコンテンツを `VC()` で囲むこと。これにより見出し下〜フッター上の余白が均等になり、コンテンツが垂直中央に配置される。

**例外**: `SFlex()` を使うスライド（split.text-image等）、`D()` を使うスライド（cover/section-divider）は独自のレイアウトを持つためこのルールは適用しない。

## ベースラインテンプレートと Spatial Style

以下の各 family/variant の例は**ベースライン実装**である。構造の参考として使い、視覚的な表現は `visual-guidelines.md` で定義された Spatial Style に応じて変形すること。

**変形の例:**

- **split（angled エッジ）**: `w-[55%] + w-[45%]` の直線分割を `clip-path: polygon(...)` で斜めカットに変形
- **grid（floating 奥行き）**: カードに `box-shadow: 0 12px 40px rgba(0,0,0,0.12)` + `transform: translateY(-4px)` を追加
- **split（curved エッジ）**: 分割パネルに `border-radius: 0 40px 40px 0` を適用
- **grid（dense 密度）**: `gap` を縮小し、パディングを `3rem` に変更

ベースラインの CSS 値は固定ではない。Spatial Style と全体のトーンに合わせて調整すること。ただし、コンテンツの可読性は維持する（テキスト領域の最小幅 500px、フォントサイズは `quality-checklist.md` の階層に従う）。

---

## テンプレート関数

HTML生成時、`<script>` ブロック内で以下の関数を定義し、スライドを動的に生成する。これによりスライドシェル（ロゴ・フッター・パディング）の繰り返しを排除する。

### 定数

```javascript
const _C = '{会社名}';
const _L = 'assets/logo.svg';
```

### スライドシェル関数

**S(n, fam, v, content, o={})** — 通常スライド（白背景 + ロゴ + フッター）

```javascript
function S(n, fam, v, content, o={}) {
  const bg = o.bg || 'var(--color-bg)';
  return `<section class="slide" data-slide="${n}" data-family="${fam}" data-variant="${v}">
  <div class="w-[1920px] h-[1080px] relative overflow-hidden" style="background: ${bg}; padding: var(--spacing-slide-padding)">
    <div class="absolute top-16 left-20"><img src="${_L}" alt="ロゴ" class="h-10" /></div>
    <div style="margin-top: var(--spacing-gap-lg); display: flex; flex-direction: column; height: calc(100% - 6rem)">
      ${content}
    </div>
    <div class="absolute bottom-8 left-20 text-sm" style="color: var(--color-text-muted)"><span style="margin-right: var(--spacing-gap-sm)">${n}</span><span>${o.sec || ''}</span></div>
    <div class="absolute bottom-8 right-8 text-sm" style="color: var(--color-text-muted)">&copy; ${_C}</div>
  </div></section>`;
}
```

| パラメータ | 説明 |
|-----------|------|
| `n` | スライド番号 |
| `fam` | family名 |
| `v` | variant名 |
| `content` | コンテンツHTML |
| `o.bg` | 背景色（デフォルト: `var(--color-bg)`） |
| `o.sec` | セクション名（フッター表示用） |

**D(n, v, content, o={})** — 暗い背景スライド（family は常に `hero`）

```javascript
function D(n, v, content, o={}) {
  const bg = o.bg || 'linear-gradient(135deg, var(--color-primary), var(--color-accent))';
  return `<section class="slide" data-slide="${n}" data-family="hero" data-variant="${v}">
  <div class="w-[1920px] h-[1080px] relative overflow-hidden" style="background: ${bg}">
    ${content}
    <div class="absolute bottom-8 right-8 text-white/30 text-sm">&copy; ${_C}</div>
  </div></section>`;
}
```

**SFlex(n, fam, v, content, o={})** — 水平フレックススライド（split.text-image用）

```javascript
function SFlex(n, fam, v, content, o={}) {
  const bg = o.bg || 'var(--color-bg)';
  return `<section class="slide" data-slide="${n}" data-family="${fam}" data-variant="${v}">
  <div class="w-[1920px] h-[1080px] relative overflow-hidden flex" style="background: ${bg}">
    <div class="absolute top-16 left-20 z-10"><img src="${_L}" alt="ロゴ" class="h-10" /></div>
    ${content}
    <div class="absolute bottom-8 left-20 text-sm z-10" style="color: var(--color-text-muted)"><span style="margin-right: var(--spacing-gap-sm)">${n}</span><span>${o.sec || ''}</span></div>
    <div class="absolute bottom-8 right-8 text-sm z-10" style="color: var(--color-text-muted)">&copy; ${_C}</div>
  </div></section>`;
}
```

### コンテンツ要素関数

```javascript
// 見出し（h2）
function H(t) {
  return `<h2 class="text-[52px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-sm)">${t}</h2>`;
}

// サブテキスト
function Sub(t) {
  return `<p class="text-[24px]" style="color: var(--color-text-muted); margin-bottom: var(--spacing-gap-lg)">${t}</p>`;
}

// 垂直中央ラッパー
function VC(c) {
  return `<div style="margin-top: auto; margin-bottom: auto">${c}</div>`;
}

// アイコンボックス
function IC(svg) {
  return `<div class="w-16 h-16 rounded-xl flex items-center justify-center text-white" style="background: var(--color-accent)">${svg}</div>`;
}

// バッジ/ラベル
function Badge(t, o={}) {
  const bg = o.bg || 'var(--color-accent)';
  return `<span class="inline-block rounded-full text-[16px] font-bold text-white" style="background: ${bg}; padding: var(--spacing-gap-sm) var(--spacing-gap-sm)">${t}</span>`;
}

// 矢印コネクタ
function Arr() {
  return `<svg width="40" height="24" viewBox="0 0 40 24" fill="none"><path d="M28 0L40 12L28 24M0 12H38" stroke="var(--color-text-muted)" stroke-width="2"/></svg>`;
}

// 画像キャプション（画像の上部中央に配置）
function Cap(label, src, alt, o={}) {
  return `<div class="relative flex flex-col items-center">
    <span class="text-[14px] font-bold rounded-full text-white" style="background: var(--color-primary); padding: 0.25rem var(--spacing-gap-sm); margin-bottom: var(--spacing-gap-sm)">${label}</span>
    <img src="${src}" alt="${alt}" class="rounded-xl shadow-2xl object-contain" style="max-width: ${o.maxW || '880px'}; max-height: ${o.maxH || '620px'};" />
  </div>`;
}
```

### スライド生成パターン

```javascript
document.getElementById('slide-container').innerHTML = [
  D(1, 'cover', `...`),
  D(2, 'section-divider', `...`),
  S(3, 'grid', 'cards', `${H('...')} ${Sub('...')} ${VC(`...`)}`, {sec: '...'}),
  SFlex(4, 'split', 'text-image', `...`, {sec: '...'}),
  // ...
].join('');
```

---

## 1. Hero Family

以下は各variantの **content** 引数のみ記載。

### cover（D() を使用）

```javascript
D(1, 'cover', `
  <div class="absolute top-0 right-0 w-[800px] h-full pointer-events-none opacity-10">
    <svg viewBox="0 0 800 1080" fill="none">
      <circle cx="500" cy="200" r="350" fill="var(--color-bg)" />
      <circle cx="650" cy="700" r="250" fill="var(--color-text-muted)" />
    </svg>
  </div>
  <div class="absolute bottom-32 left-20 max-w-[1200px]">
    <h1 class="text-[96px] font-black leading-[1.1] tracking-tight text-white">タイトル</h1>
    <p class="text-[32px] font-medium text-white/60" style="margin-top: var(--spacing-gap-md)">サブタイトル</p>
  </div>
`)
```

### section-divider（D() を使用）

```javascript
D(2, 'section-divider', `
  <div class="absolute top-12 right-20">
    <span class="text-[280px] font-black text-white/20 leading-none">{番号}</span>
  </div>
  <div class="absolute bottom-32 left-20">
    <h2 class="text-[120px] font-black text-white leading-none">{セクション名}</h2>
  </div>
`)
```

### big-number（S() + VC() を使用）

```javascript
S(n, 'hero', 'big-number', VC(`
  <div class="text-center" style="padding: 0 var(--spacing-slide-padding)">
    <p class="text-[28px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-sm)">ラベル</p>
    <p class="text-[200px] font-black leading-none" style="color: var(--color-text)">
      1,200<span class="text-[80px]">社</span>
    </p>
    <p class="text-[28px]" style="color: var(--color-text-muted); margin-top: var(--spacing-gap-md)">補足説明</p>
  </div>
`))
```

### quote（S() + VC() を使用、背景 `--color-bg-alt`）

```javascript
S(n, 'hero', 'quote', VC(`
  <div class="max-w-[1400px]" style="padding: 0 var(--spacing-slide-padding)">
    <span class="text-[160px] leading-none font-black absolute -top-4 -left-4 opacity-10" style="color: var(--color-accent)">&ldquo;</span>
    <blockquote class="text-[48px] font-medium leading-relaxed" style="color: var(--color-text)">
      引用テキスト
    </blockquote>
    <div class="flex items-center" style="margin-top: var(--spacing-gap-lg); gap: var(--spacing-gap-sm)">
      <img src="https://placehold.jp/80x80" alt="著者" class="w-16 h-16 rounded-full object-cover" />
      <div>
        <p class="text-[24px] font-bold" style="color: var(--color-text)">著者名</p>
        <p class="text-[20px]" style="color: var(--color-text-muted)">肩書き</p>
      </div>
    </div>
  </div>
`), {bg: 'var(--color-bg-alt)'})
```

### closing（S() + VC() を使用）

```javascript
S(n, 'hero', 'closing', VC(`
  <div class="text-center">
    <img src="${_L}" alt="ロゴ" class="h-24 mx-auto" style="margin-bottom: var(--spacing-gap-lg)" />
    <h2 class="text-[56px] font-bold" style="color: var(--color-text)">CTA / タグライン</h2>
    <p class="text-[28px]" style="color: var(--color-text-muted); margin-top: var(--spacing-gap-sm)">連絡先</p>
  </div>
`))
```

---

## 2. Single-Column Family

### bullet-list

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

### text-block

```javascript
S(n, 'single-column', 'text-block', `
  ${H('見出し')}
  <h3 class="text-[36px] font-bold" style="color: var(--color-text); margin-bottom: var(--spacing-gap-md)">サブ見出し</h3>
  <div class="text-[26px] leading-relaxed max-w-[1400px]" style="color: var(--color-text); display: flex; flex-direction: column; gap: var(--spacing-gap-sm)">
    <p>本文テキスト。</p>
  </div>
`, {sec: 'セクション名'})
```

---

## 3. Split Family

### text-image（SFlex() を使用）

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

### two-column

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

### comparison

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

### qa

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

---

## 4. Grid Family

### cards

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

### logos

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

### team-members

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

---

## 5. Sequence Family

### steps

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

### timeline

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

---

## 6. Table Family

### pricing

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

### feature-comparison

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

---

## 7. Diagram Family

### flow

```javascript
S(n, 'diagram', 'flow', `
  ${H('処理フロー')}
  ${Sub('補足説明')}
  ${VC(`
    <div class="flex items-center justify-center" style="gap: var(--spacing-gap-sm)">
      <div class="rounded-xl text-center min-w-[200px] text-white" style="background: var(--color-accent); padding: var(--spacing-gap-sm) var(--spacing-gap-md)">
        <p class="text-[22px] font-bold">入力</p>
      </div>
      ${Arr()}
      <div class="rounded-xl text-center min-w-[200px] border-2" style="background: var(--color-bg-alt); border-color: var(--color-accent); padding: var(--spacing-gap-sm) var(--spacing-gap-md)">
        <p class="text-[22px] font-bold" style="color: var(--color-text)">処理</p>
      </div>
    </div>
  `)}
`, {sec: 'セクション名'})
```

### org-chart

```javascript
S(n, 'diagram', 'org-chart', `
  ${H('組織図')}
  ${VC(`
    <div class="flex flex-col items-center">
      <!-- ルートノード（塗り） -->
      <div class="rounded-xl text-center text-white" style="background: var(--color-accent); padding: var(--spacing-gap-sm) var(--spacing-gap-md)">
        <p class="text-[22px] font-bold">部門名</p>
      </div>
      <div class="w-0.5 h-10" style="background: var(--color-text-muted)"></div>
      <!-- 子ノード -->
      <div class="flex relative" style="gap: var(--spacing-gap-md)">
        <div class="absolute top-0 left-[25%] right-[25%] h-0.5" style="background: var(--color-text-muted)"></div>
        <div class="flex flex-col items-center">
          <div class="w-0.5 h-6" style="background: var(--color-text-muted)"></div>
          <div class="rounded-xl text-center border-2" style="border-color: var(--color-accent); padding: var(--spacing-gap-sm) var(--spacing-gap-md)">
            <p class="text-[20px] font-bold" style="color: var(--color-accent)">チーム名</p>
            <p class="text-[16px]" style="color: var(--color-text-muted); margin-top: 0.25rem">サブ情報</p>
          </div>
        </div>
      </div>
    </div>
  `)}
`, {sec: 'セクション名'})
```

### cycle（循環関係: 2-4要素の円形/四角形サイクル）

```javascript
S(n, 'diagram', 'cycle', `
  ${H('サイクル名')}
  ${Sub('補足説明')}
  ${VC(`
    <div class="flex items-center justify-center" style="gap: var(--spacing-gap-md)">
      <div class="w-48 h-48 rounded-full flex flex-col items-center justify-center text-white text-center" style="background: var(--color-accent)">
        <p class="text-[20px] font-bold">PLAN</p>
        <p class="text-[14px] opacity-80" style="margin-top: 0.25rem">計画</p>
      </div>
      ${Arr()}
      <div class="w-48 h-48 rounded-full flex flex-col items-center justify-center border-2 text-center" style="border-color: var(--color-accent)">
        <p class="text-[20px] font-bold" style="color: var(--color-accent)">DO</p>
        <p class="text-[14px]" style="color: var(--color-text-muted); margin-top: 0.25rem">実行</p>
      </div>
      <!-- 以降のノードも同様 -->
    </div>
  `)}
`, {sec: 'セクション名'})
```

4要素以上は四角ノードで配置。2x2グリッドにして矢印で接続する。

### matrix（2x2マトリクス: SWOT、ポジショニング）

```javascript
S(n, 'diagram', 'matrix', `
  ${H('マトリクスタイトル')}
  ${Sub('補足説明')}
  ${VC(`
    <div class="relative">
      <div class="absolute -top-8 left-1/2 -translate-x-1/2 text-[18px] font-bold" style="color: var(--color-text-muted)">軸ラベル上</div>
      <div class="absolute -left-8 top-1/2 -translate-y-1/2 -rotate-90 text-[18px] font-bold" style="color: var(--color-text-muted)">軸ラベル左</div>
      <div class="grid grid-cols-2 max-w-[900px] mx-auto" style="gap: var(--spacing-gap-sm)">
        <div class="rounded-xl" style="background: var(--color-bg-alt); padding: var(--spacing-gap-md)">
          <h3 class="text-[24px] font-bold" style="color: var(--color-accent); margin-bottom: var(--spacing-gap-sm)">象限1</h3>
          <p class="text-[18px]" style="color: var(--color-text-muted)">説明テキスト</p>
        </div>
        <!-- 象限2-4 も同構造 -->
      </div>
    </div>
  `)}
`, {sec: 'セクション名'})
```

### venn（ベン図: 重なり・共通領域）

```javascript
S(n, 'diagram', 'venn', `
  ${H('ベン図タイトル')}
  ${Sub('補足説明')}
  ${VC(`
    <div class="relative flex items-center justify-center" style="height: 500px">
      <div class="absolute w-[380px] h-[380px] rounded-full opacity-20" style="background: var(--color-accent); left: calc(50% - 260px)"></div>
      <div class="absolute text-[24px] font-bold" style="color: var(--color-text); left: calc(50% - 220px)">要素A</div>
      <div class="absolute w-[380px] h-[380px] rounded-full opacity-20" style="background: var(--color-secondary); left: calc(50% - 120px)"></div>
      <div class="absolute text-[24px] font-bold" style="color: var(--color-text); left: calc(50% + 100px)">要素B</div>
      <div class="absolute text-[20px] font-bold text-center" style="color: var(--color-accent)">共通領域</div>
    </div>
  `)}
`, {sec: 'セクション名'})
```

3円の場合は3つの円を三角形に配置する。

### pyramid（ピラミッド/じょうろ: 階層的な大小関係）

```javascript
S(n, 'diagram', 'pyramid', `
  ${H('ピラミッドタイトル')}
  ${Sub('補足説明')}
  ${VC(`
    <div class="flex flex-col items-center max-w-[800px] mx-auto" style="gap: var(--spacing-gap-sm)">
      <div class="w-[30%] rounded-lg text-center text-white" style="background: var(--color-accent); padding: var(--spacing-gap-sm) 0">
        <p class="text-[20px] font-bold">頂点</p>
        <p class="text-[14px] opacity-80">少数・最重要</p>
      </div>
      <div class="w-[55%] rounded-lg text-center border-2" style="border-color: var(--color-accent); padding: var(--spacing-gap-sm) 0">
        <p class="text-[20px] font-bold" style="color: var(--color-accent)">中間層</p>
        <p class="text-[14px]" style="color: var(--color-text-muted)">中程度</p>
      </div>
      <div class="w-[80%] rounded-lg text-center" style="background: var(--color-bg-alt); padding: var(--spacing-gap-sm) 0">
        <p class="text-[20px] font-bold" style="color: var(--color-text)">基盤層</p>
        <p class="text-[14px]" style="color: var(--color-text-muted)">多数・基礎</p>
      </div>
    </div>
  `)}
`, {sec: 'セクション名'})
```

じょうろ型（逆ピラミッド）は width の順序を反転させる。TAM-SAM-SOM は同心円パターンも可。

### tree（ツリー図: 分解・分類の階層構造）

```javascript
S(n, 'diagram', 'tree', `
  ${H('ツリータイトル')}
  ${VC(`
    <div class="flex flex-col items-center">
      <div class="rounded-xl text-center text-white" style="background: var(--color-accent); padding: var(--spacing-gap-sm) var(--spacing-gap-lg)">
        <p class="text-[24px] font-bold">全体</p>
      </div>
      <div class="w-0.5 h-8" style="background: var(--color-text-muted)"></div>
      <div class="flex relative" style="gap: var(--spacing-gap-lg)">
        <div class="absolute top-0 left-[15%] right-[15%] h-0.5" style="background: var(--color-text-muted)"></div>
        <div class="flex flex-col items-center">
          <div class="w-0.5 h-6" style="background: var(--color-text-muted)"></div>
          <div class="rounded-xl text-center border-2" style="border-color: var(--color-accent); padding: var(--spacing-gap-sm) var(--spacing-gap-md)">
            <p class="text-[18px] font-bold" style="color: var(--color-accent)">分類A</p>
          </div>
          <div class="w-0.5 h-6" style="background: var(--color-text-muted)"></div>
          <div class="text-[16px]" style="color: var(--color-text-muted); display: flex; flex-direction: column; gap: 0.5rem">
            <p>・項目1</p>
            <p>・項目2</p>
          </div>
        </div>
        <div class="flex flex-col items-center">
          <div class="w-0.5 h-6" style="background: var(--color-text-muted)"></div>
          <div class="rounded-xl text-center border-2" style="border-color: var(--color-accent); padding: var(--spacing-gap-sm) var(--spacing-gap-md)">
            <p class="text-[18px] font-bold" style="color: var(--color-accent)">分類B</p>
          </div>
          <div class="w-0.5 h-6" style="background: var(--color-text-muted)"></div>
          <div class="text-[16px]" style="color: var(--color-text-muted); display: flex; flex-direction: column; gap: 0.5rem">
            <p>・項目3</p>
            <p>・項目4</p>
          </div>
        </div>
      </div>
    </div>
  `)}
`, {sec: 'セクション名'})
```

ツリーの深さは最大3レベルまでに抑える。横幅が足りない場合は横型（左→右）に変形する。
