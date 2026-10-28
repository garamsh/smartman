import { strToU8, zipSync } from "fflate";

/**
 * A cell a test writes: text as a shared string, a number, a number drawn through a format
 * code or a built-in format's id, or a formula with its cached value, a string result written
 * as Excel writes one.
 */
export type TestCell =
  | string
  | number
  | null
  | { number: number; format: string | number }
  | { formula: string; cached: number | string | null };

const escape = (text: string) =>
  text
    .replace(/&/gu, "&amp;")
    .replace(/</gu, "&lt;")
    .replace(/>/gu, "&gt;")
    .replace(/"/gu, "&quot;");

/** An `.xlsx` workbook's bytes, written as Excel lays one out, its sheets in order. */
export function xlsxOf(
  sheets: { name: string; rows: TestCell[][]; hidden?: boolean }[],
  options: { date1904?: boolean } = {},
): Uint8Array {
  const strings: string[] = [];
  const formats: (string | number)[] = [];
  const stringAt = (text: string) => {
    const at = strings.indexOf(text);
    if (at >= 0) return at;
    strings.push(text);
    return strings.length - 1;
  };
  const styleAt = (format: string | number) => {
    const at = formats.indexOf(format);
    if (at >= 0) return at + 1;
    formats.push(format);
    return formats.length;
  };
  const column = (index: number) => {
    let name = "";
    for (let at = index + 1; at > 0; at = Math.floor((at - 1) / 26))
      name = String.fromCharCode(65 + ((at - 1) % 26)) + name;
    return name;
  };
  const sheetXml = (rows: TestCell[][]) =>
    rows
      .map((cells, r) => {
        const xml = cells
          .map((cell, c) => {
            const ref = `${column(c)}${String(r + 1)}`;
            if (cell === null) return "";
            if (typeof cell === "string")
              return `<c r="${ref}" t="s"><v>${String(stringAt(cell))}</v></c>`;
            if (typeof cell === "number") return `<c r="${ref}"><v>${String(cell)}</v></c>`;
            if ("format" in cell)
              return `<c r="${ref}" s="${String(styleAt(cell.format))}"><v>${String(cell.number)}</v></c>`;
            const cached = cell.cached === null ? "" : `<v>${escape(String(cell.cached))}</v>`;
            const type = typeof cell.cached === "string" ? ` t="str"` : "";
            return `<c r="${ref}"${type}><f>${escape(cell.formula)}</f>${cached}</c>`;
          })
          .join("");
        return `<row r="${String(r + 1)}">${xml}</row>`;
      })
      .join("");
  const main = "http://schemas.openxmlformats.org/spreadsheetml/2006/main";
  const rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";
  const files: Record<string, Uint8Array> = {};
  sheets.forEach((sheet, index) => {
    files[`xl/worksheets/sheet${String(index + 1)}.xml`] = strToU8(
      `<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="${main}"><sheetData>${sheetXml(sheet.rows)}</sheetData></worksheet>`,
    );
  });
  files["xl/workbook.xml"] = strToU8(
    `<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="${main}" xmlns:r="${rel}"><workbookPr${options.date1904 ? ' date1904="1"' : ""}/><sheets>${sheets
      .map(
        (sheet, index) =>
          `<sheet name="${escape(sheet.name)}" sheetId="${String(index + 1)}"${sheet.hidden ? ' state="hidden"' : ""} r:id="rId${String(index + 1)}"/>`,
      )
      .join("")}</sheets></workbook>`,
  );
  files["xl/_rels/workbook.xml.rels"] = strToU8(
    `<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${sheets
      .map(
        (_, index) =>
          `<Relationship Id="rId${String(index + 1)}" Type="${rel}/worksheet" Target="worksheets/sheet${String(index + 1)}.xml"/>`,
      )
      .join("")}</Relationships>`,
  );
  files["xl/sharedStrings.xml"] = strToU8(
    `<?xml version="1.0" encoding="UTF-8"?><sst xmlns="${main}">${strings
      .map((text) => `<si><t xml:space="preserve">${escape(text)}</t></si>`)
      .join("")}</sst>`,
  );
  files["xl/styles.xml"] = strToU8(
    `<?xml version="1.0" encoding="UTF-8"?><styleSheet xmlns="${main}"><numFmts>${formats
      .map((format, index) =>
        typeof format === "string"
          ? `<numFmt numFmtId="${String(index + 164)}" formatCode="${escape(format)}"/>`
          : "",
      )
      .join("")}</numFmts><cellXfs><xf numFmtId="0"/>${formats
      .map(
        (format, index) =>
          `<xf numFmtId="${String(typeof format === "number" ? format : index + 164)}" applyNumberFormat="1"/>`,
      )
      .join("")}</cellXfs></styleSheet>`,
  );
  files["[Content_Types].xml"] = strToU8(
    `<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>`,
  );
  return zipSync(files);
}
