import assert from "node:assert/strict";
import {
  blankCovered,
  covers,
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
      senses: { returned: 2, page: 2, matched: 2 },
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
    senses: NO_SENSES,
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
        fields: NO_FIELDS,
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
  sensePrecision: null,
  senseRecall: null,
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
  const truth = [{ front: "apple", meaning: "사과" }];
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
  assert.deepEqual(asNote, { front: "apple", meaning: "사과" });
  assert.equal(score([asNote], truth).f1, 1);
  const senses = [
    { pos: "[동]", meaning: "직면하다, 마주하다" },
    { pos: "[명]", meaning: "표면, 겉면" },
  ];
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
  });
  assert.deepEqual(vocabulary, {
    front: "face",
    meaning: "직면하다, 마주하다; 표면, 겉면",
    senses,
  }, "the senses' meanings, not the composed answer with its labels");
});

Deno.test("senses are scored per entry matched by front, a sense counting when its part of speech and meaning both equal the page's", () => {
  const truth = [{
    front: "face",
    meaning: "직면하다; 표면; 얼굴",
    senses: [
      { pos: "[동]", meaning: "직면하다" },
      { pos: "[명]", meaning: "표면" },
      { pos: "[명]", meaning: "얼굴" },
    ],
  }];
  const result = score([{
    front: " Face",
    meaning: "직면하다; 표면",
    senses: [
      { pos: "[동]", meaning: "직면하다" },
      { pos: "[형]", meaning: "표면" },
    ],
  }], truth);
  assert.deepEqual(result.senses, { returned: 2, page: 3, matched: 1 });
  assert.equal(
    result.f1,
    0,
    "the card itself does not match, its meanings short of the page's",
  );
  // A truth written before senses is one sense of its meaning and part of speech.
  assert.deepEqual(
    score(
      [{
        front: "run",
        meaning: "달리다",
        senses: [{ pos: "v.", meaning: "달리다" }],
      }],
      [{ front: "run", meaning: "달리다", partOfSpeech: "v." }],
    ).senses,
    { returned: 1, page: 1, matched: 1 },
  );
  assert.deepEqual(
    score([{ front: "walk", meaning: "걷다" }], truth).senses,
    NO_SENSES,
    "control: a front the page does not print counts no sense",
  );
});

Deno.test("part of speech is scored per sense, against the page's label for that sense", () => {
  const senses = [
    { pos: "[동]", meaning: "직면하다" },
    { pos: "[명]", meaning: "표면" },
  ];
  const fields = score(
    [{ front: "face", meaning: "직면하다; 표면", senses }],
    [{
      front: "face",
      meaning: "직면하다; 표면",
      senses: [{ pos: "[동]", meaning: "직면하다" }, {
        pos: null,
        meaning: "표면",
      }],
    }],
  ).fields;
  assert.equal(fields.partOfSpeech, 2);
  assert.equal(fields.partOfSpeechCorrect, 1);
  assert.equal(
    fields.invented,
    1,
    "the page prints no label for the second sense",
  );
});
