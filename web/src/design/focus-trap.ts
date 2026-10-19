import type { KeyboardEvent } from "react";

/** What Tab can reach inside a dialog, in document order. */
const focusable =
  'a[href], button:not(:disabled), input:not(:disabled), select:not(:disabled), textarea:not(:disabled), [tabindex]:not([tabindex="-1"])';

/**
 * A modal dialog's `onKeyDown`: Tab from its last focusable control goes to its first, and
 * Shift+Tab from its first to its last, so the keyboard never reaches the page behind it.
 */
export function keepFocusInside(event: KeyboardEvent<HTMLElement>) {
  if (event.key !== "Tab") return;
  const controls = Array.from(event.currentTarget.querySelectorAll<HTMLElement>(focusable));
  const first = controls.at(0);
  const last = controls.at(-1);
  if (!first || !last) return;
  const active = document.activeElement;
  if (event.shiftKey && active === first) {
    event.preventDefault();
    last.focus();
  } else if (!event.shiftKey && active === last) {
    event.preventDefault();
    first.focus();
  }
}
