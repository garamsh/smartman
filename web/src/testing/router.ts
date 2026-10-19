import { vi } from "vitest";

/**
 * The App Router a test's `useRouter` returns, since a test renders outside the router whose
 * context it reads; each press of a control that refreshes the page is recorded.
 */
export const testRouter = {
  back: vi.fn(),
  forward: vi.fn(),
  prefetch: vi.fn(),
  push: vi.fn(),
  refresh: vi.fn(),
  replace: vi.fn(),
};
