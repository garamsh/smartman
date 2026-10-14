/** Scores candidate cards against an image's ground truth, and picks the recommended configuration. */

import type { Card } from "../../supabase/functions/extract-cards/cards.ts";

/**
 * The card key normalization of `docs/architecture/deck.md`: Unicode NFKC, trim, each
 * whitespace run collapsed to one space, then lowercase.
 */
export function normalize(text: string): string {
  return text.normalize("NFKC").trim().replace(/\s+/g, " ").toLowerCase();
}

export type Score = {
  readonly precision: number;
  readonly recall: number;
  readonly f1: number;
};

/**
 * Precision and recall of one image's candidates. A candidate matches a ground-truth card
 * when both sides are equal after `normalize`; each truth card matches at most one candidate.
 * An image with no candidates scores 0, as a failed extraction does.
 */
export function score(
  candidates: readonly Card[],
  truth: readonly Card[],
): Score {
  const unmatched = new Map<string, number>();
  for (const card of truth) {
    const key = cardKey(card);
    unmatched.set(key, (unmatched.get(key) ?? 0) + 1);
  }
  let matched = 0;
  for (const card of candidates) {
    const key = cardKey(card);
    const left = unmatched.get(key) ?? 0;
    if (left > 0) {
      unmatched.set(key, left - 1);
      matched += 1;
    }
  }
  const precision = candidates.length === 0 ? 0 : matched / candidates.length;
  const recall = truth.length === 0 ? 0 : matched / truth.length;
  const f1 = precision + recall === 0
    ? 0
    : (2 * precision * recall) / (precision + recall);
  return { precision, recall, f1 };
}

function cardKey(card: Card): string {
  return JSON.stringify([normalize(card.front), normalize(card.back)]);
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
  return {
    label,
    precision: mean((image) => image.score.precision),
    recall: mean((image) => image.score.recall),
    f1: mean((image) => image.score.f1),
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
