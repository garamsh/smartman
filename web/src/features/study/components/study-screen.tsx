"use client";

import { ChevronLeft, ChevronRight, Eye, X } from "lucide-react";
import Link from "next/link";
import { type ReactNode, useEffect, useRef, useState, useSyncExternalStore } from "react";
import { v7 } from "uuid";

import type { Answer, AnswerWrite } from "../answer-write";
import { loadEngine } from "../engine";
import { saveAnswer } from "../save-answer";
import { type PreviousAnswer, type SessionPlan, StudySession } from "../session";
import { WriteQueue } from "../write-queue";
import { AnswerList } from "./answer-list";
import { CardDetail } from "./card-detail";
import { CardSide } from "./card-side";
import { CompletionCard } from "./completion-card";
import { SessionGuide } from "./session-guide";
import { GradedCard } from "./graded-card";
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

/** What a key press asks of the study screen, or null when it asks nothing it can do now. */
function shortcut(
  event: KeyboardEvent,
  studying: boolean,
  answered: boolean,
): "help" | "leave" | "reveal" | "know" | "dontKnow" | "toggleLast" | null {
  if (event.key === "?") return "help";
  if (event.key === "Escape") return "leave";
  if (event.key === " ") return studying ? "reveal" : null;
  // Letters by their physical key, so they work whatever the keyboard's input language.
  if (event.key === "ArrowRight" || event.code === "KeyK") return studying ? "know" : null;
  if (event.key === "ArrowLeft" || event.code === "KeyJ") return studying ? "dontKnow" : null;
  if (event.code === "KeyZ") return answered ? "toggleLast" : null;
  return null;
}

/**
 * The study screen: the progress bar, and two cards of one size, the card answered just before
 * above the current card split into question and answer, with the two answer buttons under them.
 * A click on the previous card opens it whole; a touch swipe on it, Z or "마지막 답 바꾸기"
 * changes its answer. On a wide screen this session's answers are listed beside, each a button
 * that changes it. Once no card is left today the completion card takes the current card's
 * place, and practice goes on from it in the same screen. Every action
 * shows at once; its write runs behind it, and a write that fails is shown with a retry while
 * its answer stays. Each action has a keyboard shortcut, listed by "단축키", and a visible
 * control.
 */
export function StudyScreen({ plan }: { plan: SessionPlan }) {
  const [session] = useState(() => new StudySession(plan, Date.now, () => v7()));
  const [writes] = useState(() => new WriteQueue(saveAnswer));
  const [view, setView] = useState(() => session.view());
  const [revealed, setRevealed] = useState(false);
  const [helpOpen, setHelpOpen] = useState(false);
  /** Whether the previous card is open whole. */
  const [detailOpen, setDetailOpen] = useState(false);
  const previousButton = useRef<HTMLButtonElement>(null);
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
  function closeDetail() {
    setDetailOpen(false);
    previousButton.current?.focus();
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
      if (detailOpen) {
        if (event.key === "Escape") {
          event.preventDefault();
          closeDetail();
        }
        return;
      }
      const action = shortcut(event, view.kind === "studying", view.previous.length > 0);
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
          answer(action);
          break;
        case "toggleLast":
          toggleLast();
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

  // An answer counts only the time the page is visible.
  useEffect(() => {
    const listener = () => {
      if (document.visibilityState === "hidden") session.pause();
      else session.resume();
    };
    listener();
    document.addEventListener("visibilitychange", listener);
    return () => {
      document.removeEventListener("visibilitychange", listener);
    };
  }, [session]);

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
          className="flex min-w-0 flex-[999_1_520px] flex-col items-center gap-3 pt-6"
        >
          {view.kind === "empty" ? (
            <p className="py-16 text-center text-body text-muted">오늘은 학습할 카드가 없어요</p>
          ) : (
            <>
              {/* Two rows of one height: before the session's first answer its guide, otherwise
                  the previous card; and the current card. */}
              <div className="grid w-full max-w-study auto-rows-fr gap-7">
                {view.kind === "studying" && view.guide ? (
                  <SessionGuide size={view.guide} />
                ) : newest ? (
                  <GradedCard
                    key={newest.position}
                    answer={newest}
                    openRef={previousButton}
                    onOpen={() => {
                      setDetailOpen(true);
                    }}
                    onRedecide={(choice) => {
                      redecide(newest.position, choice);
                    }}
                  />
                ) : (
                  <div aria-hidden />
                )}
                {current}
              </div>
              {view.kind === "studying" && (
                <div className="w-full max-w-study">
                  <AnswerButtons onAnswer={answer} />
                </div>
              )}
            </>
          )}
        </section>

        {view.previous.length > 0 && <AnswerList answers={view.previous} onToggle={toggle} />}
      </div>

      {view.previous.length > 0 && (
        <button
          type="button"
          onClick={toggleLast}
          aria-keyshortcuts="Z"
          className={`${quiet} self-center`}
        >
          마지막 답 바꾸기 <Hint>Z</Hint>
        </button>
      )}

      {helpOpen && <ShortcutHelp onClose={closeHelp} />}
      {detailOpen && newest && <CardDetail answer={newest} onClose={closeDetail} />}
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
