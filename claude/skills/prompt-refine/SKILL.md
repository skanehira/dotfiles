---
name: prompt-refine
description: "作業依頼のプロンプトを、現在のセッションモデルの公式プロンプティングベストプラクティス (references/ に同梱) に沿って書き直し、ユーザ承認後にそのプロンプトで作業を続行する。「プロンプトを最適化して」「ベストプラクティスに沿ったプロンプトにして」「プロンプトを整えてから進めて」「/prompt-refine <プロンプト>」などで起動。"
argument-hint: <作業依頼のプロンプト>
---

# prompt-refine — モデル別ベストプラクティスでのプロンプト整形

作業依頼のプロンプトを、いま動いているセッションモデル向けの公式プロンプティングガイドと突き合わせて書き直し、ユーザの承認を得てからそのプロンプトで作業を続行する。

## [1/6] 対象プロンプトの特定

- `$ARGUMENTS` があればそれを対象にする
- なければ直前のユーザー依頼を対象にする
- どちらを対象にしたかを出力で明示する

## [2/6] モデル判定と reference の読み込み

system prompt に記載されている自分のモデル ID を見て、下表に従い該当する reference ファイルを Read する。

| モデル ID パターン                  | 読む reference                               |
| ----------------------------------- | -------------------------------------------- |
| `claude-fable-5` 系 / mythos 系     | `references/fable-5.md`                      |
| `claude-opus-4` 系 (4.8 等)         | `references/opus-4-8.md`                     |
| `claude-sonnet-5` 系                | `references/sonnet-5.md`                     |
| 上記以外 (haiku 等、専用ページなし) | `references/general.md` (汎用フォールバック) |

## [3/6] 突き合わせ

reference に書かれているパターン・注意点と、対象プロンプトの内容を照合し、**そのプロンプトに実際に関係する観点だけ**を適用対象として選ぶ。

reference は「そのモデルで起こりがちな挙動のズレ」を列挙したものであり、チェックリストではない。全項目を機械的に全部盛りしない。例えば短い単発タスクのプロンプトに、長時間自律実行やメモリシステムの指示を追加する必要はない。

## [4/6] 不足情報の収集

ユーザにしか決められない情報 (ゴールの曖昧さ、動作検証の手段、スコープ境界など) があれば `AskUserQuestion` で確認する。

- 質問は Q1 / Q2 のようにナンバリングする
- 選択肢は A / B / C とラベル付けし、Yes/No や選択肢から選べる closed question にする

逆に、会話履歴やリポジトリから一意に決まる情報は自動で埋め、**その選択と根拠を出力に明示する**。ユーザが意図との乖離に気づける状態を保つ。

## [5/6] 書き直し

- 元のプロンプトと同じ言語で書き直す
- 元の意図・スコープは変えない
- 改善は「構造化」「曖昧さの解消」「reference 由来の具体的な指示の追加」に留める

## [6/6] 提示と承認

書き直したプロンプト全文と、「どの observation をなぜ適用したか」の簡潔な要約を通常のテキストでユーザに提示したうえで、末尾に番号付き選択肢を **テキストで** 質問する（`AskUserQuestion` は使わない。ダイアログ UI がプロンプト全文の表示スペースを圧迫し、ユーザが書き直し内容を確認できなくなるため）。

```text
1. このまま続行 — 書き直したプロンプトを正式な作業依頼として作業を開始する
2. 修正したい — フィードバックを踏まえて [4/6]〜[6/6] をやり直す
3. プロンプトだけ受け取る — 作業は開始せず、書き直したプロンプトの提示のみで終了する
```

- **「このまま続行」選択時**: 書き直したプロンプトを正式な作業依頼として扱い、通常の作業ルール (CLAUDE.md のトリアージ・rules の参照など) に従って作業を開始する
- **「修正したい」選択時**: 続けて修正内容を受け取り、[4/6]〜[6/6] を再実行する
- **「プロンプトだけ受け取る」選択時**: 作業を開始せず終了する

---

## references/ の更新

各 reference は取得時点のスナップショットであり、公式ドキュメントの更新には自動追従しない。内容が古いと感じたら以下で再取得する (各ファイル冒頭に取得元 URL と取得日をコメントで記載している)。

```bash
curl -fsSL https://platform.claude.com/docs/ja/build-with-claude/prompt-engineering/prompting-claude-fable-5.md > references/fable-5.md
curl -fsSL https://platform.claude.com/docs/ja/build-with-claude/prompt-engineering/prompting-claude-opus-4-8.md > references/opus-4-8.md
curl -fsSL https://platform.claude.com/docs/ja/build-with-claude/prompt-engineering/prompting-claude-sonnet-5.md > references/sonnet-5.md
curl -fsSL https://platform.claude.com/docs/ja/build-with-claude/prompt-engineering/claude-prompting-best-practices.md > references/general.md
```
