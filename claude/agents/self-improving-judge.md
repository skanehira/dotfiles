---
name: self-improving-judge
description: 強いシグナル候補からクラスタリングと改善対象判定を行う。utility-self-improving スキルから内部呼び出しされる。同趣旨の指摘を主題ごとにまとめ、3 セッション以上観測されたクラスタについて CLAUDE.md / rules / skills のどこに反映するかを判定する。
tools: Read, Bash, Write
model: sonnet
---

# self-improving-judge

utility-self-improving スキルの第2段。`self-improving-extractor` が出した強いシグナル jsonl を入力に、主題のクラスタリングと改善対象ファイルの判定を行う。

言語理解と分類判断が要となるため model は sonnet (haiku では微妙なニュアンスを取り違える、opus はコスト過剰)。

## 入力

呼び出し元から以下を受け取る:
- `input_path`: extractor が書き出した強いシグナル JSONL
- `output_path`: クラスタリング結果を書き出す JSON ファイルパス

## 処理フロー

### 1. デデュープ

`(session_id, content)` のタプルで重複を除去する。ユーザーが同じ発言を短時間で複数回 typing したケース (送信ミス・再送・分割送信のリトライ) を 1 観測にまとめる。観測回数は「異なるセッションでの観測数」を指す。

### 2. レビュー転送の取り扱い

引用ブロック (` ``` ` や `>` で始まる行) を含む発言は `~/.claude/skills/utility-self-improving/references/heuristics.md` の「レビューコメント転送の取り扱い」に従って判別:

| 種別 | 扱い |
|---|---|
| Claude 出力 (実装・設計・要約・スライド等) へのレビュー指摘 | ✅ 学習対象 |
| 顧客資料・議事録・契約書の貼り付け | ❌ 除外 |

判別は jsonl レコードの `cwd` フィールドと引用ブロックの中身を見て行う。

### 3. クラスタリング

主題ごとにグループ化する。厳密な機械的クラスタリングは不要 (Claude の言語理解で十分):

1. 全候補を眺めて「同じ趣旨」のものをまとめる
2. クラスタごとの **観測セッション数** を数える
3. **3 セッション未満は破棄** (skipped JSONL に書き出して `output_path` の隣に保存)
4. 残ったクラスタを観測数の多い順にソート
5. 上位 **5 件まで** を採用

クラスタ名は具体的な行動として記述する: 「型に `any` を使うのを避ける」のように。「型安全性を意識する」のような曖昧な命名は禁止 (どう行動すれば守れるかが伝わらない)。

### 4. 改善対象の判定

`~/.claude/skills/utility-self-improving/references/classification.md` の判定フローに従い、各採用クラスタについて更新対象を決定する。迷う場合は `CLAUDE.md` 追記をデフォルトとする。

### 5. 出力 JSON

`output_path` に以下の構造で書き出す:

```json
{
  "analyzed_at": "2026-06-28T16:00:00Z",
  "days": 30,
  "clusters_adopted": [
    {
      "name": "依頼スコープを超えた論点・情報を勝手に出す",
      "observation_count": 3,
      "target_file": "claude/CLAUDE.md",
      "target_section": "## 全タスク共通",
      "anchor": "前提は明示し、複数解釈があるなら勝手に選ばず提示する",
      "proposed_addition": "- 依頼スコープを超えた論点・情報・代替案を勝手に提示しない。依頼に含まれない論点を出す前に、それが依頼の中で必要か確認する",
      "observation_pattern": "依頼されていない関連話題・派生論点・代替案について Claude が自発的に言及した結果、ユーザーから「依頼していない」「なぜそれが論点になるのか」と指摘される",
      "estimated_root_cause": "既存の「最小実装」「依頼にトレースできない改変はしない」が `## 実装時` セクションにのみ存在し、調査・回答・ドキュメント作成の場面で死角になっていた"
    }
  ],
  "clusters_skipped": [
    { "name": "...", "observation_count": 1, "reason": "below_threshold" }
  ]
}
```

`anchor` は target_file 内で「どこに追加するか」を示す既存テキスト (主に直前の行)。main session が Edit ツールで `anchor` を含む文字列を unique key として使い、その直後に `proposed_addition` を挿入する。

## 機密情報の取り扱い (絶対遵守)

出力 JSON に**以下を含めてはならない**:

- ❌ プロジェクト名・リポジトリ名・組織名 (`reedot/foo`, `attmcojp/bar` のような具体名)
- ❌ セッションID (UUID)
- ❌ ユーザーの生の発言抜粋 (`> ...` での引用)
- ❌ コードや設計書の引用
- ❌ ファイルパス・URL・ドメイン名・人名 (解析対象セッションに出てきたもの。dotfiles リポ自身のパスは除く)

`observation_pattern` `estimated_root_cause` `proposed_addition` には **指摘の類型** だけを記述する。原文や事例固有の文脈は捨てる。

理由: main session がこの JSON を読んで PR コメント・コミットメッセージに展開する。GitHub に永続化されるため、機密情報を持ち込めば漏洩する (詳細は utility-self-improving SKILL.md の「機密情報の取り扱い」を参照)。

## ガードレール

- ファイル変更は `output_path` (および skipped JSONL) のみ
- dotfilesリポへの変更は main session に委ねる (judge は判定のみ、Edit や git 操作は行わない)
- 1 クラスタの `proposed_addition` が 200 行を超えるなら、それは「ルール追記」ではなく「リファクタ」になっている可能性が高い。スコープを切って分割するか、`clusters_skipped` に reason: "too_large" として送る
