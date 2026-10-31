"use client";

import { type ReactNode, useLayoutEffect, useRef, useState } from "react";

/** The three sizes a front steps down through, largest first (ADR 0123). */
const steps = ["text-front", "text-back", "text-card-body"] as const;

/**
 * A card front's content in the largest of the front's three sizes at which it fits the face
 * whole, its lines broken only between words: centred above the body size, start-aligned at it,
 * and past it scrolling inside the face from the top, its bottom edge fading into the surface
 * while more is below (ADR 0123), as the phone's `CardScroll`.
 */
export function CardScroll({ children }: { children: ReactNode }) {
  const frame = useRef<HTMLDivElement>(null);
  const box = useRef<HTMLDivElement>(null);
  const [index, setIndex] = useState(0);
  const [more, setMore] = useState(false);
  const last = steps.length - 1;
  const step = steps[Math.min(index, last)] ?? "text-card-body";

  // Steps down while the content is wider or taller than the face, then reads whether more is
  // below. Runs before paint, so a step that does not fit is never shown.
  useLayoutEffect(() => {
    const face = box.current;
    if (!face) return;
    const overflows = face.scrollHeight > face.clientHeight || face.scrollWidth > face.clientWidth;
    if (overflows && index < last) {
      setIndex(index + 1);
      return;
    }
    setMore(face.scrollHeight - face.scrollTop - face.clientHeight > 1);
  }, [index, last, children]);

  // A face of a new size fits its content again from the largest step. The frame is watched,
  // not the scrolling face, whose width changes as its own scrollbar comes and goes.
  useLayoutEffect(() => {
    const outer = frame.current;
    if (!outer || typeof ResizeObserver === "undefined") return;
    let width = outer.offsetWidth;
    let height = outer.offsetHeight;
    const observer = new ResizeObserver(() => {
      if (outer.offsetWidth === width && outer.offsetHeight === height) return;
      width = outer.offsetWidth;
      height = outer.offsetHeight;
      setIndex(0);
    });
    observer.observe(outer);
    return () => {
      observer.disconnect();
    };
  }, []);

  const body = index >= last;
  return (
    <div ref={frame} className="relative flex min-h-0 flex-1">
      <div
        ref={box}
        data-card-step={step}
        onScroll={(event) => {
          const face = event.currentTarget;
          setMore(face.scrollHeight - face.scrollTop - face.clientHeight > 1);
        }}
        className="flex min-h-0 flex-1 overflow-y-auto p-6"
      >
        <div
          className={`m-auto flex w-full flex-col items-center gap-4 break-keep ${step} ${
            body ? "text-start wrap-break-word" : "text-center"
          }`}
        >
          {children}
        </div>
      </div>
      {more && (
        <div
          aria-hidden
          data-card-fade
          className="pointer-events-none absolute inset-x-0 bottom-0 h-8 rounded-b-card bg-linear-to-b from-transparent to-surface"
        />
      )}
    </div>
  );
}
