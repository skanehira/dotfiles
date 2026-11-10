## issue とボードの運用

issue の状態はラベルで管理する。Project <!-- 記入: Project の URL --> は人が状況を把握するためのもので、Status はラベルに合わせて GitHub Actions が動かす。状態の定義、着手可能の基準、優先度の定義は dotfiles の `dev-triage` スキルの references (`~/.claude/skills/dev-triage/references/`) が正本である。このリポジトリに `docs/ISSUE_TRIAGE.md` があれば、そこに書かれた定義を優先する。

### issue を作ったとき

状態のラベルは付けずに作る。`dev-triage` が、種別のラベルを確かめ、採点して本文に `## 優先度` を書き、状態のラベルを 1 つ付ける (親は `tracking`、人か顧客の判断が要るものは `needs-human`、それ以外の開発の issue は `needs-design`)。

`ready` は人が仕様を承認した印なので、AI は自分で付けない。

### 作業を進めるとき

| タイミング | ラベル |
| --- | --- |
| 設計 PR か修正方針を出した | `needs-design` を外して `design-review` を付ける。設計 PR の本文には `Design-for: #<issue 番号>` を書く |
| 人が承認した | `ready` (設計 PR の merge では GitHub Actions が付ける) |
| 実装を始めた | `ready` を外して `in-progress` を付ける |
| 人の判断が要って止めた | `needs-human` を付ける |
| 人が `needs-human` に回答した | 人が回答を issue に書き、止めたスキルのコメントの案内に従う。`dev-feat-spec` が止めたものは `needs-human` を外すだけでよい。`dev-triage` が止めたものはコメントの案内に従う。`/dev-impl` が止めたものは、回答を本文か参照の docs に反映してから、`needs-human` を外して `ready` を付ける (`~/.claude/skills/dev-triage/references/issue-states.md`「状態の管理」) |

Status を手で動かさない。ラベルと Status が食い違ったら、ラベルを正としてラベルを付け直す (付け直すと Actions が Status を揃える)。
