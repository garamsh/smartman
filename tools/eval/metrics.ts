/** Scores candidate cards against an image's ground truth, and picks the recommended configuration. */

import type {
  Card,
  CardType,
  Cloze,
  Sense,
  Step,
  Table,
} from "../../supabase/functions/extract-cards/cards.ts";

/**
 * The card key normalization of `docs/architecture/deck.md`: Unicode NFKC, trim, each
 * whitespace run collapsed to one space, then lowercase.
 */
export function normalize(text: string): string {
  return text.normalize("NFKC").trim().replace(/\s+/g, " ").toLowerCase();
}

/**
 * A vocabulary entry's fields as the page prints them: the shape of a ground-truth card. An
 * entry with `senses` lists each meaning with its label; one without is a single sense of its
 * `meaning` and `partOfSpeech`, as the truths written before senses are. `meaning` is the
 * senses' meanings joined by "; ".
 */
export type Entry = {
  readonly front: string;
  readonly meaning: string;
  readonly partOfSpeech?: string;
  readonly senses?: readonly Sense[];
  readonly examples?: readonly string[];
};

/** An entry's senses: its own, or the single sense of its meaning and part of speech. */
export function sensesOf(entry: Entry): readonly Sense[] {
  return entry.senses ??
    [{ pos: entry.partOfSpeech ?? null, meaning: entry.meaning }];
}

/** The meaning an entry of [senses] matches on: their meanings joined by "; ". */
export function meaningOf(senses: readonly Sense[]): string {
  return senses.map((sense) => sense.meaning).join("; ");
}

/**
 * A returned card as a vocabulary entry: a vocabulary card's senses and their meanings, or a
 * note's answer as one sense.
 */
export function entryOf(card: Card): Entry {
  const examples = card.examples === undefined
    ? {}
    : { examples: card.examples };
  return card.kind === "vocabulary"
    ? {
      front: card.front,
      meaning: meaningOf(card.senses),
      senses: card.senses,
      ...examples,
    }
    : { front: card.front, meaning: card.answer, ...examples };
}

/**
 * Counts of the optional fields over the matched cards. A sense's part of speech, or a card's
 * examples, is a field present in the candidate; it is invented when the page prints no such
 * field for that sense or entry. A matched card's senses pair with the page's in order, since
 * their meanings matched.
 */
export type FieldCounts = {
  readonly partOfSpeech: number;
  readonly partOfSpeechCorrect: number;
  readonly examples: number;
  readonly examplesCorrect: number;
  readonly fields: number;
  readonly invented: number;
};

/**
 * Over the candidates whose front matches an entry's after `normalize`, each entry matching at
 * most one: the senses returned, the page's senses, and the returned senses equal to one of the
 * page's for that entry in both part of speech and meaning, after `normalize`.
 */
export type SenseCounts = {
  readonly returned: number;
  readonly page: number;
  readonly matched: number;
};

export type Score = {
  readonly precision: number;
  readonly recall: number;
  readonly f1: number;
  readonly fields: FieldCounts;
  readonly senses: SenseCounts;
};

/**
 * Precision and recall of one image's candidates, and the field counts of the matched ones.
 * A candidate matches a ground-truth card when front and meaning are equal after `normalize`;
 * each truth card matches at most one candidate. An image with no candidates scores 0, as a
 * failed extraction does.
 */
export function score(
  candidates: readonly Entry[],
  truth: readonly Entry[],
): Score {
  const unmatched = new Map<string, Entry[]>();
  for (const card of truth) {
    const key = cardKey(card);
    unmatched.set(key, [...(unmatched.get(key) ?? []), card]);
  }
  const pairs: [Entry, Entry][] = [];
  for (const card of candidates) {
    const page = unmatched.get(cardKey(card))?.shift();
    if (page !== undefined) pairs.push([card, page]);
  }
  const matched = pairs.length;
  const precision = candidates.length === 0 ? 0 : matched / candidates.length;
  const recall = truth.length === 0 ? 0 : matched / truth.length;
  const f1 = precision + recall === 0
    ? 0
    : (2 * precision * recall) / (precision + recall);
  return {
    precision,
    recall,
    f1,
    fields: countFields(pairs),
    senses: countSenses(candidates, truth),
  };
}

function countSenses(
  candidates: readonly Entry[],
  truth: readonly Entry[],
): SenseCounts {
  const unmatched = [...truth];
  const counts = { returned: 0, page: 0, matched: 0 };
  for (const card of candidates) {
    const at = unmatched.findIndex((entry) =>
      normalize(entry.front) === normalize(card.front)
    );
    if (at < 0) continue;
    const page = sensesOf(unmatched.splice(at, 1)[0]).map(senseKey);
    const returned = sensesOf(card).map(senseKey);
    counts.returned += returned.length;
    counts.page += page.length;
    for (const sense of returned) {
      const found = page.indexOf(sense);
      if (found < 0) continue;
      page.splice(found, 1);
      counts.matched += 1;
    }
  }
  return counts;
}

function senseKey(sense: Sense): string {
  return JSON.stringify([normalize(sense.pos ?? ""), normalize(sense.meaning)]);
}

function countFields(pairs: readonly [Entry, Entry][]): FieldCounts {
  const counts = {
    partOfSpeech: 0,
    partOfSpeechCorrect: 0,
    examples: 0,
    examplesCorrect: 0,
    fields: 0,
    invented: 0,
  };
  for (const [candidate, page] of pairs) {
    const printed = sensesOf(page);
    sensesOf(candidate).forEach((sense, i) => {
      if (sense.pos === null) return;
      counts.partOfSpeech += 1;
      counts.fields += 1;
      const label = printed[i]?.pos ?? null;
      if (label === null) {
        counts.invented += 1;
      } else if (normalize(label) === normalize(sense.pos)) {
        counts.partOfSpeechCorrect += 1;
      }
    });
    const examples = candidate.examples ?? [];
    if (examples.length === 0) continue;
    counts.examples += examples.length;
    counts.fields += 1;
    if (page.examples === undefined) counts.invented += 1;
    const pageExamples = (page.examples ?? []).map(normalize);
    for (const example of examples) {
      const at = pageExamples.indexOf(normalize(example));
      if (at < 0) continue;
      pageExamples.splice(at, 1);
      counts.examplesCorrect += 1;
    }
  }
  return counts;
}

function cardKey(card: Entry): string {
  return JSON.stringify([
    normalize(card.front),
    normalize(meaningOf(sensesOf(card))),
  ]);
}

/**
 * A rule or exception a notes page teaches: the step from which it is worth learning, the page
 * terms a card's front and answer must all hold, after `normalize`, to cover it, and the worked
 * examples the page prints for it, each as printed.
 */
export type Fact = {
  readonly id: string;
  readonly step: Step;
  readonly terms: readonly string[];
  readonly examples: readonly string[];
};

/**
 * A word or cell of the page a card should ask as a blank: the terms one blank must all hold,
 * after `normalize`.
 */
export type Blank = { readonly id: string; readonly terms: readonly string[] };

/**
 * A notes page's ground truth: its rules and exceptions, every line it prints, and, on a page
 * with a table to memorise or lines recalled in context, the cells a table card should blank and
 * the words a cloze card should.
 */
export type NotesTruth = {
  readonly facts: readonly Fact[];
  /** Every line the page prints, its title included. */
  readonly lines: readonly string[];
  readonly tableBlanks?: readonly Blank[];
  readonly clozeBlanks?: readonly Blank[];
};

/** The fields of a returned card the notes metrics read; a test may leave out its type. */
export type NoteCandidate = Pick<Card, "front" | "answer" | "examples"> & {
  readonly type?: CardType;
  readonly table?: Table;
  readonly cloze?: Cloze;
};

/** The most items one card's answer may list under prompt v6's atomic rule. */
export const MAX_LISTED_ITEMS = 5;

/**
 * The items an answer lists: its non-empty parts between commas, middle dots, slashes,
 * semicolons and line breaks.
 */
export function listedItems(answer: string): number {
  return answer.split(/[,，、·;\/\n]/).filter((part) => part.trim() !== "")
    .length;
}

/**
 * One notes image's counts: `coverage`, the share of the page's facts some card covers, and over
 * every returned card, those covering no fact, those other than a table card whose answer lists
 * more than `MAX_LISTED_ITEMS` items, the examples returned and those the page does not print,
 * and those that only call themselves an exception (`isBareException`). Then the page's table
 * blanks and those some table card blanks, and its cloze blanks and those some cloze card blanks
 * (`blankCovered`).
 */
export type NotesScore = {
  readonly coverage: number;
  readonly cards: number;
  readonly unsupported: number;
  readonly longAnswers: number;
  readonly examples: number;
  readonly inventedExamples: number;
  readonly bareExceptions: number;
  readonly tableBlanks: number;
  readonly tableBlanksCovered: number;
  readonly clozeBlanks: number;
  readonly clozeBlanksCovered: number;
};

/** The words that mark a card's answer as an exception's, in the samples' two languages. */
export const EXCEPTION_WORDS = ["예외", "exception"] as const;

/**
 * Whether [card] only calls itself an exception: its answer names one (`EXCEPTION_WORDS`) yet
 * covers no fact, as "'르' 불규칙의 예외" does, where an exception card should state what the
 * exception does (#188).
 */
export function isBareException(
  card: NoteCandidate,
  facts: readonly Fact[],
): boolean {
  const answer = normalize(card.answer);
  return EXCEPTION_WORDS.some((word) => answer.includes(word)) &&
    !facts.some((fact) => covers(card, fact));
}

/** What a card asks as blanks: a table card's blank cells, or a cloze card's answers. */
export function blanksOf(card: NoteCandidate): readonly string[] {
  if (card.type === "table" && card.table !== undefined) {
    const { rows, blanks } = card.table;
    return blanks.map(({ row, column }) => rows[row][column]);
  }
  if (card.type === "cloze" && card.cloze !== undefined) {
    return card.cloze.answers;
  }
  return [];
}

/**
 * Whether one of [cards] of [type] asks [blank]: one of its blanks holds every one of the
 * blank's terms after `normalize`.
 */
export function blankCovered(
  cards: readonly NoteCandidate[],
  type: "table" | "cloze",
  blank: Blank,
): boolean {
  return cards.some((card) =>
    card.type === type &&
    blanksOf(card).some((text) =>
      blank.terms.every((term) => normalize(text).includes(normalize(term)))
    )
  );
}

/**
 * Whether [card] covers [fact]: its front and answer hold every one of the fact's terms. A
 * card's examples do not count, since another rule's worked example can hold a rule's terms.
 */
export function covers(card: NoteCandidate, fact: Fact): boolean {
  const text = normalize(`${card.front} ${card.answer}`);
  return fact.terms.every((term) => text.includes(normalize(term)));
}

/**
 * Scores one notes image. Term matching undercounts a fact the model paraphrased, which is the
 * cost of scoring without a judge model; an image with no candidates covers nothing.
 */
export function scoreNotes(
  candidates: readonly NoteCandidate[],
  truth: NotesTruth,
): NotesScore {
  const coverage =
    truth.facts.filter((fact) => candidates.some((card) => covers(card, fact)))
      .length / truth.facts.length;
  const unsupported =
    candidates.filter((card) => !truth.facts.some((fact) => covers(card, fact)))
      .length;
  // A table card's answer is its whole table, composed, which the atomic rule does not split.
  const longAnswers =
    candidates.filter((card) =>
      card.type !== "table" && listedItems(card.answer) > MAX_LISTED_ITEMS
    ).length;
  const tableBlanks = truth.tableBlanks ?? [];
  const clozeBlanks = truth.clozeBlanks ?? [];
  const printed = truth.facts.flatMap((fact) => fact.examples).map(normalize);
  const lines = truth.lines.map(normalize);
  const returned = candidates.flatMap((card) => card.examples ?? []);
  // The page may print an example after a label such as "예)" or "e.g.", which a card may keep
  // or drop, so a returned example counts as printed when it and one of the page's worked
  // examples contain each other after normalization, or when a line the page prints holds it.
  const inventedExamples = returned.filter((example) => {
    const text = normalize(example);
    return !printed.some((page) =>
      page.includes(text) || text.includes(page)
    ) &&
      !lines.some((line) => line.includes(text));
  }).length;
  return {
    coverage,
    cards: candidates.length,
    unsupported,
    longAnswers,
    examples: returned.length,
    inventedExamples,
    bareExceptions:
      candidates.filter((card) => isBareException(card, truth.facts)).length,
    tableBlanks: tableBlanks.length,
    tableBlanksCovered:
      tableBlanks.filter((blank) => blankCovered(candidates, "table", blank))
        .length,
    clozeBlanks: clozeBlanks.length,
    clozeBlanksCovered:
      clozeBlanks.filter((blank) => blankCovered(candidates, "cloze", blank))
        .length,
  };
}

/** The nearest-rank percentile `p` (0-100) of a non-empty list. */
export function percentile(values: readonly number[], p: number): number {
  if (values.length === 0) throw new RangeError("percentile of an empty list");
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.max(0, Math.ceil((p / 100) * sorted.length) - 1)];
}

/** One configuration's notes results, over every notes image. */
export type NotesRow = {
  /** The mean coverage, 0-1, over the notes images. */
  readonly coverage: number;
  /** The shares of returned cards covering no fact, and of returned examples the page does not print. */
  readonly unsupportedRate: number | null;
  readonly inventedExamplesRate: number | null;
  /** The share of returned cards whose answer lists more than `MAX_LISTED_ITEMS` items. */
  readonly longAnswerRate: number | null;
  /** The share of returned cards that only call themselves an exception. */
  readonly bareExceptionRate: number | null;
  /**
   * Over every notes image, the share of the pages' table blanks some table card blanks, and of
   * their cloze blanks some cloze card blanks; null when no page holds any.
   */
  readonly tableBlankCoverage: number | null;
  readonly clozeBlankCoverage: number | null;
  /** Each notes image's coverage and the completion tokens its calls used, in the order run. */
  readonly pages: readonly {
    readonly name: string;
    readonly coverage: number;
    readonly completionTokens: number;
  }[];
};

/** One configuration's results over every image. */
export type Row = {
  readonly label: string;
  /** Means of the per-image scores over the vocabulary images, each 0-1. */
  readonly precision: number;
  readonly recall: number;
  readonly f1: number;
  /**
   * Over every vocabulary image's matched cards: the share of parts of speech and of examples
   * equal to the page's, and the share of present fields the page does not print. Null when
   * the configuration returned no such field.
   */
  readonly partOfSpeechPrecision: number | null;
  readonly examplesPrecision: number | null;
  readonly inventedRate: number | null;
  /**
   * Over every vocabulary image's entries matched by front: the share of returned senses equal
   * to a page sense in part of speech and meaning, and the share of page senses so returned.
   * Null when no sense was returned, or the pages held none.
   */
  readonly sensePrecision: number | null;
  readonly senseRecall: number | null;
  /** The notes results, null without a notes image. */
  readonly notes: NotesRow | null;
  readonly p50Ms: number;
  readonly p90Ms: number;
  readonly costPerImageUsd: number;
  readonly spentUsd: number;
};

/** One image's outcome for one configuration: a vocabulary score or a notes score. */
export type ImageResult = {
  readonly name: string;
  readonly score: Score | null;
  readonly notes: NotesScore | null;
  readonly latencyMs: number;
  readonly costUsd: number;
  /** The completion tokens of every call for the image, retry included. */
  readonly completionTokens: number;
};

export function summarize(label: string, images: readonly ImageResult[]): Row {
  const scores = images.flatMap((image) =>
    image.score === null ? [] : [image.score]
  );
  const notes = images.flatMap((image) =>
    image.notes === null ? [] : [{
      name: image.name,
      score: image.notes,
      completionTokens: image.completionTokens,
    }]
  );
  const mean = (pick: (score: Score) => number) =>
    scores.length === 0
      ? 0
      : scores.reduce((total, score) => total + pick(score), 0) / scores.length;
  const latencies = images.map((image) => image.latencyMs);
  const spentUsd = images.reduce((total, image) => total + image.costUsd, 0);
  const sum = (pick: (fields: FieldCounts) => number) =>
    scores.reduce((total, score) => total + pick(score.fields), 0);
  const senses = (pick: (senses: SenseCounts) => number) =>
    scores.reduce((total, score) => total + pick(score.senses), 0);
  return {
    label,
    precision: mean((score) => score.precision),
    recall: mean((score) => score.recall),
    f1: mean((score) => score.f1),
    partOfSpeechPrecision: share(
      sum((f) => f.partOfSpeechCorrect),
      sum((f) => f.partOfSpeech),
    ),
    examplesPrecision: share(
      sum((f) => f.examplesCorrect),
      sum((f) => f.examples),
    ),
    inventedRate: share(sum((f) => f.invented), sum((f) => f.fields)),
    sensePrecision: share(
      senses((s) => s.matched),
      senses((s) => s.returned),
    ),
    senseRecall: share(senses((s) => s.matched), senses((s) => s.page)),
    notes: notes.length === 0 ? null : summarizeNotes(notes),
    p50Ms: percentile(latencies, 50),
    p90Ms: percentile(latencies, 90),
    costPerImageUsd: spentUsd / images.length,
    spentUsd,
  };
}

function summarizeNotes(
  images: readonly {
    name: string;
    score: NotesScore;
    completionTokens: number;
  }[],
): NotesRow {
  const notes = images.map((image) => image.score);
  const total = (pick: (score: NotesScore) => number) =>
    notes.reduce((sum, score) => sum + pick(score), 0);
  return {
    coverage: total((s) => s.coverage) / notes.length,
    unsupportedRate: share(total((s) => s.unsupported), total((s) => s.cards)),
    inventedExamplesRate: share(
      total((s) => s.inventedExamples),
      total((s) => s.examples),
    ),
    longAnswerRate: share(total((s) => s.longAnswers), total((s) => s.cards)),
    bareExceptionRate: share(
      total((s) => s.bareExceptions),
      total((s) => s.cards),
    ),
    tableBlankCoverage: share(
      total((s) => s.tableBlanksCovered),
      total((s) => s.tableBlanks),
    ),
    clozeBlankCoverage: share(
      total((s) => s.clozeBlanksCovered),
      total((s) => s.clozeBlanks),
    ),
    pages: images.map((image) => ({
      name: image.name,
      coverage: image.score.coverage,
      completionTokens: image.completionTokens,
    })),
  };
}

function share(part: number, whole: number): number | null {
  return whole === 0 ? null : part / whole;
}

/** How far below the best F1, in points of 100, a configuration may be and still be recommended. */
export const F1_TOLERANCE_POINTS = 2;

/** How far below the best notes coverage, in points of 100, a recommended configuration may be. */
export const COVERAGE_TOLERANCE_POINTS = 5;

/** A configuration's notes coverage; 0 without one. */
function notesCoverage(row: Row): number {
  return row.notes?.coverage ?? 0;
}

/**
 * The cheapest configuration per image whose vocabulary F1 is within 2 points of the best and,
 * when any configuration has notes results, whose notes coverage is within 5 points
 * of the best; among equally cheap ones, the higher F1. Null for no rows, or when no row is
 * within both.
 */
export function recommend(rows: readonly Row[]): Row | null {
  if (rows.length === 0) return null;
  const best = Math.max(...rows.map((row) => row.f1));
  const notes = rows.some((row) => row.notes !== null);
  const bestCoverage = Math.max(...rows.map(notesCoverage));
  const eligible = rows.filter((row) =>
    (best - row.f1) * 100 <= F1_TOLERANCE_POINTS + 1e-9 &&
    (!notes ||
      (bestCoverage - notesCoverage(row)) * 100 <=
        COVERAGE_TOLERANCE_POINTS + 1e-9)
  );
  return eligible.reduce<Row | null>(
    (pick, row) =>
      pick === null || row.costPerImageUsd < pick.costPerImageUsd ||
        (row.costPerImageUsd === pick.costPerImageUsd && row.f1 > pick.f1)
        ? row
        : pick,
    null,
  );
}
