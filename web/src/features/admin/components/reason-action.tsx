"use client";

import { useEffect, useId, useRef, useState, useTransition } from "react";

import type { ActionResult } from "../action-call";

const button =
  "flex min-h-button items-center justify-center rounded-button px-4 text-label font-semibold focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink disabled:opacity-50";

/**
 * An admin action that records a reason: [label] opens a field for the reason, then [question]
 * with [confirmLabel] to act and "취소" to leave it; the action's sentence shows after.
 */
export function ReasonAction({
  label,
  reasonLabel,
  question,
  confirmLabel,
  action,
}: {
  label: string;
  reasonLabel: string;
  question: string;
  confirmLabel: string;
  action: (reason: string) => Promise<ActionResult>;
}) {
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState("");
  const [message, setMessage] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();
  const field = useRef<HTMLTextAreaElement>(null);
  const id = useId();
  useEffect(() => {
    if (open) field.current?.focus();
  }, [open]);

  return (
    <div className="flex flex-col gap-2">
      {open ? (
        <div
          role="group"
          aria-label={question}
          className="flex flex-col gap-2 rounded-field border border-outline p-3"
        >
          <label htmlFor={id} className="text-label font-semibold">
            {reasonLabel}
          </label>
          <textarea
            id={id}
            ref={field}
            value={reason}
            maxLength={500}
            rows={2}
            onChange={(event) => {
              setReason(event.target.value);
            }}
            className="rounded-field border border-outline bg-surface p-3 text-body focus-visible:outline-2 focus-visible:-outline-offset-1 focus-visible:outline-ink"
          />
          <p className="text-secondary">{question}</p>
          <div className="flex flex-wrap gap-2">
            <button
              type="button"
              disabled={pending || reason.trim() === ""}
              onClick={() => {
                startTransition(async () => {
                  const result = await action(reason);
                  setMessage(result.message);
                  if (result.changed) {
                    setOpen(false);
                    setReason("");
                  }
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
                setOpen(false);
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
            setOpen(true);
          }}
          className={`${button} self-start border border-outline text-ink`}
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
