/** Scores candidate cards against an image's ground truth, and picks the recommended configuration. */

import type {
  Card,
  Step,
} from "../../supabase/functions/extract-cards/cards.ts";

/**
 * The card key normalization of `docs/architecture/deck.md`: Unicode NFKC, trim, each
 * whitespace run collapsed to one space, then lowercase.
 */
export function normalize(text: string): string {
  return text.normalize("NFKC").trim().replace(/\s+/g, " ").toLowerCase();
}

/** A vocabulary entry's fields as the page prints them: the shape of a ground-truth card. */
export type Entry = {
  readonly front: string;
  readonly meaning: string;
  readonly partOfSpeech?: string;
  readonly examples?: readonly string[];
};

/** A returned card as a vocabulary entry: its meaning, or its answer when it has none. */
export function entryOf(card: Card): Entry {
  return {
    front: card.front,
    meaning: card.meaning ?? card.answer,
    ...(card.partOfSpeech === undefined
      ? {}
      : { partOfSpeech: card.partOfSpeech }),
    ...(card.examples === undefined ? {} : { examples: card.examples }),
  };
}

/**
 * Counts of the optional fields over the matched cards. A part of speech, or a card's
 * examples, is a field present in the candidate; it is invented when the page prints no
 * such field for that entry.
 */
export type FieldCounts = {
  readonly partOfSpeech: number;
  readonly partOfSpeechCorrect: number;
  readonly examples: number;
  readonly examplesCorrect: number;
  readonly fields: number;
  readonly invented: number;
};

export type Score = {
  readonly precision: number;
  readonly recall: number;
  readonly f1: number;
  readonly fields: FieldCounts;
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
  return { precision, recall, f1, fields: countFields(pairs) };
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
    if (candidate.partOfSpeech !== undefined) {
      counts.partOfSpeech += 1;
      counts.fields += 1;
      if (page.partOfSpeech === undefined) {
        counts.invented += 1;
      } else if (
        normalize(page.partOfSpeech) === normalize(candidate.partOfSpeech)
      ) {
        counts.partOfSpeechCorrect += 1;
      }
    }
    const examples = candidate.examples ?? [];
    if (examples.length === 0) continue;
    counts.examples += examples.length;
    counts.fields += 1;
    if (page.examples === undefined) counts.invented += 1;
    const printed = (page.examples ?? []).map(normalize);
    for (const example of examples) {
      const at = printed.indexOf(normalize(example));
      if (at < 0) continue;
      printed.splice(at, 1);
      counts.examplesCorrect += 1;
    }
  }
  return counts;
}

function cardKey(card: Entry): string {
  return JSON.stringify([normalize(card.front), normalize(card.meaning)]);
}

/**
 * A fact a notes page teaches: the step from which it is worth learning, and the page terms a
 * card's front and answer must all hold, after `normalize`, to cover it.
 */
export type Fact = {
  readonly id: string;
  readonly step: Step;
  readonly terms: readonly string[];
};

/** A notes page's ground truth: its facts, and the examples it prints. */
export type NotesTruth = {
  readonly facts: readonly Fact[];
  /** The examples the page prints on lines of their own. */
  readonly examples: readonly string[];
  /** Every line the page prints, its title included. */
  readonly lines: readonly string[];
};

/** The fields of a returned card the notes metrics read. */
export type NoteCandidate = Pick<
  Card,
  "front" | "answer" | "step" | "examples"
>;

/**
 * One notes image's counts. `coverage[s - 1]` is the share of facts of step s or below that a
 * card of step s or below covers, null when the page has no such fact. Over every returned
 * card: those covering no fact, the examples returned and those the page does not print, and
 * the pairs of covered facts with different steps, with how many the returned steps order the
 * same way and how many they tie.
 */
export type NotesScore = {
  readonly coverage: readonly (number | null)[];
  readonly cards: number;
  readonly unsupported: number;
  readonly examples: number;
  readonly inventedExamples: number;
  readonly pairs: number;
  readonly concordant: number;
  readonly ties: number;
};

/** Whether [card] covers [fact]: its front and answer hold every one of the fact's terms. */
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
  const coverage = [1, 2, 3, 4, 5].map((step) => {
    const due = truth.facts.filter((fact) => fact.step <= step);
    if (due.length === 0) return null;
    const offered = candidates.filter((card) => card.step <= step);
    return due.filter((fact) => offered.some((card) => covers(card, fact)))
      .length / due.length;
  });
  const unsupported =
    candidates.filter((card) => !truth.facts.some((fact) => covers(card, fact)))
      .length;
  const printed = truth.examples.map(normalize);
  const lines = truth.lines.map(normalize);
  const returned = candidates.flatMap((card) => card.examples ?? []);
  // The page prints an example after a label such as "예)" or "e.g.", which a card may keep
  // or drop, so a returned example counts as printed when it and a printed one contain each
  // other after normalization. A rule's own worked example sits inside the rule's line, so an
  // example any printed line contains counts as printed too.
  const inventedExamples = returned.filter((example) => {
    const text = normalize(example);
    return !printed.some((page) =>
      page.includes(text) || text.includes(page)
    ) &&
      !lines.some((line) => line.includes(text));
  }).length;
  // Each covered fact's returned step is the lowest step of a card covering it.
  const placed = truth.facts.flatMap((fact) => {
    const steps = candidates.filter((card) => covers(card, fact)).map((card) =>
      card.step
    );
    return steps.length === 0
      ? []
      : [{ truth: fact.step, returned: Math.min(...steps) }];
  });
  let pairs = 0;
  let concordant = 0;
  let ties = 0;
  for (const [i, a] of placed.entries()) {
    for (const b of placed.slice(i + 1)) {
      if (a.truth === b.truth) continue;
      pairs += 1;
      if (a.returned === b.returned) ties += 1;
      else if ((a.returned - b.returned) * (a.truth - b.truth) > 0) {
        concordant += 1;
      }
    }
  }
  return {
    coverage,
    cards: candidates.length,
    unsupported,
    examples: returned.length,
    inventedExamples,
    pairs,
    concordant,
    ties,
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
  /** The mean coverage at each step from 1 to 5, each 0-1, over the images with such facts. */
  readonly coverage: readonly (number | null)[];
  /** The shares of returned cards covering no fact, and of returned examples the page does not print. */
  readonly unsupportedRate: number | null;
  readonly inventedExamplesRate: number | null;
  /** The share of pairs of covered facts ordered alike by their steps, a tie counting half. */
  readonly stepAgreement: number | null;
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
  /** The notes results, null without a notes image. */
  readonly notes: NotesRow | null;
  readonly p50Ms: number;
  readonly p90Ms: number;
  readonly costPerImageUsd: number;
  readonly spentUsd: number;
};

/** One image's outcome for one configuration: a vocabulary score or a notes score. */
export type ImageResult = {
  readonly score: Score | null;
  readonly notes: NotesScore | null;
  readonly latencyMs: number;
  readonly costUsd: number;
};

export function summarize(label: string, images: readonly ImageResult[]): Row {
  const scores = images.flatMap((image) =>
    image.score === null ? [] : [image.score]
  );
  const notes = images.flatMap((image) =>
    image.notes === null ? [] : [image.notes]
  );
  const mean = (pick: (score: Score) => number) =>
    scores.length === 0
      ? 0
      : scores.reduce((total, score) => total + pick(score), 0) / scores.length;
  const latencies = images.map((image) => image.latencyMs);
  const spentUsd = images.reduce((total, image) => total + image.costUsd, 0);
  const sum = (pick: (fields: FieldCounts) => number) =>
    scores.reduce((total, score) => total + pick(score.fields), 0);
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
    notes: notes.length === 0 ? null : summarizeNotes(notes),
    p50Ms: percentile(latencies, 50),
    p90Ms: percentile(latencies, 90),
    costPerImageUsd: spentUsd / images.length,
    spentUsd,
  };
}

function summarizeNotes(notes: readonly NotesScore[]): NotesRow {
  const total = (pick: (score: NotesScore) => number) =>
    notes.reduce((sum, score) => sum + pick(score), 0);
  const coverage = [0, 1, 2, 3, 4].map((at) => {
    const values = notes.flatMap((score) => {
      const value = score.coverage[at];
      return value === null || value === undefined ? [] : [value];
    });
    return values.length === 0
      ? null
      : values.reduce((sum, value) => sum + value, 0) / values.length;
  });
  return {
    coverage,
    unsupportedRate: share(total((s) => s.unsupported), total((s) => s.cards)),
    inventedExamplesRate: share(
      total((s) => s.inventedExamples),
      total((s) => s.examples),
    ),
    stepAgreement: share(
      total((s) => s.concordant + s.ties / 2),
      total((s) => s.pairs),
    ),
  };
}

function share(part: number, whole: number): number | null {
  return whole === 0 ? null : part / whole;
}

/** How far below the best F1, in points of 100, a configuration may be and still be recommended. */
export const F1_TOLERANCE_POINTS = 2;

/** How far below the best notes coverage at step 5, in points of 100, a recommended configuration may be. */
export const COVERAGE_TOLERANCE_POINTS = 5;

/** A configuration's notes coverage at step 5, every fact offered; 0 without one. */
function fullCoverage(row: Row): number {
  return row.notes?.coverage[4] ?? 0;
}

/**
 * The cheapest configuration per image whose vocabulary F1 is within 2 points of the best and,
 * when any configuration has notes results, whose notes coverage at step 5 is within 5 points
 * of the best; among equally cheap ones, the higher F1. Null for no rows, or when no row is
 * within both.
 */
export function recommend(rows: readonly Row[]): Row | null {
  if (rows.length === 0) return null;
  const best = Math.max(...rows.map((row) => row.f1));
  const notes = rows.some((row) => row.notes !== null);
  const bestCoverage = Math.max(...rows.map(fullCoverage));
  const eligible = rows.filter((row) =>
    (best - row.f1) * 100 <= F1_TOLERANCE_POINTS + 1e-9 &&
    (!notes ||
      (bestCoverage - fullCoverage(row)) * 100 <=
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
