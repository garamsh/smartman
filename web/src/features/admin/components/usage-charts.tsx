"use client";

import { useId } from "react";
import { Bar, BarChart, CartesianGrid, ComposedChart, Line, XAxis, YAxis } from "recharts";

import type { Amount, Stack } from "../usage";

/** Dollars with four decimals, as "$0.0540". */
export function usd(value: number): string {
  return `$${value.toFixed(4)}`;
}

const axis = { stroke: "var(--color-muted)", fontSize: 12 } as const;
const shortDay = (day: string) => day.slice(5);

/**
 * Each day's photos as bars and their estimated cost as a dashed line, told apart by shape rather
 * than colour. The chart is one image named by [summary]; the table beside it holds every value.
 */
export function DailyUsageChart({
  days,
  summary,
}: {
  days: ({ day: string } & Amount)[];
  summary: string;
}) {
  return (
    <div role="img" aria-label={summary} className="h-60 w-full">
      <ComposedChart
        data={days}
        responsive
        accessibilityLayer={false}
        style={{ width: "100%", height: "100%" }}
        margin={{ top: 8, right: 8, bottom: 0, left: 0 }}
      >
        <CartesianGrid vertical={false} stroke="var(--color-hairline)" />
        <XAxis dataKey="day" tickFormatter={shortDay} tick={axis} stroke="var(--color-hairline)" />
        <YAxis
          yAxisId="photos"
          allowDecimals={false}
          tick={axis}
          stroke="var(--color-hairline)"
          width={36}
        />
        <YAxis
          yAxisId="usd"
          orientation="right"
          tickFormatter={(value: number) => `$${value.toFixed(2)}`}
          tick={axis}
          stroke="var(--color-hairline)"
          width={48}
        />
        <Bar yAxisId="photos" dataKey="photos" fill="var(--color-ink)" isAnimationActive={false} />
        <Line
          yAxisId="usd"
          dataKey="usd"
          stroke="var(--color-ink-2)"
          strokeWidth={2}
          strokeDasharray="5 3"
          dot={{ r: 2, fill: "var(--color-ink-2)" }}
          isAnimationActive={false}
        />
      </ComposedChart>
    </div>
  );
}

/** The fills a stacked series takes in turn, all in ink, so a series is told by its pattern. */
const patterns = ["solid", "stripes", "dots", "lines", "cross"] as const;

function Pattern({ id, kind }: { id: string; kind: (typeof patterns)[number] }) {
  return (
    <pattern id={id} width={6} height={6} patternUnits="userSpaceOnUse">
      {kind === "solid" && <rect width={6} height={6} fill="var(--color-ink)" />}
      {kind === "stripes" && (
        <path d="M-1,1 l2,-2 M0,6 l6,-6 M5,7 l2,-2" stroke="var(--color-ink)" strokeWidth={1.5} />
      )}
      {kind === "dots" && <circle cx={3} cy={3} r={1.4} fill="var(--color-ink)" />}
      {kind === "lines" && <path d="M0,3 h6" stroke="var(--color-ink)" strokeWidth={1.5} />}
      {kind === "cross" && (
        <path d="M0,0 l6,6 M6,0 l-6,6" stroke="var(--color-ink)" strokeWidth={1} />
      )}
    </pattern>
  );
}

/**
 * Each day's estimated cost stacked by [stack]'s series, each series in its own ink pattern with a
 * legend naming it, so no series is told by colour. The chart is one image named by [summary].
 */
export function StackedCostChart({ stack, summary }: { stack: Stack; summary: string }) {
  const id = useId().replaceAll(":", "");
  const fill = (index: number) => `url(#${id}-${String(index % patterns.length)})`;
  // Series keys can hold dots and slashes, which a data key would read as a path.
  const data = stack.days.map(({ day, values }) => ({
    day,
    ...Object.fromEntries(
      stack.series.map((series, index) => [`s${String(index)}`, values[series.key] ?? 0]),
    ),
  }));
  return (
    <div className="flex flex-col gap-2">
      <div role="img" aria-label={summary} className="h-60 w-full">
        <BarChart
          data={data}
          responsive
          accessibilityLayer={false}
          style={{ width: "100%", height: "100%" }}
          margin={{ top: 8, right: 8, bottom: 0, left: 0 }}
        >
          <defs>
            {patterns.map((kind, index) => (
              <Pattern key={kind} id={`${id}-${String(index)}`} kind={kind} />
            ))}
          </defs>
          <CartesianGrid vertical={false} stroke="var(--color-hairline)" />
          <XAxis
            dataKey="day"
            tickFormatter={shortDay}
            tick={axis}
            stroke="var(--color-hairline)"
          />
          <YAxis
            tickFormatter={(value: number) => `$${value.toFixed(2)}`}
            tick={axis}
            stroke="var(--color-hairline)"
            width={48}
          />
          {stack.series.map((series, index) => (
            <Bar
              key={series.key}
              dataKey={`s${String(index)}`}
              stackId="cost"
              fill={fill(index)}
              stroke="var(--color-ink)"
              strokeWidth={0.5}
              isAnimationActive={false}
            />
          ))}
        </BarChart>
      </div>
      <ul aria-hidden className="flex flex-wrap gap-x-4 gap-y-1 text-caption text-ink-2">
        {stack.series.map((series, index) => (
          <li key={series.key} className="flex items-center gap-1.5">
            <svg width={14} height={14} className="rounded-sm border border-ink">
              <defs>
                <Pattern
                  id={`${id}-legend-${String(index)}`}
                  kind={patterns[index % patterns.length] ?? "solid"}
                />
              </defs>
              <rect width={14} height={14} fill={`url(#${id}-legend-${String(index)})`} />
            </svg>
            {series.label}
          </li>
        ))}
      </ul>
    </div>
  );
}
