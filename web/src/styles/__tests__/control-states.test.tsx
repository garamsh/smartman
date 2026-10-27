import { readFileSync } from "node:fs";
import path from "node:path";

import { render, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

import { EnterLink } from "@/app/(shell)/_components/enter-link";
import { SideMenuAt, TabBarAt } from "@/app/(shell)/_components/shell-menu";
import { CardGrid, DeckList, parseCardId, parseDeckId } from "@/features/decks";
import { uuidOf } from "@/testing/library";

vi.mock("next/navigation", async (importOriginal) => ({
  ...(await importOriginal<typeof import("next/navigation")>()),
  usePathname: () => "/",
}));

const globalsCss = readFileSync(path.join(import.meta.dirname, "../globals.css"), "utf8");

/** [id] parsed by [parse], which a test's fixed uuid always passes. */
function idOf<T>(parse: (id: string) => T | null, name: string): T {
  const id = parse(uuidOf(name));
  if (id === null) throw new Error(`${name} is no uuid`);
  return id;
}

/** Whether [element] carries the shared hover and pressed state. */
const pressable = (element: HTMLElement) => element.className.split(" ").includes("pressable");

describe("the controls' pointer, hover and pressed states", () => {
  afterEach(() => {
    document.head.querySelector("style[data-cursor]")?.remove();
  });

  it("points over an enabled button and not over a disabled one", () => {
    const rule = /@layer base \{\s*(button:not\(:disabled\) \{[^}]*\})/.exec(globalsCss)?.[1];
    expect(rule).toContain("cursor: pointer");
    const style = document.createElement("style");
    style.dataset.cursor = "";
    style.textContent = rule ?? "";
    document.head.append(style);
    render(
      <>
        <button type="button">enabled</button>
        <button type="button" disabled>
          disabled
        </button>
      </>,
    );

    expect(getComputedStyle(screen.getByRole("button", { name: "enabled" })).cursor).toBe(
      "pointer",
    );
    // Control: the same rule leaves a disabled button the arrow.
    expect(getComputedStyle(screen.getByRole("button", { name: "disabled" })).cursor).not.toBe(
      "pointer",
    );
  });

  it("draws the state as a layer of the control's text colour on hover and press, and presses only under motion-safe", () => {
    const rule = /\.pressable \{([^}]*)\}/.exec(globalsCss)?.[1] ?? "";
    expect(rule).toContain("--state-layer: color-mix(in srgb, currentColor 4%, transparent);");
    for (const variant of ["not-disabled:hover:", "not-disabled:active:"]) {
      expect(rule).toContain(
        `${variant}bg-[linear-gradient(var(--state-layer),var(--state-layer))]`,
      );
    }
    expect(rule).toContain("motion-safe:not-disabled:active:scale-98");
    expect(rule).not.toMatch(/(^|\s)active:scale/);
  });

  it("is on the menus' items, 모두 학습, a deck row and a deck page's cards and switch", () => {
    render(
      <>
        <SideMenuAt path="/" account={null} />
        <TabBarAt path="/" />
        <EnterLink href="/study" label="모두 학습" />
        <DeckList
          rows={[
            {
              deck: { id: idOf(parseDeckId, "d-fr"), name: "French", public: false },
              cards: 1,
              today: 1,
              mastered: 0,
              learning: 0,
            },
          ]}
        />
        <CardGrid
          cards={[
            {
              id: idOf(parseCardId, "c-chat"),
              deckId: idOf(parseDeckId, "d-fr"),
              createdAt: 0,
              front: [{ kind: "text", text: "chat" }],
              back: [{ kind: "text", text: "cat" }],
            },
          ]}
        />
      </>,
    );

    const [side, bar] = screen.getAllByRole("navigation", { name: "주 메뉴" });
    for (const menu of [side, bar]) {
      for (const item of ["오늘", "덱", "기록"]) {
        expect(pressable(within(menu as HTMLElement).getByRole("link", { name: item }))).toBe(true);
      }
    }
    expect(pressable(screen.getByRole("link", { name: "모두 학습" }))).toBe(true);
    expect(pressable(screen.getByRole("link", { name: /^French/ }))).toBe(true);
    expect(pressable(screen.getByRole("button", { name: "chat, 뒷면 가려짐" }))).toBe(true);
    expect(pressable(screen.getByRole("switch", { name: "뒷면 보기" }))).toBe(true);
    // Control: the card search, a field, takes no button state.
    expect(pressable(screen.getByRole("searchbox", { name: "카드 검색" }))).toBe(false);
  });
});
