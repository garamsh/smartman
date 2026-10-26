import { type Content, type ImageBox, cellRuns, clozeBlank, spokenContent } from "../card-content";
import { SensesText } from "./side-text";

/**
 * A whole card's front, its blocks in order: a text block as its title, a cloze as its sentence,
 * a table as its table and a photo as its frame with its boxes, with each blank empty, or filled
 * in place when [revealed] (ADR 0068, ADR 0109), a table's span inside its cell's text
 * (ADR 0110). The web reads no photo from the bucket yet, so
 * the frame is drawn on the ground at the photo's aspect ratio. An empty blank keeps its
 * answer's width, so filling it moves nothing. It reads as
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
                  cells.map((_, column) => (
                    <span
                      key={`${String(row)}-${String(column)}`}
                      className={`border-r border-b border-outline px-2 py-1 ${column === 0 ? "font-bold" : ""}`}
                    >
                      {cellRuns(block, row, column).map((run, at) =>
                        run.blank ? (
                          <Blank key={at} answer={run.text} revealed={revealed} />
                        ) : (
                          <span key={at}>{run.text}</span>
                        ),
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
          case "image":
            return (
              <span
                key={index}
                aria-hidden
                data-image={block.media}
                className="relative mx-auto block w-full rounded-sm bg-ground"
                style={{
                  aspectRatio: `${String(block.width)} / ${String(block.height)}`,
                  maxWidth: `calc(${photoMaxHeight} * ${String(block.width)} / ${String(block.height)})`,
                }}
              >
                {block.boxes.map((box) => (
                  <ImageBoxMark key={box.id} box={box} revealed={revealed} />
                ))}
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

/**
 * The tallest a photo's frame is drawn. Its width is bounded by the same height through its aspect
 * ratio, so a tall photo fits whole on the screen, as the app's `imageFrame` fits it.
 */
const photoMaxHeight = "60dvh";

/** A percentage of the photo's frame, the CSS form of a box's fraction. */
function percent(fraction: number): string {
  return `${String(fraction * 100)}%`;
}

/**
 * A box over a photo, placed in percentages of the frame, which has the photo's aspect ratio, so
 * the one transform that sizes the frame places the box (ADR 0109): an opaque fill hiding what it
 * covers, or, revealed, a border with its answer at its top left. The border, corners and label
 * stay in CSS pixels at every width.
 */
function ImageBoxMark({ box, revealed }: { box: ImageBox; revealed: boolean }) {
  return (
    <span
      data-box={revealed ? "revealed" : "hidden"}
      className={`absolute rounded-sm ${revealed ? "border-2 border-brand" : "bg-hero"}`}
      style={{
        left: percent(box.x),
        top: percent(box.y),
        width: percent(box.w),
        height: percent(box.h),
      }}
    >
      {revealed && box.answer !== null && box.answer.trim() !== "" && (
        <span className="absolute top-0 left-0 rounded-sm bg-brand-tint px-1 text-caption text-ink">
          {box.answer}
        </span>
      )}
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
