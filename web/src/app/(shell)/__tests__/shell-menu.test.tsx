import { cleanup, render, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

import { SideMenu, TabBar } from "../_components/shell-menu";

let path = "/";
vi.mock("next/navigation", () => ({ usePathname: () => path }));

/** Each link of [menu] as "name → href", the current page marked. */
function links(menu: HTMLElement) {
  return within(menu)
    .getAllByRole("link")
    .map(
      (link) =>
        `${link.getAttribute("aria-label") ?? link.textContent} → ${String(link.getAttribute("href"))}${link.getAttribute("aria-current") === "page" ? " (current)" : ""}`,
    );
}

describe("the shell's menus", () => {
  afterEach(cleanup);

  it.each([
    ["/", "오늘"],
    ["/decks", "덱"],
    ["/decks/d-fr", "덱"],
    ["/record", "기록"],
  ])("on %s mark %s as the current page, in the side menu and the tab bar", (at, current) => {
    path = at;
    render(
      <>
        <SideMenu account={<a href="/account">설정</a>} />
        <TabBar />
      </>,
    );
    const [side, tabs] = screen.getAllByRole("navigation", { name: "주 메뉴" });
    const pages = ["오늘 → /", "덱 → /decks", "기록 → /record"].map((link) =>
      link.startsWith(current) ? `${link} (current)` : link,
    );

    expect(links(side ?? document.body)).toEqual([
      "알아몰라, 오늘 → /",
      ...pages,
      "설정 → /account",
    ]);
    expect(links(tabs ?? document.body)).toEqual(pages);
  });

  it("draw the current page a coral-tinted pill behind its icon and a bold label, the others muted, on both menus", () => {
    path = "/decks";
    render(
      <>
        <SideMenu account={null} />
        <TabBar />
      </>,
    );
    const menus = screen.getAllByRole("navigation", { name: "주 메뉴" });
    expect(menus).toHaveLength(2);
    for (const menu of menus) {
      const current = within(menu).getByRole("link", { name: "덱" });
      expect(current).toHaveClass("text-ink");
      expect(current.className).toMatch(/font-bold|text-label/);
      expect(current.querySelector("svg")?.parentElement).toHaveClass("bg-brand-tint");
      // Control: another page has the pill's place and no tint.
      const other = within(menu).getByRole("link", { name: "기록" });
      expect(other).toHaveClass("text-muted");
      expect(other).not.toHaveClass("text-ink");
      expect(other.querySelector("svg")?.parentElement).not.toHaveClass("bg-brand-tint");
    }
  });

  it("show the side menu from 1024 px wide and the tab bar below it", () => {
    path = "/";
    render(
      <>
        <SideMenu account={null} />
        <TabBar />
      </>,
    );
    const [side, tabs] = screen.getAllByRole("navigation", { name: "주 메뉴" });

    // The side menu shows and hides with the column that draws its surface down the page.
    expect(side?.parentElement).toHaveClass("hidden", "lg:block");
    expect(tabs).toHaveClass("lg:hidden");
    expect(tabs).not.toHaveClass("hidden");
  });
});
