import assert from "node:assert/strict";
import {
  normalize,
  percentile,
  recommend,
  type Row,
  score,
  summarize,
} from "./metrics.ts";

Deno.test("normalize applies NFKC, trims, collapses whitespace and lowercases", () => {
  assert.equal(normalize("  Ａpple \t\n Pie "), "apple pie");
  assert.equal(normalize("ｶﾞ"), "ガ");
  assert.equal(normalize("don't!"), "don't!", "punctuation is kept");
});

Deno.test("a candidate matches only when both sides match after normalization", () => {
  const truth = [{ front: "apple", back: "사과" }, {
    front: "river",
    back: "강",
  }];
  assert.deepEqual(
    score(
      [{ front: " Apple", back: "사과 " }, { front: "river", back: "강" }],
      truth,
    ),
    {
      precision: 1,
      recall: 1,
      f1: 1,
    },
  );
  const wrongBack = score([{ front: "apple", back: "배" }, {
    front: "river",
    back: "강",
  }], truth);
  assert.equal(wrongBack.precision, 0.5);
  assert.equal(wrongBack.recall, 0.5);
});

Deno.test("each ground-truth card matches at most one candidate", () => {
  const truth = [{ front: "apple", back: "사과" }];
  const twice = score([{ front: "apple", back: "사과" }, {
    front: "apple",
    back: "사과",
  }], truth);
  assert.equal(twice.precision, 0.5);
  assert.equal(twice.recall, 1);
  assert.ok(Math.abs(twice.f1 - 2 / 3) < 1e-12);
});

Deno.test("an image with no candidates scores zero", () => {
  assert.deepEqual(score([], [{ front: "a", back: "b" }]), {
    precision: 0,
    recall: 0,
    f1: 0,
  });
});

Deno.test("percentile takes the nearest rank", () => {
  const values = [10, 1, 9, 2, 8, 3, 7, 4, 6, 5];
  assert.equal(percentile(values, 50), 5);
  assert.equal(percentile(values, 90), 9);
  assert.equal(percentile([42], 90), 42);
});

Deno.test("summarize averages per-image scores and sums the spend", () => {
  const row = summarize("m", [
    {
      score: { precision: 1, recall: 0.5, f1: 2 / 3 },
      latencyMs: 1000,
      costUsd: 0.01,
    },
    {
      score: { precision: 0, recall: 0, f1: 0 },
      latencyMs: 3000,
      costUsd: 0.03,
    },
  ]);
  assert.equal(row.precision, 0.5);
  assert.equal(row.recall, 0.25);
  assert.equal(row.p50Ms, 1000);
  assert.equal(row.p90Ms, 3000);
  assert.ok(Math.abs(row.costPerImageUsd - 0.02) < 1e-12);
  assert.ok(Math.abs(row.spentUsd - 0.04) < 1e-12);
});

const row = (label: string, f1: number, costPerImageUsd: number): Row => ({
  label,
  precision: f1,
  recall: f1,
  f1,
  p50Ms: 0,
  p90Ms: 0,
  costPerImageUsd,
  spentUsd: 0,
});

Deno.test("the recommendation is the cheapest configuration within 2 F1 points of the best", () => {
  const rows = [
    row("best", 0.95, 0.05),
    row("close", 0.931, 0.01),
    row("cheap", 0.92, 0.001),
  ];
  assert.equal(
    recommend(rows)?.label,
    "close",
    "0.92 is 3 points below the best and is passed over",
  );
  assert.equal(
    recommend([row("best", 0.95, 0.05), row("edge", 0.93, 0.01)])?.label,
    "edge",
    "exactly 2 points",
  );
  assert.equal(recommend([row("only", 0.5, 1)])?.label, "only");
  assert.equal(recommend([]), null);
});

Deno.test("among equally cheap eligible configurations the higher F1 is recommended", () => {
  assert.equal(
    recommend([row("a", 0.94, 0.01), row("b", 0.95, 0.01)])?.label,
    "b",
  );
});
