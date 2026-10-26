/**
 * The two-stage photo import eval (#414): today's single call against stage 1 then stage 2,
 * over every sample. From the repository root:
 *
 *   deno run --allow-read --allow-write=tools/eval/spend.json,docs/eval,tools/eval/replies \
 *     --allow-net=openrouter.ai --allow-env=OPENROUTER_API_KEY --env-file=supabase/functions/.env \
 *     tools/eval/two_stage_run.ts [--dry-run] [--preflight]
 *
 * It resolves `two_stage.json` against OpenRouter's model list, prints each configuration's
 * planned calls and estimate, with the prompt cache and without it, and refuses to start a run
 * the remaining budget in `spend.json` cannot cover without it. `--dry-run` stops after the plan
 * and calls no model. `--preflight` runs only the preflight: one stage-1 call and one call of
 * every shape, on one page.
 */

import { SYSTEM_PROMPT } from "../../supabase/functions/extract-cards/prompt_v9.ts";
import {
  cost,
  estimateUsd,
  type Ledger,
  parseLedger,
  remaining,
  spent,
  TYPICAL_PROMPT_TOKENS,
  TYPICAL_REASONING_TOKENS,
} from "./budget.ts";
import {
  type Model,
  MODELS_URL,
  newest,
  parseModels,
  type Pricing,
} from "./models.ts";
import {
  denoIo,
  type Io,
  loadSamples,
  MODEL_ERRORS_TO_STOP,
  PATHS,
  sizeOf,
  slug,
} from "./run.ts";
import {
  isRecord,
  linesOf,
  parseTruthSections,
  type Section,
} from "./sections.ts";
import { SHAPES, shapesFor } from "./shapes.ts";
import {
  type Configuration,
  OutOfBudget,
  type PageRun,
  type PageTruth,
  plannedLines,
  plannedSections,
  preflight,
  preflightSection,
  runSingle,
  runTwoStage,
  SECTIONS_FORMAT,
  type TwoStageDeps,
  TYPICAL_LINE_TOKENS,
  TYPICAL_SHAPE_TOKENS_PER_LINE,
  TYPICAL_VERDICT_TOKENS,
  Wallet,
} from "./two_stage.ts";
import {
  decide,
  type PageResult,
  summarizePages,
  type TwoStageRow,
} from "./two_stage_metrics.ts";

export const TWO_STAGE_PATHS = {
  configurations: "tools/eval/two_stage.json",
  report: "docs/eval/two-stage.md",
} as const;

/** How many composed sentences the report lists for the PM's check by hand. */
export const HUMAN_CHECK_SIZE = 30;

/** A configuration as `two_stage.json` states it, by model patterns. */
export type ConfigurationSelector =
  | { readonly label: string; readonly model: string }
  | {
    readonly label: string;
    readonly sections: string;
    readonly shapes: string;
  };

export type TwoStageFile = {
  readonly configurations: readonly ConfigurationSelector[];
  readonly judge: string;
};

export function parseTwoStageFile(value: unknown): TwoStageFile {
  const malformed = (detail: string) =>
    new Error(`two_stage.json is malformed: ${detail}`);
  if (
    !isRecord(value) || !Array.isArray(value.configurations) ||
    value.configurations.length === 0 || typeof value.judge !== "string"
  ) throw malformed("it needs configurations and a judge");
  const configurations = value.configurations.map(
    (entry: unknown): ConfigurationSelector => {
      if (isRecord(entry) && typeof entry.label === "string") {
        const keys = Object.keys(entry).sort().join(",");
        if (keys === "label,model" && typeof entry.model === "string") {
          return { label: entry.label, model: entry.model };
        }
        if (
          keys === "label,sections,shapes" &&
          typeof entry.sections === "string" &&
          typeof entry.shapes === "string"
        ) {
          return {
            label: entry.label,
            sections: entry.sections,
            shapes: entry.shapes,
          };
        }
      }
      throw malformed(JSON.stringify(entry));
    },
  );
  return { configurations, judge: value.judge };
}

/** Every configuration and the judge resolved, or the patterns no usable model matched. */
export function resolveFile(
  file: TwoStageFile,
  models: readonly Model[],
): { readonly configurations: Configuration[]; readonly judge: Model } | {
  readonly unresolved: string[];
} {
  const unresolved: string[] = [];
  const pick = (pattern: string) => {
    const model = newest(pattern, models);
    if (model === null) unresolved.push(pattern);
    return model;
  };
  const configurations: Configuration[] = [];
  for (const selector of file.configurations) {
    if ("model" in selector) {
      const model = pick(selector.model);
      if (model !== null) {
        configurations.push({ label: selector.label, kind: "single", model });
      }
      continue;
    }
    const sections = pick(selector.sections);
    const shapes = pick(selector.shapes);
    if (sections !== null && shapes !== null) {
      configurations.push({
        label: selector.label,
        kind: "two_stage",
        sections,
        shapes,
      });
    }
  }
  const judge = pick(file.judge);
  return unresolved.length > 0 || judge === null
    ? { unresolved }
    : { configurations, judge };
}

/** Every sample with the sections its ground truth records, when it records any. */
export async function loadTruths(
  io: Pick<Io, "list" | "readText" | "readBytes">,
): Promise<PageTruth[]> {
  const samples = await loadSamples(io);
  const truths: PageTruth[] = [];
  for (const sample of samples) {
    const truth: unknown = JSON.parse(
      await io.readText(`${PATHS.samples}/${sample.name}.json`),
    );
    if (!isRecord(truth) || truth.sections === undefined) {
      truths.push({ sample, sections: null });
      continue;
    }
    const sections = parseTruthSections(truth.sections);
    if (sections === null) {
      throw new Error(
        `${sample.name} holds sections that are not stage 1's shape with blanks`,
      );
    }
    truths.push({ sample, sections });
  }
  return truths;
}

/**
 * The calls a configuration is planned to make over the samples, by step, and their estimate with
 * the prompt cache and without it.
 */
export type Plan = {
  readonly label: string;
  readonly single: number;
  readonly sections: number;
  readonly shapes: number;
  readonly judge: number;
  readonly cachedUsd: number;
  readonly uncachedUsd: number;
};

/** A stage-1 call on a page of [lines], its prefix aside: it transcribes each line. */
function sectionsUsd(pricing: Pricing, lines: number): number {
  return cost(
    pricing,
    0,
    TYPICAL_REASONING_TOKENS + lines * TYPICAL_LINE_TOKENS,
  );
}

/** A stage-2 call on a section of [lines], its prefix aside: it is sent and writes each line. */
function shapeUsd(pricing: Pricing, lines: number): number {
  return cost(
    pricing,
    lines * TYPICAL_LINE_TOKENS,
    TYPICAL_REASONING_TOKENS + lines * TYPICAL_SHAPE_TOKENS_PER_LINE,
  );
}

/**
 * The dry estimate of [configuration] over [truths]. A single call is priced as `run.ts` prices
 * it. Every two-stage call sends the system prompt and the photo, `TYPICAL_PROMPT_TOKENS`, ahead
 * of a cache breakpoint. Without the cache, each writes that prefix. With it, a call reads the
 * prefix where an earlier call of the page sent the same model and the same reply schema, since
 * the schema sits ahead of the messages, and writes it otherwise. Stage 1 transcribes
 * `TYPICAL_LINE_TOKENS` a line; each stage-2 call is sent its section's lines and writes
 * `TYPICAL_SHAPE_TOKENS_PER_LINE` a line. Every call adds `TYPICAL_REASONING_TOKENS`. The judge
 * reads a notes page's lines and a sentence for each cloze line and question, and writes
 * `TYPICAL_VERDICT_TOKENS` a sentence.
 */
export function plan(
  configuration: Configuration,
  truths: readonly PageTruth[],
  judge: Model,
): Plan {
  if (configuration.kind === "single") {
    const usd = estimateUsd(
      [{ label: configuration.label, primary: configuration.model }],
      truths.map((truth) => sizeOf(truth.sample)),
    );
    return {
      label: configuration.label,
      single: truths.length,
      sections: 0,
      shapes: 0,
      judge: 0,
      cachedUsd: usd,
      uncachedUsd: usd,
    };
  }
  let cachedUsd = 0;
  let uncachedUsd = 0;
  let shapes = 0;
  let judgeCalls = 0;
  for (const truth of truths) {
    const written = new Set<string>();
    const call = (model: Model, format: string, usd: number) => {
      const key = `${model.id} ${format}`;
      const prefix = written.has(key)
        ? model.pricing.cacheRead
        : model.pricing.cacheWrite;
      written.add(key);
      cachedUsd += usd + prefix * TYPICAL_PROMPT_TOKENS;
      uncachedUsd += usd + model.pricing.cacheWrite * TYPICAL_PROMPT_TOKENS;
    };
    const lines = plannedLines(truth);
    call(
      configuration.sections,
      SECTIONS_FORMAT.name,
      sectionsUsd(configuration.sections.pricing, lines),
    );
    let composed = 0;
    for (const section of plannedSections(truth)) {
      for (const shape of shapesFor(section.content_type)) {
        call(
          configuration.shapes,
          shape,
          shapeUsd(configuration.shapes.pricing, section.lines),
        );
        if (shape === "cloze") composed += section.lines;
        if (shape === "qa") composed += section.cells;
        shapes += 1;
      }
    }
    if (truth.sample.kind === "notes" && composed > 0) {
      judgeCalls += 1;
      const usd = cost(
        judge.pricing,
        (lines + composed) * TYPICAL_LINE_TOKENS,
        TYPICAL_REASONING_TOKENS + composed * TYPICAL_VERDICT_TOKENS,
      );
      cachedUsd += usd;
      uncachedUsd += usd;
    }
  }
  return {
    label: configuration.label,
    single: 0,
    sections: truths.length,
    shapes,
    judge: judgeCalls,
    cachedUsd,
    uncachedUsd,
  };
}

/**
 * The estimate of the preflight: stage 1 on [truth], and every shape of [section], each call
 * writing its prefix, since no two of them send the same schema.
 */
export function preflightUsd(
  configuration: Extract<Configuration, { kind: "two_stage" }>,
  truth: PageTruth,
  section: Section,
): number {
  const prefix = (model: Model) =>
    model.pricing.cacheWrite * TYPICAL_PROMPT_TOKENS;
  return sectionsUsd(configuration.sections.pricing, plannedLines(truth)) +
    prefix(configuration.sections) +
    SHAPES.length * (
        shapeUsd(configuration.shapes.pricing, linesOf(section).length) +
        prefix(configuration.shapes)
      );
}

/** One configuration's pages, and the composed sentences with the judge's verdicts. */
type ConfigurationRun = {
  readonly configuration: Configuration;
  readonly pages: readonly PageResult[];
  readonly composed: PageRun["composed"];
  /** Set when the configuration stopped after model errors in a row. */
  readonly halted: boolean;
};

/**
 * Every configuration over every page, one call at a time, each page's calls kept as it
 * completes. A configuration whose first call fails `MODEL_ERRORS_TO_STOP` pages in a row runs no
 * further page; a call whose worst case may not fit the budget stops the run.
 */
export async function runAll(
  configurations: readonly Configuration[],
  truths: readonly PageTruth[],
  deps: TwoStageDeps & {
    readonly print: (line: string) => void;
    readonly keep: (path: string, run: unknown) => Promise<void>;
  },
): Promise<{ readonly runs: ConfigurationRun[]; readonly stopped: boolean }> {
  const runs: ConfigurationRun[] = [];
  for (const configuration of configurations) {
    const pages: PageResult[] = [];
    const composed: PageRun["composed"][number][] = [];
    let errorsInRow = 0;
    let halted = false;
    for (const truth of truths) {
      if (errorsInRow === MODEL_ERRORS_TO_STOP) {
        halted = true;
        deps.print(
          `${configuration.label}: stopped after ${MODEL_ERRORS_TO_STOP} model errors in a row, ${pages.length} of ${truths.length} images run`,
        );
        break;
      }
      let run: PageRun;
      try {
        run = configuration.kind === "single"
          ? await runSingle(configuration, truth, deps)
          : await runTwoStage(configuration, truth, deps);
      } catch (error) {
        if (!(error instanceof OutOfBudget)) throw error;
        if (pages.length > 0) {
          runs.push({ configuration, pages, composed, halted });
        }
        return { runs, stopped: true };
      }
      errorsInRow = run.modelError ? errorsInRow + 1 : 0;
      pages.push(run.result);
      composed.push(...run.composed);
      await deps.keep(
        `${slug(configuration.label)}/${truth.sample.name}.json`,
        {
          configuration: configuration.label,
          sample: truth.sample.name,
          result: run.result,
          output: run.cards,
          composed: run.composed,
          calls: run.calls,
        },
      );
      deps.print(
        `${configuration.label} ${truth.sample.name}: ${
          usd(run.result.spentUsd)
        }`,
      );
    }
    if (pages.length > 0) runs.push({ configuration, pages, composed, halted });
  }
  return { runs, stopped: false };
}

/** Runs the two-stage eval and returns the process exit code. */
export async function main(args: readonly string[], io: Io): Promise<number> {
  const dryRun = args.includes("--dry-run");
  const file = parseTwoStageFile(
    JSON.parse(await io.readText(TWO_STAGE_PATHS.configurations)),
  );
  const ledger = parseLedger(JSON.parse(await io.readText(PATHS.ledger)));
  const truths = await loadTruths(io);
  if (truths.length === 0) {
    io.print(`no sample in ${PATHS.samples}/`);
    return 1;
  }
  const response = await io.fetch(MODELS_URL);
  if (!response.ok) {
    io.print(`the model list answered ${response.status}`);
    return 1;
  }
  const resolved = resolveFile(file, parseModels(await response.json()));
  if ("unresolved" in resolved) {
    io.print(
      `no model with image input and structured outputs matches: ${
        resolved.unresolved.join(", ")
      }`,
    );
    return 1;
  }
  const { configurations, judge } = resolved;
  for (const configuration of configurations) {
    io.print(`${configuration.label}: ${describe(configuration)}`);
  }
  io.print(`judge: ${model(judge)}`);
  const left = remaining(ledger);
  if (args.includes("--preflight")) {
    return await runPreflight(configurations, truths, judge, ledger, {
      io,
      dryRun,
    });
  }
  const plans = configurations.map((configuration) =>
    plan(configuration, truths, judge)
  );
  for (const one of plans) {
    io.print(
      `${one.label}: ${
        one.single + one.sections + one.shapes + one.judge
      } calls (${one.single} single, ${one.sections} stage 1, ${one.shapes} stage 2, ${one.judge} judge), estimated ${
        usd(one.cachedUsd)
      } with the cache, ${usd(one.uncachedUsd)} without`,
    );
  }
  const cached = plans.reduce((total, one) => total + one.cachedUsd, 0);
  const estimate = plans.reduce((total, one) => total + one.uncachedUsd, 0);
  const structured = truths.filter((truth) => truth.sections !== null).length;
  io.print(
    `${truths.length} samples (${structured} with sections) x ${configurations.length} configurations: ${
      plans.reduce(
        (total, one) =>
          total + one.single + one.sections + one.shapes + one.judge,
        0,
      )
    } calls, estimated ${usd(cached)} with the cache, ${
      usd(estimate)
    } without, ${usd(left)} of the ${usd(ledger.budgetUsd)} budget remaining`,
  );
  if (dryRun) return 0;
  // The budget is held to the estimate without the cache, which the run cannot rule out.
  if (estimate > left) {
    io.print("refused: the estimate exceeds the remaining budget");
    return 1;
  }
  const apiKey = readApiKey(io);
  if (apiKey === null) return 1;
  const replies = repliesFolder(io, "two-stage");
  io.print(`keeping every reply in ${replies}/`);
  const wallet = new Wallet(left);
  const loose = new Set<string>();
  const { runs, stopped } = await runAll(configurations, truths, {
    apiKey,
    fetch: io.fetch,
    now: io.now,
    wallet,
    judge,
    singlePrompt: SYSTEM_PROMPT,
    loose,
    print: io.print,
    keep: (path, run) =>
      io.writeText(`${replies}/${path}`, JSON.stringify(run, null, 2) + "\n"),
  });
  printLoose(loose, io);
  const updated: Ledger = {
    ...ledger,
    runs: [...ledger.runs, {
      date: io.today(),
      spentUsd: Math.round(wallet.spent * 1e6) / 1e6,
      note: stopped
        ? "two-stage eval (#414), stopped before exceeding the budget"
        : "two-stage eval (#414)",
    }],
  };
  io.print(
    `this run spent ${usd(wallet.spent)}; ${usd(spent(updated))} of ${
      usd(updated.budgetUsd)
    } spent in total`,
  );
  // As in run.ts: the report before the ledger, and the ledger even when the report fails.
  try {
    if (!stopped) {
      await io.writeText(
        TWO_STAGE_PATHS.report,
        report(runs, truths.length, wallet.spent, updated, io.today(), {
          replies,
          loose: [...loose],
        }),
      );
      io.print(`wrote ${TWO_STAGE_PATHS.report}`);
    }
  } finally {
    await io.writeText(PATHS.ledger, JSON.stringify(updated, null, 2) + "\n");
  }
  if (stopped) {
    io.print(
      "stopped: the next call could have exceeded the remaining budget; no report was written",
    );
    return 1;
  }
  return 0;
}

function readApiKey(io: Io): string | null {
  const apiKey = io.env("OPENROUTER_API_KEY")?.trim();
  if (apiKey !== undefined && apiKey !== "") return apiKey;
  io.print(
    "OPENROUTER_API_KEY is not set; pass --env-file=supabase/functions/.env",
  );
  return null;
}

/** The folder of `tools/eval/replies/` a run keeps its replies in, named for its start. */
function repliesFolder(io: Io, suffix: string): string {
  return `${PATHS.replies}/${
    io.startedAt().replace(/\.\d+/, "").replaceAll(":", "-")
  }-${suffix}`;
}

function printLoose(loose: ReadonlySet<string>, io: Io): void {
  io.print(
    loose.size === 0
      ? "every schema was sent with strict structured outputs"
      : `asked as plain JSON after the provider refused the schema as too large a grammar: ${
        [...loose].join(", ")
      }`,
  );
}

/**
 * The preflight: on the sample with a table and the fewest lines, one real stage-1 call and one
 * call of every shape, by the first two-stage configuration, then its spend in the ledger. It
 * refuses to start when the ledger cannot cover its estimate, and returns 0 only when every step's
 * reply was valid.
 */
async function runPreflight(
  configurations: readonly Configuration[],
  truths: readonly PageTruth[],
  judge: Model,
  ledger: Ledger,
  { io, dryRun }: { readonly io: Io; readonly dryRun: boolean },
): Promise<number> {
  const configuration = configurations.find((one) => one.kind === "two_stage");
  if (configuration === undefined || configuration.kind !== "two_stage") {
    io.print("refused: two_stage.json holds no two-stage configuration");
    return 1;
  }
  let page: { readonly truth: PageTruth; readonly section: Section } | null =
    null;
  for (const truth of truths) {
    const section = preflightSection(truth);
    if (
      section !== null &&
      (page === null || plannedLines(truth) < plannedLines(page.truth))
    ) page = { truth, section };
  }
  if (page === null) {
    io.print("refused: no sample's truth records a table");
    return 1;
  }
  const estimate = preflightUsd(configuration, page.truth, page.section);
  const left = remaining(ledger);
  io.print(
    `preflight: ${configuration.label} on ${page.truth.sample.name}, 1 stage-1 call and ${SHAPES.length} stage-2 calls (${
      SHAPES.join(", ")
    }) on its section ${page.section.title}, estimated ${usd(estimate)}, ${
      usd(left)
    } of the ${usd(ledger.budgetUsd)} budget remaining`,
  );
  if (dryRun) return 0;
  if (estimate > left) {
    io.print("refused: the estimate exceeds the remaining budget");
    return 1;
  }
  const apiKey = readApiKey(io);
  if (apiKey === null) return 1;
  const wallet = new Wallet(left);
  const loose = new Set<string>();
  let outcome: Awaited<ReturnType<typeof preflight>> | null = null;
  try {
    outcome = await preflight(configuration, page.truth, page.section, {
      apiKey,
      fetch: io.fetch,
      now: io.now,
      wallet,
      judge,
      singlePrompt: SYSTEM_PROMPT,
      loose,
    });
  } catch (error) {
    if (!(error instanceof OutOfBudget)) throw error;
    io.print(
      "stopped: the next call could have exceeded the remaining budget",
    );
  }
  if (outcome !== null) {
    const replies = repliesFolder(io, "two-stage-preflight");
    await io.writeText(
      `${replies}/${page.truth.sample.name}.json`,
      JSON.stringify(outcome.calls, null, 2) + "\n",
    );
    io.print(`kept every reply in ${replies}/`);
    for (const row of outcome.rows) {
      io.print(
        `${row.asked} on ${row.model}: ${
          row.strict ? "strict" : "plain JSON"
        }, ${row.status === null ? "no answer" : `HTTP ${row.status}`}, ${
          row.valid ? "valid" : "not valid"
        }, ${row.promptTokens ?? "—"} prompt tokens, ${
          row.cachedTokens ?? "—"
        } read from the cache, ${usd(row.usd)}`,
      );
    }
    printLoose(loose, io);
  }
  const updated: Ledger = {
    ...ledger,
    runs: [...ledger.runs, {
      date: io.today(),
      spentUsd: Math.round(wallet.spent * 1e6) / 1e6,
      note: "two-stage eval preflight (#414)",
    }],
  };
  await io.writeText(PATHS.ledger, JSON.stringify(updated, null, 2) + "\n");
  io.print(
    `the preflight spent ${usd(wallet.spent)}; ${usd(spent(updated))} of ${
      usd(updated.budgetUsd)
    } spent in total`,
  );
  const valid = outcome?.rows.filter((row) => row.valid).length ?? 0;
  return valid === 1 + SHAPES.length ? 0 : 1;
}

/**
 * [all] spread evenly when it holds more than [size], in its order: the sentences the PM checks
 * by hand.
 */
export function evenly<T>(all: readonly T[], size: number): T[] {
  if (all.length <= size) return [...all];
  return Array.from(
    { length: size },
    (_, i) => all[Math.floor((i * all.length) / size)],
  );
}

/** The committed results: each configuration's row, the decision, and the sentences to check. */
export function report(
  runs: readonly ConfigurationRun[],
  sampleCount: number,
  runUsd: number,
  ledger: Ledger,
  date: string,
  { replies, loose }: {
    readonly replies: string;
    /** The formats asked as plain JSON, by `looseKey`. */
    readonly loose: readonly string[];
  },
): string {
  const rows = runs.map((run) =>
    summarizePages(run.configuration.label, run.pages)
  );
  const today = rows.find((_, i) => runs[i].configuration.kind === "single");
  const pct = (value: number | null) =>
    value === null ? "—" : (value * 100).toFixed(1);
  const ms = (value: number | null) =>
    value === null ? "—" : `${(value / 1000).toFixed(1)} s`;
  const shapes = [
    ...new Set(rows.flatMap((row) => Object.keys(row.shapeFidelityByShape))),
  ] as (keyof TwoStageRow["shapeFidelityByShape"])[];
  const composed = runs.flatMap((run) =>
    run.composed.map((one) => ({ label: run.configuration.label, ...one }))
  );
  const yes = (value: boolean) => value ? "yes" : "no";
  return [
    "# Two-stage photo import eval",
    "",
    "Results of `tools/eval/two_stage_run.ts` (#414): today's single call against stage 1, a page's sections, then stage 2, each section's card shapes.",
    "",
    `- Run on ${date} over ${sampleCount} images in \`tools/eval/samples/\`; every reply is kept in \`${replies}/\`, which git ignores.`,
    "- Coverage, unsupported and invented examples are the notes metrics of `docs/eval/extract-cards.md`, over the cards of each section's default shape: the vocabulary cards of a vocabulary list, a table card with whole-cell blanks for a table, and one cloze sentence a line otherwise. Vocabulary F1 is that report's, over the vocabulary shape.",
    "- Structure, over the pages whose truth records sections: section F1 by title, and the shares of the truth's columns, row headers and lines stage 1 returned in place.",
    "- Mark-to-blank: recall is the share of the writer's pen underlines, circles and highlights a cloze or span-table blank on the same line asks; precision the share of those blanks on a marked line that ask a mark. Spans: the same against every blank the truth names in table cells, for the span table alone.",
    "- Shape fidelity is the share of stage-2 calls whose reply is the requested shape, valid against its section. Fabrication is the share of composed questions and sentences the judge found the page does not support.",
    "- Cost per photo is the single call, or stage 1 with each section's default shape, as OpenRouter reported it. Latency to stage 1 is its call; total latency is stage 1 and the slowest default shape, as if the sections ran at once.",
    loose.length === 0
      ? "- Every two-stage call sent its own reply schema with strict structured outputs."
      : `- Every two-stage call sent its own reply schema with strict structured outputs, but for these, asked as plain JSON and read by their parser, once more on a reply it refused, after the provider refused the schema as too large a grammar: ${
        loose.join(", ")
      }.`,
    ...runs.filter((run) => run.halted).map((run) =>
      `- ${run.configuration.label} stopped after ${MODEL_ERRORS_TO_STOP} model errors in a row: its row covers ${run.pages.length} of ${sampleCount} images.`
    ),
    "",
    "## Models",
    "",
    ...runs.map((run) =>
      `- ${run.configuration.label}: ${describe(run.configuration)}`
    ),
    "",
    "## Cards",
    "",
    "| Configuration | Vocabulary F1 | Coverage | Unsupported | Invented examples | Cost per photo | Spend |",
    "|---|---|---|---|---|---|---|",
    ...rows.map((row) =>
      `| ${row.label} | ${pct(row.vocabularyF1)} | ${pct(row.coverage)} | ${
        pct(row.unsupportedRate)
      } | ${pct(row.inventedExamplesRate)} | ${usd(row.costPerPhotoUsd)} | ${
        usd(row.spentUsd)
      } |`
    ),
    "",
    "## Structure and blanks",
    "",
    "| Configuration | Section F1 | Columns | Rows | Lines | Mark recall | Mark precision | Span recall | Span precision |",
    "|---|---|---|---|---|---|---|---|---|",
    ...rows.map((row) =>
      `| ${row.label} | ${pct(row.sectionF1)} | ${pct(row.columnMatch)} | ${
        pct(row.rowMatch)
      } | ${pct(row.lineMatch)} | ${pct(row.markRecall)} | ${
        pct(row.markPrecision)
      } | ${pct(row.spanRecall)} | ${pct(row.spanPrecision)} |`
    ),
    "",
    "## Shapes",
    "",
    `| Configuration | Fidelity | ${
      shapes.join(" | ")
    } | Fabrication | Composed judged |`,
    `|---|---|${shapes.map(() => "---|").join("")}---|---|`,
    ...rows.map((row) =>
      `| ${row.label} | ${pct(row.shapeFidelity)} | ${
        shapes.map((shape) => pct(row.shapeFidelityByShape[shape] ?? null))
          .join(" | ")
      }${shapes.length > 0 ? " | " : ""}${
        pct(row.fabricationRate)
      } | ${row.composedJudged} |`
    ),
    "",
    "## Latency",
    "",
    "| Configuration | Stage 1 p50 | Stage 1 p95 | Total p50 | Total p95 |",
    "|---|---|---|---|---|",
    ...rows.map((row) =>
      `| ${row.label} | ${ms(row.stage1P50Ms)} | ${ms(row.stage1P95Ms)} | ${
        ms(row.totalP50Ms)
      } | ${ms(row.totalP95Ms)} |`
    ),
    "",
    "## Decision",
    "",
    "A two-stage configuration is adopted only if its coverage is no more than 3 points below today's, its unsupported share at or below today's, its shape fidelity at least 95%, and its p50 latency at most 1.5 times today's.",
    "",
    ...(today === undefined
      ? ["- None: today's single call did not run."]
      : rows.filter((row) => row !== today).map((row) => {
        const decision = decide(today, row);
        return `- ${row.label}: ${
          decision.adopt ? "adopt" : "keep the single call"
        } (coverage ${yes(decision.coverage)}, unsupported ${
          yes(decision.unsupported)
        }, fidelity ${yes(decision.fidelity)}, latency ${
          yes(decision.latency)
        }).`;
      })),
    "",
    "## Human check",
    "",
    `Up to ${HUMAN_CHECK_SIZE} composed sentences, spread evenly over the run, for the PM to mark by hand against their pages.`,
    "",
    "| Configuration | Sentence | Judge | PM |",
    "|---|---|---|---|",
    ...evenly(composed, HUMAN_CHECK_SIZE).map((one) =>
      `| ${one.label} | ${one.sentence.replaceAll("|", "\\|")} | ${
        one.supported === null
          ? "—"
          : one.supported
          ? "supported"
          : "unsupported"
      } | |`
    ),
    "",
    "## Spend",
    "",
    `- This run: ${usd(runUsd)}.`,
    `- All runs: ${usd(spent(ledger))} of the ${
      usd(ledger.budgetUsd)
    } budget, recorded in \`tools/eval/spend.json\`.`,
    "",
  ].join("\n");
}

function model(m: Model): string {
  return `\`${m.id}\` (${usd(m.pricing.prompt * 1e6)}/M prompt, ${
    usd(m.pricing.completion * 1e6)
  }/M completion, ${usd(m.pricing.cacheRead * 1e6)}/M cache read)`;
}

function describe(configuration: Configuration): string {
  return configuration.kind === "single"
    ? model(configuration.model)
    : `stage 1 ${model(configuration.sections)}, stage 2 ${
      model(configuration.shapes)
    }`;
}

const usd = (value: number) => `$${value.toFixed(4)}`;

if (import.meta.main) {
  Deno.exit(await main(Deno.args, denoIo()));
}
