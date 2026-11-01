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
