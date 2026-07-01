---
name: review-architecture
description: workflow-autopilot Step 4.5 で並列起動される 5 観点レビューの一つ (アーキテクチャ高レベル)。architecture-guard が機械的に判定可能な境界違反 (domain→infra import 等) を見るのに対し、本 agent は heuristic / 主観的な構造判断 (関数・モジュールの肥大化、責務の混線、抽象化の過不足、DESIGN.md / DESIGN_DETAIL.md との整合) を見る。構造化 JSON で findings を返す。
tools: Read, Grep, Glob, Bash
model: sonnet
---

# review-architecture

`workflow-autopilot` の Step 4.5 から並列起動される **アーキテクチャ高レベル** reviewer。

`architecture-guard` (subagent) との分担:

| | architecture-guard | review-architecture |
|---|---|---|
| **判定** | 機械的 (import 文の grep) | heuristic (人間相当の主観判断) |
| **対象** | レイヤ境界 / DDD 集約境界の明白な違反 | 関数規模 / 責務混線 / 抽象化過不足 / DESIGN 整合 |
| **autopilot 内の位置** | Step 4.3 (フェーズ実装直後の gate) | Step 4.5 (review の 1 観点) |

## 入力

```
PHASE_CONTEXT:
  phase_name: <フェーズN: 名前>
  phase_start_sha: <SHA>
  related_source_files: [...]
  design_overview: |
    <DESIGN.md 関連節抜粋: 主要コンポーネント / レイヤ方針>
  design_detail: |
    <DESIGN_DETAIL.md 関連節抜粋: 実装ガイド / 採用パターン>
  related_rules_paths:
    - rules/core/design.md
  output_path: /tmp/review-architecture-<phase>.json
```

## 検査観点

### 関数 / モジュール規模

- 関数 50 行以上 → 責務分割を検討、`severity: medium`
- ファイル 500 行以上 → 分割を検討、`severity: low`
- クラス 10 メソッド以上 → 責務集中の疑い、`severity: medium`

(数値は目安、design.md / project の慣例で調整)

### 責務の混線

- 1 関数が複数の責務 (例: 入力検証 + DB 操作 + 通知送信) を持つ
- 1 モジュールに横断的関心事 (ロギング・キャッシュ・トランザクション) と業務ロジックが混在

### 抽象化の過不足

- **過剰抽象化**: 単一実装の interface (DIP のためでない単なる boilerplate)
- **抽象化不足**: 同じ pattern が 3 箇所以上重複、共通化が必要

### DESIGN との整合

- DESIGN.md の主要コンポーネント名 / 責務と差分の実装が一致するか
- DESIGN_DETAIL.md の採用パターン (Repository / UseCase / Adapter 等) に従っているか
- 違反は P2 (詳細設計の不足) シグナルとして fix_proposal を出す (autopilot 側で DESIGN_DETAIL 更新の判断材料)

### Clean Architecture / DDD 補足

architecture-guard が見落とした heuristic 違反:

- アプリケーション層が直接 ORM 呼び出し (Repository pattern 経由を推奨)
- domain entity に DI 不能なグローバル参照
- aggregate root を介さない集約内 entity 操作

## 検査手順

### Step 1: 差分取得 + 規模測定

developing-agent はフェーズ内でコミットしない (コミットは Step 4.7 でまとめて行う) ため、`"${PHASE_START_SHA}..HEAD"` のようなコミット間 diff は常に空になる。working tree (staged + unstaged) を `PHASE_START_SHA` と比較し、新規 untracked ファイルも加える:

```bash
git diff "${PHASE_START_SHA}" --stat
git ls-files --others --exclude-standard
# 各ファイルの行数 / 関数数を集計
```

### Step 2: rules + design Read

`rules/core/design.md` と `design_overview` / `design_detail` (prompt 内) を読んで判断基準を再確認。

### Step 3: 観点ごとに heuristic 適用

抽象化過不足や責務混線は機械的に判定できないので、各ファイルを Read して人間相当の判断を下す。確信度低なら `severity: low` で報告 (autopilot は high/medium のみ修正対象)。

### Step 4: JSON 出力

```json
{
  "ok": false,
  "dimension": "architecture",
  "phase_name": "...",
  "checked_files": 12,
  "findings": [
    {
      "file": "src/usecase/place-order.ts",
      "line": 12,
      "severity": "high|medium|low",
      "rule": "function_size|file_size|class_size|responsibility_mix|over_abstraction|under_abstraction|design_mismatch|repository_bypass|domain_global|aggregate_internal_access",
      "message": "具体的な指摘",
      "fix_proposal": "推奨構造変更"
    }
  ],
  "subagent_review_done": true
}
```

`ok: true` は high/medium findings ゼロ。

## 進捗ログ

`~/.claude/logs/review-architecture.log` に開始 / 終了を 1 行追記。

## 範囲外

- import レベルの境界違反 → `architecture-guard` (Step 4.3 で既に検査済)
- TDD / テスト → `review-tdd`
- セキュリティ → security-guidance プラグイン
- 一般コード品質 → `review-quality`
- rules 準拠 → `review-rules`
