# 通知テンプレート (dev-impl Step 6 / エスカレ停止時)

`dev-impl/SKILL.md` の Step 6 (全フェーズ完了サマリ) とエスカレ停止時の挙動から参照される出力テンプレート。裏付け確認の規則・停止条件・停止時の処理手順は SKILL.md 本体にあるので、そちらを先に読んでから該当テンプレートだけをここで参照する。

## 完了サマリ (Step 6)

```
✅ dev-impl 完了 (status: <done|partial|escalated>)

実装フェーズ: N / N (全完了)
新規コミット: <git rev-list --count $START_SHA..HEAD>
動的修正: P1 <X> 回 / P2 <Y> 回 / P3 0 回 (停止無し)
  P2 の内訳 (設計を実装に合わせて書き換えた箇所。要確認):
  - <section> — <what> (<commit_sha>)
  ... P2 が 0 回なら「P2 なし」の 1 行
ゴール達成: <achieved>/<total> (うち手動確認待ち <manual_pending>)
受入監査 (spec_compliance): high <X> 件 / medium <Y> 件 / vacuous_verification による手動 pending 落ち <Z> 件
未検証 (skip された検証): <verification_skipped の一覧、なければ「なし」>
DoD (手動確認待ち): <issue 番号と `DoD (手動):` の本文。自動では確かめられないので人が見る。なければ「なし」>
DoD の自動コマンドが 0 件だった issue: <番号一覧、なければ「なし」> (抽出の空振りと「手動のみ」を区別できないため通過扱いにしていない)
UI/UX gap: <未実装画面数> 画面 / <未実装ナビ経路数> 経路 / frontend-design: <適用|未適用> (product-mode: cli の場合は「該当なし (product-mode: cli)」)
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

停止時点の状態:
- close 済み issue: <このループで閉じた issue 番号、無ければ「なし」>
- 停止した issue: #<N> (ラベル: <in-progress | needs-human>)、または「なし (着手中の issue が無い時点の停止 — Step 1 / 1.5 / 2 / Step 5 系。ラベル操作なし)」
  - `in-progress` = 再実行で解決しうる停止。`/dev-impl` の再実行で Step 2 が再開対象として拾う
  - `needs-human` = 人間の判断が要る停止。対応後、次の `/dev-impl` 起動時に Step 0 が確認してラベルを戻す
  - どちらを貼るかは SKILL.md「エスカレ停止時の挙動」の停止理由別の表に従う
- ラウンドのコミット: `git log --oneline <PHASE_START_SHA>..HEAD` の結果 (フェーズ最終コミットは未実施 = 全体スイートと DoD を通っていない)
- 未コミットの変更: `git status --porcelain` の結果 (通常は空。非空なら検査 agent の汚染)
- レビュー結果 JSON: ~/.claude/logs/dev-impl/<run_id>/reviews/phase-<識別子>/ (issue 番号ではなくフェーズ識別子)

次のステップ:
- 上記詳細を踏まえ DESIGN.md / DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md を見直す
- (issue の実装をやり直したい場合) `git reset --hard <PHASE_START_SHA>` で巻き戻してから dev-impl 再起動 (レポート・設計書のコミットが混ざっていないことを先に確認する)
- (DESIGN 修正後) /dev-spec で TODO 再生成 → issue 更新後、/dev-impl を再起動
```
