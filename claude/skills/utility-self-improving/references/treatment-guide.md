# 施策選択ガイド (treatment-guide)

utility-self-improving の `self-improving-judge` subagent が「**観測した課題から、どの拡張機構をどのスコープで使うか**」を判断するための公式準拠ガイド。

`classification.md` は「rules / skills / agents / hooks のどこに書くか」のファイル振り分けを担当し、本ガイドは「**そもそも rules で十分か、hook へ昇格すべきか、別の機構 (permission / output style / MCP 等) が適切か**」という上位レイヤの判断を担当する。

## 目次

- [大原則](#大原則)
- [強制レベル別の選択肢](#強制レベル別の選択肢)
- [スコープ別の配置場所](#スコープ別の配置場所)
- [観測パターン → 施策 決定表 (Tier A: 即時)](#観測パターン--施策-tier-a-即時施策が明確)
- [観測パターン → 施策 決定表 (Tier B: 慎重検討)](#観測パターン--施策-tier-b-慎重な検討が必要)
- [拡張機構の組み合わせ (Tier C)](#拡張機構の組み合わせ-tier-c)
- [強制レベル昇格の判断軸](#強制レベル昇格の判断軸)
- [skipped クラスタの取り扱い](#skipped-クラスタの取り扱い)
- [公式参照](#公式参照)

## 大原則

### 原則 1: instructions は context、enforcement は hook

> "CLAUDE.md content is delivered as a user message after the system prompt, not as part of the system prompt itself. Claude reads it and tries to follow it, but there's no guarantee of strict compliance, especially for vague or conflicting instructions."
> -- `memory.md`

- `CLAUDE.md` と `rules/` は **ユーザーメッセージとして Claude に渡される文脈** であり、確実な実行を保証しない
- 「確実に止めたい行為」は `PreToolUse` hook で deny する以外に手段はない
- → 観測パターンの **強制必要度** で施策を選ぶ

### 原則 2: 観測の不可逆性が高いほど上位施策へ

- 機密漏出・コード破壊・本番誤デプロイのような不可逆事象 → hook / permission で確実に止める
- 出力スタイルや姿勢の話 → rule で「文脈として供給」で十分

### 原則 3: 最小施策で済むなら最小で

公式の "Build over time" によれば:
- 2 回観測の誤りは CLAUDE.md 1 行追記が起点
- 3 回観測の手順は Skill 化
- 設計上の死角と判断したら Subagent / Hook へ昇格

新規 Skill / Subagent / Hook を生むのは最終手段。先に既存ルールの文言強化で吸収できないか検討する。

## 強制レベル別の選択肢

| 必要性 | 選択肢 | 確実度 | 観測パターン例 |
|---|---|---|---|
| **絶対禁止** | `PreToolUse` hook (deny) または `permissions.deny` | 高 (100%) | `rm -rf` の誤実行、.env への書き込み、本番ブランチへの force push |
| **強い推奨** | rule + Skill + 補助 hook (gate) | 中 | 設計逸脱、必須テスト省略、コミット規約違反 |
| **助言** | CLAUDE.md / rules (paths-scoped 可) | 低 (文脈次第) | 命名規約、姿勢、回答の冗長さ |

## スコープ別の配置場所

| スコープ | 配置 | 例 |
|---|---|---|
| 全タスク・全ファイル | `~/.claude/CLAUDE.md` (user) or project `CLAUDE.md` | 「依頼スコープ外を出さない」「具体例を併記」 |
| 特定ファイル型・特定ディレクトリ | `.claude/rules/*.md` + `paths` frontmatter | `**/*.tsx` で React ルール、`**/*.go` で Go ルール |
| ワークフロー手順 | Skill (`.claude/skills/*/SKILL.md`) | `/workflow-commit`, `/utility-self-improving` |
| 専門判断・context isolation | Subagent (`.claude/agents/*.md`) | `self-improving-judge`, `architecture-guard` |
| 生命周期イベント (block 可能・観測専用) | Hook (`settings.json`) | `PreToolUse` で deny、`SessionEnd` で archive |
| 外部システム連携 | MCP server | Slack / Figma / DB |
| 出力スタイル恒久変更 | Output style (`.claude/output-styles/`) | 役割の変更 (例: 教師モード)、フォーマット恒久指定 |
| 配布・共有 | Plugin (`.claude-plugin/plugin.json`) | 自作 skill 群の他マシン展開 |
| 並列大規模化 | Workflows / Agent teams / Worktrees | codebase 監査、500 ファイル移行 |
| 定期実行 | `/loop` (session-scoped) / Routines (cloud schedule) | 日次自己改善、PR babysit |

## 観測パターン → 施策 (Tier A: 即時施策が明確)

| 観測パターン | 推奨施策 | 公式根拠 |
|---|---|---|
| Claude が同じ誤りを 2 回以上繰り返す (誤った命名・アンチパターン) | `CLAUDE.md` 追記 (1-3 行) | `features-overview.md` "convention wrong twice → CLAUDE.md" |
| 特定ファイル型・特定ディレクトリでだけ必要なルール | `.claude/rules/` に `paths` frontmatter | `memory.md` "path-scoped rules only load when matching files" |
| ルールに書いても繰り返し守られない (rule 効力不足) | rule の文言強化 → 改善なければ `PreToolUse` hook 昇格 | `memory.md` "instructions are context, not enforced" |
| 同じプロンプトを 3 回以上入力している | user-invocable Skill 化 | `features-overview.md` "save it as user-invocable skill" |
| 多段ステップの手順を貼り付けている | Skill (場合により Skill + Subagent) | `features-overview.md` "capture it as a skill" |
| 編集後に自動チェック (lint, type check, test) を入れたい | `PostToolUse` hook | `features-overview.md` "Run ESLint after every file edit" |
| 探索系の重いサイドタスクで context flood | Subagent 委譲 | `features-overview.md` "route through subagent" |
| 外部サービス連携 (Slack, Figma, DB) | MCP server (+ Skill で使い方ガイド) | `mcp.md` |
| 出力フォーマット・トーンへの繰り返し指摘 | Output style (`.claude/output-styles/`) | `output-styles.md` |
| permission prompt が頻発するツール | `permissions.allow` 追記 | `permissions.md` |
| 危険コマンド (`rm -rf`, force push 等) を絶対実行させない | `permissions.deny` + `PreToolUse` hook (二重防御) | `permissions.md`, `sandboxing.md` |
| 機密ファイル (.env, ~/.ssh) アクセス防止 | `sandbox.credentials.files` + `permissions.deny` | `sandboxing.md` |
| context 圧縮で重要情報が消える | `PreCompact` hook で snapshot | `hooks.md` |
| `/compact` 後に nested CLAUDE.md がリロードされない | プロジェクトルート CLAUDE.md に記述を寄せる | `memory.md` |

## 観測パターン → 施策 (Tier B: 慎重な検討が必要)

| 観測パターン | 第一候補 | 代替候補 | 検討事項 |
|---|---|---|---|
| `already_in_target_file` が 3 回観測される (既存ルールが守られていない) | 既存 rule の文言強化 (具体例追加、`anchor` の周辺に補強) | `PreToolUse` hook 昇格 | 「rule で表現できる事項か」「機械的に検出可能か」 |
| 採用後も同パターンが観測継続 | hook 昇格 | rule の例示拡充、Skill 化 | 「ルールが文脈として薄い」のか「Claude が従わない設計上の死角」か |
| 設計逸脱 (Clean Arch のレイヤ違反など) | 専用 reviewer subagent (実装後) + 補助 `PreToolUse` hook | rules への記載 | 違反したら止めるか警告のみか、自動検出が現実的か |
| 30 日サイクルでは間に合わない速度の課題 | `UserPromptSubmit` / `Stop` hook で即時抽出 | - | リアルタイム性が必要か |
| 大規模並列タスク (codebase 監査・移行) | Workflows (script-based orchestration) | Agent teams (議論型) | 数十〜数百並列 vs 数体協調 |
| 複数マシン・PC オフ時実行 | Routines (cloud schedule) | tmux 常駐 + cron | データの所在と機密性 (cloud に出していい情報か) |
| try & rollback を頻繁にやる | Checkpointing | git branch 運用 | 試行錯誤の頻度と context cost |
| 外部 (Slack / webhook 等) からセッションを起こしたい | Channels (push events) | Routines (GitHub trigger) | 即応性とトリガー元 |

## 拡張機構の組み合わせ (Tier C)

| 観測パターン | 組み合わせ |
|---|---|
| 特定 MCP server 操作で permission prompt が頻発 | MCP server 設定 + `permissions.allow: ["mcp__<server>__*"]` |
| 同じ手順を context isolation したい | Skill (orchestration) + Subagent (実行) |
| 複数 skill のセットを他マシン展開 | Plugin 化 + `.claude-plugin/plugin.json` + private marketplace |
| dev container 起動時の自動セットアップ | `SessionStart` hook + devcontainer 設定 |
| 大量並列の subagent が同じファイル編集競合 | Subagent + `isolation: worktree` |
| 機密情報を扱う subagent | model 別指定 (`haiku` で低コスト) + `tools` 制限 + 出力 sanitize |

## 強制レベル昇格の判断軸

観測クラスタが「**何回**」「**どのプロジェクトで**」観測されたかに加え、以下を見る:

| 軸 | 判定 | 影響 |
|---|---|---|
| **被害の不可逆性** | 失われる情報・コードがあるか | 高 → hook 必須 / 低 → rule で十分 |
| **検出可能性** | 違反を機械的に判別できるか (path / command / regex で) | 高 → hook で gate / 低 → rule + 例示 |
| **観測頻度** | 週次以上 → 上位施策, 月1 → rule で十分 | 頻度に応じて昇格 |
| **既存ルールの存在** | 同趣旨が rules/CLAUDE.md にあるか | あれば文言強化 (Tier B 第一候補) |
| **クラスタの抽象度** | 「○○で△△するな」と具体的か、姿勢か | 具体的 → hook 化容易 / 抽象 → rule で文脈供給 |

## skipped クラスタの取り扱い

`clusters_skipped` は通常スキップだが、`reason` 別に追加分析する:

| reason | 取り扱い |
|---|---|
| `below_threshold` (3 セッション未満) | 次回観測で積み上がる可能性。`scratchpad/self-improvement-skipped-*.jsonl` にログ |
| `already_in_target_file` (既存ルール該当) 3 回 | rule の **文言強化** を提案 (clusters_adopted に「rule 強化」として入れる) |
| `already_in_target_file` 5 回以上 | rule では効果不足と判断、**hook 昇格** を rule_audit に conflicts として記録 |
| `already_adopted` (memory で過去採用) 重複検出 | スキップで OK (D1 の本来の効果) |
| `too_large` (1 クラスタの diff > 200 行) | 「リファクタが必要」として人間にエスカレ。skill 内では対応せず |

## 提案の出力形式

判定の結果、`clusters_adopted` の各エントリには `treatment_strength` を併記する:

```json
{
  "name": "...",
  "observation_count": N,
  "target_file": "claude/CLAUDE.md",
  "treatment_strength": "advice",
  "proposed_addition": "..."
}
```

`treatment_strength` の値:
- `"advice"`: rules / CLAUDE.md への追記
- `"strong"`: rule + Skill or 補助 hook
- `"enforced"`: PreToolUse hook で block、permission rule で deny

`treatment_strength` を main session が読み、本来 `enforced` レベルなのに rule 追記で済ませている場合は、PR 本文で「次回観測時に hook 化を検討」とコメントを残す。

## 公式参照

- [features-overview.md](https://code.claude.com/docs/en/features-overview.md) — **最重要**: 使い分けマスター表 (CLAUDE.md / Skills / Subagents / Hooks / MCP / Plugins)
- [memory.md](https://code.claude.com/docs/en/memory.md) — CLAUDE.md vs rules、`paths` frontmatter、auto memory、`@import`
- [skills.md](https://code.claude.com/docs/en/skills.md) — Skill 定義、user-invocable、progressive disclosure
- [sub-agents.md](https://code.claude.com/docs/en/sub-agents.md) — Subagent frontmatter、tools 制限、model 指定、`memory: user|project|local`
- [hooks-guide.md](https://code.claude.com/docs/en/hooks-guide.md) — Hook 実装ガイド、matcher、exit code
- [hooks.md](https://code.claude.com/docs/en/hooks.md) — 全 hook イベント reference、JSON schema
- [permissions.md](https://code.claude.com/docs/en/permissions.md) — allow / deny / ask、tool-specific rule、managed settings
- [permission-modes.md](https://code.claude.com/docs/en/permission-modes.md) — default / acceptEdits / plan / auto / dontAsk / bypassPermissions
- [sandboxing.md](https://code.claude.com/docs/en/sandboxing.md) — sandbox config、credential 保護、network isolation
- [mcp.md](https://code.claude.com/docs/en/mcp.md) — MCP server 接続、scope、transport
- [output-styles.md](https://code.claude.com/docs/en/output-styles.md) — 役割/フォーマット恒久指定
- [plugins.md](https://code.claude.com/docs/en/plugins.md) — Plugin 構造、marketplace、配布
- [scheduled-tasks.md](https://code.claude.com/docs/en/scheduled-tasks.md) — `/loop` (session-scoped、7 日 expire)
- [routines.md](https://code.claude.com/docs/en/routines.md) — Cloud schedule、API / GitHub trigger
- [agent-teams.md](https://code.claude.com/docs/en/agent-teams.md) — 複数 session 協調
- [workflows.md](https://code.claude.com/docs/en/workflows.md) — script-based orchestration
- [worktrees.md](https://code.claude.com/docs/en/worktrees.md) — 並列 session の isolation
- [checkpointing.md](https://code.claude.com/docs/en/checkpointing.md) — undo / rewind / state 追跡
- [channels.md](https://code.claude.com/docs/en/channels.md) — push event 受信
- [best-practices.md](https://code.claude.com/docs/en/best-practices.md) — 「Build over time」「kitchen sink session を避ける」「verify する手段を持つ」
