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
    topic: "Unit 1",
    partOfSpeech: "n.",
    examples: ["She ate an apple."],
  },
  {
    kind: "vocabulary",
    front: "river",
    answer: "강",
    topic: "Unit 1",
    partOfSpeech: null,
    examples: [],
  },
];
/** A notes page's ground truth, and the note cards a model writes for it. */
const notesTruth = {
  kind: "notes",
  facts: [
    {
      id: "deduction",
      step: 1,
      terms: ["연역", "반드시"],
      examples: ["253+4637+647898=652788 -> 연역"],
    },
    { id: "induction", step: 2, terms: ["귀납", "개연"] },
  ],
  lines: [
    "5. 연역과 귀납",
    "연역 논증: 전제가 참이면 결론이 반드시 참",
    "예) 253+4637+647898=652788 -> 연역",
  ],
};
const noteCards = [{
  kind: "note",
  front: "연역 논증",
  answer: "전제가 참이면 결론이 반드시 참인 논증",
  topic: "연역과 귀납",
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
    note: "prompt v5",
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
    note: "prompt v5",
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

Deno.test("a notes sample is scored by coverage, unsupported cards and invented examples, with no step order", async () => {
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
  // The one note card covers one of the page's two facts.
  assert.match(
    table,
    /\| Configuration \| Coverage \| Unsupported \| Invented examples \|\n/,
  );
  assert.match(table, /\| Cheap \| 50\.0 \| 0\.0 \| 0\.0 \|\n/);
  assert.doesNotMatch(table, /Step order|Coverage at/);
  assert.match(table, /\| Cheap \| 100\.0 \| 50\.0 \| 66\.7 \|/);
});

Deno.test("the report gives each notes page's coverage, with the completion tokens of its calls", async () => {
  const w = world(undefined, [{ label: "Cheap", primary: "^vendor/cheap$" }]);
  w.files.set(
    `${PATHS.samples}/03-notes.json`,
    JSON.stringify({ image: "03-notes.jpg", ...notesTruth }),
  );
  // A page whose one rule is the deduction rule the note card states.
  w.files.set(
    `${PATHS.samples}/04-notes-dense.json`,
    JSON.stringify({
      image: "04-notes-dense.jpg",
      kind: "notes",
      facts: [notesTruth.facts[0]],
      lines: notesTruth.lines,
    }),
  );
  assert.equal(await main([], io(w)), 0);
  const table = w.files.get(PATHS.report) ?? "";
  assert.match(table, /## Coverage per notes page/);
  assert.match(table, /\| Page \| Cheap \|/);
  // Each call of the fake replies with 50 completion tokens.
  assert.match(table, /\| 03-notes \| 50\.0 · 50 tokens \|/);
  assert.match(table, /\| 04-notes-dense \| 100\.0 · 50 tokens \|/);
  assert.match(table, /against the function's `max_tokens` of 16384 per call/);
});

Deno.test("a notes ground truth without facts, with a step outside 1 to 5, with examples not of text, or without its lines, is refused", async () => {
  for (
    const facts of [
      [],
      [{ id: "a", step: 6, terms: ["x"] }],
      [{ id: "a", step: 1, terms: ["x"], examples: "x" }],
      [{ id: "a", step: 1, terms: ["x"], examples: [1] }],
    ]
  ) {
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
      /notes ground truth of \{facts: \[\{id, step, terms, examples\?\}\], lines\}/,
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

/** The notes document a committed notes sample was drawn from, named between "notes-" and its hand. */
function documentOf(name: string): string {
  return name.replace(/^\d+-notes-/, "").replace(
    /-(print|handwriting)-.*$/,
    "",
  );
}

Deno.test("the committed notes samples cover Korean and English, print and handwriting, each step from 1 to 4, and only terms and examples their page prints", async () => {
  const notes = (await committedSamples()).flatMap((sample) =>
    sample.kind === "notes" ? [sample] : []
  );
  assert.equal(notes.length, 16);
  const documents = JSON.parse(
    await Deno.readTextFile(new URL("./notes.json", import.meta.url)),
  );
  for (const document of ["ko", "en", "ko-grammar", "ko-auxiliary"]) {
    const drawn = notes.filter((sample) =>
      documentOf(sample.name) === document
    );
    for (const part of ["print", "handwriting", "mild", "harsh"]) {
      assert.equal(
        drawn.filter((sample) => sample.name.includes(part)).length,
        2,
        `${document} ${part}`,
      );
    }
  }
  for (const sample of notes) {
    const page = normalize(
      documents[documentOf(sample.name)].lines.map((line: { text: string }) =>
        line.text
      ).join("\n"),
    );
    for (const step of [1, 2, 3, 4]) {
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
    for (const example of sample.notes.facts.flatMap((fact) => fact.examples)) {
      assert.ok(page.includes(normalize(example)), `${example} is printed`);
    }
    assert.deepEqual(
      sample.notes.lines,
      [
        documents[documentOf(sample.name)].title,
        ...documents[documentOf(sample.name)].lines.map((
          line: { text: string },
        ) => line.text),
      ],
      `${sample.name} holds every line its page prints`,
    );
  }
});

Deno.test("the committed notes pages count rules and exceptions as facts, each worked example an example of its rule's fact, and the dense page marks its exceptions", async () => {
  const documents = JSON.parse(
    await Deno.readTextFile(new URL("./notes.json", import.meta.url)),
  );
  const dense = documents["ko-grammar"];
  const sparse = documents["ko"];
  type Line = { text: string; kind: string; mark?: string };
  type Fact = {
    id: string;
    step: number;
    terms: string[];
    examples?: string[];
  };
  // Control: the earlier Korean page marks nothing and teaches 10 rules.
  assert.equal(sparse.lines.filter((line: Line) => line.mark).length, 0);
  assert.equal(sparse.facts.length, 10);
  assert.ok(dense.facts.length >= 2 * sparse.facts.length, "dense");
  const marked = dense.lines.filter((line: Line) => line.mark);
  assert.deepEqual(
    [...new Set(marked.map((line: Line) => line.mark))].sort(),
    ["circle", "star"],
  );
  // Every marked line is covered by a fact of its own terms.
  for (const line of marked) {
    const text = normalize(line.text);
    assert.ok(
      dense.facts.some((fact: Fact) =>
        fact.terms.every((term) => text.includes(normalize(term)))
      ),
      `a fact for: ${line.text}`,
    );
  }
  for (const name of ["ko", "en", "ko-grammar", "ko-auxiliary"]) {
    const document = documents[name];
    // No fact is a worked example: none is named as one.
    assert.ok(
      document.facts.every((fact: Fact) => !fact.id.endsWith("-example")),
      `${name} has no worked-example fact`,
    );
    // Every example line belongs to the examples of exactly one fact.
    for (
      const line of document.lines.filter((line: Line) =>
        line.kind === "example"
      )
    ) {
      const owners = document.facts.filter((fact: Fact) =>
        (fact.examples ?? []).some((example) =>
          normalize(line.text).includes(normalize(example))
        )
      );
      assert.equal(owners.length, 1, `${name}: one rule owns ${line.text}`);
    }
  }
  const samples = (await committedSamples()).filter((sample) =>
    sample.name.includes("-ko-grammar-")
  );
  assert.equal(samples.length, 4);
  for (const sample of samples) {
    assert.ok(sample.kind === "notes");
    assert.equal(sample.notes.facts.length, dense.facts.length);
  }
});

Deno.test("the committed page with the writer's additions holds a classification table, a definition with printed examples, and pen additions, and its truth makes each list one card", async () => {
  const documents = JSON.parse(
    await Deno.readTextFile(new URL("./notes.json", import.meta.url)),
  );
  const page = documents["ko-auxiliary"];
  type Line = {
    text: string;
    kind: string;
    mark?: string;
    hand?: boolean;
    header?: boolean;
  };
  type Fact = { id: string; terms: string[]; examples?: string[] };
  const lines: Line[] = page.lines;
  const rows = lines.filter((line) => line.kind === "row");
  assert.ok(rows[0].header, "the table opens with a header row");
  assert.ok(rows.length >= 4, "a header and at least three kinds");
  assert.ok(rows.every((row) => row.text.split(" | ").length === 3));
  const definition = lines.findIndex((line) =>
    line.kind === "point" && !line.hand
  );
  assert.equal(
    lines[definition + 1].kind,
    "example",
    "the definition with its printed examples",
  );
  const starred = lines.filter((line) => line.hand && line.mark === "star");
  assert.equal(starred.length, 1, "a starred list added in pen");
  const methods = lines.filter((line) =>
    line.hand && /^[12]\) /.test(line.text)
  );
  assert.equal(methods.length, 2, "numbered judgment methods added in pen");
  const aside = lines.findIndex((line) => line.kind === "aside");
  assert.equal(lines[aside - 1].kind, "heading", "a rule beside a heading");
  // Control: the earlier pages have no table and no pen additions.
  for (const name of ["ko", "en", "ko-grammar"]) {
    assert.ok(
      documents[name].lines.every((line: Line) =>
        line.kind !== "row" && line.kind !== "aside" && !line.hand
      ),
      name,
    );
  }

  const facts: Fact[] = page.facts;
  const fact = (id: string) => {
    const found = facts.find((fact) => fact.id === id);
    assert.ok(found, id);
    return found;
  };
  const holds = (line: string, terms: string[]) =>
    terms.every((term) => normalize(line).includes(normalize(term)));
  // The definition, with its printed examples.
  assert.deepEqual(fact("definition").examples, [
    lines[definition + 1].text.replace(/^예\) /, ""),
  ]);
  // The starred list as one card: every member a term of one fact.
  assert.ok(holds(starred[0].text, fact("always-auxiliary").terms));
  assert.equal(fact("always-auxiliary").terms.length, 4);
  // A table row's list as one card.
  assert.ok(
    rows.some((row) => holds(row.text, fact("auxiliary-verbs").terms)),
  );
  // Both judgment methods as one card.
  const judgment = fact("judgment").terms;
  assert.ok(
    methods.every((method) =>
      judgment.some((term) => holds(method.text, [term]))
    ),
  );
  // The rule beside the heading.
  assert.ok(holds(lines[aside].text, fact("spacing-rule").terms));
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
