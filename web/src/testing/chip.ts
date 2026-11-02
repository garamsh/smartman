/**
 * The tone of the one chip that draws [text], as its fill names it (`surface`, `brand-tint`,
 * `tint-amber`, `know`, `dont-know-text`), or null when no chip draws it: the nearest element on the
 * `chip` radius, in the `section` type, 12 by 4 around its words, with a line.
 */
export function chipTone(text: Element): string | null {
  const chip = text.closest(".rounded-chip");
  if (!chip) return null;
  const classes = chip.className.split(" ");
  const shaped = ["text-section", "px-3", "py-1", "border"].every((name) => classes.includes(name));
  if (!shaped) return null;
  return classes.find((name) => name.startsWith("bg-"))?.slice(3) ?? null;
}
