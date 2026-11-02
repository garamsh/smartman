// Prompt v10 (#493) is the owner's prompt store version 3, kept general, tuned for clear material
// (ADR 0128) and to leave the form of its output to the output contract sent after it (ADR 0124).
import assert from "node:assert/strict";
import { PROMPT_VERSION, SYSTEM_PROMPT } from "./prompt_v10.ts";

/** The store's limit on a version's text (`20261019210000_prompts.sql`). */
const STORE_MAX_CHARS = 20000;

Deno.test("prompt v10 keeps version 3's general principles", () => {
  assert.equal(PROMPT_VERSION, "v10");
  for (
    const phrase of [
      "1. 특정 과목, 문서 형식 또는 카드 유형을 가정하지 않는다.",
      "9. 자료에 없는 지식, 번역, 예시, 설명 또는 추론을 사실처럼 추가하지 않는다.",
    ]
  ) {
    assert.ok(SYSTEM_PROMPT.includes(phrase), phrase);
  }
});

Deno.test("prompt v10 assumes clear material and finds what it teaches by analysing it", () => {
  for (
    const phrase of [
      "입력은 인쇄된 단어 목록이나 용어집처럼 내용이 분명하게 정리된 학습 자료다.",
      "먼저 자료를 분석하여 그 자료가 가르치는 학습 항목, 곧 단어, 용어 또는 사실을 찾은 다음",
    ]
  ) {
    assert.ok(SYSTEM_PROMPT.includes(phrase), phrase);
  }
});

Deno.test("prompt v10 drops version 3's lines for handwriting and complex notes", () => {
  const handwriting = /손글씨|필기/;
  const complexInput = /강의 노트|다이어그램|코드/;
  assert.doesNotMatch(SYSTEM_PROMPT, handwriting);
  assert.doesNotMatch(SYSTEM_PROMPT, complexInput);
  // Control: the expressions match version 3's lines.
  assert.match(
    "- 손글씨로 추가된 중요 내용은 별도의 학습 항목으로 고려한다.",
    handwriting,
  );
  assert.match(
    "입력은 인쇄물, 필기, 교재, 어휘 목록, 표, 강의 노트, 수식, 다이어그램, 코드 또는 이들이 혼합된 사진일 수 있다.",
    complexInput,
  );
});

Deno.test("prompt v10 never puts a list's number or bullet on a card's front", () => {
  for (
    const phrase of [
      "12. 목록의 번호, 순서를 나타내는 숫자나 글자, 글머리 기호는 항목의 자리를 표시할 뿐 학습할 내용이 아니다. 카드의 앞면이 되거나 앞면의 일부가 되지 않는다.",
      "- 카드 앞면에 목록의 번호나 글머리 기호가 들어가지 않았는가?",
    ]
  ) {
    assert.ok(SYSTEM_PROMPT.includes(phrase), phrase);
  }
});

Deno.test("prompt v10 puts a vocabulary card's word on the front and its meaning on the back", () => {
  assert.ok(
    SYSTEM_PROMPT.includes(
      "11. 어휘 카드는 학습할 단어나 표현을 앞면에, 그 의미를 뒷면에 둔다.",
    ),
  );
});

Deno.test("prompt v10 leaves the output's form to the output contract and invents no card type", () => {
  for (
    const phrase of [
      "새로운 질문 방식이 필요하면 출력 계약이 정한 카드 유형 가운데 가장 가까운 것으로 표현한다.",
      "- 아래 출력 계약의 필드와 규칙을 모두 지켰는가? 규칙을 어긴 카드는 버려진다.",
      "분석 결과는 아래 출력 계약(Output contract)에 따라 JSON으로만 반환한다.",
    ]
  ) {
    assert.ok(SYSTEM_PROMPT.includes(phrase), phrase);
  }
  // Version 3 asked to design a card type beyond the supported ones, which the schema refuses.
  const extendTypes = /카드 유형을 확장/;
  assert.doesNotMatch(SYSTEM_PROMPT, extendTypes);
  // Control: the expression matches version 3's sentence.
  assert.match(
    "지원되는 카드 유형을 확장할 수 있는 방식으로 설계한다.",
    extendTypes,
  );
});

Deno.test("prompt v10 fits the prompt store, so an admin can save it as a version", () => {
  assert.ok(
    [...SYSTEM_PROMPT].length <= STORE_MAX_CHARS,
    `${[...SYSTEM_PROMPT].length} characters`,
  );
});
