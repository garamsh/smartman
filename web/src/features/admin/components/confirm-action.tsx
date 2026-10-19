"use client";

import { useEffect, useRef, useState, useTransition } from "react";

import type { ActionResult } from "../admin-actions";

const button =
  "flex min-h-button items-center justify-center rounded-button px-4 text-label font-semibold focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink disabled:opacity-50";

/**
 * An admin action behind a confirmation: [label] asks [question], with [confirmLabel] to act and
 * "취소" to leave it; the action's sentence then shows in a status region. The server checks the
 * role, so this only spares a slip of the finger.
 */
export function ConfirmAction({
  label,
  question,
  confirmLabel,
  action,
}: {
  label: string;
  question: string;
  confirmLabel: string;
  action: () => Promise<ActionResult>;
}) {
  const [confirming, setConfirming] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();
  const confirmRef = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    if (confirming) confirmRef.current?.focus();
  }, [confirming]);

  return (
    <div className="flex flex-col gap-2">
      {confirming ? (
        <div
          role="group"
          aria-label={question}
          className="flex flex-col gap-2 rounded-field border border-outline p-3"
        >
          <p className="text-secondary">{question}</p>
          <div className="flex flex-wrap gap-2">
            <button
              ref={confirmRef}
              type="button"
              disabled={pending}
              onClick={() => {
                startTransition(async () => {
                  const result = await action();
                  setMessage(result.message);
                  setConfirming(false);
                });
              }}
              className={`${button} bg-ink text-surface`}
            >
              {confirmLabel}
            </button>
            <button
              type="button"
              disabled={pending}
              onClick={() => {
                setConfirming(false);
              }}
              className={`${button} border border-outline text-ink`}
            >
              취소
            </button>
          </div>
        </div>
      ) : (
        <button
          type="button"
          onClick={() => {
            setMessage(null);
            setConfirming(true);
          }}
          className={`${button} border border-outline text-ink`}
        >
          {label}
        </button>
      )}
      <p role="status" className="text-caption text-muted empty:hidden">
        {message}
      </p>
    </div>
  );
}
