/**
 * The extract-cards model eval. From the repository root:
 *
 *   deno run --allow-read --allow-write=tools/eval/spend.json,docs/eval,tools/eval/replies \
 *     --allow-net=openrouter.ai --allow-env=OPENROUTER_API_KEY --env-file=supabase/functions/.env \
 *     tools/eval/run.ts [--dry-run]
 *
 * It resolves `candidates.json` against OpenRouter's model list, estimates the run's cost,
 * and refuses to start one the remaining budget in `spend.json` cannot cover. `--dry-run`
 * stops after the estimate and calls no model. Every reply is kept in a folder of
 * `tools/eval/replies/` named for the run's start, which git ignores.
 */

import { STEPS } from "../../supabase/functions/extract-cards/cards.ts";
import {
  extractCards,
  type Extraction,
  MAX_OUTPUT_TOKENS,
  type Models,
  OPENROUTER_URL,
} from "../../supabase/functions/extract-cards/openrouter.ts";
import { PROMPT_VERSION } from "../../supabase/functions/extract-cards/prompt_v4.ts";
import type {
  Image,
  LanguageHints,
  LanguageTag,
} from "../../supabase/functions/extract-cards/request.ts";
import {
  callUsd,
  estimateUsd,
  type Ledger,
  parseLedger,
  remaining,
  type SampleSize,
  spent,
  TYPICAL_NOTE_TOKENS_PER_CARD,
  TYPICAL_VOCABULARY_TOKENS_PER_CARD,
  worstCallUsd,
} from "./budget.ts";
import {
  type Entry,
  entryOf,
  type Fact,
  type ImageResult,
  type NotesTruth,
  recommend,
  type Row,
  score,
  scoreNotes,
  summarize,
} from "./metrics.ts";
import {
  type Candidate,
  type Model,
  MODELS_URL,
  parseModels,
  parseSelectors,
  resolve,
} from "./models.ts";

export const PATHS = {
  candidates: "tools/eval/candidates.json",
  ledger: "tools/eval/spend.json",
  samples: "tools/eval/samples",
  report: "docs/eval/extract-cards.md",
  replies: "tools/eval/replies",
} as const;

/** A candidate's images stop running after this many model errors in a row. */
export const MODEL_ERRORS_TO_STOP = 2;

/**
 * One labelled photo: its name, the image as the function receives it, its hints, and its
 * ground truth: a vocabulary page's cards, or a notes page's facts and examples.
 */
export type Sample =
  & {
    readonly name: string;
    readonly image: Image;
    readonly languages: LanguageHints;
  }
  & (
    | { readonly kind: "vocabulary"; readonly cards: readonly Entry[] }
    | { readonly kind: "notes"; readonly notes: NotesTruth }
  );

/** How large a sample's reply is taken to be in the dry estimate. */
export function sizeOf(sample: Sample): SampleSize {
  return sample.kind === "vocabulary"
    ? {
      cards: sample.cards.length,
      tokensPerCard: TYPICAL_VOCABULARY_TOKENS_PER_CARD,
    }
    : {
      cards: sample.notes.facts.length,
      tokensPerCard: TYPICAL_NOTE_TOKENS_PER_CARD,
    };
}

/** Everything the eval reads, writes, or calls, so a test can stand in for each. */
export type Io = {
  readonly fetch: typeof fetch;
  readonly now: () => number;
  readonly env: (name: string) => string | undefined;
  readonly readText: (path: string) => Promise<string>;
  readonly readBytes: (path: string) => Promise<Uint8Array>;
  readonly list: (dir: string) => Promise<string[]>;
  readonly writeText: (path: string, text: string) => Promise<void>;
  readonly print: (line: string) => void;
  /** Today's date as YYYY-MM-DD. */
  readonly today: () => string;
  /** The current UTC time as an ISO 8601 string. */
  readonly startedAt: () => string;
};

/** Runs the eval and returns the process exit code. */
export async function main(args: readonly string[], io: Io): Promise<number> {
  const dryRun = args.includes("--dry-run");
  const selectors = parseSelectors(
    JSON.parse(await io.readText(PATHS.candidates)),
  );
  const ledger = parseLedger(JSON.parse(await io.readText(PATHS.ledger)));
  const samples = await loadSamples(io);
  if (samples.length === 0) {
    io.print(`no sample in ${PATHS.samples}/`);
    return 1;
  }

  const response = await io.fetch(MODELS_URL);
  if (!response.ok) {
    io.print(`the model list answered ${response.status}`);
    return 1;
  }
  const resolved = resolve(selectors, parseModels(await response.json()));
  if (!resolved.ok) {
    io.print(
      `no model with image input and structured outputs matches: ${
        resolved.unresolved.join(", ")
      }`,
    );
    io.print(`edit ${PATHS.candidates} to name current models`);
    return 1;
  }
  const candidates = resolved.candidates;
  for (const candidate of candidates) {
    io.print(`${candidate.label}: ${describe(candidate)}`);
  }

  const estimate = estimateUsd(candidates, samples.map(sizeOf));
  const notes = samples.filter((sample) => sample.kind === "notes").length;
  const left = remaining(ledger);
  io.print(
    `${samples.length} samples (${
      samples.length - notes
    } vocabulary, ${notes} notes) x ${candidates.length} configurations: estimated ${
      usd(estimate)
    }, ` +
      `${usd(left)} of the ${usd(ledger.budgetUsd)} budget remaining`,
  );
  if (dryRun) return 0;
  if (estimate > left) {
    io.print(`refused: the estimate exceeds the remaining budget`);
    return 1;
  }
  const apiKey = io.env("OPENROUTER_API_KEY")?.trim();
  if (apiKey === undefined || apiKey === "") {
    io.print(
      "OPENROUTER_API_KEY is not set; pass --env-file=supabase/functions/.env",
    );
    return 1;
  }

  const replies = `${PATHS.replies}/${
    io.startedAt().replace(/\.\d+/, "").replaceAll(":", "-")
  }`;
  io.print(`keeping every reply in ${replies}/`);
  const run = await runEval(candidates, samples, ledger, {
    apiKey,
    fetch: io.fetch,
    now: io.now,
    print: io.print,
    keep: (path, reply) =>
      io.writeText(
        `${replies}/${path}`,
        JSON.stringify(reply, null, 2) + "\n",
      ),
  });
  const updated: Ledger = {
    ...ledger,
    runs: [...ledger.runs, {
      date: io.today(),
      spentUsd: round(run.spentUsd),
      note: run.stopped
        ? "stopped before exceeding the budget"
        : `prompt ${PROMPT_VERSION}`,
    }],
  };
  io.print(
    `this run spent ${usd(run.spentUsd)}; ${usd(spent(updated))} of ${
      usd(updated.budgetUsd)
    } spent in total`,
  );
  // The report is written before the ledger, and the ledger even when the report fails, so a
  // failed write after the paid calls loses at most one of them.
  try {
    if (!run.stopped) {
      await io.writeText(
        PATHS.report,
        report(
          candidates,
          run.rows,
          samples.length,
          run.spentUsd,
          updated,
          io.today(),
          { replies, halted: run.halted },
        ),
      );
      io.print(`wrote ${PATHS.report}`);
    }
  } finally {
    await io.writeText(PATHS.ledger, JSON.stringify(updated, null, 2) + "\n");
  }
  if (run.stopped) {
    io.print(
      "stopped: the next call could have exceeded the remaining budget; no report was written",
    );
    return 1;
  }
  return 0;
}

/** One OpenRouter call as it answered: its HTTP status and body, or the error that ended it. */
export type Call =
  | { readonly status: number; readonly body: unknown }
  | { readonly error: string };

/** What one candidate returned for one image: the parsed cards, and every call's answer. */
export type Reply = {
  readonly candidate: string;
  readonly sample: string;
  readonly outcome: Extraction["kind"];
  readonly cards: readonly unknown[];
  readonly calls: readonly ({ readonly model: string } & Call)[];
};

/** A candidate that stopped after model errors in a row, and how many images it ran. */
export type Halt = { readonly label: string; readonly ran: number };

type RunDeps = {
  apiKey: string;
  fetch: typeof fetch;
  now: () => number;
  print: (line: string) => void;
  /** Stores one image's reply at [path], relative to the run's replies folder. */
  keep: (path: string, reply: Reply) => Promise<void>;
};

/**
 * Every candidate over every sample, one call at a time. Before each image it checks that the
 * worst case of a call and its retry still fits the remaining budget, and stops otherwise. A
 * candidate whose calls fail `MODEL_ERRORS_TO_STOP` images in a row runs no further image.
 * Each image's reply is kept as it completes.
 */
export async function runEval(
  candidates: readonly Candidate[],
  samples: readonly Sample[],
  ledger: Ledger,
  deps: RunDeps,
): Promise<
  { rows: Row[]; spentUsd: number; stopped: boolean; halted: Halt[] }
> {
  const rows: Row[] = [];
  const halted: Halt[] = [];
  let spentUsd = 0;
  for (const candidate of candidates) {
    const models: Models = {
      primary: candidate.primary.id,
      retry: candidate.retry.id,
    };
    const pricing = new Map<string, Model>([[
      candidate.primary.id,
      candidate.primary,
    ], [
      candidate.retry.id,
      candidate.retry,
    ]]);
    const results: ImageResult[] = [];
    let errorsInRow = 0;
    for (const sample of samples) {
      if (errorsInRow === MODEL_ERRORS_TO_STOP) {
        halted.push({ label: candidate.label, ran: results.length });
        deps.print(
          `${candidate.label}: stopped after ${MODEL_ERRORS_TO_STOP} model errors in a row, ${results.length} of ${samples.length} images run`,
        );
        break;
      }
      const worst = worstCallUsd(candidate.primary.pricing) +
        worstCallUsd(candidate.retry.pricing);
      if (spentUsd + worst > remaining(ledger)) {
        return { rows, spentUsd, stopped: true, halted };
      }
      const calls: Call[] = [];
      const extraction = await extractCards(
        sample.image,
        sample.languages,
        models,
        { ...deps, fetch: recording(deps.fetch, calls) },
      );
      errorsInRow = extraction.kind === "model_error" ? errorsInRow + 1 : 0;
      let costUsd = 0;
      let latencyMs = 0;
      let completionTokens = 0;
      for (const attempt of extraction.attempts) {
        const model = pricing.get(attempt.model);
        if (model === undefined) {
          throw new Error(
            `a call used ${attempt.model}, which ${candidate.label} does not`,
          );
        }
        costUsd += callUsd(model.pricing, attempt.usage);
        latencyMs += attempt.latencyMs;
        completionTokens += attempt.usage?.completionTokens ?? 0;
      }
      spentUsd += costUsd;
      const cards = extraction.kind === "cards" ? extraction.cards : [];
      await deps.keep(`${slug(candidate.label)}/${sample.name}.json`, {
        candidate: candidate.label,
        sample: sample.name,
        outcome: extraction.kind,
        cards,
        calls: extraction.attempts.map((attempt, i) => ({
          model: attempt.model,
          ...(calls[i] ?? { error: "no answer was recorded" }),
        })),
      });
      results.push({
        name: sample.name,
        score: sample.kind === "vocabulary"
          ? score(cards.map(entryOf), sample.cards)
          : null,
        notes: sample.kind === "notes" ? scoreNotes(cards, sample.notes) : null,
        latencyMs,
        costUsd,
        completionTokens,
      });
      deps.print(
        `${candidate.label} ${sample.name}: ${extraction.kind}, ${
          usd(costUsd)
        }`,
      );
    }
    rows.push(summarize(candidate.label, results));
  }
  return { rows, spentUsd, stopped: false, halted };
}

/** [send], recording each OpenRouter call's status and body, or its error, into [calls]. */
function recording(send: typeof fetch, calls: Call[]): typeof fetch {
  return async (input, init) => {
    if (String(input) !== OPENROUTER_URL) return send(input, init);
    let response: Response;
    try {
      response = await send(input, init);
    } catch (error) {
      calls.push({ error: String(error) });
      throw error;
    }
    const text = await response.clone().text();
    let body: unknown = text;
    try {
      body = JSON.parse(text);
    } catch {
      // A body that is not JSON is kept as its text.
    }
    calls.push({ status: response.status, body });
    return response;
  };
}

/** A configuration's label as a folder name: lower case, runs of other characters as one dash. */
function slug(label: string): string {
  return label.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
}

/**
 * Reads every `NN-*.json` ground truth in the samples folder with the image it names: a
 * vocabulary page's `cards`, or, with `kind` "notes", a notes page's `facts` and `examples`.
 */
export async function loadSamples(
  io: Pick<Io, "list" | "readText" | "readBytes">,
): Promise<Sample[]> {
  const names = (await io.list(PATHS.samples)).filter((name) =>
    name.endsWith(".json")
  ).sort();
  const samples: Sample[] = [];
  for (const name of names) {
    const truth: unknown = JSON.parse(
      await io.readText(`${PATHS.samples}/${name}`),
    );
    if (!isRecord(truth) || typeof truth.image !== "string") {
      throw new Error(`${name} is not a ground truth naming its image`);
    }
    const bytes = await io.readBytes(`${PATHS.samples}/${truth.image}`);
    const type = truth.image.endsWith(".png")
      ? "image/png"
      : truth.image.endsWith(".webp")
      ? "image/webp"
      : "image/jpeg";
    const photo = {
      name: name.replace(/\.json$/, ""),
      image: { type, base64: encodeBase64(bytes) },
      languages: languages(truth.languages),
    } as const;
    if (truth.kind === "notes") {
      const notes = parseNotes(truth);
      if (notes === null) {
        throw new Error(
          `${name} is not a notes ground truth of {facts: [{id, step, terms}], examples, lines}`,
        );
      }
      samples.push({ ...photo, kind: "notes", notes });
      continue;
    }
    if (!Array.isArray(truth.cards)) {
      throw new Error(`${name} is not a ground truth of {image, cards}`);
    }
    const cards = truth.cards.map((card: unknown) => {
      const entry = parseEntry(card);
      if (entry === null) {
        throw new Error(
          `${name} holds a card that is not {front, meaning, partOfSpeech?, examples?} of text`,
        );
      }
      return entry;
    });
    samples.push({ ...photo, kind: "vocabulary", cards });
  }
  return samples;
}

function parseNotes(truth: Record<string, unknown>): NotesTruth | null {
  const { facts, examples, lines } = truth;
  if (
    !Array.isArray(facts) || facts.length === 0 || !Array.isArray(examples) ||
    !examples.every((example) => typeof example === "string") ||
    !Array.isArray(lines) || lines.length === 0 ||
    !lines.every((line) => typeof line === "string")
  ) return null;
  const parsed: Fact[] = [];
  for (const fact of facts) {
    if (!isRecord(fact) || typeof fact.id !== "string") return null;
    const step = STEPS.find((known) => known === fact.step);
    const terms = fact.terms;
    if (
      step === undefined || !Array.isArray(terms) || terms.length === 0 ||
      !terms.every((term) => typeof term === "string" && term.trim() !== "")
    ) return null;
    parsed.push({ id: fact.id, step, terms });
  }
  return { facts: parsed, examples, lines };
}

function parseEntry(card: unknown): Entry | null {
  if (
    !isRecord(card) || typeof card.front !== "string" ||
    typeof card.meaning !== "string"
  ) return null;
  const { partOfSpeech, examples } = card;
  if (partOfSpeech !== undefined && typeof partOfSpeech !== "string") {
    return null;
  }
  if (
    examples !== undefined &&
    !(Array.isArray(examples) && examples.length > 0 &&
      examples.every((example) => typeof example === "string"))
  ) return null;
  return {
    front: card.front,
    meaning: card.meaning,
    ...(partOfSpeech === undefined ? {} : { partOfSpeech }),
    ...(examples === undefined ? {} : { examples }),
  };
}

function languages(value: unknown): LanguageHints {
  if (!isRecord(value)) return {};
  const tag = (side: unknown) =>
    typeof side === "string" && /^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$/.test(side)
      ? side as LanguageTag
      : undefined;
  const front = tag(value.front);
  const back = tag(value.back);
  return {
    ...(front === undefined ? {} : { front }),
    ...(back === undefined ? {} : { back }),
  };
}

/** The committed results: one table row per configuration, and the recommendation. */
export function report(
  candidates: readonly Candidate[],
  rows: readonly Row[],
  sampleCount: number,
  runUsd: number,
  ledger: Ledger,
  date: string,
  kept: { readonly replies: string; readonly halted: readonly Halt[] },
): string {
  const pick = recommend(rows);
  const pct = (value: number) => (value * 100).toFixed(1);
  const pctOrNone = (value: number | null) => value === null ? "—" : pct(value);
  const lines = [
    "# Extract-cards model eval",
    "",
    "Results of `tools/eval/run.ts`: how each candidate configuration extracts cards from the sample set.",
    "",
    `- Run on ${date} with prompt ${PROMPT_VERSION}, over ${sampleCount} images in \`tools/eval/samples/\`.`,
    "- The samples are synthetic: printed and handwritten-style pages rendered and distorted by `tools/eval/generate.py`, not phone photos.",
    "- Vocabulary pages: precision, recall and F1 are means of the per-image values, in percent; a card matches when its front and meaning (its answer, when it has no meaning) equal the ground truth after card key normalization.",
    "- Over the matched cards of every image, in percent: part of speech and examples are the share equal to the page's after the same normalization; invented is the share of present parts of speech and example lists on an entry whose page prints none. A dash means the configuration returned no such field.",
    "- Notes pages, in percent: coverage at step s is the share of the page's facts of step s or below that a card of step s or below covers, its front, answer and examples holding each of the fact's terms after the same normalization, averaged over the images; unsupported is the share of returned cards covering no fact, which also counts a fact the model paraphrased past its terms; invented examples is the share of returned examples the page does not print; step order is the share of pairs of covered facts with different steps that the returned steps order alike, a tie counting half.",
    "- Latency is per image, retry included; cost per image is the mean of OpenRouter's reported cost, over every image.",
    `- Every reply, its parsed cards or its error body, is kept in \`${kept.replies}/\`, which git ignores.`,
    ...kept.halted.map((halt) =>
      `- ${halt.label} stopped after ${MODEL_ERRORS_TO_STOP} model errors in a row: its row covers ${halt.ran} of ${sampleCount} images.`
    ),
    "",
    "## Models",
    "",
    ...candidates.map((candidate) =>
      `- ${candidate.label}: ${describe(candidate)}`
    ),
    "",
    "## Vocabulary pages",
    "",
    "| Configuration | Precision | Recall | F1 | Part of speech | Examples | Invented | p50 latency | p90 latency | Cost per image | Total spend |",
    "|---|---|---|---|---|---|---|---|---|---|---|",
    ...rows.map((row) =>
      `| ${row.label} | ${pct(row.precision)} | ${pct(row.recall)} | ${
        pct(row.f1)
      } | ${pctOrNone(row.partOfSpeechPrecision)} | ${
        pctOrNone(row.examplesPrecision)
      } | ${pctOrNone(row.inventedRate)} | ${seconds(row.p50Ms)} | ` +
      `${seconds(row.p90Ms)} | ${usd(row.costPerImageUsd)} | ${
        usd(row.spentUsd)
      } |`
    ),
    "",
    ...notesSection(rows),
    ...pagesSection(rows),
    "## Recommendation",
    "",
    pick === null
      ? "- None: no configuration is within both bounds below, or none completed."
      : `- ${pick.label}: the cheapest configuration whose vocabulary F1 is within 2 points of the best and whose notes coverage at step 5 is within 5 points of the best.`,
    "",
    "## Spend",
    "",
    `- This run: ${usd(runUsd)}.`,
    `- All runs: ${usd(spent(ledger))} of the ${
      usd(ledger.budgetUsd)
    } budget, recorded in \`tools/eval/spend.json\`.`,
    "",
  ];
  return lines.join("\n");
}

/** The notes table, one row per configuration, or nothing when no notes image ran. */
function notesSection(rows: readonly Row[]): string[] {
  if (rows.every((row) => row.notes === null)) return [];
  const pct = (value: number | null | undefined) =>
    value === null || value === undefined ? "—" : (value * 100).toFixed(1);
  return [
    "## Notes pages",
    "",
    "| Configuration | Coverage at 1 | 2 | 3 | 4 | 5 | Unsupported | Invented examples | Step order |",
    "|---|---|---|---|---|---|---|---|---|",
    ...rows.map((row) => {
      const notes = row.notes;
      return `| ${row.label} | ${
        [0, 1, 2, 3, 4].map((at) => pct(notes?.coverage[at])).join(" | ")
      } | ${pct(notes?.unsupportedRate)} | ${
        pct(notes?.inventedExamplesRate)
      } | ${pct(notes?.stepAgreement)} |`;
    }),
    "",
  ];
}

/**
 * Coverage at step 5 of each notes page, with the completion tokens its calls used against the
 * function's output cap, one row per page and a column per configuration, or nothing when no
 * notes image ran.
 */
function pagesSection(rows: readonly Row[]): string[] {
  const names = rows.find((row) => row.notes !== null)?.notes?.pages.map((
    page,
  ) => page.name) ?? [];
  if (names.length === 0) return [];
  const pct = (value: number | null | undefined) =>
    value === null || value === undefined ? "—" : (value * 100).toFixed(1);
  return [
    "## Notes pages, coverage at step 5 per page",
    "",
    `Each cell is the page's coverage at step 5 in percent, then the completion tokens of its calls, retry included, against the function's \`max_tokens\` of ${MAX_OUTPUT_TOKENS} per call.`,
    "",
    `| Page | ${rows.map((row) => row.label).join(" | ")} |`,
    `|---|${rows.map(() => "---|").join("")}`,
    ...names.map((name) =>
      `| ${name} | ${
        rows.map((row) => {
          const page = row.notes?.pages.find((page) => page.name === name);
          return page === undefined
            ? "—"
            : `${pct(page.coverage)} · ${page.completionTokens} tokens`;
        }).join(" | ")
      } |`
    ),
    "",
  ];
}

function describe(candidate: Candidate): string {
  const model = (m: Model) =>
    `\`${m.id}\` (${usd(m.pricing.prompt * 1e6)}/M prompt, ${
      usd(m.pricing.completion * 1e6)
    }/M completion)`;
  return candidate.retry.id === candidate.primary.id
    ? model(candidate.primary)
    : `${model(candidate.primary)}, retry ${model(candidate.retry)}`;
}

const usd = (value: number) => `$${value.toFixed(4)}`;
const seconds = (ms: number) => `${(ms / 1000).toFixed(1)} s`;
const round = (value: number) => Math.round(value * 1e6) / 1e6;

function encodeBase64(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(binary);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * The eval's real I/O, as the command in this file's header runs it. A write creates its
 * directory only when the directory is missing, so writing `spend.json` needs no grant beyond
 * that file.
 */
export function denoIo(): Io {
  return {
    fetch,
    now: () => performance.now(),
    env: (name) => Deno.env.get(name),
    readText: (path) => Deno.readTextFile(path),
    readBytes: (path) => Deno.readFile(path),
    list: async (dir) =>
      (await Array.fromAsync(Deno.readDir(dir))).map((entry) => entry.name),
    writeText: async (path, text) => {
      try {
        await Deno.writeTextFile(path, text);
      } catch (error) {
        if (!(error instanceof Deno.errors.NotFound)) throw error;
        await Deno.mkdir(path.slice(0, path.lastIndexOf("/")), {
          recursive: true,
        });
        await Deno.writeTextFile(path, text);
      }
    },
    print: (line) => console.log(line),
    today: () => new Date().toISOString().slice(0, 10),
    startedAt: () => new Date().toISOString(),
  };
}

if (import.meta.main) {
  Deno.exit(await main(Deno.args, denoIo()));
}
