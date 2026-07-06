#!/usr/bin/env -S deno run --allow-env --allow-read

/**
 * コミット規約ゲート hook (PreToolUse Bash)。
 *
 * `git commit` コマンドの subject 行を rules/core/commit.md の形式
 * `<emoji> <type>: <subject>` (emoji と type の対応表つき) で機械検証し、
 * 違反していたら deny して正しい形式を提示する。
 *
 * 適用範囲: hook 入力の cwd が `$GHQ_ROOT/github.com/skanehira/` 配下のときのみ。
 * 外部リポジトリ (OSS への contribution 等) は別規約のため検証しない。
 * GHQ_ROOT 未設定時も検証しない (fail-open)。
 *
 * 検証不能なケース (--amend / -F / メッセージ抽出不能) は allow。
 * 緊急脱出: 環境変数 COMMIT_GUARD=off で素通り。
 */

export const DENY_COMMIT_FORMAT =
  "[commit-msg-guard] コミットメッセージが規約 (rules/core/commit.md) に違反しています。";

const TYPE_TO_EMOJI: Record<string, string> = {
  feat: "✨",
  fix: "🐛",
  docs: "📝",
  style: "🎨",
  refactor: "♻️",
  test: "✅",
  chore: "🔧",
  perf: "⚡",
};

const FORMAT_GUIDE = `subject は "<emoji> <type>: <subject>" 形式にしてください。emoji と type の対応: ${
  Object.entries(TYPE_TO_EMOJI).map(([t, e]) => `${t}=${e}`).join(" ")
}`;

// 検証できない (= 検証対象のメッセージを持たない) commit オプション
const UNVERIFIABLE_COMMIT_PATTERN = /\s(--amend|--no-edit|-F|--file|-C|-c|--reuse-message)\b/;

export function extractCommitSubject(command: string): string | null {
  if (!/(^|[;&|]\s*|&&\s*)git\s+commit\b/.test(command)) return null;
  if (UNVERIFIABLE_COMMIT_PATTERN.test(command)) return null;

  // HEREDOC 形式 (-m "$(cat <<'EOF' ... EOF)") を先に見る
  const heredoc = command.match(/<<\s*'?EOF'?\n([\s\S]*?)\nEOF/);
  if (heredoc) return heredoc[1].split("\n")[0];

  const inline = command.match(/\s-m\s+"([^"]*)"/) ??
    command.match(/\s-m\s+'([^']*)'/);
  if (inline) return inline[1].split("\n")[0];

  return null;
}

export type SubjectValidation = {
  ok: boolean;
  reason?: string;
};

// 絵文字の異体字セレクタ (U+FE0F) 有無の揺れを吸収して比較する
function stripVariationSelector(s: string): string {
  return s.replace(/️/g, "");
}

export function validateCommitSubject(subject: string): SubjectValidation {
  const deny = (detail: string): SubjectValidation => ({
    ok: false,
    reason: `${DENY_COMMIT_FORMAT} ${detail} ${FORMAT_GUIDE} 違反 subject: "${subject}"`,
  });

  const m = subject.match(/^(\S+)\s+([a-z]+):\s*(.*)$/u);
  if (!m) return deny("形式が <emoji> <type>: <subject> になっていません。");

  const [, emoji, type, rest] = m;
  const expected = TYPE_TO_EMOJI[type];
  if (!expected) return deny(`type "${type}" は規約の表にありません。`);
  if (stripVariationSelector(emoji) !== stripVariationSelector(expected)) {
    return deny(`type "${type}" の emoji は ${expected} です。`);
  }
  if (rest.trim() === "") return deny("subject が空です。");

  return { ok: true };
}

// ---- 以下 hook I/O 層 (settings.json から PreToolUse Bash で起動される) ----

type HookInput = {
  cwd?: string;
  tool_input?: {
    command?: string;
  };
};

function isEnforcedRepo(cwd: string | undefined): boolean {
  const ghqRoot = Deno.env.get("GHQ_ROOT");
  if (!ghqRoot || !cwd) return false;
  return cwd.startsWith(`${ghqRoot}/github.com/skanehira/`);
}

async function main() {
  if (Deno.env.get("COMMIT_GUARD") === "off") return;

  let input: HookInput = {};
  try {
    input = await new Response(Deno.stdin.readable).json();
  } catch {
    return;
  }

  const command = input.tool_input?.command;
  if (!command || !isEnforcedRepo(input.cwd)) return;

  try {
    const subject = extractCommitSubject(command);
    if (subject === null) return;

    const result = validateCommitSubject(subject);
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
