import assert from "node:assert/strict";
import type {
  Extra,
  Sense,
  SenseLabel,
} from "../../supabase/functions/extract-cards/cards.ts";
import {
  blankCovered,
  covers,
  type Entry,
  entryOf,
  type FieldCounts,
  isBareException,
  listedItems,
  normalize,
  type NotesRow,
  percentile,
  recommend,
  type Row,
  score,
  scoreNotes,
  summarize,
} from "./metrics.ts";

const NO_SENSES = { returned: 0, page: 0, matched: 0 };

const NO_FIELDS: FieldCounts = {
  labels: 0,
  labelsCorrect: 0,
  pageLabels: 0,
  categoriesCorrect: 0,
  unlabelledSenses: 0,
  unprintedLabels: 0,
  examples: 0,
  examplesCorrect: 0,
  senseExamples: 0,
  senseExamplesReturned: 0,
  extras: 0,
  extrasReturned: 0,
  fields: 0,
  invented: 0,
};

const VERB: SenseLabel = {
  kind: "part_of_speech",
  category: "verb",
  text: "동",
};
const NOUN: SenseLabel = {
  kind: "part_of_speech",
  category: "noun",
  text: "명",
};
const CLASS: SenseLabel = { kind: "other", category: null, text: "사물" };

/** A sense of [meaning] with [labels] and [examples]. */
const sense = (
  meaning: string,
  labels: readonly SenseLabel[] = [],
  examples: string[] = [],
): Sense => ({ labels, meaning, examples });

/** An entry of one sense of [meaning] with [labels], and [fields] such as its examples. */
const entry = (
  front: string,
  meaning: string,
  labels: readonly SenseLabel[] = [],
  fields: { examples?: readonly string[]; extras?: readonly Extra[] } = {},
): Entry => ({ front, senses: [sense(meaning, labels)], ...fields });

/** The field counts of [candidate] scored against [page], each one entry. */
const fieldsOf = (candidate: Entry, page: Entry) =>
  score([candidate], [page]).fields;

Deno.test("normalize applies NFKC, trims, collapses whitespace and lowercases", () => {
  assert.equal(normalize("  Ａpple \t\n Pie "), "apple pie");
  assert.equal(normalize("ｶﾞ"), "ガ");
  assert.equal(normalize("don't!"), "don't!", "punctuation is kept");
});

Deno.test("a candidate matches only when both sides match after normalization", () => {
  const truth = [entry("apple", "사과"), entry("river", "강")];
  assert.deepEqual(
    score([entry(" Apple", "사과 "), entry("river", "강")], truth),
    {
      precision: 1,
      recall: 1,
      f1: 1,
      fields: { ...NO_FIELDS, unlabelledSenses: 2 },
      senses: { returned: 2, page: 2, matched: 2 },
    },
  );
  const wrongBack = score([entry("apple", "배"), entry("river", "강")], truth);
  assert.equal(wrongBack.precision, 0.5);
  assert.equal(wrongBack.recall, 0.5);
});

Deno.test("each ground-truth card matches at most one candidate", () => {
  const truth = [entry("apple", "사과")];
  const twice = score([entry("apple", "사과"), entry("apple", "사과")], truth);
  assert.equal(twice.precision, 0.5);
  assert.equal(twice.recall, 1);
  assert.ok(Math.abs(twice.f1 - 2 / 3) < 1e-12);
});

Deno.test("an image with no candidates scores zero", () => {
  assert.deepEqual(score([], [entry("a", "b")]), {
    precision: 0,
    recall: 0,
    f1: 0,
    fields: NO_FIELDS,
    senses: NO_SENSES,
  });
});

Deno.test("percentile takes the nearest rank", () => {
  const values = [10, 1, 9, 2, 8, 3, 7, 4, 6, 5];
  assert.equal(percentile(values, 50), 5);
  assert.equal(percentile(values, 90), 9);
  assert.equal(percentile([42], 90), 42);
});

Deno.test("summarize averages per-image scores, pools the field counts, keeps each page's own shares and sums the spend", () => {
  const row = summarize("m", [
    {
      name: "01",
      score: {
        precision: 1,
        recall: 0.5,
        f1: 2 / 3,
        fields: {
          ...NO_FIELDS,
          labels: 2,
          labelsCorrect: 1,
          pageLabels: 4,
          categoriesCorrect: 1,
          fields: 2,
        },
        senses: NO_SENSES,
      },
      notes: null,
      latencyMs: 1000,
      costUsd: 0.01,
      completionTokens: 0,
    },
    {
      name: "02",
      score: {
        precision: 0,
        recall: 0,
        f1: 0,
        fields: { ...NO_FIELDS, unlabelledSenses: 4, unprintedLabels: 1 },
        senses: NO_SENSES,
      },
      notes: null,
      latencyMs: 3000,
      costUsd: 0.03,
      completionTokens: 0,
    },
  ]);
  assert.equal(row.precision, 0.5);
  assert.equal(row.recall, 0.25);
  assert.equal(row.labelPrecision, 0.5);
  assert.equal(row.labelRecall, 0.25);
  assert.equal(row.categoryAccuracy, 1);
  assert.equal(row.unprintedLabelRate, 0.25);
  assert.equal(row.examplesPrecision, null, "no examples were returned");
  assert.equal(row.extrasRecall, null, "the pages print no extras");
  assert.equal(row.inventedRate, 0);
  assert.deepEqual(
    row.vocabularyPages.map((page) => [
      page.name,
      page.f1,
      page.labelPrecision,
      page.unprintedLabelRate,
    ]),
    [["01", 2 / 3, 0.5, null], ["02", 0, null, 0.25]],
  );
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
  labelPrecision: null,
  labelRecall: null,
  categoryAccuracy: null,
  unprintedLabelRate: null,
  examplesPrecision: null,
  senseExamplesRecall: null,
  extrasRecall: null,
  inventedRate: null,
  sensePrecision: null,
  senseRecall: null,
  vocabularyPages: [],
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

Deno.test("a candidate matches on front and meaning, whatever its labels or examples", () => {
  const page = [entry("run", "달리다", [VERB])];
  const r = score([entry("run", "달리다", [NOUN])], page);
  assert.equal(r.recall, 1);
  assert.equal(r.fields.labels, 1);
  assert.equal(r.fields.labelsCorrect, 0, "a wrong label");
  assert.equal(
    score([entry("run", "뛰다", [VERB])], page).recall,
    0,
    "control: another meaning does not match",
  );
});

Deno.test("labels count when their text equals the page's for that sense, and their category when kind and category match too", () => {
  const page = entry("기차", "철도 위를 다니는 긴 차", [
    { kind: "part_of_speech", category: "noun", text: "명사" },
    CLASS,
  ]);
  const fields = fieldsOf(
    entry("기차", "철도 위를 다니는 긴 차", [
      { kind: "part_of_speech", category: "verb", text: " 명사" },
      { kind: "part_of_speech", category: "noun", text: "사물" },
      { kind: "other", category: null, text: "구어" },
    ]),
    page,
  );
  assert.equal(fields.labels, 3);
  assert.equal(fields.pageLabels, 2);
  assert.equal(fields.labelsCorrect, 2, "명사 and 사물 as printed");
  assert.equal(
    fields.categoriesCorrect,
    0,
    "명사 is a noun, not a verb, and 사물 another label, not a noun",
  );
  assert.equal(
    fieldsOf(
      entry("기차", "철도 위를 다니는 긴 차", page.senses[0].labels),
      page,
    )
      .categoriesCorrect,
    2,
    "control: both of the page's kind and category",
  );
});

Deno.test("a label given to a sense the page prints none for is an unprinted label, and none given is not", () => {
  const page = {
    front: "face",
    senses: [sense("직면하다", [VERB]), sense("표면")],
  };
  const given = fieldsOf({
    front: "face",
    senses: [sense("직면하다", [VERB]), sense("표면", [NOUN])],
  }, page);
  assert.equal(given.unlabelledSenses, 1);
  assert.equal(given.unprintedLabels, 1);
  assert.equal(given.invented, 1, "a label list the page does not print");
  const kept = fieldsOf({
    front: "face",
    senses: [sense("직면하다", [VERB]), sense("표면")],
  }, page);
  assert.equal(kept.unlabelledSenses, 1);
  assert.equal(kept.unprintedLabels, 0, "control: the sense left unlabelled");
  assert.equal(kept.labelsCorrect, 1, "control: the printed label is kept");
});

Deno.test("examples count wherever the card puts them, and a sense's examples count under that sense only", () => {
  const page = {
    front: "run",
    senses: [
      sense("달리다", [VERB], ["I run every morning."]),
      sense("운영하다", [VERB], ["She runs a shop."]),
    ],
  };
  const fields = fieldsOf({
    front: "run",
    senses: [
      sense("달리다", [VERB], ["She runs a shop."]),
      sense("운영하다", [VERB], ["I run every  morning."]),
    ],
  }, page);
  assert.equal(fields.examples, 2);
  assert.equal(fields.examplesCorrect, 2, "both are printed for the entry");
  assert.equal(fields.senseExamples, 2);
  assert.equal(fields.senseExamplesReturned, 0, "each under the other sense");
  const placed = fieldsOf({
    front: "run",
    senses: [
      sense("달리다", [VERB], ["I run every morning."]),
      sense("운영하다", [VERB], ["She runs a shop."]),
    ],
  }, page);
  assert.equal(placed.senseExamplesReturned, 2, "control: each under its own");
  const onCard = fieldsOf(
    entry("run", "달리다", [], {
      examples: ["I run every morning.", "run a bath"],
    }),
    entry("run", "달리다", [], { examples: ["I run every morning."] }),
  );
  assert.equal(onCard.examples, 2);
  assert.equal(onCard.examplesCorrect, 1);
});

Deno.test("an extra counts when its label and text both equal one the page prints", () => {
  const page = entry("Tisch", "책상", [NOUN], {
    extras: [{ label: "성", text: "der" }, {
      label: "복수",
      text: "die Tische",
    }],
  });
  const fields = fieldsOf(
    entry("Tisch", "책상", [NOUN], {
      extras: [
        { label: "성", text: " der" },
        { label: "복수", text: "Tische" },
        { label: "Genus", text: "der" },
      ],
    }),
    page,
  );
  assert.equal(fields.extras, 2);
  assert.equal(fields.extrasReturned, 1, "the plural without its article");
  assert.equal(fields.invented, 0, "the page prints extras");
  assert.equal(
    fieldsOf(entry("Tisch", "책상", [NOUN], { extras: page.extras }), page)
      .extrasReturned,
    2,
    "control: both as printed",
  );
});

Deno.test("a field the page does not print counts as invented, and an absent one does not", () => {
  const page = [entry("apple", "사과")];
  const invented = score([{
    front: "apple",
    senses: [sense("사과", [NOUN], ["an apple a day"])],
    examples: ["She ate an apple."],
    extras: [{ label: "복수", text: "apples" }],
  }], page);
  assert.equal(invented.fields.fields, 4);
  assert.equal(invented.fields.invented, 4);
  const absent = score([entry("apple", "사과")], page);
  assert.deepEqual(
    absent.fields,
    { ...NO_FIELDS, unlabelledSenses: 1 },
    "control: nothing returned",
  );
  const printed = score([entry("apple", "사과", [NOUN])], [
    entry("apple", "사과", [NOUN]),
  ]);
  assert.equal(printed.fields.invented, 0, "control: a printed field");
});

Deno.test("an unmatched candidate's fields are not counted", () => {
  const r = score([entry("pear", "배", [NOUN])], [entry("apple", "사과")]);
  assert.deepEqual(r.fields, NO_FIELDS);
});

// Notes pages: a page teaching four rules at steps 1, 2, 3 and 5, the first with a worked example.
const notesTruth = {
  facts: [
    {
      id: "deduction",
      step: 1 as const,
      terms: ["연역", "반드시"],
      examples: ["253+4637+647898=652788 -> 연역"],
    },
    {
      id: "induction",
      step: 2 as const,
      terms: ["귀납", "개연"],
      examples: [],
    },
    { id: "premise", step: 3 as const, terms: ["전제", "근거"], examples: [] },
    {
      id: "indicators",
      step: 5 as const,
      terms: ["결론 지시어", "따라서"],
      examples: [],
    },
  ],
  lines: [
    "5. 연역과 귀납",
    "연역 논증: 전제가 참이면 결론이 반드시 참",
    "결론 지시어: 따라서, 그러므로",
    "'하다'는 '-여'가 붙는다: 하+여 -> 하여(해)",
    "예) 253+4637+647898=652788 -> 연역",
  ],
};
const noteCard = (front: string, answer: string) => ({ front, answer });

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
      { id: "x", step: 1, terms: ["law of demand"], examples: [] },
    ),
    true,
    "case and whitespace are normalized",
  );
});

Deno.test("a card's examples do not cover a rule, whose terms its front and answer must hold", () => {
  const fact = notesTruth.facts[3];
  const card = {
    ...noteCard("연역 논증", "전제가 참이면 결론이 반드시 참"),
    examples: ["결론 지시어 따라서 -> 연역"],
  };
  assert.equal(covers(card, fact), false);
  assert.equal(
    covers(noteCard("결론 지시어", "따라서, 그러므로"), fact),
    true,
    "control: the same terms in the front and answer",
  );
  const notes = scoreNotes([card], notesTruth);
  assert.equal(notes.coverage, 1 / 4, "the deduction rule alone");
  assert.equal(notes.unsupported, 0);
});

Deno.test("coverage is the share of the page's facts some card covers, whatever the fact's step", () => {
  const notes = scoreNotes([
    noteCard("연역 논증", "전제가 참이면 결론이 반드시 참"),
    noteCard("결론 지시어", "따라서, 그러므로"),
  ], notesTruth);
  assert.equal(notes.coverage, 2 / 4, "the step-1 and step-5 rules");
});

Deno.test("an image with no candidates covers nothing and has no counts", () => {
  const notes = scoreNotes([], notesTruth);
  assert.equal(notes.coverage, 0);
  assert.equal(notes.cards, 0);
});

Deno.test("a card covering no fact is unsupported", () => {
  const notes = scoreNotes([
    noteCard("연역 논증", "결론이 반드시 참"),
    noteCard("논리학의 아버지는?", "아리스토텔레스"),
  ], notesTruth);
  assert.equal(notes.cards, 2);
  assert.equal(notes.unsupported, 1, "control: the first card covers a fact");
});

Deno.test("an answer listing more than 5 items is a long answer, its items split at commas, middle dots, slashes, semicolons and line breaks", () => {
  assert.equal(listedItems("이, 그, 저 · 이것 / 그것; 저것\n여기"), 7);
  assert.equal(listedItems("빛 에너지로 포도당을 만드는 과정"), 1);
  const notes = scoreNotes([
    noteCard("이, 그, 저가 결합된 단어", "이것, 그것, 저것, 여기, 거기, 저기"),
    // Control: five items is within the atomic rule.
    noteCard("3인칭", "그, 그녀, 이분, 그분, 저분"),
  ], notesTruth);
  assert.equal(notes.cards, 2);
  assert.equal(notes.longAnswers, 1);
});

Deno.test("an example the page does not print is invented, and one printed with or without its label is not", () => {
  const notes = scoreNotes([{
    ...noteCard("연역 논증", "결론이 반드시 참"),
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
    ...noteCard("'하다'의 어미는?", "'-여'가 붙는다"),
    examples: ["하+여 -> 하여(해)", "하+어 -> 해어"],
  }], notesTruth);
  assert.equal(notes.examples, 2);
  assert.equal(
    notes.inventedExamples,
    1,
    "the rule line holds the first; control: no line holds the second",
  );
});

Deno.test("summarize averages notes coverage over the notes images and pools their counts", () => {
  const vocabulary = {
    name: "01-vocabulary",
    score: {
      precision: 1,
      recall: 1,
      f1: 1,
      fields: NO_FIELDS,
      senses: NO_SENSES,
    },
    notes: null,
    latencyMs: 1000,
    costUsd: 0.01,
    completionTokens: 50,
  };
  const full = scoreNotes([
    noteCard("연역", "결론이 반드시 참"),
    noteCard("귀납", "결론이 개연적으로 참"),
    noteCard("전제", "근거가 되는 문장"),
    {
      ...noteCard("결론 지시어", "따라서, 그러므로"),
      examples: ["652788 -> 연역"],
    },
  ], notesTruth);
  const long = scoreNotes([
    noteCard("연역", "결론이 반드시 참"),
    noteCard("목록", "가, 나, 다, 라, 마, 바"),
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
  // Long answers pool over every notes image's returned cards: one of the six.
  const pooled = summarize("m", [
    { ...vocabulary, name: "02-notes", score: null, notes: full },
    { ...vocabulary, name: "03-notes", score: null, notes: long },
  ]);
  assert.equal(pooled.notes?.longAnswerRate, 1 / 6);
  assert.equal(row.f1, 1, "vocabulary scores average over vocabulary images");
  assert.deepEqual(row.notes, {
    coverage: 0.5,
    unsupportedRate: 0,
    inventedExamplesRate: 0,
    longAnswerRate: 0,
    bareExceptionRate: 0,
    tableBlankCoverage: null,
    clozeBlankCoverage: null,
    pages: [
      { name: "02-notes", coverage: 1, completionTokens: 900 },
      { name: "03-notes", coverage: 0, completionTokens: 0 },
    ],
  });
  assert.ok(Math.abs(row.costPerImageUsd - 0.02) < 1e-12, "over every image");
});

const notesRow = (coverage: number): NotesRow => ({
  coverage,
  unsupportedRate: null,
  inventedExamplesRate: null,
  longAnswerRate: null,
  bareExceptionRate: null,
  tableBlankCoverage: null,
  clozeBlankCoverage: null,
  pages: [],
});

/** A page whose truth also names the cells a table card should blank and the words a cloze card should. */
const blanksTruth = {
  ...notesTruth,
  tableBlanks: [
    { id: "subject", terms: ["-시-"] },
    { id: "object", terms: ["드리다", "여쭈다"] },
  ],
  clozeBlanks: [
    { id: "predicate", terms: ["서술어"] },
    { id: "complement", terms: ["보어"] },
  ],
};

/** A table card of the honorifics table, its method cells blanks as [blanks] says. */
const tableCard = (blanks: { row: number; column: number }[]) => ({
  type: "table" as const,
  front: "높임법의 갈래",
  answer:
    "구분 | 실현 방법 | 대상\n주체 높임 | 선어말 어미 '-시-' | 주어\n객체 높임 | 드리다, 모시다, 여쭈다 | 목적어, 부사어",
  table: {
    columns: ["구분", "실현 방법", "대상"],
    rows: [
      ["주체 높임", "선어말 어미 '-시-'", "주어"],
      ["객체 높임", "드리다, 모시다, 여쭈다", "목적어, 부사어"],
    ],
    blanks,
  },
});

/** A cloze card of [front] and [answers]. */
const clozeCard = (front: string, answers: string[]) => ({
  type: "cloze" as const,
  front,
  answer: answers.join("\n"),
  cloze: { answers },
});

Deno.test("a table blank is covered when one blank cell of a table card holds each of its terms, and not by the same text left unblanked or on a concept card", () => {
  const [subject, object] = blanksTruth.tableBlanks;
  const both = tableCard([{ row: 0, column: 1 }, { row: 1, column: 1 }]);
  assert.equal(blankCovered([both], "table", subject), true);
  assert.equal(blankCovered([both], "table", object), true);
  const targetsOnly = tableCard([{ row: 0, column: 2 }, { row: 1, column: 2 }]);
  assert.equal(
    blankCovered([targetsOnly], "table", subject),
    false,
    "the cell is in the table but not a blank",
  );
  assert.equal(
    blankCovered(
      [noteCard("주체 높임", "선어말 어미 '-시-'")],
      "table",
      subject,
    ),
    false,
    "a concept card stating the cell",
  );
  assert.equal(
    blankCovered([clozeCard("주체 높임: ___", ["-시-"])], "table", subject),
    false,
    "a cloze card asks it, but not as a table",
  );
  const notes = scoreNotes([targetsOnly, both], blanksTruth);
  assert.equal(notes.tableBlanks, 2);
  assert.equal(notes.tableBlanksCovered, 2);
  assert.equal(scoreNotes([targetsOnly], blanksTruth).tableBlanksCovered, 0);
});

Deno.test("a cloze blank is covered when one answer of a cloze card holds each of its terms, and not by the word in its front", () => {
  const [predicate, complement] = blanksTruth.clozeBlanks;
  const card = clozeCard("주성분: 주어, ___, 목적어, 보어", ["서술어"]);
  assert.equal(blankCovered([card], "cloze", predicate), true);
  assert.equal(
    blankCovered([card], "cloze", complement),
    false,
    "보어 is in the front, not a blank",
  );
  const notes = scoreNotes([card], blanksTruth);
  assert.equal(notes.clozeBlanks, 2);
  assert.equal(notes.clozeBlanksCovered, 1);
});

Deno.test("a page whose truth names no blanks counts none", () => {
  const notes = scoreNotes([clozeCard("___", ["서술어"])], notesTruth);
  assert.equal(notes.tableBlanks, 0);
  assert.equal(notes.clozeBlanks, 0);
});

Deno.test("a card whose answer only names an exception is a bare exception, and one stating what the exception does is not", () => {
  const facts = [{
    id: "reu",
    step: 3 as const,
    terms: ["르", "흘러"],
    examples: [],
  }];
  assert.equal(
    isBareException(noteCard("'르' 불규칙", "'르' 불규칙의 예외"), facts),
    true,
  );
  assert.equal(
    isBareException(noteCard("Irregular plural", "An exception"), facts),
    true,
    "the English word, in any case",
  );
  assert.equal(
    isBareException(
      noteCard("'르' 불규칙", "예외: 흐르+어 -> 흘러, 'ㄹ'이 덧난다"),
      facts,
    ),
    false,
    "control: an exception card that covers its fact",
  );
  assert.equal(
    isBareException(noteCard("논리학의 아버지는?", "아리스토텔레스"), facts),
    false,
    "control: a card covering nothing that names no exception",
  );
  const notes = scoreNotes([
    noteCard("'르' 불규칙", "'르' 불규칙의 예외"),
    noteCard("연역 논증", "전제가 참이면 결론이 반드시 참"),
  ], notesTruth);
  assert.equal(notes.bareExceptions, 1);
});

Deno.test("a table card's answer, its whole table, is not a long answer, while the same answer on a concept card is", () => {
  const card = tableCard([{ row: 0, column: 1 }]);
  assert.ok(listedItems(card.answer) > 5);
  assert.equal(scoreNotes([card], notesTruth).longAnswers, 0);
  assert.equal(
    scoreNotes([noteCard(card.front, card.answer)], notesTruth).longAnswers,
    1,
    "control: the same answer on a concept card",
  );
});

Deno.test("summarize pools the bare exceptions over the cards, and the table and cloze blanks over the pages holding any", () => {
  const image = (name: string, notes: ReturnType<typeof scoreNotes>) => ({
    name,
    score: null,
    notes,
    latencyMs: 0,
    costUsd: 0,
    completionTokens: 0,
  });
  const row = summarize("m", [
    image(
      "01-notes",
      scoreNotes([
        tableCard([{ row: 0, column: 1 }]),
        clozeCard("주성분: 주어, ___, 목적어, ___", ["서술어", "보어"]),
        noteCard("'르' 불규칙", "'르' 불규칙의 예외"),
      ], blanksTruth),
    ),
    image(
      "02-notes",
      scoreNotes([noteCard("연역 논증", "결론이 반드시 참")], notesTruth),
    ),
  ]);
  assert.equal(row.notes?.bareExceptionRate, 1 / 4);
  assert.equal(row.notes?.tableBlankCoverage, 1 / 2);
  assert.equal(row.notes?.clozeBlankCoverage, 1);
});

Deno.test("with notes results, the recommendation must also be within 5 points of the best notes coverage", () => {
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

Deno.test("a note card is matched on a vocabulary page by its answer, and a vocabulary card by its senses' meanings", () => {
  const truth = [entry("apple", "사과")];
  const asNote = entryOf({
    kind: "note",
    type: "concept",
    front: "apple",
    answer: "사과",
    short: "사과",
    step: 1,
    topic: "과일",
    back: "사과",
  });
  assert.deepEqual(asNote, entry("apple", "사과"));
  assert.equal(score([asNote], truth).f1, 1);
  const senses = [
    sense("직면하다, 마주하다", [VERB]),
    sense("표면, 겉면", [NOUN]),
  ];
  const extras = [{ label: "유의어", text: "confront" }];
  const vocabulary = entryOf({
    kind: "vocabulary",
    type: "concept",
    front: "face",
    answer: "[동] 직면하다, 마주하다\n[명] 표면, 겉면",
    short: "[동] 직면하다, 마주하다\n[명] 표면, 겉면",
    step: 1,
    topic: "단어",
    back: "[동] 직면하다, 마주하다\n[명] 표면, 겉면",
    meaning: "[동] 직면하다, 마주하다\n[명] 표면, 겉면",
    senses,
    extras,
  });
  assert.deepEqual(vocabulary, { front: "face", senses, extras });
  assert.equal(
    score([vocabulary], [{ front: "face", senses }]).f1,
    1,
    "the senses' meanings, not the composed answer with its labels",
  );
});

Deno.test("senses are scored per entry matched by front, a sense counting when its labels and meaning both equal the page's", () => {
  const truth = [{
    front: "face",
    senses: [
      sense("직면하다", [VERB]),
      sense("표면", [NOUN]),
      sense("얼굴", [NOUN]),
    ],
  }];
  const result = score([{
    front: " Face",
    senses: [sense("직면하다", [VERB]), sense("표면")],
  }], truth);
  assert.deepEqual(result.senses, { returned: 2, page: 3, matched: 1 });
  assert.equal(
    result.f1,
    0,
    "the card itself does not match, its meanings short of the page's",
  );
  assert.deepEqual(
    score([entry("walk", "걷다")], truth).senses,
    NO_SENSES,
    "control: a front the page does not print counts no sense",
  );
});
