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

| パラメータ | 説明                                    |
| ---------- | --------------------------------------- |
| `n`        | スライド番号                            |
| `fam`      | family名                                |
| `v`        | variant名                               |
| `content`  | コンテンツHTML                          |
| `o.bg`     | 背景色（デフォルト: `var(--color-bg)`） |
| `o.sec`    | セクション名（フッター表示用）          |

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

## Family別テンプレート

各familyのvariant例は個別ファイルに分割されている。スライド生成時に該当familyのファイルを参照すること。

| Family          | ファイル                      | Variants                                            |
| --------------- | ----------------------------- | --------------------------------------------------- |
| hero            | `families/hero.md`            | cover, section-divider, big-number, quote, closing  |
| single-column   | `families/single-column.md`   | bullet-list, text-block                             |
| split           | `families/split.md`           | text-image, two-column, comparison, qa, capture-zoom |
| grid            | `families/grid.md`            | cards, logos, team-members, team-member-1, team-member-2, achievement-metric, achievement-award |
| sequence        | `families/sequence.md`        | steps, timeline, gantt                              |
| table           | `families/table.md`           | pricing, feature-comparison, data-table, overlap    |
| diagram         | `families/diagram.md`         | flow, org-chart, cycle, matrix, venn, pyramid, tree, concentric, mutual, staircase, scale-compare, box-flow |
| toc             | `families/toc.md`             | list, grouped, circle                               |
| company-profile | `families/company-profile.md` | standard, text-only, with-clients                   |
| funnel          | `families/funnel.md`          | funnel, funnel-bar                                  |
| chart           | `families/chart.md`           | bar-vertical, bar-horizontal, pie-simple            |
| ranking         | `families/ranking.md`         | bar-ranking, table-ranking                          |
| formula         | `families/formula.md`         | equation, multiply, addition                        |
| case-study      | `families/case-study.md`      | photo-text, metric-cards                            |
