import { StudyLink } from "./study-link";

/**
 * The deck list's header: what a session over every deck would study now, whether new cards
 * pause for a [backlog] of reviews, and its button.
 */
export function TodayHeader({
  decks,
  review,
  fresh,
  backlog,
}: {
  decks: readonly string[];
  review: number;
  fresh: number;
  backlog: boolean;
}) {
  return (
    <section
      aria-labelledby="today-title"
      className="flex flex-col gap-4 rounded-card bg-surface p-6"
    >
      <div className="flex flex-col gap-1">
        <h2 id="today-title" className="text-xl font-bold">
          오늘 할 카드 {review + fresh}장
        </h2>
        <p className="text-muted">
          복습 {review} · 새 카드 {fresh}
        </p>
        {backlog && <p className="text-muted">밀린 복습을 마칠 때까지 새 카드는 쉬어요.</p>}
      </div>
      <StudyLink decks={decks} cards={review + fresh} label="모두 학습" />
    </section>
  );
}
