import { expect } from "@playwright/test";

/**
 * Acts on a page until it reacts: [act] runs only while [reacted] is false, and the step ends once
 * it is true. A key or a click that reaches a page before it hydrates finds no handler and does
 * nothing, and the markup the server rendered is there before then, so waiting for it is not
 * waiting for the page to react (#152); the reaction itself is. After acting, the reaction is given
 * two seconds before [act] runs again, so an action the page took is not repeated.
 */
export async function untilReacted(
  act: () => Promise<unknown>,
  reacted: () => Promise<boolean>,
): Promise<void> {
  await expect(async () => {
    if (!(await reacted())) await act();
    await expect.poll(reacted, { timeout: 2_000 }).toBe(true);
  }).toPass();
}
