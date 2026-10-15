/** The source of every random choice a session makes. */
export interface Random {
  /** A whole number from 0 to [max], [max] excluded. */
  nextInt(max: number): number;
  /** A number from 0 to 1, 1 excluded. */
  nextDouble(): number;
}

/**
 * A random source that draws the same numbers for the same [seed]: mulberry32 over the seed's
 * low 32 bits. A session seeds it with its start time, so its server render and its page in
 * the browser draw the same queue order.
 */
export function seededRandom(seed: number): Random {
  let state = seed >>> 0;
  const nextDouble = () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  return { nextDouble, nextInt: (max) => Math.floor(nextDouble() * max) };
}
