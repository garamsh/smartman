"use client";

import { ChevronLeft, ChevronRight, X } from "lucide-react";
import Link from "next/link";
import { useEffect, useRef, useState, useSyncExternalStore } from "react";

import type { Answer, AnswerWrite } from "../answer-write";
import { loadEngine } from "../engine";
import { saveAnswer } from "../save-answer";
import { type SessionPlan, StudySession } from "../session";
import { WriteQueue } from "../write-queue";
import { CardSide } from "./card-side";
import { PreviousAnswers } from "./previous-answers";
import { SessionSummary } from "./session-summary";
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
  if (event.key === "Escape") return studying ? "leave" : null;
  if (event.key === " ") return studying ? "reveal" : null;
  // Letters by their physical key, so they work whatever the keyboard's input language.
  if (event.key === "ArrowRight" || event.code === "KeyK") return studying ? "know" : null;
  if (event.key === "ArrowLeft" || event.code === "KeyJ") return studying ? "dontKnow" : null;
  if (event.code === "KeyZ") return answered ? "toggleLast" : null;
  return null;
}

/**
 * The study screen: the current card split into question and answer, the progress bar, and the
 * stack of answers given, any of which a click toggles. Every action shows at once; its write
 * runs behind it, and a write that fails is shown with a retry while its answer stays in the
 * stack. Each action has a keyboard shortcut, listed by "단축키", and a visible control.
 */
export function StudyScreen({ plan }: { plan: SessionPlan }) {
  const [session] = useState(() => new StudySession(plan, Date.now, () => crypto.randomUUID()));
  const [writes] = useState(() => new WriteQueue(saveAnswer));
  const [view, setView] = useState(() => session.view());
  const [revealed, setRevealed] = useState(false);
  const [helpOpen, setHelpOpen] = useState(false);
  const helpButton = useRef<HTMLButtonElement>(null);
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
  function toggleLast() {
    apply(session.toggleLast());
  }
  function leave() {
    session.leave();
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

  const studying = view.kind === "studying";
  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-study flex-col gap-4 px-gutter py-6">
      <header className="flex items-center gap-4">
        {studying ? (
          <button
            type="button"
            onClick={leave}
            aria-label="끝내기"
            aria-keyshortcuts="Escape"
            title="끝내기 (Esc)"
            className="flex size-tap-target items-center justify-center rounded-full text-ink focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink"
          >
            <X aria-hidden className="size-6" strokeWidth={2} />
          </button>
        ) : (
          <Link
            href="/"
            aria-label="덱으로"
            className="flex size-tap-target items-center justify-center rounded-full text-ink focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink"
          >
            <X aria-hidden className="size-6" strokeWidth={2} />
          </Link>
        )}
        <div className="flex flex-1 items-center gap-3">
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
              className="h-full rounded-full bg-ink transition-[width]"
              style={{
                width: `${String(view.total === 0 ? 0 : (100 * view.answered) / view.total)}%`,
              }}
            />
          </div>
          <span aria-hidden className="text-secondary font-bold text-ink tabular-nums">
            {view.answered}/{view.total}
          </span>
        </div>
        <button
          ref={helpButton}
          type="button"
          onClick={() => {
            setHelpOpen(true);
          }}
          aria-keyshortcuts="?"
          className={quiet}
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

      <PreviousAnswers answers={view.previous} onToggle={toggle} />

      {view.kind === "studying" ? (
        <>
          <section
            aria-label="현재 카드"
            className="grid min-h-52 grid-cols-1 rounded-card bg-surface shadow-raised sm:grid-cols-[1fr_auto_1fr]"
          >
            <div aria-label="문제" role="group" className="flex items-center justify-center p-6">
              <CardSide blocks={view.current.front} size="question" />
            </div>
            <span aria-hidden className="mx-7 h-px bg-hairline sm:mx-0 sm:my-7 sm:h-auto sm:w-px" />
            <div aria-label="답" role="group" className="flex items-center justify-center p-6">
              {revealed ? (
                <CardSide blocks={view.current.back} size="answer" />
              ) : (
                <p className="text-muted">답이 가려져 있어요.</p>
              )}
            </div>
          </section>
          <div className="grid grid-cols-3 gap-3">
            <button
              type="button"
              onClick={() => {
                answer("dontKnow");
              }}
              aria-keyshortcuts="ArrowLeft J"
              className={quiet}
            >
              <ChevronLeft aria-hidden className="size-5 text-dont-know-text" strokeWidth={2} />
              모른다 <Hint>← J</Hint>
            </button>
            <button
              type="button"
              onClick={() => {
                setRevealed((shown) => !shown);
              }}
              aria-keyshortcuts="Space"
              aria-pressed={revealed}
              className={quiet}
            >
              답 보기 <Hint>Space</Hint>
            </button>
            <button
              type="button"
              onClick={() => {
                answer("know");
              }}
              aria-keyshortcuts="ArrowRight K"
              className={quiet}
            >
              안다 <Hint>→ K</Hint>
              <ChevronRight aria-hidden className="size-5 text-know" strokeWidth={2} />
            </button>
          </div>
        </>
      ) : (
        <SessionSummary summary={view.summary} total={view.total} />
      )}

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
    </main>
  );
}
