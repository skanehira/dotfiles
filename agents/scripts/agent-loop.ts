#!/usr/bin/env -S deno run --allow-env --allow-run --allow-read --allow-write
/**
 * agent-loop: launchd から 10 分おきに 1 回呼ばれ、対象のリポジトリごとに仕事を探して、
 * 仕事の種類ごとに新しい Claude Code をバックグラウンドで起動する。LLM は使わない。
 *
 * | 種類   | 仕事があるとき                                   | 起動するスキル   |
 * | ------ | ------------------------------------------------ | ---------------- |
 * | triage | dev-triage の list-untriaged.sh が番号を返す     | /dev-triage      |
 * | design | needs-design の issue (設計 PR が無いもの) がある | /dev-feat-spec   |
 * | impl   | ready か in-progress の issue がある              | /dev-impl        |
 *
 * tmux ではなく `claude --bg -w <名前>` で起動する。Claude Code が worktree を作り (リポジトリに
 * WorktreeCreate フックがあればそれが作る)、`claude attach <名前>` で動いている画面を見られる。
 * 同じリポジトリの同じ種類は同時に 1 つだけにする (dev-triage と dev-feat-spec は同時に 1 つの
 * 前提で、dev-impl は自分の中で worktree による並列実行を持つため)。
 *
 * 前回の run と入力 (対象の issue の番号と更新時刻) が同じなら起動しない。何もしない起動や、
 * 同じ失敗の繰り返しを LLM なしで止めるため。6 時間経てば、同じ入力でも 1 回だけ起動し直す。
 *
 * 設定 (対象のリポジトリの一覧) は dotfiles の外の ~/.config/agent-loop/repos.yaml に置く。
 * dotfiles は公開リポジトリで、一覧には業務のリポジトリの名前が入るため。
 */

import { parse as parseYaml } from "jsr:@std/yaml@1";

export type Kind = "triage" | "design" | "impl";
export const KINDS: readonly Kind[] = ["triage", "design", "impl"];

const PROMPTS: Record<Kind, string> = {
  triage: "/dev-triage",
  design: "/dev-feat-spec",
  impl: "/dev-impl",
};

export const RETRY_AFTER_MS = 6 * 60 * 60 * 1000;

export interface RepoConfig {
  slug: string;
  path: string;
  kinds: Kind[];
}

export interface RawIssue {
  number: number;
  labels: { name: string }[];
  author_association: string;
  updated_at: string;
  pull_request?: unknown;
}

export interface Item {
  number: number;
  updatedAt: string;
}

export interface RunRecord {
  sessionId: string;
  name: string;
  inputKey: string;
  startedAt: number;
}

export interface Finished {
  inputKey: string;
  finishedAt: number;
}

export interface RepoState {
  running?: Partial<Record<Kind, RunRecord>>;
  finished?: Partial<Record<Kind, Finished>>;
}

export type State = Record<string, RepoState>;

export interface SessionInfo {
  id: string;
  state: string;
}

export interface Deps {
  listUntriaged(repo: RepoConfig): Promise<number[]>;
  listIssues(repo: RepoConfig): Promise<RawIssue[]>;
  listOpenPrBodies(repo: RepoConfig): Promise<string[]>;
  listSessions(): Promise<SessionInfo[]>;
  launch(
    repo: RepoConfig,
    kind: Kind,
    now: number,
  ): Promise<{ sessionId: string; name: string }>;
  cleanup(repo: RepoConfig, run: RunRecord): Promise<void>;
  log(message: string): void;
}

const MEMBERS = ["OWNER", "MEMBER", "COLLABORATOR"];
const DESIGN_BLOCKERS = ["needs-human", "tracking", "事業・運営"];
const IMPL_BLOCKERS = ["needs-human", "tracking"];

/** 設計と実装の対象を選ぶ。条件は dev-feat-spec と /dev-impl の Step 1 の対象の選び方に合わせる */
export function classifyIssues(
  issues: RawIssue[],
  openPrBodies: string[],
): { design: Item[]; impl: Item[] } {
  const designedByPr = new Set<number>();
  for (const body of openPrBodies) {
    for (const m of body.matchAll(/^\s*Design-for:\s*#(\d+)/gm)) {
      designedByPr.add(Number(m[1]));
    }
  }
  const toItem = (i: RawIssue): Item => ({
    number: i.number,
    updatedAt: i.updated_at,
  });
  const candidates = issues.filter((i) =>
    !i.pull_request && MEMBERS.includes(i.author_association)
  );
  const has = (i: RawIssue, names: string[]) =>
    i.labels.some((l) => names.includes(l.name));
  return {
    design: candidates
      .filter((i) =>
        has(i, ["needs-design"]) && !has(i, DESIGN_BLOCKERS) &&
        !designedByPr.has(i.number)
      )
      .map(toItem),
    impl: candidates
      .filter((i) => has(i, ["ready", "in-progress"]) && !has(i, IMPL_BLOCKERS))
      .map(toItem),
  };
}

export interface WorktreeFacts {
  dirty: boolean;
  headPushed: boolean;
  nestedWorktrees: number;
}

/** run が終わった worktree を消してよいか。未保存の作業を消さないことだけを見る */
export function decideWorktreeRemoval(
  f: WorktreeFacts,
): { remove: boolean; reason: string } {
  if (f.dirty) return { remove: false, reason: "追跡中のファイルに変更がある" };
  if (!f.headPushed) {
    return {
      remove: false,
      reason: "HEAD がどの remote のブランチにも含まれていない",
    };
  }
  if (f.nestedWorktrees > 0) {
    return {
      remove: false,
      reason: `中に別の worktree が ${f.nestedWorktrees} つ残っている`,
    };
  }
  return { remove: true, reason: "未保存の作業が無い" };
}

export function inputKey(items: Item[]): string {
  return [...items].sort((a, b) => a.number - b.number).map((i) =>
    `${i.number}@${i.updatedAt}`
  ).join(",");
}

/** 終わったとみなすセッションの状態。一覧から消えたもの (undefined) も含む */
function isFinished(session: SessionInfo | undefined): boolean {
  return session === undefined || session.state === "done" ||
    session.state === "error";
}

function shouldLaunch(
  key: string,
  finished: Finished | undefined,
  now: number,
): string | null {
  if (key === "") return "仕事なし";
  if (
    finished && finished.inputKey === key &&
    now - finished.finishedAt < RETRY_AFTER_MS
  ) {
    return "前回の run から入力が変わっていない";
  }
  return null;
}

/** 1 回分の見回り。状態を受け取り、起動と片付けを行って、新しい状態を返す */
export async function tick(
  repos: RepoConfig[],
  state: State,
  deps: Deps,
  now: number,
): Promise<State> {
  const next: State = structuredClone(state);
  const sessions = new Map((await deps.listSessions()).map((s) => [s.id, s]));

  for (const repo of repos) {
    const rs: RepoState = next[repo.slug] ?? {};
    rs.running ??= {};
    rs.finished ??= {};
    next[repo.slug] = rs;

    const idle: Kind[] = [];
    for (const kind of repo.kinds) {
      const run = rs.running[kind];
      if (run) {
        if (!isFinished(sessions.get(run.sessionId))) {
          deps.log(`${repo.slug} ${kind}: 実行中 (${run.name})`);
          continue;
        }
        await deps.cleanup(repo, run);
        rs.finished[kind] = { inputKey: run.inputKey, finishedAt: now };
        delete rs.running[kind];
        deps.log(`${repo.slug} ${kind}: 終了を確認して片付けた (${run.name})`);
      }
      idle.push(kind);
    }
    if (idle.length === 0) continue;

    const keys = await snapshotKeys(repo, idle, deps);
    for (const kind of idle) {
      const key = keys[kind] ?? "";
      const skip = shouldLaunch(key, rs.finished[kind], now);
      if (skip) {
        deps.log(`${repo.slug} ${kind}: 起動しない (${skip})`);
        continue;
      }
      const launched = await deps.launch(repo, kind, now);
      rs.running[kind] = { ...launched, inputKey: key, startedAt: now };
      deps.log(
        `${repo.slug} ${kind}: 起動した (${launched.name}, 入力 ${key})`,
      );
    }
  }
  return next;
}

async function snapshotKeys(
  repo: RepoConfig,
  kinds: Kind[],
  deps: Deps,
): Promise<Partial<Record<Kind, string>>> {
  const keys: Partial<Record<Kind, string>> = {};
  if (kinds.includes("triage")) {
    // 未整理の issue は状態のラベルが付くと対象から外れるので、番号だけで入力を表す
    keys.triage = inputKey(
      (await deps.listUntriaged(repo)).map((number) => ({
        number,
        updatedAt: "",
      })),
    );
  }
  if (kinds.includes("design") || kinds.includes("impl")) {
    const [issues, prBodies] = await Promise.all([
      deps.listIssues(repo),
      deps.listOpenPrBodies(repo),
    ]);
    const classified = classifyIssues(issues, prBodies);
    if (kinds.includes("design")) keys.design = inputKey(classified.design);
    if (kinds.includes("impl")) keys.impl = inputKey(classified.impl);
  }
  return keys;
}

// ---- ここから下は外界に触れる実装 (テストでは fake に差し替える) ----

const HOME = Deno.env.get("HOME") ?? "";
const CONFIG_PATH = Deno.env.get("AGENT_LOOP_CONFIG") ??
  `${HOME}/.config/agent-loop/repos.yaml`;
const STATE_DIR = Deno.env.get("AGENT_LOOP_STATE_DIR") ??
  `${HOME}/.local/state/agent-loop`;
const UNTRIAGED_SCRIPT =
  `${HOME}/.claude/skills/dev-triage/scripts/list-untriaged.sh`;

async function run(
  cmd: string,
  args: string[],
  cwd?: string,
): Promise<{ code: number; stdout: string; stderr: string }> {
  const out = await new Deno.Command(cmd, {
    args,
    cwd,
    stdout: "piped",
    stderr: "piped",
  }).output();
  const dec = new TextDecoder();
  return {
    code: out.code,
    stdout: dec.decode(out.stdout),
    stderr: dec.decode(out.stderr),
  };
}

async function runOk(
  cmd: string,
  args: string[],
  cwd?: string,
): Promise<string> {
  const r = await run(cmd, args, cwd);
  if (r.code !== 0) {
    throw new Error(
      `${cmd} ${args.join(" ")} が exit ${r.code}: ${r.stderr.trim()}`,
    );
  }
  return r.stdout;
}

export function parseConfig(text: string): RepoConfig[] {
  const doc = parseYaml(text) as {
    repos?: { slug?: string; path?: string; kinds?: string[] }[];
  } | null;
  const repos = doc?.repos ?? [];
  return repos.map((r, i) => {
    if (!r.slug || !r.path) {
      throw new Error(`repos[${i}] に slug と path が要る`);
    }
    const kinds = (r.kinds ?? [...KINDS]) as Kind[];
    for (const k of kinds) {
      if (!KINDS.includes(k)) {
        throw new Error(`repos[${i}] の kinds に知らない値: ${k}`);
      }
    }
    return { slug: r.slug, path: r.path.replace(/^~(?=\/)/, HOME), kinds };
  });
}

async function worktreePaths(repoPath: string): Promise<string[]> {
  const out = await runOk("git", [
    "-C",
    repoPath,
    "worktree",
    "list",
    "--porcelain",
  ]);
  return out.split("\n").filter((l) => l.startsWith("worktree ")).map((l) =>
    l.slice(9)
  );
}

/** Claude Code (とリポジトリの WorktreeCreate フック) は <clone>/.claude/worktrees/<名前> に作る */
async function findWorktree(
  repoPath: string,
  name: string,
): Promise<string | null> {
  return (await worktreePaths(repoPath)).find((p) =>
    p.endsWith(`/.claude/worktrees/${name}`)
  ) ??
    null;
}

async function worktreeFacts(
  repoPath: string,
  wt: string,
): Promise<WorktreeFacts> {
  const status = await runOk("git", ["-C", wt, "status", "--porcelain"]);
  const containing = await run("git", [
    "-C",
    wt,
    "branch",
    "-r",
    "--contains",
    "HEAD",
  ]);
  const nested =
    (await worktreePaths(repoPath)).filter((p) => p.startsWith(`${wt}/`))
      .length;
  return {
    dirty: status.trim() !== "",
    headPushed: containing.code === 0 && containing.stdout.trim() !== "",
    nestedWorktrees: nested,
  };
}

function sessionName(repo: RepoConfig, kind: Kind, now: number): string {
  const stamp = new Date(now).toISOString().replace(/[-:]/g, "").slice(0, 13); // 20261111T1200
  return `al-${repo.slug.split("/")[1]}-${kind}-${stamp}`;
}

export function realDeps(logFile: string): Deps {
  return {
    async listUntriaged(repo) {
      const out = await runOk(UNTRIAGED_SCRIPT, [repo.slug]);
      return out.split("\n").filter((l) => l.trim() !== "").map(Number);
    },
    async listIssues(repo) {
      const out = await runOk("gh", [
        "api",
        "--paginate",
        `repos/${repo.slug}/issues?state=open&per_page=100`,
        "--jq",
        ".[]",
      ]);
      return out.split("\n").filter((l) => l.trim() !== "").map((l) =>
        JSON.parse(l) as RawIssue
      );
    },
    async listOpenPrBodies(repo) {
      const out = await runOk("gh", [
        "pr",
        "list",
        "--repo",
        repo.slug,
        "--state",
        "open",
        "--limit",
        "500",
        "--json",
        "body",
        "--jq",
        ".[].body | @json",
      ]);
      return out.split("\n").filter((l) => l.trim() !== "").map((l) =>
        JSON.parse(l) as string
      );
    },
    async listSessions() {
      const out = await runOk("claude", ["agents", "--json", "--all"]);
      return (JSON.parse(out) as SessionInfo[]).map((s) => ({
        id: s.id,
        state: s.state,
      }));
    },
    async launch(repo, kind, now) {
      const name = sessionName(repo, kind, now);
      // --permission-mode を明示する: 省くと普段の既定のモード (plan など) を引き継ぎ、読み取りだけで終わる
      const out = await runOk("claude", [
        "--bg",
        "--name",
        name,
        "--worktree",
        name,
        "--model",
        "opus",
        "--permission-mode",
        "bypassPermissions",
        PROMPTS[kind],
      ], repo.path);
      const id = out.match(/claude attach (\S+)/)?.[1];
      if (!id) {
        throw new Error(
          `claude --bg の出力からセッションの id を読めない: ${out.trim()}`,
        );
      }
      return { sessionId: id, name };
    },
    async cleanup(repo, rec) {
      await run("claude", ["stop", rec.sessionId]);
      // claude rm は、フック (WorktreeCreate) が作った worktree に管理外のファイル (node_modules など)
      // があると、worktree を消さずに "kept" と出して exit 0 で終わる。そのため worktree は自分で確かめて消す
      const wt = await findWorktree(repo.path, rec.name);
      if (wt) {
        const decision = decideWorktreeRemoval(
          await worktreeFacts(repo.path, wt),
        );
        if (!decision.remove) {
          this.log(
            `${repo.slug}: ${rec.name} の worktree を残す (${decision.reason}): ${wt}`,
          );
          return;
        }
        await runOk("git", [
          "-C",
          repo.path,
          "worktree",
          "remove",
          "--force",
          wt,
        ]);
      }
      const rm = await run("claude", ["rm", rec.sessionId]);
      if (rm.code !== 0 || /\bkept\b/.test(rm.stdout + rm.stderr)) {
        this.log(
          `${repo.slug}: claude rm ${rec.sessionId} がセッションを消さなかった: ${
            (rm.stdout + rm.stderr).trim()
          }`,
        );
      }
      // worktree の作成で切られたブランチ (Claude Code の既定の名前) を消す。中身は origin の先頭のまま
      const branch = `worktree-${rec.name}`;
      const exists = await run("git", [
        "-C",
        repo.path,
        "rev-parse",
        "--verify",
        "--quiet",
        `refs/heads/${branch}`,
      ]);
      if (exists.code === 0) {
        await run("git", ["-C", repo.path, "branch", "-D", branch]);
      }
    },
    log(message) {
      const line = `${new Date().toISOString()} ${message}\n`;
      Deno.writeTextFileSync(logFile, line, { append: true });
      console.log(line.trimEnd());
    },
  };
}

async function withLock<T>(
  dir: string,
  fn: () => Promise<T>,
): Promise<T | undefined> {
  const lock = `${dir}/lock`;
  try {
    Deno.mkdirSync(lock);
  } catch {
    const age = Date.now() - (Deno.statSync(lock).mtime?.getTime() ?? 0);
    if (age < 60 * 60 * 1000) {
      console.log("前回の見回りがまだ動いているので何もしない");
      return undefined;
    }
    // 1 時間を超えて残っているロックは、落ちた見回りの残骸として取り直す
    Deno.removeSync(lock);
    Deno.mkdirSync(lock);
  }
  try {
    return await fn();
  } finally {
    Deno.removeSync(lock);
  }
}

async function main(): Promise<void> {
  Deno.mkdirSync(STATE_DIR, { recursive: true });
  const statePath = `${STATE_DIR}/state.json`;
  const real = realDeps(`${STATE_DIR}/agent-loop.log`);
  // --dry-run: 判定だけを出し、起動・片付け・状態の保存をしない
  const dryRun = Deno.args.includes("--dry-run");
  const deps: Deps = dryRun
    ? {
      ...real,
      launch: (repo, kind, now) => {
        console.log(
          `[dry-run] 起動する: ${repo.slug} ${kind} (${PROMPTS[kind]})`,
        );
        return Promise.resolve({
          sessionId: "dry-run",
          name: sessionName(repo, kind, now),
        });
      },
      cleanup: (repo, rec) => {
        console.log(`[dry-run] 片付ける: ${repo.slug} ${rec.name}`);
        return Promise.resolve();
      },
      log: (message) => console.log(message),
    }
    : real;
  await withLock(STATE_DIR, async () => {
    let repos: RepoConfig[];
    try {
      repos = parseConfig(Deno.readTextFileSync(CONFIG_PATH));
    } catch (e) {
      deps.log(
        `設定を読めない (${CONFIG_PATH}): ${
          e instanceof Error ? e.message : e
        }`,
      );
      return;
    }
    let state: State = {};
    try {
      state = JSON.parse(Deno.readTextFileSync(statePath));
    } catch {
      // 初回は状態のファイルが無い
    }
    const next = await tick(repos, state, deps, Date.now());
    if (!dryRun) {
      Deno.writeTextFileSync(statePath, JSON.stringify(next, null, 2) + "\n");
    }
  });
}

if (import.meta.main) {
  await main();
}
