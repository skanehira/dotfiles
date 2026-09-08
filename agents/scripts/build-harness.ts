/**
 * ハーネス正本 (agents/) をランタイムごとの完成品へコンパイルする。
 *
 * 共通の base に対して (1) ランタイム別 overlay の節マージ (2) 語彙のプレースホルダ置換
 * を順に当て、Claude Code / Codex / OpenCode がそれぞれ自分の語彙で書かれた 1 セットを
 * 読めるようにする。読み替え規約という間接層を無くすのが目的。
 *
 * 順序はマージ → 置換で固定する。見出しにツール名を含むファイルがあるため、逆順だと
 * overlay の見出しキーをランタイム語彙で書く必要が生じ、キーがランタイムごとに変わる。
 *
 * 現時点では純粋関数だけのライブラリで、CLI と配布への接続は配布切り替えのフェーズで足す。
 */

import { basename, dirname, join, relative, resolve } from "jsr:@std/path@1";
import { walk } from "jsr:@std/fs@1/walk";
import { parseSubagent, toCodexToml, toOpencodeMarkdown } from "./subagent-format.ts";

/** 語彙表。`{{@<name>}}` → ランタイム別の実語。vocabulary.json の形と一致させる */
export type Vocabulary = Record<string, Record<string, string>>;

/**
 * プレースホルダの区切り。素の `{{...}}` は既存文書と衝突するので `@` を付ける
 * (untrusted-input.md の `{{transcript}}`、dgx-spark.md の Docker `{{.Repository}}` 等)。
 */
function placeholderPattern(): RegExp {
  return /\{\{@([a-z][a-z0-9-]*)\}\}/g;
}

/**
 * プレースホルダをランタイムの語彙に展開する。
 *
 * frontmatter もコードフェンスも区別しない。`{{@name}}` は書き手が明示的に置いた印なので、
 * どこにあっても展開する。frontmatter の `allowed-tools: Agent, Skill` のような裸のツール名は
 * そもそもプレースホルダではないため触れられない。
 */
export function substitute(
  text: string,
  vocabulary: Vocabulary,
  runtime: string,
): string {
  return text.replace(placeholderPattern(), (_whole, name: string) => {
    const entry = vocabulary[name];
    if (!entry) throw new Error(`語彙表に {{@${name}}} がありません`);
    const value = entry[runtime];
    if (value === undefined) {
      throw new Error(`{{@${name}}} に ${runtime} の値がありません`);
    }
    return value;
  });
}

type Heading = { line: number; level: number; text: string };

/**
 * H2〜H6 の見出し行を拾う。frontmatter とコードフェンスの中は見出しにしない。
 *
 * スキルには文書テンプレートを載せたコードブロックが多く、その中に `##` で始まる行がある
 * (usecase-template.md に 22 行など)。素朴な行頭マッチでは節を切れない。
 */
function scanHeadings(lines: string[]): Heading[] {
  const headings: Heading[] = [];
  let fence: string | null = null;
  let inFrontmatter = false;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (i === 0 && line.trim() === "---") {
      inFrontmatter = true;
      continue;
    }
    if (inFrontmatter) {
      if (line.trim() === "---") inFrontmatter = false;
      continue;
    }

    const opener = line.trimStart().match(/^(`{3,}|~{3,})/);
    if (opener) {
      const marker = opener[1];
      if (fence === null) fence = marker;
      // 閉じるのは同種でかつ開始と同じ長さ以上のときだけ (```` の中の ``` は閉じない)
      else if (marker[0] === fence[0] && marker.length >= fence.length) fence = null;
      continue;
    }
    if (fence !== null) continue;

    const heading = line.trimStart().match(/^(#{2,6})\s+\S/);
    if (heading) {
      headings.push({ line: i, level: heading[1].length, text: line.trimEnd() });
    }
  }
  return headings;
}

/** 見出し k の節の終わり (次の同レベル以上の見出しの行、無ければ末尾) */
function sectionEnd(headings: Heading[], k: number, total: number): number {
  for (let j = k + 1; j < headings.length; j++) {
    if (headings[j].level <= headings[k].level) return headings[j].line;
  }
  return total;
}

/** overlay の最上位の節だけを取る (親を差し替えるとき子を二重に当てないため) */
function topLevelSections(
  lines: string[],
  headings: Heading[],
): Array<{ text: string; start: number; end: number }> {
  const sections = [];
  let k = 0;
  while (k < headings.length) {
    const end = sectionEnd(headings, k, lines.length);
    sections.push({ text: headings[k].text, start: headings[k].line, end });
    let next = k + 1;
    while (next < headings.length && headings[next].line < end) next++;
    k = next;
  }
  return sections;
}

/**
 * overlay の見出しと一致する base の節を、配下ごと差し替える。
 *
 * - 差し替え単位は「任意レベルの見出し 1 本 + その配下 (次の同レベル以上の見出しまで)」。
 *   H2 粒度に固定すると、ui-sketch.md のように 1 つの H2 が全体の 8 割を占めるファイルで
 *   差し替えが実質全文コピーになる
 * - 見出しを持たない overlay は全文差し替え (investigation.md は H1 + 箇条書きで H2 が無い)
 * - base に無い見出しは末尾へ追加する。削除はしない
 */
export function mergeSections(base: string, overlay: string): string {
  if (overlay.trim() === "") return base;

  const baseLines = base.split("\n");
  const baseHeadings = scanHeadings(baseLines);

  // マージキーの前提。実測では 106 ファイルすべてで重複 0 件だが、崩れたら黙って
  // 片方だけ差し替わるので例外にする。
  const seen = new Map<string, number>();
  for (const h of baseHeadings) seen.set(h.text, (seen.get(h.text) ?? 0) + 1);
  for (const h of baseHeadings) {
    const count = seen.get(h.text)!;
    if (count > 1) {
      throw new Error(`base に見出し '${h.text}' が ${count} 回現れます`);
    }
  }

  const overlayLines = overlay.split("\n");
  const overlayHeadings = scanHeadings(overlayLines);
  if (overlayHeadings.length === 0) return overlay;

  // 最初の見出しより前の本文はマージキーを持たず、黙って捨てられてしまう。
  // overlay を書く側が気づけないので例外にする。
  const preamble = overlayLines.slice(0, overlayHeadings[0].line);
  if (preamble.some((line) => line.trim() !== "")) {
    throw new Error(
      `overlay の最初の見出しより前に本文があります: ${preamble.find((l) => l.trim() !== "")}`,
    );
  }

  const byText = new Map(baseHeadings.map((h, k) => [h.text, k]));
  const replacements: Array<{ start: number; end: number; lines: string[] }> = [];
  const appended: string[] = [];

  for (const section of topLevelSections(overlayLines, overlayHeadings)) {
    const body = overlayLines.slice(section.start, section.end);
    const k = byText.get(section.text);
    if (k === undefined) {
      appended.push(...body);
      continue;
    }
    replacements.push({
      start: baseHeadings[k].line,
      end: sectionEnd(baseHeadings, k, baseLines.length),
      lines: body,
    });
  }

  const merged = [...baseLines];
  for (const r of replacements.sort((a, b) => b.start - a.start)) {
    merged.splice(r.start, r.end - r.start, ...r.lines);
  }
  if (appended.length > 0) {
    if (merged.length > 0 && merged[merged.length - 1].trim() !== "") merged.push("");
    merged.push(...appended);
  }
  return merged.join("\n");
}

/** 実在する祖先まで遡って realpath で解決し、残りのセグメントを繋ぎ直す */
function resolveIntendedPath(path: string): string {
  const absolute = resolve(path);
  const pending: string[] = [];
  let current = absolute;
  for (;;) {
    try {
      const real = Deno.realPathSync(current);
      return pending.length > 0 ? join(real, ...pending.reverse()) : real;
    } catch {
      const parent = dirname(current);
      if (parent === current) return absolute;
      pending.push(basename(current));
      current = parent;
    }
  }
}

/**
 * 出力先が正本を壊さないことを確かめる。
 *
 * Home Manager の activation は `linkAgentSkills` (旧 symlink を張る) が
 * `linkGeneration` (旧 symlink を撤去する) より先に走るため、素直に書くと生成器が
 * 旧 symlink 越しに agents/ 自身へ書き込んで正本を破壊する。
 * 中間に link farm が 1 段挟まるので、素のパス比較では検出できず realpath で解決する。
 */
export function assertSafeOutRoot(outRoot: string, dotfilesRoot: string): void {
  try {
    if (Deno.lstatSync(outRoot).isSymlink) {
      throw new Error(`出力先が symlink です: ${outRoot}`);
    }
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }

  const target = resolveIntendedPath(outRoot);
  const root = resolveIntendedPath(dotfilesRoot);
  if (target === root || target.startsWith(`${root}/`)) {
    throw new Error(`出力先が正本の中を指しています: ${outRoot} → ${target}`);
  }
}

/** 生成物の台帳。prune はここに載っているものだけを対象にする */
export const MANIFEST_NAME = ".harness-manifest.json";

const GENERATOR = "agents/scripts/build-harness.ts";

/** 前回の台帳にあって今回書かれなかったものが撤去対象 */
export function planPrune(previous: string[], current: string[]): string[] {
  const now = new Set(current);
  return previous.filter((p) => !now.has(p)).sort();
}

async function readManifest(outDir: string): Promise<string[]> {
  try {
    const parsed = JSON.parse(await Deno.readTextFile(join(outDir, MANIFEST_NAME)));
    return Array.isArray(parsed?.paths) ? parsed.paths : [];
  } catch {
    return [];
  }
}

export type BuildOptions = {
  baseDir: string;
  overlayDir: string;
  outDir: string;
  runtime: string;
  vocabulary: Vocabulary;
  dotfilesRoot: string;
  /** subagent は書式変換が要る。指定するとランタイムのスキーマへ変換して出す */
  subagentFormat?: "codex" | "opencode";
};

const SUBAGENT_RENDERERS = {
  codex: { render: toCodexToml, extension: ".toml" },
  opencode: { render: toOpencodeMarkdown, extension: ".md" },
} as const;

/**
 * base を 1 ランタイム分の完成品へ変換して outDir に配る。
 *
 * `.md` は overlay をマージしてから置換し、それ以外はパーミッションごと素通しでコピーする
 * (スキルの scripts/ には実行ビットを持つファイルがあり、落とすとスキルが壊れる)。
 *
 * 生成は outDir の隣の staging に行い、閉包チェックを通ってから rename で運ぶ。途中で
 * 失敗しても配布先が半端な状態で残らない。staging を隣に置くのは同一ファイルシステムを
 * 保証して rename を成立させるため。
 */
export async function buildTree(
  options: BuildOptions,
): Promise<{ written: string[]; pruned: string[] }> {
  assertSafeOutRoot(options.outDir, options.dotfilesRoot);

  const staging = `${options.outDir}.harness-staging-${crypto.randomUUID().slice(0, 8)}`;
  try {
    const written: string[] = [];
    for await (const entry of walk(options.baseDir, { includeDirs: false })) {
      const rel = relative(options.baseDir, entry.path);
      if (basename(rel) === ".DS_Store") continue;

      const destination = join(staging, rel);
      await Deno.mkdir(dirname(destination), { recursive: true });

      if (rel.endsWith(".md")) {
        let overlay = "";
        try {
          overlay = await Deno.readTextFile(join(options.overlayDir, rel));
        } catch {
          // overlay が無いファイルは base のまま通す
        }
        const merged = mergeSections(await Deno.readTextFile(entry.path), overlay);
        const text = substitute(merged, options.vocabulary, options.runtime);

        if (options.subagentFormat) {
          // 語彙を当ててから書式変換する。逆順だと TOML の中身に置換をかけることになる
          const { render, extension } = SUBAGENT_RENDERERS[options.subagentFormat];
          const subagent = parseSubagent(text);
          const renamed = `${subagent.frontmatter.name}${extension}`;
          await Deno.writeTextFile(join(staging, renamed), render(subagent));
          written.push(renamed);
          continue;
        }
        await Deno.writeTextFile(destination, text);
      } else {
        // copyFile はパーミッションごと複製する。スキルの scripts/ には実行ビットを
        // 持つファイルがあり、テキストとして読み書きし直すと落ちる。
        await Deno.copyFile(entry.path, destination);
      }
      written.push(rel);
    }
    written.sort();

    const previous = await readManifest(options.outDir);
    await Deno.writeTextFile(
      join(staging, MANIFEST_NAME),
      `${JSON.stringify({ generatedBy: GENERATOR, paths: written }, null, 2)}\n`,
    );

    await Deno.mkdir(options.outDir, { recursive: true });
    for (const rel of [...written, MANIFEST_NAME]) {
      const destination = join(options.outDir, rel);
      await Deno.mkdir(dirname(destination), { recursive: true });
      await Deno.rename(join(staging, rel), destination);
    }

    const pruned = planPrune(previous, written);
    for (const rel of pruned) {
      try {
        await Deno.remove(join(options.outDir, rel));
      } catch {
        // 既に人が消していても失敗にしない
      }
    }
    return { written, pruned };
  } finally {
    try {
      await Deno.remove(staging, { recursive: true });
    } catch {
      // staging を作る前に落ちた場合は何もしない
    }
  }
}

export type BuildFileOptions = {
  baseFile: string;
  overlayFile: string;
  outFile: string;
  runtime: string;
  vocabulary: Vocabulary;
  dotfilesRoot: string;
};

/**
 * 単一ファイルを 1 ランタイム分に変換して配る (グローバル指示 AGENTS.md 用)。
 *
 * 配布先のファイル名がランタイムごとに違う (~/.claude/CLAUDE.md と ~/.codex/AGENTS.md) ので
 * ディレクトリ単位の buildTree では扱えない。出力が固定 1 ファイルなので台帳も prune も要らない。
 */
export async function buildFile(options: BuildFileOptions): Promise<void> {
  assertSafeOutRoot(options.outFile, options.dotfilesRoot);

  let overlay = "";
  try {
    overlay = await Deno.readTextFile(options.overlayFile);
  } catch {
    // overlay が無ければ base のまま通す
  }
  const merged = mergeSections(await Deno.readTextFile(options.baseFile), overlay);
  await Deno.mkdir(dirname(options.outFile), { recursive: true });
  await Deno.writeTextFile(
    options.outFile,
    substitute(merged, options.vocabulary, options.runtime),
  );
}

/**
 * 旧方式が張った symlink だけを撤去する。
 *
 * 配布をやめたディレクトリ (~/.agents/skills) には他ツールが置いた実体が同居しており、
 * Home Manager は activation script が張った symlink を自動では撤去しない。判定は
 * 「target が dotfilesRoot 配下に解決する symlink」で、実測では我々の 28 件ちょうどに
 * 一致し、他ツールの 9 件 (すべて実体ディレクトリ) は掛からない。
 */
export async function removeDotfilesLinks(
  dir: string,
  dotfilesRoot: string,
): Promise<string[]> {
  let entries: Deno.DirEntry[];
  try {
    entries = [...Deno.readDirSync(dir)];
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return [];
    throw error;
  }

  const root = resolveIntendedPath(dotfilesRoot);
  const removed: string[] = [];
  for (const entry of entries) {
    const path = join(dir, entry.name);
    if (!Deno.lstatSync(path).isSymlink) continue;

    let target: string;
    try {
      target = Deno.realPathSync(path);
    } catch {
      // 壊れた symlink も対象にできるよう readlink から解決する
      target = resolve(dirname(path), Deno.readLinkSync(path));
    }
    if (target === root || target.startsWith(`${root}/`)) {
      await Deno.remove(path, { recursive: true });
      removed.push(entry.name);
    }
  }
  return removed.sort();
}

/** vocabulary.json を読む。`_comment` などメタキーは語彙として扱わない */
export async function loadVocabulary(path: string): Promise<Vocabulary> {
  const parsed = JSON.parse(await Deno.readTextFile(path));
  const vocabulary: Vocabulary = {};
  for (const [key, value] of Object.entries(parsed)) {
    if (key.startsWith("_")) continue;
    vocabulary[key] = value as Record<string, string>;
  }
  return vocabulary;
}

const USAGE = `usage:
  build-harness.ts --runtime <name> --base <dir> --out <dir> \\
      [--overlay <dir>] [--vocabulary <file>] [--dotfiles-root <dir>] \\
      [--subagent-format codex|opencode]
  build-harness.ts --remove-dotfiles-links <dir> --dotfiles-root <dir>`;

function parseArgs(args: string[]): Record<string, string> {
  const parsed: Record<string, string> = {};
  for (let i = 0; i < args.length; i += 2) {
    if (!args[i].startsWith("--") || args[i + 1] === undefined) {
      throw new Error(`引数を解釈できません: ${args[i]}\n${USAGE}`);
    }
    parsed[args[i].slice(2)] = args[i + 1];
  }
  return parsed;
}

async function main(args: string[]): Promise<number> {
  const options = parseArgs(args);

  if (options["remove-dotfiles-links"]) {
    const dotfilesRoot = options["dotfiles-root"];
    if (!dotfilesRoot) throw new Error(`--dotfiles-root が要ります\n${USAGE}`);
    const removed = await removeDotfilesLinks(options["remove-dotfiles-links"], dotfilesRoot);
    console.log(`撤去した旧 symlink: ${removed.length} 件${removed.length ? ` (${removed.join(", ")})` : ""}`);
    return 0;
  }

  const { runtime, base, out } = options;
  if (!runtime || !base || !out) {
    console.error(USAGE);
    return 2;
  }
  const vocabulary = options.vocabulary ? await loadVocabulary(options.vocabulary) : {};
  const dotfilesRoot = options["dotfiles-root"] ?? ".";

  // --base がファイルなら単一ファイルモード (グローバル指示)
  if ((await Deno.stat(base)).isFile) {
    await buildFile({
      baseFile: base,
      overlayFile: options.overlay ?? `${base}.__no_overlay__`,
      outFile: out,
      runtime,
      vocabulary,
      dotfilesRoot,
    });
    console.log(`${runtime}: ${base} → ${out}`);
    return 0;
  }

  const result = await buildTree({
    baseDir: base,
    overlayDir: options.overlay ?? `${base}/__no_overlay__`,
    outDir: out,
    runtime,
    vocabulary,
    dotfilesRoot,
    subagentFormat: options["subagent-format"] as "codex" | "opencode" | undefined,
  });
  console.log(
    `${runtime}: ${result.written.length} 件を生成${
      result.pruned.length ? ` / ${result.pruned.length} 件を撤去 (${result.pruned.join(", ")})` : ""
    } → ${out}`,
  );
  return 0;
}

if (import.meta.main) {
  Deno.exit(await main(Deno.args));
}
