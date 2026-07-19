---
name: dev-impl-quick
description: 軽量実装ループ。設計 docs 不要で、依頼文または簡易タスクリストを入力に、タスクごとに直営 TDD → テストゲート → review-tdd (単一観点レビュー) → コミットを回す。意味のないテスト (トートロジー・実装詳細依存) を検出する review-tdd 以外の複数観点レビュー fan-out・進捗ログ・レポート生成は持たない (TDD 順序自体は常時有効の tdd-guard hook が強制)。「軽く実装して」「サクッと直して」「まとめて修正して」「docs なしで一括実装」「dev-impl だと重すぎるタスク」などで起動。大きい機能・新規プロダクトは /dev-spec → /dev-impl を使う。
argument-hint: 依頼内容 (省略時は直前の会話のタスクを対象)
model: sonnet
allowed-tools: Read, Edit, Write, Glob, Grep, Bash, Agent, TaskCreate, TaskUpdate, AskUserQuestion
---

# dev-impl-quick — 軽量実装ループ

設計 docs (DESIGN.md / TODO.md 等) を前提にしない、依頼文をそのまま入力にできる薄い実装ループ。`dev-impl` が持つ承認ゲート・複数観点レビュー fan-out (quality / product-readiness / adversarial)・進捗ログ・HTML レポートは持たない。TDD の RED→GREEN→REFACTOR 順序は本スキルではなく `~/.claude/hooks/tdd-guard.ts` (常時有効な PreToolUse/Stop hook) が機械強制するため、スキル側で再実装しない。

一方で「テストは通るが意味がない (トートロジー・実装詳細への依存)」は tdd-guard では検知できない。これはメインループが自分で書いたテストを自己レビューしても見逃しやすいため、タスクごとに `review-tdd` subagent (fresh context) を 1 観点だけ都度起動して検証する。

## モデル方針

本スキルの actor は frontmatter で `model: sonnet` を指定している。検証器の `review-tdd` subagent は起動時に **`model: opus` を明示**する (原則: 実行器のモデル ≤ 検証器のモデル。`skills/README.md`「モデル方針」参照)。

## いつ使うか

- 1〜数件のタスクをまとめて委任されたが、DESIGN.md 等の設計 docs は無い/不要な規模
- `/dev-impl` を起動するには前提ドキュメントの準備コストが見合わない中小タスク

大きい機能・新規プロダクトは `/dev-spec` → 承認ゲート → `/dev-impl` を使う (`skills/README.md` の規模別入口を参照)。

## 入力

`$ARGUMENTS` の依頼文、または箇条書きタスクリストをそのまま入力とする。docs ディレクトリは不要。ゴールと検証手段が依頼から自明でない場合のみ、着手前に 1 回確認する (自律モード・一括委任時は CLAUDE.md「自律モード時の優先順位」に従い、選択と根拠を明示して前進する)。

## ステップ

1. **タスク分解と見える化**: 依頼をタスク単位に分解し `TaskCreate` でリスト化する。CLAUDE.md「オーケストレーションとモデル階層」のトリアージ (難易度・コンテキスト連続性・並列可能性) を 1 行で出力してから着手する
2. **1 件ずつ実装**: `TaskUpdate` で in_progress にし、メインループ直営で TDD 実装する (RED→GREEN→REFACTOR の順序は tdd-guard hook が強制するため、着手前にセッション未読なら `~/.claude/rules/core/tdd.md` / `design.md` / `testing.md` を Read する)。TDD を適用しない判断 (typo 修正・宣言的 config 変更など) をした場合は理由を出力に明示する
3. **テストゲート**: 関連テストを Bash で実行し exit code で green を確認する。テストの削除・skip・弱体化によるゲート通過は禁止 — やむを得ない場合は理由を明示してユーザーに判断を仰ぐ
4. **review-tdd (単一観点レビュー)**: テスト green 後、`review-tdd` subagent を `model: opus` 明示・`Agent` ツールで起動する。指示文にはそのタスクの diff (実装ファイル + テストファイル) と「振る舞いのテストか / トートロジーではないか / AAA パターン / モックの過剰使用 / テスト独立性を判定して構造化 JSON を返し、結果は必ず `SendMessage` で親に送ること」を含める。CONFIRMED/PLAUSIBLE な finding があればメインループで直接 self-fix し、ステップ 3 に戻る (この往復も次項の失敗カウントに含める)。finding が無ければ次へ
5. **コミット**: review-tdd 通過後、そのタスク単位で `~/.claude/rules/core/commit.md` 準拠のコミットを作成する (push はしない)
6. **`TaskUpdate` で completed にして次のタスクへ**: 全タスク消化まで 1〜5 を繰り返す
7. **停止条件**: 同一タスクでステップ 3〜4 の同一アプローチが 2 回失敗したら戦略を変える、3 回失敗したら詰まっている箇所を具体化してユーザーにエスカレーションする。破壊的・不可逆操作 (force push・削除・外部公開) は必ず停止して確認する

## 完了報告

`~/.claude/rules/core/collaboration.md` の 4 点形式で報告する: 変更の要約 / 動作確認結果 (テスト件数・review-tdd の finding 有無・実機確認) / 既知の残骸 (未対応・スコープ外) / 次にユーザがする決定。review-tdd 以外の観点 (品質・アーキテクチャ・プロダクト readiness) の深いレビューが必要そうであれば、末尾で `/workflow-review` の手動起動を案内する (自動では起動しない)。
