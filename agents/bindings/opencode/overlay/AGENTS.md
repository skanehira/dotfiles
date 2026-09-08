## OpenCode に配られているもの

この文書自体が生成物である。共通の正本 (`dotfiles/agents/AGENTS.md`) に OpenCode 向けの overlay
(`dotfiles/agents/bindings/opencode/overlay/AGENTS.md`) をマージしたものが
`~/.config/opencode/AGENTS.md` に置かれる。
**上に書かれている共通ルールはこのファイルに含まれているので、他のファイルを読みに行く必要はない。**

| 要素 | 配布先 | 正本 | 反映のタイミング |
| --- | --- | --- | --- |
| このグローバル指示 | `~/.config/opencode/AGENTS.md` | `agents/AGENTS.md` + `agents/bindings/opencode/overlay/AGENTS.md` | `drs` / `hms` が要る (生成物) |
| スキル | `~/.config/opencode/skills/<name>` | `agents/skills/` | `drs` / `hms` が要る (生成物) |
| subagent | `~/.config/opencode/agents/*.md` | `agents/subagents/*.md` を変換したもの | `drs` / `hms` が要る (生成物) |
| ルール | `~/.agents/rules/opencode/` を絶対パスで直接 Read する | `agents/rules/` | `drs` / `hms` が要る (生成物) |

`~/.agents/skills/` は使わない。ここは他ツールが入れたスキルの領域で、Codex と OpenCode の
両方が探索するためランタイム別の生成物を置けない。`~/.claude/skills/` も読まない
(`OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1` で切ってある。これが効いていないと同名スキルの
どちらが採用されるかが実行ごとに変わる)。

配布されているか自分で確かめる:

```bash
# パイプに繋ぐと出力が途中で切れるので必ずファイルに落とす (実測: パイプだと毎回違う件数になる)
opencode debug skill > /tmp/s.json && rg -c '"name"' /tmp/s.json
ls ~/.config/opencode/skills/.harness-manifest.json  # 生成でしか作られない
opencode agent list                                   # subagent 4 本が出る
echo $OPENCODE_DISABLE_CLAUDE_CODE_SKILLS             # 1 でなければターミナルを開き直す
```

生成物には `.harness-manifest.json` が同居し、`drs` / `hms` のたびに上書きされる。**手で編集しない。**
手で流し直すときは `agents/scripts/build-harness.ts` を直接叩く (使い方は引数なしで実行すると出る)。

## hooks は OpenCode では動かない

**OpenCode に hooks は配られていない。** そもそもこのハーネスは機械ゲートを 1 本も持っていないうえ、OpenCode はシェル hooks 自体を持たない (JS プラグイン API しか無く、しかもコマンドに stdin を渡さず stdout も解釈しないため deny するゲートには使えない)。

dev-impl の修正ラウンド上限は**自律遵守**である。

## 読み替えが要らなくなったもの / まだ要るもの

ハーネスは配布時に語彙を OpenCode のものへ展開している。本文に出てくる
`question` / `todowrite` / `task` ツール / `explore` / `general` や
`~/.agents/rules/opencode/...` は**すでに OpenCode の語彙**なので、読み替えずそのまま使う。

置換で吸収できないものだけが残る。

- **呼び出し例の引数の形は Claude Code のもの**。ツール名は展開済みだが、
  `question({ questions: [...] })` のような例に出てくる引数の構造は Claude Code の
  スキーマのまま。**自分のツールのスキーマに合わせて読み替える**
- **`task` ツールに渡す `model` / `subagent_type`** は subagent の生成物に表現手段が
  無く落ちるので、**親のモデルを継承する**。`@<name>` のメンションでも起動できる
- **スキルの相互呼び出し**で `slide-plugin:*` / `document-skills:*` のような Claude 専用
  プラグインのスキルが指定されている場合は、その旨を伝えて代替手段を提案する
- **`chrome-devtools` の MCP ツール**: **未配布**。`opencode.json` に MCP の設定が無い。
  必要になったら報告して指示を仰ぐ
- **`{{@scripts-root}}`** は 3 者で共有している。Claude Code 用のパスに見えても同一
  マシン上のファイルなのでそのまま実行する
- **skill の frontmatter** (`allowed-tools` / `model` / `argument-hint` 等): OpenCode は
  `name` / `description` / `license` / `compatibility` / `metadata` 以外を無視する。
  制約として書かれている内容は本文と同じ重みで自分で守る
- **`/model` コマンドと `Fable` / `Mythos` の tier 名**: Claude Code 固有。セッションモデルの切り替え手段と世代名は自分のランタイムのものに読み替える
- **`ScheduleWakeup`**: OpenCode に相当機能が無い。バックグラウンドタスクの追跡は自分から
  状態を取りに行く運用で代替する

ここに無い Claude 固有の記述に出会ったら、勝手に読み替えず**その旨を報告して指示を仰ぐ**。
