#!/usr/bin/env -S deno run --allow-read --allow-write --allow-run

/**
 * 変異検証の実験ハーネス。
 *
 * 「テストが変異を殺せるか」を測る実験は、手で組むと**実験そのものが成立していないのに
 * 結論を出す**事故が起きる。実際に踏んだもの:
 *
 * - 置換対象が見つからず変異が当たっていないのに「テストが緑 = 殺せなかった」と結論した
 * - 変異前から赤いのに「変異で落ちた」と結論した
 * - 変異を戻し忘れて変異体をリポジトリに残した
 *
 * どれも「検出できないこと」と「異常が無いこと」を区別していない。本スクリプトは
 * baseline / 適用確認 / 復元確認の 3 つの対照を必ず取り、1 つでも崩れたら
 * killed / survived ではなく **invalid (実験が成立していない)** を返す。
 *
 * 使い方:
 *   mutate-check.ts <file> <old> <new> -- <test command...>
 * 例:
 *   mutate-check.ts src/limit.ts 'slice(0, Math.max(0, n))' 'slice(0, n)' -- deno test src/limit_test.ts
 */

export type MutationRun = {
  /** 変異前のテストの exit code */
  baselineExit: number;
  /** 変異がファイルに実際に適用されたか */
  fileChanged: boolean;
  /** 変異後のテストの exit code */
  mutatedExit: number;
  /** 復元後の内容が元とバイト一致したか */
  restored: boolean;
  /** 復元後のテストの exit code */
  restoredExit: number;
};

export type MutationVerdict =
  | { verdict: "killed" }
  | { verdict: "survived" }
  | { verdict: "invalid"; reason: string };

/** 前提が 1 つでも崩れていれば killed / survived と結論しない。判定順は実験の時系列に従う。 */
export function judgeMutationRun(run: MutationRun): MutationVerdict {
  if (run.baselineExit !== 0) {
    return {
      verdict: "invalid",
      reason: "変異前のテストが緑ではない。変異が原因で落ちたのか判別できない",
    };
  }
  if (!run.fileChanged) {
    return {
      verdict: "invalid",
      reason: "変異がファイルに適用されていない (置換対象が見つからなかった可能性)。実験は成立していない",
    };
  }
  if (!run.restored) {
    return {
      verdict: "invalid",
      reason: "変異を戻せていない (バイト一致しない)。変異体がリポジトリに残っている",
    };
  }
  if (run.restoredExit !== 0) {
    return {
      verdict: "invalid",
      reason: "復元後のテストが緑に戻らない。実験の前後で別の要因が変化している",
    };
  }
  return { verdict: run.mutatedExit !== 0 ? "killed" : "survived" };
}

// ---- 以下 CLI ----

async function runCommand(cmd: string[]): Promise<number> {
  const p = new Deno.Command(cmd[0], {
    args: cmd.slice(1),
    stdout: "null",
    stderr: "null",
  }).spawn();
  return (await p.status).code;
}

async function main() {
  const argv = Deno.args;
  const sep = argv.indexOf("--");
  if (sep === -1 || sep < 3) {
    console.error("usage: mutate-check.ts <file> <old> <new> -- <test command...>");
    Deno.exit(64);
  }
  const [file, oldStr, newStr] = argv.slice(0, 3);
  const testCmd = argv.slice(sep + 1);

  const original = await Deno.readTextFile(file);
  const baselineExit = await runCommand(testCmd);

  const mutated = original.replace(oldStr, newStr);
  const fileChanged = mutated !== original;
  let mutatedExit = -1;
  if (fileChanged) {
    await Deno.writeTextFile(file, mutated);
    mutatedExit = await runCommand(testCmd);
  }

  await Deno.writeTextFile(file, original);
  const restored = (await Deno.readTextFile(file)) === original;
  const restoredExit = await runCommand(testCmd);

  const result = judgeMutationRun({
    baselineExit,
    fileChanged,
    mutatedExit,
    restored,
    restoredExit,
  });

  console.log(JSON.stringify({
    file,
    baselineExit,
    fileChanged,
    mutatedExit,
    restored,
    restoredExit,
    ...result,
  }));

  // killed 以外はすべて非ゼロ。survived (テストが弱い) と invalid (実験が壊れている) を
  // 呼び出し側が区別できるよう別のコードにする
  Deno.exit(result.verdict === "killed" ? 0 : result.verdict === "survived" ? 1 : 2);
}

if (import.meta.main) {
  await main();
}
