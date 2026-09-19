#!/usr/bin/env -S deno run --allow-read --allow-write
/**
 * `agents/subagents/*.md` (Claude Code 形式) を Codex の `~/.codex/agents/*.toml` か
 * OpenCode の `~/.config/opencode/agents/*.md` へ同期する。
 *
 * subagent だけは symlink で共有できない (Codex は TOML を要求し、OpenCode は
 * `description` / `mode` の別スキーマを要求するため、どちらも正本の Markdown +
 * frontmatter をそのまま読めない)。書式変換は subagent-format.ts が持ち、このファイルは
 * ディレクトリの走査と prune だけを担う。
 *
 * prune は出力先で GENERATED_MARKER を持つファイルに限る。他ツールが置いたファイルを
 * 巻き込まないため。
 */

import {
  GENERATED_MARKER,
  parseSubagent,
  type Subagent,
  subagentName,
  toCodexToml,
  toOpencodeMarkdown,
} from "./subagent-format.ts";

export type Format = "codex" | "opencode";

/** 形式ごとの拡張子・変換・prune 判定。prune の接頭辞は生成物の先頭と一致させる */
const FORMATS: Record<Format, {
  suffix: string;
  render: (subagent: Subagent) => string;
  generatedPrefix: string;
}> = {
  codex: {
    suffix: ".toml",
    render: toCodexToml,
    generatedPrefix: GENERATED_MARKER,
  },
  opencode: {
    // OpenCode は subagent 名をファイル名から決めるので、正本の name をファイル名にする
    suffix: ".md",
    render: toOpencodeMarkdown,
    generatedPrefix: `---\n${GENERATED_MARKER}`,
  },
};

export type SyncResult = {
  /** 出力先からの相対パス。ソート済み */
  written: string[];
  /** 撤去した出力先からの相対パス。ソート済み */
  pruned: string[];
};

async function listNames(dir: string, suffix: string): Promise<string[]> {
  const names: string[] = [];
  for await (const entry of Deno.readDir(dir)) {
    if (entry.isFile && entry.name.endsWith(suffix)) names.push(entry.name);
  }
  return names;
}

export async function syncSubagents(
  srcDir: string,
  outDir: string,
  format: Format = "codex",
): Promise<SyncResult> {
  const spec = FORMATS[format];
  await Deno.mkdir(outDir, { recursive: true });

  // 全件を先に変換してから書く。1 件でも壊れていたら 1 ファイルも書かずに投げる
  // (途中まで書いた状態で止まると、生成物と前回の残りが混ざった出力先になる)
  const outputs: { name: string; content: string }[] = [];
  for (const source of (await listNames(srcDir, ".md")).sort()) {
    const markdown = await Deno.readTextFile(`${srcDir}/${source}`);
    const subagent = parseSubagent(markdown);
    outputs.push({
      name: `${subagentName(subagent)}${spec.suffix}`,
      content: spec.render(subagent),
    });
  }

  const sourceNames = new Set<string>();
  const written: string[] = [];
  for (const output of outputs) {
    await Deno.writeTextFile(`${outDir}/${output.name}`, output.content);
    sourceNames.add(output.name);
    written.push(output.name);
  }

  const pruned: string[] = [];
  for (const existing of await listNames(outDir, spec.suffix)) {
    if (sourceNames.has(existing)) continue;
    const content = await Deno.readTextFile(`${outDir}/${existing}`);
    if (!content.startsWith(spec.generatedPrefix)) continue;
    await Deno.remove(`${outDir}/${existing}`);
    pruned.push(existing);
  }

  return { written: written.sort(), pruned: pruned.sort() };
}

/** CLI の第 3 引数を形式に解釈する。省略時は codex (codex.nix が引数を省いて呼ぶ) */
export function parseFormat(value: string | undefined): Format {
  if (value === undefined) return "codex";
  if (value === "codex" || value === "opencode") return value;
  throw new Error(`形式は codex か opencode です: ${value}`);
}

if (import.meta.main) {
  const [srcDir, outDir, format] = Deno.args;
  if (!srcDir || !outDir) {
    console.error(
      "使い方: sync-subagents.ts <subagents のディレクトリ> <出力先> [codex|opencode]",
    );
    Deno.exit(1);
  }
  const result = await syncSubagents(srcDir, outDir, parseFormat(format));
  console.log(`written: ${result.written.length} / pruned: ${result.pruned.length}`);
  for (const name of result.written) console.log(`  + ${name}`);
  for (const name of result.pruned) console.log(`  - ${name}`);
}
