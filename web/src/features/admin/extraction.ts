/**
 * Every user's photo extractions a UTC day, as `extract-cards` enforces it
 * (`supabase/functions/extract-cards/supabase.ts`'s `DAILY_EXTRACTION_LIMIT`, which a test compares).
 */
export const dailyExtractionLimit = 30;

/**
 * The estimated model cost of one photo in US dollars, the one place the admin area states it:
 * Claude Haiku 5.5 on prompt v6, $0.0018 per photo in the PM's eval run of 2026-10-19 over the
 * 47 samples (issue #217).
 */
export const estimatedUsdPerPhoto = 0.0018;

/** [photos] at [estimatedUsdPerPhoto], in dollars with four decimals, as "$0.0540". */
export function estimatedCost(photos: number): string {
  return `$${(photos * estimatedUsdPerPhoto).toFixed(4)}`;
}
