import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";

import { themeStorageKey } from "@/design/theme";

import { ThemeChoice } from "../theme-choice";

/** The choice under the heading that labels it, as the account page lays it out. */
function renderChoice() {
  render(
    <section>
      <h2 id="display">화면</h2>
      <ThemeChoice labelledBy="display" />
    </section>,
  );
}

describe("the theme choice", () => {
  afterEach(() => {
    localStorage.clear();
    delete document.documentElement.dataset.theme;
    vi.restoreAllMocks();
  });

  it("is a radio group named 화면 offering 시스템, 라이트 and 다크, with 시스템 checked by default", () => {
    renderChoice();

    const group = screen.getByRole("radiogroup", { name: "화면" });
    expect(group).toBeInTheDocument();
    expect(
      screen.getAllByRole("radio").map((radio) => radio.closest("label")?.textContent),
    ).toEqual(["시스템", "라이트", "다크"]);
    expect(screen.getByRole("radio", { name: "시스템" })).toBeChecked();
  });

  it("draws the three as one group of hairline rows, the chosen one's check shown, and no shadow", () => {
    document.documentElement.dataset.theme = "light";
    renderChoice();

    const group = screen.getByRole("radiogroup", { name: "화면" });
    expect(group).toHaveClass("rounded-group", "bg-surface", "divide-y", "divide-hairline");
    expect(group.querySelector('[class*="shadow"]')).toBeNull();
    // Each row ends with a check that shows once its radio is checked, the selection's check.
    expect(
      screen.getAllByRole("radio").map((radio) => {
        const check = radio.closest("label")?.querySelector("svg");
        return [radio.matches(":checked"), check?.getAttribute("class")?.split(" ")];
      }),
    ).toEqual(
      ["시스템", "라이트", "다크"].map((name) => [
        name === "라이트",
        expect.arrayContaining(["invisible", "peer-checked:visible"]),
      ]),
    );
  });

  it("checks the theme the page was first drawn in", () => {
    document.documentElement.dataset.theme = "dark";

    renderChoice();

    expect(screen.getByRole("radio", { name: "다크" })).toBeChecked();
    expect(screen.getByRole("radio", { name: "시스템" })).not.toBeChecked();
  });

  it("applies a choice at once and keeps it on this browser; 시스템 returns to the system's", async () => {
    renderChoice();

    await userEvent.click(screen.getByRole("radio", { name: "다크" }));
    expect(document.documentElement.dataset.theme).toBe("dark");
    expect(localStorage.getItem(themeStorageKey)).toBe("dark");
    expect(screen.getByRole("radio", { name: "다크" })).toBeChecked();

    await userEvent.click(screen.getByRole("radio", { name: "라이트" }));
    expect(document.documentElement.dataset.theme).toBe("light");
    expect(localStorage.getItem(themeStorageKey)).toBe("light");

    await userEvent.click(screen.getByRole("radio", { name: "시스템" }));
    expect(document.documentElement.hasAttribute("data-theme")).toBe(false);
    expect(localStorage.getItem(themeStorageKey)).toBeNull();
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  it("is moved with the arrow keys, as a radio group is", async () => {
    renderChoice();

    await userEvent.click(screen.getByRole("radio", { name: "시스템" }));
    await userEvent.keyboard("{ArrowRight}");

    expect(screen.getByRole("radio", { name: "라이트" })).toBeChecked();
    expect(document.documentElement.dataset.theme).toBe("light");
  });

  it("still applies a choice the browser refuses to keep, and says it was not kept", async () => {
    vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
      throw new DOMException("full", "QuotaExceededError");
    });
    renderChoice();

    await userEvent.click(screen.getByRole("radio", { name: "다크" }));

    expect(document.documentElement.dataset.theme).toBe("dark");
    expect(screen.getByRole("alert")).toHaveTextContent(
      "이 브라우저에 설정을 저장하지 못했어요. 다시 열면 이전 설정으로 보여요.",
    );
  });
});
