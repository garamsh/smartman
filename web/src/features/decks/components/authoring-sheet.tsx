"use client";

import { X } from "lucide-react";
import { useEffect, useId, useRef, type ReactNode } from "react";
import { keepFocusInside } from "@/design/focus-trap";

/** The authoring flow's modal sheet, with native focus isolation and focus return. */
export function AuthoringSheet({
  title,
  children,
  close,
}: {
  title: string;
  children: ReactNode;
  close: () => void;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  const heading = useId();
  useEffect(() => {
    const dialog = ref.current;
    const trigger = document.activeElement;
    dialog?.showModal();
    return () => {
      dialog?.close();
      if (trigger instanceof HTMLElement) trigger.focus();
    };
  }, []);
  return (
    <dialog
      ref={ref}
      aria-labelledby={heading}
      aria-modal="true"
      onCancel={(event) => {
        event.preventDefault();
        event.stopPropagation();
        close();
      }}
      onKeyDown={(event) => {
        event.stopPropagation();
        keepFocusInside(event);
      }}
      onClick={(event) => {
        if (event.target === event.currentTarget) close();
      }}
      className="fixed inset-x-0 top-auto bottom-0 m-0 max-h-[100dvh] w-full max-w-none overflow-hidden rounded-t-sheet bg-ground break-keep p-0 text-ink backdrop:bg-hero/40 lg:inset-0 lg:m-auto lg:max-h-[90dvh] lg:max-w-list lg:rounded-sheet"
    >
      <div className="flex max-h-[90dvh] min-h-0 flex-col pb-[env(safe-area-inset-bottom)]">
        <header className="flex shrink-0 items-center justify-between gap-3 px-gutter py-3">
          <h2 id={heading} className="text-title break-keep">
            {title}
          </h2>
          <button
            type="button"
            aria-label="닫기"
            onClick={close}
            className="pressable flex size-tap-target shrink-0 items-center justify-center rounded-button"
          >
            <X aria-hidden className="size-5" />
          </button>
        </header>
        <div className="min-h-0 overflow-y-auto overscroll-contain px-gutter pb-4">{children}</div>
      </div>
    </dialog>
  );
}
