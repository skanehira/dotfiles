import { assertEquals } from "jsr:@std/assert";
import { MAX_FIX_ROUNDS, validateFixRound } from "./fix-round-guard.ts";

// --- ラウンド上限の検証 ---

Deno.test("validateFixRound_with_first_fix_round_allows", () => {
  const result = validateFixRound({
    subagent_type: "dev-impl-implementer",
    model: "opus",
    prompt: [
      "mode: fix",
      "repo_dir: /tmp/repo",
      "issue_number: 20",
      "findings_path: /tmp/scratch/dev-impl-20260827-145613/review-20-r1.json",
      "report_path: /tmp/scratch/dev-impl-20260827-145613/impl-20-fix1.json",
    ].join("\n"),
  });

  assertEquals(result, { ok: true });
});

Deno.test("validateFixRound_with_second_fix_round_allows", () => {
  const result = validateFixRound({
    subagent_type: "dev-impl-implementer",
    model: "opus",
    prompt: "mode: fix\nfindings_path: /tmp/s/review-33-r2.json",
  });

  assertEquals(result, { ok: true });
});

Deno.test("validateFixRound_with_third_fix_round_denies_naming_issue_and_round", () => {
  const result = validateFixRound({
    subagent_type: "dev-impl-implementer",
    model: "opus",
    prompt: "mode: fix\nfindings_path: /tmp/s/review-33-r3.json",
  });

  assertEquals(result.ok, false);
  assertEquals(
    result.reason,
    "[fix-round-guard] issue #33 の修正ラウンドが 3 周目に入っています " +
      "(findings_path: review-33-r3.json)。dev-impl の規定は修正 2 ラウンドまでです。" +
      "high が残っているなら 2.6 の needs-human 駐車へ、medium だけなら " +
      "docs/PENDING_REVIEW.html に追記して 2.4 へ進んでください。" +
      "人間が明示的に継続を指示した場合のみ FIX_ROUND_GUARD=off で解除できます。",
  );
});

Deno.test("validateFixRound_with_fourth_fix_round_denies", () => {
  const result = validateFixRound({
    subagent_type: "dev-impl-implementer",
    model: "opus",
    prompt: "mode: fix\nfindings_path: /tmp/s/review-46-r4.json",
  });

  assertEquals(result.ok, false);
});

// 上限は literal で pin する。実装の MAX_FIX_ROUNDS を参照して期待値を組むと、
// 上限を書き換えても常に green になり、規定の 2 ラウンドが固定されない
Deno.test("MAX_FIX_ROUNDS pins the documented two-round limit", () => {
  assertEquals(MAX_FIX_ROUNDS, 2);
});

// --- 対象外の起動は通す (fail-open) ---

Deno.test("validateFixRound_with_implement_mode_allows", () => {
  const result = validateFixRound({
    subagent_type: "dev-impl-implementer",
    model: "opus",
    prompt: "mode: implement\nrepo_dir: /tmp/repo\nissue_number: 30",
  });

  assertEquals(result, { ok: true });
});

Deno.test("validateFixRound_with_other_agent_allows", () => {
  // review-impl 自身は何周目でも起動してよい (ゲートするのは修正の再実行だけ)
  const result = validateFixRound({
    subagent_type: "review-impl",
    model: "opus",
    prompt: "focus: all\nreport_path: /tmp/s/review-33-r5.json",
  });

  assertEquals(result, { ok: true });
});

Deno.test("validateFixRound_with_unparsable_findings_path_allows", () => {
  // ラウンドを読み取れないときは素通しする (検収差し戻しなど findings_path を持たない fix がある)
  const result = validateFixRound({
    subagent_type: "dev-impl-implementer",
    model: "opus",
    prompt: "mode: fix\nsummary: 検収に満たない報告の差し戻し",
  });

  assertEquals(result, { ok: true });
});

Deno.test("validateFixRound_with_no_subagent_type_allows", () => {
  const result = validateFixRound({ prompt: "mode: fix" });

  assertEquals(result, { ok: true });
});

// --- hook I/O 層 (main: stdin パース → PreToolUse deny JSON 出力・FIX_ROUND_GUARD=off 脱出口) ---

const HOOK = new URL("./fix-round-guard.ts", import.meta.url).pathname;

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

Deno.test("hook emits a PreToolUse deny decision on the third fix round", async () => {
  const stdout = await runHook({
    subagent_type: "dev-impl-implementer",
    model: "opus",
    prompt: "mode: fix\nfindings_path: /tmp/s/review-33-r3.json",
  });

  assertEquals(JSON.parse(stdout), {
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason:
        "[fix-round-guard] issue #33 の修正ラウンドが 3 周目に入っています " +
        "(findings_path: review-33-r3.json)。dev-impl の規定は修正 2 ラウンドまでです。" +
        "high が残っているなら 2.6 の needs-human 駐車へ、medium だけなら " +
        "docs/PENDING_REVIEW.html に追記して 2.4 へ進んでください。" +
        "人間が明示的に継続を指示した場合のみ FIX_ROUND_GUARD=off で解除できます。",
    },
  });
});

Deno.test("hook stays silent within the round limit", async () => {
  const stdout = await runHook({
    subagent_type: "dev-impl-implementer",
    model: "opus",
    prompt: "mode: fix\nfindings_path: /tmp/s/review-33-r2.json",
  });

  assertEquals(stdout, "");
});

Deno.test("hook stays silent when FIX_ROUND_GUARD is off", async () => {
  const stdout = await runHook(
    {
      subagent_type: "dev-impl-implementer",
      model: "opus",
      prompt: "mode: fix\nfindings_path: /tmp/s/review-33-r3.json",
    },
    { FIX_ROUND_GUARD: "off", PATH: Deno.env.get("PATH") ?? "" },
  );

  assertEquals(stdout, "");
});
