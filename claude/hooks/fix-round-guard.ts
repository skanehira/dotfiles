#!/usr/bin/env -S deno run --allow-env

/**
 * 修正ラウンド上限ゲート hook (PreToolUse Agent)。
 *
 * dev-impl の実装ループは「レビュー指摘の修正は最大 2 ラウンド (固定)」と
 * skills/dev-impl/SKILL.md 2.3 で規定しているが、オーケストレーター自身が
 * 「r3・規定超過」と書きながら 3 周目以降を起動した実績がある (セッション
 * e6b5eb50 の実測: 22 issue 中 6 件が r3 以上に入り、規定超過分だけで 5.7h)。
 * 指示文の規定は破られるので、起動そのものをコードで止める。
 *
 * ラウンド数は状態を持たずに判定する。`mode: fix` の起動は必ず
 * `findings_path: <SCRATCH>/review-<issue>-r<ラウンド>.json` を渡す契約なので
 * (同セッションの実測で 29/29 が該当)、パスからラウンドを読めば足りる。
 * 状態を持たないため、スキルの再実行 (新しい SCRATCH で r1 から採番) が
 * そのままカウンタのリセットになり、subagent エラー時の「同条件で 1 回だけ
 * 再起動」でも二重カウントしない。
 *
 * 適用範囲: 全リポジトリ。対象 agent は個人定義 (~/.claude/agents) なので
 * 他人のリポジトリで誤検知しない。
 * 緊急脱出: 環境変数 FIX_ROUND_GUARD=off で素通り。
 */

/** SKILL.md 2.3「このループは最大 2 ラウンド (固定)」。 */
export const MAX_FIX_ROUNDS = 2;

const TARGET_AGENT = "dev-impl-implementer";

/** `findings_path: .../review-<issue>-r<round>.json` から issue とラウンドを取る。 */
const FINDINGS_PATH = /findings_path:\s*\S*?review-(\d+)-r(\d+)\.json/;

export type AgentSpawnInput = {
  subagent_type?: string;
  model?: string;
  prompt?: string;
};

export type FixRoundValidation = {
  ok: boolean;
  reason?: string;
};

export function validateFixRound(input: AgentSpawnInput): FixRoundValidation {
  if (input.subagent_type !== TARGET_AGENT) return { ok: true };

  const prompt = input.prompt ?? "";
  if (!/\bmode:\s*fix\b/.test(prompt)) return { ok: true };

  // ラウンドを読めない fix (検収差し戻しなど findings_path を持たない起動) は素通しする。
  // 読めないことを違反とみなすと、規定に無い経路まで巻き添えで止まる
  const matched = FINDINGS_PATH.exec(prompt);
  if (!matched) return { ok: true };

  const issue = matched[1];
  const round = Number(matched[2]);
  if (round <= MAX_FIX_ROUNDS) return { ok: true };

  return {
    ok: false,
    reason: `[fix-round-guard] issue #${issue} の修正ラウンドが ${round} 周目に入っています ` +
      `(findings_path: review-${issue}-r${round}.json)。` +
      `dev-impl の規定は修正 ${MAX_FIX_ROUNDS} ラウンドまでです。` +
      `high が残っているなら 2.6 の needs-human 駐車へ、medium だけなら ` +
      `docs/PENDING_REVIEW.html に追記して 2.4 へ進んでください。` +
      `人間が明示的に継続を指示した場合のみ FIX_ROUND_GUARD=off で解除できます。`,
  };
}

// ---- 以下 hook I/O 層 (settings.json から PreToolUse Agent で起動される) ----

type HookInput = {
  tool_input?: AgentSpawnInput;
};

async function main() {
  if (Deno.env.get("FIX_ROUND_GUARD") === "off") return;

  let input: HookInput = {};
  try {
    input = await new Response(Deno.stdin.readable).json();
  } catch {
    return;
  }

  try {
    const result = validateFixRound(input.tool_input ?? {});
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
