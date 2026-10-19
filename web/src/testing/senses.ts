/**
 * Each sense line drawn under [element]: its labels' text, whether each label carries the gap
 * after it (Tailwind's `mr-1`, one spacing step), and the line's whole text.
 */
export function sensesUnder(
  element: HTMLElement,
): { labels: (string | null)[]; gapped: boolean; text: string | null }[] {
  return [...element.querySelectorAll("[data-sense]")].map((sense) => {
    const labels = [...sense.querySelectorAll("[data-label]")];
    return {
      labels: labels.map((label) => label.textContent),
      gapped: labels.every((label) => label.classList.contains("mr-1")),
      text: sense.textContent,
    };
  });
}
