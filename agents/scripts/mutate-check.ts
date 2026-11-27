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
 * 変異とテストの実行は、作業ツリーの根 (`--root`。省くとカレントディレクトリ) の複製の中で行う。原本は書き換えない。
 * テストのコマンドは複製の根で実行するので、コマンドの中のパスは根からの相対で書き、原本のパスや `cd` を使わない。
 * 原本を指すと、変異していないコードをテストして survived と誤って結論する。複製の `.git` は原本と同じ git の状態を
 * 指すので、git の状態を書き換えるテストのコマンドには使わない。
 *
 * 使い方:
 *   mutate-check.ts [--root <dir>] <file> <old> <new> -- <test command...>
 * 例:
 *   mutate-check.ts src/limit.ts 'slice(0, Math.max(0, n))' 'slice(0, n)' -- deno test src/limit_test.ts
 */

import { isAbsolute, join, relative } from "node:path";

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

export type MutationInput = {
  /** 作業ツリーの根。`file` はここからの相対パス */
  root: string;
  file: string;
  oldStr: string;
  newStr: string;
  testCmd: string[];
};

async function runCommand(cmd: string[], cwd: string): Promise<number> {
  const p = new Deno.Command(cmd[0], {
    args: cmd.slice(1),
    cwd,
    stdout: "null",
    stderr: "null",
  }).spawn();
  return (await p.status).code;
}

/** 作業ツリーを丸ごと複製する。copy-on-write の複製を先に試し、使えないファイルシステムでは通常の複製にする */
async function cloneTree(src: string, dest: string): Promise<void> {
  const attempts = Deno.build.os === "darwin" ? [["-cR"], ["-R"]] : [["-a", "--reflink=auto"], ["-a"]];
  for (const flags of attempts) {
    const { code } = await new Deno.Command("cp", {
      args: [...flags, src, dest],
      stdout: "null",
      stderr: "null",
    }).output();
    if (code === 0) return;
    await Deno.remove(dest, { recursive: true }).catch(() => {});
  }
  throw new Error(`作業ツリーを複製できない: ${src}`);
}

/**
 * 作業ツリーの複製の中で変異させ、テストも複製の中で実行する。作業ツリーの原本は書き換えないので、
 * 同じ作業ツリーで並列に動く他のレビュワーが変異中のコードを読むことはない。
 */
export async function runMutation(input: MutationInput): Promise<MutationRun> {
  const workDir = await Deno.makeTempDir({ prefix: "mutate-check-" });
  const clone = `${workDir}/tree`;
  try {
    const rel = relative(input.root, isAbsolute(input.file) ? input.file : join(input.root, input.file));
    if (rel.startsWith("..") || isAbsolute(rel)) {
      throw new Error(`変異させるファイルが根の外にある: ${input.file} (根: ${input.root})`);
    }
    await cloneTree(input.root, clone);
    const target = join(clone, rel);
    const original = await Deno.readTextFile(target);
    const baselineExit = await runCommand(input.testCmd, clone);

    const mutated = original.replace(input.oldStr, () => input.newStr);
    const fileChanged = mutated !== original;
    let mutatedExit = -1;
    if (fileChanged) {
      await Deno.writeTextFile(target, mutated);
      mutatedExit = await runCommand(input.testCmd, clone);
    }

    await Deno.writeTextFile(target, original);
    const restored = (await Deno.readTextFile(target)) === original;
    const restoredExit = await runCommand(input.testCmd, clone);

    return { baselineExit, fileChanged, mutatedExit, restored, restoredExit };
  } finally {
    await Deno.remove(workDir, { recursive: true }).catch(() => {});
  }
}

async function main() {
  let argv = Deno.args;
  let root = Deno.cwd();
  if (argv[0] === "--root") {
    root = argv[1];
    argv = argv.slice(2);
  }
  const sep = argv.indexOf("--");
  if (sep === -1 || sep < 3 || root === undefined) {
    console.error("usage: mutate-check.ts [--root <dir>] <file> <old> <new> -- <test command...>");
    Deno.exit(64);
  }
  const [file, oldStr, newStr] = argv.slice(0, 3);
  const testCmd = argv.slice(sep + 1);

  let run: MutationRun;
  try {
    run = await runMutation({ root, file, oldStr, newStr, testCmd });
  } catch (e) {
    // 実験そのものが成立していない。survived (exit 1) と区別するため invalid (exit 2) で返す
    console.error(e instanceof Error ? e.message : String(e));
    console.log(JSON.stringify({ file, verdict: "invalid", reason: "実行できなかった" }));
    Deno.exit(2);
  }
  const result = judgeMutationRun(run);

  console.log(JSON.stringify({ file, ...run, ...result }));

  // killed 以外はすべて非ゼロ。survived (テストが弱い) と invalid (実験が壊れている) を
  // 呼び出し側が区別できるよう別のコードにする
  Deno.exit(result.verdict === "killed" ? 0 : result.verdict === "survived" ? 1 : 2);
}

if (import.meta.main) {
  await main();
}
