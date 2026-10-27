"use client";

import { Check } from "lucide-react";
import { useState, useSyncExternalStore } from "react";

import {
  applyThemeChoice,
  parseThemeChoice,
  storeThemeChoice,
  type ThemeChoice as Choice,
  type ThemeStoreFailure,
} from "@/design/theme";

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
 * The settings page's "화면" choice: 시스템, 라이트 or 다크, as radios labelled by the section's
 * heading [labelledBy], drawn as one group of three rows with a check on the chosen one. A choice applies at once and is then kept on this browser; when it cannot
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
      <div
        role="radiogroup"
        aria-labelledby={labelledBy}
        className="flex flex-col divide-y divide-hairline rounded-group bg-surface"
      >
        {choices.map(({ value, label }) => (
          <label
            key={value}
            className="pressable flex min-h-button cursor-pointer items-center justify-between gap-3 px-4 first:rounded-t-group last:rounded-b-group py-3 text-body text-ink has-focus-visible:outline-2 has-focus-visible:-outline-offset-2 has-focus-visible:outline-ink"
          >
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
            {label}
            <Check
              aria-hidden
              className="invisible size-5 shrink-0 peer-checked:visible"
              strokeWidth={2}
            />
          </label>
        ))}
      </div>
      {failure && (
        <p role="alert" className="text-secondary text-dont-know-text">
          {failures[failure]}
        </p>
      )}
    </div>
  );
}
