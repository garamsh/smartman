/** The value of [key] in a row PostgREST answered, or undefined when the row lacks it. */
export function field(row: unknown, key: string): unknown {
  return typeof row === "object" && row !== null && key in row
    ? (row as Record<string, unknown>)[key]
    : undefined;
}

/** Milliseconds since the epoch of a `timestamptz` PostgREST answered, or null. */
export function parseTime(value: unknown): number | null {
  if (typeof value !== "string") return null;
  const time = Date.parse(value);
  return Number.isNaN(time) ? null : time;
}
