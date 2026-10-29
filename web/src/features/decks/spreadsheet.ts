import { unzipSync } from "fflate";
import { format, get_table } from "ssf";

/** The largest file read, refused by its size before a byte of it is read (ADR 0125). */
export const fileLimitBytes = 5 * 1024 * 1024;
/** The most rows holding text a sheet may have, refused before any of them becomes a card. */
export const rowLimit = 1000;
/** The most a workbook part may unpack to, so a small file cannot unpack without bound. */
const partLimitBytes = 50 * 1024 * 1024;

/** A cell as the sheet shows it, and whether it is text rather than a number, date or other value. */
export type Cell = { text: string; isText: boolean };
/** A row holding text in at least one cell, by its number in the sheet, counted from 1. */
export type SheetRow = { number: number; cells: Cell[] };
/** A refusal, in the sentence the flow shows. */
export type Refusal = { refused: string };
/** A file's sheets by name; a sheet's rows are read when it is chosen. */
export type Spreadsheet = { sheets: string[]; read: (sheet: number) => SheetRow[] | Refusal };

const unreadable: Refusal = { refused: "파일을 읽지 못했어요. 엑셀에서 다시 저장해 골라 주세요." };
const tooManyRows: Refusal = {
  refused: `행이 ${rowLimit.toLocaleString("ko-KR")}개보다 많아 읽지 못했어요. 파일을 나눠 다시 골라 주세요.`,
};

/** Opens an `.xlsx` or a UTF-8 `.csv` file, refusing one over the size limit before reading it. */
export async function openSpreadsheet(file: File): Promise<Spreadsheet | Refusal> {
  const name = file.name.toLowerCase();
  const csv = name.endsWith(".csv");
  if (!csv && !name.endsWith(".xlsx")) return { refused: ".xlsx나 .csv 파일을 골라 주세요" };
  if (file.size > fileLimitBytes)
    return { refused: "파일이 5MB보다 커서 읽지 못했어요. 파일을 나눠 다시 골라 주세요." };
  const bytes = new Uint8Array(await file.arrayBuffer());
  if (csv) {
    let text: string;
    try {
      text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes);
    } catch {
      return { refused: "CSV를 읽지 못했어요. UTF-8 CSV로 저장해 다시 골라 주세요." };
    }
    const rows = csvRows(text);
    return { sheets: [file.name], read: () => rows };
  }
  try {
    return openWorkbook(bytes);
  } catch {
    return unreadable;
  }
}

/** A CSV's rows by RFC 4180: comma-separated, `"` quoting, `""` a quote, line breaks kept inside quotes. */
function csvRows(text: string): SheetRow[] | Refusal {
  const records: string[][] = [];
  let record: string[] = [];
  let cell = "";
  let quoted = false;
  for (let at = 0; at < text.length; at += 1) {
    const char = text.charAt(at);
    if (quoted) {
      if (char === '"' && text[at + 1] === '"') {
        cell += '"';
        at += 1;
      } else if (char === '"') quoted = false;
      else cell += char;
    } else if (char === '"' && cell === "") quoted = true;
    else if (char === ",") {
      record.push(cell);
      cell = "";
    } else if (char === "\n" || char === "\r") {
      if (char === "\r" && text[at + 1] === "\n") at += 1;
      record.push(cell);
      records.push(record);
      record = [];
      cell = "";
    } else cell += char;
  }
  if (cell !== "" || record.length > 0) {
    record.push(cell);
    records.push(record);
  }
  return sheetRows(
    records.map((cells) =>
      cells.map((value) => ({
        text: value,
        isText: !/^[-+]?[\d,]*\.?\d+(?:e[-+]?\d+)?%?$/iu.test(value.trim()),
      })),
    ),
  );
}

/** Rows holding text, trimmed with their line breaks kept, numbered from 1; over the row limit, a refusal. */
function sheetRows(rows: ((Cell | undefined)[] | undefined)[]): SheetRow[] | Refusal {
  const result: SheetRow[] = [];
  rows.forEach((cells, index) => {
    if (!cells) return;
    const trimmed = Array.from(cells, (cell) => ({
      text: (cell?.text ?? "").replace(/\r\n?/gu, "\n").trim(),
      isText: cell?.isText ?? true,
    }));
    if (trimmed.some((cell) => cell.text !== ""))
      result.push({ number: index + 1, cells: trimmed });
  });
  return result.length > rowLimit ? tooManyRows : result;
}

function openWorkbook(bytes: Uint8Array): Spreadsheet | Refusal {
  const parts = unpack(
    bytes,
    (name) => name === "xl/workbook.xml" || name === "xl/_rels/workbook.xml.rels",
  );
  const workbook = parts.get("xl/workbook.xml");
  const rels = parts.get("xl/_rels/workbook.xml.rels");
  if (!workbook || !rels) return unreadable;
  const targets = new Map(
    elements(rels, "Relationship").map((rel) => [
      rel.getAttribute("Id"),
      rel.getAttribute("Target"),
    ]),
  );
  const date1904 = elements(workbook, "workbookPr").some((pr) =>
    ["1", "true"].includes(pr.getAttribute("date1904") ?? ""),
  );
  const sheets = elements(workbook, "sheet")
    .filter((sheet) => !["hidden", "veryHidden"].includes(sheet.getAttribute("state") ?? ""))
    .flatMap((sheet) => {
      const target = targets.get(relationshipId(sheet));
      const name = sheet.getAttribute("name");
      if (!target || !name) return [];
      return [{ name, path: target.startsWith("/") ? target.slice(1) : `xl/${target}` }];
    });
  if (sheets.length === 0) return unreadable;
  const read = new Map<number, SheetRow[] | Refusal>();
  return {
    sheets: sheets.map((sheet) => sheet.name),
    read: (index) => {
      const known = read.get(index);
      if (known) return known;
      const rows = readPart(index);
      read.set(index, rows);
      return rows;
    },
  };
  function readPart(index: number): SheetRow[] | Refusal {
    const path = sheets[index]?.path;
    if (!path) return unreadable;
    try {
      const parts = unpack(
        bytes,
        (name) => name === path || name === "xl/sharedStrings.xml" || name === "xl/styles.xml",
      );
      const part = parts.get(path);
      if (!part) return unreadable;
      return readSheet(
        part,
        parts.get("xl/sharedStrings.xml"),
        parts.get("xl/styles.xml"),
        date1904,
      );
    } catch {
      return unreadable;
    }
  }
}

/** The named parts of a zip, each refused past the unpacked limit, parsed as XML. */
function unpack(bytes: Uint8Array, wanted: (name: string) => boolean): Map<string, Document> {
  const files = unzipSync(bytes, {
    filter: (file) => {
      if (!wanted(file.name)) return false;
      if (file.originalSize > partLimitBytes) throw new Error("part over the unpacked limit");
      return true;
    },
  });
  const decoder = new TextDecoder();
  const parser = new DOMParser();
  const parts = new Map<string, Document>();
  for (const [name, data] of Object.entries(files)) {
    const xml = parser.parseFromString(decoder.decode(data), "application/xml");
    if (xml.getElementsByTagName("parsererror").length > 0) throw new Error(`malformed ${name}`);
    parts.set(name, xml);
  }
  return parts;
}

/** Elements by local name, whatever namespace the writer used, transitional or strict. */
function elements(node: Document | Element, name: string): Element[] {
  return Array.from(node.getElementsByTagNameNS("*", name));
}

function relationshipId(sheet: Element): string | null {
  for (const attribute of Array.from(sheet.attributes))
    if (attribute.localName === "id" && attribute.prefix) return attribute.value;
  return null;
}

/** A string item's text: its runs' text, without phonetic runs, `_xHHHH_` escapes decoded. */
function itemText(item: Element): string {
  return elements(item, "t")
    .filter((t) => t.parentElement?.localName !== "rPh")
    .map((t) => t.textContent)
    .join("")
    .replace(/_x([0-9a-f]{4})_/giu, (_, hex: string) => String.fromCharCode(parseInt(hex, 16)));
}

/** Built-in formats as Korean Excel draws them where SSF's table, US English, differs or lacks one. */
const koreanBuiltIns: Record<number, string> = { 14: "yyyy-mm-dd", 22: "yyyy-mm-dd h:mm" };
for (const id of [27, 28, 29, 30, 31, 34, 35, 36, 50, 51, 52, 53, 54, 55, 56, 57, 58])
  koreanBuiltIns[id] = "yyyy-mm-dd";

function readSheet(
  sheet: Document,
  shared: Document | undefined,
  styles: Document | undefined,
  date1904: boolean,
): SheetRow[] | Refusal {
  const strings = shared ? elements(shared, "si").map(itemText) : [];
  const custom = new Map(
    (styles ? elements(styles, "numFmt") : []).map((fmt) => [
      Number(fmt.getAttribute("numFmtId")),
      fmt.getAttribute("formatCode") ?? "General",
    ]),
  );
  const cellFormats = (styles ? elements(styles, "cellXfs") : [])
    .flatMap((xfs) => Array.from(xfs.children).filter((xf) => xf.localName === "xf"))
    .map((xf) => {
      const id = Number(xf.getAttribute("numFmtId") ?? 0);
      const table: Record<number, string | undefined> = get_table();
      return custom.get(id) ?? koreanBuiltIns[id] ?? table[id] ?? "General";
    });
  const rows: ((Cell | undefined)[] | undefined)[] = [];
  let next = 0;
  for (const row of elements(sheet, "row")) {
    const number = Number(row.getAttribute("r") ?? next + 1);
    if (!Number.isInteger(number) || number < 1) throw new Error("row number");
    next = number;
    const cells: (Cell | undefined)[] = [];
    let column = 0;
    for (const cell of Array.from(row.children).filter((c) => c.localName === "c")) {
      const reference = cell.getAttribute("r");
      column = reference ? columnIndex(reference) : column;
      cells[column] = cellOf(cell, strings, cellFormats, date1904);
      column += 1;
    }
    if (cells.some((cell) => cell && cell.text.trim() !== "")) {
      rows[number - 1] = cells;
    }
  }
  return sheetRows(rows);
}

/** A cell reference's column, from 0: `A1` is 0, `AB7` is 27. */
function columnIndex(reference: string): number {
  const letters = /^[A-Z]+/u.exec(reference.toUpperCase())?.[0];
  if (!letters) throw new Error("cell reference");
  return Array.from(letters).reduce((sum, letter) => sum * 26 + letter.charCodeAt(0) - 64, 0) - 1;
}

/** A cell's shown text: a string as written, a formula's cached value, a number or date through its format. */
function cellOf(cell: Element, strings: string[], formats: string[], date1904: boolean): Cell {
  const type = cell.getAttribute("t") ?? "n";
  const child = (name: string) => Array.from(cell.children).find((c) => c.localName === name);
  const value = child("v")?.textContent ?? "";
  if (type === "inlineStr") {
    const item = child("is");
    return { text: item ? itemText(item) : "", isText: true };
  }
  if (type === "s") return { text: strings[Number(value)] ?? "", isText: true };
  if (type === "str") return { text: value, isText: true };
  if (type === "b")
    return { text: value === "1" ? "TRUE" : value === "0" ? "FALSE" : "", isText: false };
  if (type === "e") return { text: value, isText: false };
  if (value === "") return { text: "", isText: false };
  const code = formats[Number(cell.getAttribute("s") ?? 0)] ?? "General";
  let number = Number(value);
  if (type === "d") {
    const epoch = date1904 ? Date.UTC(1904, 0, 1) : Date.UTC(1899, 11, 30);
    number = (Date.parse(value.endsWith("Z") ? value : `${value}Z`) - epoch) / 86_400_000;
    if (!Number.isFinite(number)) return { text: value, isText: false };
    return {
      text: shown(code === "General" ? "yyyy-mm-dd" : code, number, date1904),
      isText: false,
    };
  }
  if (!Number.isFinite(number)) return { text: value, isText: false };
  return { text: shown(code, number, date1904), isText: false };
}

function shown(code: string, number: number, date1904: boolean): string {
  try {
    return format(code, number, { date1904 });
  } catch {
    return format("General", number);
  }
}
