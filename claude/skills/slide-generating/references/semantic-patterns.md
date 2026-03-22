# Semantic Patterns（意味パターン）

コンテンツの「意味的関係」からレイアウトを選ぶための分類体系。Step 1.75（Semantic Diagnosis）で使用する。

## 9つの意味プリミティブ

| # | Primitive | 日本語 | 判断基準 | 推奨 family/variant | 代表 variant |
|---|-----------|------|--------|-------------------|-------------|
| 1 | **parallel** | 並列 | 同格の要素を横/縦に並べて見せたい | grid.cards, split.two-column, single-column.bullet-list | grid.cards（横並び）, single-column.bullet-list（縦並び） |
| 2 | **compare** | 比較 | 要素間の違い・優劣・変化を対比したい | split.comparison, table.feature-comparison, diagram.matrix | split.comparison（2項目）, table.feature-comparison（3項目以上） |
| 3 | **process** | 過程 | 順序・手順・時系列を示したい | sequence.steps, sequence.timeline, diagram.flow | sequence.steps（4項目以下）, diagram.flow（分岐あり） |
| 4 | **cycle** | 循環 | 要素が循環する関係を示したい | diagram.cycle | diagram.cycle |
| 5 | **hierarchy** | 階層 | 上下関係・分解・段階を示したい | diagram.org-chart, diagram.pyramid, diagram.tree | diagram.org-chart（人・組織）, diagram.pyramid（量の階層）, diagram.tree（分解） |
| 6 | **relationship** | 関係 | 要素間の重なり・包含・相互作用を示したい | diagram.venn, diagram.flow, split.two-column | diagram.venn（重なり）, split.two-column（対応関係） |
| 7 | **data-viz** | データ | 数値・割合・推移をグラフで示したい | hero.big-number, Chart.js利用スライド | hero.big-number（KPI 1-3個）, Chart.js（推移・比率） |
| 8 | **evidence** | 根拠 | スクリーンショット・事例・ロゴで裏付けたい | split.text-image, grid.logos, grid.cards | split.text-image（キャプチャ+説明）, grid.logos（ロゴ一覧） |
| 9 | **page-role** | 定型 | 表紙・目次・会社概要など定型ページ | hero.cover, hero.section-divider, hero.closing, grid.team-members | hero.cover（表紙）, hero.section-divider（中扉） |

### Diagram Family の Semantic Identity

diagram family の各 variant は異なる semantic_pattern に属する。variant 選択時はこの対応を厳守すること。

| variant | semantic_pattern | semantic identity | 使い分け |
|---------|-----------------|-------------------|---------|
| flow | process | 順方向の処理フロー | 入力→処理→出力の一方向 |
| org-chart | hierarchy | 組織的な上下関係 | 人・部門の報告ライン |
| cycle | cycle | 循環する反復プロセス | PDCA、ビジネスサイクル |
| matrix | compare | 2軸による4象限分析 | SWOT、ポジショニング、優先度 |
| venn | relationship | 要素の重なり・共通部分 | 共通領域の可視化、2-3要素 |
| pyramid | hierarchy | スケール階層（上→小 or 上→大） | TAM-SAM-SOM、組織階層 |
| tree | hierarchy | 分類・分解の木構造 | ユニットエコノミクス分解、カテゴリ分類 |

**org-chart vs pyramid vs tree の使い分け:**
- org-chart: 「誰が誰に報告するか」（人・組織の関係）
- pyramid: 「上位ほど少ない/重要」（量・重要度の階層）
- tree: 「全体を要素に分解する」（論理的な分類・分解）

## 選択フロー

```
スライドのメッセージ
    │
    ├─ 定型ページか？（表紙/目次/会社概要/メンバー紹介/closing）
    │   └→ page-role
    │
    ├─ 数値データを見せたいか？
    │   ├─ グラフが必要 → data-viz
    │   └─ 大きな数字1つ → data-viz (big-number)
    │
    ├─ スクリーンショット/事例/導入実績を見せたいか？
    │   └→ evidence
    │
    └─ 要素間に関係があるか？
        ├─ 関係なし（同格の羅列） → parallel
        │
        └─ 関係あり
            ├─ 対比・違い → compare
            ├─ 順序・手順 → process
            ├─ 循環 → cycle
            ├─ 上下・分解 → hierarchy
            └─ 重なり・包含・相互 → relationship
```

## entity_count による variant 調整

同じ意味プリミティブでも要素数で最適な variant が変わる:

| Primitive | 1要素 | 2要素 | 3要素 | 4要素以上 |
|-----------|------|------|------|---------|
| parallel | single-column.text-block | split.two-column | grid.cards (3col) | grid.cards (4col) or 複数羅列 |
| compare | hero.big-number | split.comparison | grid.cards | table.feature-comparison |
| process | single-column.text-block | split.two-column | sequence.steps (横) | sequence.steps or timeline |
| hierarchy | — | diagram.pyramid | diagram.tree | diagram.org-chart |

## Deck Profile（用途プロファイル）

スライドの用途によって、推奨される意味パターンの優先度が変わる。

### business-pitch（営業資料・投資家ピッチ）

**優先**: compare, evidence, data-viz, parallel
**頻出ページ**: 会社概要, 導入実績, 料金体系, 事例, 比較表
**特徴**: 数値による説得、他社比較、導入企業ロゴが多い

### conference-talk（カンファレンス登壇）

**優先**: parallel, process, data-viz, compare
**頻出ページ**: big-number, quote, steps, 概念図
**特徴**: 1スライド1メッセージを徹底、情報密度は低め、ビジュアルインパクト重視

### internal-study（社内勉強会・研修）

**優先**: process, parallel, evidence, compare
**頻出ページ**: フロー、テキスト多め、Q&A、キャプチャ
**特徴**: 情報密度を許容、表やフローを多用、詳細な説明を含む

## 39パターン → 意味プリミティブ対応表

以下は c-slide 社「パワーポイントのデザインパターン大全（39種）」を基に、9プリミティブへの正規化を行った対応表。

| PDF パターン | Primitive | 備考（family/variant 選択条件） |
|-----------|-----------|------|
| 並列・横並び | parallel | テキスト量少: grid.cards (横並び) / テキスト量多: single-column.bullet-list (縦並び) |
| 並列・縦並び | parallel | 説明文が長い: single-column.bullet-list / 短い+アイコンあり: grid.cards (1列縦) |
| 並列・複数羅列 | parallel | 4個以下: grid.cards (1行) / 5個以上: grid.cards (2x3等の複数行) |
| 比較・規模比較 | compare | 数値差を強調: hero.big-number (並置) / 視覚的サイズ差: split.comparison (大小の図) |
| 比較・項目比較 | compare | 2項目: split.comparison / 3項目以上: grid.cards + 差異ハイライト |
| 比較・表での比較 | compare | 機能比較: table.feature-comparison / 料金比較: table.pricing |
| フロー・横型 | process | アイコンあり+項目4以下: sequence.steps / アイコンなし+項目多い: diagram.flow |
| フロー・縦型 | process | 各ステップに説明文あり: single-column.bullet-list (番号付き) / 説明少: sequence.steps (縦) |
| フロー・箱型 | process | 分岐・合流あり: diagram.flow / 単純な直列: sequence.steps |
| サイクル・円 | cycle | 2-3要素: diagram.cycle (円形配置) |
| サイクル・四角 | cycle | 4要素以上: diagram.cycle (四角配置) |
| ピラミッド型 | hierarchy | 量・重要度が上→小: diagram.pyramid (正三角形) |
| じょうろ型 | hierarchy | ファネル・量が上→大: diagram.pyramid (逆三角形) |
| マトリクス | compare | 2軸×2軸の4象限分析: diagram.matrix |
| ベン図 | relationship | 2-3要素の重なり: diagram.venn / 4要素以上は matrix か table に変更 |
| ツリー図 | hierarchy | 論理分解・カテゴリ分類: diagram.tree / 人の報告ラインなら diagram.org-chart |
| 数式 | relationship | A = B / C 等の演算関係: split.two-column (左に式、右に解説) |
| 掛け算 | relationship | A × B の相乗効果: split.two-column (要素間に × 記号) |
| 足し算 | relationship | A + B の組み合わせ: split.two-column (要素間に + 記号) |
| 領域 | relationship | 対応範囲の可視化: split.two-column (左右で対応線) / 多対多: diagram.flow |
| 階段 | hierarchy | 段階的成長・ステップアップ: sequence.steps (階段状CSS) / 段階数多い: diagram.pyramid (横向き) |
| 重複 | relationship | 共有部分の可視化: diagram.venn (重なり強調) |
| 包括 | relationship | A ⊂ B の包含: diagram.venn (入れ子円) / 多段包含: diagram.pyramid |
| 相互関係 | relationship | 双方向矢印: diagram.flow (双方向) / 2要素: split.two-column (矢印付き) |
| ビフォーアフター | compare | 画像比較: split.comparison (左右に画像) / テキスト比較: split.comparison (左右にテキスト) |
| グラフ（棒/円/折線） | data-viz | 推移: Chart.js 折線 / 比率: Chart.js 円 / 比較: Chart.js 棒 |
| キャプチャ（羅列/拡大/フロー） | evidence | 1枚+説明: split.text-image / 複数枚羅列: grid.cards / フロー形式: sequence.steps (画像付き) |
| 料金体系 | compare | プラン比較: table.pricing / 単一プラン詳細: single-column.text-block |
| 表 | compare | 項目数少+比較目的: table.feature-comparison / 情報一覧: table.data-table |
| 拠点 | evidence | 地図+拠点マーク: split.text-image (左に地図、右にリスト) / リストのみ: grid.cards |
| スケジュール | process | 時系列: sequence.timeline / マイルストーン少: sequence.steps |
| ランキング | data-viz | 数値差を強調: Chart.js 横棒グラフ / 順位のみ: single-column.bullet-list (番号付き) |
| 事例 | evidence | 画像+テキスト: split.text-image / 複数事例: grid.cards |
| テキストのみ | page-role | 短文メッセージ: hero.big-number / 長文説明: single-column.text-block |
| Q&A | page-role | 1問1答: split.two-column (左Q右A) / 複数Q&A: single-column.bullet-list |
| 名言 | page-role | 引用+出典: hero.quote |
| ピクトグラム | page-role | アイコン+短テキスト: grid.cards (アイコン付き) / 1つのアイコン強調: hero.big-number |
| 表紙 | page-role | タイトル+サブタイトル: hero.cover |
| 目次 | page-role | 項目数少: hero.section-divider / 項目数多: single-column.bullet-list |
| 会社概要 | page-role | 項目一覧: table.data-table / 概要+画像: split.text-image |
| メンバー紹介 | page-role | 写真+名前+役職: grid.team-members |
| MVV提示 | page-role | 短い標語: hero.big-number / 長い説明付き: hero.quote |
| 背景静止画 | page-role | 画像全面+テキストオーバーレイ: hero.cover (背景画像指定) |
| 会社沿革 | process | 年表形式: sequence.timeline |
| 導入実績 | evidence | ロゴ一覧: grid.logos / 社名+説明: grid.cards |
| 組織図 | hierarchy | 人・部門の報告ライン: diagram.org-chart |
