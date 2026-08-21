#!/usr/bin/env -S deno run --allow-env

/**
 * subagent 起動ゲート hook (PreToolUse Agent)。
 *
 * 2 つの欠陥を機械検証する。どちらも dev-impl 実行 7 セッションのログ実測で
 * 「指示文としては書かれているのに守られていない」ことが確認されたもの:
 *
 * 1. model 未指定での起動 — Agent ツールの model は未指定だと agent 定義の
 *    frontmatter ではなく親のセッションモデルを継承する。実測では
 *    architecture-guard の 22 spawn が haiku ではなく opus 単価で走っていた
 *    ($2.40/spawn vs haiku 指定時 $0.16/spawn)。
 *
 * 2. review-spec-compliance の必須フィールド欠落 — goal-audit.md の
 *    テンプレートを読まず記憶で prompt を再構成した結果、実測 15 spawn すべてで
 *    product_mode / approved_stamp / run_start_sha / decisions_jsonl /
 *    holdout_enabled が欠落していた (完全な spawn は 0/15、コンテキスト規模とは
 *    無相関 r=-0.01)。これらが欠けると第三者監査の独立性が落ちる。
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
 * 例: dev-impl-implementer は implement と fix ラウンド 1 が opus、
 *     fix ラウンド 2 以降は fable (SKILL.md「修正ラウンドのモデル昇格」)。
 */
export const MANDATED_MODEL: Record<string, string> = {
  "dev-impl-implementer": "opus",
  "architecture-guard": "haiku",
  "fix-lsp-warnings": "haiku",
  "review-adversarial": "sonnet",
  "review-tdd": "opus",
  "review-quality": "opus",
  "review-product-readiness": "opus",
  "review-spec-compliance": "opus",
};

/** review-spec-compliance の mode 別の必須フィールド (goal-audit.md のテンプレート由来)。 */
const REQUIRED_FIELDS: Record<string, string[]> = {
  "post-impl": [
    "product_mode:",
    "docs_dir:",
    "approved_stamp:",
    "run_start_sha:",
    "decisions_jsonl:",
    "output_path:",
    "holdout_enabled:",
    "全文 Read",
  ],
  "pre-approval": [
    "docs_dir:",
    "output_path:",
    "全文 Read",
  ],
};

/** テンプレートの所在をモードごとに示す。 */
const TEMPLATE_HINT: Record<string, string> = {
  "post-impl": " skills/dev-impl/references/goal-audit.md の `## 5.2: 監査 agent の並列起動` " +
    "にある完全なテンプレートを Read して、そのまま使ってください。",
  "pre-approval": " skills/dev-impl/references/goal-audit.md の `## 5.2: 監査 agent の並列起動` " +
    "にある完全なテンプレートを Read して、そのまま使ってください。",
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

/**
 * `key:` 形式のフィールドは値が空でないことまで確認する (キーだけ並べても満たさない)。
 *
 * 行頭アンカーが「deny 文を prompt に貼り戻すだけで通る」迂回路も同時に塞いでいる。
 * deny 文は `[agent-spawn-guard]` で始まる 1 行なので、その中に `approved_stamp:` が
 * 列挙されていても行頭には来ず、フィールドが満たされたとは判定されない。
 */
function hasField(prompt: string, field: string): boolean {
  if (!field.endsWith(":")) return prompt.includes(field);
  const key = field.slice(0, -1).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  // 値の検出は同一行に限定する。`\s` は改行を含むため、キーだけの行が
  // 次行の先頭文字を値とみなして通ってしまう
  return new RegExp(`^[ \\t]*${key}:[ \\t]*\\S`, "m").test(prompt);
}

function validateSpecCompliancePrompt(rawPrompt: string): SpawnValidation {
  const prompt = rawPrompt;
  const mode = Object.keys(REQUIRED_FIELDS).find((m) => prompt.includes(`mode: ${m}`)) ?? null;

  if (mode === null) {
    return {
      ok: false,
      reason:
        "[agent-spawn-guard] review-spec-compliance の prompt に `mode: post-impl` / " +
        "`mode: pre-approval` のいずれもありません。" +
        "監査の種別が決まらないため起動できません。",
    };
  }

  const missing = REQUIRED_FIELDS[mode].filter((f) => !hasField(prompt, f));
  if (missing.length === 0) return { ok: true };

  return {
    ok: false,
    reason:
      `[agent-spawn-guard] review-spec-compliance (mode: ${mode}) の prompt に必須項目が不足しています: ` +
      `${missing.join(", ")}。${TEMPLATE_HINT[mode]}`,
  };
}

export function validateAgentSpawn(input: AgentSpawnInput): SpawnValidation {
  const type = input.subagent_type;
  if (!type) return { ok: true };

  const mandated = MANDATED_MODEL[type];
  if (!mandated) return { ok: true };

  // model は「未指定」だけを弾く。規定と違う値でも明示されていれば意図的な override として通す
  if (!input.model) {
    return {
      ok: false,
      reason:
        `[agent-spawn-guard] ${type} の起動に model が指定されていません。` +
        `未指定だと agent 定義ではなく親のセッションモデルを継承します。` +
        `model: "${mandated}" を明示してください。` +
        (type === "dev-impl-implementer"
          ? ` (mode: implement と mode: fix のラウンド 1 は "opus"、` +
            `mode: fix のラウンド 2 以降は "fable"。SKILL.md「修正ラウンドのモデル昇格」)`
          : ""),
    };
  }

  if (type === "review-spec-compliance") {
    return validateSpecCompliancePrompt(input.prompt ?? "");
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
