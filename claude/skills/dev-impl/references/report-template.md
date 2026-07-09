# dev-impl HTML レポート テンプレート参照

dev-impl の Step 7 で生成する `docs/dev-impl-reports/${run_id}.html` の構造とテーマ定義のリファレンス。

実装方式: **単一 HTML ファイル / Tailwind CDN / CSS 変数によるテーマ / 軽量 JS でインタラクション**。データ (JSONL の中身) は HTML 生成時に inline JSON として埋め込み、ブラウザでは fetch 不要。

## 出力先

- ファイルパス: `docs/dev-impl-reports/${run_id}.html`
- `run_id` 形式: `YYYYMMDD-HHMMSS` (例 `20260630-100023`)
- 生成後 `git add` + `git commit` でリポジトリ管理対象に含める (PR レビューやチーム共有に使えるため)

## テーマ CSS 変数

```css
:root {
  --bg: #fafafa;
  --bg-card: #ffffff;
  --fg: #1a1a1a;
  --fg-muted: #6b7280;
  --border: #e5e7eb;

  --severity-info: #3b82f6;       /* blue: 通常進捗 */
  --severity-warn: #f59e0b;       /* amber: 注意 */
  --severity-error: #ef4444;      /* red: 致命 */

  --p1-bg: #fef3c7;               /* amber-100: P1 TODO 軽微 */
  --p1-fg: #92400e;
  --p2-bg: #fed7aa;               /* orange-200: P2 詳細設計の不足 */
  --p2-fg: #9a3412;
  --p3-bg: #fecaca;               /* red-200: P3 概要破綻 */
  --p3-fg: #991b1b;
  --poc-bg: #dbeafe;              /* blue-100: 技術調査 */
  --poc-fg: #1e40af;
  --goal-met: #16a34a;            /* green-600 */
  --goal-unmet: #dc2626;          /* red-600 */
  --goal-pending: #6b7280;        /* gray-500 (手動確認待ち) */
}
```

ダークモードは今は対応しない (将来 `@media (prefers-color-scheme: dark)` を追加余地)。

## HTML 骨組み

```html
<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="UTF-8">
<title>dev-impl report ${run_id}</title>
<script src="https://cdn.tailwindcss.com"></script>
<style>:root { /* テーマ CSS 変数 (上記) */ }</style>
</head>
<body class="min-h-screen" style="background: var(--bg); color: var(--fg);">

<main class="max-w-5xl mx-auto p-8 space-y-8">
  <!-- Section 1: Header -->
  <!-- Section 2: Summary -->
  <!-- Section 3: Phase Timeline -->
  <!-- Section 4: Decisions (P1/P2/P3) -->
  <!-- Section 4.5: Review Low/Medium Findings -->
  <!-- Section 5: PoC Results -->
  <!-- Section 6: Goal Verification -->
  <!-- Section 7: Footer -->
</main>

<script>
// 行クリックで <details> 展開 / aria 属性 / その他軽量インタラクション
</script>
</body>
</html>
```

## セクション 1: Header

```html
<header class="border-b pb-6" style="border-color: var(--border);">
  <h1 class="text-2xl font-semibold">dev-impl report</h1>
  <dl class="mt-3 grid grid-cols-2 gap-x-6 gap-y-1 text-sm" style="color: var(--fg-muted);">
    <dt>run_id</dt><dd class="font-mono">${run_id}</dd>
    <dt>開始</dt><dd class="font-mono">${start_at}</dd>
    <dt>終了</dt><dd class="font-mono">${end_at} (${duration})</dd>
    <dt>SHA</dt><dd class="font-mono">${start_sha} → ${end_sha}</dd>
  </dl>
</header>
```

## セクション 2: 全体サマリ

サマリカードを横並びに 5 枚 (Tailwind grid):

| ラベル | 値 | 色 |
|---|---|---|
| フェーズ完了 | `${completed}/${total}` | info |
| P1 修正 | `${p1_count} 回` | p1 (amber) |
| P2 修正 | `${p2_count} 回` | p2 (orange) |
| P3 停止 | `${p3_count} 回 (停止 ${stopped ? "あり" : "なし"})` | p3 (red) |
| ゴール達成 | `${achieved}/${total_goals} (手動待 ${pending})` | goal |

エスカレ停止時は P3 カードを赤強調 + 「停止理由」を見出し直下に出す。

## セクション 3: フェーズタイムライン

```html
<section class="space-y-2">
  <h2 class="text-lg font-semibold">フェーズタイムライン</h2>
  <table class="w-full text-sm">
    <thead class="text-left" style="color: var(--fg-muted);">
      <tr><th>phase</th><th>duration</th><th>guard loops</th><th>review loops</th><th>commit</th><th>status</th></tr>
    </thead>
    <tbody>
      ${phases.map(p => `
        <tr class="border-t cursor-pointer" style="border-color: var(--border);" onclick="this.nextElementSibling.querySelector('details').open = !this.nextElementSibling.querySelector('details').open">
          <td class="py-2 font-mono">${p.name}</td>
          <td class="py-2 font-mono">${p.duration}</td>
          <td class="py-2 font-mono">${p.guard_loops}/3</td>
          <td class="py-2 font-mono">${p.review_loops}/3</td>
          <td class="py-2 font-mono"><a href="...">${p.commit_sha.slice(0,7)}</a></td>
          <td class="py-2">${p.status_badge}</td>
        </tr>
        <tr><td colspan="6">
          <details class="ml-4 my-2">
            <summary class="cursor-pointer text-sm" style="color: var(--fg-muted);">詳細</summary>
            <div class="mt-2 text-xs space-y-1">
              ${p.events.map(e => `<div><span class="font-mono">${e.timestamp}</span> ${e.step}: ${e.summary}</div>`).join('')}
            </div>
          </details>
        </td></tr>
      `).join('')}
    </tbody>
  </table>
</section>
```

各フェーズ行クリックで `<details>` を toggle (JS は最小限)。

## セクション 4: 動的修正の詳細 (P1 / P2 / P3)

JSONL から `event_type` が `p1_fix | p2_fix | p3_escalate` のエントリだけ抽出して時系列で表示。

各エントリカード:

```html
<article class="rounded border p-4" style="border-color: var(--border); background: var(--p1-bg); color: var(--p1-fg);">
  <header class="flex items-center justify-between text-sm">
    <span class="font-mono">${e.timestamp}</span>
    <span class="px-2 py-0.5 rounded text-xs uppercase font-semibold">${e.event_type}</span>
  </header>
  <p class="mt-2">${e.summary}</p>
  <dl class="mt-3 grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-xs">
    <dt>修正対象</dt><dd>${e.context.affected_files.join(', ')}</dd>
    <dt>関連設計</dt><dd><a href="../${e.context.related_design_section}">${e.context.related_design_section}</a></dd>
    <dt>判断根拠</dt><dd>${e.context.rationale}</dd>
  </dl>
  <details class="mt-2">
    <summary class="cursor-pointer text-xs">前後 diff</summary>
    <pre class="mt-1 p-2 bg-white text-xs overflow-x-auto rounded"><code>${escape(e.context.diff_before)}\n→\n${escape(e.context.diff_after)}</code></pre>
  </details>
</article>
```

severity (p1 / p2 / p3) で背景色と前景色を出し分け。

## セクション 4.5: レビュー残課題 (low/medium)

JSONL から `event_type: review_low` のエントリを抽出し、フェーズごとに `context.findings_by_dimension` (dimension をキーにした findings map) をまとめて表示する。fatal (severity: high) はセクション4のP1/P2/P3側で扱い済みなので、ここは「通過はしたが残っている軽微な指摘」の一覧:

```html
<section class="space-y-2">
  <h2 class="text-lg font-semibold">レビュー残課題 (low/medium)</h2>
  ${reviewLowEvents.map(e => {
    const total = Object.values(e.context.findings_by_dimension).flat().length;
    if (total === 0) return '';
    return `
    <details class="rounded border p-3" style="border-color: var(--border);">
      <summary class="cursor-pointer text-sm font-mono">${e.phase} — ${total} 件</summary>
      <div class="mt-2 text-xs space-y-1">
        ${Object.entries(e.context.findings_by_dimension).flatMap(([dim, findings]) =>
          findings.map(f => `<div><span class="font-mono uppercase">[${dim}]</span> ${escape(f.file)}:${f.line} - ${escape(f.message)}</div>`)
        ).join('')}
      </div>
    </details>`;
  }).join('')}
</section>
```

`findings_by_dimension` の全 dimension が空配列のフェーズは表示をスキップする (残課題ゼロの正常系をノイズにしないため)。

## セクション 5: 技術調査結果 (POC_NEEDED)

JSONL から `event_type: poc_resolved` のエントリだけ抽出:

```html
<section class="space-y-2">
  <h2 class="text-lg font-semibold">技術調査結果</h2>
  ${pocs.map(p => `
    <article class="rounded border p-4" style="border-color: var(--border); background: var(--poc-bg); color: var(--poc-fg);">
      <header class="flex items-center gap-3 text-sm">
        <span class="font-mono font-semibold">${p.id}</span>
        <span class="px-2 py-0.5 rounded bg-white text-xs">${p.result}</span>
        <span class="text-xs">confidence ${(p.confidence * 100).toFixed(0)}%</span>
      </header>
      <p class="mt-1 text-sm">${p.scope}</p>
      <p class="mt-2 text-xs"><strong>採用:</strong> ${p.recommended_approach}</p>
      ${p.fallback ? `<p class="mt-1 text-xs"><strong>fallback:</strong> ${p.fallback}</p>` : ''}
      <ul class="mt-2 text-xs space-y-0.5">
        ${p.references.map(r => `<li><a href="${r}" class="underline">${r}</a></li>`).join('')}
      </ul>
    </article>
  `).join('')}
</section>
```

## セクション 6: ゴール達成判定

JSONL から `event_type: goal_check | goal_unmet` のエントリ + Step 5 の最終結果を集約:

```html
<section class="space-y-2">
  <h2 class="text-lg font-semibold">ゴール達成判定</h2>
  <ul class="space-y-1">
    ${goals.map(g => {
      const icon = g.status === 'achieved' ? '✓' : g.status === 'unmet' ? '✗' : '⋯';
      const color = g.status === 'achieved' ? 'var(--goal-met)' : g.status === 'unmet' ? 'var(--goal-unmet)' : 'var(--goal-pending)';
      return `
        <li class="flex items-start gap-2">
          <span class="mt-0.5 font-bold" style="color: ${color};">${icon}</span>
          <div class="text-sm">
            <div><span class="font-mono">${g.id}</span> ${g.description}</div>
            <div class="text-xs" style="color: var(--fg-muted);">検証: <code>${g.verification}</code></div>
            ${g.status === 'unmet' ? `<details class="mt-1"><summary class="text-xs cursor-pointer">失敗ログ</summary><pre class="mt-1 p-2 bg-white text-xs">${escape(g.actual_output)}</pre></details>` : ''}
            ${g.status === 'pending' ? `<div class="text-xs italic">手動確認待ち</div>` : ''}
          </div>
        </li>
      `;
    }).join('')}
  </ul>
  <p class="text-xs mt-2" style="color: var(--fg-muted);">goal_loop: ${goal_loop_count}/2</p>
</section>
```

## セクション 7: フッター

```html
<footer class="border-t pt-6 text-xs space-y-1" style="border-color: var(--border); color: var(--fg-muted);">
  <p>コミット範囲: <code>git log ${start_sha}..${end_sha}</code></p>
  <p>push はユーザ手動で実行してください</p>
  <p>このレポートは <code>~/.claude/logs/dev-impl/${run_id}/decisions.jsonl</code> から生成されました</p>
</footer>
```

## エスカレ停止時の差分

エスカレ停止 (P3) の場合:
- ヘッダー直下に **赤いバナー**で「⛔ 停止: ${stop_reason}」を強調
- フェーズタイムライン最終行に `status: stopped` バッジ (red)
- P1/P2/P3 セクションの最後の P3 エントリを最上段に固定表示

## CDN セキュリティ注意

`<script src="https://cdn.tailwindcss.com">` は Tailwind の JIT 動的ビルド CDN で、配信内容がバージョン毎に変わるため SRI hash (`integrity` 属性) を付けられない。

dev-impl レポートは「ローカルで開いて振り返る」「リポジトリにコミットして PR レビューで参照する」が主な用途で、外部に公開しないため CDN compromise の影響範囲は限定的。それでも、以下の状況では別方式を検討する:

- **公開ドキュメントとしてレポートを配布する** → Tailwind を事前ビルドして `<style>` に inline、または `jsdelivr` の固定バージョン (`https://cdn.jsdelivr.net/npm/tailwindcss@3.4.0/...`) + SRI hash
- **オフラインでも見たい** → Tailwind の最小 build を `docs/dev-impl-reports/_assets/tailwind.css` に置いて相対参照

切替時は CDN リンクを丸ごと差し替えるだけで、本ファイルの他セクションは影響しない。

## XSS 対策 (生成時注意)

JSONL から取り出した値 (`rationale` / `diff_before` / `actual_output` 等) は HTML に埋め込む前に**必ず escape する**:

```javascript
function escape(s) {
  return String(s).replace(/[&<>"']/g, c => ({
    '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;'
  }[c]));
}
```

特に diff にコードや HTML 片が混ざる可能性が高いので、`<pre><code>` 内でも escape は省略しない。

## 生成プロセス (dev-impl 視点)

1. JSONL を Read して entries 配列に
2. entries を event_type で分類 (phases / decisions / review_low / pocs / goals)
3. 上記テンプレ各セクションを順に組み立て (template literal で文字列構築)
4. 1 つの HTML 文字列にして Write
5. `git add` + `git commit -m "📝 docs: dev-impl ${run_id} 実行レポート"`

dev-impl は単純な文字列組み立てで HTML を作る (ビルドツール不要、外部 npm 依存なし)。
