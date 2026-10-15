// The eval end to end with OpenRouter and the file system replaced by in-memory fakes.
import assert from "node:assert/strict";
import { OPENROUTER_URL } from "../../supabase/functions/extract-cards/openrouter.ts";
import { MODELS_URL, newest, parseModels } from "./models.ts";
import { type Io, loadSamples, main, PATHS, runEval } from "./run.ts";
import { worstCallUsd } from "./budget.ts";

const truth = [{ front: "apple", meaning: "사과", partOfSpeech: "n." }, {
  front: "river",
  meaning: "강",
}];
/** The same cards as the model writes them, one inventing an example. */
const modelCards = [
  { ...truth[0], examples: ["She ate an apple."] },
  { ...truth[1], partOfSpeech: null, examples: [] },
];
const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4, 5, 6, 7, 8]);

const model = (
  id: string,
  created: number,
  prompt = "0.000001",
  extra: Record<string, unknown> = {},
) => ({
  id,
  created,
  architecture: {
    input_modalities: ["text", "image"],
    output_modalities: ["text"],
  },
  supported_parameters: ["max_tokens", "response_format", "structured_outputs"],
  pricing: { prompt, completion: "0.000004", image: "0", request: "0" },
  ...extra,
});

const MODEL_LIST = {
  data: [
    model("vendor/cheap", 1),
    model("vendor/cheap-old", 0),
    model("vendor/dear", 2, "0.00001"),
    model("vendor/text-only", 3, "0.000001", {
      architecture: { input_modalities: ["text"] },
    }),
    model("vendor/no-schema", 4, "0.000001", {
      supported_parameters: ["response_format"],
    }),
  ],
};

type World = {
  files: Map<string, string>;
  chatCalls: string[];
  printed: string[];
  /** The cost each chat reply reports. */
  replyCost: number;
};

function world(
  ledger = { budgetUsd: 10, runs: [] as unknown[] },
  candidates?: unknown,
): World {
  const files = new Map<string, string>([
    [
      PATHS.candidates,
      JSON.stringify(
        candidates ?? [{ label: "Cheap", primary: "^vendor/cheap" }, {
          label: "Dear with cheap retry",
          primary: "^vendor/dear$",
          retry: "^vendor/cheap$",
        }],
      ),
    ],
    [PATHS.ledger, JSON.stringify(ledger)],
    [
      `${PATHS.samples}/01-a.json`,
      JSON.stringify({
        image: "01-a.jpg",
        languages: { front: "en", back: "ko" },
        cards: truth,
      }),
    ],
    [
      `${PATHS.samples}/02-b.json`,
      JSON.stringify({ image: "02-b.jpg", cards: truth }),
    ],
  ]);
  return { files, chatCalls: [], printed: [], replyCost: 0.001 };
}

function io(
  w: World,
  env: Record<string, string> = { OPENROUTER_API_KEY: "key" },
): Io {
  return {
    fetch: (input, init) => {
      const url = String(input);
      if (url === MODELS_URL) return Promise.resolve(Response.json(MODEL_LIST));
      if (url === OPENROUTER_URL) {
        const body = JSON.parse(String(init?.body));
        w.chatCalls.push(body.model);
        const cards = body.model === "vendor/dear"
          ? modelCards
          : modelCards.slice(0, 1);
        return Promise.resolve(Response.json({
          choices: [{ message: { content: JSON.stringify({ cards }) } }],
          usage: {
            prompt_tokens: 1000,
            completion_tokens: 50,
            cost: w.replyCost,
          },
        }));
      }
      throw new Error(`unexpected request to ${url}`);
    },
    now: () => 0,
    env: (name) => env[name],
    readText: (path) => {
      const text = w.files.get(path);
      return text === undefined
        ? Promise.reject(new Error(`no file ${path}`))
        : Promise.resolve(text);
    },
    readBytes: () => Promise.resolve(JPEG),
    list: () =>
      Promise.resolve(
        [...w.files.keys()].filter((p) => p.startsWith(PATHS.samples)).map((
          p,
        ) => p.slice(PATHS.samples.length + 1)),
      ),
    writeText: (path, text) => {
      w.files.set(path, text);
      return Promise.resolve();
    },
    print: (line) => w.printed.push(line),
    today: () => "2026-10-15",
  };
}

Deno.test("only models taking images with structured outputs are candidates, the newest match chosen", () => {
  const models = parseModels(MODEL_LIST);
  assert.deepEqual(models.map((m) => m.id), [
    "vendor/cheap",
    "vendor/cheap-old",
    "vendor/dear",
  ]);
  assert.equal(newest("^vendor/cheap", models)?.id, "vendor/cheap");
  assert.equal(newest("^vendor/text-only$", models), null);
});

Deno.test("a dry run prints the resolved models and the estimate, and calls no model", async () => {
  const w = world();
  assert.equal(await main(["--dry-run"], io(w, {})), 0);
  assert.equal(w.chatCalls.length, 0);
  assert.ok(
    w.printed.some((line) =>
      line.includes("`vendor/dear`") && line.includes("retry `vendor/cheap`")
    ),
  );
  assert.ok(
    w.printed.some((line) =>
      /2 samples x 2 configurations: estimated \$\d/.test(line)
    ),
  );
  assert.equal(w.files.get(PATHS.report), undefined);
});

Deno.test("a run whose estimate exceeds the remaining budget is refused before any call", async () => {
  const nearlySpent = world({
    budgetUsd: 10,
    runs: [{ date: "2026-10-01", spentUsd: 9.999, note: "" }],
  });
  assert.equal(await main([], io(nearlySpent)), 1);
  assert.equal(nearlySpent.chatCalls.length, 0);
  assert.ok(
    nearlySpent.printed.includes(
      "refused: the estimate exceeds the remaining budget",
    ),
  );
  assert.equal(
    JSON.parse(nearlySpent.files.get(PATHS.ledger) ?? "").runs.length,
    1,
    "the ledger is unchanged",
  );

  const control = world();
  assert.equal(
    await main([], io(control)),
    0,
    "control: the same run with the budget unspent",
  );
  assert.ok(control.chatCalls.length > 0);
});

Deno.test("a run records its spend in the ledger and writes the results table", async () => {
  const w = world({
    budgetUsd: 10,
    runs: [{ date: "2026-10-01", spentUsd: 1, note: "earlier" }],
  });
  assert.equal(await main([], io(w)), 0);
  assert.deepEqual(w.chatCalls, [
    "vendor/cheap",
    "vendor/cheap",
    "vendor/dear",
    "vendor/dear",
  ]);
  const ledger = JSON.parse(w.files.get(PATHS.ledger) ?? "");
  assert.deepEqual(ledger.runs.at(-1), {
    date: "2026-10-15",
    spentUsd: 0.004,
    note: "prompt v2",
  });
  assert.ok(
    w.printed.includes(
      "this run spent $0.0040; $1.0040 of $10.0000 spent in total",
    ),
  );

  const table = w.files.get(PATHS.report) ?? "";
  assert.match(
    table,
    /\| Cheap \| 100\.0 \| 50\.0 \| 66\.7 \| 100\.0 \| 0\.0 \| 50\.0 \| 0\.0 s \| 0\.0 s \| \$0\.0010 \| \$0\.0020 \|/,
  );
  assert.match(
    table,
    /\| Dear with cheap retry \| 100\.0 \| 100\.0 \| 100\.0 \|/,
  );
  assert.match(
    table,
    /- Dear with cheap retry: the cheapest configuration whose F1 is within 2 points/,
  );
  assert.match(table, /All runs: \$1\.0040 of the \$10\.0000 budget/);
});

Deno.test("a run stops before a call whose worst case could exceed the remaining budget", async () => {
  const w = world();
  const samples = await loadSamples(io(w));
  const models = parseModels(MODEL_LIST);
  const cheap = newest("^vendor/cheap$", models);
  assert.ok(cheap !== null);
  const worst = 2 * worstCallUsd(cheap.pricing);
  // Room for the worst case of the first image, and not for it again once that image spent its reply cost.
  const ledger = { budgetUsd: worst + w.replyCost / 2, runs: [] };
  const run = await runEval(
    [{ label: "Cheap", primary: cheap, retry: cheap }],
    samples,
    ledger,
    {
      apiKey: "key",
      fetch: io(w).fetch,
      now: () => 0,
      print: () => {},
    },
  );
  assert.equal(run.stopped, true);
  assert.equal(
    w.chatCalls.length,
    1,
    "the first image ran, the second did not",
  );
  assert.ok(run.spentUsd <= ledger.budgetUsd);

  const roomy = await runEval(
    [{ label: "Cheap", primary: cheap, retry: cheap }],
    samples,
    {
      budgetUsd: worst + 3 * w.replyCost,
      runs: [],
    },
    { apiKey: "key", fetch: io(world()).fetch, now: () => 0, print: () => {} },
  );
  assert.equal(roomy.stopped, false, "control: room for both images");
});

Deno.test("a candidate matching no usable model stops the run before any call", async () => {
  const w = world(undefined, [{
    label: "Gone",
    primary: "^vendor/text-only$",
  }]);
  assert.equal(await main([], io(w)), 1);
  assert.equal(w.chatCalls.length, 0);
  assert.ok(w.printed[0].includes("Gone"));
});

Deno.test("a run without OPENROUTER_API_KEY stops before any call", async () => {
  const w = world();
  assert.equal(await main([], io(w, {})), 1);
  assert.equal(w.chatCalls.length, 0);
});

Deno.test("the committed sample set has at least 20 images in every layout and language pair, with the fields each prints", async () => {
  const dir = new URL("./samples/", import.meta.url);
  const names = (await Array.fromAsync(Deno.readDir(dir))).map((entry) =>
    entry.name
  );
  const samples = await loadSamples({
    list: () => Promise.resolve(names),
    readText: (path) =>
      Deno.readTextFile(new URL(path.slice(PATHS.samples.length + 1), dir)),
    readBytes: (path) =>
      Deno.readFile(new URL(path.slice(PATHS.samples.length + 1), dir)),
  });
  assert.ok(samples.length >= 20, `${samples.length} samples`);
  for (const sample of samples) {
    assert.ok(sample.cards.length > 0, `${sample.name} has cards`);
    assert.ok(
      atob(sample.image.base64.slice(0, 4)).startsWith("\xff\xd8\xff"),
      `${sample.name} is a JPEG`,
    );
  }
  const dictionary = samples.filter((s) => s.name.includes("dictionary"));
  const others = samples.filter((s) => !s.name.includes("dictionary"));
  assert.ok(
    dictionary.every((s) => s.cards.every((c) => c.partOfSpeech !== undefined)),
    "every dictionary entry has the part of speech its page prints",
  );
  assert.ok(
    dictionary.some((s) =>
      s.cards.some((c) => /^\[.\]$/.test(c.partOfSpeech ?? ""))
    ),
    "a dictionary page prints a bracket notation such as [동]",
  );
  assert.ok(
    dictionary.some((s) => s.cards.some((c) => (c.examples ?? []).length > 0)),
    "a dictionary page prints examples",
  );
  assert.ok(
    others.every((s) =>
      s.cards.every((c) =>
        c.partOfSpeech === undefined && c.examples === undefined
      )
    ),
    "the other layouts print neither, so their truth holds neither",
  );
  for (
    const part of [
      "two-column",
      "bilingual-table",
      "dictionary",
      "glossary",
      "en-ko",
      "ja-ko",
      "handwriting",
    ]
  ) {
    assert.ok(
      samples.some((sample) => sample.name.includes(part)),
      `a sample has ${part}`,
    );
  }
});
