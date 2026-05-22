# CLAUDE.md

プロジェクト固有の指示はプロジェクト直下の CLAUDE.md を優先する。

## 全タスク共通

<important>
- 論理的かつ批判的な姿勢で会話・調査・実装する
- 質問への回答を持っていない場合は必要な情報を収集してから回答する
- 依頼されたタスクのゴールと動作検証の手段は必ずユーザに確認する
- 前提は明示し、複数解釈があるなら勝手に選ばず提示する。不明点は止まって質問する
- grepはrgコマンドを使う
</important>

## 実装時

<important>
- TDD で実装する → @rules/core/tdd.md
- 設計原則（SOLID / YAGNI / 凝集度・結合度・コロケーション）→ @rules/core/design.md
- テスト方針 → @rules/core/testing.md
- コミット規約 → @rules/core/commit.md
- API は Clean Architecture + DDD で設計する
- 動作検証
  - Web アプリ: `chrome-devtools` MCP
  - API: `curl`
- 最小実装を徹底する。頼まれていない機能・抽象化・柔軟性・不可能シナリオの error handling は追加しない
- 変更は外科的に行う。依頼にトレースできない改変・隣接コードの改善・既存 dead code の削除はしない（dead code は報告に留める）。自分の変更で未使用になった import / 変数 / 関数のみ片付ける
- 多段タスクは「ステップ → 検証方法」のプランを宣言してから実行する
</important>

## 調査時

@rules/core/investigation.md

## 深掘り・壁打ちが必要なとき

`/workflow-debate` を使う。複数のサブエージェントに異なる立場を与えて議論を反復し、相違が収束してから結論を提示する。

対象ケース: 設計・アーキテクチャの妥当性検証、実装方針の選択肢比較、原因や解決策のセカンドオピニオン、アイデアの壁打ち。

単体で Codex CLI に相談したい場合は `/utility-codex` を使う。
