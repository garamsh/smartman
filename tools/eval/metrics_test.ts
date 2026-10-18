import assert from "node:assert/strict";
import {
  covers,
  entryOf,
  type FieldCounts,
  normalize,
  type NotesRow,
  percentile,
  recommend,
  type Row,
  score,
  scoreNotes,
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
      name: "01",
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
      notes: null,
      latencyMs: 1000,
      costUsd: 0.01,
      completionTokens: 0,
    },
    {
      name: "02",
      score: { precision: 0, recall: 0, f1: 0, fields: NO_FIELDS },
      notes: null,
      latencyMs: 3000,
      costUsd: 0.03,
      completionTokens: 0,
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
  assert.equal(row.notes, null, "no notes image ran");
});

const row = (
  label: string,
  f1: number,
  costPerImageUsd: number,
  notes: NotesRow | null = null,
): Row => ({
  label,
  precision: f1,
  recall: f1,
  f1,
  partOfSpeechPrecision: null,
  examplesPrecision: null,
  inventedRate: null,
  notes,
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

// Notes pages: a page teaching four facts at steps 1, 2, 3 and 5, and printing one example.
const notesTruth = {
  facts: [
    { id: "deduction", step: 1 as const, terms: ["연역", "반드시"] },
    { id: "induction", step: 2 as const, terms: ["귀납", "개연"] },
    { id: "premise", step: 3 as const, terms: ["전제", "근거"] },
    { id: "example", step: 5 as const, terms: ["652788"] },
  ],
  examples: ["253+4637+647898=652788 -> 연역"],
  lines: [
    "5. 연역과 귀납",
    "연역 논증: 전제가 참이면 결론이 반드시 참",
    "'하다'는 '-여'가 붙는다: 하+여 -> 하여(해)",
    "예) 253+4637+647898=652788 -> 연역",
  ],
};
const noteCard = (
  front: string,
  answer: string,
  step: 1 | 2 | 3 | 4 | 5 = 1,
) => ({
  front,
  answer,
  step,
});

Deno.test("a card covers a fact when its front and answer hold every term after normalization", () => {
  const fact = notesTruth.facts[1];
  assert.equal(
    covers(noteCard("귀납 논증이란?", "결론이 개연적으로 참"), fact),
    true,
  );
  assert.equal(
    covers(noteCard("Induction", "결론이 개연적으로 참"), fact),
    false,
    "a term missing from both sides",
  );
  assert.equal(
    covers(
      noteCard("Law  of DEMAND", "falls"),
      { id: "x", step: 1, terms: ["law of demand"] },
    ),
    true,
    "case and whitespace are normalized",
  );
});

Deno.test("a worked example kept as the example of the card it illustrates covers its fact", () => {
  const fact = notesTruth.facts[3];
  const rule = noteCard("연역 논증이란?", "전제가 참이면 결론이 반드시 참", 1);
  // Control: the rule alone holds none of the example's terms.
  assert.equal(covers(rule, fact), false);
  assert.equal(
    covers({ ...rule, examples: ["253+4637+647898=652788 -> 연역"] }, fact),
    true,
  );
  const notes = scoreNotes([
    { ...rule, examples: ["253+4637+647898=652788 -> 연역"] },
  ], notesTruth);
  assert.equal(notes.coverage[4], 2 / 4, "the rule and its example");
  assert.equal(notes.unsupported, 0);
});

Deno.test("coverage at a step counts the facts of that step or below covered by cards of that step or below", () => {
  const notes = scoreNotes([
    noteCard("연역 논증", "전제가 참이면 결론이 반드시 참", 1),
    // The premise fact, offered only from step 4.
    noteCard("전제란?", "결론을 뒷받침하는 근거", 4),
  ], notesTruth);
  assert.deepEqual(notes.coverage, [1, 1 / 2, 1 / 3, 2 / 3, 2 / 4]);
});

Deno.test("an image with no candidates covers nothing and has no counts", () => {
  const notes = scoreNotes([], notesTruth);
  assert.deepEqual(notes.coverage, [0, 0, 0, 0, 0]);
  assert.equal(notes.cards, 0);
  assert.equal(notes.pairs, 0);
});

Deno.test("a card covering no fact is unsupported", () => {
  const notes = scoreNotes([
    noteCard("연역 논증", "결론이 반드시 참", 1),
    noteCard("논리학의 아버지는?", "아리스토텔레스", 2),
  ], notesTruth);
  assert.equal(notes.cards, 2);
  assert.equal(notes.unsupported, 1, "control: the first card covers a fact");
});

Deno.test("an example the page does not print is invented, and one printed with or without its label is not", () => {
  const notes = scoreNotes([{
    ...noteCard("연역 논증", "결론이 반드시 참", 1),
    examples: [
      "253+4637+647898=652788 -> 연역",
      "예) 253+4637+647898=652788 -> 연역",
      "모든 사람은 죽는다 -> 소크라테스는 죽는다",
    ],
  }], notesTruth);
  assert.equal(notes.examples, 3);
  assert.equal(notes.inventedExamples, 1);
});

Deno.test("an example printed inside a rule's line is not invented, and one no line prints is", () => {
  const notes = scoreNotes([{
    ...noteCard("'하다'의 어미는?", "'-여'가 붙는다", 2),
    examples: ["하+여 -> 하여(해)", "하+어 -> 해어"],
  }], notesTruth);
  assert.equal(notes.examples, 2);
  assert.equal(
    notes.inventedExamples,
    1,
    "the rule line holds the first; control: no line holds the second",
  );
});

Deno.test("step order counts the pairs of covered facts the returned steps order alike, and their ties", () => {
  const notes = scoreNotes([
    noteCard("연역", "결론이 반드시 참", 1),
    noteCard("귀납", "결론이 개연적으로 참", 3),
    // Placed above the induction card, though the page puts it at step 3.
    noteCard("전제", "근거가 되는 문장", 2),
    noteCard("예", "652788", 3),
  ], notesTruth);
  // Pairs: (1,2) alike, (1,3) alike, (1,5) alike, (2,3) reversed, (2,5) tie, (3,5) alike.
  assert.equal(notes.pairs, 6);
  assert.equal(notes.concordant, 4);
  assert.equal(notes.ties, 1);
});

Deno.test("summarize averages notes coverage over the notes images and pools their counts", () => {
  const vocabulary = {
    name: "01-vocabulary",
    score: { precision: 1, recall: 1, f1: 1, fields: NO_FIELDS },
    notes: null,
    latencyMs: 1000,
    costUsd: 0.01,
    completionTokens: 50,
  };
  const full = scoreNotes([
    noteCard("연역", "결론이 반드시 참", 1),
    noteCard("귀납", "결론이 개연적으로 참", 2),
    noteCard("전제", "근거가 되는 문장", 3),
    { ...noteCard("예", "652788", 5), examples: ["652788 -> 연역"] },
  ], notesTruth);
  const empty = scoreNotes([], notesTruth);
  const row = summarize("m", [
    vocabulary,
    {
      name: "02-notes",
      score: null,
      notes: full,
      latencyMs: 2000,
      costUsd: 0.02,
      completionTokens: 900,
    },
    {
      name: "03-notes",
      score: null,
      notes: empty,
      latencyMs: 3000,
      costUsd: 0.03,
      completionTokens: 0,
    },
  ]);
  assert.equal(row.f1, 1, "vocabulary scores average over vocabulary images");
  assert.deepEqual(row.notes, {
    coverage: [0.5, 0.5, 0.5, 0.5, 0.5],
    unsupportedRate: 0,
    inventedExamplesRate: 0,
    stepAgreement: 1,
    pages: [
      { name: "02-notes", coverage: 1, completionTokens: 900 },
      { name: "03-notes", coverage: 0, completionTokens: 0 },
    ],
  });
  assert.ok(Math.abs(row.costPerImageUsd - 0.02) < 1e-12, "over every image");
});

const notesRow = (coverage5: number): NotesRow => ({
  coverage: [null, null, null, null, coverage5],
  unsupportedRate: null,
  inventedExamplesRate: null,
  stepAgreement: null,
  pages: [],
});

Deno.test("with notes results, the recommendation must also be within 5 points of the best coverage at step 5", () => {
  const rows = [
    row("best", 0.95, 0.05, notesRow(0.9)),
    row("cheap but misses notes", 0.95, 0.001, notesRow(0.8)),
    row("cheap enough", 0.94, 0.01, notesRow(0.86)),
  ];
  assert.equal(recommend(rows)?.label, "cheap enough");
  assert.equal(
    recommend([row("best", 0.95, 0.05), row("cheap", 0.95, 0.001)])?.label,
    "cheap",
    "control: without notes results coverage plays no part",
  );
  assert.equal(
    recommend([
      row("vocabulary", 0.95, 0.01, notesRow(0.5)),
      row("notes", 0.5, 0.01, notesRow(0.9)),
    ]),
    null,
    "no configuration within both bounds",
  );
});

Deno.test("a returned card without a meaning is matched on a vocabulary page by its answer", () => {
  const truth = [{ front: "apple", meaning: "사과" }];
  const asNote = entryOf({
    kind: "note",
    front: "apple",
    answer: "사과",
    short: "사과",
    step: 1,
    back: "사과",
  });
  assert.deepEqual(asNote, { front: "apple", meaning: "사과" });
  assert.equal(score([asNote], truth).f1, 1);
  const vocabulary = entryOf({
    kind: "vocabulary",
    front: "apple",
    answer: "사과, 능금",
    short: "사과",
    step: 1,
    back: "n. 사과",
    meaning: "사과",
    partOfSpeech: "n.",
  });
  assert.equal(
    vocabulary.meaning,
    "사과",
    "control: a card's meaning is used over its answer",
  );
});
