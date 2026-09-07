---
# 常駐読み込みさせないためのマーカー (このパスにマッチするファイルは存在しない)。
# 本ファイルは必要になったときに Read で参照する。
paths:
  - "__read-on-demand-only__"
---

# 設計書の構造規範

- 種別: 構造規範

/utility-doc-audit のフォーマット適合チェックの正本。各項目は yes/no + 根拠箇所で判定できる形にしてある。

節構成の正本は dev-spec スキルの `references/design-doc.md` (横断設計書 = docs/design/DESIGN.md) と `references/feature-doc.md` (機能設計書 = docs/design/features/)。本規範は独自フォーマットを定義せず、「dev-spec の issue 生成と /dev-impl に接続できる設計書」の要件をテンプレートに重ねて定義する。実装を伴わない検討文書（方針比較・アーキテクチャ調査等）は本型の対象外 — 種別をそれと明記し（例: `- 種別: 設計方針書`）、`rules/core/documentation.md` の汎用原則のみでよい。

## 成果物とパス（違反は major）

1. 横断設計 = `docs/design/DESIGN.md` の 1 枚 + 機能単位の設計 = `docs/design/features/<機能名>.md`（1 機能 = 1 ファイル、機能名で命名）
2. `docs/design/DESIGN.md` の 1 行目にプロダクトモードスタンプ (`<!-- product-mode: cli|webapp -->`) がある
3. 節構成は各テンプレートに従う。該当しない節（データスキーマ・API・インフラ等）は省略できる。機能設計書の「エッジケースの決定」だけは、検討して該当なしと判断した観点に「該当なし (<理由>)」を残す（feature-doc.md の記入基準と同一）

## 機械ゲート（機械判定・違反は major）

| 要件 | 判定 |
| --- | --- |
| PoC 未解決なし | `rg -n 'POC_NEEDED:.*blocker=true' docs/design/DESIGN.md docs/design/features/` が 0 件 |
| 開発・検証コマンド | `docs/design/DESIGN.md` に「開発・検証コマンド」節がある（issue の DoD がこの節の前提の上で実行されるため。scaffold 前は「セットアップ issue の完了後に確定」の明記で可） |

## 整合性の仕掛け（違反は major/minor）

1. **横断と機能の分担**: テーブル定義・API 共通規約・エラー形式・認証は DESIGN.md のみにあり、features 側に重複していない。逆に機能単体の入出力契約・エッジケースの決定は features 側のみにある
2. **参照の実在**: features → DESIGN.md の節参照（「DESIGN.md「<節名>」参照」）が実在の節名を指す
3. **UC との対応**: USECASES.md がある構成では、各機能設計書の冒頭メタ情報に対象 UC が明記されている

## 構造（違反は major/minor）

1. 冒頭メタ情報: タイトル直後に種別（と機能設計書なら対象 UC）があるか
2. 表の完全性: 数値列に単位、選択肢列に取りうる値の例があるか（「詳細は別途確認」単独の記述がないか）
3. 未解決の論点: DESIGN.md に「未解決の論点」節があり、ビジネス判断待ちが列挙されている（なければ「なし」）

## 可読性（違反は suggestion）

- 1 節 1 主題（節の要約が「〜と〜と〜」にならない）
- 各節は結論の一文で始まり、根拠・詳細が続く
- 過程の記録（「以前は〜だったが」）を含まない（最終状態のみ。1 行目の product-mode スタンプと `<!-- 変更履歴 ... -->` の HTML コメントは過程の記録に数えない）
