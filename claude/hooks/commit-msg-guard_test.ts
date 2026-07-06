import { assertEquals } from "jsr:@std/assert";
import {
  DENY_COMMIT_FORMAT,
  extractCommitSubject,
  validateCommitSubject,
} from "./commit-msg-guard.ts";

Deno.test("extractCommitSubject returns first line of heredoc commit message", () => {
  const command = `git commit -m "$(cat <<'EOF'
✨ feat: add user authentication

Implement JWT-based authentication.
EOF
)"`;

  assertEquals(extractCommitSubject(command), "✨ feat: add user authentication");
});

Deno.test("extractCommitSubject returns inline -m message", () => {
  const cases: [string, string][] = [
    ['git commit -m "🐛 fix: resolve crash"', "🐛 fix: resolve crash"],
    ["git commit -m '📝 docs: update readme'", "📝 docs: update readme"],
    ['git add foo.ts && git commit -m "✅ test: add cases"', "✅ test: add cases"],
  ];
  for (const [cmd, expected] of cases) {
    assertEquals(extractCommitSubject(cmd), expected, cmd);
  }
});

Deno.test("extractCommitSubject returns null for non-commit or unverifiable commands", () => {
  const cases = [
    "git status",
    "git commit --amend --no-edit",
    "git commit -F message.txt",
    "ls -la",
    'echo "git commit -m test"',
  ];
  for (const cmd of cases) {
    assertEquals(extractCommitSubject(cmd), null, cmd);
  }
});

Deno.test("validateCommitSubject accepts conventional subjects with matching emoji", () => {
  const cases = [
    "✨ feat: add user authentication",
    "🐛 fix: resolve crash on startup",
    "📝 docs: [STRUCTURAL] update README",
    "🎨 style: format code",
    "♻️ refactor: extract helper",
    "✅ test: add edge cases",
    "🔧 chore: update CI config",
    "⚡ perf: cache lookups",
  ];
  for (const subject of cases) {
    assertEquals(validateCommitSubject(subject), { ok: true }, subject);
  }
});

Deno.test("validateCommitSubject rejects malformed subjects with a reason", () => {
  const cases = [
    "add user authentication", // emoji も type も無い
    "feat: add user authentication", // emoji 無し
    "✨ fix: mismatched emoji and type", // emoji と type の不一致
    "✨ build: unknown type", // 表に無い type
    "✨ feat:", // subject 無し
  ];
  for (const subject of cases) {
    const result = validateCommitSubject(subject);
    assertEquals(result.ok, false, subject);
    assertEquals(result.reason?.startsWith(DENY_COMMIT_FORMAT), true, subject);
  }
});
