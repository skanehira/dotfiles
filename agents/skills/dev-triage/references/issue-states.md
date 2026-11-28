# issue の状態と着手可能の基準

- 種別: 開発プロセスの規約 (全プロジェクト共通の定義)
- 生成者: dotfiles の `dev-triage` スキル (このファイルが正本)
- 消費者: `dev-triage` (状態を付ける)、`dev-feat-spec` (設計して `design-review` にする)、`/dev-impl` (`ready` を実装する)、設計をレビューする人

対象のリポジトリに `docs/ISSUE_TRIAGE.md` があり、このファイルと同じ見出しの節 (例: `## 着手可能の基準`) があれば、その節をこのファイルの同じ節の代わりに使う。ラベルの名前と状態の遷移 (「状態の管理」の表) は上書きできない (スキルとスクリプトに固定で書かれているため)。

## 状態の管理

issue の状態はラベルで管理する。スキルはどれも人が手元で起動し、ラベルを読んで対象の issue を決める。人の作業は、スキルの起動と設計の確認と `ready` の付与である。整理、設計、実装、merge は AI が進め、Deploy は人が実行する。

| 状態 | ラベル | 次に動く人 | 次へ進む条件 |
| --- | --- | --- | --- |
| 未整理 | なし | AI (`dev-triage`) | 状態のラベルを付けた |
| 設計待ち | `needs-design` | AI (`dev-feat-spec`) | 設計 PR か修正方針を出した |
| 設計レビュー | `design-review` | 人 | 承認して `ready` を付けた |
| 着手可能 | `ready` | AI (`/dev-impl`) | `/dev-impl` が着手した |
| 作業中 | `in-progress` | AI (`/dev-impl`) | PR を merge した |
| 判断待ち | `needs-human` | 人 | 回答を issue に書き、`needs-human` を外した |

- `ready` は人が仕様を承認した印で、`/dev-impl` の入力である。AI は自分で付けない
- 人は承認した issue のラベルを `gh issue edit <番号> --add-label ready --remove-label design-review` で付け替える。設計 PR なら merge した後に、修正方針なら issue の本文を読んで付け替える
- 設計 PR は本文に `Design-for: #<issue 番号>` の行を書く。この行は、承認したら `ready` にする issue を人に示し、`dev-feat-spec` が設計済みの issue を見分けるのにも使う。設計 PR は issue の Development に紐づけない (`Closes` などのキーワードを書かない)。紐づいた PR は merge で issue を close するため
- 実装の PR は本文の先頭行に `Closes #<issue 番号>` を書き、issue の Development に必ず紐づける。人が確認せず、AI が merge する。merge で issue は close される
- 親 issue は `tracking` を付け、進捗は子に任せる。親は実装の対象ではない
- 種別はラベルで見る: `bug` / `enhancement` / `refactoring` / `question`。事業・運営の issue を同じリポジトリに置くプロジェクトでは `事業・運営` のラベルを作って付け、AI の整理と開発の対象から外す
- ラベルは、使うスキルが前提の確認で用意する。`dev-triage` と `dev-feat-spec` は `~/.claude/skills/dev-triage/scripts/setup-labels.sh` を、`/dev-spec` と `/dev-impl` は dev-spec の `references/issue-template.md`「ラベルの用意」を実行する。どちらも何度実行してもよい
- 判断待ちから戻るときは、人が回答を issue に書き、止めたスキルのコメントの案内に従ってラベルを直す

  | 止めたスキル | 人が直すラベル | 次に動くもの |
  | --- | --- | --- |
  | `dev-triage` | コメントの案内に従う (多くは `needs-human` を外すだけ。緊急枠は `needs-design` に付け替え、着手済みは `ready` を付ける) | 次の `dev-triage` が回答を読んで整理し直す |
  | `dev-feat-spec` | `needs-human` を外す (`needs-design` は残っている) | 次の `dev-feat-spec` が設計し直す |
  | `/dev-impl` | 回答を issue の本文か参照の docs に反映してから、`needs-human` を外して `ready` を付ける (implementer は本文と docs しか読まないため) | 次の `/dev-impl` が `issue-<N>` ブランチから再開する |

  `/dev-impl` が止めた issue で `ready` を付け忘れると、状態のラベルが無くなる。`dev-triage` は `issue-<N>` ブランチを見てこれに気付き、設計し直さずに `needs-human` に戻す

## 着手可能の基準

issue が次をすべて満たすとき、人は `ready` を付けてよい。`dev-feat-spec` は、書き直した本文がこの基準を満たすようにしてから `design-review` にする。

1. **実装の単位**である。親 (`tracking`)・質問・事業・運営・人手による検証だけのものは対象外。1 issue = 独立して検証できる 1 作業単位にする
2. **設計が確定**している。「設計」節が指す設計書 (`docs/design/features/*.md` と `docs/design/DESIGN.md` の該当節) に、未決の「決めること」が残っていない
3. 本文が**自己完結**している。ゴール・設計・DoD・非スコープ・依存 の 5 節が揃っている。ゴールだけを読んだ人が内容を理解でき、ほかの 4 節は折りたたまれている (型は dev-spec の `references/issue-template.md`「子 issue テンプレート」)。この型ができる前に書かれた issue は、折りたたまれていなくてよい。会話にしかない前提を書かない
4. **DoD が実行可能で空虚でない**。具体的なコマンドと期待結果がある。存在の確認だけ・恒真の grep を DoD にしない
5. **依存の順序が決まっている**。`Depends on` の先は open でもよく、`/dev-impl` が依存順に実装する。依存グラフに循環がない
6. **人間・外部の判断を要さない**。顧客の回答・法務・実環境の設定や承認が要るものは `needs-human` にする
