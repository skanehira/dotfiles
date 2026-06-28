#!/usr/bin/env -S deno run --allow-env --allow-read --allow-write
export {};

// SessionEnd hook で起動される。
// stdin から JSON ({transcript_path, session_id, ...}) を読み、
// 1. transcript_path の jsonl を ~/.claude/archive/ にコピー
// 2. RETENTION_DAYS より古い archive ファイルを削除
// utility-self-improving スキルが安定した解析対象として archive を参照する前提。

const HOME = Deno.env.get("HOME") ?? "";
const ARCHIVE_DIR = `${HOME}/.claude/archive`;

// utility-self-improving のデフォルト解析期間 (30日) + 余裕で 90日
const RETENTION_DAYS = 90;

await Deno.mkdir(ARCHIVE_DIR, { recursive: true });

let input: { transcript_path?: string; session_id?: string } = {};
try {
  input = await new Response(Deno.stdin.readable).json();
} catch {
  // stdin 不在/JSON 不正でも掃除処理だけは継続する
}

if (input.transcript_path) {
  try {
    const src = input.transcript_path;
    const fname = src.split("/").pop() ?? `unknown-${input.session_id ?? "session"}.jsonl`;
    const dest = `${ARCHIVE_DIR}/${fname}`;
    await Deno.copyFile(src, dest);
  } catch {
    // 元 jsonl が見つからない/コピー失敗は session に影響させない (SessionEnd は decision control なし)
  }
}

const cutoff = Date.now() - RETENTION_DAYS * 86400 * 1000;
try {
  for await (const entry of Deno.readDir(ARCHIVE_DIR)) {
    if (!entry.isFile || !entry.name.endsWith(".jsonl")) continue;
    const path = `${ARCHIVE_DIR}/${entry.name}`;
    try {
      const stat = await Deno.stat(path);
      if (stat.mtime && stat.mtime.getTime() < cutoff) {
        await Deno.remove(path);
      }
    } catch {
      // 個別ファイルの失敗は無視
    }
  }
} catch {
  // archive ディレクトリが読めない場合は無視
}
