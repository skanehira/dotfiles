import { assertEquals } from "jsr:@std/assert";
import {
  applyTestRun,
  classifyFile,
  DENY_BASH_WRITE,
  DENY_NO_RED,
  detectDelegatedTestResult,
  detectTestCommand,
  didTestsFail,
  evaluateBashCommand,
  evaluateEdit,
  evaluateStop,
  evaluateStopAttempt,
  extractBashWriteTargets,
  type GuardState,
  STOP_RERUN_TESTS,
  STOP_RUN_NEW_TEST,
} from "./tdd-guard.ts";

const initialState: GuardState = {
  lastRun: null,
  testEditedSinceRun: false,
  implEditedSinceRun: false,
};

Deno.test("classifyFile returns test for test file conventions", () => {
  const cases = [
    "src/foo.test.ts",
    "src/__tests__/Button.tsx",
    "pkg/parser_test.go",
    "src/lib_test.rs",
  ];
  for (const path of cases) {
    assertEquals(classifyFile(path), "test", path);
  }
});

Deno.test("classifyFile returns impl for production code files", () => {
  const cases = [
    "src/foo.ts",
    "src/main.rs",
    "lib/util.go",
    "cmd/server/handler.lua",
  ];
  for (const path of cases) {
    assertEquals(classifyFile(path), "impl", path);
  }
});

Deno.test("classifyFile returns exempt for docs and declarative config", () => {
  const cases = [
    "README.md",
    "package.json",
    "config/app.yaml",
    "docker-compose.yml",
    "flake.nix",
    "Cargo.toml",
    "Cargo.lock",
    "vite.config.ts",
    "next.config.mjs",
    ".eslintrc",
    ".eslintrc.js",
    "styles/main.css",
    "index.html",
    ".env.example",
    "Makefile",
    "Dockerfile",
    "references/phase-pipeline.workflow.js",
    // py/rb は GATED_EXTENSIONS から外れたので exempt(ff3de6e で除外)
    "tests/helper.py",
    "app/models/user.rb",
    "spec/models/user_spec.rb",
  ];
  for (const path of cases) {
    assertEquals(classifyFile(path), "exempt", path);
  }
});

Deno.test("classifyFile returns exempt for extensions outside the gated allowlist", () => {
  const cases = [
    "scripts/install.sh",
    "db/schema.sql",
    "assets/logo.png",
    "fonts/inter.woff2",
    "proto/api.proto",
    "terraform/main.tf",
  ];
  for (const path of cases) {
    assertEquals(classifyFile(path), "exempt", path);
  }
});

Deno.test("classifyFile returns exempt for Claude harness config files", () => {
  const cases = [
    "/Users/x/dotfiles/claude/hooks/remind-rules.ts",
    "/Users/x/.claude/hooks/foo.ts",
    "/Users/x/dotfiles/claude/agents/foo.ts",
    "/Users/x/dotfiles/claude/skills/foo/bar.ts",
    "/Users/x/dotfiles/claude/commands/foo.ts",
    "/Users/x/dotfiles/claude/plugins/foo/bar.ts",
  ];
  for (const path of cases) {
    assertEquals(classifyFile(path), "exempt", path);
  }
});

Deno.test("classifyFile does not over-exempt a non-harness claude/ directory", () => {
  const result = classifyFile("/proj/src/claude/model.ts");

  assertEquals(result, "impl");
});

Deno.test("detectTestCommand returns true for test runner invocations", () => {
  const cases = [
    "deno test --allow-read",
    "cargo test",
    "cargo nextest run",
    "go test ./...",
    "pytest -x tests/",
    "python -m pytest",
    "npx vitest run",
    "pnpm test",
    "npm run test:unit",
    "yarn test",
    "bun test",
    "npx jest src/foo.test.ts",
    "make test",
  ];
  for (const cmd of cases) {
    assertEquals(detectTestCommand(cmd), true, cmd);
  }
});

Deno.test("detectTestCommand returns false for non-test commands", () => {
  const cases = [
    "cargo build",
    "npm run build",
    'git commit -m "add vitest config"',
    "ls -la",
    "deno run main.ts",
    "go build ./...",
    "echo test",
  ];
  for (const cmd of cases) {
    assertEquals(detectTestCommand(cmd), false, cmd);
  }
});

Deno.test("evaluateEdit allows test file edit and marks unverified test", () => {
  const result = evaluateEdit(initialState, "test");

  assertEquals(result, {
    decision: "allow",
    state: {
      lastRun: null,
      testEditedSinceRun: true,
      implEditedSinceRun: false,
    },
  });
});

Deno.test("evaluateEdit allows exempt file edit without state change", () => {
  const result = evaluateEdit(initialState, "exempt");

  assertEquals(result, { decision: "allow", state: initialState });
});

Deno.test("evaluateEdit denies impl edit when no test has been run", () => {
  const result = evaluateEdit(initialState, "impl");

  assertEquals(result, {
    decision: "deny",
    reason: DENY_NO_RED,
    state: initialState,
  });
});

Deno.test("evaluateEdit allows impl edit when last run is red", () => {
  const state: GuardState = {
    lastRun: "red",
    testEditedSinceRun: true,
    implEditedSinceRun: false,
  };

  const result = evaluateEdit(state, "impl");

  assertEquals(result, {
    decision: "allow",
    state: {
      lastRun: "red",
      testEditedSinceRun: true,
      implEditedSinceRun: true,
    },
  });
});

Deno.test("evaluateEdit allows refactor (impl edit on green without new tests)", () => {
  const state: GuardState = {
    lastRun: "green",
    testEditedSinceRun: false,
    implEditedSinceRun: false,
  };

  const result = evaluateEdit(state, "impl");

  assertEquals(result, {
    decision: "allow",
    state: {
      lastRun: "green",
      testEditedSinceRun: false,
      implEditedSinceRun: true,
    },
  });
});

Deno.test("evaluateEdit allows impl edit after a test edit (RED phase, even on green)", () => {
  // Claude Code は Bash 非ゼロ終了時に PostToolUse を発火せず RED 実行を観測できないため、
  // テスト編集自体を RED シグナルとして扱い実装を許可する。最終グリーンは Stop ゲートで担保。
  const state: GuardState = {
    lastRun: "green",
    testEditedSinceRun: true,
    implEditedSinceRun: false,
  };

  const result = evaluateEdit(state, "impl");

  assertEquals(result, {
    decision: "allow",
    state: {
      lastRun: "green",
      testEditedSinceRun: true,
      implEditedSinceRun: true,
    },
  });
});

Deno.test("evaluateEdit allows impl edit after a test edit from a fresh state (RED phase)", () => {
  const state: GuardState = {
    lastRun: null,
    testEditedSinceRun: true,
    implEditedSinceRun: false,
  };

  const result = evaluateEdit(state, "impl");

  assertEquals(result, {
    decision: "allow",
    state: {
      lastRun: null,
      testEditedSinceRun: true,
      implEditedSinceRun: true,
    },
  });
});

Deno.test("applyTestRun records red and clears edit flags when tests fail", () => {
  const state: GuardState = {
    lastRun: "green",
    testEditedSinceRun: true,
    implEditedSinceRun: true,
  };

  assertEquals(applyTestRun(state, true), {
    lastRun: "red",
    testEditedSinceRun: false,
    implEditedSinceRun: false,
  });
});

Deno.test("applyTestRun records green and clears edit flags when tests pass", () => {
  const state: GuardState = {
    lastRun: "red",
    testEditedSinceRun: true,
    implEditedSinceRun: true,
  };

  assertEquals(applyTestRun(state, false), {
    lastRun: "green",
    testEditedSinceRun: false,
    implEditedSinceRun: false,
  });
});

Deno.test("evaluateStop passes when nothing was edited since last run", () => {
  const state: GuardState = {
    lastRun: "green",
    testEditedSinceRun: false,
    implEditedSinceRun: false,
  };

  assertEquals(evaluateStop(state), { block: false });
});

Deno.test("evaluateStop blocks when impl was edited after last test run", () => {
  const state: GuardState = {
    lastRun: "green",
    testEditedSinceRun: false,
    implEditedSinceRun: true,
  };

  assertEquals(evaluateStop(state), {
    block: true,
    reason: STOP_RERUN_TESTS,
  });
});

Deno.test("didTestsFail uses exit_code when present", () => {
  assertEquals(didTestsFail({ exit_code: 1, stdout: "", stderr: "" }), true);
  assertEquals(didTestsFail({ exit_code: 0, stdout: "", stderr: "" }), false);
});

Deno.test("didTestsFail uses is_error when exit_code is absent", () => {
  assertEquals(didTestsFail({ is_error: true, stdout: "", stderr: "" }), true);
  assertEquals(
    didTestsFail({ is_error: false, stdout: "", stderr: "" }),
    false,
  );
});

Deno.test("didTestsFail detects failure markers in runner output", () => {
  const failures = [
    "FAILED | 1 passed | 1 failed (2ms)", // deno
    "test result: FAILED. 1 passed; 1 failed;", // cargo
    "--- FAIL: TestParse (0.00s)\nFAIL", // go
    "1 failed, 2 passed in 0.12s", // pytest
    "Tests:  1 failed, 3 passed, 4 total", // jest/vitest
    "Success: 0 \nFailed : 5 \nErrors : 0", // plenary/busted (nvim)
    "Success: 40 \nFailed : 0 \nErrors : 2", // plenary エラーあり
  ];
  for (const out of failures) {
    assertEquals(didTestsFail({ stdout: out, stderr: "" }), true, out);
  }
});

Deno.test("didTestsFail returns false for passing runner output", () => {
  const passes = [
    "ok | 16 passed | 0 failed (9ms)", // deno
    "test result: ok. 5 passed; 0 failed;", // cargo
    "ok  \tgithub.com/foo/bar\t0.5s", // go
    "5 passed in 0.10s", // pytest
    "Test Files  2 passed (2)", // vitest
    "Success: 60 \nFailed : 0 \nErrors : 0", // plenary/busted 全パス
  ];
  for (const out of passes) {
    assertEquals(didTestsFail({ stdout: out, stderr: "" }), false, out);
  }
});

Deno.test("didTestsFail flags failing output even when the exit code is 0", () => {
  // exit 0 でも出力が失敗を示すランナー(0 終了する構成)を取りこぼさない。
  assertEquals(
    didTestsFail({ exit_code: 0, stdout: "Failed : 3 \nErrors : 0" }),
    true,
  );
  assertEquals(
    didTestsFail({ exit_code: 0, stdout: "Failed : 0 \nErrors : 0" }),
    false,
  );
});

Deno.test("evaluateStop blocks when a test was written but never run", () => {
  const state: GuardState = {
    lastRun: null,
    testEditedSinceRun: true,
    implEditedSinceRun: false,
  };

  assertEquals(evaluateStop(state), {
    block: true,
    reason: STOP_RUN_NEW_TEST,
  });
});

Deno.test("evaluateStopAttempt blocks dirty stop and keeps flags for the next attempt", () => {
  const state: GuardState = {
    lastRun: "green",
    testEditedSinceRun: false,
    implEditedSinceRun: true,
  };

  assertEquals(evaluateStopAttempt(state), {
    block: true,
    reason: STOP_RERUN_TESTS,
    state: {
      lastRun: "green",
      testEditedSinceRun: false,
      implEditedSinceRun: true,
      stopBlockCount: 1,
    },
  });
});

Deno.test("evaluateStopAttempt blocks a second dirty stop attempt", () => {
  const state: GuardState = {
    lastRun: "green",
    testEditedSinceRun: false,
    implEditedSinceRun: true,
    stopBlockCount: 1,
  };

  assertEquals(evaluateStopAttempt(state), {
    block: true,
    reason: STOP_RERUN_TESTS,
    state: {
      lastRun: "green",
      testEditedSinceRun: false,
      implEditedSinceRun: true,
      stopBlockCount: 2,
    },
  });
});

Deno.test("evaluateStopAttempt gives up after max blocks and clears flags", () => {
  const state: GuardState = {
    lastRun: "green",
    testEditedSinceRun: true,
    implEditedSinceRun: true,
    stopBlockCount: 2,
  };

  assertEquals(evaluateStopAttempt(state), {
    block: false,
    state: {
      lastRun: "green",
      testEditedSinceRun: false,
      implEditedSinceRun: false,
      stopBlockCount: 0,
    },
  });
});

Deno.test("evaluateStopAttempt passes clean stop and resets the block counter", () => {
  const state: GuardState = {
    lastRun: "green",
    testEditedSinceRun: false,
    implEditedSinceRun: false,
    stopBlockCount: 1,
  };

  assertEquals(evaluateStopAttempt(state), {
    block: false,
    state: {
      lastRun: "green",
      testEditedSinceRun: false,
      implEditedSinceRun: false,
      stopBlockCount: 0,
    },
  });
});

Deno.test("extractBashWriteTargets detects redirect, tee, and in-place edit targets", () => {
  const cases: [string, string[]][] = [
    ["cat > src/foo.ts", ["src/foo.ts"]],
    ["echo 'x' >> src/foo.ts", ["src/foo.ts"]],
    ["echo hi | tee src/foo.ts", ["src/foo.ts"]],
    ["echo hi | tee -a src/foo.ts", ["src/foo.ts"]],
    ["sed -i '' 's/a/b/' src/foo.ts", ["src/foo.ts"]],
    ["patch src/foo.rs < fix.patch", ["src/foo.rs"]],
    ["cargo test > result.log 2>&1", ["result.log"]],
  ];
  for (const [cmd, expected] of cases) {
    assertEquals(extractBashWriteTargets(cmd), expected, cmd);
  }
});

Deno.test("extractBashWriteTargets ignores quoted strings and non-write commands", () => {
  const cases = [
    'git commit -m "fix > src/foo.ts"',
    "ls -la",
    "deno test --allow-read",
    "rg 'pattern' src/",
  ];
  for (const cmd of cases) {
    assertEquals(extractBashWriteTargets(cmd), [], cmd);
  }
});

Deno.test("evaluateBashCommand denies bash writes to gated source files", () => {
  const cases = [
    "cat > src/foo.ts",
    "sed -i '' 's/a/b/' src/main.rs",
    "echo 'test' >> src/foo.test.ts",
  ];
  for (const cmd of cases) {
    const result = evaluateBashCommand(cmd);
    assertEquals(result.decision, "deny", cmd);
    assertEquals(result.reason?.startsWith(DENY_BASH_WRITE), true, cmd);
  }
});

Deno.test("evaluateBashCommand allows writes to exempt files and normal commands", () => {
  const cases = [
    "cargo test > result.log 2>&1",
    "echo 'note' >> README.md",
    "git commit -m 'update src/foo.ts'",
    "ls -la",
  ];
  for (const cmd of cases) {
    assertEquals(evaluateBashCommand(cmd), { decision: "allow" }, cmd);
  }
});

Deno.test("detectDelegatedTestResult returns green when report contains a green marker", () => {
  const text = "テストは全て green です。\nTDD_GUARD: green\n以上です。";

  assertEquals(detectDelegatedTestResult(text), "green");
});

Deno.test("detectDelegatedTestResult returns red when report contains a red marker", () => {
  const text = "1 件失敗しました。\nTDD_GUARD: red\n";

  assertEquals(detectDelegatedTestResult(text), "red");
});

Deno.test("detectDelegatedTestResult returns red when both markers are present (fail-safe)", () => {
  const text = "TDD_GUARD: green\nTDD_GUARD: red\n";

  assertEquals(detectDelegatedTestResult(text), "red");
});

Deno.test("detectDelegatedTestResult returns null when no marker is present", () => {
  const text = "テストを実行しました。5 passed, 0 failed。";

  assertEquals(detectDelegatedTestResult(text), null);
});

Deno.test("detectDelegatedTestResult detects markers regardless of case", () => {
  assertEquals(detectDelegatedTestResult("tdd_guard: GREEN"), "green");
  assertEquals(detectDelegatedTestResult("Tdd_Guard: Red"), "red");
});
