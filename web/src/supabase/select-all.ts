import type { PostgrestError } from "@supabase/supabase-js";

import { classifyFailure, type ServerFailure } from "./failure";

/**
 * The rows PostgREST answers per request at most: `max_rows` in supabase/config.toml, and
 * the hosted project's default. A page shorter than this is the last one.
 */
export const pageSize = 1000;

type Page = PromiseLike<{
  data: unknown[] | null;
  error: PostgrestError | null;
  status: number;
  count: number | null;
}>;

/**
 * Every row a query selects, read [pageSize] rows at a time. [page] runs the query over the
 * rows from index `from` to `to`, both included, in an order that does not change between
 * pages, and with `counted` also counts every row the query selects. The first page is
 * counted and the pages after it are read together, so a read waits on two requests at most,
 * however many pages it holds.
 */
export async function selectAll(
  page: (from: number, to: number, counted: boolean) => Page,
): Promise<{ rows: unknown[] } | { failure: ServerFailure }> {
  const first = await page(0, pageSize - 1, true);
  if (first.error) return { failure: classifyFailure(first.error, first.status) };
  if (!first.data) return { failure: "failed" };
  if (first.data.length < pageSize) return { rows: first.data };
  if (first.count === null) return { failure: "failed" };

  const starts: number[] = [];
  for (let from = pageSize; from < first.count; from += pageSize) starts.push(from);
  const rest = await Promise.all(starts.map((from) => page(from, from + pageSize - 1, false)));
  const rows = [...first.data];
  for (const { data, error, status } of rest) {
    if (error) return { failure: classifyFailure(error, status) };
    if (!data) return { failure: "failed" };
    rows.push(...data);
  }
  return { rows };
}
