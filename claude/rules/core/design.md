# 設計共通ルール

詳細なコード例が必要になったら `rules/core/references/design-examples.md` を Read する。

## SOLID

- **SRP**: 1 モジュール 1 責務。変更する理由が 1 つだけになるようにする
- **OCP**: 既存コードを変更せずに機能追加できる設計にする
- **LSP**: 派生型は基底型と置換可能に保ち、親の契約を破らない
- **ISP**: 使わないメソッドへの依存を強制しない。大きな interface より小さな専用 interface
- **DIP**: 上位・下位モジュールとも抽象に依存させる

## YAGNI

- 「将来必要になるかもしれない」コードは書かず、現在必要な機能のみ実装する
- 自分の変更で生まれた未使用のメソッド・フィールド・パラメータは即削除する（既存の dead code には触れない。CLAUDE.md の外科的変更ルール参照）
- 意図が不明確なコードを変更する前にユーザーに確認する

## 外界 (IO) は必ず DI

外部世界に触れる処理 (fetch / WebSocket / localStorage / Cookie / Date.now() / Math.random() / process.env など) はすべて DI で渡す。グローバルシングルトンや関数内部での直接呼び出しは禁止。理由: テスト時に fake を注入できる。

- IO を内部で呼ぶカスタムフック (`useFetchUser` 等) は禁止。IO は props / context 経由で渡された関数を hook が呼び出す形にする。ステートだけの hook (`useToggle` 等) は OK
- モックの優先順位: ① DI + fake（最優先）→ ② 手書きスタブ → ③ モックライブラリ (MSW 等、最終手段)。ボイラープレートは OpenAPI などからのコード自動生成で解決する
- トランザクション (DB コネクション / tx オブジェクト) も DI で渡す。Repository 内で暗黙に開始しない
- 1 ユースケースの不変条件を守る複数書き込みは単一トランザクションで括る (Unit of Work)。境界は DESIGN_DETAIL_APP.md の「トランザクション境界」の表に従う

## 命名

- `check` / `process` / `handle` / `do` のような曖昧な動詞を避け、具体的なアクションで命名する（`compare_version` / `validate_input` / `fetch_latest_data`）
- 戻り値の型名は操作の結果を説明する名前にする（`VersionCompareResult`。× `CheckResult` / `Data`）

## 凝集度・結合度・コロケーション

- **高凝集**: 1 モジュールは 1 責務。判断基準は「変更理由が 1 つか」「テストが 1 観点に集中できるか」「説明が『〜と〜と〜』ではなく『〜』で済むか」
- **低結合**: 依存は 外部（不安定）→ ドメイン（安定）の一方向。UI 層 → ビジネスロジック層 → ドメインモデル
- **コロケーション**: 関連ファイル（実装・テスト・型）は `features/<機能>/` に同居させる。`__tests__/` へのテスト隔離は禁止

## アンチパターン（避ける）

God Component（責務過多）/ Prop Drilling 地獄 / テストと実装の分離 / Feature Envy（他モジュールのデータへの過度な依存）/ Shotgun Surgery（1 変更で多数ファイル修正）
