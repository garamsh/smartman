import { type Content, clozeBlank, isBlank, spokenContent } from "../card-content";
import { SensesText } from "./side-text";

/**
 * A whole card's front, its blocks in order: a text block as its title, a cloze as its sentence
 * and a table as its table, with each blank empty, or filled in place when [revealed] (ADR
 * 0068). An empty blank keeps its answer's width, so filling it moves nothing. It reads as
 * `spokenContent` says, blanks as "빈칸" until revealed. It is spans throughout, so a button can
 * hold it.
 */
export function WholeCard({
  blocks,
  revealed,
  className = "",
}: {
  blocks: Content[];
  revealed: boolean;
  className?: string;
}) {
  return (
    <span
      role="group"
      aria-label={spokenContent(blocks, revealed)}
      className={`flex w-full flex-col gap-3 text-center break-words whitespace-pre-wrap ${className}`}
    >
      {blocks.map((block, index) => {
        switch (block.kind) {
          case "text":
            return (
              <span key={index} aria-hidden className="text-headline">
                {block.text}
              </span>
            );
          case "cloze":
            return (
              <span key={index} aria-hidden>
                {block.text.split(clozeBlank).map((part, at) => (
                  <span key={at}>
                    {part}
                    {at < block.answers.length && (
                      <Blank answer={block.answers[at] ?? ""} revealed={revealed} />
                    )}
                  </span>
                ))}
              </span>
            );
          case "table":
            return (
              <span
                key={index}
                aria-hidden
                data-table
                className="grid border-t border-l border-outline text-body"
                style={{ gridTemplateColumns: `repeat(${String(block.columns.length)}, auto)` }}
              >
                {block.columns.map((cell, column) => (
                  <span
                    key={`h-${String(column)}`}
                    className="border-r border-b border-outline bg-ground px-2 py-1 font-bold"
                  >
                    {cell}
                  </span>
                ))}
                {block.rows.flatMap((cells, row) =>
                  cells.map((cell, column) => (
                    <span
                      key={`${String(row)}-${String(column)}`}
                      className={`border-r border-b border-outline px-2 py-1 ${column === 0 ? "font-bold" : ""}`}
                    >
                      {isBlank(block.blanks, row, column) ? (
                        <Blank answer={cell} revealed={revealed} />
                      ) : (
                        cell
                      )}
                    </span>
                  )),
                )}
              </span>
            );
          case "senses":
            return (
              <span key={index} aria-hidden>
                <SensesText senses={block.senses} />
              </span>
            );
          case "unsupported":
            return (
              <span key={index} aria-hidden className="text-body text-muted italic">
                [이 버전에서 표시할 수 없는 내용: {block.type}]
              </span>
            );
        }
      })}
    </span>
  );
}

/** A blank: its answer in no colour on the hairline, or filled on the brand tint. */
function Blank({ answer, revealed }: { answer: string; revealed: boolean }) {
  return (
    <span
      data-blank={revealed ? "filled" : "empty"}
      className={`rounded-sm px-1 ${revealed ? "bg-brand-tint" : "bg-hairline text-transparent"}`}
    >
      {answer}
    </span>
  );
}
