// The eval end to end with OpenRouter and the file system replaced by in-memory fakes.
import assert from "node:assert/strict";
import { OPENROUTER_URL } from "../../supabase/functions/extract-cards/openrouter.ts";
import { normalize } from "./metrics.ts";
import { MODELS_URL, newest, parseModels } from "./models.ts";
import { type Io, loadSamples, main, PATHS, runEval } from "./run.ts";
import {
  estimateUsd,
  TYPICAL_NOTE_TOKENS_PER_CARD,
  TYPICAL_VOCABULARY_TOKENS_PER_CARD,
  worstCallUsd,
} from "./budget.ts";

const truth = [{ front: "apple", meaning: "사과", partOfSpeech: "n." }, {
  front: "river",
  meaning: "강",
}];
/** The same cards as the model writes them, one inventing an example. */
const modelCards = [
  {
    kind: "vocabulary",
    front: "apple",
    answer: "사과",
    short: "사과",
    step: 1,
    partOfSpeech: "n.",
    examples: ["She ate an apple."],
  },
  {
    kind: "vocabulary",
    front: "river",
    answer: "강",
    short: "강",
    step: 1,
    partOfSpeech: null,
    examples: [],
  },
];
/** A notes page's ground truth, and the note cards a model writes for it. */
const notesTruth = {
  kind: "notes",
  facts: [
    { id: "deduction", step: 1, terms: ["연역", "반드시"] },
    { id: "induction", step: 2, terms: ["귀납", "개연"] },
  ],
  examples: ["253+4637+647898=652788 -> 연역"],
  lines: [
    "5. 연역과 귀납",
    "연역 논증: 전제가 참이면 결론이 반드시 참",
    "예) 253+4637+647898=652788 -> 연역",
  ],
};
const noteCards = [{
  kind: "note",
  front: "연역 논증이란?",
  answer: "전제가 참이면 결론이 반드시 참인 논증",
  short: "결론이 반드시 참",
  step: 1,
  partOfSpeech: null,
  examples: ["253+4637+647898=652788 -> 연역"],
}];
const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4, 5, 6, 7, 8]);
/** A notes sample's image, told apart from the vocabulary ones by its bytes. */
const NOTES_JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 9, 9, 9, 9, 9, 9]);
const NOTES_IMAGE = btoa(String.fromCharCode(...NOTES_JPEG));

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
    model("vendor/broken", 5),
    model("vendor/flaky", 6),
  ],
};

type World = {
  files: Map<string, string>;
  chatCalls: string[];
  printed: string[];
  /** The cost each chat reply reports. */
  replyCost: number;
};

/** The error body OpenRouter answers a call to `vendor/broken` with, and `vendor/flaky`'s first. */
const ERROR_BODY = {
  error: { code: 400, message: "Provider returned error", metadata: {} },
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
        if (
          body.model === "vendor/broken" ||
          (body.model === "vendor/flaky" &&
            w.chatCalls.filter((m) => m === "vendor/flaky").length === 1)
        ) {
          return Promise.resolve(Response.json(ERROR_BODY, { status: 400 }));
        }
        const notes = JSON.stringify(body.messages).includes(NOTES_IMAGE);
        const cards = notes
          ? noteCards
          : body.model === "vendor/dear"
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
    readBytes: (path) =>
      Promise.resolve(path.includes("notes") ? NOTES_JPEG : JPEG),
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
    startedAt: () => "2026-10-15T04:05:06.789Z",
  };
}

Deno.test("only models taking images with structured outputs are candidates, the newest match chosen", () => {
  const models = parseModels(MODEL_LIST);
  assert.deepEqual(models.map((m) => m.id), [
    "vendor/cheap",
    "vendor/cheap-old",
    "vendor/dear",
    "vendor/broken",
    "vendor/flaky",
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
      /2 samples \(2 vocabulary, 0 notes\) x 2 configurations: estimated \$\d/
        .test(line)
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
    note: "prompt v3",
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
    /- Dear with cheap retry: the cheapest configuration whose vocabulary F1 is within 2 points/,
  );
  assert.match(table, /All runs: \$1\.0040 of the \$10\.0000 budget/);
  assert.doesNotMatch(table, /## Notes pages/, "no notes image ran");
});

/** An I/O whose write to [failing] rejects, as a missing grant does, after the paid calls. */
function failingWrite(w: World, failing: string): Io {
  const base = io(w);
  return {
    ...base,
    writeText: (path, text) =>
      path === failing
        ? Promise.reject(new Error(`no write access to ${path}`))
        : base.writeText(path, text),
  };
}

Deno.test("a failed report write still records the run in the ledger", async () => {
  const w = world();
  await assert.rejects(
    main([], failingWrite(w, PATHS.report)),
    /no write access to docs\/eval/,
  );
  assert.equal(w.chatCalls.length, 4, "the calls were made");
  assert.equal(w.files.get(PATHS.report), undefined);
  assert.deepEqual(JSON.parse(w.files.get(PATHS.ledger) ?? "").runs, [{
    date: "2026-10-15",
    spentUsd: 0.004,
    note: "prompt v3",
  }]);
});

Deno.test("the report is written before the ledger, so a failed ledger write leaves the report", async () => {
  const w = world();
  await assert.rejects(
    main([], failingWrite(w, PATHS.ledger)),
    /no write access to tools\/eval\/spend\.json/,
  );
  assert.match(w.files.get(PATHS.report) ?? "", /\| Cheap \| 100\.0 \|/);
  assert.ok(
    w.printed.includes(
      "this run spent $0.0040; $0.0040 of $10.0000 spent in total",
    ),
    "the spend is printed before either write",
  );
});

Deno.test("a run keeps each image's reply in a folder named for its start, and the report names the folder", async () => {
  const w = world();
  assert.equal(await main([], io(w)), 0);
  const folder = "tools/eval/replies/2026-10-15T04-05-06Z";
  const kept = [...w.files.keys()].filter((path) =>
    path.startsWith("tools/eval/replies/")
  ).sort();
  assert.deepEqual(kept, [
    `${folder}/cheap/01-a.json`,
    `${folder}/cheap/02-b.json`,
    `${folder}/dear-with-cheap-retry/01-a.json`,
    `${folder}/dear-with-cheap-retry/02-b.json`,
  ]);
  const reply = JSON.parse(w.files.get(`${folder}/cheap/01-a.json`) ?? "");
  assert.equal(reply.candidate, "Cheap");
  assert.equal(reply.sample, "01-a");
  assert.equal(reply.outcome, "cards");
  assert.equal(reply.cards[0].front, "apple");
  assert.equal(reply.calls.length, 1);
  assert.equal(reply.calls[0].model, "vendor/cheap");
  assert.equal(reply.calls[0].status, 200);
  assert.equal(reply.calls[0].body.usage.cost, w.replyCost);
  assert.match(
    w.files.get(PATHS.report) ?? "",
    /Every reply, its parsed cards or its error body, is kept in `tools\/eval\/replies\/2026-10-15T04-05-06Z\/`/,
  );
});

Deno.test("a candidate stops after two model errors in a row, its error bodies kept, and one error then a reply does not stop it", async () => {
  const w = world(undefined, [
    { label: "Broken", primary: "^vendor/broken$" },
    { label: "Flaky", primary: "^vendor/flaky$" },
  ]);
  w.files.set(
    `${PATHS.samples}/03-c.json`,
    JSON.stringify({ image: "03-c.jpg", cards: truth }),
  );
  assert.equal(await main([], io(w)), 0);

  assert.deepEqual(w.chatCalls, [
    "vendor/broken",
    "vendor/broken",
    "vendor/flaky",
    "vendor/flaky",
    "vendor/flaky",
  ], "Broken ran two of the three images; control: Flaky ran all three");
  const folder = "tools/eval/replies/2026-10-15T04-05-06Z";
  const broken = JSON.parse(w.files.get(`${folder}/broken/02-b.json`) ?? "");
  assert.equal(broken.outcome, "model_error");
  assert.deepEqual(broken.calls, [{
    model: "vendor/broken",
    status: 400,
    body: ERROR_BODY,
  }]);
  assert.equal(w.files.get(`${folder}/broken/03-c.json`), undefined);
  assert.ok(
    w.printed.includes(
      "Broken: stopped after 2 model errors in a row, 2 of 3 images run",
    ),
  );
  const table = w.files.get(PATHS.report) ?? "";
  assert.match(
    table,
    /- Broken stopped after 2 model errors in a row: its row covers 2 of 3 images\./,
  );
  assert.doesNotMatch(table, /- Flaky stopped/);
  assert.equal(
    JSON.parse(w.files.get(PATHS.ledger) ?? "").runs.at(-1).spentUsd,
    2 * w.replyCost,
    "a failed call reports no usage and records no spend; control: Flaky's two replies do",
  );
});

Deno.test("a notes sample is scored by coverage per step, unsupported cards, invented examples and step order", async () => {
  const w = world(undefined, [{ label: "Cheap", primary: "^vendor/cheap$" }]);
  w.files.set(
    `${PATHS.samples}/03-notes.json`,
    JSON.stringify({ image: "03-notes.jpg", ...notesTruth }),
  );
  assert.equal(await main(["--dry-run"], io(w)), 0);
  assert.ok(
    w.printed.some((line) =>
      line.startsWith("3 samples (2 vocabulary, 1 notes)")
    ),
  );
  assert.equal(await main([], io(w)), 0);
  const table = w.files.get(PATHS.report) ?? "";
  // The one note card covers the step-1 fact: all of step 1, half from step 2.
  assert.match(
    table,
    /\| Cheap \| 100\.0 \| 50\.0 \| 50\.0 \| 50\.0 \| 50\.0 \| 0\.0 \| 0\.0 \| — \|/,
  );
  assert.match(table, /\| Cheap \| 100\.0 \| 50\.0 \| 66\.7 \|/);
});

Deno.test("a notes ground truth without facts, with a step outside 1 to 5, or without its lines, is refused", async () => {
  for (const facts of [[], [{ id: "a", step: 6, terms: ["x"] }]]) {
    const w = world();
    w.files.set(
      `${PATHS.samples}/03-notes.json`,
      JSON.stringify({ image: "03-notes.jpg", ...notesTruth, facts }),
    );
    await assert.rejects(loadSamples(io(w)), /notes ground truth/);
  }
  for (const lines of [undefined, [], [1]]) {
    const w = world();
    w.files.set(
      `${PATHS.samples}/03-notes.json`,
      JSON.stringify({ image: "03-notes.jpg", ...notesTruth, lines }),
    );
    await assert.rejects(
      loadSamples(io(w)),
      /notes ground truth of \{facts: \[\{id, step, terms\}\], examples, lines\}/,
    );
  }
  const control = world();
  control.files.set(
    `${PATHS.samples}/03-notes.json`,
    JSON.stringify({ image: "03-notes.jpg", ...notesTruth }),
  );
  assert.equal((await loadSamples(io(control))).length, 3);
});

Deno.test("the dry estimate prices a note card above a vocabulary card", () => {
  const cheap = newest("^vendor/cheap$", parseModels(MODEL_LIST));
  assert.ok(cheap !== null);
  const candidate = [{ label: "Cheap", primary: cheap, retry: cheap }];
  const vocabulary = estimateUsd(candidate, [{
    cards: 10,
    tokensPerCard: TYPICAL_VOCABULARY_TOKENS_PER_CARD,
  }]);
  const notes = estimateUsd(candidate, [{
    cards: 10,
    tokensPerCard: TYPICAL_NOTE_TOKENS_PER_CARD,
  }]);
  assert.ok(notes > vocabulary);
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
      keep: () => Promise.resolve(),
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
    {
      apiKey: "key",
      fetch: io(world()).fetch,
      now: () => 0,
      print: () => {},
      keep: () => Promise.resolve(),
    },
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

Deno.test("the committed sample set has at least 20 vocabulary images in every layout and language pair, with the fields each prints", async () => {
  const samples = await committedSamples();
  const vocabulary = samples.flatMap((sample) =>
    sample.kind === "vocabulary" ? [sample] : []
  );
  assert.ok(vocabulary.length >= 20, `${vocabulary.length} vocabulary samples`);
  for (const sample of samples) {
    assert.ok(
      atob(sample.image.base64.slice(0, 4)).startsWith("\xff\xd8\xff"),
      `${sample.name} is a JPEG`,
    );
  }
  for (const sample of vocabulary) {
    assert.ok(sample.cards.length > 0, `${sample.name} has cards`);
  }
  const dictionary = vocabulary.filter((s) => s.name.includes("dictionary"));
  const others = vocabulary.filter((s) => !s.name.includes("dictionary"));
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
      vocabulary.some((sample) => sample.name.includes(part)),
      `a sample has ${part}`,
    );
  }
});

Deno.test("the committed notes samples cover Korean and English, print and handwriting, each step, and only terms and examples their page prints", async () => {
  const notes = (await committedSamples()).flatMap((sample) =>
    sample.kind === "notes" ? [sample] : []
  );
  assert.equal(notes.length, 8);
  for (
    const part of ["-ko-", "-en-", "print", "handwriting", "mild", "harsh"]
  ) {
    assert.equal(
      notes.filter((sample) => sample.name.includes(part)).length,
      4,
      part,
    );
  }
  const documents = JSON.parse(
    await Deno.readTextFile(new URL("./notes.json", import.meta.url)),
  );
  for (const sample of notes) {
    const language = sample.name.includes("-ko-") ? "ko" : "en";
    const page = normalize(
      documents[language].lines.map((line: { text: string }) => line.text)
        .join("\n"),
    );
    for (const step of [1, 2, 3, 4, 5]) {
      assert.ok(
        sample.notes.facts.some((fact) => fact.step === step),
        `${sample.name} has a fact at step ${step}`,
      );
    }
    for (const fact of sample.notes.facts) {
      for (const term of fact.terms) {
        assert.ok(
          page.includes(normalize(term)),
          `${sample.name}: ${fact.id}'s term ${term} is on the page`,
        );
      }
    }
    for (const example of sample.notes.examples) {
      assert.ok(page.includes(normalize(example)), `${example} is printed`);
    }
    assert.deepEqual(
      sample.notes.lines,
      [
        documents[language].title,
        ...documents[language].lines.map((line: { text: string }) => line.text),
      ],
      `${sample.name} holds every line its page prints`,
    );
  }
});

/** The committed samples, read from `tools/eval/samples/`. */
async function committedSamples() {
  const dir = new URL("./samples/", import.meta.url);
  const names = (await Array.fromAsync(Deno.readDir(dir))).map((entry) =>
    entry.name
  );
  return await loadSamples({
    list: () => Promise.resolve(names),
    readText: (path) =>
      Deno.readTextFile(new URL(path.slice(PATHS.samples.length + 1), dir)),
    readBytes: (path) =>
      Deno.readFile(new URL(path.slice(PATHS.samples.length + 1), dir)),
  });
}
