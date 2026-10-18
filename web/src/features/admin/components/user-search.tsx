import { Search } from "lucide-react";
import Link from "next/link";

import { formatDate } from "../format";
import type { UserMatch } from "../read-admin";

/** The search by email, a form that opens the users page with the query, and its results. */
export function UserSearch({
  query,
  matches,
  timeZone,
}: {
  query: string;
  matches: UserMatch[] | null;
  timeZone: string;
}) {
  return (
    <div className="flex flex-col gap-3">
      <form role="search" action="/admin/users" className="relative">
        <Search
          aria-hidden
          className="pointer-events-none absolute top-1/2 left-4 size-5 -translate-y-1/2 text-muted"
          strokeWidth={2}
        />
        <input
          type="search"
          name="q"
          aria-label="이메일 검색"
          placeholder="이메일 검색"
          defaultValue={query}
          className="h-search w-full rounded-field border border-outline bg-surface pr-4 pl-12 text-body placeholder:text-muted focus-visible:outline-2 focus-visible:-outline-offset-1 focus-visible:outline-ink"
        />
      </form>
      {matches !== null &&
        (matches.length === 0 ? (
          <p role="status" className="text-muted">
            찾는 사용자가 없어요. 다른 단어로 검색해 보세요.
          </p>
        ) : (
          <ul className="flex flex-col gap-2">
            {matches.map((user) => (
              <li key={user.id}>
                <Link
                  href={`/admin/users/${user.id}`}
                  className="flex min-h-13 items-center justify-between gap-3 rounded-row bg-surface px-4 py-3 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink"
                >
                  <span className="truncate text-body-strong">{user.email}</span>
                  <span className="text-caption text-muted">
                    {formatDate(user.createdAt, timeZone)} 가입
                  </span>
                </Link>
              </li>
            ))}
          </ul>
        ))}
    </div>
  );
}
