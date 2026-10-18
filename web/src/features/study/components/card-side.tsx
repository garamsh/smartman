import { type Content, WholeCard } from "@/features/decks";

/**
 * Every block of a card side, in the question's or the answer's size: text as written, a cloze
 * or a table filled, as a whole card draws it, and a block of an unknown type as a placeholder.
 */
export function CardSide({ blocks, size }: { blocks: Content[]; size: "question" | "answer" }) {
  return (
    <div
      className={`flex w-full flex-col gap-2 text-center break-words whitespace-pre-wrap ${
        size === "question" ? "text-question" : "text-answer"
      }`}
    >
      {blocks.map((block, index) =>
        block.kind === "text" ? (
          <p key={index}>{block.text}</p>
        ) : block.kind === "unsupported" ? (
          <p key={index} className="text-body text-muted italic">
            [이 버전에서 표시할 수 없는 내용: {block.type}]
          </p>
        ) : (
          <WholeCard key={index} blocks={[block]} revealed />
        ),
      )}
    </div>
  );
}
