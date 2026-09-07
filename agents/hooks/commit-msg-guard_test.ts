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

Deno.test("extractCommitSubject returns inline -m message when git carries global options before commit", () => {
  const cases: [string, string][] = [
    ['git -C /tmp/repo commit -m "🐛 fix: resolve crash"', "🐛 fix: resolve crash"],
    ["git -c user.name=probe commit -m '✨ feat: add login'", "✨ feat: add login"],
    [
      'git -C /tmp/repo -c user.name=probe -c user.email=p@e.com commit -m "📝 docs: update readme"',
      "📝 docs: update readme",
    ],
    ['cd /tmp/repo && git -C /tmp/repo commit -m "✅ test: add cases"', "✅ test: add cases"],
  ];
  for (const [cmd, expected] of cases) {
    assertEquals(extractCommitSubject(cmd), expected, cmd);
  }
});

Deno.test("extractCommitSubject returns null when the commit subcommand itself reuses another message", () => {
  const cases = [
    "git commit -C HEAD~1",
    "git commit -c HEAD~1",
    "git commit --reuse-message=HEAD",
    "git -C /tmp/repo commit --amend --no-edit",
    // -m を持つ形。この 1 ケースだけが afterCommit に対する検証節を pin する
    // (他は -m を持たないため、検証節を外しても関数末尾の return null に落ちて同じ結果になる)
    'git commit --amend -m "🐛 fix: reword"',
  ];
  for (const cmd of cases) {
    assertEquals(extractCommitSubject(cmd), null, cmd);
  }
});

Deno.test("extractCommitSubject returns null when the git commit line only appears inside a heredoc body", () => {
  // ファイルに書き出すスクリプトの中身であって、実行されるコミットではない。
  // ここを subject とみなすと、コミットでないコマンドが deny される
  const command = [
    "cat > /tmp/probe.sh <<'EOF'",
    'cd /tmp/repo && git -C /tmp/repo commit -m "update stuff"',
    "EOF",
  ].join("\n");

  assertEquals(extractCommitSubject(command), null);
});

Deno.test("extractCommitSubject reads the commit message, not an unrelated heredoc written earlier in the same command", () => {
  // ファイルを heredoc で書き出してからコミットする複合コマンド。
  // 抽出をコマンド全体に対して行うと、書き出した本文の 1 行目を subject と誤認する
  const command = [
    "cat > docs/TODO.md <<'EOF'",
    "# TODO: cclog",
    "",
    "## 実装タスク",
    "EOF",
    'cd repo && git add -A && git commit -m "📝 docs: cclog の設計と TODO を追加する"',
  ].join("\n");

  assertEquals(extractCommitSubject(command), "📝 docs: cclog の設計と TODO を追加する");
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
