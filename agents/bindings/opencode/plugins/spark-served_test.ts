import { assertEquals } from "jsr:@std/assert@1";
import plugin, {
  applyServed,
  BASE_URL,
  createPlugin,
  fetchServedModels,
  type ModelEditorLike,
  PROVIDER,
} from "./spark-served.ts";

type FakeModel = { id: string; enabled: boolean };

/** OpenCode V2 の ModelEditor のうちプラグインが触る部分だけを再現する fake */
function fakeEditor(ids: string[]) {
  const models: FakeModel[] = ids.map((id) => ({ id, enabled: true }));
  let defaultModel: { providerID: string; modelID: string } | undefined;
  const editor: ModelEditorLike = {
    list: (providerID) => (providerID === PROVIDER ? models : []),
    update: (providerID, modelID, update) => {
      const model = models.find((m) => providerID === PROVIDER && m.id === modelID);
      if (model) update(model);
    },
    default: {
      set: (providerID, modelID) => {
        defaultModel = { providerID, modelID };
      },
    },
  };
  return { editor, state: () => ({ models, defaultModel }) };
}

/** /v1/models の応答を返す fetch。呼ばれた URL を記録する */
function fakeFetch(respond: () => Response | Promise<Response>) {
  const urls: string[] = [];
  const fn = (input: string | URL | Request) => {
    urls.push(String(input));
    return Promise.resolve(respond());
  };
  return { fn: fn as typeof fetch, urls };
}

const modelsResponse = (...ids: string[]) =>
  new Response(JSON.stringify({ object: "list", data: ids.map((id) => ({ id, object: "model" })) }));

Deno.test("fetchServedModels_with_ok_response_returns_served_ids_from_models_endpoint", async () => {
  const fetch = fakeFetch(() => modelsResponse("GLM-5.3-Flash-EXL3"));

  const served = await fetchServedModels("http://spark.test/v1", fetch.fn);

  assertEquals(served, new Set(["GLM-5.3-Flash-EXL3"]));
  assertEquals(fetch.urls, ["http://spark.test/v1/models"]);
});

Deno.test("fetchServedModels_with_error_status_or_network_failure_returns_undefined", async () => {
  // 本文は正しい一覧でも、ステータスがエラーなら採らない
  const errorStatus = fakeFetch(() =>
    new Response(JSON.stringify({ data: [{ id: "GLM-5.3-Flash-EXL3" }] }), { status: 503 })
  );
  const networkFailure = fakeFetch(() => Promise.reject(new TypeError("connection refused")));

  assertEquals(await fetchServedModels("http://spark.test/v1", errorStatus.fn), undefined);
  assertEquals(await fetchServedModels("http://spark.test/v1", networkFailure.fn), undefined);
});

Deno.test("applyServed_with_one_served_model_enables_only_it_and_makes_it_default", () => {
  const { editor, state } = fakeEditor(["DeepSeek-v4.1-Flash-EXL3", "GLM-5.3-Flash-EXL3", "qwen3.8-flash-next"]);

  applyServed(editor, new Set(["GLM-5.3-Flash-EXL3"]));

  assertEquals(state(), {
    models: [
      { id: "DeepSeek-v4.1-Flash-EXL3", enabled: false },
      { id: "GLM-5.3-Flash-EXL3", enabled: true },
      { id: "qwen3.8-flash-next", enabled: false },
    ],
    defaultModel: { providerID: PROVIDER, modelID: "GLM-5.3-Flash-EXL3" },
  });
});

Deno.test("applyServed_when_no_declared_model_is_served_keeps_the_previous_selection", () => {
  const { editor, state } = fakeEditor(["DeepSeek-v4.1-Flash-EXL3", "GLM-5.3-Flash-EXL3"]);
  applyServed(editor, new Set(["GLM-5.3-Flash-EXL3"]));

  applyServed(editor, new Set(["undeclared-model"]));

  assertEquals(state(), {
    models: [
      { id: "DeepSeek-v4.1-Flash-EXL3", enabled: false },
      { id: "GLM-5.3-Flash-EXL3", enabled: true },
    ],
    defaultModel: { providerID: PROVIDER, modelID: "GLM-5.3-Flash-EXL3" },
  });
});

const DECLARED = ["DeepSeek-v4.1-Flash-EXL3", "GLM-5.3-Flash-EXL3"];
const [D, G] = DECLARED;
type Served = string[] | "down";

/**
 * 配信状態を 1 回の取得ごとに sequence から順に返す fetch でプラグインを起動し、
 * 起動直後と各ポーリング後の「有効なモデル」と reload 回数を記録する。
 * 有効なモデルは V2 と同じく、毎回まっさらな宣言に transform をかけ直して求める
 */
async function runPlugin(sequence: Served[]) {
  let fetched = 0;
  const fetch = fakeFetch(() => {
    const served = sequence[fetched++];
    return served === "down" ? Promise.reject(new TypeError("connection refused")) : modelsResponse(...served);
  });
  let tick: () => Promise<void> = () => Promise.resolve();
  const intervals: number[] = [];
  let cleared = false;
  const plugin = createPlugin({
    baseURL: "http://spark.test/v1",
    fetch: fetch.fn,
    setInterval: (fn, ms) => {
      tick = fn;
      intervals.push(ms);
      return 1;
    },
    clearInterval: () => {
      cleared = true;
    },
  });
  const transforms: ((editor: ModelEditorLike) => void)[] = [];
  let reloads = 0;
  const ctx = {
    model: {
      transform: (fn: (editor: ModelEditorLike) => void) => {
        transforms.push(fn);
        return Promise.resolve();
      },
      reload: () => {
        reloads++;
        return Promise.resolve();
      },
    },
  };
  const enabled = () => {
    const { editor, state } = fakeEditor(DECLARED);
    transforms.forEach((fn) => fn(editor));
    return state().models.filter((m) => m.enabled).map((m) => m.id);
  };

  const cleanup = await plugin.setup(ctx);
  const steps = [{ reloads, enabled: enabled() }];
  for (let i = 1; i < sequence.length; i++) {
    await tick();
    steps.push({ reloads, enabled: enabled() });
  }
  cleanup?.();
  return { steps, intervals, cleared };
}

const pollCases: { name: string; sequence: Served[]; steps: { reloads: number; enabled: string[] }[] }[] = [
  {
    name: "unchanged_set_does_not_reload_and_a_switch_reloads_to_the_new_model",
    sequence: [[G], [G], [D]],
    steps: [{ reloads: 0, enabled: [G] }, { reloads: 0, enabled: [G] }, { reloads: 1, enabled: [D] }],
  },
  {
    name: "fetch_failure_while_polling_keeps_the_previous_selection",
    sequence: [[G], "down"],
    steps: [{ reloads: 0, enabled: [G] }, { reloads: 0, enabled: [G] }],
  },
  {
    name: "unreachable_at_startup_keeps_all_models_then_reloads_once_reachable",
    sequence: ["down", [G]],
    steps: [{ reloads: 0, enabled: [D, G] }, { reloads: 1, enabled: [G] }],
  },
  {
    name: "served_set_shrinking_to_a_subset_reloads",
    sequence: [[D, G], [G]],
    steps: [{ reloads: 0, enabled: [D, G] }, { reloads: 1, enabled: [G] }],
  },
];

for (const c of pollCases) {
  Deno.test(`plugin_polling_${c.name}`, async () => {
    const { steps } = await runPlugin(c.sequence);

    assertEquals(steps, c.steps);
  });
}

Deno.test("plugin_polls_every_30_seconds_and_stops_polling_on_cleanup", async () => {
  const { intervals, cleared } = await runPlugin([[G]]);

  assertEquals({ intervals, cleared }, { intervals: [30_000], cleared: true });
});

Deno.test("default_export_is_an_opencode_plugin_with_id_and_setup", () => {
  assertEquals(
    { id: plugin.id, setup: typeof plugin.setup },
    { id: "local.spark-served", setup: "function" },
  );
});

Deno.test("BASE_URL_matches_the_spark_baseURL_declared_in_opencode_json", async () => {
  const config = JSON.parse(
    await Deno.readTextFile(new URL("../opencode.json", import.meta.url)),
  );

  assertEquals(BASE_URL, config.provider[PROVIDER].options.baseURL);
});
