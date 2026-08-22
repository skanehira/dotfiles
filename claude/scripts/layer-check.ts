#!/usr/bin/env -S deno run --allow-read

/**
 * Clean Architecture のレイヤ境界違反 (内側の層が外側の層を import している) を
 * 決定的に判定する。
 *
 * 「import 文の向き」は完全に機械的な性質なので、LLM に import 行を読ませる必要が無い。
 * 実測では読ませていたために、**型のみの cross-layer import 1 行を 5 回中 4 回
 * 見落としながら毎回 `ok: true` を返していた** (architecture-guard の実測記録)。
 * 見落としは「違反が無い」と区別が付かないため、検出器としては機能していない。
 *
 * 本スクリプトは層の判定・import の抽出・向きの照合をすべて規則で行い、
 * **検査したファイルを 1 件も省略せず `checked_file_list` に載せる** —
 * これが無いと呼び出し側は「違反が無い」と「そのファイルを見ていない」を区別できない
 * (`rules/core/verification.md`)。
 *
 * 使い方:
 *   layer-check.ts --inner <パターン,...> --outer <パターン,...> [--repo <dir>] <file>...
 * 例:
 *   layer-check.ts --inner src/domain/,src/usecase/ --outer src/infra/,src/web/ \
 *     $(git diff --name-only "$PHASE_START_SHA")
 *
 * 出力は JSON (stdout)。exit code は 違反なし=0 / 違反あり=1 / 入力不正=2。
 */

export type LayerConfig = {
  /** 依存される側 (内側) の path パターン。部分一致で判定する */
  inner: string[];
  /** 依存する側 (外側) の path パターン */
  outer: string[];
};

export type SourceFile = { path: string; content: string };

export type Layer = "inner" | "outer" | "unknown";

export type Violation = {
  file: string;
  line: number;
  rule: "clean_arch_layer";
  severity: "high";
  message: string;
  fix_proposal: string;
};

export type CheckedFile = {
  file: string;
  layer: Layer;
  import_lines_checked: number;
  violation_count: number;
};

export type LayerCheckResult = {
  ok: boolean;
  /** 検査を行わなかった理由。行った場合は null */
  skip_reason: string | null;
  violations: Violation[];
  checked_file_list: CheckedFile[];
};

const FIX_PROPOSAL =
  "inner に Port (interface) を定義し、outer に Adapter 実装を置いて DI で繋ぐ";

/** 1 行から import 先を取り出す。言語ごとに書式が違うので拡張子で分ける。 */
function importTargets(path: string, line: string): string[] {
  const ext = path.slice(path.lastIndexOf("."));
  const hits: string[] = [];
  const push = (re: RegExp) => {
    for (const m of line.matchAll(re)) if (m[1]) hits.push(m[1]);
  };

  if (
    [".ts", ".tsx", ".mts", ".cts", ".js", ".jsx", ".mjs", ".cjs"].includes(ext)
  ) {
    // `import type ... from "X"` も同じ from 句を持つので、型のみの import も必ず当たる
    push(/\bfrom\s+["']([^"']+)["']/g);
    push(/\bimport\s+["']([^"']+)["']/g);
    push(/\brequire\(\s*["']([^"']+)["']\s*\)/g);
    push(/\bimport\(\s*["']([^"']+)["']\s*\)/g);
  } else if (ext === ".go") {
    // import ブロック内は裸のクォート文字列 1 行が 1 import
    push(/["']([^"']+)["']/g);
  } else if (ext === ".rs") {
    push(/^\s*(?:pub\s+)?use\s+([^\s;]+)/g);
  } else if (ext === ".py") {
    push(/^\s*from\s+(\S+)\s+import\b/g);
    push(/^\s*import\s+(\S+)/g);
  } else if (ext === ".lua") {
    push(/\brequire\s*\(?\s*["']([^"']+)["']/g);
  }
  return hits;
}

/** `a/b/../c` のような相対参照を畳んで、リポジトリ相対の path に正規化する。 */
function normalize(p: string): string {
  const out: string[] = [];
  for (const seg of p.split("/")) {
    if (seg === "" || seg === ".") continue;
    if (seg === "..") out.pop();
    else out.push(seg);
  }
  return out.join("/");
}

/** import 先を、import 元のファイル位置を基準に解決する。 */
function resolveTarget(fromPath: string, target: string): string {
  if (!target.startsWith(".")) return target;
  const dir = fromPath.slice(0, fromPath.lastIndexOf("/"));
  return normalize(`${dir}/${target}`);
}

/**
 * path がどの層に属するかを決める。inner と outer の両方に当たる構成
 * (inner の下に outer 名のディレクトリがある等) では**最長一致を優先する** —
 * 短いパターンを先に見ると、より具体的な指定が無視される。
 */
function classify(path: string, config: LayerConfig): Layer {
  let best: Layer = "unknown";
  let bestLen = -1;
  for (
    const [layer, patterns] of [["inner", config.inner], [
      "outer",
      config.outer,
    ]] as const
  ) {
    for (const pattern of patterns) {
      if (
        pattern !== "" && path.includes(pattern) && pattern.length > bestLen
      ) {
        best = layer;
        bestLen = pattern.length;
      }
    }
  }
  return best;
}

export function checkLayers(
  files: SourceFile[],
  config: LayerConfig,
): LayerCheckResult {
  if (config.inner.length === 0 || config.outer.length === 0) {
    return {
      ok: true,
      skip_reason: "no_layer_convention",
      violations: [],
      checked_file_list: [],
    };
  }

  const violations: Violation[] = [];
  const checked: CheckedFile[] = [];

  for (const file of files) {
    const layer = classify(file.path, config);
    let importLines = 0;
    let count = 0;

    file.content.split("\n").forEach((line, i) => {
      const targets = importTargets(file.path, line);
      if (targets.length === 0) return;
      importLines += 1;
      // 向きの違反になるのは inner → outer のときだけ。
      // outer → inner は許される依存で、unknown は層が決まらないので判定しない。
      if (layer !== "inner") return;
      for (const target of targets) {
        const resolved = resolveTarget(file.path, target);
        if (classify(resolved, config) !== "outer") continue;
        count += 1;
        violations.push({
          file: file.path,
          line: i + 1,
          rule: "clean_arch_layer",
          severity: "high",
          message: `${file.path}:${
            i + 1
          } (inner) が outer の ${resolved} を import している: ${line.trim()}`,
          fix_proposal: FIX_PROPOSAL,
        });
      }
    });

    checked.push({
      file: file.path,
      layer,
      import_lines_checked: importLines,
      violation_count: count,
    });
  }

  return {
    ok: violations.length === 0,
    skip_reason: null,
    violations,
    checked_file_list: checked,
  };
}

function parseList(v: string | undefined): string[] {
  return (v ?? "").split(",").map((s) => s.trim()).filter((s) => s !== "");
}

async function main() {
  const argv = [...Deno.args];
  let inner = "", outer = "", repo = ".";
  const paths: string[] = [];
  while (argv.length > 0) {
    const a = argv.shift()!;
    if (a === "--inner") inner = argv.shift() ?? "";
    else if (a === "--outer") outer = argv.shift() ?? "";
    else if (a === "--repo") repo = argv.shift() ?? ".";
    else paths.push(a);
  }

  const config = { inner: parseList(inner), outer: parseList(outer) };
  const files: SourceFile[] = [];
  for (const p of paths) {
    try {
      files.push({ path: p, content: await Deno.readTextFile(`${repo}/${p}`) });
    } catch (e) {
      // 読めなかったファイルを黙って落とすと「検査した」件数が実態とずれる
      console.error(
        JSON.stringify({ error: "unreadable", file: p, detail: String(e) }),
      );
      Deno.exit(2);
    }
  }

  const result = checkLayers(files, config);
  console.log(JSON.stringify(result, null, 2));
  Deno.exit(result.violations.length === 0 ? 0 : 1);
}

if (import.meta.main) {
  await main();
}
