import { assertEquals } from "jsr:@std/assert@1";
import { GENERATED_MARKER } from "./subagent-format.ts";
import { syncSubagents } from "./sync-subagents.ts";

const MARKDOWN = `---
name: review-impl
description: 実装差分の統合レビュワー。修正は行わない。
tools: Read, Grep, Glob, Bash, Write
model: opus
---

# review-impl

本文。
`;

/** src / out の一時ディレクトリを作り、テスト終了時に必ず片付ける */
async function withTempDirs(fn: (src: string, out: string) => Promise<void>) {
  const base = await Deno.makeTempDir();
  const src = `${base}/subagents`;
  const out = `${base}/agents`;
  await Deno.mkdir(src, { recursive: true });
  try {
    await fn(src, out);
  } finally {
    await Deno.remove(base, { recursive: true });
  }
}

Deno.test("syncSubagents_with_one_markdown_writes_the_codex_toml_into_a_missing_out_dir", async () => {
  await withTempDirs(async (src, out) => {
    await Deno.writeTextFile(`${src}/review-impl.md`, MARKDOWN);

    const result = await syncSubagents(src, out);

    assertEquals(result, { written: ["review-impl.toml"], pruned: [] });
    assertEquals(
      await Deno.readTextFile(`${out}/review-impl.toml`),
      `${GENERATED_MARKER}
name = "review-impl"
description = "実装差分の統合レビュワー。修正は行わない。"
developer_instructions = '''
# review-impl

本文。
'''
`,
    );
  });
});

Deno.test("syncSubagents_prunes_a_generated_toml_whose_markdown_is_gone", async () => {
  await withTempDirs(async (src, out) => {
    await Deno.mkdir(out, { recursive: true });
    await Deno.writeTextFile(
      `${out}/removed.toml`,
      `${GENERATED_MARKER}\nname = "removed"\ndescription = "d"\ndeveloper_instructions = '''\nbody\n'''\n`,
    );

    const result = await syncSubagents(src, out);

    assertEquals(result, { written: [], pruned: ["removed.toml"] });
    let files: string[] = [];
    for await (const entry of Deno.readDir(out)) files.push(entry.name);
    assertEquals(files, []);
  });
});

Deno.test("syncSubagents_leaves_a_toml_without_the_generated_marker_in_place", async () => {
  await withTempDirs(async (src, out) => {
    await Deno.mkdir(out, { recursive: true });
    const foreign = "name = \"hand-written\"\n";
    await Deno.writeTextFile(`${out}/notes.toml`, foreign);

    const result = await syncSubagents(src, out);

    assertEquals(result, { written: [], pruned: [] });
    assertEquals(await Deno.readTextFile(`${out}/notes.toml`), foreign);
  });
});
