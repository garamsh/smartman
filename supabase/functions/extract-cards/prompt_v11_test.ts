// Prompt v11 (#515) is prompt v10 made as faithful as prompt v9, in general terms.
import assert from "node:assert/strict";
import { PROMPT_VERSION, SYSTEM_PROMPT } from "./prompt_v11.ts";
import * as v10 from "./prompt_v10.ts";

/** The store's limit on a version's text (`20261019210000_prompts.sql`). */
const STORE_MAX_CHARS = 20000;

Deno.test("prompt v11 keeps prompt v10's principles, scope and list rule", () => {
  assert.equal(PROMPT_VERSION, "v11");
  const principles = v10.SYSTEM_PROMPT.slice(
    v10.SYSTEM_PROMPT.indexOf("# 역할"),
    v10.SYSTEM_PROMPT.indexOf("# 작업 절차"),
  );
  assert.ok(principles.includes("12. 목록의 번호"), "the slice holds them");
  assert.ok(SYSTEM_PROMPT.includes(principles));
  assert.ok(
    SYSTEM_PROMPT.includes(
      "- 카드 앞면에 목록의 번호나 글머리 기호가 들어가지 않았는가?",
    ),
  );
});

Deno.test("prompt v11 transcribes the material as written and adds nothing it does not give", () => {
  for (
    const phrase of [
      "- 용어, 정의, 번역, 예시, 수식 및 표의 값은 원문에 쓰인 그대로 옮긴다. 번역하거나 고치거나 완성하지 않는다.",
      "- 의미, 표지, 발음, 관련어, 예시 가운데 원문이 그 항목에 보여 주지 않는 것은 알고 있거나 분명해 보여도 추가하지 않는다. 그 필드는 비워 둔다.",
      "- 원문이 보여 주지 않는 의미, 표지, 발음, 관련어 또는 예시를 넣지 않았는가?",
    ]
  ) {
    assert.ok(SYSTEM_PROMPT.includes(phrase), phrase);
  }
  // Prompt v10 said only that the values are based on the material, which a paraphrase keeps.
  assert.ok(!SYSTEM_PROMPT.includes("원문을 기준으로 한다."));
  // Control: prompt v10 says it.
  assert.ok(v10.SYSTEM_PROMPT.includes("원문을 기준으로 한다."));
});

Deno.test("prompt v11 gives a meaning only the labels printed with it, and none where none is printed", () => {
  assert.ok(
    SYSTEM_PROMPT.includes(
      "- 품사, 분류, 분야 같은 표지는 원문이 그 의미와 함께 표시한 것만 쓰인 그대로 옮긴다. 원문이 표지를 표시하지 않은 의미의 표지는 품사가 분명해 보여도 비워 둔다. 그 의미가 아닌 다른 자리, 예컨대 발음이나 제목 옆에 표시된 표지는 어느 의미의 표지도 아니다.",
    ),
  );
});

Deno.test("prompt v11 copies an example only when the material gives it for the card, whole", () => {
  assert.ok(
    SYSTEM_PROMPT.includes(
      "- 예시는 원문이 그 카드의 항목이나 규칙에 실제로 제시한 것만, 줄이거나 늘리거나 고치지 않고 통째로 옮긴다. 규칙을 보여 주려고 예시를 지어내지 않는다.",
    ),
  );
});

Deno.test("prompt v11 keeps a table whole and a listed line as one cloze, their values as blanks", () => {
  for (
    const phrase of [
      "표 전체를 하나의 표 카드에 담고, 머리글은 그대로 두며, 머리글이 아니면서 학습할 값이 있는 칸은 모두 빈칸으로 한다. 표를 칸이나 행마다 여러 카드로 나누거나 일부 칸만 묻지 않는다.",
      "- 하나의 이름 아래 그 이름에 속하는 여러 항목을 나열한 줄은 그 줄 전체를 앞면으로 하고 나열된 항목마다 빈칸을 둔 빈칸 카드로 만든다. 이름을 앞면에, 나열을 답에 두는 카드로 만들지 않는다.",
      "- 단어와 그 의미를 짝지은 목록이나 표는 어휘 자료다. 위의 두 경우에 해당하지 않으며 단어마다 어휘 카드를 만든다.",
      "- 표와 항목을 나열한 줄을 나누지 않고, 학습할 값을 빈칸으로 남겼는가?",
    ]
  ) {
    assert.ok(SYSTEM_PROMPT.includes(phrase), phrase);
  }
  // Prompt v10 offered recalling part of a table, which splits a table or blanks some cells.
  assert.ok(!SYSTEM_PROMPT.includes("표의 일부 회상"));
  // Control: prompt v10 offers it.
  assert.ok(v10.SYSTEM_PROMPT.includes("표의 일부 회상"));
});

Deno.test("prompt v11 holds no rule for one subject or layout", () => {
  const specific = /손글씨|필기|강의 노트|다이어그램|코드|단어장|문법/;
  assert.doesNotMatch(SYSTEM_PROMPT, specific);
  // Control: the expression matches version 3's line for handwriting, which prompt v10 dropped.
  assert.match(
    "손글씨로 추가된 중요 내용은 별도의 학습 항목으로 고려한다.",
    specific,
  );
});

Deno.test("prompt v11 fits the prompt store, so an admin can save it as a version", () => {
  assert.ok(
    [...SYSTEM_PROMPT].length <= STORE_MAX_CHARS,
    `${[...SYSTEM_PROMPT].length} characters`,
  );
});
