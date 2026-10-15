import { StudyLink } from "./study-link";

/** The deck list's header: what a session over every deck would study now, and its button. */
export function TodayHeader({
  decks,
  review,
  fresh,
}: {
  decks: readonly string[];
  review: number;
  fresh: number;
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
      </div>
      <StudyLink decks={decks} cards={review + fresh} label="모두 학습" />
    </section>
  );
}
