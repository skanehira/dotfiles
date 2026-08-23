import { assertEquals } from "jsr:@std/assert";
import { MANDATED_MODEL, validateAgentSpawn } from "./agent-spawn-guard.ts";

// --- model 明示の検証 ---

Deno.test("validateAgentSpawn_with_managed_agent_and_explicit_model_allows", () => {
  const result = validateAgentSpawn({
    subagent_type: "review-impl",
    model: "opus",
    prompt: "repo_dir: /tmp/repo",
  });

  assertEquals(result, { ok: true });
});

Deno.test("validateAgentSpawn_with_deliberate_model_override_allows", () => {
  // 規定と違う model でも、明示されていれば意図的な override として通す
  const result = validateAgentSpawn({
    subagent_type: "dev-impl-implementer",
    model: "fable",
    prompt: "mode: implement",
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
  ["review-impl", "opus"],
  ["fix-lsp-warnings", "haiku"],
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
      prompt: "mode: implement",
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

Deno.test("validateAgentSpawn_with_no_subagent_type_allows", () => {
  const result = validateAgentSpawn({ prompt: "何かの作業" });

  assertEquals(result, { ok: true });
});
