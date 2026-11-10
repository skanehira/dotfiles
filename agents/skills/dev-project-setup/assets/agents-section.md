## issue とボードの運用

issue の状態はラベルで管理する。Project <!-- 記入: Project の URL --> は人が状況を把握するためのもので、Status はラベルに合わせて GitHub Actions が動かす。状態の定義、着手可能の基準、優先度の定義は [docs/ISSUE_TRIAGE.md](./docs/ISSUE_TRIAGE.md) を参照する。

### issue を作ったとき

作成した直後に状態のラベルを決める。上から順に見て、最初に当てはまる行を使う。開発の issue は本文の `## 優先度` に点数と根拠を書く。種別のラベル (`bug` / `enhancement` / `refactoring` / `question`) は行にかかわらず付ける。

| issue の状態 | ラベル |
| --- | --- |
| 親 issue | `tracking` |
| 人か顧客の判断が要る | `needs-human` |
| 決めることが残っている | `needs-design` |
| 判定する材料が足りない | なし |

`ready` は人が仕様を承認した印なので、AI は自分で付けない。

### 作業を進めるとき

| タイミング | ラベル |
| --- | --- |
| 設計 PR か修正方針を出した | `needs-design` を外して `design-review` を付ける。設計 PR の本文には `Design-for: #<issue 番号>` を書く |
| 人が承認した | `ready` (設計 PR の merge では GitHub Actions が付ける) |
| 実装を始めた | `ready` を外して `in-progress` を付ける |
| 人の判断が要って止めた | `needs-human` を付ける |

Status を手で動かさない。ラベルと Status が食い違ったら、ラベルを正としてラベルを付け直す (付け直すと Actions が Status を揃える)。
