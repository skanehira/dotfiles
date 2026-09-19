/**
 * `agents/subagents/*.md` (Claude Code 形式) を `~/.codex/agents/*.toml` へ同期する。
 *
 * subagent だけは symlink で共有できない (Codex は TOML を要求し、Markdown +
 * frontmatter を読めない)。書式変換は subagent-format.ts が持ち、このファイルは
 * ディレクトリの走査と prune だけを担う。
 *
 * prune は出力先で GENERATED_MARKER を持つファイルに限る。他ツールが置いた
 * `.toml` を巻き込まないため。
 */

import { GENERATED_MARKER, parseSubagent, toCodexToml } from "./subagent-format.ts";

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

export async function syncSubagents(srcDir: string, outDir: string): Promise<SyncResult> {
  await Deno.mkdir(outDir, { recursive: true });

  const sources = await listNames(srcDir, ".md");
  const sourceNames = new Set<string>();
  const written: string[] = [];

  for (const source of sources.sort()) {
    const markdown = await Deno.readTextFile(`${srcDir}/${source}`);
    const subagent = parseSubagent(markdown);
    const outName = `${subagent.frontmatter.name}.toml`;
    await Deno.writeTextFile(`${outDir}/${outName}`, toCodexToml(subagent));
    sourceNames.add(outName);
    written.push(outName);
  }

  const pruned: string[] = [];
  for (const existing of await listNames(outDir, ".toml")) {
    if (sourceNames.has(existing)) continue;
    const content = await Deno.readTextFile(`${outDir}/${existing}`);
    if (!content.startsWith(GENERATED_MARKER)) continue;
    await Deno.remove(`${outDir}/${existing}`);
    pruned.push(existing);
  }

  return { written: written.sort(), pruned: pruned.sort() };
}

if (import.meta.main) {
  const [srcDir, outDir] = Deno.args;
  if (!srcDir || !outDir) {
    console.error("使い方: sync-subagents.ts <subagents のディレクトリ> <出力先>");
    Deno.exit(1);
  }
  const result = await syncSubagents(srcDir, outDir);
  console.log(`written: ${result.written.length} / pruned: ${result.pruned.length}`);
  for (const name of result.written) console.log(`  + ${name}`);
  for (const name of result.pruned) console.log(`  - ${name}`);
}
