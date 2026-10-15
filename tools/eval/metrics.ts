/** Scores candidate cards against an image's ground truth, and picks the recommended configuration. */

import type { Card } from "../../supabase/functions/extract-cards/cards.ts";

/**
 * The card key normalization of `docs/architecture/deck.md`: Unicode NFKC, trim, each
 * whitespace run collapsed to one space, then lowercase.
 */
export function normalize(text: string): string {
  return text.normalize("NFKC").trim().replace(/\s+/g, " ").toLowerCase();
}

/** A card's fields as the page prints them: the shape of a ground-truth card. */
export type Entry = Pick<
  Card,
  "front" | "meaning" | "partOfSpeech" | "examples"
>;

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

/** The nearest-rank percentile `p` (0-100) of a non-empty list. */
export function percentile(values: readonly number[], p: number): number {
  if (values.length === 0) throw new RangeError("percentile of an empty list");
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.max(0, Math.ceil((p / 100) * sorted.length) - 1)];
}

/** One configuration's results over every image. */
export type Row = {
  readonly label: string;
  /** Means of the per-image scores, each 0-1. */
  readonly precision: number;
  readonly recall: number;
  readonly f1: number;
  /**
   * Over every image's matched cards: the share of parts of speech and of examples equal to
   * the page's, and the share of present fields the page does not print. Null when the
   * configuration returned no such field.
   */
  readonly partOfSpeechPrecision: number | null;
  readonly examplesPrecision: number | null;
  readonly inventedRate: number | null;
  readonly p50Ms: number;
  readonly p90Ms: number;
  readonly costPerImageUsd: number;
  readonly spentUsd: number;
};

/** One image's outcome for one configuration. */
export type ImageResult = {
  readonly score: Score;
  readonly latencyMs: number;
  readonly costUsd: number;
};

export function summarize(label: string, images: readonly ImageResult[]): Row {
  const mean = (pick: (image: ImageResult) => number) =>
    images.reduce((total, image) => total + pick(image), 0) / images.length;
  const latencies = images.map((image) => image.latencyMs);
  const spentUsd = images.reduce((total, image) => total + image.costUsd, 0);
  const sum = (pick: (fields: FieldCounts) => number) =>
    images.reduce((total, image) => total + pick(image.score.fields), 0);
  const share = (part: number, whole: number) =>
    whole === 0 ? null : part / whole;
  return {
    label,
    precision: mean((image) => image.score.precision),
    recall: mean((image) => image.score.recall),
    f1: mean((image) => image.score.f1),
    partOfSpeechPrecision: share(
      sum((f) => f.partOfSpeechCorrect),
      sum((f) => f.partOfSpeech),
    ),
    examplesPrecision: share(
      sum((f) => f.examplesCorrect),
      sum((f) => f.examples),
    ),
    inventedRate: share(sum((f) => f.invented), sum((f) => f.fields)),
    p50Ms: percentile(latencies, 50),
    p90Ms: percentile(latencies, 90),
    costPerImageUsd: spentUsd / images.length,
    spentUsd,
  };
}

/** How far below the best F1, in points of 100, a configuration may be and still be recommended. */
export const F1_TOLERANCE_POINTS = 2;

/**
 * The cheapest configuration per image whose F1 is within 2 points of the best; among equally
 * cheap ones, the higher F1. Null for no rows.
 */
export function recommend(rows: readonly Row[]): Row | null {
  if (rows.length === 0) return null;
  const best = Math.max(...rows.map((row) => row.f1));
  const eligible = rows.filter((row) =>
    (best - row.f1) * 100 <= F1_TOLERANCE_POINTS + 1e-9
  );
  return eligible.reduce((pick, row) =>
    row.costPerImageUsd < pick.costPerImageUsd ||
      (row.costPerImageUsd === pick.costPerImageUsd && row.f1 > pick.f1)
      ? row
      : pick
  );
}
