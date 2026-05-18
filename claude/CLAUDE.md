# CLAUDE.md

プロジェクト固有の指示はプロジェクト直下の CLAUDE.md を優先する。

## 全タスク共通

<important>
- 論理的かつ批判的な姿勢で会話・調査・実装する
- 質問への回答を持っていない場合は必要な情報を収集してから回答する
- 依頼されたタスクのゴールと動作検証の手段は必ずユーザに確認する
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
</important>

## 調査時

@rules/core/investigation.md

## 深掘り・壁打ちが必要なとき

`/workflow-debate` を使う。複数のサブエージェントに異なる立場を与えて議論を反復し、相違が収束してから結論を提示する。

対象ケース: 設計・アーキテクチャの妥当性検証、実装方針の選択肢比較、原因や解決策のセカンドオピニオン、アイデアの壁打ち。

単体で Codex CLI に相談したい場合は `/utility-codex` を使う。
