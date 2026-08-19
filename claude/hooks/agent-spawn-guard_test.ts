import { assertEquals } from "jsr:@std/assert";
import { MANDATED_MODEL, validateAgentSpawn } from "./agent-spawn-guard.ts";

// --- model 明示の検証 ---

Deno.test("validateAgentSpawn_with_managed_agent_and_explicit_model_allows", () => {
  const result = validateAgentSpawn({
    subagent_type: "architecture-guard",
    model: "haiku",
    prompt: "target_diff: phase:3",
  });

  assertEquals(result, { ok: true });
});

Deno.test("validateAgentSpawn_with_deliberate_model_override_allows", () => {
  // 規定と違う model でも、明示されていれば意図的な override として通す
  const result = validateAgentSpawn({
    subagent_type: "review-adversarial",
    model: "opus",
    prompt: "phase_name: 3",
  });

  assertEquals(result, { ok: true });
});

Deno.test("validateAgentSpawn_with_unmanaged_agent_missing_model_allows", () => {
  const result = validateAgentSpawn({
    subagent_type: "general-purpose",
    prompt: "調査してください",
  });

  assertEquals(result, { ok: true });
});

// 期待値は MANDATED_MODEL から読まず literal で持つ。表を反復して同じ表の値を期待すると、
// 割当を書き換えても常に green になり、どの agent のモデルも pin されない
const EXPECTED_MANDATED_MODELS: [string, string][] = [
  ["dev-impl-implementer", "opus"],
  ["architecture-guard", "haiku"],
  ["fix-lsp-warnings", "haiku"],
  ["review-adversarial", "sonnet"],
  ["review-tdd", "opus"],
  ["review-quality", "opus"],
  ["review-product-readiness", "opus"],
  ["review-spec-compliance", "opus"],
];

Deno.test("MANDATED_MODEL covers exactly the agents that have a pinned model expectation", () => {
  assertEquals(
    Object.keys(MANDATED_MODEL).sort(),
    EXPECTED_MANDATED_MODELS.map(([type]) => type).sort(),
  );
});

Deno.test("validateAgentSpawn denies every mandated agent spawned without model, naming that agent's model", () => {
  for (const [type, model] of EXPECTED_MANDATED_MODELS) {
    const result = validateAgentSpawn({
      subagent_type: type,
      prompt: VALID_POST_IMPL_PROMPT,
    });

    assertEquals(result.ok, false, type);
    assertEquals(
      result.reason,
      `[agent-spawn-guard] ${type} の起動に model が指定されていません。` +
        "未指定だと agent 定義ではなく親のセッションモデルを継承します。" +
        `model: "${model}" を明示してください。`,
      type,
    );
  }
});

// --- review-spec-compliance の必須フィールド検証 ---

const VALID_POST_IMPL_PROMPT = `mode: post-impl
product_mode: cli
docs_dir: docs/
approved_stamp: "<!-- dev-spec:approved goals_sha=abc -->"
run_start_sha: deadbeef
decisions_jsonl: ~/.claude/logs/dev-impl/20260801-120000/decisions.jsonl
output_path: /tmp/review-spec-compliance-20260801-120000.json
holdout_enabled: false
docs は自分で全文 Read すること。
作業結果 (output_path のパス) は必ず最終メッセージで親に返すこと。`;

Deno.test("validateAgentSpawn_with_complete_post_impl_prompt_allows", () => {
  const result = validateAgentSpawn({
    subagent_type: "review-spec-compliance",
    model: "opus",
    prompt: VALID_POST_IMPL_PROMPT,
  });

  assertEquals(result, { ok: true });
});

Deno.test("validateAgentSpawn_with_post_impl_prompt_missing_fields_denies_and_lists_them", () => {
  // 実測 (dev-impl 7 セッション / spawn 15 件) で常に落ちていた 5 項目を欠いた prompt
  const observed = `mode: post-impl
docs_dir: docs/
output_path: /tmp/review-spec-compliance.json
docs は自分で全文 Read すること。`;

  const result = validateAgentSpawn({
    subagent_type: "review-spec-compliance",
    model: "opus",
    prompt: observed,
  });

  assertEquals(result.ok, false);
  assertEquals(
    result.reason,
    "[agent-spawn-guard] review-spec-compliance (mode: post-impl) の prompt に必須項目が不足しています: " +
      "product_mode:, approved_stamp:, run_start_sha:, decisions_jsonl:, holdout_enabled:。" +
      " skills/dev-impl/references/goal-audit.md の `## 5.2: 監査 agent の並列起動` " +
      "にある完全なテンプレートを Read して、そのまま使ってください。",
  );
});

Deno.test("validateAgentSpawn_with_pre_approval_prompt_does_not_require_post_impl_fields", () => {
  // dev-spec フェーズ 10.5 の起動。post-impl 固有項目は不要
  const result = validateAgentSpawn({
    subagent_type: "review-spec-compliance",
    model: "opus",
    prompt: `mode: pre-approval
docs_dir: docs/
output_path: /tmp/review-spec-compliance-pre-approval.json
docs (DESIGN.md / DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md / TODO.md) は自分で全文 Read すること。`,
  });

  assertEquals(result, { ok: true });
});

Deno.test("validateAgentSpawn_with_pre_approval_prompt_missing_output_path_denies", () => {
  const result = validateAgentSpawn({
    subagent_type: "review-spec-compliance",
    model: "opus",
    prompt: `mode: pre-approval
docs_dir: docs/
docs は自分で全文 Read すること。`,
  });

  assertEquals(result.ok, false);
  assertEquals(
    result.reason,
    "[agent-spawn-guard] review-spec-compliance (mode: pre-approval) の prompt に必須項目が不足しています: " +
      "output_path:。" +
      " skills/dev-impl/references/goal-audit.md の `## 5.2: 監査 agent の並列起動` " +
      "にある完全なテンプレートを Read して、そのまま使ってください。",
  );
});

Deno.test("validateAgentSpawn_with_spec_compliance_prompt_lacking_mode_denies", () => {
  const result = validateAgentSpawn({
    subagent_type: "review-spec-compliance",
    model: "opus",
    prompt: `docs_dir: docs/
output_path: /tmp/out.json
docs は自分で全文 Read すること。`,
  });

  assertEquals(result.ok, false);
  assertEquals(
    result.reason,
    "[agent-spawn-guard] review-spec-compliance の prompt に `mode: post-impl` / " +
      "`mode: pre-approval` のいずれもありません。" +
      "監査の種別が決まらないため起動できません。",
  );
});

Deno.test("validateAgentSpawn_with_post_impl_prompt_missing_full_read_instruction_denies", () => {
  // 「docs は自分で全文 Read すること」が落ちると被監査者の編纂物を信用してしまう
  const withoutFullRead = VALID_POST_IMPL_PROMPT.replace(
    "docs は自分で全文 Read すること。\n",
    "",
  );

  const result = validateAgentSpawn({
    subagent_type: "review-spec-compliance",
    model: "opus",
    prompt: withoutFullRead,
  });

  assertEquals(result.ok, false);
  assertEquals(
    result.reason,
    "[agent-spawn-guard] review-spec-compliance (mode: post-impl) の prompt に必須項目が不足しています: " +
      "全文 Read。" +
      " skills/dev-impl/references/goal-audit.md の `## 5.2: 監査 agent の並列起動` " +
      "にある完全なテンプレートを Read して、そのまま使ってください。",
  );
});

Deno.test("validateAgentSpawn_with_missing_subagent_type_allows", () => {
  const result = validateAgentSpawn({ prompt: "何か" });

  assertEquals(result, { ok: true });
});

Deno.test("validateAgentSpawn denies field keys that carry no value", () => {
  const keysOnly = `mode: post-impl
product_mode:
docs_dir: docs/
approved_stamp:
run_start_sha:
decisions_jsonl:
output_path: /tmp/o.json
holdout_enabled:
docs は自分で全文 Read すること。`;

  const result = validateAgentSpawn({
    subagent_type: "review-spec-compliance",
    model: "opus",
    prompt: keysOnly,
  });

  assertEquals(result.ok, false);
  assertEquals(
    result.reason,
    "[agent-spawn-guard] review-spec-compliance (mode: post-impl) の prompt に必須項目が不足しています: " +
      "product_mode:, approved_stamp:, run_start_sha:, decisions_jsonl:, holdout_enabled:。" +
      " skills/dev-impl/references/goal-audit.md の `## 5.2: 監査 agent の並列起動` " +
      "にある完全なテンプレートを Read して、そのまま使ってください。",
  );
});

// --- hook I/O 層 (settings.json から起動される実体) ---

const HOOK = new URL("./agent-spawn-guard.ts", import.meta.url).pathname;

async function runHook(
  toolInput: Record<string, unknown>,
  env: Record<string, string> = {},
): Promise<string> {
  const cmd = new Deno.Command("deno", {
    args: ["run", "--allow-env", HOOK],
    stdin: "piped",
    stdout: "piped",
    stderr: "null",
    env,
  });
  const child = cmd.spawn();
  const writer = child.stdin.getWriter();
  await writer.write(
    new TextEncoder().encode(JSON.stringify({ tool_input: toolInput })),
  );
  await writer.close();
  const { stdout } = await child.output();
  return new TextDecoder().decode(stdout).trim();
}

Deno.test("hook emits a PreToolUse deny decision when the spawn violates the policy", async () => {
  const stdout = await runHook({
    subagent_type: "architecture-guard",
    prompt: "target_diff: phase:3",
  });

  assertEquals(JSON.parse(stdout), {
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason:
        "[agent-spawn-guard] architecture-guard の起動に model が指定されていません。" +
        "未指定だと agent 定義ではなく親のセッションモデルを継承します。" +
        'model: "haiku" を明示してください。',
    },
  });
});

Deno.test("hook stays silent when the spawn complies", async () => {
  const stdout = await runHook({
    subagent_type: "architecture-guard",
    model: "haiku",
    prompt: "target_diff: phase:3",
  });

  assertEquals(stdout, "");
});

Deno.test("hook stays silent when AGENT_SPAWN_GUARD is off", async () => {
  const stdout = await runHook(
    { subagent_type: "architecture-guard", prompt: "target_diff: phase:3" },
    { AGENT_SPAWN_GUARD: "off", PATH: Deno.env.get("PATH") ?? "" },
  );

  assertEquals(stdout, "");
});
