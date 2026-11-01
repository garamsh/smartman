// The 기록 page's chart shades, derived from the tokens as the phone derives them
// (app/lib/study/src/stats_style.dart), so no token is added. The ink bands and the quiet week are
// 3:1 on the surface, the coral's count carrying it where it is not, and every two bands, and every
// two adjacent heatmap levels, differ in lightness by 1.5:1;
// src/features/study/__tests__/record-shades.test.ts reads these classes to check it.

/** The recall bands: strong in ink, fair in ink a step back (75% light, 40% dark), fading coral. */
export const bandShades = {
  strong: "bg-ink",
  fair: "bg-ink/75 dark:bg-ink/40",
  fading: "bg-primary",
} as const;

/** A mastered week that is not this one: the ink at 55%; this week's is the ink. */
export const quietWeekShade = "bg-ink/55";

/** A heatmap cell at each level, from a day without a card to the busiest third. */
export const heatShades = ["bg-hairline", "bg-ink/35", "bg-ink/65", "bg-ink"] as const;
