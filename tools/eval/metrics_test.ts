import assert from "node:assert/strict";
import {
  type FieldCounts,
  normalize,
  percentile,
  recommend,
  type Row,
  score,
  summarize,
} from "./metrics.ts";

const NO_FIELDS: FieldCounts = {
  partOfSpeech: 0,
  partOfSpeechCorrect: 0,
  examples: 0,
  examplesCorrect: 0,
  fields: 0,
  invented: 0,
};

Deno.test("normalize applies NFKC, trims, collapses whitespace and lowercases", () => {
  assert.equal(normalize("  Ａpple \t\n Pie "), "apple pie");
  assert.equal(normalize("ｶﾞ"), "ガ");
  assert.equal(normalize("don't!"), "don't!", "punctuation is kept");
});

Deno.test("a candidate matches only when both sides match after normalization", () => {
  const truth = [{ front: "apple", meaning: "사과" }, {
    front: "river",
    meaning: "강",
  }];
  assert.deepEqual(
    score(
      [{ front: " Apple", meaning: "사과 " }, {
        front: "river",
        meaning: "강",
      }],
      truth,
    ),
    {
      precision: 1,
      recall: 1,
      f1: 1,
      fields: NO_FIELDS,
    },
  );
  const wrongBack = score([{ front: "apple", meaning: "배" }, {
    front: "river",
    meaning: "강",
  }], truth);
  assert.equal(wrongBack.precision, 0.5);
  assert.equal(wrongBack.recall, 0.5);
});

Deno.test("each ground-truth card matches at most one candidate", () => {
  const truth = [{ front: "apple", meaning: "사과" }];
  const twice = score([{ front: "apple", meaning: "사과" }, {
    front: "apple",
    meaning: "사과",
  }], truth);
  assert.equal(twice.precision, 0.5);
  assert.equal(twice.recall, 1);
  assert.ok(Math.abs(twice.f1 - 2 / 3) < 1e-12);
});

Deno.test("an image with no candidates scores zero", () => {
  assert.deepEqual(score([], [{ front: "a", meaning: "b" }]), {
    precision: 0,
    recall: 0,
    f1: 0,
    fields: NO_FIELDS,
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
      score: {
        precision: 1,
        recall: 0.5,
        f1: 2 / 3,
        fields: {
          ...NO_FIELDS,
          partOfSpeech: 2,
          partOfSpeechCorrect: 1,
          fields: 2,
        },
      },
      latencyMs: 1000,
      costUsd: 0.01,
    },
    {
      score: { precision: 0, recall: 0, f1: 0, fields: NO_FIELDS },
      latencyMs: 3000,
      costUsd: 0.03,
    },
  ]);
  assert.equal(row.precision, 0.5);
  assert.equal(row.recall, 0.25);
  assert.equal(row.partOfSpeechPrecision, 0.5);
  assert.equal(row.examplesPrecision, null, "no examples were returned");
  assert.equal(row.inventedRate, 0);
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
  partOfSpeechPrecision: null,
  examplesPrecision: null,
  inventedRate: null,
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

Deno.test("a candidate matches on front and meaning, whatever its part of speech or examples", () => {
  const page = [{ front: "run", meaning: "달리다", partOfSpeech: "[동]" }];
  const r = score(
    [{ front: "run", meaning: "달리다", partOfSpeech: "n." }],
    page,
  );
  assert.equal(r.recall, 1);
  assert.equal(r.fields.partOfSpeech, 1);
  assert.equal(r.fields.partOfSpeechCorrect, 0, "a wrong part of speech");
  assert.equal(
    score([{ front: "run", meaning: "뛰다" }], page).recall,
    0,
    "control: another meaning does not match",
  );
});

Deno.test("field precision counts parts of speech and examples equal to the page's", () => {
  const page = [{
    front: "run",
    meaning: "달리다",
    partOfSpeech: "[동]",
    examples: ["I run every morning.", "run a shop"],
  }];
  const r = score([{
    front: "run",
    meaning: "달리다",
    partOfSpeech: " [동]",
    examples: ["I run every  morning.", "run a bath"],
  }], page);
  assert.deepEqual(r.fields, {
    partOfSpeech: 1,
    partOfSpeechCorrect: 1,
    examples: 2,
    examplesCorrect: 1,
    fields: 2,
    invented: 0,
  });
});

Deno.test("a field the page does not print counts as invented, and an absent one does not", () => {
  const page = [{ front: "apple", meaning: "사과" }];
  const invented = score([{
    front: "apple",
    meaning: "사과",
    partOfSpeech: "n.",
    examples: ["She ate an apple."],
  }], page);
  assert.equal(invented.fields.fields, 2);
  assert.equal(invented.fields.invented, 2);
  const absent = score([{ front: "apple", meaning: "사과" }], page);
  assert.deepEqual(absent.fields, NO_FIELDS, "control: nothing returned");
  const printed = score([{
    front: "apple",
    meaning: "사과",
    partOfSpeech: "n.",
  }], [{
    ...page[0],
    partOfSpeech: "n.",
  }]);
  assert.equal(printed.fields.invented, 0, "control: a printed field");
});

Deno.test("an unmatched candidate's fields are not counted", () => {
  const r = score([{ front: "pear", meaning: "배", partOfSpeech: "n." }], [{
    front: "apple",
    meaning: "사과",
  }]);
  assert.deepEqual(r.fields, NO_FIELDS);
});
