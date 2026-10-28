/** [time] as its date and minute in [timeZone], as "2026-10-19 14:03". */
export function formatTime(time: number, timeZone: string): string {
  return new Intl.DateTimeFormat("sv-SE", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).format(time);
}

/** [time] as its date in [timeZone], as "2026-10-19". */
export function formatDate(time: number, timeZone: string): string {
  return new Intl.DateTimeFormat("sv-SE", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(time);
}

/** Dollars with four decimals, as "$0.0540". */
export function usd(value: number): string {
  return `$${value.toFixed(4)}`;
}
