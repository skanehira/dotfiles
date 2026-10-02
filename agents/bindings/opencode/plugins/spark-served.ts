// OpenCode V2 のローカルプラグイン。DGX Spark が今配信しているモデルだけを有効にし、
// それを既定モデルにする。素の `opencode` を打つだけで配信中のモデルに繋がるようにするため。
//
// Spark は同時に 1 モデルしか配信せず、配信モデルは頻繁に切り替わる。opencode.json には
// 配信しうる全モデルを reasoningEffort / limit 付きで宣言してあるので、そのままだと
// 配信していないモデルが既定に選ばれうる (V2 は宣言順の先頭や「最近使ったモデル」を採る)。
// このプラグインは /v1/models を引いて、配信していないモデルを無効にする。
//
// 接続先は opencode.json の provider.spark.options.baseURL と同じ値を BASE_URL に持つ。
// プラグインの setup が走る時点では設定の provider がまだ組み立てられておらず、
// baseURL を読めないため。2 か所の一致は spark-served_test.ts が検査する。
//
// 配信モデルの切り替えには POLL_MS ごとの再取得で追従する。V2 の常駐サービスは
// 複数の TUI 起動をまたいで生き続けるので、起動時の 1 回だけでは古くなる。

export const PROVIDER = "spark";
export const BASE_URL = "http://spark-head:8888/v1";
const POLL_MS = 30_000;
const TIMEOUT_MS = 3_000;

/** OpenCode V2 の ModelEditor (@opencode/plugin) のうち、このプラグインが使う部分 */
export interface ModelEditorLike {
  list(providerID?: string): readonly { id: string; enabled: boolean }[];
  update(providerID: string, modelID: string, update: (model: { enabled: boolean }) => void): void;
  default: { set(providerID: string, modelID: string): void };
}

interface ContextLike {
  model: {
    transform(fn: (editor: ModelEditorLike) => void): Promise<unknown>;
    reload(): Promise<void>;
  };
}

/** 配信中のモデル ID の集合を返す。サーバに届かないときは undefined (直前の状態を保つ) */
export async function fetchServedModels(
  baseURL: string,
  fetchFn: typeof fetch,
): Promise<Set<string> | undefined> {
  try {
    const res = await fetchFn(`${baseURL}/models`, { signal: AbortSignal.timeout(TIMEOUT_MS) });
    if (!res.ok) return undefined;
    const body = (await res.json()) as { data: { id: string }[] };
    return new Set(body.data.map((model) => model.id));
  } catch {
    return undefined;
  }
}

/**
 * 配信中のモデルだけを有効にして既定に据える。宣言済みのモデルが 1 つも配信されて
 * いなければ何もしない (全部無効にすると選べるモデルが無くなるため)。
 */
export function applyServed(editor: ModelEditorLike, served: ReadonlySet<string>): void {
  const declared = editor.list(PROVIDER);
  if (!declared.some((model) => served.has(model.id))) return;
  for (const model of declared) {
    const isServed = served.has(model.id);
    editor.update(PROVIDER, model.id, (m) => {
      m.enabled = isServed;
    });
    if (isServed) editor.default.set(PROVIDER, model.id);
  }
}

const sameSet = (a: ReadonlySet<string>, b: ReadonlySet<string>) =>
  a.size === b.size && [...a].every((id) => b.has(id));

export function createPlugin(deps: {
  baseURL: string;
  fetch: typeof fetch;
  setInterval: (fn: () => Promise<void>, ms: number) => unknown;
  clearInterval: (id: unknown) => void;
}) {
  return {
    id: "local.spark-served",
    setup: async (ctx: ContextLike) => {
      // transform は同期なので、配信一覧は登録前に取っておく (V2 の plugin README の作法)
      let served = await fetchServedModels(deps.baseURL, deps.fetch);
      await ctx.model.transform((editor) => {
        if (served) applyServed(editor, served);
      });
      const timer = deps.setInterval(async () => {
        const next = await fetchServedModels(deps.baseURL, deps.fetch);
        if (!next || (served && sameSet(next, served))) return;
        served = next;
        await ctx.model.reload();
      }, POLL_MS);
      return () => deps.clearInterval(timer);
    },
  };
}

export default createPlugin({
  baseURL: BASE_URL,
  fetch: globalThis.fetch,
  setInterval: (fn, ms) => globalThis.setInterval(fn, ms),
  clearInterval: (id) => globalThis.clearInterval(id as number),
});
