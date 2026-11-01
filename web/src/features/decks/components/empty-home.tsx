import { AuthoringButton } from "./authoring-button";

import { Mascot, type MascotExpression } from "@/design/brand";

/**
 * The first run's layout: the invitation [title] as a heading and one [body] line, under the
 * mascot in its [mascot] expression, as large as [size] says.
 */
function FirstRun({
  id,
  title,
  body,
  mascot,
  size,
}: {
  id: string;
  title: string;
  body: string;
  mascot: MascotExpression;
  size: "size-mascot-large" | "size-mascot-medium";
}) {
  return (
    <section aria-labelledby={id} className="flex flex-col items-center gap-2 pt-10 text-center">
      <Mascot expression={mascot} className={`mb-4 ${size}`} />
      <h2 id={id} className="text-body-strong">
        {title}
      </h2>
      <p className="text-secondary text-muted">{body}</p>
    </section>
  );
}

/**
 * The home page of a user with no deck, as the phone's first run draws it: the mascot, the
 * invitation, and where decks are made, with its creation action.
 */
export function EmptyHome() {
  return (
    <>
      <FirstRun
        id="empty-home-title"
        title="첫 덱을 만들어 볼까요?"
        body="단어장 사진을 찍거나 직접 입력해 시작해 보세요."
        mascot="thinking"
        size="size-mascot-large"
      />
      <AuthoringButton />
    </>
  );
}

/**
 * A deck's page while the deck holds no card, in the first run's layout under the sleepy mascot,
 * with the phone's words for an empty deck, and where cards are added, with the page’s creation
 * action.
 */
export function EmptyDeck() {
  return (
    <FirstRun
      id="empty-deck-title"
      title="아직 카드가 없어요"
      body="카드를 추가해 시작해 보세요."
      mascot="sleepy"
      size="size-mascot-medium"
    />
  );
}

/**
 * The 오늘 page of a user whose decks hold no card, as the phone's 오늘 tab draws it, the mascot
 * glad of the deck just made: how to start rather than a finished day.
 */
export function NoCardsHome() {
  return (
    <FirstRun
      id="no-cards-title"
      title="첫 카드를 만들어 볼까요?"
      body="카드를 추가해 시작해 보세요."
      mascot="happy"
      size="size-mascot-large"
    />
  );
}
