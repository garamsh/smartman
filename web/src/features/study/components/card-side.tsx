import type { Content } from "@/lib/card-content";

/** Every block of a card side: text as written, a block of an unknown type as a placeholder. */
export function CardSide({ blocks }: { blocks: Content[] }) {
  return (
    <div className="flex flex-col gap-2 text-lg break-words whitespace-pre-wrap">
      {blocks.map((block, index) =>
        block.kind === "text" ? (
          <p key={index}>{block.text}</p>
        ) : (
          <p key={index} className="text-muted italic">
            [이 버전에서 표시할 수 없는 내용: {block.type}]
          </p>
        ),
      )}
    </div>
  );
}
