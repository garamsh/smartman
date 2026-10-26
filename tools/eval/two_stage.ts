/**
 * The two-stage photo import prototype (#414): stage 1 reads a photo's sections, stage 2 makes
 * each section's card shapes from its JSON and the same photo, and a text-only judge reads the
 * sentences stage 2 composed. Every stage-1 and stage-2 call shares one system prompt, one reply
 * schema and the photo ahead of a cache breakpoint, so the calls after the first on a model read
 * the photo from the prompt cache.
 */

import type { Card } from "../../supabase/functions/extract-cards/cards.ts";
import {
  type Attempt,
  extractCards,
  MAX_OUTPUT_TOKENS,
  OPENROUTER_URL,
  type Usage,
} from "../../supabase/functions/extract-cards/openrouter.ts";
import type {
  Image,
  LanguageHints,
} from "../../supabase/functions/extract-cards/request.ts";
import { callUsd, worstCallUsd } from "./budget.ts";
import { entryOf, score, scoreNotes } from "./metrics.ts";
import type { Model } from "./models.ts";
import { type Call, recording, type Sample } from "./run.ts";
import {
  hasOnlyKeys,
  isRecord,
  linesOf,
  list,
  parseSections,
  type Section,
  sectionsSchema,
  type TruthLine,
} from "./sections.ts";
import {
  cardsOf,
  composedOf,
  type LineBlank,
  lineBlanksOf,
  parseShape,
  type Shape,
  type ShapeOutput,
  SHAPES,
  shapeSchemas,
  shapesFor,
} from "./shapes.ts";
import {
  type PageResult,
  scoreMarks,
  scoreSpans,
  scoreStructure,
} from "./two_stage_metrics.ts";

/** The instructions of every stage-1 and stage-2 call; the user turn says which to do. */
export const TWO_STAGE_PROMPT =
  `You read a photo of a study page and turn it into flashcards in two stages. Every request carries the same photo; its text says which stage to do. Answer with JSON only, matching the given schema: {"reply": ...} holding the one reply the request asks for.

Stage 1, when the request says "Return the page's sections": transcribe the page into sections, in reading order, as {"kind": "sections", "sections": [...]}.
- A section is a part of the page under one heading, or one block of it: its title as printed, or a short name for a block without one; its language as a BCP 47 tag such as "ko" or "en"; and its content_type: vocabulary_list (words with their meanings), comparison_table (a table comparing several items over the same aspects), table (any other table), rule_list (rules, definitions or facts listed), process (ordered steps), worked_examples (examples worked through), or prose.
- A comparison_table or table section holds its table and no lines. Its columns are the headers of the columns that hold cells, left to right, leaving out the column that names the rows; its rows each give their header, the text of that first column, and their cells, one per column, each holding the cell's lines. Every other section holds its lines, and its table is null.
- A line is one printed line or bullet point, its text character for character as the page shows it, without the bullet; a bullet point wrapped onto a second row is still one line. Give each line an id unique on the page, such as "s1-l3" or "s1-r2-c1-l1".
- marks: each mark on the line, underline, circle, highlight or star, its ink "pen" where a writer added it by hand and "print" where the page printed it, and the span it covers as start and end, offsets into the line's text counted in characters from 0, end exclusive. A star, or a mark on the whole line, covers the whole line.
- key_terms: the spans of the line a learner should recall, source "mark" for each span a pen underline, circle or highlight covers, every one of which is a key term, and source "model" for each you chose yourself.
- Transcribe only what is printed or written. Never add, complete, translate or correct.

Stage 2, when the request says "Return the shape <shape> for this section": the request gives one section of stage 1 as JSON. Return only that shape, as {"kind": "<shape>", ...}, made from that section and the photo:
- table_cells: the table kept whole, with the cells to recall as its blanks, each {row, column}, row counting the section's rows from 0 and column its columns from 0, the column of row headers not counted. Blank the cells holding key terms; never an empty cell.
- table_spans: the table kept whole, with blanks inside its cells, each {line_id, start, end}, a span of one cell line's text: its key terms first. One cell may hold several blanks; two blanks never overlap.
- qa: one question for each cell that holds lines, each {row, column, question, composed}, asking the row's aspect of the column's item, such as "부여의 정치 체제는?" for the cell of row 정치 under 부여. The cell's lines are its answer.
- cloze: one sentence for each line of the section, each {line_id, sentence, blanks, composed}, stating the line's fact with its key terms as blanks, each {start, end} a span of the sentence. Keep the line's own wording when it reads as a sentence on its own; otherwise write one sentence that names what the line is about, such as "부여는 5부족 연맹체였다." for the line "5부족 연맹체" in the cell of row 정치 under 부여.
- vocabulary: the section's entries as vocabulary cards, one for each headword: kind "vocabulary", type "concept", front the headword as printed, answer null, topic the section's title, senses in the page's order, each with the labels printed for it (a part of speech with its category, any other label with category null), its meaning, and the examples printed under it; extras, pronunciation and examples as the page prints them, and otherwise empty lists or null; table and cloze null.
- composed is true for any question or sentence whose wording is not printed on the page, and false only for a sentence that is its line word for word.
- Never state a fact, name, number or example the section does not hold.`;

/** What the judge is asked: whether each composed sentence states only what the page prints. */
export const JUDGE_PROMPT =
  `You check flashcard sentences against the text of the study page they were made from. For each numbered sentence, answer supported true when everything it states, every fact, name, number and relation, is stated or directly implied by the page's lines, and false when it states anything the page does not, or misattributes a fact to another item. A question is supported when what it presupposes is on the page. Answer with JSON only, matching the given schema, one verdict for every sentence, in order.`;

/** Every two-stage call's reply: `{reply}`, one of stage 1's sections or a stage-2 shape. */
export const replySchema = {
  type: "object",
  properties: {
    reply: {
      anyOf: [
        sectionsSchema,
        ...SHAPES.map((shape) => shapeSchemas[shape]),
      ],
    },
  },
  required: ["reply"],
  additionalProperties: false,
} as const;

export const judgeSchema = {
  type: "object",
  properties: {
    verdicts: {
      type: "array",
      items: {
        type: "object",
        properties: {
          id: { type: "integer" },
          supported: { type: "boolean" },
        },
        required: ["id", "supported"],
        additionalProperties: false,
      },
    },
  },
  required: ["verdicts"],
  additionalProperties: false,
} as const;

/** A configuration: today's single call, or stage 1 and stage 2 on their own models. */
export type Configuration =
  | { readonly label: string; readonly kind: "single"; readonly model: Model }
  | {
    readonly label: string;
    readonly kind: "two_stage";
    readonly sections: Model;
    readonly shapes: Model;
  };

/** The run's spend so far against what the budget leaves; a call that may not fit is refused. */
export class Wallet {
  #spent = 0;
  constructor(readonly left: number) {}
  get spent(): number {
    return this.#spent;
  }
  /** Whether a call whose worst case is [usd] still fits. */
  fits(usd: number): boolean {
    return this.#spent + usd <= this.left;
  }
  spend(usd: number): void {
    this.#spent += usd;
  }
}

/** A call refused because its worst case could exceed what the budget leaves. */
export class OutOfBudget extends Error {}

export type TwoStageDeps = {
  readonly apiKey: string;
  readonly fetch: typeof fetch;
  readonly now: () => number;
  readonly wallet: Wallet;
  /** The judge's model, text only. */
  readonly judge: Model;
  /** The instructions of today's single call. */
  readonly singlePrompt: string;
};

/** One call as kept: what it asked for, its model, and its HTTP status and body or its error. */
export type KeptCall =
  & {
    readonly step: "single" | "sections" | "shape" | "judge";
    readonly section?: string;
    readonly shape?: Shape;
    readonly model: string;
  }
  & Call;

/** One page's outcome: its scores, the calls kept, and whether stage 1's call failed. */
export type PageRun = {
  readonly result: PageResult;
  readonly calls: readonly KeptCall[];
  readonly cards: readonly unknown[];
  /** Each composed sentence, with the judge's verdict, or null where it gave none. */
  readonly composed: readonly {
    readonly sentence: string;
    readonly supported: boolean | null;
  }[];
  readonly modelError: boolean;
};

/** A call's reply text, null when the call failed, with what the call cost and took. */
type Answer = {
  readonly attempt: Attempt;
  readonly reply: string | null;
  readonly kept: Call;
  readonly usd: number;
};

/**
 * Sends one chat completion, after checking that its worst case fits the wallet: the system
 * prompt, then a user turn of the photo, a cache breakpoint, and [request], or the text alone.
 */
async function send(
  model: Model,
  system: string,
  request: string,
  image: Image | null,
  schema: { readonly name: string; readonly schema: unknown },
  deps: TwoStageDeps,
): Promise<Answer> {
  const worst = worstCallUsd(model.pricing) +
    model.pricing.prompt * [...system, ...request].length;
  if (!deps.wallet.fits(worst)) throw new OutOfBudget();
  const content = image === null ? [{ type: "text", text: request }] : [
    {
      type: "image_url",
      image_url: { url: `data:${image.type};base64,${image.base64}` },
    },
    // The breakpoint caches the system prompt and the photo, the prefix every call shares.
    {
      type: "text",
      text: "This is the page.",
      cache_control: { type: "ephemeral" },
    },
    { type: "text", text: request },
  ];
  const started = deps.now();
  let response: Response;
  try {
    response = await deps.fetch(OPENROUTER_URL, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${deps.apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: model.id,
        messages: [
          { role: "system", content: system },
          { role: "user", content },
        ],
        response_format: {
          type: "json_schema",
          json_schema: {
            name: schema.name,
            strict: true,
            schema: schema.schema,
          },
        },
        provider: { require_parameters: true },
        max_tokens: MAX_OUTPUT_TOKENS,
      }),
    });
  } catch (error) {
    return {
      attempt: {
        model: model.id,
        latencyMs: deps.now() - started,
        usage: null,
      },
      reply: null,
      kept: { error: String(error) },
      usd: 0,
    };
  }
  const raw = await response.text();
  let body: unknown = raw;
  try {
    body = JSON.parse(raw);
  } catch {
    // A body that is not JSON is kept as its text.
  }
  const usage = readUsage(body);
  const usd = callUsd(model.pricing, usage);
  deps.wallet.spend(usd);
  return {
    attempt: { model: model.id, latencyMs: deps.now() - started, usage },
    reply: response.ok ? readReply(body) ?? "" : null,
    kept: { status: response.status, body },
    usd,
  };
}

function readReply(body: unknown): string | null {
  if (!isRecord(body) || !Array.isArray(body.choices)) return null;
  const choice: unknown = body.choices[0];
  if (!isRecord(choice) || !isRecord(choice.message)) return null;
  return typeof choice.message.content === "string"
    ? choice.message.content
    : null;
}

function readUsage(body: unknown): Usage | null {
  if (!isRecord(body) || !isRecord(body.usage)) return null;
  const { prompt_tokens, completion_tokens, cost } = body.usage;
  if (
    typeof prompt_tokens !== "number" || typeof completion_tokens !== "number"
  ) return null;
  return {
    promptTokens: prompt_tokens,
    completionTokens: completion_tokens,
    costUsd: typeof cost === "number" ? cost : null,
  };
}

/** The `reply` of a two-stage call's text, or undefined when it is not `{reply}` JSON. */
function replyOf(text: string | null): unknown {
  if (text === null) return undefined;
  try {
    const value: unknown = JSON.parse(text);
    return isRecord(value) && hasOnlyKeys(value, ["reply"])
      ? value.reply
      : undefined;
  } catch {
    return undefined;
  }
}

/** The language hints of a sample, as a sentence after the request, or nothing. */
function hints(languages: LanguageHints): string {
  return [
    languages.front === undefined
      ? null
      : `The cards' fronts are in the language ${languages.front}.`,
    languages.back === undefined
      ? null
      : `Their answers are in the language ${languages.back}.`,
  ].filter((hint) => hint !== null).map((hint) => ` ${hint}`).join("");
}

/** The request of stage 1. */
export function sectionsRequest(languages: LanguageHints): string {
  return `Return the page's sections.${hints(languages)}`;
}

/** The request of stage 2 for [shape] of [section]. */
export function shapeRequest(
  shape: Shape,
  section: Section,
  languages: LanguageHints,
): string {
  return `Return the shape ${shape} for this section.${hints(languages)}\n${
    JSON.stringify(section)
  }`;
}

/** The judge's request: the page's lines, then each composed sentence numbered from 1. */
export function judgeRequest(
  lines: readonly string[],
  sentences: readonly string[],
): string {
  return [
    "The page's lines:",
    ...lines,
    "",
    "The sentences:",
    ...sentences.map((sentence, i) => `${i + 1}. ${sentence}`),
  ].join("\n");
}

/**
 * The judge's verdicts, one per sentence in order, or null when the reply does not give exactly
 * one for each of [count] sentences, numbered from 1.
 */
export function parseVerdicts(
  text: string | null,
  count: number,
): boolean[] | null {
  if (text === null) return null;
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    return null;
  }
  if (!isRecord(value) || !hasOnlyKeys(value, ["verdicts"])) return null;
  const verdicts = list(
    value.verdicts,
    count,
    (verdict) =>
      isRecord(verdict) && hasOnlyKeys(verdict, ["id", "supported"]) &&
        Number.isInteger(verdict.id) && typeof verdict.supported === "boolean"
        ? { id: verdict.id as number, supported: verdict.supported }
        : null,
  );
  if (verdicts === null || verdicts.length !== count) return null;
  return verdicts.every((verdict, i) => verdict.id === i + 1)
    ? verdicts.map((verdict) => verdict.supported)
    : null;
}

/** The ground truth a page is scored on: a sample, and its sections when it records them. */
export type PageTruth = {
  readonly sample: Sample;
  readonly sections: readonly Section<TruthLine>[] | null;
};

/** Today's single call on one page, scored as the eval scores it. */
export async function runSingle(
  configuration: Extract<Configuration, { kind: "single" }>,
  truth: PageTruth,
  deps: TwoStageDeps,
): Promise<PageRun> {
  const { sample } = truth;
  if (!deps.wallet.fits(worstCallUsd(configuration.model.pricing))) {
    throw new OutOfBudget();
  }
  const calls: Call[] = [];
  const extraction = await extractCards(
    sample.image,
    sample.languages,
    configuration.model.id,
    deps.singlePrompt,
    { ...deps, fetch: recording(deps.fetch, calls) },
  );
  const [attempt] = extraction.attempts;
  const usd = callUsd(configuration.model.pricing, attempt.usage);
  deps.wallet.spend(usd);
  const cards: readonly Card[] = extraction.kind === "cards"
    ? extraction.cards
    : [];
  return {
    result: {
      name: sample.name,
      vocabulary: sample.kind === "vocabulary"
        ? score(cards.map(entryOf), sample.cards)
        : null,
      notes: sample.kind === "notes" ? scoreNotes(cards, sample.notes) : null,
      structure: null,
      marks: null,
      spans: null,
      shapes: [],
      composed: { judged: 0, unsupported: 0 },
      stage1Ms: null,
      totalMs: attempt.latencyMs,
      photoUsd: usd,
      spentUsd: usd,
    },
    calls: [{
      step: "single",
      model: attempt.model,
      ...(calls[0] ?? { error: "no answer was recorded" }),
    }],
    cards,
    composed: [],
    modelError: extraction.kind === "model_error",
  };
}

/** One stage-2 call's outcome: the shape asked for, its checked reply or null, and its call. */
type ShapeRun = {
  readonly section: Section;
  readonly shape: Shape;
  readonly isDefault: boolean;
  readonly output: ShapeOutput | null;
  readonly answer: Answer;
};

/**
 * Stage 1 and stage 2 on one page, then the judge over the sentences stage 2 composed. Stage 2
 * makes every shape of every section, each section's default shape first, so the default shapes
 * are the ones that pay the cache's write as the app's one shape a section would.
 */
export async function runTwoStage(
  configuration: Extract<Configuration, { kind: "two_stage" }>,
  truth: PageTruth,
  deps: TwoStageDeps,
): Promise<PageRun> {
  const { sample } = truth;
  const kept: KeptCall[] = [];
  const first = await send(
    configuration.sections,
    TWO_STAGE_PROMPT,
    sectionsRequest(sample.languages),
    sample.image,
    { name: "two_stage", schema: replySchema },
    deps,
  );
  kept.push({ step: "sections", model: first.attempt.model, ...first.kept });
  const sections = parseSections(replyOf(first.reply));
  const asked = (sections ?? []).flatMap((section) =>
    shapesFor(section.content_type).map((shape, i) => ({
      section,
      shape,
      isDefault: i === 0,
    }))
  ).sort((a, b) => Number(b.isDefault) - Number(a.isDefault));
  const runs: ShapeRun[] = [];
  for (const { section, shape, isDefault } of asked) {
    const answer = await send(
      configuration.shapes,
      TWO_STAGE_PROMPT,
      shapeRequest(shape, section, sample.languages),
      sample.image,
      { name: "two_stage", schema: replySchema },
      deps,
    );
    kept.push({
      step: "shape",
      section: section.title,
      shape,
      model: answer.attempt.model,
      ...answer.kept,
    });
    runs.push({
      section,
      shape,
      isDefault,
      output: parseShape(shape, replyOf(answer.reply), section),
      answer,
    });
  }
  const valid = runs.flatMap((run) =>
    run.output === null ? [] : [{ ...run, output: run.output }]
  );
  const defaults = valid.filter((run) => run.isDefault);
  const cards = defaults.flatMap((run) => cardsOf(run.output, run.section));
  const composed = valid.flatMap((run) => composedOf(run.output));
  let judged = { judged: 0, unsupported: 0 };
  let verdicts: boolean[] | null = null;
  let judgeUsd = 0;
  if (sample.kind === "notes" && composed.length > 0) {
    const verdict = await send(
      deps.judge,
      JUDGE_PROMPT,
      judgeRequest(sample.notes.lines, composed),
      null,
      { name: "verdicts", schema: judgeSchema },
      deps,
    );
    kept.push({ step: "judge", model: verdict.attempt.model, ...verdict.kept });
    judgeUsd = verdict.usd;
    verdicts = parseVerdicts(verdict.reply, composed.length);
    if (verdicts !== null) {
      judged = {
        judged: verdicts.length,
        unsupported: verdicts.filter((supported) => !supported).length,
      };
    }
  }
  const blanks = (shapes: readonly Shape[]): LineBlank[] =>
    valid.filter((run) => shapes.includes(run.shape)).flatMap((run) =>
      lineBlanksOf(run.output, run.section)
    );
  const defaultMs = runs.filter((run) => run.isDefault).map((run) =>
    run.answer.attempt.latencyMs
  );
  const pageTruth = truth.sections;
  const stageUsd = (pick: readonly ShapeRun[]) =>
    pick.reduce((total, run) => total + run.answer.usd, 0);
  return {
    result: {
      name: sample.name,
      vocabulary: sample.kind === "vocabulary"
        ? score(
          defaults.flatMap((run) =>
            run.output.kind === "vocabulary"
              ? run.output.cards.map(entryOf)
              : []
          ),
          sample.cards,
        )
        : null,
      notes: sample.kind === "notes" ? scoreNotes(cards, sample.notes) : null,
      structure: pageTruth === null
        ? null
        : scoreStructure(sections ?? [], pageTruth),
      marks: pageTruth === null
        ? null
        : scoreMarks(blanks(["cloze", "table_spans"]), pageTruth),
      spans: pageTruth === null
        ? null
        : scoreSpans(blanks(["table_spans"]), pageTruth),
      shapes: runs.map((run) => ({
        shape: run.shape,
        valid: run.output !== null,
      })),
      composed: judged,
      stage1Ms: first.attempt.latencyMs,
      totalMs: first.attempt.latencyMs + Math.max(0, ...defaultMs),
      photoUsd: first.usd + stageUsd(runs.filter((run) => run.isDefault)),
      spentUsd: first.usd + stageUsd(runs) + judgeUsd,
    },
    calls: kept,
    cards: [
      ...(sections === null ? [] : [{ sections }]),
      ...valid.map((run) => ({ section: run.section.title, ...run.output })),
    ],
    composed: composed.map((sentence, i) => ({
      sentence,
      supported: verdicts?.[i] ?? null,
    })),
    modelError: first.reply === null,
  };
}

/** Typical tokens the dry estimate prices a two-stage page at, beside `budget.ts`'s. */
export const TYPICAL_LINE_TOKENS = 40;
export const TYPICAL_SHAPE_TOKENS_PER_LINE = 60;
export const TYPICAL_VERDICT_TOKENS = 20;
/** The sections a page whose truth records none is taken to hold, each a list. */
export const TYPICAL_SECTIONS = 3;

/** A section as the dry estimate sees it: its content type and how many lines it holds. */
export type PlannedSection = {
  readonly content_type: Section["content_type"];
  readonly lines: number;
  /** The cells holding lines, which a table's questions ask one each. */
  readonly cells: number;
};

/**
 * The sections a page is planned with: its truth's, a vocabulary page's one list, or a notes
 * page's lines split over `TYPICAL_SECTIONS` lists.
 */
export function plannedSections(truth: PageTruth): PlannedSection[] {
  if (truth.sections !== null) {
    return truth.sections.map((section) => ({
      content_type: section.content_type,
      lines: linesOf(section).length,
      cells: section.table?.rows.flatMap((row) =>
        row.cells.filter((cell) =>
          cell.lines.length > 0
        )
      ).length ?? 0,
    }));
  }
  if (truth.sample.kind === "vocabulary") {
    return [{
      content_type: "vocabulary_list",
      lines: truth.sample.cards.length,
      cells: 0,
    }];
  }
  const lines = Math.ceil(truth.sample.notes.lines.length / TYPICAL_SECTIONS);
  return Array.from({ length: TYPICAL_SECTIONS }, () => ({
    content_type: "rule_list" as const,
    lines,
    cells: 0,
  }));
}

/** The lines a page's notes print, or a vocabulary page's two a card, for the estimate. */
export function plannedLines(truth: PageTruth): number {
  return truth.sample.kind === "notes"
    ? truth.sample.notes.lines.length
    : truth.sample.cards.length * 2;
}
