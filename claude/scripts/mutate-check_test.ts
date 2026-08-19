import { assertEquals } from "jsr:@std/assert";
import { judgeMutationRun } from "./mutate-check.ts";

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
