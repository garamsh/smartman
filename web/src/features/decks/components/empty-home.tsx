import { Mascot } from "@/design/brand";

/** The first run's layout: the mascot, the invitation [title] as a heading, and one [body] line. */
function FirstRun({ id, title, body }: { id: string; title: string; body: string }) {
  return (
    <section aria-labelledby={id} className="flex flex-col items-center gap-2 pt-10 text-center">
      <Mascot className="mb-4 size-mascot-large bg-surface shadow-card" />
      <h2 id={id} className="text-title">
        {title}
      </h2>
      <p className="text-secondary text-muted">{body}</p>
    </section>
  );
}

/**
 * The home page of a user with no deck, as the phone's first run draws it: the mascot, the
 * invitation, and where decks are made, since the web makes none.
 */
export function EmptyHome() {
  return (
    <FirstRun
      id="empty-home-title"
      title="첫 덱을 만들어 볼까요?"
      body="덱은 휴대폰 앱에서 만들어요. 단어장 사진을 찍거나 직접 입력하면 여기에도 보여요."
    />
  );
}

/**
 * A deck's page while the deck holds no card, in the first run's layout with the phone's words
 * for an empty deck, and where cards are added, since the web adds none.
 */
export function EmptyDeck() {
  return (
    <FirstRun
      id="empty-deck-title"
      title="아직 카드가 없어요"
      body="카드는 휴대폰 앱에서 덱에 추가해요. 추가한 카드는 여기에도 보여요."
    />
  );
}

/**
 * The 오늘 page of a user whose decks hold no card, as the phone's 오늘 tab draws it: how to
 * start rather than a finished day, and where cards are added, since the web adds none.
 */
export function NoCardsHome() {
  return (
    <FirstRun
      id="no-cards-title"
      title="첫 카드를 만들어 볼까요?"
      body="카드는 휴대폰 앱에서 덱에 추가해요. 추가한 카드는 여기에도 보여요."
    />
  );
}
