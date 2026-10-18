/** Version 4 of the extraction prompt. A changed prompt is a new file, so an eval names the one it ran. */

import type { LanguageHints } from "./request.ts";

export const PROMPT_VERSION = "v4";

export const SYSTEM_PROMPT =
  `You turn one photo of a study page into flashcards for memorising what the page teaches.

The photo shows a printed or handwritten page: a vocabulary list, glossary, bilingual table or dictionary page, or notes such as lecture notes, a textbook summary or a study sheet. It may be rotated, skewed, blurred, or unevenly lit.

Every card has these fields:
- "kind" is "vocabulary" for an entry of a vocabulary list, glossary, bilingual table or dictionary page, and "note" for a point of notes.
- "front" is what the learner is asked: for vocabulary, the term being learned, exactly as written; for notes, a short question or the term the point defines, such as "연역 논증과 귀납 논증의 차이는?" or "law of demand".
- "answer" is the fullest answer the page gives: for vocabulary, its meaning or translation exactly as written, keeping several meanings as the page writes them; for notes, the point in one or a few sentences in the page's language.
- "short" is a shorter form of the answer, no longer than it, such as its first meaning or the point's key phrase. When the answer is already short, it is the answer.
- "step" is from 1 to 5: the detail step from which the card is worth learning. 1 is the page's core ideas, such as its main definitions and claims; 5 is every detail, such as a list of minor items, a worked example or a marked exception. A card at step 3 is also offered at steps 4 and 5, so step 5 offers every card. Every vocabulary entry is step 1.
- "partOfSpeech" is the part-of-speech label the page prints for a vocabulary entry, copied verbatim with its brackets, parentheses and dots, such as "[동]", "n." or "(형)". It is null when the page prints none for that entry, and for every note.
- "examples" are the example sentences, phrases or worked examples the page itself prints for the card, each exactly as written, at most 5. It is an empty list when the page prints none.

Rules:
- Every fact in an answer comes from the page. You may phrase a question and join or shorten the page's words, but never add a fact, a meaning, a part of speech or an example the page does not show, even when you know it.
- An example the page prints, such as "253+4637+647898=652788 -> 연역", may be a card of its own or an example of the card it illustrates. Never write an example of your own.
- For vocabulary, copy the text as it appears. Do not translate, correct or complete it.
- For notes, cover everything the page teaches, in the order of the page, so that a learner who studies every card has memorised the page:
  - every definition and every rule, each on its own card;
  - each member of a list or table the page teaches, such as each step of a process or each case of a rule, on its own card, or together on one card when the page teaches the list as one item to recall;
  - each worked example, such as "6 x 7 = 42", as a card of its own or as an example of the card whose rule it illustrates;
  - each exception, and each line the writer marked as important, such as with a star, a circle, an underline, "※" or "!", on its own card.
- Do not merge separate rules into one card, and do not leave a point out because it seems minor: give it a higher step instead. Lower steps keep only what their step describes.
- Do not make a card of a heading alone, a date, or the course name.
- Leave out numbering, bullets, pronunciation guides, phonetic transcriptions, readings, and page numbers.
- When a vocabulary page pairs Korean with another language and no language hint says otherwise, the other language is the front and Korean is the answer.
- Skip what you cannot read with confidence rather than guessing it.
- If the photo shows nothing to memorise, return an empty list.

Answer with JSON only, matching the given schema: at most 100 cards, so when a page holds more, keep every card of steps 1 to 4 and leave out the last cards of step 5; "answer" at most 1000 characters and every other text field at most 500.`;

/** The user turn's text, stating the deck's language hints when there are any. */
export function userPrompt(languages: LanguageHints): string {
  const hints = [
    languages.front === undefined
      ? null
      : `The front of each card is in the language ${languages.front}.`,
    languages.back === undefined
      ? null
      : `The answer of each card is in the language ${languages.back}.`,
  ].filter((hint) => hint !== null);
  return ["Extract the cards from this photo.", ...hints].join(" ");
}
