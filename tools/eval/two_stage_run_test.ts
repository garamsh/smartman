// The two-stage eval end to end, with OpenRouter and the file system replaced by in-memory fakes.
import assert from "node:assert/strict";
import {
  type ModelId,
  OPENROUTER_URL,
} from "../../supabase/functions/extract-cards/openrouter.ts";
import { MODELS_URL } from "./models.ts";
import { type Io, PATHS } from "./run.ts";
import { linesOf, parseTruthSections, spanText } from "./sections.ts";
import { TWO_STAGE_PROMPT } from "./two_stage.ts";
import {
  evenly,
  loadTruths,
  main,
  parseTwoStageFile,
  plan,
  TWO_STAGE_PATHS,
} from "./two_stage_run.ts";

const model = (id: string, prompt: string) => ({
  id,
  created: 1,
  architecture: { input_modalities: ["text", "image"] },
  supported_parameters: ["structured_outputs"],
  pricing: {
    prompt,
    completion: "0.000004",
    input_cache_read: "0.0000001",
    input_cache_write: "0.00000125",
  },
});
const MODEL_LIST = {
  data: [model("vendor/haiku", "0.000001"), model("vendor/sonnet", "0.00001")],
};
const CONFIGURATIONS = {
  configurations: [
    { label: "A", model: "^vendor/haiku$" },
    { label: "B", sections: "^vendor/haiku$", shapes: "^vendor/haiku$" },
    { label: "C", sections: "^vendor/sonnet$", shapes: "^vendor/haiku$" },
  ],
  judge: "^vendor/sonnet$",
};

const truthLine = (
  id: string,
  text: string,
  blank: string,
  marked: boolean,
) => {
  const start = text.indexOf(blank);
  const span = { start, end: start + [...blank].length };
  return {
    id,
    text,
    marks: marked ? [{ ...span, kind: "underline", ink: "pen" }] : [],
    blanks: [span],
  };
};
/** A page of a one-row comparison table and a list, as `generate.py` writes its truth. */
const SECTIONS = [{
  title: "여러 나라의 비교",
  language: "ko",
  content_type: "comparison_table",
  lines: [],
  table: {
    columns: ["부여", "고구려"],
    rows: [{
      header: "정치",
      cells: [
        {
          lines: [
            truthLine("s1-r1-c1-l1", "5부족 연맹체", "5부족 연맹체", true),
          ],
        },
        {
          lines: [truthLine("s1-r1-c2-l1", "5부 연맹체", "5부 연맹체", false)],
        },
      ],
    }],
  },
}, {
  title: "더 기억할 점",
  language: "ko",
  content_type: "rule_list",
  lines: [truthLine("s2-l1", "동예는 책화로 갚았다", "책화", true)],
  table: null,
}];
const STRUCTURE_TRUTH = {
  image: "02-structure.jpg",
  kind: "notes",
  languages: { front: "ko", back: "ko" },
  facts: [
    { id: "s1-r1-c1-l1", step: 1, terms: ["5부족 연맹체"] },
    { id: "s1-r1-c2-l1", step: 2, terms: ["5부 연맹체"] },
    { id: "s2-l1", step: 1, terms: ["책화"] },
  ],
  lines: [
    "초기 국가",
    "여러 나라의 비교",
    "부여",
    "고구려",
    "정치",
    "5부족 연맹체",
    "5부 연맹체",
    "더 기억할 점",
    "동예는 책화로 갚았다",
  ],
  sections: SECTIONS,
};
const VOCABULARY_TRUTH = {
  image: "01-words.jpg",
  cards: [{
    front: "apple",
    senses: [{ labels: [], meaning: "사과", examples: [] }],
  }],
};

/** Stage 1's reply for the structure page: its sections as the truth records them. */
const STAGE1 = {
  kind: "sections",
  sections: SECTIONS.map((section) => {
    const toLine = (line: ReturnType<typeof truthLine>) => ({
      id: line.id,
      text: line.text,
      marks: line.marks,
      key_terms: line.blanks.map((blank) => ({ ...blank, source: "mark" })),
    });
    return {
      ...section,
      lines: section.lines.map(toLine),
      table: section.table === null ? null : {
        ...section.table,
        rows: section.table.rows.map((row) => ({
          ...row,
          cells: row.cells.map((cell) => ({ lines: cell.lines.map(toLine) })),
        })),
      },
    };
  }),
};
const VOCABULARY_CARD = {
  kind: "vocabulary",
  type: "concept",
  front: "apple",
  answer: null,
  topic: "Words",
  senses: [{ labels: [], meaning: "사과", examples: [] }],
  extras: [],
  pronunciation: null,
  examples: [],
  table: null,
  cloze: null,
};
/** Today's single call on the structure page: one card covering a fact, one covering none. */
const NOTE_CARDS = [
  { front: "부여의 정치", answer: "5부족 연맹체" },
  { front: "삼한", answer: "벼농사" },
].map((card) => ({
  kind: "note",
  type: "concept",
  topic: "초기 국가",
  senses: [],
  extras: [],
  pronunciation: null,
  examples: [],
  table: null,
  cloze: null,
  ...card,
}));
const SHAPE_REPLIES: Record<string, unknown> = {
  table_cells: { kind: "table_cells", blanks: [{ row: 0, column: 0 }] },
  table_spans: {
    kind: "table_spans",
    blanks: [{ line_id: "s1-r1-c1-l1", start: 0, end: 7 }],
  },
  qa: {
    kind: "qa",
    cards: [
      { row: 0, column: 0, question: "부여의 정치 체제는?", composed: true },
      { row: 0, column: 1, question: "고구려의 정치 체제는?", composed: true },
    ],
  },
  // Answered for the table's cloze too, which the table's lines refuse.
  cloze: {
    kind: "cloze",
    items: [{
      line_id: "s2-l1",
      sentence: "동예는 책화로 갚았다",
      blanks: [{ start: 4, end: 6 }],
      composed: false,
    }],
  },
  vocabulary: { kind: "vocabulary", cards: [VOCABULARY_CARD] },
};

type Request = {
  model: string;
  system: string;
  content: { type: string; text?: string; cache_control?: unknown }[];
  schema: string;
};

type World = {
  files: Map<string, string>;
  requests: Request[];
  printed: string[];
  /** Stage 1 answers with an HTTP error when set. */
  failStage1?: boolean;
};

function world(budgetUsd = 10): World {
  return {
    files: new Map([
      [TWO_STAGE_PATHS.configurations, JSON.stringify(CONFIGURATIONS)],
      [PATHS.ledger, JSON.stringify({ budgetUsd, runs: [] })],
      [`${PATHS.samples}/01-words.json`, JSON.stringify(VOCABULARY_TRUTH)],
      [`${PATHS.samples}/02-structure.json`, JSON.stringify(STRUCTURE_TRUTH)],
    ]),
    requests: [],
    printed: [],
  };
}

const reply = (content: unknown, cost = 0.001) =>
  new Response(
    JSON.stringify({
      choices: [{ message: { content: JSON.stringify(content) } }],
      usage: { prompt_tokens: 100, completion_tokens: 10, cost },
    }),
    { status: 200 },
  );

function io(w: World): Io {
  let clock = 0;
  return {
    fetch: (input, init) => {
      if (String(input) === MODELS_URL) {
        return Promise.resolve(new Response(JSON.stringify(MODEL_LIST)));
      }
      assert.equal(String(input), OPENROUTER_URL);
      const body = JSON.parse(String(init?.body));
      const [system, user] = body.messages;
      const content = typeof user.content === "string"
        ? [{ type: "text", text: user.content }]
        : user.content;
      w.requests.push({
        model: body.model,
        system: system.content,
        content,
        schema: body.response_format.json_schema.name,
      });
      clock += 1000;
      const request = content.at(-1).text ?? "";
      const image: string =
        content.find((part: { type: string }) => part.type === "image_url")
          ?.image_url.url ?? "";
      const words = image.endsWith(btoa("words"));
      if (body.response_format.json_schema.name === "verdicts") {
        const count = request.split("\n").filter((line: string) =>
          /^\d+\. /.test(line)
        ).length;
        return Promise.resolve(reply({
          verdicts: Array.from({ length: count }, (_, i) => ({
            id: i + 1,
            supported: i > 0,
          })),
        }, 0.01));
      }
      if (body.response_format.json_schema.name === "cards") {
        return Promise.resolve(
          reply({ cards: words ? [VOCABULARY_CARD] : NOTE_CARDS }),
        );
      }
      if (request.startsWith("Return the page's sections")) {
        if (w.failStage1) {
          return Promise.resolve(new Response("{}", { status: 500 }));
        }
        return Promise.resolve(reply({
          reply: words
            ? {
              kind: "sections",
              sections: [{
                title: "Words",
                language: "en",
                content_type: "vocabulary_list",
                lines: [{
                  id: "w1",
                  text: "apple 사과",
                  marks: [],
                  key_terms: [],
                }],
                table: null,
              }],
            }
            : STAGE1,
        }));
      }
      const shape = /^Return the shape (\w+)/.exec(request)?.[1] ?? "";
      return Promise.resolve(reply({ reply: SHAPE_REPLIES[shape] }));
    },
    now: () => clock,
    env: (name) => name === "OPENROUTER_API_KEY" ? "key" : undefined,
    readText: (path) => {
      const text = w.files.get(path);
      return text === undefined
        ? Promise.reject(new Error(`no ${path}`))
        : Promise.resolve(text);
    },
    readBytes: (path) =>
      Promise.resolve(
        new TextEncoder().encode(path.includes("words") ? "words" : "page"),
      ),
    list: () =>
      Promise.resolve(
        [...w.files.keys()].filter((path) =>
          path.startsWith(`${PATHS.samples}/`)
        ).map((path) => path.slice(PATHS.samples.length + 1)),
      ),
    writeText: (path, text) => {
      w.files.set(path, text);
      return Promise.resolve();
    },
    print: (line) => w.printed.push(line),
    today: () => "2026-10-27",
    startedAt: () => "2026-10-27T01:02:03.456Z",
  };
}

Deno.test("a dry run prints each configuration's planned calls by step and its estimate, and calls no model", async () => {
  const w = world();
  assert.equal(await main(["--dry-run"], io(w)), 0);
  assert.equal(w.requests.length, 0);
  const lines = w.printed.join("\n");
  // The model list's cache prices are read, not the prompt's.
  assert.match(
    lines,
    /judge: `vendor\/sonnet` \(\$10\.0000\/M prompt, \$4\.0000\/M completion, \$0\.1000\/M cache read\)/,
  );
  // A: one call a page. B and C: stage 1 a page; the table's four shapes, the list's cloze and
  // the vocabulary list's one shape; and the judge on the one notes page.
  assert.match(
    lines,
    /A: 2 calls \(2 single, 0 stage 1, 0 stage 2, 0 judge\), estimated \$0\.\d{4}/,
  );
  assert.match(
    lines,
    /B: 9 calls \(0 single, 2 stage 1, 6 stage 2, 1 judge\), estimated \$0\.\d{4}/,
  );
  assert.match(lines, /C: 9 calls \(0 single, 2 stage 1, 6 stage 2, 1 judge\)/);
  assert.match(
    lines,
    /2 samples \(1 with sections\) x 3 configurations: 20 calls, estimated \$\d\.\d{4}, \$10\.0000 of the \$10\.0000 budget remaining/,
  );
  const estimate = (label: string) =>
    Number(new RegExp(`${label}: .*estimated \\$(\\S+)`).exec(lines)?.[1]);
  // C's stage 1 runs on the dearer model, and its stage 2 cannot read stage 1's cache.
  assert.ok(
    estimate("C") > estimate("B"),
    `${estimate("C")} > ${estimate("B")}`,
  );
});

Deno.test("the estimate prices stage 2's photo as a cache read where stage 1 wrote it on the same model, and as a write on another", async () => {
  const truths = await loadTruths(io(world()));
  const pricing = {
    prompt: 0.000001,
    completion: 0.000004,
    image: 0,
    request: 0,
    cacheRead: 0.0000001,
    cacheWrite: 0.00000125,
  };
  const haiku = { id: "vendor/haiku" as ModelId, created: 1, pricing };
  // The same prices under another id: only the cache it cannot share differs.
  const twin = { ...haiku, id: "vendor/twin" as ModelId };
  const shared = plan(
    { label: "B", kind: "two_stage", sections: haiku, shapes: haiku },
    truths,
    haiku,
  );
  const apart = plan(
    { label: "D", kind: "two_stage", sections: twin, shapes: haiku },
    truths,
    haiku,
  );
  // Each page's first stage-2 call writes the photo's 2,500 tokens instead of reading them.
  assert.equal(
    Math.round((apart.usd - shared.usd) * 1e9),
    Math.round(2 * 2500 * (pricing.cacheWrite - pricing.cacheRead) * 1e9),
  );
});

Deno.test("a run whose estimate exceeds the remaining budget is refused before any model call", async () => {
  const w = world(0.0001);
  assert.equal(await main([], io(w)), 1);
  assert.equal(w.requests.length, 0);
  assert.ok(
    w.printed.includes("refused: the estimate exceeds the remaining budget"),
  );
});

Deno.test("a run asks stage 1 then each section's shapes, defaults first, on the photo behind one cached prefix, then the judge on text alone", async () => {
  const w = world();
  assert.equal(await main([], io(w)), 0);
  const b = w.requests.slice(2, 2 + 8);
  const asked = b.map((request) =>
    request.content.at(-1)?.text?.split("\n")[0]
  );
  assert.deepEqual(asked, [
    "Return the page's sections.",
    "Return the shape vocabulary for this section.",
    "Return the page's sections. The cards' fronts are in the language ko. Their answers are in the language ko.",
    "Return the shape table_cells for this section. The cards' fronts are in the language ko. Their answers are in the language ko.",
    "Return the shape cloze for this section. The cards' fronts are in the language ko. Their answers are in the language ko.",
    "Return the shape table_spans for this section. The cards' fronts are in the language ko. Their answers are in the language ko.",
    "Return the shape qa for this section. The cards' fronts are in the language ko. Their answers are in the language ko.",
    "Return the shape cloze for this section. The cards' fronts are in the language ko. Their answers are in the language ko.",
  ]);
  for (const request of b) {
    assert.equal(request.system, TWO_STAGE_PROMPT);
    assert.equal(request.schema, "two_stage");
    assert.equal(request.content[0].type, "image_url");
    assert.deepEqual(request.content[1].cache_control, { type: "ephemeral" });
  }
  const judge = w.requests[10];
  assert.equal(judge.schema, "verdicts");
  assert.equal(judge.model, "vendor/sonnet");
  assert.equal(judge.content.length, 1, "text alone");
  assert.match(
    judge.content[0].text ?? "",
    /1\. 부여의 정치 체제는\?\n2\. 고구려의 정치 체제는\?$/,
  );
  // C: stage 1 on its own model, stage 2 on the other.
  const c = w.requests.slice(11);
  assert.deepEqual(
    c.map((request) => request.model),
    [
      "vendor/sonnet",
      "vendor/haiku",
      "vendor/sonnet",
      ...Array(5).fill("vendor/haiku"),
      "vendor/sonnet",
    ],
  );
});

Deno.test("a run writes the report with each configuration's metrics, the decision against the single call and the sentences to check, then the ledger", async () => {
  const w = world();
  assert.equal(await main([], io(w)), 0);
  const report = w.files.get(TWO_STAGE_PATHS.report) ?? "";
  // The single call covers one of three facts, and one of its two cards covers none; B's
  // default shapes, a table card and the list's cloze, cover all three.
  assert.match(
    report,
    /\| A \| 100\.0 \| 33\.3 \| 50\.0 \| — \| \$0\.0010 \| \$0\.0020 \|/,
  );
  assert.match(report, /\| B \| 100\.0 \| 100\.0 \| 0\.0 \| — \| /);
  // B's shapes, columns in the order first asked: the table's cloze is refused, since its one
  // sentence names a list line, so 5 of 6 calls are valid; the judge finds 1 of 2 questions
  // unsupported.
  assert.match(
    report,
    /\| Configuration \| Fidelity \| vocabulary \| table_cells \| cloze \| table_spans \| qa \| Fabrication \| Composed judged \|/,
  );
  assert.match(
    report,
    /\| B \| 83\.3 \| 100\.0 \| 100\.0 \| 50\.0 \| 100\.0 \| 100\.0 \| 50\.0 \| 2 \|/,
  );
  // Stage 1 returned the truth's structure; both pen marks were blanked, and the span table
  // blanked one of the two blanks the truth names in its cells.
  assert.match(
    report,
    /\| B \| 100\.0 \| 100\.0 \| 100\.0 \| 100\.0 \| 100\.0 \| 100\.0 \| 50\.0 \| 100\.0 \|/,
  );
  assert.match(report, /\| A \| — \| — \| 1\.0 s \| 1\.0 s \|/);
  assert.match(report, /\| B \| 1\.0 s \| 1\.0 s \| 2\.0 s \| 2\.0 s \|/);
  assert.match(
    report,
    /- B: keep the single call \(coverage yes, unsupported yes, fidelity no, latency no\)\./,
  );
  assert.match(report, /\| B \| 부여의 정치 체제는\? \| unsupported \| \|/);
  const ledger = JSON.parse(w.files.get(PATHS.ledger) ?? "");
  assert.equal(ledger.runs.length, 1);
  assert.equal(ledger.runs[0].note, "two-stage eval (#414)");
  // Every call reported $0.001, and each judge call $0.01.
  assert.equal(ledger.runs[0].spentUsd, 0.038);
  assert.ok(
    w.files.has(
      `${PATHS.replies}/2026-10-27T01-02-03Z-two-stage/c/02-structure.json`,
    ),
  );
});

Deno.test("a configuration whose stage 1 fails two pages in a row runs no further page, and the report says so", async () => {
  const w = world();
  w.failStage1 = true;
  w.files.set(
    `${PATHS.samples}/03-more.json`,
    JSON.stringify({ ...VOCABULARY_TRUTH, image: "03-more.jpg" }),
  );
  assert.equal(await main([], io(w)), 0);
  const report = w.files.get(TWO_STAGE_PATHS.report) ?? "";
  assert.match(
    report,
    /- B stopped after 2 model errors in a row: its row covers 2 of 3 images\./,
  );
  // A's three calls, then two stage-1 calls each for B and C, and no stage 2.
  assert.equal(w.requests.length, 3 + 2 + 2);
});

Deno.test("two_stage.json takes single and two-stage configurations and a judge, and refuses any other entry", () => {
  // Control: the committed shape parses.
  assert.equal(parseTwoStageFile(CONFIGURATIONS).configurations.length, 3);
  for (
    const entry of [
      { label: "x", model: "a", sections: "b", shapes: "c" },
      { label: "x", sections: "b" },
      { label: "x", model: "a", retry: "b" },
      { model: "a" },
    ]
  ) {
    assert.throws(
      () => parseTwoStageFile({ ...CONFIGURATIONS, configurations: [entry] }),
      /two_stage\.json is malformed/,
      JSON.stringify(entry),
    );
  }
  assert.throws(() =>
    parseTwoStageFile({ configurations: CONFIGURATIONS.configurations })
  );
});

Deno.test("the human check spreads its sentences evenly over the run", () => {
  assert.deepEqual(evenly([1, 2, 3], 30), [1, 2, 3]);
  assert.deepEqual(evenly([0, 1, 2, 3, 4, 5, 6, 7, 8, 9], 5), [0, 2, 4, 6, 8]);
});

Deno.test("the committed structure pages are 5 documents in print and handwriting, mild and harsh, each line with its blanks and marks inside it", async () => {
  const dir = new URL("./samples/", import.meta.url);
  const names = (await Array.fromAsync(Deno.readDir(dir))).map((entry) =>
    entry.name
  );
  const truths = await loadTruths({
    list: () => Promise.resolve(names),
    readText: (path) =>
      Deno.readTextFile(new URL(path.slice(PATHS.samples.length + 1), dir)),
    readBytes: (path) =>
      Deno.readFile(new URL(path.slice(PATHS.samples.length + 1), dir)),
  });
  const structured = truths.filter((truth) => truth.sections !== null);
  assert.equal(structured.length, 20);
  assert.ok(
    structured.every((truth) => truth.sample.name.includes("-structure-")),
  );
  for (const part of ["print", "handwriting", "mild", "harsh"]) {
    assert.equal(
      structured.filter((truth) => truth.sample.name.includes(`-${part}`))
        .length,
      10,
      part,
    );
  }
  for (const { sample, sections } of structured) {
    assert.ok(sample.kind === "notes" && sections !== null);
    assert.ok(
      sections.some((section) => section.content_type === "comparison_table") ||
        sections.some((section) => section.content_type === "table"),
      `${sample.name} has a table`,
    );
    const lines = sections.flatMap(linesOf);
    const marks = lines.flatMap((line) => line.marks);
    assert.ok(marks.every((mark) => mark.ink === "pen"), "the writer's pen");
    assert.ok(marks.some((mark) => mark.kind === "underline"), "underline");
    assert.ok(marks.some((mark) => mark.kind === "circle"), "circle");
    for (const line of lines) {
      assert.ok(line.blanks.length > 0, line.text);
      // Each printed line is a fact whose terms are its blanks.
      const fact: { readonly terms: readonly string[] } | undefined = sample
        .notes.facts.find((one) => one.id === line.id);
      assert.deepEqual(
        fact?.terms,
        line.blanks.map((blank) => spanText(line.text, blank)),
      );
      assert.ok(sample.notes.lines.includes(line.text), line.text);
    }
    // A comparison table holds bullet lines in its cells: a line, not a whole cell, is the unit.
    for (
      const section of sections.filter((one) =>
        one.content_type === "comparison_table"
      )
    ) {
      assert.ok(
        section.table?.rows.some((row) =>
          row.cells.some((cell) => cell.lines.length > 1)
        ),
        `${sample.name} has a cell of several lines`,
      );
    }
  }
  assert.equal(
    structured.filter((truth) =>
      truth.sections?.some((section) =>
        section.content_type === "comparison_table"
      )
    ).length,
    12,
    "three documents of comparison tables",
  );
  // The truth parser refuses a section whose line names no blank: the committed ones all do.
  assert.equal(
    parseTruthSections([{
      ...SECTIONS[1],
      lines: [{ ...SECTIONS[1].lines[0], blanks: [] }],
    }]),
    null,
  );
});
