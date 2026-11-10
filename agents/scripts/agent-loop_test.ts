import { assertEquals } from "jsr:@std/assert@1";
import {
  classifyIssues,
  decideWorktreeRemoval,
  type Deps,
  inputKey,
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

const REPO: RepoConfig = {
  slug: "acme/app",
  path: "/work/acme/app",
  kinds: ["triage", "design", "impl"],
};

/** 呼び出しを記録する fake。snapshot の中身と、セッションの一覧をテストごとに与える */
function fakeDeps(
  opts: {
    untriaged?: number[];
    issues?: RawIssue[];
    designPrBodies?: string[];
    sessions?: SessionInfo[];
  } = {},
) {
  const calls: string[] = [];
  let seq = 0;
  const deps: Deps = {
    listUntriaged: (repo) => {
      calls.push(`listUntriaged ${repo.slug}`);
      return Promise.resolve(opts.untriaged ?? []);
    },
    listIssues: (repo) => {
      calls.push(`listIssues ${repo.slug}`);
      return Promise.resolve(opts.issues ?? []);
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
      calls.push(
        `cleanup ${repo.slug} ${run.sessionId}${
          endState === "blocked" ? " keep" : ""
        }`,
      );
      return Promise.resolve();
    },
    log: () => {},
  };
  return { deps, calls };
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
  ];
  const prBodies = ["何を決めたか\n\nDesign-for: #4\n"];

  const actual = classifyIssues(issues, prBodies);

  assertEquals(actual, {
    design: [{ number: 1, updatedAt: "2026-11-11T00:00:00Z" }],
    impl: [
      { number: 5, updatedAt: "2026-11-10T00:00:00Z" },
      { number: 6, updatedAt: "2026-11-11T00:00:00Z" },
    ],
  });
});

Deno.test("inputKey は番号の順に並べ、空なら空文字を返す", () => {
  assertEquals(
    inputKey([{ number: 9, updatedAt: "b" }, { number: 2, updatedAt: "a" }]),
    "2@a,9@b",
  );
  assertEquals(inputKey([]), "");
});

Deno.test("仕事のある種類だけを起動し、起動した記録を状態に残す", async () => {
  const { deps, calls } = fakeDeps({
    untriaged: [3],
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
          inputKey: "3@",
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

Deno.test("動いているセッションがある種類は、仕事があっても起動しない", async () => {
  const { deps, calls } = fakeDeps({
    untriaged: [3, 4],
    sessions: [{ id: "s1", state: "working" }],
  });
  const before: State = {
    "acme/app": {
      running: {
        triage: {
          sessionId: "s1",
          name: "x",
          inputKey: "3@",
          startedAt: NOW - HOUR,
        },
      },
      finished: {},
    },
  };

  const state = await tick([REPO], before, deps, NOW);

  assertEquals(
    calls.filter((c) => c.startsWith("launch") || c.startsWith("cleanup")),
    [],
  );
  assertEquals(state["acme/app"].running?.triage?.sessionId, "s1");
});

Deno.test("終わったセッションを片付けて、入力が変わっていれば同じ種類を起動し直す", async () => {
  const { deps, calls } = fakeDeps({
    untriaged: [5],
    sessions: [{ id: "s1", state: "done" }],
  });
  const before: State = {
    "acme/app": {
      running: {
        triage: {
          sessionId: "s1",
          name: "x",
          inputKey: "3@",
          startedAt: NOW - HOUR,
        },
      },
      finished: {},
    },
  };

  const state = await tick([REPO], before, deps, NOW);

  assertEquals(
    calls.filter((c) => c.startsWith("launch") || c.startsWith("cleanup")),
    [
      "cleanup acme/app s1",
      "launch acme/app triage",
    ],
  );
  assertEquals(state["acme/app"].finished?.triage, {
    inputKey: "3@",
    finishedAt: NOW,
  });
  assertEquals(state["acme/app"].running?.triage?.inputKey, "5@");
});

Deno.test("一覧から消えたセッションも終わったものとして片付ける", async () => {
  const { deps, calls } = fakeDeps({ sessions: [] });
  const before: State = {
    "acme/app": {
      running: {
        impl: {
          sessionId: "gone",
          name: "x",
          inputKey: "1@a",
          startedAt: NOW - HOUR,
        },
      },
      finished: {},
    },
  };

  const state = await tick([REPO], before, deps, NOW);

  assertEquals(calls.filter((c) => c.startsWith("cleanup")), [
    "cleanup acme/app gone",
  ]);
  assertEquals(state["acme/app"].running, {});
  assertEquals(state["acme/app"].finished?.impl, {
    inputKey: "1@a",
    finishedAt: NOW,
  });
});

Deno.test("前回の run と入力が同じなら起動しないが、6 時間を過ぎたら 1 回だけ起動し直す", async () => {
  const finishedRecently: State = {
    "acme/app": {
      running: {},
      finished: { triage: { inputKey: "3@", finishedAt: NOW - HOUR } },
    },
  };
  const finishedLongAgo: State = {
    "acme/app": {
      running: {},
      finished: { triage: { inputKey: "3@", finishedAt: NOW - 6 * HOUR - 1 } },
    },
  };

  const recent = fakeDeps({ untriaged: [3] });
  await tick([REPO], finishedRecently, recent.deps, NOW);
  const old = fakeDeps({ untriaged: [3] });
  await tick([REPO], finishedLongAgo, old.deps, NOW);

  assertEquals(recent.calls.filter((c) => c.startsWith("launch")), []);
  assertEquals(old.calls.filter((c) => c.startsWith("launch")), [
    "launch acme/app triage",
  ]);
});

Deno.test("設定で外した種類は、仕事があっても起動しない", async () => {
  const { deps, calls } = fakeDeps({
    untriaged: [3],
    issues: [issue(1, ["needs-design"]), issue(2, ["ready"])],
  });

  await tick([{ ...REPO, kinds: ["design"] }], {}, deps, NOW);

  assertEquals(calls.filter((c) => c.startsWith("launch")), [
    "launch acme/app design",
  ]);
});

Deno.test("すべての種類が動いているリポジトリでは、GitHub に問い合わせない", async () => {
  const running = (id: string) => ({
    sessionId: id,
    name: id,
    inputKey: "k",
    startedAt: NOW,
  });
  const { deps, calls } = fakeDeps({
    sessions: ["a", "b", "c"].map((id) => ({ id, state: "working" })),
  });
  const before: State = {
    "acme/app": {
      running: {
        triage: running("a"),
        design: running("b"),
        impl: running("c"),
      },
      finished: {},
    },
  };

  await tick([REPO], before, deps, NOW);

  assertEquals(calls, []);
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

Deno.test("人の返事を待って止まったセッション (blocked) は終わったものとし、会話を残す片付けにする", async () => {
  const { deps, calls } = fakeDeps({
    sessions: [{ id: "s9", state: "blocked" }],
  });
  const before: State = {
    "acme/app": {
      running: {
        design: {
          sessionId: "s9",
          name: "x",
          inputKey: "1@a",
          startedAt: NOW - HOUR,
        },
      },
      finished: {},
    },
  };

  const state = await tick([REPO], before, deps, NOW);

  assertEquals(calls.filter((c) => c.startsWith("cleanup")), [
    "cleanup acme/app s9 keep",
  ]);
  assertEquals(state["acme/app"].finished?.design, {
    inputKey: "1@a",
    finishedAt: NOW,
  });
});
