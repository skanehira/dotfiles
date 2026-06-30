#!/usr/bin/env -S deno run --allow-env --allow-read
export {};

/**
 * SubagentStop hook。subagent の TDD 遵守を機械チェックする。
 *
 * 背景: parent settings.json の Stop / PostToolUse / UserPromptSubmit hook は
 * subagent には継承されない。よって `self-review.ts` は subagent 内の
 * Edit/Write には効かない。本 hook は subagent 終了時に parent 側で発火し、
 * subagent transcript を読んで TDD 痕跡をチェックする。
 *
 * 判定: 編集系 tool (Edit/Write/NotebookEdit) で
 *   1. implementation ファイルだけ編集して test ファイルが無い → 違反
 *   2. test ファイルの編集が implementation より後 → 違反 (RED-GREEN 順序破壊)
 *   3. 全部 test or 全部 implementation でも test 先行 → OK
 *
 * 違反検出時は decision: "block" + reason で subagent に再ターンの機会を与える。
 * subagent が `[subagent-review-done]` マーカーを応答に含めれば次回 block しない
 * (誤検知の救済、TDD を意図的にスキップする宣言的編集ターンを通すため)。
 *
 * stop_hook_active=true (この hook が起こした再ターン) なら無条件で素通り
 * (無限ループ防止)。
 */

type SubagentStopInput = {
  hook_event_name?: string;
  session_id?: string;
  transcript_path?: string;
  stop_hook_active?: boolean;
};

const EDIT_TOOLS = new Set(["Edit", "Write", "NotebookEdit"]);

// テストファイル判定の慣例 pattern
const TEST_FILE_PATTERN =
  /(^|\/)(test|tests|spec|specs|__tests__)\/|(_test|_spec|\.test|\.spec)\.[a-z]+$/i;

const REVIEW_DONE_MARKER = "[subagent-review-done]";

async function readTranscript(path: string): Promise<unknown[]> {
  try {
    const txt = await Deno.readTextFile(path);
    return txt
      .trim()
      .split("\n")
      .map((line: string) => {
        try {
          return JSON.parse(line);
        } catch {
          return null;
        }
      })
      .filter((x: unknown): x is Record<string, unknown> => x !== null);
  } catch {
    return [];
  }
}

/**
 * subagent transcript の末尾から逆順に走査し、直近 user turn 以降の entries
 * を「直前のターン」とみなす。
 */
function lastAssistantTurnEntries(entries: unknown[]): unknown[] {
  let lastUserIdx = -1;
  for (let i = entries.length - 1; i >= 0; i--) {
    const e = entries[i] as { type?: string };
    if (e?.type === "user") {
      lastUserIdx = i;
      break;
    }
  }
  return entries.slice(lastUserIdx + 1);
}

type EditUse = { tool: string; path: string; order: number };

function collectEditUses(entries: unknown[]): EditUse[] {
  const uses: EditUse[] = [];
  let order = 0;
  for (const e of entries) {
    const msg = (e as { message?: { content?: unknown } })?.message;
    const content = msg?.content;
    if (!Array.isArray(content)) continue;
    for (const item of content) {
      const it = item as {
        type?: string;
        name?: string;
        input?: { file_path?: string; notebook_path?: string };
      };
      if (it?.type === "tool_use" && it?.name && EDIT_TOOLS.has(it.name)) {
        const path = it.input?.file_path ?? it.input?.notebook_path ?? "";
        uses.push({ tool: it.name, path, order: order++ });
      }
    }
  }
  return uses;
}

function hasReviewDoneMarker(entries: unknown[]): boolean {
  for (const e of entries) {
    const msg = (e as { message?: { content?: unknown } })?.message;
    const content = msg?.content;
    if (!Array.isArray(content)) continue;
    for (const item of content) {
      const it = item as { type?: string; text?: string };
      if (
        it?.type === "text" &&
        typeof it?.text === "string" &&
        it.text.includes(REVIEW_DONE_MARKER)
      ) {
        return true;
      }
    }
  }
  return false;
}

function detectTddViolation(uses: EditUse[]): {
  violated: boolean;
  detail: string;
} {
  if (uses.length === 0) return { violated: false, detail: "" };

  let firstImplOrder = -1;
  let firstImplPath = "";
  let firstTestOrder = -1;
  for (const u of uses) {
    const isTest = TEST_FILE_PATTERN.test(u.path);
    if (isTest && firstTestOrder === -1) firstTestOrder = u.order;
    if (!isTest && firstImplOrder === -1) {
      firstImplOrder = u.order;
      firstImplPath = u.path;
    }
  }

  if (firstImplOrder === -1) return { violated: false, detail: "" }; // test だけ

  if (firstTestOrder === -1) {
    return {
      violated: true,
      detail: `implementation ファイル (${firstImplPath}) を編集したが test ファイルの編集痕跡が無い`,
    };
  }

  if (firstTestOrder > firstImplOrder) {
    return {
      violated: true,
      detail: `test の編集 (order ${firstTestOrder}) が implementation の編集 (order ${firstImplOrder}, ${firstImplPath}) より後 — RED→GREEN の順序違反`,
    };
  }

  return { violated: false, detail: "" };
}

const REVIEW_PROMPT = (detail: string) =>
  `<system-reminder>
[hook: self-review-subagent] subagent 内で TDD 違反の可能性を検出しました。

検出内容: ${detail}

対応:
- 失敗テストを先に書いていない場合、後追いでもテストを追加してください
- すでにテストを追加した、または TDD をスキップする正当な理由 (1行 typo / 宣言的 config 編集 / 既存テストの修正のみ / リネーム等の構造変更) がある場合は、応答末尾に \`${REVIEW_DONE_MARKER}\` を付けてください

修正後はテストを実行して緑であることを確認してください。
</system-reminder>`;

async function main() {
  let input: SubagentStopInput = {};
  try {
    input = await new Response(Deno.stdin.readable).json();
  } catch {
    return;
  }

  if (input.stop_hook_active) return;

  const path = input.transcript_path;
  if (!path) return;

  const entries = await readTranscript(path);
  const lastTurn = lastAssistantTurnEntries(entries);

  if (hasReviewDoneMarker(lastTurn)) return;

  const uses = collectEditUses(lastTurn);
  const { violated, detail } = detectTddViolation(uses);
  if (!violated) return;

  const output = {
    decision: "block",
    reason: REVIEW_PROMPT(detail),
  };
  console.log(JSON.stringify(output));
}

await main();
