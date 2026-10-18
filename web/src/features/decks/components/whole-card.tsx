import { type MarkupRun, runsOf, spoken, tableOf } from "../card-markup";

/**
 * A whole card's front: its sentence, or its table, with each blank empty, or filled in place
 * when [revealed] (ADR 0068). An empty blank keeps its answer's width, so filling it moves
 * nothing. It reads as `spoken` says, blanks as "빈칸" until revealed. It is spans throughout, so
 * a button can hold it.
 */
export function WholeCard({
  text,
  revealed,
  className = "",
}: {
  text: string;
  revealed: boolean;
  className?: string;
}) {
  const table = tableOf(text);
  return (
    <span
      role="group"
      aria-label={spoken(text, revealed)}
      className={`block w-full text-center break-words whitespace-pre-wrap ${className}`}
    >
      {table ? (
        <span
          aria-hidden
          data-table
          className="grid border-t border-l border-outline text-body"
          style={{ gridTemplateColumns: `repeat(${String(table.rows[0]?.length ?? 1)}, auto)` }}
        >
          {table.rows.flatMap((row, index) =>
            row.map((cell, column) => (
              <span
                key={`${String(index)}-${String(column)}`}
                className={`border-r border-b border-outline px-2 py-1 ${index < table.headerRows ? "bg-ground font-bold" : ""}`}
              >
                <Runs runs={runsOf(cell)} revealed={revealed} />
              </span>
            )),
          )}
        </span>
      ) : (
        <span aria-hidden>
          <Runs runs={runsOf(text)} revealed={revealed} />
        </span>
      )}
    </span>
  );
}

/**
 * A line's runs: an empty blank as its answer in no colour on the hairline, a filled one on the
 * brand tint.
 */
function Runs({ runs, revealed }: { runs: MarkupRun[]; revealed: boolean }) {
  return runs.map((run, index) =>
    run.kind === "plain" ? (
      run.text
    ) : (
      <span
        key={index}
        data-blank={revealed ? "filled" : "empty"}
        className={`rounded-sm px-1 ${revealed ? "bg-brand-tint" : "bg-hairline text-transparent"}`}
      >
        {run.answer}
      </span>
    ),
  );
}
