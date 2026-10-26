import { render } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import type { Content } from "../card-content";
import { WholeCard } from "../components/whole-card";

// A wide photo and a tall one, each with a box near the top left holding an answer and one near
// the bottom right without, as the app's `image_block_test.dart` draws them (ADR 0109).
const boxes = [
  { id: "1", x: 0.1, y: 0.2, w: 0.3, h: 0.15, answer: "Paris" },
  { id: "2", x: 0.55, y: 0.7, w: 0.4, h: 0.25, answer: null },
];
const photos: Content[] = [
  { kind: "image", media: "wide", width: 1600, height: 900, boxes },
  { kind: "image", media: "tall", width: 600, height: 1200, boxes },
];

/** [photo] drawn in a container [width] CSS pixels wide, revealed or not. */
function draw(photo: Content, width: number, revealed = false) {
  const { container } = render(
    <div style={{ width: `${String(width)}px` }}>
      <WholeCard blocks={[photo]} revealed={revealed} />
    </div>,
  );
  const frame = container.querySelector<HTMLElement>("[data-image]");
  const marks = [...container.querySelectorAll<HTMLElement>("[data-box]")];
  return { container, frame, marks };
}

/**
 * Where each box falls in pixels inside a frame [width] wide, from the CSS that places it: the
 * frame's height follows from its aspect ratio, and each box's place and size are percentages of
 * the frame. jsdom lays nothing out, so this reads the CSS rather than measuring the page.
 */
function placed(frame: HTMLElement, marks: HTMLElement[], width: number) {
  const [w, h] = frame.style.aspectRatio.split("/").map(Number);
  const height = (width * (h ?? 0)) / (w ?? 1);
  const at = (value: string, of: number) => (Number.parseFloat(value) / 100) * of;
  return marks.map((mark) => ({
    left: at(mark.style.left, width) / width,
    top: at(mark.style.top, height) / height,
    width: at(mark.style.width, width) / width,
    height: at(mark.style.height, height) / height,
  }));
}

describe("a photo on a whole card", () => {
  for (const photo of photos) {
    if (photo.kind !== "image") continue;
    it(`draws the ${photo.media} photo's frame at its aspect ratio and each box over the same part of it at 320 and 1024 px`, () => {
      for (const width of [320, 1024]) {
        const { frame, marks } = draw(photo, width);
        expect(frame, `${String(width)} px`).not.toBeNull();
        if (!frame) continue;
        expect(frame.style.aspectRatio).toBe(`${String(photo.width)} / ${String(photo.height)}`);
        expect(frame.className).toContain("w-full");
        const fractions = placed(frame, marks, width);
        expect(fractions).toHaveLength(photo.boxes.length);
        photo.boxes.forEach((box, index) => {
          const drawn = fractions[index];
          for (const [part, value] of [
            ["left", box.x],
            ["top", box.y],
            ["width", box.w],
            ["height", box.h],
          ] as const) {
            expect(drawn?.[part], `${String(width)} px, box ${box.id}, ${part}`).toBeCloseTo(
              value,
              9,
            );
          }
        });
      }
    });
  }

  it("bounds each photo's frame to a height, its width following from its aspect ratio, so a tall photo fits", () => {
    for (const photo of photos) {
      if (photo.kind !== "image") continue;
      const { frame } = draw(photo, 1024);
      // At most 60dvh tall: as wide as 60dvh times width over height, in whatever form jsdom
      // keeps the calc.
      const maxWidth = frame?.style.maxWidth ?? "";
      expect(maxWidth, photo.media).toMatch(/^(calc\()?[\d.]+dvh\)?$/);
      expect(Number.parseFloat(maxWidth.replace("calc(", "")), photo.media).toBeCloseTo(
        (60 * photo.width) / photo.height,
        2,
      );
      expect(frame?.className, photo.media).toContain("mx-auto");
    }
  });

  it("hides each box with an opaque fill until revealed, then outlines it with its answer", () => {
    const [photo] = photos;
    if (!photo) return;

    const hidden = draw(photo, 320);
    expect(hidden.marks.map((mark) => mark.dataset.box)).toEqual(["hidden", "hidden"]);
    expect(hidden.marks.every((mark) => mark.className.includes("bg-hero"))).toBe(true);
    expect(hidden.container.textContent).not.toContain("Paris");
    expect(hidden.container.querySelector("[role=group]")?.getAttribute("aria-label")).toBe(
      "사진, 빈칸, 빈칸",
    );

    const revealed = draw(photo, 320, true);
    expect(revealed.marks.map((mark) => mark.dataset.box)).toEqual(["revealed", "revealed"]);
    expect(revealed.marks.every((mark) => mark.className.includes("border-2"))).toBe(true);
    expect(revealed.marks[0]?.textContent).toBe("Paris");
    expect(revealed.marks[1]?.textContent).toBe("");
    expect(revealed.container.querySelector("[role=group]")?.getAttribute("aria-label")).toBe(
      "사진, Paris, 빈칸",
    );
  });
});
