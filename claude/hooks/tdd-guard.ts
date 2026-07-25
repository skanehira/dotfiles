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
  // tdd-judge が trivial と判定した編集内容。pre-edit の deny 直前に厳密一致で突合し、
  // 一致すれば消し込んで allow する (旧状態ファイルには無い = undefined)
  pendingExemptions?: JudgedEdit[];
  // 前回の review-tdd 合格 (ok: true) 以降にテストファイル編集で armed になったか。
  // レビューゲート (Stop ブロック) の発火判定に使う (旧状態ファイルには無い = undefined)
  testEditedSinceReview?: boolean;
  // 前回の review-tdd 合格以降のテスト差分行数の概算累積 (発火閾値の判定用)
  testDiffLines?: number;
};

// tdd-judge に判定させる編集内容。Edit(old/new_string) と Write(content) を区別する。
export type JudgedEdit =
  | { op: "edit"; filePath: string; oldString: string; newString: string }
  | { op: "write"; filePath: string; content: string };

// レビューゲート (testEditedSinceReview) の発火閾値: 前回レビュー以降のテスト差分の
// 概算累積行数がこれを超えたら arm する。新規テストファイルの Write は行数に関わらず即 arm。
export const REVIEW_GATE_LINE_THRESHOLD = 20;

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
  "[tdd-guard] 実装ファイルの編集を拒否しました。このセッションではまだテストを書いていません。TDD (rules/core/tdd.md) に従い、先に失敗するテストを書いてください。" +
  "この編集がテスト不要 (スタイル調整・宣言的変更等で観測可能な振る舞いを変えない) だと考える場合は、Agent(subagent_type: \"tdd-judge\") にこの編集内容を渡して判定させてください。" +
  "指示文に次の sentinel 形式で編集内容を含めること (複数まとめて渡してよい): " +
  '<<<TDD_JUDGE_EDIT 1 op="edit" file_path="...">>>\\n--- old ---\\n<old_string>\\n--- new ---\\n<new_string>\\n<<<END_TDD_JUDGE_EDIT 1>>> ' +
  '(Write の場合は op="write" とし --- content --- <content> のみ)。trivial と判定されればこの編集は許可されます。';

export const STOP_RERUN_TESTS =
  "[tdd-guard] 実装ファイルを編集した後、テストが再実行されていません。停止する前にテストを実行して緑であることを確認してください。";

export const STOP_RUN_NEW_TEST =
  "[tdd-guard] テストファイルを編集しましたが、まだ実行されていません。停止する前にテストを実行して結果 (RED/GREEN) を確認してください。";

export const STOP_REQUEST_REVIEW =
  '[tdd-guard] 前回レビュー以降にテストの追加・変更がありました。review-tdd agent (model: "sonnet" を明示、output_path 指定) にこのセッションのテスト差分をレビューさせ、high/medium findings を修正してからテストを再実行してください。再レビューは findings があったファイルのみを対象にしてください。';

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

// Neovim 設定ツリー (vim/ 配下全体): 宣言的な keymap/autocmd/plugin spec 等で、
// このリポジトリには対応する Lua テストランナー (busted/plenary 等) が存在しないため
// テスト対象外とする。
const NVIM_CONFIG_PATTERN = /(^|\/)vim\//;

export function classifyFile(path: string): FileClass {
  if (CLAUDE_CONFIG_PATTERN.test(path)) return "exempt";
  if (NVIM_CONFIG_PATTERN.test(path)) return "exempt";

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

export function evaluateEdit(
  state: GuardState,
  cls: FileClass,
  editContent?: JudgedEdit,
): EditResult {
  if (cls === "exempt") {
    return { decision: "allow", state };
  }
  if (cls === "test") {
    // editContent が無い呼び出し (tool_input からの content/old_new_string が取れない
    // 異常系) では、レビューゲートの新規フィールドを state に持ち込まない。
    // 追加フィールドを持たない旧 state との互換性を壊さないための分岐。
    const reviewGateUpdate =
      editContent || state.testEditedSinceReview !== undefined ||
        state.testDiffLines !== undefined
        ? updateReviewGateState(state, editContent)
        : {};
    return {
      decision: "allow",
      state: {
        ...state,
        testEditedSinceRun: true,
        ...reviewGateUpdate,
      },
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
  // テストを一度も書いておらず、実行結果も無い。tdd-judge が trivial と判定した
  // 編集内容 (pendingExemptions) と実編集が厳密一致すれば、消し込んで許可する。
  if (editContent) {
    const idx = matchExemption(state.pendingExemptions ?? [], editContent);
    if (idx >= 0) {
      const remaining = (state.pendingExemptions ?? []).filter((_, i) => i !== idx);
      return { decision: "allow", state: { ...state, pendingExemptions: remaining } };
    }
  }
  return { decision: "deny", reason: DENY_NO_RED, state };
}

function countLines(text: string): number {
  if (text === "") return 0;
  return text.split("\n").length;
}

// テストファイル編集ごとに testEditedSinceReview / testDiffLines を更新する。
// 新規ファイルの Write は行数に関わらず即 arm、Edit は new_string の行数を累積し
// 閾値超過で arm する。一度 arm されたら次の review-tdd 合格までラッチする。
function updateReviewGateState(
  state: GuardState,
  editContent: JudgedEdit | undefined,
): Pick<GuardState, "testEditedSinceReview" | "testDiffLines"> {
  const priorLines = state.testDiffLines ?? 0;
  const priorArmed = state.testEditedSinceReview ?? false;

  if (!editContent) {
    return { testEditedSinceReview: priorArmed, testDiffLines: priorLines };
  }

  const isNewFile = editContent.op === "write";
  const changedLines = editContent.op === "write"
    ? countLines(editContent.content)
    : countLines(editContent.newString);
  const newDiffLines = priorLines + changedLines;
  const armed = priorArmed || isNewFile || newDiffLines > REVIEW_GATE_LINE_THRESHOLD;

  return { testEditedSinceReview: armed, testDiffLines: newDiffLines };
}

function judgedEditEquals(a: JudgedEdit, b: JudgedEdit): boolean {
  if (a.op !== b.op || a.filePath !== b.filePath) return false;
  if (a.op === "edit" && b.op === "edit") {
    return a.oldString === b.oldString && a.newString === b.newString;
  }
  if (a.op === "write" && b.op === "write") {
    return a.content === b.content;
  }
  return false;
}

// pendingExemptions から editContent と厳密一致する要素の index を返す (無ければ -1)。
export function matchExemption(list: JudgedEdit[], candidate: JudgedEdit): number {
  return list.findIndex((e) => judgedEditEquals(e, candidate));
}

// PreToolUse (Edit/Write) の tool_input から JudgedEdit を組み立てる。
// Write は content、Edit は old_string/new_string のペアで判別する。
export function buildEditContent(
  filePath: string,
  toolInput: { old_string?: string; new_string?: string; content?: string } | undefined,
): JudgedEdit | undefined {
  if (toolInput?.content !== undefined) {
    return { op: "write", filePath, content: toolInput.content };
  }
  if (toolInput?.old_string !== undefined && toolInput?.new_string !== undefined) {
    return {
      op: "edit",
      filePath,
      oldString: toolInput.old_string,
      newString: toolInput.new_string,
    };
  }
  return undefined;
}

// tdd-judge への指示文 (prompt) に埋め込まれた sentinel ブロックを機械抽出する。
// 書式: <<<TDD_JUDGE_EDIT n op="edit"|"write" file_path="...">>>\n<body>\n<<<END_TDD_JUDGE_EDIT n>>>
const JUDGE_SENTINEL_PATTERN =
  /<<<TDD_JUDGE_EDIT (\d+) op="(edit|write)" file_path="([^"]*)">>>\n([\s\S]*?)\n<<<END_TDD_JUDGE_EDIT \1>>>/g;

export function extractJudgeSentinels(
  prompt: string,
): { index: number; edit: JudgedEdit }[] {
  const results: { index: number; edit: JudgedEdit }[] = [];
  for (const m of prompt.matchAll(JUDGE_SENTINEL_PATTERN)) {
    const index = Number(m[1]);
    const op = m[2] as "edit" | "write";
    const filePath = m[3];
    const body = m[4];

    if (op === "write") {
      const cm = body.match(/^--- content ---\n([\s\S]*)$/);
      if (!cm) continue;
      results.push({ index, edit: { op: "write", filePath, content: cm[1] } });
    } else {
      const em = body.match(/^--- old ---\n([\s\S]*?)\n--- new ---\n([\s\S]*)$/);
      if (!em) continue;
      results.push({
        index,
        edit: { op: "edit", filePath, oldString: em[1], newString: em[2] },
      });
    }
  }
  return results;
}

export type JudgeVerdict = {
  index: number;
  filePath: string;
  verdict: "trivial" | "behavioral";
};

// 文字列中から最初の '{' 〜 最後の '}' を切り出す (agent の応答が JSON 前後にプロースを含む場合の救済)。
function extractJsonObject(text: string): string | null {
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start === -1 || end === -1 || end < start) return null;
  return text.slice(start, end + 1);
}

// tdd-judge の応答テキストから verdict JSON をパースする。形式不正・値不正なら null (fail-safe)。
export function parseJudgeVerdicts(text: string): JudgeVerdict[] | null {
  const candidate = extractJsonObject(text);
  if (!candidate) return null;

  let parsed: unknown;
  try {
    parsed = JSON.parse(candidate);
  } catch {
    return null;
  }

  const verdicts = (parsed as { verdicts?: unknown })?.verdicts;
  if (!Array.isArray(verdicts)) return null;

  const result: JudgeVerdict[] = [];
  for (const v of verdicts) {
    const index = (v as { index?: unknown })?.index;
    const filePath = (v as { file_path?: unknown })?.file_path;
    const verdict = (v as { verdict?: unknown })?.verdict;
    if (typeof index !== "number") return null;
    if (typeof filePath !== "string") return null;
    if (verdict !== "trivial" && verdict !== "behavioral") return null;
    result.push({ index, filePath, verdict });
  }
  return result;
}

// sentinel (judge に渡した編集内容) と verdict (judge の判定) を index で対応付け、
// trivial かつ file_path が sentinel と一致するものだけを pendingExemptions 候補として返す。
export function buildExemptions(
  sentinels: { index: number; edit: JudgedEdit }[],
  verdicts: JudgeVerdict[],
): JudgedEdit[] {
  const byIndex = new Map(sentinels.map((s) => [s.index, s.edit]));
  const result: JudgedEdit[] = [];
  for (const v of verdicts) {
    if (v.verdict !== "trivial") continue;
    const edit = byIndex.get(v.index);
    if (!edit) continue;
    if (edit.filePath !== v.filePath) continue;
    result.push(edit);
  }
  return result;
}

export function applyTestRun(state: GuardState, failed: boolean): GuardState {
  // pendingExemptions (tdd-judge の免除) と testEditedSinceReview/testDiffLines
  // (レビューゲート) はテスト実行と無関係に持ち越す。RED→GREEN サイクルのたびに
  // 免除やレビュー要求が消えてしまうと、それぞれの機構が骨抜きになるため。
  // stopBlockCount は従来通りテスト実行でリセットする (=結果を返す新しい state に含めない)。
  return {
    lastRun: failed ? "red" : "green",
    testEditedSinceRun: false,
    implEditedSinceRun: false,
    ...(state.pendingExemptions !== undefined
      ? { pendingExemptions: state.pendingExemptions }
      : {}),
    ...(state.testEditedSinceReview !== undefined
      ? { testEditedSinceReview: state.testEditedSinceReview }
      : {}),
    ...(state.testDiffLines !== undefined
      ? { testDiffLines: state.testDiffLines }
      : {}),
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
  if (state.testEditedSinceReview) {
    return { block: true, reason: STOP_REQUEST_REVIEW };
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
    old_string?: string;
    new_string?: string;
    content?: string;
    subagent_type?: string;
    prompt?: string;
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

  const editContent = buildEditContent(path, input.tool_input);
  const result = evaluateEdit(state, classifyFile(path), editContent);
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

  if (input.tool_input?.subagent_type === "tdd-judge") {
    await handleJudgeReport(input, state, text);
    return;
  }

  if (input.tool_input?.subagent_type === "review-tdd") {
    await handleReviewReport(input, state, text);
    return;
  }

  const result = detectDelegatedTestResult(text);
  if (result === null) return;

  await saveState(input.session_id!, applyTestRun(state, result === "red"));
}

// tdd-judge subagent の報告を処理する。TDD_GUARD_JUDGE=off なら誘導・免除機構ごと
// 無効化 (現行の常時 deny に戻す)。sentinel 抽出・verdict パースのいずれかが失敗したら
// 何も免除しない (fail-safe)。
async function handleJudgeReport(
  input: HookInput,
  state: GuardState,
  responseText: string,
) {
  if (Deno.env.get("TDD_GUARD_JUDGE") === "off") return;

  const prompt = input.tool_input?.prompt ?? "";
  const sentinels = extractJudgeSentinels(prompt);
  const verdicts = parseJudgeVerdicts(responseText);
  if (!verdicts) return;

  const exemptions = buildExemptions(sentinels, verdicts);
  if (exemptions.length === 0) return;

  await saveState(input.session_id!, {
    ...state,
    pendingExemptions: [...(state.pendingExemptions ?? []), ...exemptions],
  });
}

// review-tdd subagent の報告を処理する。stdout は output_path の絶対パスのみという
// review-tdd.md の契約に従い、そのファイルを直接読んで ok: true のときだけレビュー
// ゲートを解除する。「done と言わせる」マーカー方式は使わない (findings が残る限り
// ゲートは開かない)。パス取得・読み込み・パースのいずれかが失敗したらクリアしない (fail-safe)。
async function handleReviewReport(
  input: HookInput,
  state: GuardState,
  responseText: string,
) {
  const path = responseText.trim();
  if (!path) return;

  let parsed: unknown;
  try {
    const txt = await Deno.readTextFile(path);
    parsed = JSON.parse(txt);
  } catch {
    return;
  }

  if ((parsed as { ok?: unknown })?.ok !== true) return;

  await saveState(input.session_id!, {
    ...state,
    testEditedSinceReview: false,
    testDiffLines: 0,
  });
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
