// Prompt v10 (#493) is the owner's prompt store version 3, kept general, tuned to leave the form
// of its output to the output contract sent after it (ADR 0124).
import assert from "node:assert/strict";
import { PROMPT_VERSION, SYSTEM_PROMPT } from "./prompt_v10.ts";

/** The store's limit on a version's text (`20261019210000_prompts.sql`). */
const STORE_MAX_CHARS = 20000;

Deno.test("prompt v10 keeps version 3's general principles, an important handwritten addition a learning item among them", () => {
  assert.equal(PROMPT_VERSION, "v10");
  for (
    const phrase of [
      "1. 특정 과목, 문서 형식 또는 카드 유형을 가정하지 않는다.",
      "9. 자료에 없는 지식, 번역, 예시, 설명 또는 추론을 사실처럼 추가하지 않는다.",
      "- 손글씨로 추가된 중요 내용은 별도의 학습 항목으로 고려한다.",
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
