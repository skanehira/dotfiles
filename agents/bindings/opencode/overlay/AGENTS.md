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
| ルール | `~/.claude/rules/` を絶対パスで直接 Read する | `agents/rules/` | `drs` / `hms` が要る (生成物) |

`~/.agents/skills/` は使わない。ここは他ツールが入れたスキルの領域で、Codex と OpenCode の
両方が探索するためランタイム別の生成物を置けない。`~/.claude/skills/` も読まない
(`OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1` で切ってある。これが効いていないと同名スキルの
どちらが採用されるかが実行ごとに変わる)。

配布されているか自分で確かめる:

```bash
opencode debug skill | rg -c '"name"'    # スキルが並ぶ
opencode agent list                       # subagent 4 本が出る
echo $OPENCODE_DISABLE_CLAUDE_CODE_SKILLS # 1 でなければターミナルを開き直す
```

生成物には `.harness-manifest.json` が同居し、`drs` / `hms` のたびに上書きされる。**手で編集しない。**
手で流し直すときは `agents/scripts/build-harness.ts` を直接叩く (使い方は引数なしで実行すると出る)。

## hooks は OpenCode では動かない

**`fix-round-guard` は OpenCode では発火しない。** OpenCode はシェル hooks を持たず、JS プラグイン API しか無い。しかもそのプラグインはコマンドに stdin を渡さず stdout も解釈しないため、deny する機械ゲートとしては使えない。

したがって OpenCode 上では dev-impl の修正ラウンド上限が**機械ゲート無しの自律遵守**になり、上記「評価関数」が採点者として挙げる 4 者のうち hooks が居ない。残るのはユーザー / レビュー subagent / プロジェクトの CI である。

## Claude Code 由来の記述の読み替え

スキル・subagent・ルールの本文はまだ Claude Code 向けの語彙で書かれている。以下の記述が出てきたら OpenCode 上では次のように読み替える。

| Claude の記述 | OpenCode での扱い |
| --- | --- |
| `AskUserQuestion` ツール | `question` ツールで確認する |
| `Agent` ツールでの subagent 起動 | `task` ツールに `~/.config/opencode/agents/*.md` の名前を渡す。`@<name>` のメンションでも起動できる。`model` / `subagent_type` は生成物に表現手段が無く落ちるので**親のモデルを継承する** |
| `Skill` ツールでの相互呼び出し | `skill` ツールを使う。Claude 専用プラグインのスキル (`slide-plugin:*` / `document-skills:*`) は OpenCode に存在しないので、その旨を伝えて代替手段を提案する |
| `TodoWrite` / `TaskCreate` / `TaskUpdate` | `todowrite` ツールで置き換える |
| `WebFetch` | `webfetch` ツール |
| `WebSearch` | `websearch` ツール |
| `run_in_background` での Bash 起動 | OpenCode のバックグラウンド実行。同期を指示している箇所 (`run_in_background: false`) は素直に同期で回す |
| `plan mode` | 組み込みの `plan` agent に切り替える |
| `chrome-devtools` の MCP ツール | **未配布**。`opencode.json` に MCP の設定が無い。必要になったら報告して指示を仰ぐ |
| `~/.claude/rules/...` / `~/.claude/scripts/...` | 同一マシン上のファイルなのでそのまま Read / 実行する |
| `~/.claude/agents/...` | OpenCode 側の実体は `~/.config/opencode/agents/*.md` である |
| skill の frontmatter (`allowed-tools` / `model` / `argument-hint` 等) | OpenCode は `name` / `description` / `license` / `compatibility` / `metadata` 以外を無視する。制約として書かれている内容は本文と同じ重みで自分で守る |
| 組み込み subagent 名 (`Explore` / `general-purpose`) | OpenCode の `explore` / `general` で代替する |

ここに無い Claude 固有の記述に出会ったら、勝手に読み替えず**その旨を報告して指示を仰ぐ**。
