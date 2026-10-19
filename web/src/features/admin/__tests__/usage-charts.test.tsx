import { render } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { DailyUsageChart, StackedCostChart } from "../components/usage-charts";
import type { Stack } from "../usage";

// jsdom lays nothing out, so the charts' container is given a size as a browser would.
beforeEach(() => {
  vi.stubGlobal(
    "ResizeObserver",
    class {
      constructor(private readonly callback: ResizeObserverCallback) {}
      observe(target: Element) {
        this.callback(
          [{ target, contentRect: { width: 600, height: 240 } } as unknown as ResizeObserverEntry],
          this,
        );
      }
      unobserve() {}
      disconnect() {}
    },
  );
  vi.spyOn(HTMLElement.prototype, "getBoundingClientRect").mockReturnValue(
    DOMRect.fromRect({ width: 600, height: 240 }),
  );
  vi.spyOn(HTMLElement.prototype, "clientWidth", "get").mockReturnValue(600);
  vi.spyOn(HTMLElement.prototype, "clientHeight", "get").mockReturnValue(240);
});
afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

const days = ["2026-10-17", "2026-10-18", "2026-10-19"];

describe("the usage charts", () => {
  it("draw a bar for each day with photos and a dashed cost line, inside one named image", () => {
    const { container, getByRole } = render(
      <DailyUsageChart
        days={days.map((day, index) => ({ day, photos: index, usd: index * 0.0018, unpriced: 0 }))}
        summary="summary"
      />,
    );
    expect(getByRole("img", { name: "summary" })).toBeInTheDocument();
    expect(container.querySelectorAll(".recharts-bar-rectangle path")).toHaveLength(2);
    expect(container.querySelector(".recharts-line path")).toHaveAttribute(
      "stroke-dasharray",
      "5 3",
    );
  });

  it("stack each series in its own pattern, named in the legend", () => {
    const stack: Stack = {
      series: [
        { key: "free", label: "무료" },
        { key: "a/b.c", label: "a/b.c" },
      ],
      days: days.map((day) => ({ day, values: { free: 0.01, "a/b.c": 0.02 } })),
      totals: {},
    };
    const { container, getByText } = render(<StackedCostChart stack={stack} summary="summary" />);
    const fills = [...container.querySelectorAll(".recharts-bar-rectangle path")].map((bar) =>
      bar.getAttribute("fill"),
    );
    expect(fills).toHaveLength(6);
    expect(new Set(fills).size).toBe(2);
    expect(fills.every((fill) => fill?.startsWith("url(#"))).toBe(true);
    expect(getByText("a/b.c")).toBeInTheDocument();
  });
});
