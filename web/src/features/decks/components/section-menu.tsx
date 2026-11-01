"use client";

import { Check, ChevronDown } from "lucide-react";
import { useEffect, useId, useRef, useState, type KeyboardEvent } from "react";
import { type Direction, formLabel, type SectionForm } from "../section-form";

/** One item of the menu: a choice of the direction, a setting turned on or off, or an action. */
type Item =
  | {
      role: "menuitemradio" | "menuitemcheckbox";
      label: string;
      checked: boolean;
      pick: () => void;
    }
  | { role: "menuitem"; label: string; pick: () => void };

/**
 * A section's form menu, as the phone's `_SectionHeader` menu: its button shows the form in words,
 * and opens the pull-down menu of the form's choices and settings, then, after the heavier rule,
 * "이 묶음 빼기" or "이 묶음 넣기". A choice closes it, as on the phone.
 */
export function SectionMenu({
  title,
  form,
  pronunciations,
  extras,
  swappable,
  anyIncluded,
  change,
  toggleSection,
}: {
  /** The section's name, "판별 · topic" for identify cards, which names the menu. */
  title: string;
  form: SectionForm;
  /** Whether any row has a pronunciation or an extra to show. */
  pronunciations: boolean;
  extras: boolean;
  /** Whether any row is not a table or cloze card, which a swap would leave as it is. */
  swappable: boolean;
  anyIncluded: boolean;
  change: (form: SectionForm) => void;
  toggleSection: () => void;
}) {
  const [open, setOpen] = useState(false);
  const button = useRef<HTMLButtonElement>(null);
  const menu = useRef<HTMLDivElement>(null);
  const id = useId();
  const groups: Item[][] = [];
  if (form.kind === "vocabulary") {
    const directions: [Direction, string][] = [
      ["forward", "앞면에 단어"],
      ["backward", "앞면에 뜻"],
      ["both", "양쪽 방향 모두"],
    ];
    groups.push(
      directions.map(([direction, label]) => ({
        role: "menuitemradio",
        label,
        checked: form.direction === direction,
        pick: () => {
          change({ ...form, direction });
        },
      })),
    );
    const settings: Item[] = [
      {
        role: "menuitemcheckbox",
        label: "첫 뜻만",
        checked: form.firstSenseOnly,
        pick: () => {
          change({ ...form, firstSenseOnly: !form.firstSenseOnly });
        },
      },
      {
        role: "menuitemcheckbox",
        label: "라벨 표시",
        checked: form.showPos,
        pick: () => {
          change({ ...form, showPos: !form.showPos });
        },
      },
    ];
    if (pronunciations)
      settings.push({
        role: "menuitemcheckbox",
        label: "발음 표시",
        checked: form.showPronunciation,
        pick: () => {
          change({ ...form, showPronunciation: !form.showPronunciation });
        },
      });
    if (extras)
      settings.push({
        role: "menuitemcheckbox",
        label: "유의어 등 표시",
        checked: form.showExtras,
        pick: () => {
          change({ ...form, showExtras: !form.showExtras });
        },
      });
    groups.push(settings);
  } else if (swappable) {
    groups.push([
      {
        role: "menuitemcheckbox",
        label: "앞면과 뒷면 바꾸기",
        checked: form.swapped,
        pick: () => {
          change({ kind: "note", swapped: !form.swapped });
        },
      },
    ]);
  }
  groups.push([
    {
      role: "menuitem",
      label: anyIncluded ? "이 묶음 빼기" : "이 묶음 넣기",
      pick: toggleSection,
    },
  ]);

  function close(refocus: boolean) {
    setOpen(false);
    if (refocus) button.current?.focus();
  }
  // The open menu takes focus on its first item, and closes on a press anywhere outside it.
  useEffect(() => {
    if (!open) return;
    menu.current?.querySelector<HTMLElement>("[role^=menuitem]")?.focus();
    function outside(event: PointerEvent) {
      const target = event.target;
      if (
        target instanceof Node &&
        !menu.current?.contains(target) &&
        !button.current?.contains(target)
      )
        setOpen(false);
    }
    document.addEventListener("pointerdown", outside);
    return () => {
      document.removeEventListener("pointerdown", outside);
    };
  }, [open]);
  function move(event: KeyboardEvent<HTMLDivElement>) {
    const items = Array.from(menu.current?.querySelectorAll<HTMLElement>("[role^=menuitem]") ?? []);
    const at = items.findIndex((item) => item === document.activeElement);
    const step =
      event.key === "ArrowDown"
        ? 1
        : event.key === "ArrowUp"
          ? -1
          : event.key === "Home"
            ? 0
            : null;
    if (event.key === "Escape") {
      // Escape closes the menu alone, never the sheet around it.
      event.preventDefault();
      event.stopPropagation();
      close(true);
    } else if (event.key === "Tab") close(false);
    else if (event.key === "End") {
      event.preventDefault();
      items.at(-1)?.focus();
    } else if (step !== null) {
      event.preventDefault();
      const next = step === 0 ? 0 : (at + step + items.length) % items.length;
      items[next]?.focus();
    }
  }

  return (
    <div className="relative shrink-0">
      <button
        ref={button}
        type="button"
        aria-haspopup="menu"
        aria-expanded={open}
        aria-controls={open ? id : undefined}
        aria-label={`${title} 카드 모양, ${formLabel(form)}`}
        onClick={() => {
          setOpen(!open);
        }}
        className="pressable flex min-h-tap-target min-w-tap-target items-center justify-end gap-1 rounded-button px-1 text-caption font-semibold text-ink"
      >
        {formLabel(form)}
        <ChevronDown aria-hidden className="size-3" />
      </button>
      {open && (
        <div
          ref={menu}
          id={id}
          role="menu"
          aria-label={`${title} 카드 모양`}
          onKeyDown={move}
          className="absolute top-full right-0 z-10 mt-1 flex w-max max-w-[min(18rem,calc(100vw-2*var(--spacing-gutter)))] min-w-56 flex-col overflow-hidden rounded-group bg-raised py-1 shadow-raised"
        >
          {groups.map((items, at) => (
            <div key={at} role="group" className={at > 0 ? "border-t-4 border-hairline" : ""}>
              {items.map((item) => (
                <button
                  key={item.label}
                  type="button"
                  role={item.role}
                  aria-checked={item.role === "menuitem" ? undefined : item.checked}
                  tabIndex={-1}
                  onClick={() => {
                    item.pick();
                    close(true);
                  }}
                  className="pressable flex min-h-tap-target w-full items-center gap-3 px-4 text-left text-body text-ink focus-visible:bg-brand-tint focus-visible:outline-none"
                >
                  <span aria-hidden className="flex size-small-icon shrink-0 items-center">
                    {item.role !== "menuitem" && item.checked && (
                      <Check className="size-small-icon" />
                    )}
                  </span>
                  {item.label}
                </button>
              ))}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
