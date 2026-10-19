"use client";

import { Minus, Pencil, Plus, X } from "lucide-react";
import { useRouter } from "next/navigation";
import { useEffect, useRef, useState, useTransition } from "react";

import { keepFocusInside } from "@/design/focus-trap";

import { saveDailyMinutes } from "../actions";
import { dailyMinutePresets, dailyMinuteStep, maxDailyMinutes, minDailyMinutes } from "../queue";
import { type MinutesPlan, minutesPreview } from "../study-time";

/** Noon of the study day starting at [start], which names its calendar date in any zone. */
const noon = (start: number) => start + 12 * 3_600_000;

const presets: readonly number[] = dailyMinutePresets;

/**
 * The daily study minutes, "하루 n분" after a pencil, read as "하루 공부 시간 n분, 바꾸기", which
 * opens the dialog that changes them: the choices, a custom value in steps of five, a preview of
 * today's new cards and [reviews] and of when the last new card starts by [plan], and "저장",
 * after which the page is read again. [onHero] draws it on the navy card.
 */
export function DailyMinutes({
  minutes,
  plan,
  reviews,
  onHero = false,
}: {
  minutes: number;
  plan: MinutesPlan;
  reviews: number;
  onHero?: boolean;
}) {
  const [open, setOpen] = useState(false);
  const trigger = useRef<HTMLButtonElement>(null);
  return (
    <>
      <button
        ref={trigger}
        type="button"
        aria-label={`하루 공부 시간 ${String(minutes)}분, 바꾸기`}
        aria-haspopup="dialog"
        onClick={() => {
          setOpen(true);
        }}
        className={`pressable flex min-h-tap-target items-center gap-2 self-start rounded-full border px-4 text-label focus-visible:outline-2 focus-visible:outline-offset-2 ${
          onHero
            ? "border-on-hero text-on-hero focus-visible:outline-on-hero"
            : "border-outline text-ink focus-visible:outline-ink"
        }`}
      >
        하루 {minutes}분
        <Pencil aria-hidden className="size-small-icon" strokeWidth={2} />
      </button>
      {open && (
        <MinutesDialog
          minutes={minutes}
          plan={plan}
          reviews={reviews}
          onClose={() => {
            setOpen(false);
            trigger.current?.focus();
          }}
        />
      )}
    </>
  );
}

function MinutesDialog({
  minutes: stored,
  plan,
  reviews,
  onClose,
}: {
  minutes: number;
  plan: MinutesPlan;
  reviews: number;
  onClose: () => void;
}) {
  const router = useRouter();
  const [minutes, setMinutes] = useState(stored);
  const [custom, setCustom] = useState(!presets.includes(stored));
  const [message, setMessage] = useState<string | null>(null);
  const [saving, startSaving] = useTransition();
  const selected = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    selected.current?.focus();
  }, []);
  useEffect(() => {
    const listener = (event: KeyboardEvent) => {
      if (event.key === "Escape") onClose();
    };
    window.addEventListener("keydown", listener);
    return () => {
      window.removeEventListener("keydown", listener);
    };
  }, [onClose]);

  const choose = (value: number, isCustom: boolean) => {
    setMinutes(value);
    setCustom(isCustom);
    setMessage(null);
  };
  const { fresh, lastDay } = minutesPreview(plan, minutes);
  const date = (start: number) =>
    new Intl.DateTimeFormat("ko-KR", {
      month: "long",
      day: "numeric",
      timeZone: plan.timeZone,
    }).format(noon(start));
  const forecast =
    plan.unstarted === 0
      ? "새 카드를 모두 시작했어요"
      : lastDay === null
        ? "이 시간은 복습으로 차서 새 카드는 시작하지 않아요"
        : lastDay === plan.todayStart
          ? `남은 새 카드 ${String(plan.unstarted)}장을 오늘 다 시작해요`
          : `이대로면 남은 새 카드 ${String(plan.unstarted)}장을 ${date(lastDay)}쯤 다 시작해요`;
  const choice = (selectedNow: boolean) =>
    `pressable flex min-h-cta items-center justify-center rounded-button border text-label focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink ${
      selectedNow ? "border-ink bg-ink text-on-primary" : "border-outline bg-surface text-ink"
    }`;
  const step =
    "pressable flex size-button items-center justify-center rounded-full border border-outline text-ink focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink disabled:opacity-40";

  return (
    <div
      className="fixed inset-0 z-50 flex items-end justify-center bg-shadow/40 sm:items-center sm:px-4"
      onClick={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="daily-minutes-title"
        onKeyDown={keepFocusInside}
        aria-describedby="daily-minutes-body"
        className="flex max-h-[90dvh] w-full max-w-md flex-col gap-4 overflow-y-auto rounded-t-sheet bg-surface p-6 text-ink sm:rounded-sheet"
      >
        <div className="flex items-start justify-between gap-3">
          <div className="flex flex-col gap-1">
            <h2 id="daily-minutes-title" className="text-headline">
              하루 공부 시간
            </h2>
            <p id="daily-minutes-body" className="text-secondary text-muted">
              복습을 먼저 하고, 남는 시간에 새 카드를 시작해요.
            </p>
          </div>
          <button
            type="button"
            aria-label="닫기"
            onClick={onClose}
            className="pressable flex size-tap-target shrink-0 items-center justify-center rounded-full text-ink focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink"
          >
            <X aria-hidden className="size-5" strokeWidth={2} />
          </button>
        </div>
        <div role="group" aria-label="하루 공부 시간" className="grid grid-cols-3 gap-2">
          {presets.map((preset) => {
            const isSelected = !custom && minutes === preset;
            return (
              <button
                key={preset}
                ref={isSelected ? selected : undefined}
                type="button"
                aria-pressed={isSelected}
                onClick={() => {
                  choose(preset, false);
                }}
                className={choice(isSelected)}
              >
                {preset}분
              </button>
            );
          })}
          <button
            ref={custom ? selected : undefined}
            type="button"
            aria-pressed={custom}
            onClick={() => {
              choose(minutes, true);
            }}
            className={`col-span-3 ${choice(custom)}`}
          >
            {custom ? `직접 · ${String(minutes)}분` : "직접 정하기"}
          </button>
        </div>
        {custom && (
          <div className="flex items-center justify-between gap-3">
            <button
              type="button"
              aria-label="5분 줄이기"
              disabled={minutes <= minDailyMinutes}
              onClick={() => {
                choose(Math.max(minDailyMinutes, minutes - dailyMinuteStep), true);
              }}
              className={step}
            >
              <Minus aria-hidden className="size-5" strokeWidth={2} />
            </button>
            <span aria-hidden className="text-headline">
              {minutes}분
            </span>
            <button
              type="button"
              aria-label="5분 늘리기"
              disabled={minutes >= maxDailyMinutes}
              onClick={() => {
                choose(Math.min(maxDailyMinutes, minutes + dailyMinuteStep), true);
              }}
              className={step}
            >
              <Plus aria-hidden className="size-5" strokeWidth={2} />
            </button>
          </div>
        )}
        <div
          role="status"
          aria-atomic="true"
          className="flex flex-col gap-1 rounded-row bg-brand-tint p-4"
        >
          {plan.backlog ? (
            <p className="text-body-strong">밀린 복습을 마칠 때까지 새 카드는 쉬어요.</p>
          ) : (
            <>
              <p className="text-body-strong">
                오늘 새 카드 약 {fresh}장 · 복습 {reviews}장
              </p>
              <p className="text-secondary text-ink-2">{forecast}</p>
            </>
          )}
        </div>
        {message && (
          <p role="alert" className="text-caption text-dont-know-text">
            {message}
          </p>
        )}
        <button
          type="button"
          disabled={saving}
          onClick={() => {
            startSaving(async () => {
              const result = await saveDailyMinutes(minutes);
              if (!result.saved) {
                setMessage(result.message);
                return;
              }
              onClose();
              router.refresh();
            });
          }}
          className="pressable flex min-h-cta items-center justify-center rounded-button bg-ink px-6 text-label text-on-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink disabled:opacity-50"
        >
          {saving ? "저장 중" : "저장"}
        </button>
      </div>
    </div>
  );
}
