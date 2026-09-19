import { assertEquals, assertRejects, assertThrows } from "jsr:@std/assert@1";
import { GENERATED_MARKER } from "./subagent-format.ts";
import { parseFormat, syncSubagents } from "./sync-subagents.ts";

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

Deno.test("syncSubagents_with_opencode_format_writes_the_markdown_without_a_name_key", async () => {
  await withTempDirs(async (src, out) => {
    await Deno.writeTextFile(`${src}/review-impl.md`, MARKDOWN);

    const result = await syncSubagents(src, out, "opencode");

    assertEquals(result, { written: ["review-impl.md"], pruned: [] });
    assertEquals(
      await Deno.readTextFile(`${out}/review-impl.md`),
      `---
${GENERATED_MARKER}
description: "実装差分の統合レビュワー。修正は行わない。"
mode: subagent
---

# review-impl

本文。
`,
    );
  });
});

Deno.test("syncSubagents_with_opencode_format_prunes_its_own_markdown_and_leaves_a_foreign_one", async () => {
  await withTempDirs(async (src, out) => {
    await Deno.mkdir(out, { recursive: true });
    await Deno.writeTextFile(
      `${out}/removed.md`,
      `---\n${GENERATED_MARKER}\ndescription: "d"\nmode: subagent\n---\n\nbody\n`,
    );
    const foreign = `---\ndescription: hand written\nmode: subagent\n---\n\nbody\n`;
    await Deno.writeTextFile(`${out}/kept.md`, foreign);

    const result = await syncSubagents(src, out, "opencode");

    assertEquals(result, { written: [], pruned: ["removed.md"] });
    assertEquals(await Deno.readTextFile(`${out}/kept.md`), foreign);
  });
});

Deno.test("syncSubagents_with_opencode_format_leaves_the_codex_toml_of_the_same_out_dir_alone", async () => {
  await withTempDirs(async (src, out) => {
    await Deno.mkdir(out, { recursive: true });
    const codexToml =
      `${GENERATED_MARKER}\nname = "stale"\ndescription = "d"\ndeveloper_instructions = '''\nbody\n'''\n`;
    await Deno.writeTextFile(`${out}/stale.toml`, codexToml);

    const result = await syncSubagents(src, out, "opencode");

    assertEquals(result, { written: [], pruned: [] });
    assertEquals(await Deno.readTextFile(`${out}/stale.toml`), codexToml);
  });
});

Deno.test("syncSubagents_writes_the_source_and_leaves_every_file_that_is_not_its_own", async () => {
  await withTempDirs(async (src, out) => {
    await Deno.writeTextFile(`${src}/review-impl.md`, MARKDOWN);
    await Deno.mkdir(out, { recursive: true });
    const foreignToml = "name = \"hand-written\"\n";
    await Deno.writeTextFile(`${out}/notes.toml`, foreignToml);
    await Deno.writeTextFile(`${out}/notes.txt`, "third party\n");
    await Deno.mkdir(`${out}/dir.toml`);

    const result = await syncSubagents(src, out);

    assertEquals(result, { written: ["review-impl.toml"], pruned: [] });
    assertEquals(await Deno.readTextFile(`${out}/notes.toml`), foreignToml);
    assertEquals(await Deno.readTextFile(`${out}/notes.txt`), "third party\n");
    assertEquals((await Deno.stat(`${out}/dir.toml`)).isDirectory, true);
  });
});

Deno.test("syncSubagents_names_the_output_after_the_frontmatter_name_not_the_source_file_name", async () => {
  await withTempDirs(async (src, out) => {
    // OpenCode は subagent 名をファイル名から決めるので、正本の name が出力名になることを固定する
    await Deno.writeTextFile(`${src}/source-file-name.md`, MARKDOWN);

    const result = await syncSubagents(src, out, "opencode");

    assertEquals(result, { written: ["review-impl.md"], pruned: [] });
    assertEquals((await Deno.stat(`${out}/review-impl.md`)).isFile, true);
  });
});

Deno.test("syncSubagents_without_a_frontmatter_name_throws_and_writes_nothing_in_both_formats", async () => {
  for (const format of ["codex", "opencode"] as const) {
    await withTempDirs(async (src, out) => {
      await Deno.writeTextFile(
        `${src}/nameless.md`,
        "---\ndescription: 名前の無い定義\n---\n\n本文。\n",
      );

      await assertRejects(
        () => syncSubagents(src, out, format),
        Error,
        "frontmatter に name がありません",
      );

      const written: string[] = [];
      for await (const entry of Deno.readDir(out)) written.push(entry.name);
      assertEquals(written, []);
    });
  }
});

Deno.test("syncSubagents_overwrites_a_hand_written_file_whose_name_collides_with_a_generated_one", async () => {
  await withTempDirs(async (src, out) => {
    // 出力先 (~/.config/opencode/agents) は人が手で agent を置ける場所なので、
    // 同名の手書きファイルが黙って置き換わることを仕様として固定する
    await Deno.writeTextFile(`${src}/review-impl.md`, MARKDOWN);
    await Deno.mkdir(out, { recursive: true });
    await Deno.writeTextFile(`${out}/review-impl.md`, "---\ndescription: 手書き\n---\n\n手書きの本文。\n");

    const result = await syncSubagents(src, out, "opencode");

    assertEquals(result, { written: ["review-impl.md"], pruned: [] });
    assertEquals(
      (await Deno.readTextFile(`${out}/review-impl.md`)).startsWith(`---\n${GENERATED_MARKER}`),
      true,
    );
  });
});

Deno.test("parseFormat_maps_an_omitted_argument_to_codex_and_rejects_an_unknown_one", () => {
  assertEquals(parseFormat(undefined), "codex");
  assertEquals(parseFormat("codex"), "codex");
  assertEquals(parseFormat("opencode"), "opencode");
  assertThrows(
    () => parseFormat("Opencode"),
    Error,
    "形式は codex か opencode です: Opencode",
  );
});
