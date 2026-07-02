import { assertEquals } from "jsr:@std/assert";
import {
  applyTestRun,
  classifyFile,
  DENY_NO_RED,
  DENY_UNVERIFIED_TEST,
  detectTestCommand,
  didTestsFail,
  evaluateEdit,
  evaluateStop,
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
    "tests/helper.py",
    "pkg/parser_test.go",
    "spec/models/user_spec.rb",
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
    "app/models/user.rb",
    "cmd/server/handler.py",
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
    "styles/main.css",
    "index.html",
    ".env.example",
    "Makefile",
    "Dockerfile",
    "references/phase-pipeline.workflow.js",
  ];
  for (const path of cases) {
    assertEquals(classifyFile(path), "exempt", path);
  }
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

Deno.test("evaluateEdit denies impl edit when new test is written but not yet run red", () => {
  const state: GuardState = {
    lastRun: "green",
    testEditedSinceRun: true,
    implEditedSinceRun: false,
  };

  const result = evaluateEdit(state, "impl");

  assertEquals(result, {
    decision: "deny",
    reason: DENY_UNVERIFIED_TEST,
    state,
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
  assertEquals(didTestsFail({ is_error: false, stdout: "", stderr: "" }), false);
});

Deno.test("didTestsFail detects failure markers in runner output", () => {
  const failures = [
    "FAILED | 1 passed | 1 failed (2ms)", // deno
    "test result: FAILED. 1 passed; 1 failed;", // cargo
    "--- FAIL: TestParse (0.00s)\nFAIL", // go
    "1 failed, 2 passed in 0.12s", // pytest
    "Tests:  1 failed, 3 passed, 4 total", // jest/vitest
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
  ];
  for (const out of passes) {
    assertEquals(didTestsFail({ stdout: out, stderr: "" }), false, out);
  }
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
