/**
 * The extract-cards model eval. From the repository root:
 *
 *   deno run --allow-read --allow-write=tools/eval/spend.json,docs/eval --allow-net=openrouter.ai \
 *     --allow-env=OPENROUTER_API_KEY --env-file=supabase/functions/.env tools/eval/run.ts [--dry-run]
 *
 * It resolves `candidates.json` against OpenRouter's model list, estimates the run's cost,
 * and refuses to start one the remaining budget in `spend.json` cannot cover. `--dry-run`
 * stops after the estimate and calls no model.
 */

import {
  extractCards,
  type Models,
} from "../../supabase/functions/extract-cards/openrouter.ts";
import { PROMPT_VERSION } from "../../supabase/functions/extract-cards/prompt_v2.ts";
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
  spent,
  worstCallUsd,
} from "./budget.ts";
import {
  type Entry,
  type ImageResult,
  recommend,
  type Row,
  score,
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
} as const;

/** One labelled photo: its name, the image as the function receives it, its hints and cards. */
export type Sample = {
  readonly name: string;
  readonly image: Image;
  readonly languages: LanguageHints;
  readonly cards: readonly Entry[];
};

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

  const estimate = estimateUsd(
    candidates,
    samples.map((sample) => sample.cards.length),
  );
  const left = remaining(ledger);
  io.print(
    `${samples.length} samples x ${candidates.length} configurations: estimated ${
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

  const run = await runEval(candidates, samples, ledger, {
    apiKey,
    fetch: io.fetch,
    now: io.now,
    print: io.print,
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
  await io.writeText(PATHS.ledger, JSON.stringify(updated, null, 2) + "\n");
  io.print(
    `this run spent ${usd(run.spentUsd)}; ${usd(spent(updated))} of ${
      usd(updated.budgetUsd)
    } spent in total`,
  );
  if (run.stopped) {
    io.print(
      "stopped: the next call could have exceeded the remaining budget; no report was written",
    );
    return 1;
  }
  await io.writeText(
    PATHS.report,
    report(
      candidates,
      run.rows,
      samples.length,
      run.spentUsd,
      updated,
      io.today(),
    ),
  );
  io.print(`wrote ${PATHS.report}`);
  return 0;
}

type RunDeps = {
  apiKey: string;
  fetch: typeof fetch;
  now: () => number;
  print: (line: string) => void;
};

/**
 * Every candidate over every sample, one call at a time. Before each image it checks that the
 * worst case of a call and its retry still fits the remaining budget, and stops otherwise.
 */
export async function runEval(
  candidates: readonly Candidate[],
  samples: readonly Sample[],
  ledger: Ledger,
  deps: RunDeps,
): Promise<{ rows: Row[]; spentUsd: number; stopped: boolean }> {
  const rows: Row[] = [];
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
    for (const sample of samples) {
      const worst = worstCallUsd(candidate.primary.pricing) +
        worstCallUsd(candidate.retry.pricing);
      if (spentUsd + worst > remaining(ledger)) {
        return { rows, spentUsd, stopped: true };
      }
      const extraction = await extractCards(
        sample.image,
        sample.languages,
        models,
        deps,
      );
      let costUsd = 0;
      let latencyMs = 0;
      for (const attempt of extraction.attempts) {
        const model = pricing.get(attempt.model);
        if (model === undefined) {
          throw new Error(
            `a call used ${attempt.model}, which ${candidate.label} does not`,
          );
        }
        costUsd += callUsd(model.pricing, attempt.usage);
        latencyMs += attempt.latencyMs;
      }
      spentUsd += costUsd;
      const cards = extraction.kind === "cards" ? extraction.cards : [];
      results.push({ score: score(cards, sample.cards), latencyMs, costUsd });
      deps.print(
        `${candidate.label} ${sample.name}: ${extraction.kind}, ${
          usd(costUsd)
        }`,
      );
    }
    rows.push(summarize(candidate.label, results));
  }
  return { rows, spentUsd, stopped: false };
}

/** Reads every `NN-*.json` ground truth in the samples folder with the image it names. */
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
    if (
      !isRecord(truth) || typeof truth.image !== "string" ||
      !Array.isArray(truth.cards)
    ) {
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
    const bytes = await io.readBytes(`${PATHS.samples}/${truth.image}`);
    const type = truth.image.endsWith(".png")
      ? "image/png"
      : truth.image.endsWith(".webp")
      ? "image/webp"
      : "image/jpeg";
    samples.push({
      name: name.replace(/\.json$/, ""),
      image: { type, base64: encodeBase64(bytes) },
      languages: languages(truth.languages),
      cards,
    });
  }
  return samples;
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
    "- The samples are synthetic: printed pages rendered and distorted by `tools/eval/generate.py`, not phone photos.",
    "- Precision, recall and F1 are means of the per-image values, in percent; a card matches when its front and meaning equal the ground truth after card key normalization.",
    "- Over the matched cards of every image, in percent: part of speech and examples are the share equal to the page's after the same normalization; invented is the share of present parts of speech and example lists on an entry whose page prints none. A dash means the configuration returned no such field.",
    "- Latency is per image, retry included; cost per image is the mean of OpenRouter's reported cost.",
    "",
    "## Models",
    "",
    ...candidates.map((candidate) =>
      `- ${candidate.label}: ${describe(candidate)}`
    ),
    "",
    "## Results",
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
    "## Recommendation",
    "",
    pick === null
      ? "- None: no configuration completed."
      : `- ${pick.label}: the cheapest configuration whose F1 is within 2 points of the best.`,
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

if (import.meta.main) {
  Deno.exit(
    await main(Deno.args, {
      fetch,
      now: () => performance.now(),
      env: (name) => Deno.env.get(name),
      readText: (path) => Deno.readTextFile(path),
      readBytes: (path) => Deno.readFile(path),
      list: async (dir) =>
        (await Array.fromAsync(Deno.readDir(dir))).map((entry) => entry.name),
      writeText: async (path, text) => {
        await Deno.mkdir(path.slice(0, path.lastIndexOf("/")), {
          recursive: true,
        });
        await Deno.writeTextFile(path, text);
      },
      print: (line) => console.log(line),
      today: () => new Date().toISOString().slice(0, 10),
    }),
  );
}
