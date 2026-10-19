/** Each blank of a whole card under [element], by its answer: true where it is filled. */
export function blanksUnder(element: HTMLElement): Record<string, boolean> {
  return Object.fromEntries(
    [...element.querySelectorAll("[data-blank]")].map((blank) => [
      blank.textContent,
      blank.getAttribute("data-blank") === "filled",
    ]),
  );
}
