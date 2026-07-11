#!/usr/bin/env -S deno run --allow-env --allow-read --allow-write

/**
 * TDD ゲート hook (PreToolUse / PostToolUse / Stop / SubagentStop 兼用)。
 *
 * 事後の自己申告に頼らず、実装ファイルへの Edit/Write を tool call の時点で
 * 機械的にゲートする。LLM の追加ターンは発生しない。
 *
 * 状態機械 (セッション単位、~/.claude/tdd-guard/<session_id>.json に永続化):
 *
 *   - テストコマンド実行 (PostToolUse Bash) → exit/出力から lastRun = red|green
 *   - テストファイル編集 → 常に許可、testEditedSinceRun = true
 *   - 実装ファイル編集:
 *       テスト編集あり (testEditedSinceRun)   → 許可 (RED フェーズ = 失敗テストを書いた直後)
 *       lastRun == red                        → 許可 (GREEN フェーズ)
 *       lastRun == green                      → 許可 (REFACTOR)
 *       テスト編集なし & lastRun == null       → deny (テストを一度も書いていない)
 *   - Stop/SubagentStop 時に「編集後テスト未実行」フラグが残っていれば block
 *     (テスト実行でフラグが消えるまで最大 MAX_STOP_BLOCKS 回。上限到達で諦めて通す)
 *   - Bash コマンドのファイル書き込み (> / >> / tee / sed -i / patch / git apply) が
 *     ゲート対象ソースを向いていたら deny し、Edit/Write ツールへ誘導 (pre-bash)
 *   - サブエージェント委譲 (PostToolUse Task/Agent) → 報告本文の TDD_GUARD: green|red マーカーで lastRun を更新 (post-agent)
 *
 * RED 観測の制約: Claude Code は Bash が非ゼロ終了すると PostToolUse を発火しない。
 * よって失敗するテスト実行 (RED) の結果をフックから捕捉できない。そのため「テストを
 * 編集した」こと自体を RED シグナルとして扱い実装を許可する。最終的なグリーンは Stop
 * ゲート (implEditedSinceRun が残ると block) が担保し、緑の実行時のみ PostToolUse が
 * 発火して緑が記録される。didTestsFail は exit コードに加え出力マーカーでも失敗を拾う。
 *
 * ゲート対象: GATED_EXTENSIONS に列挙した実装言語の拡張子のみ。
 * それ以外 (md / json / yaml / nix / sh 等) と *.config.* 等の宣言的ファイルは対象外。
 * Claude harness 設定ツリー (.claude/ や claude/hooks|agents|skills|rules|commands|plugins/) も対象外。
 * 緊急脱出: 環境変数 TDD_GUARD=off で全イベント素通り。
 *
 * イベントは --event <pre-edit|post-bash|stop> で指定する (settings.json 配線)。
 */

export type FileClass = "test" | "impl" | "exempt";

export type GuardState = {
  lastRun: "red" | "green" | null;
  testEditedSinceRun: boolean;
  implEditedSinceRun: boolean;
  // Stop で block した回数。テスト実行でリセット。旧状態ファイルには無い (undefined = 0)
  stopBlockCount?: number;
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
  "[tdd-guard] 実装ファイルの編集を拒否しました。このセッションではまだテストを書いていません。TDD (rules/core/tdd.md) に従い、先に失敗するテストを書いてから実装してください。例外 (typo 修正等) は該当ファイルがテスト対象外である理由をユーザに説明した上で、テストを先に用意してください。";

export const STOP_RERUN_TESTS =
  "[tdd-guard] 実装ファイルを編集した後、テストが再実行されていません。停止する前にテストを実行して緑であることを確認してください。";

export const STOP_RUN_NEW_TEST =
  "[tdd-guard] テストファイルを編集しましたが、まだ実行されていません。停止する前にテストを実行して結果 (RED/GREEN) を確認してください。";

export const DENY_BASH_WRITE =
  "[tdd-guard] Bash 経由でのソースファイル書き込みを拒否しました。実装・テストファイルの編集は Edit / Write ツールで行ってください (TDD ゲートの対象にするため)。対象: ";

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

// Claude harness 設定ツリー: デプロイ済み .claude/ 配下、および dotfiles 側の
// claude/hooks|agents|skills|rules|commands|plugins/ 配下。アプリ内にたまたま
// claude/ ディレクトリがあっても harness サブディレクトリでなければ対象にしない。
const CLAUDE_CONFIG_PATTERN =
  /(^|\/)\.claude\/|(^|\/)claude\/(hooks|agents|skills|rules|commands|plugins)\//;

// Neovim lazy.nvim のプラグイン定義 (vim/lua/plugins/ 配下): 宣言的な plugin spec でテスト対象外
const NVIM_PLUGIN_SPEC_PATTERN = /(^|\/)vim\/lua\/plugins\//;

export function classifyFile(path: string): FileClass {
  if (CLAUDE_CONFIG_PATTERN.test(path)) return "exempt";
  if (NVIM_PLUGIN_SPEC_PATTERN.test(path)) return "exempt";

  const basename = path.split("/").pop() ?? path;
  const ext = basename.includes(".")
    ? basename.split(".").pop()!.toLowerCase()
    : "";

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
  // RED フェーズ: 最後のテスト実行以降にテストを編集した = 失敗するテストを書いた直後とみなす。
  // Claude Code は Bash 非ゼロ終了時に PostToolUse を発火せず RED 実行を観測できないため、
  // テスト編集自体を RED シグナルとして許可する(最終グリーンは Stop ゲートで担保)。
  if (state.testEditedSinceRun) {
    return {
      decision: "allow",
      state: { ...state, implEditedSinceRun: true },
    };
  }
  // GREEN フェーズ(直近の実行が赤)/ REFACTOR(直近の実行が緑・新規テストなし)。
  if (state.lastRun === "red" || state.lastRun === "green") {
    return {
      decision: "allow",
      state: { ...state, implEditedSinceRun: true },
    };
  }
  // テストを一度も書いておらず、実行結果も無い。
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
  /(^|\s)Failed :\s*[1-9]/, // plenary/busted (nvim): "Failed : 5"
  /(^|\s)Errors :\s*[1-9]/, // plenary/busted (nvim): "Errors : 2"
];

export function didTestsFail(response: ToolResponse): boolean {
  const output = `${response.stdout ?? ""}\n${response.stderr ?? ""}`;
  // exit 0 でも出力が失敗を示すランナー(0 終了する構成)があるので、出力マーカーも併用する。
  const outputSaysFailed = FAILURE_MARKERS.some((re) => re.test(output));
  if (typeof response.exit_code === "number") {
    return response.exit_code !== 0 || outputSaysFailed;
  }
  if (typeof response.is_error === "boolean") {
    return response.is_error || outputSaysFailed;
  }
  return outputSaysFailed;
}

// サブエージェントへテスト実行を委譲した場合、親セッションの state はサブエージェント
// 自身の session_id に書かれてしまうため親に反映されない。報告本文に含めさせた
// TDD_GUARD: green|red マーカーで親 state を更新する (post-agent イベント)。
const DELEGATED_RED_PATTERN = /tdd_guard:\s*red\b/i;
const DELEGATED_GREEN_PATTERN = /tdd_guard:\s*green\b/i;

export function detectDelegatedTestResult(text: string): "green" | "red" | null {
  // fail-safe: 両方あれば red を優先
  if (DELEGATED_RED_PATTERN.test(text)) return "red";
  if (DELEGATED_GREEN_PATTERN.test(text)) return "green";
  return null;
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

// 汚れた状態 (編集後テスト未実行) での停止を block できる最大回数。
// テスト実行 (applyTestRun) でフラグとカウンタが消えるため、素直にテストを
// 実行すれば block は 1 回で済む。上限到達 = リマインドを無視し続けたケースで、
// これ以上 block しても前進しないため諦めて通す (無限ループ防止)。
export const MAX_STOP_BLOCKS = 2;

export type StopAttemptResult = {
  block: boolean;
  reason?: string;
  state: GuardState;
};

export function evaluateStopAttempt(state: GuardState): StopAttemptResult {
  const verdict = evaluateStop(state);
  if (!verdict.block) {
    return { block: false, state: { ...state, stopBlockCount: 0 } };
  }
  const count = state.stopBlockCount ?? 0;
  if (count >= MAX_STOP_BLOCKS) {
    return {
      block: false,
      state: {
        ...state,
        testEditedSinceRun: false,
        implEditedSinceRun: false,
        stopBlockCount: 0,
      },
    };
  }
  return {
    block: true,
    reason: verdict.reason,
    state: { ...state, stopBlockCount: count + 1 },
  };
}

// Bash コマンドからファイル書き込み先を抽出する。Edit/Write ツールを迂回した
// ソース編集 (リダイレクト / tee / sed -i / patch / git apply) を検知するための
// ベストエフォート実装。クォート内 (コミットメッセージ等) は判定対象から外す。
const IN_PLACE_EDIT_PATTERNS = [
  /\bsed\s+(?:-\S+\s+)*-i\b/,
  /\bpatch\b/,
  /\bgit\s+apply\b/,
];

const GATED_EXT_PATTERN = new RegExp(
  `\\.(${[...GATED_EXTENSIONS].join("|")})$`,
  "i",
);

export function extractBashWriteTargets(command: string): string[] {
  const stripped = command
    .replace(/"[^"]*"/g, " ")
    .replace(/'[^']*'/g, " ");

  const targets: string[] = [];
  for (const m of stripped.matchAll(/(?:>>?\s*|\btee\s+(?:-a\s+)?)([^\s;|&]+)/g)) {
    targets.push(m[1]);
  }
  // in-place 編集系はリダイレクトと違い書き込み先が構文から確定しないため、
  // 同一コマンド区切り内のゲート対象拡張子トークンを書き込み先とみなす
  for (const segment of stripped.split(/[;|&]+/)) {
    if (!IN_PLACE_EDIT_PATTERNS.some((re) => re.test(segment))) continue;
    for (const token of segment.split(/\s+/)) {
      if (GATED_EXT_PATTERN.test(token)) targets.push(token);
    }
  }
  return targets;
}

export type BashCommandResult = {
  decision: "allow" | "deny";
  reason?: string;
};

export function evaluateBashCommand(command: string): BashCommandResult {
  const sources = extractBashWriteTargets(command)
    .filter((t) => classifyFile(t) !== "exempt");
  if (sources.length === 0) return { decision: "allow" };
  return {
    decision: "deny",
    reason: `${DENY_BASH_WRITE}${sources.join(", ")}`,
  };
}

// ---- 以下 hook I/O 層 (settings.json から --event 付きで起動される) ----

type HookInput = {
  session_id?: string;
  tool_name?: string;
  tool_input?: {
    file_path?: string;
    notebook_path?: string;
    command?: string;
  };
  tool_response?: ToolResponse | string | unknown;
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

async function handlePostAgent(input: HookInput, state: GuardState) {
  const raw = input.tool_response;
  const text = typeof raw === "string" ? raw : JSON.stringify(raw ?? "");
  const result = detectDelegatedTestResult(text);
  if (result === null) return;

  await saveState(input.session_id!, applyTestRun(state, result === "red"));
}

async function handleStop(input: HookInput, state: GuardState) {
  // 汚れた状態 (編集後テスト未実行) なら MAX_STOP_BLOCKS 回まで block して
  // テスト実行を促す。テストを実行すれば post-bash がフラグとカウンタを消すので
  // 次の停止は素通りする。上限到達で諦めて通す (無限ループ防止)。
  const result = evaluateStopAttempt(state);
  await saveState(input.session_id!, result.state);

  if (result.block) {
    console.log(JSON.stringify({ decision: "block", reason: result.reason }));
  }
}

function handlePreBash(input: HookInput) {
  const command = input.tool_input?.command;
  if (!command) return;

  const result = evaluateBashCommand(command);
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
    else if (event === "pre-bash") handlePreBash(input);
    else if (event === "post-bash") await handlePostBash(input, state);
    else if (event === "post-agent") await handlePostAgent(input, state);
    else if (event === "stop") await handleStop(input, state);
  } catch {
    // hook の失敗でセッションを壊さない
  }
}

if (import.meta.main) {
  await main();
}
