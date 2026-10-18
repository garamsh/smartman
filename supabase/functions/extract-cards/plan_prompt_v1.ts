/**
 * Version 1 of the plan prompt: the user's choices, added to the extraction prompt's user turn
 * when the cards are made to a plan.
 */

import type { Plan, Shape } from "./request.ts";

export const PLAN_PROMPT_VERSION = "plan-v1";

const FRONT: Record<Shape["front"], string> = {
  question: "a short question about the item",
  term: "the item's term, formula or example alone, as the page writes it",
  answer: "the item's answer, so the learner recalls the term or question",
};

const BACK: Record<Shape["back"], string> = {
  short: "the short form of the answer",
  answer:
    "the full answer the page gives, with its reason where the page states one",
};

/** The plan as instructions: only the chosen groups and typed topics, each in its shape. */
export function planPrompt(plan: Plan): string {
  const lines = [
    "Make cards only for the groups below, and every item of each that the page holds. Make no card for any other part of the page.",
    ...plan.groups.map((group) =>
      `- "${group.title}" (${group.id}): "front" is ${
        FRONT[group.shape.front]
      }; "answer" is ${BACK[group.shape.back]}.`
    ),
    ...plan.added.map((topic) =>
      `- "${topic}", a topic the learner asked for: if the page teaches it, "front" is ${FRONT.question}; "answer" is ${BACK.short}. If the page does not teach it, make no card for it.`
    ),
    'Write "short" as a shorter form of "answer", no longer than it. Every fact still comes from the page.',
  ];
  return lines.join("\n");
}
