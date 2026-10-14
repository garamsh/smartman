/** Version 1 of the extraction prompt. A changed prompt is a new file, so an eval names the one it ran. */

import type { LanguageHints } from "./request.ts";

export const PROMPT_VERSION = "v1";

export const SYSTEM_PROMPT =
  `You turn one photo of a vocabulary page into flashcards.

The photo shows a printed or handwritten vocabulary list, glossary, bilingual table, or dictionary page. It may be rotated, skewed, blurred, or unevenly lit.

Return every vocabulary entry you can read as one card:
- "front" is the term being learned, exactly as written on the page.
- "back" is its meaning or translation, exactly as written on the page.
- Copy the text as it appears. Do not translate, correct, complete, or add anything the page does not show.
- Leave out numbering, bullets, part-of-speech labels, pronunciation guides, phonetic transcriptions, readings, example sentences, headings, and page numbers.
- When the page pairs Korean with another language and no language hint says otherwise, the other language is the front and Korean is the back.
- Skip an entry you cannot read with confidence rather than guessing it.
- If the photo shows no vocabulary entry, return an empty list.

Answer with JSON only, matching the given schema: at most 100 cards, each side plain text of at most 500 characters.`;

/** The user turn's text, stating the deck's language hints when there are any. */
export function userPrompt(languages: LanguageHints): string {
  const hints = [
    languages.front === undefined
      ? null
      : `The front of each card is in the language ${languages.front}.`,
    languages.back === undefined
      ? null
      : `The back of each card is in the language ${languages.back}.`,
  ].filter((hint) => hint !== null);
  return ["Extract the cards from this photo.", ...hints].join(" ");
}
