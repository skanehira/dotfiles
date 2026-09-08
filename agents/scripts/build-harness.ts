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

import { basename, dirname, join, resolve } from "jsr:@std/path@1";

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
