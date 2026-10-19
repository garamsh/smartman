import { describe, expect, it } from "vitest";

import { lineDiff } from "../prompt-diff";

describe("a prompt's line diff", () => {
  it("keeps the shared lines once and marks each other line removed or added, in order", () => {
    expect(lineDiff("intro\nold rule\nend", "intro\nnew rule\nextra\nend")).toEqual([
      { kind: "same", text: "intro" },
      { kind: "removed", text: "old rule" },
      { kind: "added", text: "new rule" },
      { kind: "added", text: "extra" },
      { kind: "same", text: "end" },
    ]);
  });

  it("marks nothing between equal texts, and everything between texts sharing no line", () => {
    expect(lineDiff("a\nb", "a\nb").every((line) => line.kind === "same")).toBe(true);
    expect(lineDiff("a", "b")).toEqual([
      { kind: "removed", text: "a" },
      { kind: "added", text: "b" },
    ]);
  });

  it("keeps a moved line's longest shared run, not its first match", () => {
    expect(lineDiff("x\na\nb\nc", "a\nb\nc\nx").filter((line) => line.kind !== "same")).toEqual([
      { kind: "removed", text: "x" },
      { kind: "added", text: "x" },
    ]);
  });
});
