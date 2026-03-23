# Diagram Family

## flow

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

## org-chart

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

## cycle（循環関係: 2-4要素の円形/四角形サイクル）

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

## matrix（2x2マトリクス: SWOT、ポジショニング）

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

## venn（ベン図: 重なり・共通領域）

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

## pyramid（ピラミッド/じょうろ: 階層的な大小関係）

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

## tree（ツリー図: 分解・分類の階層構造）

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

## concentric（同心円: 包括関係）

```javascript
S(n, 'diagram', 'concentric', `
  ${H('同心円タイトル')}
  ${Sub('補足説明')}
  ${VC(`
    <div class="relative flex items-center justify-center" style="height: 520px">
      <svg width="520" height="520" viewBox="0 0 520 520">
        <!-- 外側の円 (TAM) -->
        <circle cx="260" cy="260" r="250" fill="none" stroke="var(--color-bg-alt)" stroke-width="2" />
        <circle cx="260" cy="260" r="250" fill="var(--color-accent)" fill-opacity="0.08" />
        <!-- 中間の円 (SAM) -->
        <circle cx="260" cy="260" r="170" fill="none" stroke="var(--color-accent)" stroke-width="2" stroke-opacity="0.3" />
        <circle cx="260" cy="260" r="170" fill="var(--color-accent)" fill-opacity="0.12" />
        <!-- 内側の円 (SOM) -->
        <circle cx="260" cy="260" r="90" fill="none" stroke="var(--color-accent)" stroke-width="2" />
        <circle cx="260" cy="260" r="90" fill="var(--color-accent)" fill-opacity="0.25" />
      </svg>
      <!-- ラベル -->
      <div class="absolute flex flex-col items-center" style="top: 50%; left: 50%; transform: translate(-50%, -50%)">
        <p class="text-[20px] font-bold" style="color: var(--color-accent)">SOM</p>
        <p class="text-[32px] font-bold" style="color: var(--color-accent)">¥10億</p>
      </div>
      <div class="absolute" style="top: 22%; left: 50%; transform: translateX(-50%); text-align: center">
        <p class="text-[18px] font-bold" style="color: var(--color-text)">SAM</p>
        <p class="text-[24px] font-bold" style="color: var(--color-text)">¥100億</p>
      </div>
      <div class="absolute" style="top: 4%; left: 50%; transform: translateX(-50%); text-align: center">
        <p class="text-[18px] font-bold" style="color: var(--color-text-muted)">TAM</p>
        <p class="text-[24px] font-bold" style="color: var(--color-text-muted)">¥1,000億</p>
      </div>
    </div>
  `)}
`, {sec: 'セクション名'})
```

3つの入れ子円で包括関係を表現する。外側が最大市場、内側が獲得可能市場。TAM/SAM/SOM等の市場規模分析に最適。

## mutual（相互関係: 双方向矢印）

```javascript
S(n, 'diagram', 'mutual', `
  ${H('相互関係タイトル')}
  ${Sub('補足説明')}
  ${VC(`
    <div class="flex items-center justify-center" style="gap: var(--spacing-gap-lg)">
      <!-- 左の要素 -->
      <div class="rounded-2xl text-center" style="background: var(--color-bg-alt); padding: var(--spacing-gap-md) var(--spacing-gap-lg); min-width: 280px">
        <div style="margin-bottom: var(--spacing-gap-sm)">${IC('<!-- SVG -->')}</div>
        <p class="text-[24px] font-bold" style="color: var(--color-text)">関係者A</p>
        <p class="text-[16px]" style="color: var(--color-text-muted); margin-top: var(--spacing-gap-sm)">説明テキスト</p>
      </div>
      <!-- 双方向矢印 -->
      <div class="flex flex-col items-center" style="gap: var(--spacing-gap-sm)">
        <div class="text-center">
          <p class="text-[14px] font-bold" style="color: var(--color-accent)">提供する価値</p>
          <svg width="160" height="24" viewBox="0 0 160 24" fill="none">
            <path d="M0 12H148M148 12L136 4M148 12L136 20" stroke="var(--color-accent)" stroke-width="2"/>
          </svg>
        </div>
        <div class="rounded-xl text-center text-white" style="background: linear-gradient(135deg, var(--color-primary), var(--color-accent)); padding: var(--spacing-gap-sm) var(--spacing-gap-md); min-width: 200px">
          <p class="text-[20px] font-bold">サービス名</p>
        </div>
        <div class="text-center">
          <svg width="160" height="24" viewBox="0 0 160 24" fill="none">
            <path d="M160 12H12M12 12L24 4M12 12L24 20" stroke="var(--color-secondary)" stroke-width="2"/>
          </svg>
          <p class="text-[14px] font-bold" style="color: var(--color-secondary)">受け取る価値</p>
        </div>
      </div>
      <!-- 右の要素 -->
      <div class="rounded-2xl text-center" style="background: var(--color-bg-alt); padding: var(--spacing-gap-md) var(--spacing-gap-lg); min-width: 280px">
        <div style="margin-bottom: var(--spacing-gap-sm)">${IC('<!-- SVG -->')}</div>
        <p class="text-[24px] font-bold" style="color: var(--color-text)">関係者B</p>
        <p class="text-[16px]" style="color: var(--color-text-muted); margin-top: var(--spacing-gap-sm)">説明テキスト</p>
      </div>
    </div>
  `)}
`, {sec: 'セクション名'})
```

中央のサービス/プロダクトと左右の関係者を双方向矢印で接続する。3要素の場合は左・中央・右に配置。

## staircase（階段型: 段階的成長）

```javascript
S(n, 'diagram', 'staircase', `
  ${H('階段タイトル')}
  ${Sub('補足説明')}
  ${VC(`
    <div class="flex items-end justify-center" style="gap: var(--spacing-gap-md); height: 420px">
      <!-- Level 1（最低段） -->
      <div class="flex flex-col items-center" style="width: 200px">
        <div class="w-full rounded-t-xl text-center text-white" style="background: var(--color-accent); opacity: 0.4; height: 100px; display: flex; flex-direction: column; justify-content: center">
          <p class="text-[20px] font-bold">Lv.1</p>
        </div>
        <div class="text-center" style="margin-top: var(--spacing-gap-sm)">
          <p class="text-[18px] font-bold" style="color: var(--color-text)">基礎</p>
          <p class="text-[14px]" style="color: var(--color-text-muted)">説明テキスト</p>
        </div>
      </div>
      <!-- Level 2 -->
      <div class="flex flex-col items-center" style="width: 200px">
        <div class="w-full rounded-t-xl text-center text-white" style="background: var(--color-accent); opacity: 0.6; height: 200px; display: flex; flex-direction: column; justify-content: center">
          <p class="text-[20px] font-bold">Lv.2</p>
        </div>
        <div class="text-center" style="margin-top: var(--spacing-gap-sm)">
          <p class="text-[18px] font-bold" style="color: var(--color-text)">応用</p>
          <p class="text-[14px]" style="color: var(--color-text-muted)">説明テキスト</p>
        </div>
      </div>
      <!-- Level 3 -->
      <div class="flex flex-col items-center" style="width: 200px">
        <div class="w-full rounded-t-xl text-center text-white" style="background: var(--color-accent); opacity: 0.8; height: 300px; display: flex; flex-direction: column; justify-content: center">
          <p class="text-[20px] font-bold">Lv.3</p>
        </div>
        <div class="text-center" style="margin-top: var(--spacing-gap-sm)">
          <p class="text-[18px] font-bold" style="color: var(--color-text)">発展</p>
          <p class="text-[14px]" style="color: var(--color-text-muted)">説明テキスト</p>
        </div>
      </div>
      <!-- Level 4（最高段） -->
      <div class="flex flex-col items-center" style="width: 200px">
        <div class="w-full rounded-t-xl text-center text-white" style="background: var(--color-accent); height: 400px; display: flex; flex-direction: column; justify-content: center">
          <p class="text-[20px] font-bold">Lv.4</p>
        </div>
        <div class="text-center" style="margin-top: var(--spacing-gap-sm)">
          <p class="text-[18px] font-bold" style="color: var(--color-text)">最適化</p>
          <p class="text-[14px]" style="color: var(--color-text-muted)">説明テキスト</p>
        </div>
      </div>
    </div>
  `)}
`, {sec: 'セクション名'})
```

右肩上がりの棒が段階的に高くなるレイアウト。`align-items: flex-end`（`items-end`）で棒を下揃え。成熟度モデルやレベル表現に最適。段数は3〜5を推奨。

## scale-compare（規模比較: サイズの異なる円）

```javascript
S(n, 'diagram', 'scale-compare', `
  ${H('規模比較タイトル')}
  ${Sub('補足説明')}
  ${VC(`
    <div class="flex items-end justify-center" style="gap: var(--spacing-gap-lg); height: 440px">
      <!-- 大 -->
      <div class="flex flex-col items-center">
        <div class="rounded-full flex flex-col items-center justify-center text-white" style="width: 360px; height: 360px; background: var(--color-accent)">
          <p class="text-[20px]" style="opacity: 0.8">グローバル市場</p>
          <p class="text-[48px] font-bold">$500B</p>
        </div>
      </div>
      <!-- 中 -->
      <div class="flex flex-col items-center">
        <div class="rounded-full flex flex-col items-center justify-center text-white" style="width: 220px; height: 220px; background: var(--color-secondary)">
          <p class="text-[16px]" style="opacity: 0.8">国内市場</p>
          <p class="text-[36px] font-bold">$50B</p>
        </div>
      </div>
      <!-- 小 -->
      <div class="flex flex-col items-center">
        <div class="rounded-full flex flex-col items-center justify-center text-white" style="width: 120px; height: 120px; background: var(--color-primary)">
          <p class="text-[12px]" style="opacity: 0.8">当社</p>
          <p class="text-[22px] font-bold">$1B</p>
        </div>
      </div>
    </div>
  `)}
`, {sec: 'セクション名'})
```

異なるサイズの円で大小関係を視覚的に表現する。横並びで3つの円（大/中/小）を配置し、各円の中にラベルと数値を表示。市場規模比較や競合比較に最適。

## box-flow（箱型フロー: 分岐・合流のある複雑フロー）

```javascript
S(n, 'diagram', 'box-flow', `
  ${H('処理フロータイトル')}
  ${Sub('補足説明')}
  ${VC(`
    <div class="flex flex-col items-center" style="gap: 0">
      <!-- 開始ノード -->
      <div class="rounded-xl text-center text-white" style="background: var(--color-accent); padding: var(--spacing-gap-sm) var(--spacing-gap-lg); min-width: 240px">
        <p class="text-[22px] font-bold">開始</p>
      </div>
      <div class="w-0.5 h-7" style="background: var(--color-text-muted)"></div>
      <!-- 処理ノード -->
      <div class="rounded-xl text-center border-2" style="border-color: var(--color-accent); background: var(--color-bg-alt); padding: var(--spacing-gap-sm) var(--spacing-gap-lg); min-width: 240px">
        <p class="text-[20px] font-bold" style="color: var(--color-text)">処理A</p>
      </div>
      <div class="w-0.5 h-7" style="background: var(--color-text-muted)"></div>
      <!-- 分岐: 条件ノード -->
      <div class="rounded-xl text-center border-2" style="border-color: var(--color-secondary); background: var(--color-bg-alt); padding: var(--spacing-gap-sm) var(--spacing-gap-lg); min-width: 240px">
        <p class="text-[20px] font-bold" style="color: var(--color-secondary)">条件判定</p>
      </div>
      <div class="w-0.5 h-6" style="background: var(--color-text-muted)"></div>
      <!-- 分岐: 2つのノードを横並び -->
      <div class="flex items-start justify-center" style="gap: var(--spacing-gap-lg)">
        <div class="flex flex-col items-center">
          <p class="text-[16px] font-bold" style="color: var(--color-text-muted); margin-bottom: 0.25rem">Yes</p>
          <div class="w-0.5 h-6" style="background: var(--color-text-muted)"></div>
          <div class="rounded-xl text-center border-2" style="border-color: var(--color-accent); background: var(--color-bg-alt); padding: var(--spacing-gap-sm) var(--spacing-gap-md); min-width: 200px">
            <p class="text-[18px] font-bold" style="color: var(--color-text)">処理B</p>
          </div>
          <div class="w-0.5 h-6" style="background: var(--color-text-muted)"></div>
        </div>
        <div class="flex flex-col items-center">
          <p class="text-[16px] font-bold" style="color: var(--color-text-muted); margin-bottom: 0.25rem">No</p>
          <div class="w-0.5 h-6" style="background: var(--color-text-muted)"></div>
          <div class="rounded-xl text-center border-2" style="border-color: var(--color-accent); background: var(--color-bg-alt); padding: var(--spacing-gap-sm) var(--spacing-gap-md); min-width: 200px">
            <p class="text-[18px] font-bold" style="color: var(--color-text)">処理C</p>
          </div>
          <div class="w-0.5 h-6" style="background: var(--color-text-muted)"></div>
        </div>
      </div>
      <!-- 合流線 -->
      <div class="w-0.5 h-6" style="background: var(--color-text-muted)"></div>
      <!-- 終了ノード -->
      <div class="rounded-xl text-center text-white" style="background: var(--color-accent); padding: var(--spacing-gap-sm) var(--spacing-gap-lg); min-width: 240px">
        <p class="text-[22px] font-bold">終了</p>
      </div>
    </div>
  `)}
`, {sec: 'セクション名'})
```

縦方向のフローチャート。各ステップが箱（rounded-xl）で、箱同士を縦線と矢印で接続。条件分岐は水平に2つの箱を並べ、上から縦線で分岐させる。全体の高さに注意（1080px内に収まるよう、ノード間の線の高さを h-6〜h-8 に抑える）。
