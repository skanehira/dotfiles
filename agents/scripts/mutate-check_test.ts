import { assertEquals } from "jsr:@std/assert";
import { judgeMutationRun, runMutation } from "./mutate-check.ts";

// 変異検証は「テストが変異を殺せるか」を測る実験である。実験そのものが成立していない
// (変異が当たっていない / baseline が最初から赤い / 復元できていない) 場合に
// 「殺せた・殺せなかった」を結論してはいけない。ここではその判定を pin する。

Deno.test("judgeMutationRun_with_a_complete_run_reports_the_mutant_as_killed", () => {
  const result = judgeMutationRun({
    baselineExit: 0,
    fileChanged: true,
    mutatedExit: 1,
    restored: true,
    restoredExit: 0,
  });

  assertEquals(result, { verdict: "killed" });
});

Deno.test("judgeMutationRun_with_a_surviving_mutant_reports_survived", () => {
  const result = judgeMutationRun({
    baselineExit: 0,
    fileChanged: true,
    mutatedExit: 0,
    restored: true,
    restoredExit: 0,
  });

  assertEquals(result, { verdict: "survived" });
});

// --- 実験が成立していないケース。いずれも killed / survived と結論してはいけない ---

Deno.test("judgeMutationRun_with_an_unapplied_mutation_reports_invalid_not_survived", () => {
  // 置換対象が見つからず変異が当たっていない。テストが緑でも「殺せなかった」ではない
  const result = judgeMutationRun({
    baselineExit: 0,
    fileChanged: false,
    mutatedExit: 0,
    restored: true,
    restoredExit: 0,
  });

  assertEquals(result, {
    verdict: "invalid",
    reason: "変異がファイルに適用されていない (置換対象が見つからなかった可能性)。実験は成立していない",
  });
});

Deno.test("judgeMutationRun_with_a_red_baseline_reports_invalid", () => {
  // 変異前から落ちている。変異で落ちたのか元から落ちていたのか区別できない
  const result = judgeMutationRun({
    baselineExit: 1,
    fileChanged: true,
    mutatedExit: 1,
    restored: true,
    restoredExit: 1,
  });

  assertEquals(result, {
    verdict: "invalid",
    reason: "変異前のテストが緑ではない。変異が原因で落ちたのか判別できない",
  });
});

Deno.test("judgeMutationRun_with_a_failed_restore_reports_invalid", () => {
  const result = judgeMutationRun({
    baselineExit: 0,
    fileChanged: true,
    mutatedExit: 1,
    restored: false,
    restoredExit: 0,
  });

  assertEquals(result, {
    verdict: "invalid",
    reason: "変異を戻せていない (バイト一致しない)。変異体がリポジトリに残っている",
  });
});

Deno.test("judgeMutationRun_with_a_red_result_after_restore_reports_invalid", () => {
  // バイト一致で戻したのに緑にならない = 別の要因が混ざっている
  const result = judgeMutationRun({
    baselineExit: 0,
    fileChanged: true,
    mutatedExit: 1,
    restored: true,
    restoredExit: 1,
  });

  assertEquals(result, {
    verdict: "invalid",
    reason: "復元後のテストが緑に戻らない。実験の前後で別の要因が変化している",
  });
});

Deno.test("judgeMutationRun reports the first broken precondition when several are broken", () => {
  // baseline が赤く、かつ変異も当たっていない。最初に壊れた前提を報告する
  const result = judgeMutationRun({
    baselineExit: 1,
    fileChanged: false,
    mutatedExit: 0,
    restored: true,
    restoredExit: 1,
  });

  assertEquals(result, {
    verdict: "invalid",
    reason: "変異前のテストが緑ではない。変異が原因で落ちたのか判別できない",
  });
});

// --- 変異は作業ツリーの複製の中で行う。並列に動く他のレビュワーが、変異中のコードを読まないため ---

Deno.test("runMutation_runs_the_tests_in_a_clone_and_never_touches_the_working_tree", async () => {
  const root = await Deno.makeTempDir();
  const log = `${root}.log`;
  try {
    await Deno.writeTextFile(`${root}/a.txt`, "hello\n");
    // テストのコマンドは、実行のたびに作業ツリーの原本を記録し、cwd のファイルを検査する
    const testCmd = ["sh", "-c", `cat '${root}/a.txt' >> '${log}'; grep -q hello a.txt`];

    const run = await runMutation({ root, file: "a.txt", oldStr: "hello", newStr: "bye", testCmd });

    assertEquals(judgeMutationRun(run), { verdict: "killed" });
    assertEquals(await Deno.readTextFile(log), "hello\nhello\nhello\n");
    assertEquals(await Deno.readTextFile(`${root}/a.txt`), "hello\n");
  } finally {
    await Deno.remove(root, { recursive: true });
    await Deno.remove(log).catch(() => {});
  }
});

Deno.test("runMutation_with_a_surviving_mutant_reports_survived_from_the_clone", async () => {
  const root = await Deno.makeTempDir();
  try {
    await Deno.writeTextFile(`${root}/a.txt`, "hello\n");
    const run = await runMutation({ root, file: "a.txt", oldStr: "hello", newStr: "bye", testCmd: ["true"] });

    assertEquals(judgeMutationRun(run), { verdict: "survived" });
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});

Deno.test("runMutation_accepts_an_absolute_file_path_inside_the_root", async () => {
  const root = await Deno.makeTempDir();
  try {
    await Deno.writeTextFile(`${root}/a.txt`, "hello\n");
    const testCmd = ["sh", "-c", "grep -q hello a.txt"];

    const run = await runMutation({ root, file: `${root}/a.txt`, oldStr: "hello", newStr: "bye", testCmd });

    assertEquals(judgeMutationRun(run), { verdict: "killed" });
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});

// CLI の失敗は survived (exit 1) と区別できる invalid (exit 2) で返す。survived と読まれると空虚テストの誤検出になる
async function runCli(args: string[], cwd: string): Promise<number> {
  const script = new URL("./mutate-check.ts", import.meta.url).pathname;
  const { code } = await new Deno.Command(Deno.execPath(), {
    args: ["run", "--allow-read", "--allow-write", "--allow-run", script, ...args],
    cwd,
    stdout: "null",
    stderr: "null",
  }).output();
  return code;
}

Deno.test("cli_with_a_missing_file_exits_2_not_1", async () => {
  const root = await Deno.makeTempDir();
  try {
    assertEquals(await runCli(["--root", root, "missing.txt", "a", "b", "--", "true"], root), 2);
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});

Deno.test("cli_with_a_file_outside_the_root_exits_2", async () => {
  const root = await Deno.makeTempDir();
  const other = await Deno.makeTempDir();
  try {
    await Deno.writeTextFile(`${other}/a.txt`, "hello\n");
    assertEquals(await runCli(["--root", root, `${other}/a.txt`, "hello", "bye", "--", "true"], root), 2);
  } finally {
    await Deno.remove(root, { recursive: true });
    await Deno.remove(other, { recursive: true });
  }
});

Deno.test("cli_with_root_option_mutates_inside_a_clone_of_that_root", async () => {
  const root = await Deno.makeTempDir();
  const cwd = await Deno.makeTempDir();
  try {
    await Deno.writeTextFile(`${root}/a.txt`, "hello\n");
    assertEquals(await runCli(["--root", root, "a.txt", "hello", "bye", "--", "sh", "-c", "grep -q hello a.txt"], cwd), 0);
    assertEquals(await Deno.readTextFile(`${root}/a.txt`), "hello\n");
  } finally {
    await Deno.remove(root, { recursive: true });
    await Deno.remove(cwd, { recursive: true });
  }
});

Deno.test("runMutation_inserts_the_replacement_literally_without_expanding_dollar_patterns", async () => {
  const root = await Deno.makeTempDir();
  try {
    await Deno.writeTextFile(`${root}/a.txt`, "price\n");
    // 置換後に "$&" がそのまま入れば grep が見つける。$& が展開されると "price" に戻り、変異が当たらない
    const testCmd = ["sh", "-c", "! grep -qF '$&' a.txt"];

    const run = await runMutation({ root, file: "a.txt", oldStr: "price", newStr: "$&", testCmd });

    assertEquals(judgeMutationRun(run), { verdict: "killed" });
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});
