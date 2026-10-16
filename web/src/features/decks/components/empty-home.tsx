import { Mascot } from "@/design/brand";

/**
 * The home page of a user with no deck, as the phone's first run draws it: the mascot, the
 * invitation, and where decks are made, since the web makes none.
 */
export function EmptyHome() {
  return (
    <section
      aria-labelledby="empty-home-title"
      className="flex flex-col items-center gap-2 pt-10 text-center"
    >
      <Mascot className="mb-4 size-mascot-large bg-surface shadow-card" />
      <h2 id="empty-home-title" className="text-title">
        첫 덱을 만들어 볼까요?
      </h2>
      <p className="text-secondary text-muted">
        덱은 휴대폰 앱에서 만들어요. 단어장 사진을 찍거나 직접 입력하면 여기에도 보여요.
      </p>
    </section>
  );
}
