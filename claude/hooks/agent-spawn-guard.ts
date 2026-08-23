#!/usr/bin/env -S deno run --allow-env

/**
 * subagent 起動ゲート hook (PreToolUse Agent)。
 *
 * model 未指定での起動を機械検証する。Agent ツールの model は未指定だと
 * agent 定義の frontmatter ではなく親のセッションモデルを継承するため、
 * 「指示文には model を書いたのに、起動時に指定し忘れて意図しない単価で走る」
 * 事故が起きる (旧構成の dev-impl 実行 7 セッションのログ実測で、指示文としては
 * 書かれているのに守られていないことを確認済み)。
 *
 * 適用範囲: 全リポジトリ。対象 agent は個人定義 (~/.claude/agents) なので
 * 他人のリポジトリで誤検知しない。
 * 緊急脱出: 環境変数 AGENT_SPAWN_GUARD=off で素通り。
 */

/**
 * model の明示が必要な agent と、未指定時の deny メッセージで案内する既定値
 * (skills/dev-impl/SKILL.md「モデル方針」)。
 *
 * この hook が弾くのは **model の未指定だけ**で、規定と違う値でも明示されていれば
 * 意図的な override として通す。したがってここの値は「固定値」ではなく
 * 「未指定を叱るときに提示する既定値」である。
 */
export const MANDATED_MODEL: Record<string, string> = {
  "dev-impl-implementer": "opus",
  "review-impl": "opus",
  "fix-lsp-warnings": "haiku",
};

export type AgentSpawnInput = {
  subagent_type?: string;
  model?: string;
  prompt?: string;
};

export type SpawnValidation = {
  ok: boolean;
  reason?: string;
};

export function validateAgentSpawn(input: AgentSpawnInput): SpawnValidation {
  const type = input.subagent_type;
  if (!type) return { ok: true };

  const mandated = MANDATED_MODEL[type];
  if (!mandated) return { ok: true };

  // model は「未指定」だけを弾く。規定と違う値でも明示されていれば意図的な override として通す
  if (!input.model) {
    return {
      ok: false,
      reason: `[agent-spawn-guard] ${type} の起動に model が指定されていません。` +
        `未指定だと agent 定義ではなく親のセッションモデルを継承します。` +
        `model: "${mandated}" を明示してください。`,
    };
  }

  return { ok: true };
}

// ---- 以下 hook I/O 層 (settings.json から PreToolUse Agent で起動される) ----

type HookInput = {
  tool_input?: AgentSpawnInput;
};

async function main() {
  if (Deno.env.get("AGENT_SPAWN_GUARD") === "off") return;

  let input: HookInput = {};
  try {
    input = await new Response(Deno.stdin.readable).json();
  } catch {
    return;
  }

  try {
    const result = validateAgentSpawn(input.tool_input ?? {});
    if (!result.ok) {
      console.log(JSON.stringify({
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason: result.reason,
        },
      }));
    }
  } catch {
    // hook の失敗でセッションを壊さない
  }
}

if (import.meta.main) {
  await main();
}
