/**
 * The markup of a whole card's text, as the phone reads it (ADR 0068): `{{c::answer}}` marks a
 * blank, and lines that each start and end with `|` make a table, its header rows above a line
 * of `---` cells.
 */

/** A run of a whole card's text: plain text, or a blank and what fills it. */
export type MarkupRun = { kind: "plain"; text: string } | { kind: "blank"; answer: string };

/** A table's rows of cells, each row as long as the longest, and how many of them head it. */
export type MarkupTable = { rows: string[][]; headerRows: number };

const blank = /\{\{c::([^{}\n]+)\}\}/g;
const separatorCell = /^:?-{3,}:?$/;

/** Whether [text] holds a blank: a card with such a front is drawn whole, not split. */
export function hasBlanks(text: string): boolean {
  return [...text.matchAll(blank)].some((match) => (match[1] ?? "").trim() !== "");
}

/** [text] with every blank filled: a whole card's back. */
export function filled(text: string): string {
  return text.replace(blank, (_, answer: string) => answer.trim());
}

/** [text] as its plain runs and its blanks, in order. */
export function runsOf(text: string): MarkupRun[] {
  const runs: MarkupRun[] = [];
  let start = 0;
  for (const match of text.matchAll(blank)) {
    if (match.index > start) runs.push({ kind: "plain", text: text.slice(start, match.index) });
    runs.push({ kind: "blank", answer: (match[1] ?? "").trim() });
    start = match.index + match[0].length;
  }
  if (start < text.length) runs.push({ kind: "plain", text: text.slice(start) });
  return runs;
}

/**
 * [text] as a table, when each of its lines, at least two, starts and ends with `|`; otherwise
 * null. A row of `---` cells under the first rows makes them its header and is not itself a row.
 */
export function tableOf(text: string): MarkupTable | null {
  const lines = text
    .trim()
    .split("\n")
    .map((line) => line.trim());
  if (
    lines.length < 2 ||
    !lines.every((line) => line.length >= 2 && line.startsWith("|") && line.endsWith("|"))
  ) {
    return null;
  }
  const rows: string[][] = [];
  let headerRows = 0;
  for (const line of lines) {
    const cells = line
      .slice(1, -1)
      .split("|")
      .map((cell) => cell.trim());
    if (headerRows === 0 && rows.length > 0 && cells.every((cell) => separatorCell.test(cell))) {
      headerRows = rows.length;
      continue;
    }
    rows.push(cells);
  }
  const width = Math.max(...rows.map((row) => row.length));
  return {
    rows: rows.map((row) => [...row, ...Array<string>(width - row.length).fill("")]),
    headerRows,
  };
}

/**
 * [text] as a screen reader reads it: each blank as its answer when [revealed], else as
 * "빈칸"; a table row by row, its cells joined by commas.
 */
export function spoken(text: string, revealed: boolean): string {
  const line = (value: string) =>
    runsOf(value)
      .map((run) => (run.kind === "plain" ? run.text : revealed ? run.answer : "빈칸"))
      .join("");
  const table = tableOf(text);
  if (!table) return line(text);
  return table.rows
    .map((row) =>
      row
        .filter((cell) => cell !== "")
        .map(line)
        .join(", "),
    )
    .join(". ");
}
