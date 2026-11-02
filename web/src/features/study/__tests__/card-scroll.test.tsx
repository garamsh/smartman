import { act, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { CardScroll } from "../components/card-scroll";

// jsdom lays nothing out, so the face reports the sizes a browser would: 200 px high, and its
// content's height in each step's type as [heights] says.
const faceHeight = 200;
let heights: Record<string, number> = {};
let scrollTop = 0;

function face() {
  const node = document.querySelector("[data-card-step]");
  if (!(node instanceof HTMLElement)) throw new Error("no face rendered");
  return node;
}

beforeEach(() => {
  scrollTop = 0;
  vi.spyOn(HTMLElement.prototype, "clientHeight", "get").mockImplementation(function (
    this: HTMLElement,
  ) {
    return this.hasAttribute("data-card-step") ? faceHeight : 0;
  });
  vi.spyOn(HTMLElement.prototype, "scrollHeight", "get").mockImplementation(function (
    this: HTMLElement,
  ) {
    const step = this.getAttribute("data-card-step");
    return step === null ? 0 : (heights[step] ?? 0);
  });
  vi.spyOn(HTMLElement.prototype, "scrollTop", "get").mockImplementation(() => scrollTop);
});

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

describe("a card's face", () => {
  it("keeps a front that fits at the front size there, centred, with no fade", () => {
    heights = { "text-front": 120, "text-back": 80, "text-card-body": 60 };
    render(<CardScroll>짧은 앞면</CardScroll>);

    expect(face().dataset.cardStep).toBe("text-front");
    expect(screen.getByText("짧은 앞면").className).toContain("text-center");
    expect(screen.getByText("짧은 앞면").className).toContain("break-keep");
    expect(document.querySelector("[data-card-fade]")).toBeNull();
  });

  it("steps a front down to the first size it fits whole, still centred", () => {
    heights = { "text-front": 320, "text-back": 180, "text-card-body": 150 };
    render(<CardScroll>중간 앞면</CardScroll>);

    expect(face().dataset.cardStep).toBe("text-back");
    expect(screen.getByText("중간 앞면").className).toContain("text-center");
    expect(document.querySelector("[data-card-fade]")).toBeNull();
  });

  it("past the body size scrolls start-aligned with a fading edge, which goes at the end", () => {
    heights = { "text-front": 900, "text-back": 600, "text-card-body": 500 };
    render(<CardScroll>긴 앞면</CardScroll>);

    expect(face().dataset.cardStep).toBe("text-card-body");
    expect(face().className).toContain("overflow-y-auto");
    expect(screen.getByText("긴 앞면").className).toContain("text-start");
    expect(document.querySelector("[data-card-fade]")).not.toBeNull();

    // Scrolled to its last line, nothing more is below.
    scrollTop = heights["text-card-body"] ?? 0;
    scrollTop -= faceHeight;
    fireEvent.scroll(face());
    expect(document.querySelector("[data-card-fade]")).toBeNull();
  });

  it("fits a front again when the card narrows while it holds the front size", () => {
    // jsdom has no ResizeObserver, so this one hands the test the callback a browser would call.
    let resized: (() => void) | undefined;
    vi.stubGlobal(
      "ResizeObserver",
      class {
        constructor(callback: () => void) {
          resized = callback;
        }
        observe() {}
        disconnect() {}
      },
    );
    let frameWidth = 720;
    vi.spyOn(HTMLElement.prototype, "offsetWidth", "get").mockImplementation(() => frameWidth);
    vi.spyOn(HTMLElement.prototype, "offsetHeight", "get").mockImplementation(() => faceHeight);
    heights = { "text-front": 120, "text-back": 80, "text-card-body": 60 };
    render(<CardScroll>좁아지는 앞면</CardScroll>);
    expect(face().dataset.cardStep).toBe("text-front");

    // At 350 px the front wraps to more lines than the face holds at the front size.
    frameWidth = 350;
    heights = { "text-front": 320, "text-back": 180, "text-card-body": 150 };
    act(() => {
      resized?.();
    });

    expect(face().dataset.cardStep).toBe("text-back");
  });
});
