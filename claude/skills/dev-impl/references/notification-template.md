# 通知テンプレート (dev-impl Step 6 / エスカレ停止時)

`dev-impl/SKILL.md` の Step 6 (全フェーズ完了サマリ) とエスカレ停止時の挙動から参照される出力テンプレート。裏付け確認の規則・停止条件・停止時の処理手順は SKILL.md 本体にあるので、そちらを先に読んでから該当テンプレートだけをここで参照する。

## 完了サマリ (Step 6)

```
✅ dev-impl 完了 (status: <done|partial|escalated>)

実装フェーズ: N / N (全完了)
新規コミット: <git rev-list --count $START_SHA..HEAD>
動的修正: P1 <X> 回 / P2 <Y> 回 / P3 0 回 (停止無し)
ゴール達成: <achieved>/<total> (うち手動確認待ち <manual_pending>)
受入監査 (spec_compliance): high <X> 件 / medium <Y> 件 / vacuous_verification による手動 pending 落ち <Z> 件
未検証 (skip された検証): <verification_skipped の一覧、なければ「なし」>
UI/UX gap: <未実装画面数> 画面 / <未実装ナビ経路数> 経路 / frontend-design: <適用|未適用>
実装ノート: 設計判断 <X> 件 / 未解決の質問 <Y> 件 (詳細は HTML レポート)

範囲:
- 開始 SHA: <START_SHA>
- 終了 SHA: <HEAD>
- run_id: <run_id>

次のステップ:
- HTML レポート: docs/dev-impl-reports/<run_id>.html を開いて意思決定と検証結果を確認
- UI/UX gap (status: partial の場合): docs/POST_MVP.md の「UI/UX gap」セクションで残課題を確認
- 手動確認待ちゴール (あれば): <ゴール ID リスト> を実機で検証
- 手動レビュー: git log <START_SHA>..HEAD で差分確認
- push はユーザ手動で実行
```

## エスカレ停止通知

```
⛔ dev-impl 停止

停止フェーズ: <フェーズ名>
停止理由: <理由カテゴリ>
詳細:
  <違反内容や乖離の構造化サマリ>

範囲:
- 完了済みフェーズ: <完了数> / <全フェーズ数>
- 最終成功 commit: <SHA>
- 実装ノート: 設計判断 <X> 件 / 未解決の質問 <Y> 件 (詳細は HTML レポート)

次のステップ:
- 上記詳細を踏まえ DESIGN.md / DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md を見直す
- (フェーズ実装やり直したい場合) git restore で working tree クリア後、dev-impl 再起動
- (DESIGN 修正後) /dev-spec で TODO 再生成後、/dev-impl を再起動
```
