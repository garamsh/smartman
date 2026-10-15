"use client";

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
  "flex min-h-13 items-center justify-center gap-2 rounded-row px-5 font-semibold focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink disabled:opacity-50";

/** A key hint beside a control's name, left out of the name screen readers announce. */
function Hint({ children }: { children: string }) {
  return (
    <kbd aria-hidden className="font-sans text-sm font-normal opacity-80">
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
      const studying = view.kind === "studying";
      const act = (action: () => void) => {
        event.preventDefault();
        action();
      };
      if (event.key === "?")
        act(() => {
          setHelpOpen(true);
        });
      else if (event.key === "Escape" && studying) act(leave);
      else if (event.key === " " && studying)
        act(() => {
          setRevealed((shown) => !shown);
        });
      // Letters by their physical key, so they work whatever the keyboard's input language.
      else if ((event.key === "ArrowRight" || event.code === "KeyK") && studying)
        act(() => {
          answer("know");
        });
      else if ((event.key === "ArrowLeft" || event.code === "KeyJ") && studying)
        act(() => {
          answer("dontKnow");
        });
      else if (event.code === "KeyZ" && view.previous.length > 0) act(toggleLast);
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
    <main className="mx-auto flex min-h-dvh w-full max-w-3xl flex-col gap-4 px-5 py-6">
      <header className="flex items-center gap-4">
        {studying ? (
          <button
            type="button"
            onClick={leave}
            aria-keyshortcuts="Escape"
            className={`${button} border border-hairline bg-surface text-ink`}
          >
            끝내기 <Hint>Esc</Hint>
          </button>
        ) : (
          <Link href="/" className={`${button} border border-hairline bg-surface text-ink`}>
            덱으로
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
            className="h-2 flex-1 overflow-hidden rounded-full bg-hairline"
          >
            <div
              className="h-full rounded-full bg-know transition-[width]"
              style={{
                width: `${String(view.total === 0 ? 0 : (100 * view.answered) / view.total)}%`,
              }}
            />
          </div>
          <span aria-hidden className="text-sm text-muted tabular-nums">
            {view.answered} / {view.total}
          </span>
        </div>
        <button
          ref={helpButton}
          type="button"
          onClick={() => {
            setHelpOpen(true);
          }}
          aria-keyshortcuts="?"
          className={`${button} border border-hairline bg-surface text-ink`}
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
            className={`${button} self-start bg-ink text-surface`}
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
            className="grid min-h-52 grid-cols-1 gap-6 rounded-card bg-surface p-6 sm:grid-cols-2"
          >
            <div aria-label="문제" role="group">
              <CardSide blocks={view.current.front} />
            </div>
            <div
              aria-label="답"
              role="group"
              className="border-t border-hairline pt-6 sm:border-t-0 sm:border-l sm:pt-0 sm:pl-6"
            >
              {revealed ? (
                <CardSide blocks={view.current.back} />
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
              className={`${button} bg-dont-know-text text-on-dont-know-text`}
            >
              모른다 <Hint>← J</Hint>
            </button>
            <button
              type="button"
              onClick={() => {
                setRevealed((shown) => !shown);
              }}
              aria-keyshortcuts="Space"
              aria-pressed={revealed}
              className={`${button} border border-hairline bg-surface text-ink`}
            >
              답 보기 <Hint>Space</Hint>
            </button>
            <button
              type="button"
              onClick={() => {
                answer("know");
              }}
              aria-keyshortcuts="ArrowRight K"
              className={`${button} bg-know text-on-know`}
            >
              안다 <Hint>→ K</Hint>
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
          className={`${button} self-center border border-hairline bg-surface text-ink`}
        >
          마지막 답 바꾸기 <Hint>Z</Hint>
        </button>
      )}

      {helpOpen && <ShortcutHelp onClose={closeHelp} />}
    </main>
  );
}
