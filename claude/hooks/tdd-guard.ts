#!/usr/bin/env -S deno run --allow-env --allow-read --allow-write

/**
 * TDD ゲート hook (PreToolUse / PostToolUse / Stop / SubagentStop 兼用)。
 *
 * 事後の自己申告に頼らず、実装ファイルへの Edit/Write を tool call の時点で
 * 機械的にゲートする。LLM の追加ターンは発生しない。
 *
 * 状態機械 (セッション単位、~/.claude/tdd-guard/<session_id>.json に永続化):
 *
 *   - テストコマンド実行 (PostToolUse Bash) → exit 結果から lastRun = red|green
 *   - テストファイル編集 → 常に許可、testEditedSinceRun = true
 *   - 実装ファイル編集:
 *       lastRun == red                        → 許可 (GREEN フェーズ)
 *       lastRun == green && テスト編集なし     → 許可 (REFACTOR)
 *       それ以外                              → deny (先に失敗テストを書いて RED 確認)
 *   - Stop/SubagentStop 時に「編集後テスト未実行」フラグが残っていれば 1 回だけ block
 *
 * ゲート対象: GATED_EXTENSIONS に列挙した実装言語の拡張子のみ。
 * それ以外 (md / json / yaml / nix / sh 等) と *.config.* 等の宣言的ファイルは対象外。
 * 緊急脱出: 環境変数 TDD_GUARD=off で全イベント素通り。
 *
 * イベントは --event <pre-edit|post-bash|stop> で指定する (settings.json 配線)。
 */

export type FileClass = "test" | "impl" | "exempt";

export type GuardState = {
  lastRun: "red" | "green" | null;
  testEditedSinceRun: boolean;
  implEditedSinceRun: boolean;
};

export type EditResult = {
  decision: "allow" | "deny";
  reason?: string;
  state: GuardState;
};

export type StopResult = {
  block: boolean;
  reason?: string;
};

export const DENY_NO_RED =
  "[tdd-guard] 実装ファイルの編集を拒否しました。このセッションではまだテストが実行されていません。TDD (rules/core/tdd.md) に従い、先に失敗するテストを書いて実行し、RED を確認してから実装してください。例外 (typo 修正等) は該当ファイルがテスト対象外である理由をユーザに説明した上で、テストを先に用意してください。";

export const DENY_UNVERIFIED_TEST =
  "[tdd-guard] 実装ファイルの編集を拒否しました。テストファイルを編集した後、まだテストを実行して RED (失敗) を確認していません。先にテストを実行して失敗を確認してから実装に進んでください。";

export const STOP_RERUN_TESTS =
  "[tdd-guard] 実装ファイルを編集した後、テストが再実行されていません。停止する前にテストを実行して緑であることを確認してください。";

export const STOP_RUN_NEW_TEST =
  "[tdd-guard] テストファイルを編集しましたが、まだ実行されていません。停止する前にテストを実行して結果 (RED/GREEN) を確認してください。";

const TEST_FILE_PATTERN =
  /(^|\/)(test|tests|spec|specs|__tests__)\/|(_test|_spec|\.test|\.spec)\.[a-z]+$/i;

// テスト対象 (ゲート対象) の実装言語だけを列挙する。ここに無い拡張子は exempt
const GATED_EXTENSIONS = new Set([
  "ts",
  "tsx",
  "mts",
  "cts",
  "js",
  "jsx",
  "mjs",
  "cjs",
  "rs",
  "go",
  "lua",
]);

// ゲート対象拡張子でもテスト不要な宣言的ファイル
const EXEMPT_BASENAME_PATTERNS = [
  /^\..*rc(\.\w+)?$/, // .eslintrc.js など
  /\.config\.[cm]?[jt]sx?$/, // vite.config.ts, next.config.mjs など
  /\.workflow\.js$/, // Workflow スクリプト (Workflow ランタイム外で単体テスト不能)
];

export function classifyFile(path: string): FileClass {
  const basename = path.split("/").pop() ?? path;
  const ext = basename.includes(".") ? basename.split(".").pop()!.toLowerCase() : "";

  if (!GATED_EXTENSIONS.has(ext)) return "exempt";
  if (EXEMPT_BASENAME_PATTERNS.some((re) => re.test(basename))) return "exempt";
  if (TEST_FILE_PATTERN.test(path)) return "test";
  return "impl";
}

const TEST_COMMAND_PATTERNS = [
  /\bdeno test\b/,
  /\bcargo test\b/,
  /\bcargo nextest\b/,
  /\bgo test\b/,
  /\bpytest\b/,
  /\bvitest\b/,
  /\bjest\b/,
  /\bbun test\b/,
  /\b(npm|pnpm|yarn)( run)? test/,
  /\bmake test\b/,
];

export function detectTestCommand(command: string): boolean {
  // クォート内 (コミットメッセージ等) の文字列は判定対象から外す
  const stripped = command
    .replace(/"[^"]*"/g, " ")
    .replace(/'[^']*'/g, " ");
  return TEST_COMMAND_PATTERNS.some((re) => re.test(stripped));
}

export function evaluateEdit(state: GuardState, cls: FileClass): EditResult {
  if (cls === "exempt") {
    return { decision: "allow", state };
  }
  if (cls === "test") {
    return {
      decision: "allow",
      state: { ...state, testEditedSinceRun: true },
    };
  }
  // impl
  if (state.lastRun === "red") {
    return {
      decision: "allow",
      state: { ...state, implEditedSinceRun: true },
    };
  }
  if (state.lastRun === "green" && !state.testEditedSinceRun) {
    return {
      decision: "allow",
      state: { ...state, implEditedSinceRun: true },
    };
  }
  if (state.lastRun === "green" && state.testEditedSinceRun) {
    return { decision: "deny", reason: DENY_UNVERIFIED_TEST, state };
  }
  return { decision: "deny", reason: DENY_NO_RED, state };
}

export function applyTestRun(_state: GuardState, failed: boolean): GuardState {
  return {
    lastRun: failed ? "red" : "green",
    testEditedSinceRun: false,
    implEditedSinceRun: false,
  };
}

export type ToolResponse = {
  exit_code?: number;
  is_error?: boolean;
  stdout?: string;
  stderr?: string;
};

// 「1 件以上 failed」のみ失敗扱い ("0 failed" は成功サマリに含まれるため除外)
const FAILURE_MARKERS = [
  /\bFAILED\b/,
  /(^|\n)(--- )?FAIL\b/,
  /[1-9]\d* failed/,
];

export function didTestsFail(response: ToolResponse): boolean {
  if (typeof response.exit_code === "number") {
    return response.exit_code !== 0;
  }
  if (typeof response.is_error === "boolean") {
    return response.is_error;
  }
  const output = `${response.stdout ?? ""}\n${response.stderr ?? ""}`;
  return FAILURE_MARKERS.some((re) => re.test(output));
}

export function evaluateStop(state: GuardState): StopResult {
  if (state.implEditedSinceRun) {
    return { block: true, reason: STOP_RERUN_TESTS };
  }
  if (state.testEditedSinceRun) {
    return { block: true, reason: STOP_RUN_NEW_TEST };
  }
  return { block: false };
}

// ---- 以下 hook I/O 層 (settings.json から --event 付きで起動される) ----

type HookInput = {
  session_id?: string;
  stop_hook_active?: boolean;
  tool_name?: string;
  tool_input?: {
    file_path?: string;
    notebook_path?: string;
    command?: string;
  };
  tool_response?: ToolResponse;
};

const INITIAL_STATE: GuardState = {
  lastRun: null,
  testEditedSinceRun: false,
  implEditedSinceRun: false,
};

function stateFilePath(sessionId: string): string {
  const home = Deno.env.get("HOME") ?? "/tmp";
  return `${home}/.claude/tdd-guard/${sessionId}.json`;
}

async function loadState(sessionId: string): Promise<GuardState> {
  try {
    const txt = await Deno.readTextFile(stateFilePath(sessionId));
    return { ...INITIAL_STATE, ...JSON.parse(txt) };
  } catch {
    return INITIAL_STATE;
  }
}

async function saveState(sessionId: string, state: GuardState): Promise<void> {
  const path = stateFilePath(sessionId);
  await Deno.mkdir(path.substring(0, path.lastIndexOf("/")), {
    recursive: true,
  });
  await Deno.writeTextFile(path, JSON.stringify(state));
}

async function handlePreEdit(input: HookInput, state: GuardState) {
  const path = input.tool_input?.file_path ?? input.tool_input?.notebook_path;
  if (!path) return;

  const result = evaluateEdit(state, classifyFile(path));
  await saveState(input.session_id!, result.state);

  if (result.decision === "deny") {
    console.log(JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: result.reason,
      },
    }));
  }
}

async function handlePostBash(input: HookInput, state: GuardState) {
  const command = input.tool_input?.command;
  if (!command || !detectTestCommand(command)) return;

  const failed = didTestsFail(input.tool_response ?? {});
  await saveState(input.session_id!, applyTestRun(state, failed));
}

async function handleStop(input: HookInput, state: GuardState) {
  // この hook が起こした再ターンでの再 block はしない (無限ループ防止)。
  // フラグは残したままにせず消す (1 違反 1 リマインドで打ち止め、次ターンに持ち越さない)
  if (input.stop_hook_active) {
    await saveState(input.session_id!, {
      ...state,
      testEditedSinceRun: false,
      implEditedSinceRun: false,
    });
    return;
  }

  const result = evaluateStop(state);
  if (result.block) {
    console.log(JSON.stringify({ decision: "block", reason: result.reason }));
  }
}

async function main() {
  if (Deno.env.get("TDD_GUARD") === "off") return;

  const eventIdx = Deno.args.indexOf("--event");
  const event = eventIdx >= 0 ? Deno.args[eventIdx + 1] : "";

  let input: HookInput = {};
  try {
    input = await new Response(Deno.stdin.readable).json();
  } catch {
    return;
  }
  if (!input.session_id) return;

  const state = await loadState(input.session_id);

  try {
    if (event === "pre-edit") await handlePreEdit(input, state);
    else if (event === "post-bash") await handlePostBash(input, state);
    else if (event === "stop") await handleStop(input, state);
  } catch {
    // hook の失敗でセッションを壊さない
  }
}

if (import.meta.main) {
  await main();
}
