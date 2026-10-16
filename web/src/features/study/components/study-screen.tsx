"use client";

import { ChevronDown, ChevronLeft, ChevronRight, Eye, X } from "lucide-react";
import Link from "next/link";
import { type ReactNode, useEffect, useRef, useState, useSyncExternalStore } from "react";
import { v7 } from "uuid";

import type { Answer, AnswerWrite } from "../answer-write";
import { loadEngine } from "../engine";
import { saveAnswer } from "../save-answer";
import { type PreviousAnswer, type SessionPlan, StudySession } from "../session";
import { WriteQueue } from "../write-queue";
import { AnswerList } from "./answer-list";
import { CardSide } from "./card-side";
import { CompletionCard } from "./completion-card";
import { FirstRunGuide } from "./first-run-guide";
import { GradedCard, type Standing } from "./graded-card";
import { ShortcutHelp } from "./shortcut-help";

const button =
  "flex min-h-button items-center justify-center gap-2 rounded-button px-5 text-label focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink disabled:opacity-50";

const quiet = `${button} border border-outline bg-surface text-ink`;

/** A key hint beside a control's name, left out of the name screen readers announce. */
function Hint({ children }: { children: string }) {
  return (
    <kbd aria-hidden className="font-sans text-caption font-normal opacity-80">
      {children}
    </kbd>
  );
}

/** Whether a key press belongs to a field or a modifier shortcut, not to the study screen. */
function isForeign(event: KeyboardEvent): boolean {
  if (event.isComposing || event.ctrlKey || event.metaKey || event.altKey) return true;
  const target = event.target;
  return (
    target instanceof HTMLElement &&
    (target.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(target.tagName))
  );
}

/**
 * What a key press asks of the study screen, or null when it asks nothing it can do now. While
 * an earlier card is centred, → and ← change its answer rather than answer the current card.
 */
function shortcut(
  event: KeyboardEvent,
  studying: boolean,
  browsing: boolean,
  answered: boolean,
): "help" | "leave" | "reveal" | "know" | "dontKnow" | "toggleLast" | "earlier" | "later" | null {
  if (event.key === "?") return "help";
  if (event.key === "Escape") return "leave";
  if (event.key === "ArrowUp") return answered ? "earlier" : null;
  if (event.key === "ArrowDown") return browsing ? "later" : null;
  if (event.key === " ") return studying && !browsing ? "reveal" : null;
  // Letters by their physical key, so they work whatever the keyboard's input language.
  if (event.key === "ArrowRight" || event.code === "KeyK") {
    return studying || browsing ? "know" : null;
  }
  if (event.key === "ArrowLeft" || event.code === "KeyJ") {
    return studying || browsing ? "dontKnow" : null;
  }
  if (event.code === "KeyZ") return answered ? "toggleLast" : null;
  return null;
}

/** How far a wheel turns, in pixels, before it moves one card. */
const wheelStep = 60;

/** How far a touch drags, in pixels, before it moves one card. */
const touchStep = 48;

/**
 * The study screen: the progress bar, and the previous card above the current card split into
 * question and answer, with the two answer buttons under it. ↑, the wheel or a downward drag
 * reaches earlier cards, three at a time with the centred one emphasised, whose answer → and ←
 * or its button change; "지금 카드로" returns. On a wide screen this session's answers are
 * listed beside, each a button that changes it. Once no card is left today the completion card
 * takes the current card's place, and practice goes on from it in the same screen. Every action
 * shows at once; its write runs behind it, and a write that fails is shown with a retry while
 * its answer stays. Each action has a keyboard shortcut, listed by "단축키", and a visible
 * control.
 */
export function StudyScreen({ plan }: { plan: SessionPlan }) {
  const [session] = useState(() => new StudySession(plan, Date.now, () => v7()));
  const [writes] = useState(() => new WriteQueue(saveAnswer));
  const [view, setView] = useState(() => session.view());
  const [revealed, setRevealed] = useState(false);
  /** The position of the earlier card centred, or null at rest on the current card. */
  const [centred, setCentred] = useState<number | null>(null);
  const [helpOpen, setHelpOpen] = useState(false);
  const helpButton = useRef<HTMLButtonElement>(null);
  const closeLink = useRef<HTMLAnchorElement>(null);
  const status = useSyncExternalStore(writes.subscribe, writes.getStatus, writes.getStatus);

  function apply(write: AnswerWrite | null) {
    setView(session.view());
    if (write) writes.push(write);
  }
  function answer(choice: Answer) {
    const write = session.answer(choice);
    if (write) setRevealed(false);
    apply(write);
  }
  function toggle(position: number) {
    apply(session.toggle(position));
  }
  function redecide(position: number, choice: Answer) {
    apply(session.redecide(position, choice));
  }
  /** Moves the centre one card earlier, or from rest to the newest previous card. */
  function earlier() {
    const newest = view.previous.length - 1;
    if (newest < 0) return;
    setCentred((at) => (at === null ? newest : Math.max(0, at - 1)));
  }
  /** Moves the centre one card later, back to rest past the newest previous card. */
  function later() {
    setCentred((at) => (at === null || at >= view.previous.length - 1 ? null : at + 1));
  }
  function toggleLast() {
    apply(session.toggleLast());
  }
  function leave() {
    closeLink.current?.click();
  }
  function practice() {
    session.practice();
    setView(session.view());
  }
  function closeHelp() {
    setHelpOpen(false);
    helpButton.current?.focus();
  }

  // The handler reads the latest render's functions, so it is registered once.
  const keys = useRef<(event: KeyboardEvent) => void>(() => undefined);
  useEffect(() => {
    keys.current = (event) => {
      if (isForeign(event)) return;
      if (helpOpen) {
        if (event.key === "Escape" || event.key === "?") {
          event.preventDefault();
          closeHelp();
        }
        return;
      }
      const action = shortcut(
        event,
        view.kind === "studying",
        centred !== null,
        view.previous.length > 0,
      );
      if (!action) return;
      event.preventDefault();
      switch (action) {
        case "help":
          setHelpOpen(true);
          break;
        case "leave":
          leave();
          break;
        case "reveal":
          setRevealed((shown) => !shown);
          break;
        case "know":
        case "dontKnow":
          if (centred === null) answer(action);
          else redecide(centred, action);
          break;
        case "toggleLast":
          toggleLast();
          break;
        case "earlier":
          earlier();
          break;
        case "later":
          later();
          break;
      }
    };
  });
  useEffect(() => {
    const listener = (event: KeyboardEvent) => {
      keys.current(event);
    };
    window.addEventListener("keydown", listener);
    return () => {
      window.removeEventListener("keydown", listener);
    };
  }, []);

  // The first write needs the engine; fetching it now keeps that write from waiting on it. A
  // failure here is not shown: the write that needs the engine fetches it again and reports it.
  useEffect(() => {
    loadEngine().catch(() => undefined);
  }, []);

  // Leaving the page drops the writes still waiting, so the browser asks first.
  const unsaved = status.pending > 0;
  useEffect(() => {
    if (!unsaved) return;
    const listener = (event: BeforeUnloadEvent) => {
      event.preventDefault();
    };
    window.addEventListener("beforeunload", listener);
    return () => {
      window.removeEventListener("beforeunload", listener);
    };
  }, [unsaved]);

  // A wheel's or a touch's travel, gathered until it moves a card.
  const travel = useRef(0);
  const touchY = useRef<number | null>(null);
  function scrollBy(delta: number, step: number) {
    travel.current += delta;
    if (Math.abs(travel.current) < step) return;
    if (travel.current < 0) earlier();
    else later();
    travel.current = 0;
  }

  const newest = view.previous.at(-1);
  const current: ReactNode =
    view.kind === "studying" ? (
      <CurrentCard
        front={view.current.front}
        back={view.current.back}
        revealed={revealed}
        onReveal={() => {
          setRevealed((shown) => !shown);
        }}
      />
    ) : view.kind === "complete" ? (
      <CompletionCard completion={view.completion} onPractice={practice} />
    ) : null;

  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-6xl flex-col gap-6 px-gutter py-6">
      <header className="flex items-center gap-4">
        <Link
          ref={closeLink}
          href="/"
          aria-label="끝내기"
          aria-keyshortcuts="Escape"
          title="끝내기 (Esc)"
          className="flex size-tap-target shrink-0 items-center justify-center rounded-full text-ink-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink"
        >
          <X aria-hidden className="size-5" strokeWidth={2.2} />
        </Link>
        <div className="flex flex-1 items-center gap-3">
          {view.kind !== "empty" && (
            <>
              <div
                role="progressbar"
                aria-label="진행"
                aria-valuemin={0}
                aria-valuemax={view.total}
                aria-valuenow={view.answered}
                aria-valuetext={`${String(view.total)}장 중 ${String(view.answered)}장 답함`}
                className="h-progress flex-1 overflow-hidden rounded-full bg-hairline"
              >
                <div
                  className="h-full rounded-full bg-ink motion-safe:transition-[width]"
                  style={{
                    width: `${String(view.total === 0 ? 0 : (100 * view.answered) / view.total)}%`,
                  }}
                />
              </div>
              <span aria-hidden className="text-secondary font-bold text-ink tabular-nums">
                {view.answered}/{view.total}
              </span>
            </>
          )}
        </div>
        <button
          ref={helpButton}
          type="button"
          onClick={() => {
            setHelpOpen(true);
          }}
          aria-keyshortcuts="?"
          className={`${quiet} hidden lg:flex`}
        >
          단축키 <Hint>?</Hint>
        </button>
      </header>

      {status.failure !== null && (
        <div role="alert" className="flex flex-col gap-3 rounded-row bg-surface p-4">
          <p className="text-dont-know-text">{status.failure}</p>
          <button
            type="button"
            onClick={() => {
              writes.retry();
            }}
            className={`${button} self-start bg-ink text-on-primary`}
          >
            다시 시도
          </button>
        </div>
      )}

      <div className="flex flex-wrap items-start justify-center gap-7">
        <section
          aria-label="카드"
          onWheel={(event) => {
            scrollBy(event.deltaY, wheelStep);
          }}
          onTouchStart={(event) => {
            touchY.current = event.touches[0]?.clientY ?? null;
          }}
          onTouchEnd={(event) => {
            const from = touchY.current;
            const to = event.changedTouches[0]?.clientY;
            touchY.current = null;
            // A drag down brings earlier cards, as on the phone.
            if (from !== null && to !== undefined) scrollBy(from - to, touchStep);
          }}
          className="flex min-w-0 flex-[999_1_520px] flex-col items-center gap-7 pt-6"
        >
          {view.kind === "empty" ? (
            <p className="py-16 text-center text-body text-muted">오늘은 학습할 카드가 없어요</p>
          ) : centred === null ? (
            <>
              {view.kind === "studying" && view.firstRun && <FirstRunGuide />}
              {newest && (
                <GradedCard
                  answer={newest}
                  standing="rest"
                  onRedecide={(choice) => {
                    redecide(newest.position, choice);
                  }}
                />
              )}
              <div className="flex w-full max-w-study flex-col gap-3">
                {current}
                {view.kind === "studying" && <AnswerButtons onAnswer={answer} />}
              </div>
            </>
          ) : (
            <Browsing
              previous={view.previous}
              centred={centred}
              current={current}
              onRedecide={redecide}
              onReturn={() => {
                setCentred(null);
              }}
            />
          )}
        </section>

        {view.previous.length > 0 && <AnswerList answers={view.previous} onToggle={toggle} />}
      </div>

      {view.previous.length > 0 && (
        <button
          type="button"
          onClick={toggleLast}
          aria-keyshortcuts="Z"
          className={`${quiet} hidden self-center lg:flex`}
        >
          마지막 답 바꾸기 <Hint>Z</Hint>
        </button>
      )}

      {helpOpen && <ShortcutHelp onClose={closeHelp} />}
    </main>
  );
}

/**
 * The card under study: the question on one half and the answer on the other, hidden behind an
 * eye until shown. The answer's half is the control that shows and hides it.
 */
function CurrentCard({
  front,
  back,
  revealed,
  onReveal,
}: {
  front: PreviousAnswer["card"]["front"];
  back: PreviousAnswer["card"]["back"];
  revealed: boolean;
  onReveal: () => void;
}) {
  return (
    <section
      aria-label="현재 카드"
      className="grid min-h-52 grid-cols-[1fr_auto_1fr] rounded-card bg-surface shadow-raised lg:min-h-75"
    >
      <div aria-label="문제" role="group" className="flex items-center justify-center p-6">
        <CardSide blocks={front} size="question" />
      </div>
      <span aria-hidden className="my-7 w-px bg-hairline" />
      <div aria-label="답" role="group" className="flex">
        <button
          type="button"
          onClick={onReveal}
          aria-label="답 보기"
          aria-keyshortcuts="Space"
          aria-pressed={revealed}
          className="flex flex-1 flex-col items-center justify-center gap-2 rounded-r-card p-6 text-muted focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-ink"
        >
          {revealed ? (
            <CardSide blocks={back} size="answer" />
          ) : (
            <>
              <Eye aria-hidden className="size-6" strokeWidth={2} />
              <span aria-hidden className="hidden text-label lg:inline">
                답 보기 <Hint>Space</Hint>
              </span>
            </>
          )}
        </button>
      </div>
    </section>
  );
}

/** "모른다" and "안다" under the current card, each with its keys. */
function AnswerButtons({ onAnswer }: { onAnswer: (answer: Answer) => void }) {
  const answerButton = `${button} min-h-cta flex-1 text-body-strong`;
  return (
    <div className="flex gap-3">
      <button
        type="button"
        onClick={() => {
          onAnswer("dontKnow");
        }}
        aria-keyshortcuts="ArrowLeft J"
        className={`${answerButton} bg-tint-red text-on-dont-know-tint`}
      >
        <ChevronLeft aria-hidden className="size-small-icon" strokeWidth={2.4} />
        모른다 <Hint>← J</Hint>
      </button>
      <button
        type="button"
        onClick={() => {
          onAnswer("know");
        }}
        aria-keyshortcuts="ArrowRight K"
        className={`${answerButton} bg-tint-green text-on-know-tint`}
      >
        안다 <Hint>→ K</Hint>
        <ChevronRight aria-hidden className="size-small-icon" strokeWidth={2.4} />
      </button>
    </div>
  );
}

/**
 * Earlier cards, three at a time: the card before the centred one, the centred one at full size
 * with the change to its other answer, and the card after it, or the current card past the
 * newest; then "지금 카드로", which returns to rest.
 */
function Browsing({
  previous,
  centred,
  current,
  onRedecide,
  onReturn,
}: {
  previous: PreviousAnswer[];
  centred: number;
  current: ReactNode;
  onRedecide: (position: number, answer: Answer) => void;
  onReturn: () => void;
}) {
  const card = (at: number, standing: Standing) => {
    const answer = previous[at];
    return answer ? (
      <GradedCard
        key={answer.position}
        answer={answer}
        standing={standing}
        onRedecide={(choice) => {
          onRedecide(answer.position, choice);
        }}
      />
    ) : null;
  };
  const after =
    centred < previous.length - 1 ? (
      card(centred + 1, "side")
    ) : (
      <div
        inert
        className="w-full max-w-study scale-90 opacity-70 motion-safe:transition-[transform,opacity] motion-safe:duration-300"
      >
        {current}
      </div>
    );
  return (
    <>
      {card(centred - 1, "side")}
      {card(centred, "centred")}
      {after}
      <button
        type="button"
        onClick={onReturn}
        aria-keyshortcuts="ArrowDown"
        className={`${button} min-h-cta bg-ink text-on-primary shadow-raised`}
      >
        <ChevronDown aria-hidden className="size-small-icon" strokeWidth={2.4} />
        지금 카드로
      </button>
    </>
  );
}
