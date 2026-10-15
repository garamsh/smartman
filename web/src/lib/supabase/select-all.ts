import type { PostgrestError } from "@supabase/supabase-js";

import { classifyFailure, type ServerFailure } from "./failure";

/**
 * The rows PostgREST answers per request at most: `max_rows` in supabase/config.toml, and
 * the hosted project's default. A page shorter than this is the last one.
 */
export const pageSize = 1000;

type Page = PromiseLike<{ data: unknown[] | null; error: PostgrestError | null; status: number }>;

/**
 * Every row a query selects, read [pageSize] rows at a time. [page] runs the query over the
 * rows from index `from` to `to`, both included, in an order that does not change between
 * pages.
 */
export async function selectAll(
  page: (from: number, to: number) => Page,
): Promise<{ rows: unknown[] } | { failure: ServerFailure }> {
  const rows: unknown[] = [];
  for (;;) {
    const { data, error, status } = await page(rows.length, rows.length + pageSize - 1);
    if (error) return { failure: classifyFailure(error, status) };
    if (!data) return { failure: "failed" };
    rows.push(...data);
    if (data.length < pageSize) return { rows };
  }
}
