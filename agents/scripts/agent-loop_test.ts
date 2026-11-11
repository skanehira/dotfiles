import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  classifyIssues,
  cleanupMode,
  decideWorktreeRemoval,
  type Deps,
  inputKey,
  type Item,
  parseConfig,
  type RawIssue,
  type RepoConfig,
  type SessionInfo,
  type State,
  tick,
} from "./agent-loop.ts";

const HOUR = 60 * 60 * 1000;
const NOW = Date.UTC(2026, 10, 11, 12, 0, 0);

function issue(
  number: number,
  labels: string[],
  opts: { author?: string; updatedAt?: string; pr?: boolean } = {},
): RawIssue {
  return {
    number,
    labels: labels.map((name) => ({ name })),
    author_association: opts.author ?? "MEMBER",
    updated_at: opts.updatedAt ?? "2026-11-11T00:00:00Z",
    ...(opts.pr ? { pull_request: {} } : {}),
  };
}

/** 未整理の issue の項目。更新時刻は既定で t0 */
function u(number: number, updatedAt = "t0"): Item {
  return { number, updatedAt };
}

const REPO: RepoConfig = {
  slug: "acme/app",
  path: "/work/acme/app",
  kinds: ["triage", "design", "impl"],
};

/** 呼び出しとログを記録する fake。snapshot の中身と、セッションの一覧をテストごとに与える */
function fakeDeps(
  opts: {
    untriaged?: Item[];
    issues?: RawIssue[] | Error;
    designPrBodies?: string[];
    sessions?: SessionInfo[];
  } = {},
) {
  const calls: string[] = [];
  const logs: string[] = [];
  const notes: string[] = [];
  let seq = 0;
  const deps: Deps = {
    listUntriaged: (repo) => {
      calls.push(`listUntriaged ${repo.slug}`);
      return Promise.resolve(opts.untriaged ?? []);
    },
    listIssues: (repo) => {
      calls.push(`listIssues ${repo.slug}`);
      return opts.issues instanceof Error
        ? Promise.reject(opts.issues)
        : Promise.resolve(opts.issues ?? []);
    },
    listOpenPrBodies: (repo) => {
      calls.push(`listOpenPrBodies ${repo.slug}`);
      return Promise.resolve(opts.designPrBodies ?? []);
    },
    listSessions: () => Promise.resolve(opts.sessions ?? []),
    launch: (repo, kind) => {
      seq += 1;
      calls.push(`launch ${repo.slug} ${kind}`);
      return Promise.resolve({
        sessionId: `s${seq}`,
        name: `al-app-${kind}-${seq}`,
      });
    },
    cleanup: (repo, run, endState) => {
      calls.push(`cleanup ${repo.slug} ${run.sessionId} ${endState}`);
      return Promise.resolve();
    },
    log: (message) => {
      logs.push(message);
    },
    notify: (title, message, attachId) => {
      notes.push(`${title} | ${message} | ${attachId ?? "-"}`);
      return Promise.resolve();
    },
  };
  return { deps, calls, logs, notes };
}

function runningRecord(sessionId: string, inputKey = "k") {
  return { sessionId, name: sessionId, inputKey, startedAt: NOW - HOUR };
}

Deno.test("classifyIssues は作成者・状態のラベル・設計 PR の有無で設計と実装の対象に分ける", () => {
  const issues = [
    issue(1, ["needs-design"]),
    issue(2, ["needs-design", "needs-human"]),
    issue(3, ["needs-design"], { author: "NONE" }),
    issue(4, ["needs-design"]),
    issue(5, ["ready"], { updatedAt: "2026-11-10T00:00:00Z" }),
    issue(6, ["in-progress"]),
    issue(7, ["ready", "tracking"]),
    issue(8, ["ready"], { pr: true }),
    issue(9, ["needs-design", "事業・運営"]),
    issue(10, ["needs-design", "tracking"]),
    issue(11, ["ready", "needs-human"]),
    issue(12, ["needs-design"], { author: "OWNER" }),
    issue(13, ["ready"], { author: "COLLABORATOR" }),
    issue(14, ["needs-design"]),
  ];
  // 行の途中の Design-for は設計 PR の宣言ではない (design-approved.yml も行頭だけを読む)
  const prBodies = [
    "何を決めたか\n\nDesign-for: #4\n",
    "関連: 前回の Design-for: #14 を参照",
  ];

  const actual = classifyIssues(issues, prBodies);

  const at = (number: number) => ({
    number,
    updatedAt: "2026-11-11T00:00:00Z",
  });
  assertEquals(actual, {
    design: [at(1), at(12), at(14)],
    impl: [{ number: 5, updatedAt: "2026-11-10T00:00:00Z" }, at(6), at(13)],
  });
});

Deno.test("inputKey は番号の順に並べ、空なら空文字を返す", () => {
  assertEquals(inputKey([u(9, "b"), u(2, "a")]), "2@a,9@b");
  assertEquals(inputKey([]), "");
});

Deno.test("cleanupMode は done と一覧から消えたものだけを消し、ほかの終わり方は会話と worktree を残す", () => {
  assertEquals(cleanupMode("done", false), "remove");
  assertEquals(cleanupMode(undefined, false), "remove");
  assertEquals(cleanupMode("blocked", false), "keep");
  assertEquals(cleanupMode("failed", false), "keep");
  assertEquals(cleanupMode("stopped", false), "keep");
  assertEquals(cleanupMode("error", false), "keep");
});

Deno.test("cleanupMode は、人の判断を求めた run なら done でも会話と worktree を残す", () => {
  // needs-human のコメントに claude attach <id> を載せた run を消すと、コメントから開けなくなる
  assertEquals(cleanupMode("done", true), "keep");
  assertEquals(cleanupMode(undefined, true), "keep");
});

Deno.test("仕事のある種類だけを起動し、起動した記録を状態に残す", async () => {
  const { deps, calls } = fakeDeps({
    untriaged: [u(3)],
    issues: [issue(1, ["needs-design"])],
  });

  const state = await tick([REPO], {}, deps, NOW);

  assertEquals(calls.filter((c) => c.startsWith("launch")), [
    "launch acme/app triage",
    "launch acme/app design",
  ]);
  assertEquals(state, {
    "acme/app": {
      running: {
        triage: {
          sessionId: "s1",
          name: "al-app-triage-1",
          inputKey: "3@t0",
          startedAt: NOW,
        },
        design: {
          sessionId: "s2",
          name: "al-app-design-2",
          inputKey: "1@2026-11-11T00:00:00Z",
          startedAt: NOW,
        },
      },
      finished: {},
    },
  });
});

Deno.test("動いているセッションがある種類は起動せず、同じリポジトリの別の種類は起動する", async () => {
  const { deps, calls } = fakeDeps({
    untriaged: [u(3), u(4)],
    issues: [issue(1, ["needs-design"])],
    sessions: [{ id: "s0", state: "working" }],
  });
  const before: State = {
    "acme/app": {
      running: { triage: runningRecord("s0", "3@t0") },
      finished: {},
    },
  };

  const state = await tick([REPO], before, deps, NOW);

  assertEquals(
    calls.filter((c) => c.startsWith("launch") || c.startsWith("cleanup")),
    [
      "launch acme/app design",
    ],
  );
  assertEquals(state["acme/app"].running?.triage, runningRecord("s0", "3@t0"));
});

Deno.test("終わったセッションを片付けて、入力が変わっていれば同じ種類を起動し直す", async () => {
  const { deps, calls } = fakeDeps({
    untriaged: [u(5)],
    sessions: [{ id: "s0", state: "done" }],
  });
  const before: State = {
    "acme/app": {
      running: { triage: runningRecord("s0", "3@t0") },
      finished: {},
    },
  };

  const state = await tick([REPO], before, deps, NOW);

  assertEquals(
    calls.filter((c) => c.startsWith("launch") || c.startsWith("cleanup")),
    [
      "cleanup acme/app s0 done",
      "launch acme/app triage",
    ],
  );
  assertEquals(state["acme/app"].finished?.triage, {
    inputKey: "3@t0",
    finishedAt: NOW,
  });
  assertEquals(state["acme/app"].running?.triage?.inputKey, "5@t0");
});

Deno.test("一覧から消えたセッションも、終わったものとして片付ける", async () => {
  const { deps, calls } = fakeDeps({ sessions: [] });
  const before: State = {
    "acme/app": {
      running: { impl: runningRecord("gone", "1@a") },
      finished: {},
    },
  };

  const state = await tick([REPO], before, deps, NOW);

  assertEquals(calls.filter((c) => c.startsWith("cleanup")), [
    "cleanup acme/app gone undefined",
  ]);
  assertEquals(state["acme/app"].running, {});
  assertEquals(state["acme/app"].finished?.impl, {
    inputKey: "1@a",
    finishedAt: NOW,
  });
});

Deno.test("blocked・failed・stopped のセッションも終わったものとし、その状態を片付けに渡す", async () => {
  const { deps, calls } = fakeDeps({
    sessions: [
      { id: "a", state: "blocked" },
      { id: "b", state: "failed" },
      { id: "c", state: "stopped" },
    ],
  });
  const before: State = {
    "acme/app": {
      running: {
        triage: runningRecord("a"),
        design: runningRecord("b"),
        impl: runningRecord("c"),
      },
      finished: {},
    },
  };

  const state = await tick([REPO], before, deps, NOW);

  assertEquals(calls.filter((c) => c.startsWith("cleanup")), [
    "cleanup acme/app a blocked",
    "cleanup acme/app b failed",
    "cleanup acme/app c stopped",
  ]);
  assertEquals(state["acme/app"].running, {});
});

Deno.test("前回の run と入力が同じなら起動しないが、6 時間を過ぎたら 1 回だけ起動し直す", async () => {
  const finished = (finishedAt: number): State => ({
    "acme/app": {
      running: {},
      finished: { triage: { inputKey: "3@t0", finishedAt } },
    },
  });

  const recent = fakeDeps({ untriaged: [u(3)] });
  await tick([REPO], finished(NOW - HOUR), recent.deps, NOW);
  const old = fakeDeps({ untriaged: [u(3)] });
  await tick([REPO], finished(NOW - 6 * HOUR - 1), old.deps, NOW);

  assertEquals(recent.calls.filter((c) => c.startsWith("launch")), []);
  assertEquals(old.calls.filter((c) => c.startsWith("launch")), [
    "launch acme/app triage",
  ]);
});

Deno.test("同じ issue でも、人が触って更新時刻が変われば、6 時間を待たずに整理を起動する", async () => {
  // dev-triage が needs-human にした issue に人が回答してラベルを外すと、番号は同じでも更新時刻が変わる
  const { deps, calls } = fakeDeps({ untriaged: [u(3, "t1")] });
  const before: State = {
    "acme/app": {
      running: {},
      finished: { triage: { inputKey: "3@t0", finishedAt: NOW - HOUR } },
    },
  };

  await tick([REPO], before, deps, NOW);

  assertEquals(calls.filter((c) => c.startsWith("launch")), [
    "launch acme/app triage",
  ]);
});

Deno.test("設定で外した種類は、仕事があっても起動しない", async () => {
  const { deps, calls } = fakeDeps({
    untriaged: [u(3)],
    issues: [issue(1, ["needs-design"]), issue(2, ["ready"])],
  });

  await tick([{ ...REPO, kinds: ["design"] }], {}, deps, NOW);

  assertEquals(calls.filter((c) => c.startsWith("launch")), [
    "launch acme/app design",
  ]);
});

Deno.test("すべての種類が動いているリポジトリでは、GitHub に問い合わせず、実行中とだけ記録する", async () => {
  const { deps, calls, logs } = fakeDeps({
    sessions: ["a", "b", "c"].map((id) => ({ id, state: "working" })),
  });
  const before: State = {
    "acme/app": {
      running: {
        triage: runningRecord("a"),
        design: runningRecord("b"),
        impl: runningRecord("c"),
      },
      finished: {},
    },
  };

  await tick([REPO], before, deps, NOW);

  assertEquals(calls, []);
  assertEquals(logs, [
    "acme/app triage: 実行中 (a)",
    "acme/app design: 実行中 (b)",
    "acme/app impl: 実行中 (c)",
  ]);
});

Deno.test("1 つのリポジトリで問い合わせが失敗しても、起動した記録を失わず、ほかのリポジトリを処理する", async () => {
  const broken: RepoConfig = {
    slug: "acme/broken",
    path: "/work/acme/broken",
    kinds: ["triage", "design"],
  };
  const { deps, calls, logs } = fakeDeps({
    untriaged: [u(3)],
    issues: new Error("gh が落ちた"),
  });

  const state = await tick(
    [broken, { ...REPO, kinds: ["triage"] }],
    {},
    deps,
    NOW,
  );

  assertEquals(calls.filter((c) => c.startsWith("launch")), [
    "launch acme/app triage",
  ]);
  assertEquals(logs.filter((l) => l.startsWith("acme/broken")), [
    "acme/broken: この見回りを中断した: gh が落ちた",
  ]);
  assertEquals(state["acme/broken"], { running: {}, finished: {} });
  assertEquals(state["acme/app"].running?.triage?.sessionId, "s1");
});

Deno.test("worktree は、変更が無く HEAD が push 済みで、中に別の worktree が無いときだけ消す", () => {
  const safe = { dirty: false, headPushed: true, nestedWorktrees: 0 };

  assertEquals(decideWorktreeRemoval(safe), {
    remove: true,
    reason: "未保存の作業が無い",
  });
  assertEquals(decideWorktreeRemoval({ ...safe, dirty: true }), {
    remove: false,
    reason: "追跡中のファイルに変更がある",
  });
  assertEquals(decideWorktreeRemoval({ ...safe, headPushed: false }), {
    remove: false,
    reason: "HEAD がどの remote のブランチにも含まれていない",
  });
  assertEquals(decideWorktreeRemoval({ ...safe, nestedWorktrees: 2 }), {
    remove: false,
    reason: "中に別の worktree が 2 つ残っている",
  });
});

Deno.test("parseConfig は kinds を省くとすべての種類にし、~ を HOME に展開する", () => {
  const repos = parseConfig(
    "repos:\n  - slug: acme/app\n    path: ~/src/app\n  - slug: acme/web\n    path: /abs/web\n    kinds: [design]\n",
    "/home/me",
  );

  assertEquals(repos, [
    {
      slug: "acme/app",
      path: "/home/me/src/app",
      kinds: ["triage", "design", "impl"],
    },
    { slug: "acme/web", path: "/abs/web", kinds: ["design"] },
  ]);
});

Deno.test("parseConfig は slug・path の欠けと知らない kinds を拒む", () => {
  assertThrows(
    () => parseConfig("repos:\n  - slug: acme/app\n", "/home/me"),
    Error,
    "repos[0] に slug と path が要る",
  );
  assertThrows(
    () =>
      parseConfig(
        "repos:\n  - slug: acme/app\n    path: /x\n    kinds: [deploy]\n",
        "/home/me",
      ),
    Error,
    "repos[0] の kinds に知らない値: deploy",
  );
});

Deno.test("done 以外で終わった run は、会話を開く id 付きで人に通知し、done では通知しない", async () => {
  const { deps, notes } = fakeDeps({
    sessions: [
      { id: "a", state: "failed" },
      { id: "b", state: "done" },
      { id: "c", state: "blocked" },
    ],
  });
  const before: State = {
    "acme/app": {
      running: {
        triage: runningRecord("a"),
        design: runningRecord("b"),
        impl: runningRecord("c"),
      },
      finished: {},
    },
  };

  await tick([REPO], before, deps, NOW);

  assertEquals(notes, [
    "agent-loop: acme/app triage | a が failed で終わった。クリックで会話を開く | a",
    "agent-loop: acme/app impl | c が blocked で終わった。クリックで会話を開く | c",
  ]);
});

Deno.test("見回りがリポジトリで中断したときも、人に通知する", async () => {
  const { deps, notes } = fakeDeps({ issues: new Error("gh が落ちた") });

  await tick([{ ...REPO, kinds: ["design"] }], {}, deps, NOW);

  assertEquals(notes, [
    "agent-loop: acme/app | 見回りを中断した: gh が落ちた | -",
  ]);
});
