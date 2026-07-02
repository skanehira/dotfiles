// workflow-autopilot の 1 フェーズ実装パイプライン。
// SKILL.md (メインセッション) から Workflow({scriptPath, args}) で起動される。
// ループ制御・カウンタ・findings 集約・fatal 判定はすべてこのスクリプト (決定的 JS) が持ち、
// LLM は「実装 / 検査 / 修正 / コミット」の中身だけを担当する。
//
// args (メインセッションの skill が組み立てる):
// {
//   contextPath:      "docs/.autopilot/<run_id>/phase-<n>-context.md" (PHASE_CONTEXT ファイル)
//   phaseName:        "フェーズN: ...",
//   phaseStartSha:    "<git SHA>",
//   designPath:       "docs/DESIGN.md",
//   designDetailPath: "docs/DESIGN_DETAIL.md",
//   isFinalPhase:     boolean,   // 最終フェーズは 5 観点フルレビュー
//   uiPhase:          boolean,   // このフェーズが UI (フロントエンド) ファイルを触る見込みか
//   isNeovimPlugin:   boolean,   // Lua/Neovim プラグインなら LSP 警告修正 stage を挟む
//   devServer:        { url, start_command } | null,  // review-product-readiness 用
// }
//
// 返り値:
// { status: "done"|"escalate", reason?, deviationSignals: [...], findings: [...],
//   modifiedFiles: [...], commit: {...}|null }

export const meta = {
  name: 'autopilot-phase',
  description: 'workflow-autopilot の 1 フェーズ実装 (dev → guard → review → fix → commit)',
  phases: [
    { title: 'Dev', detail: 'implementation-developing-agent で TDD 実装' },
    { title: 'Guard', detail: 'architecture-guard 検査 + 修正ループ (最大3回)' },
    { title: 'Review', detail: '観点 gating 付きレビュー + self-fix (最大3回)' },
    { title: 'Commit', detail: 'Conventional Commit 形式でコミット' },
  ],
}

const DEVIATION_SIGNAL = {
  type: 'object',
  required: ['type', 'what'],
  properties: {
    type: { enum: ['todo_minor', 'design_detail_gap', 'design_overview_break'] },
    what: { type: 'string' },
    why: { type: 'string' },
    scope: { type: 'string' },
    fix_proposal: { type: 'string' },
  },
}

const DEV_SCHEMA = {
  type: 'object',
  required: ['status', 'modified_files', 'deviation_signals'],
  properties: {
    status: { enum: ['done', 'escalate'] },
    escalate_reason: { type: 'string' },
    modified_files: { type: 'array', items: { type: 'string' } },
    tdd_compliance: {
      type: 'object',
      properties: {
        red_first: { type: 'boolean' },
        tests_green: { type: 'boolean' },
        notes: { type: 'string' },
      },
    },
    deviation_signals: { type: 'array', items: DEVIATION_SIGNAL },
  },
}

const FINDING = {
  type: 'object',
  required: ['file', 'severity', 'message'],
  properties: {
    file: { type: 'string' },
    line: { type: 'integer' },
    severity: { enum: ['high', 'medium', 'low'] },
    rule: { type: 'string' },
    message: { type: 'string' },
    fix_proposal: { type: 'string' },
  },
}

const GUARD_SCHEMA = {
  type: 'object',
  required: ['ok', 'violations'],
  properties: {
    ok: { type: 'boolean' },
    skip_reason: { type: ['string', 'null'] },
    violations: { type: 'array', items: FINDING },
  },
}

const REVIEW_SCHEMA = {
  type: 'object',
  required: ['dimension', 'findings'],
  properties: {
    dimension: { type: 'string' },
    findings: { type: 'array', items: FINDING },
  },
}

const COMMIT_SCHEMA = {
  type: 'object',
  required: ['committed'],
  properties: {
    committed: { type: 'boolean' },
    commits: {
      type: 'array',
      items: {
        type: 'object',
        properties: { sha: { type: 'string' }, subject: { type: 'string' } },
      },
    },
    error: { type: 'string' },
  },
}

const readContextInstruction =
  `まず PHASE_CONTEXT ファイル ${args.contextPath} を Read せよ。フェーズのタスク一覧・設計抜粋・関連ファイル・rules パスが全て書いてある。`

function escalate(reason, deviationSignals, findings) {
  return {
    status: 'escalate',
    reason,
    deviationSignals: deviationSignals ?? [],
    findings: findings ?? [],
    modifiedFiles: [],
    commit: null,
  }
}

// ---- Dev ----
phase('Dev')
log(`${args.phaseName}: TDD 実装を開始`)

const dev = await agent(
  `${readContextInstruction}
その後、PHASE_CONTEXT に従いフェーズ「${args.phaseName}」を TDD (RED→GREEN→REFACTOR) で実装せよ。
コミットはするな (後続 stage が行う)。実装中に設計乖離に気付いたら deviation_signals として報告せよ。`,
  { agentType: 'implementation-developing-agent', schema: DEV_SCHEMA, label: 'dev' },
)
if (!dev) return escalate('dev_agent_failed')

const deviationSignals = [...dev.deviation_signals]
if (dev.status === 'escalate') return escalate(dev.escalate_reason || 'dev_escalate', deviationSignals)
if (deviationSignals.some((s) => s.type === 'design_overview_break')) {
  return escalate('design_overview_break', deviationSignals)
}

// ---- Guard (最大 3 修正ループ) ----
phase('Guard')
let guardPassed = false
for (let i = 1; i <= 4; i++) {
  const g = await agent(
    `architecture-guard として、フェーズ「${args.phaseName}」の差分 (git diff ${args.phaseStartSha}..HEAD) を検査せよ。
design_path: ${args.designPath}
design_detail_path: ${args.designDetailPath}
ファイルへの出力は不要。結果は StructuredOutput で直接返せ。
git diff コマンド自体が失敗した場合は ok:false, skip_reason:"diff_command_failed" とせよ。`,
    { agentType: 'architecture-guard', schema: GUARD_SCHEMA, label: `guard#${i}`, phase: 'Guard' },
  )
  if (!g) return escalate('guard_agent_failed', deviationSignals)

  const mustFix = g.skip_reason === 'diff_command_failed' ||
    g.violations.some((v) => v.severity === 'high' || v.severity === 'medium')
  if (!mustFix) {
    guardPassed = true
    if (g.violations.length > 0) log(`guard: low violations ${g.violations.length} 件は警告のみで通過`)
    break
  }
  if (i === 4) break // guard_loop > 3 相当

  log(`guard 違反 ${g.violations.length} 件 → 修正ループ ${i}/3`)
  const fix = await agent(
    `${readContextInstruction}
architecture-guard が以下の違反を検出した。既存テストを緑に保ったまま、TDD で境界遵守に修正せよ (必要なら新規テスト追加)。コミットはするな。
違反一覧:
${JSON.stringify(g.violations, null, 2)}`,
    { agentType: 'implementation-developing-agent', schema: DEV_SCHEMA, label: `guard-fix#${i}`, phase: 'Guard' },
  )
  if (fix) deviationSignals.push(...fix.deviation_signals)
}
if (!guardPassed) return escalate('guard_loop_exceeded', deviationSignals)

// ---- LSP 警告修正 (Lua/Neovim プラグインのみ) ----
if (args.isNeovimPlugin) {
  const lsp = await agent(
    `Lua/Neovim プロジェクトの LSP 警告 (型エラー / 未定義変数 / 重複定義) を検出して修正せよ。対象はフェーズ差分 (git diff ${args.phaseStartSha}..HEAD) のファイルのみ。`,
    { agentType: 'fix-lsp-warnings', label: 'fix-lsp', phase: 'Guard' },
  )
  if (lsp === null) log('fix-lsp-warnings が失敗 (継続)')
}

// ---- Review (観点 gating + 最大 3 self-fix ループ) ----
phase('Review')

// gating: 毎フェーズ tdd。UI を触ったら product-readiness。最終フェーズは 5 観点フル。
// (architecture の機械検査は Guard stage 済み。heuristic 版 review-architecture は最終のみ)
const ALL_DIMS = ['tdd', 'quality', 'architecture', 'rules', 'product-readiness']
let dims = args.isFinalPhase ? [...ALL_DIMS] : ['tdd']
if (!args.isFinalPhase && args.uiPhase) dims.push('product-readiness')
if (!args.devServer) dims = dims.filter((d) => d !== 'product-readiness')
log(`review 観点: ${dims.join(', ')} (gating: final=${args.isFinalPhase}, ui=${args.uiPhase})`)

function reviewPrompt(d) {
  const base = `review-${d} として、フェーズ「${args.phaseName}」の差分 (git diff ${args.phaseStartSha}..HEAD) をレビューせよ。
phase_start_sha: ${args.phaseStartSha}
PHASE_CONTEXT: ${args.contextPath} を Read して設計抜粋と rules パスを参照せよ。
ファイルへの出力は不要。結果は StructuredOutput で直接返せ (dimension: "${d}")。`
  if (d === 'product-readiness' && args.devServer) {
    return `${base}
dev_server: ${JSON.stringify(args.devServer)}`
  }
  return base
}

const phaseFindings = {}
let fatal = []
for (let loop = 1; loop <= 4; loop++) {
  const results = await parallel(
    dims.map((d) => () =>
      agent(reviewPrompt(d), {
        agentType: `review-${d}`,
        schema: REVIEW_SCHEMA,
        label: `review:${d}#${loop}`,
        phase: 'Review',
      })
    ),
  )
  // 今回レビューした観点だけ洗い替え (fix 済みで 0 件のケースを正しく反映)
  results.filter(Boolean).forEach((r) => {
    phaseFindings[r.dimension] = r.findings
  })

  fatal = Object.values(phaseFindings).flat().filter((f) => f.severity === 'high')
  if (fatal.length === 0) break
  if (loop === 4) {
    return escalate('review_loop_exceeded', deviationSignals, Object.values(phaseFindings).flat())
  }

  log(`fatal findings ${fatal.length} 件 → self-fix ループ ${loop}/3`)
  const fix = await agent(
    `${readContextInstruction}
レビューで以下の致命 (severity: high) 指摘が出た。TDD で修正せよ。コミットはするな。
指摘一覧:
${JSON.stringify(fatal, null, 2)}`,
    { agentType: 'implementation-developing-agent', schema: DEV_SCHEMA, label: `review-fix#${loop}`, phase: 'Review' },
  )
  if (fix) deviationSignals.push(...fix.deviation_signals)

  dims = [...new Set(fatal.map((f) => f.dimension))] // fatal だった観点のみ再実行
}

// ---- Commit ----
phase('Commit')
const commit = await agent(
  `フェーズ「${args.phaseName}」の実装差分をコミットせよ。手順:
1. git status と git diff ${args.phaseStartSha}..HEAD で変更を確認
2. 関心事ごとに分割 (構造的変更 [STRUCTURAL] と動作的変更 [BEHAVIORAL] は別コミット、両方あるなら STRUCTURAL 先)
3. 各コミットは Conventional Commit 形式: "<emoji> <type>: <subject>" (feat=✨ fix=🐛 docs=📝 refactor=♻️ test=✅ chore=🔧)
4. コミットメッセージは HEREDOC で、末尾に以下を含める:
   🤖 Generated with [Claude Code](https://claude.com/claude-code)

   Co-Authored-By: Claude <noreply@anthropic.com>
5. git push は絶対にするな
テストが失敗する状態ならコミットせず committed: false と error を返せ。`,
  { schema: COMMIT_SCHEMA, label: 'commit', effort: 'low' },
)

return {
  status: 'done',
  deviationSignals,
  findings: Object.entries(phaseFindings).flatMap(([dimension, fs]) =>
    fs.map((f) => ({ dimension, ...f }))
  ),
  modifiedFiles: dev.modified_files,
  commit: commit ?? null,
}
