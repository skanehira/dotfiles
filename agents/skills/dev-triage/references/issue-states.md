# issue の状態と着手可能の基準

- 種別: 開発プロセスの規約 (全プロジェクト共通の定義)
- 生成者: dotfiles の `dev-triage` スキル (このファイルが正本)
- 消費者: `dev-triage` (状態を付ける)、`dev-feat-spec` (設計して `design-review` にする)、`dev-project-setup` (ラベル・Project の列・GitHub Actions をこの表に合わせて作る)、`/dev-impl` (`ready` を実装する)、設計をレビューする人

対象のリポジトリに `docs/ISSUE_TRIAGE.md` があり、このファイルと同じ見出しの節 (例: `## 着手可能の基準`) があれば、その節をこのファイルの同じ節の代わりに使う。ラベルの名前と状態の遷移 (「状態の管理」の表) は上書きできない (GitHub Actions と他のスキルに固定で書かれているため)。

## 状態の管理

ラベルで状態を管理し、GitHub Project で人が状況を把握する。人の作業は設計の確認だけで、整理、設計、実装、merge は AI が進める。Deploy は人が実行する。

| 状態 | ラベル | Status | 次に動く人 | 次へ進む条件 |
| --- | --- | --- | --- | --- |
| 未整理 | なし | 未整理 | AI (`dev-triage`) | 状態のラベルを付けた |
| 設計待ち | `needs-design` | 設計待ち | AI (`dev-feat-spec`) | 設計 PR か修正方針を出した |
| 設計レビュー | `design-review` | 設計レビュー | 人 | 承認した |
| 着手可能 | `ready` | 着手可能 | AI (`/dev-impl`) | `/dev-impl` が着手した |
| 作業中 | `in-progress` | 作業中 | AI (`/dev-impl`) | PR を merge した |
| 判断待ち | `needs-human` | 判断待ち | 人 | 回答を issue に書き、`needs-human` を外した |

- `ready` は人が仕様を承認した印で、`/dev-impl` の入力である。AI は自分で付けない
- 設計 PR は本文に `Design-for: #<issue 番号>` の行を書く。人が merge すると、GitHub Actions (`.github/workflows/design-approved.yml`) が対象の issue に `ready` を付ける。設計 PR は issue の Development に紐づけない (`Closes` などのキーワードを書かない)。紐づいた PR は merge で issue を close するため
- 設計書の変更が要らない issue は、AI が issue の本文に修正方針を書いて `design-review` を付ける。人が確認して `ready` を付ける
- 実装の PR は本文の先頭行に `Closes #<issue 番号>` を書き、issue の Development に必ず紐づける。人が確認せず、AI が merge する。merge で issue は close され、Status は「完了」になる
- ラベルが変わると、GitHub Actions (`.github/workflows/issue-state-sync.yml`) が Project の Status を動かす。Status を手で動かさない
- 親 issue は `tracking` を付ける。Status は「作業中」になり、進捗は子に任せる。親は実装の対象ではない
- 種別はラベルで見る: `bug` / `enhancement` / `refactoring` / `question`。事業・運営を同じボードに置くプロジェクトでは `事業・運営` を付け、AI の整理と開発の対象から外す
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
3. 本文が**自己完結**している。ゴール・設計・DoD・非スコープ・依存 の 5 節が揃っている。会話にしかない前提を書かない
4. **DoD が実行可能で空虚でない**。具体的なコマンドと期待結果がある。存在の確認だけ・恒真の grep を DoD にしない
5. **依存の順序が決まっている**。`Depends on` の先は open でもよく、`/dev-impl` が依存順に実装する。依存グラフに循環がない
6. **人間・外部の判断を要さない**。顧客の回答・法務・実環境の設定や承認が要るものは `needs-human` にする

## needs-human のコメントに載せる会話の入口

`agent-loop` から起動された run (`claude --bg`) では、環境変数 `CLAUDE_JOB_DIR` が `~/.claude/jobs/<id>` を指す。この run が `needs-human` を付けるコメントを書くときは、スキルの印 (`<!-- dev-triage -->` など) の前に次の 1 行を足し、印のファイルを置く。人は、あとからこの会話を開いて、判断の経緯を読んだり続きを頼んだりできる。

```bash
[ -n "${CLAUDE_JOB_DIR:-}" ] && basename "$CLAUDE_JOB_DIR" && touch "$CLAUDE_JOB_DIR/needs-human"   # 出力が <id>
```

```markdown
この判断をした run の会話は、このマシンで `claude attach <id>` を実行すると開けます。
```

- `agent-loop` は、印のファイルがあるセッションを `done` でも消さず、会話と worktree を残す。読み終えたら人が片付ける (dotfiles の `CLAUDE.md`「AI が issue を進める開発フロー」節の「残った会話と worktree」)
- `CLAUDE_JOB_DIR` が無いとき (人が手元でスキルを起動したとき) は、行もファイルも足さない。会話はその人の手元にある
- 使う側: `dev-triage` (手順 5 の 2)、`dev-feat-spec` (手順 7 の「止める」)、`/dev-impl` (2.6 の駐車)
