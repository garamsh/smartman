import { cleanup, render, screen } from "@testing-library/react";
import type { ReactElement } from "react";
import { afterEach, describe, expect, it } from "vitest";

import { TodaySkeleton } from "../(shell)/_components/today-skeleton";
import { ProfileSkeleton } from "../(shell)/account/_components/profile-skeleton";
import { DecksSkeleton } from "../(shell)/decks/_components/decks-skeleton";
import { DeckSkeleton } from "../(shell)/decks/[id]/_components/deck-skeleton";
import { StudySkeleton } from "../study/_components/study-skeleton";

const skeletons: [string, ReactElement, string][] = [
  ["the 오늘 page", <TodaySkeleton key="today" />, "오늘 할 카드를 불러오는 중이에요."],
  ["the 덱 page", <DecksSkeleton key="decks" />, "덱을 불러오는 중이에요."],
  ["a deck's page", <DeckSkeleton key="deck" />, "덱을 불러오는 중이에요."],
  ["the study page", <StudySkeleton key="study" />, "카드를 불러오는 중이에요."],
  ["the account page", <ProfileSkeleton key="account" />, "계정을 불러오는 중이에요."],
];

describe("a page's loading skeleton", () => {
  afterEach(cleanup);

  it.each(skeletons)(
    "on %s is busy, says what it waits for, and hides its placeholders from screen readers",
    (_, skeleton, sentence) => {
      const { container } = render(skeleton);

      const status = screen.getByRole("status");
      expect(status).toHaveTextContent(sentence);
      expect(status).toHaveClass("sr-only");
      const busy = status.closest('[aria-busy="true"]');
      expect(busy).not.toBeNull();
      // The placeholders are drawn and hidden: nothing else in the skeleton is read.
      const placeholders = busy?.querySelector('[aria-hidden="true"]');
      expect(placeholders?.childElementCount).toBeGreaterThan(0);
      expect(container.textContent.replace(/​/g, "")).toBe(sentence);
      // It pulses only where motion is welcome (globals.css' skeleton animation, motion-safe).
      expect(placeholders).toHaveClass("motion-safe:animate-skeleton");
      expect(placeholders?.className).not.toMatch(/(^|\s)animate-/);
    },
  );
});
