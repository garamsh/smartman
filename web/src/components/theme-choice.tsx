"use client";

import { useState, useSyncExternalStore } from "react";

import {
  applyThemeChoice,
  parseThemeChoice,
  storeThemeChoice,
  type ThemeChoice as Choice,
  type ThemeStoreFailure,
} from "@/lib/theme";

const choices: readonly { value: Choice; label: string }[] = [
  { value: "system", label: "시스템" },
  { value: "light", label: "라이트" },
  { value: "dark", label: "다크" },
];

const failures: Record<ThemeStoreFailure, string> = {
  unstorable: "이 브라우저에 설정을 저장하지 못했어요. 다시 열면 이전 설정으로 보여요.",
};

/** Calls [onChange] whenever the root element's theme changes. */
function subscribe(onChange: () => void) {
  const observer = new MutationObserver(onChange);
  observer.observe(document.documentElement, { attributeFilter: ["data-theme"] });
  return () => {
    observer.disconnect();
  };
}

/** The theme the page is drawn in now, which the root layout's script set from storage. */
function drawn(): Choice {
  return parseThemeChoice(document.documentElement.dataset.theme ?? null);
}

/**
 * The account page's "화면" choice: 시스템, 라이트 or 다크, as radios labelled by the section's
 * heading [labelledBy]. A choice applies at once and is then kept on this browser; when it cannot
 * be kept, the reason is shown beneath.
 */
export function ThemeChoice({ labelledBy }: { labelledBy: string }) {
  const current = useSyncExternalStore(subscribe, drawn, () => "system" as const);
  const [failure, setFailure] = useState<ThemeStoreFailure | null>(null);

  function choose(choice: Choice) {
    applyThemeChoice(document.documentElement, choice);
    setFailure(storeThemeChoice(window.localStorage, choice));
  }

  return (
    <div className="flex flex-col gap-3">
      <div className="rounded-row bg-surface p-1.5">
        <div
          role="radiogroup"
          aria-labelledby={labelledBy}
          className="grid grid-cols-3 gap-1 rounded-field bg-ground p-1"
        >
          {choices.map(({ value, label }) => (
            <label key={value} className="flex">
              <input
                type="radio"
                name="theme"
                value={value}
                checked={current === value}
                onChange={() => {
                  choose(value);
                }}
                className="peer sr-only"
              />
              <span className="flex min-h-tap-target flex-1 cursor-pointer items-center justify-center rounded-button text-secondary font-semibold text-ink-2 peer-checked:bg-raised peer-checked:font-bold peer-checked:text-ink peer-checked:shadow-card peer-focus-visible:outline-2 peer-focus-visible:outline-offset-2 peer-focus-visible:outline-ink">
                {label}
              </span>
            </label>
          ))}
        </div>
      </div>
      {failure && (
        <p role="alert" className="text-secondary text-dont-know-text">
          {failures[failure]}
        </p>
      )}
    </div>
  );
}
