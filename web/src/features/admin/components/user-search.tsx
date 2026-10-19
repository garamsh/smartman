"use client";

import { Search } from "lucide-react";
import Link from "next/link";
import { useEffect, useRef, useState, useTransition } from "react";

import { findUsers } from "../find-users";
import { formatDate } from "../format";
import type { UserMatch, UserPage } from "../read-admin";

/** How long the search waits after the last keystroke before it asks the server. */
export const searchDelayMs = 250;

/**
 * The users whose email holds what the admin types, updated in place [searchDelayMs] after the
 * last keystroke: the earlier results stay until the next arrive, an answer to an older query is
 * dropped, and "더 보기" adds the next page.
 */
export function UserSearch({
  initialQuery,
  initialPage,
  timeZone,
}: {
  initialQuery: string;
  initialPage: UserPage | null;
  timeZone: string;
}) {
  const [query, setQuery] = useState(initialQuery);
  const [users, setUsers] = useState<UserMatch[]>(initialPage?.users ?? []);
  const [total, setTotal] = useState<number | null>(initialPage?.total ?? null);
  const [page, setPage] = useState(0);
  const [message, setMessage] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();
  const latest = useRef(0);
  const searched = useRef(initialQuery);

  useEffect(() => {
    if (query === searched.current) return;
    const timer = setTimeout(() => {
      searched.current = query;
      const request = ++latest.current;
      startTransition(async () => {
        const answer = await findUsers(query, 0);
        if (request !== latest.current) return;
        if ("message" in answer) {
          setMessage(answer.message);
          return;
        }
        setMessage(null);
        setUsers(answer.users);
        setTotal(query.trim() === "" ? null : answer.total);
        setPage(0);
      });
    }, searchDelayMs);
    return () => {
      clearTimeout(timer);
    };
  }, [query]);

  const more = () => {
    const request = ++latest.current;
    startTransition(async () => {
      const answer = await findUsers(searched.current, page + 1);
      if (request !== latest.current) return;
      if ("message" in answer) {
        setMessage(answer.message);
        return;
      }
      setUsers((shown) => [...shown, ...answer.users]);
      setPage((current) => current + 1);
    });
  };

  return (
    <div className="flex flex-col gap-3">
      <div role="search" className="relative">
        <Search
          aria-hidden
          className="pointer-events-none absolute top-1/2 left-4 size-5 -translate-y-1/2 text-muted"
          strokeWidth={2}
        />
        <input
          type="search"
          aria-label="이메일 검색"
          placeholder="이메일 검색"
          value={query}
          onChange={(event) => {
            setQuery(event.target.value);
          }}
          className="h-search w-full rounded-field border border-outline bg-surface pr-4 pl-12 text-body placeholder:text-muted focus-visible:outline-2 focus-visible:-outline-offset-1 focus-visible:outline-ink"
        />
      </div>
      <p role="status" aria-live="polite" className="min-h-6 text-caption text-muted">
        {message ??
          (total === null
            ? ""
            : total === 0
              ? "찾는 사용자가 없어요. 다른 단어로 검색해 보세요."
              : `${String(total)}명`)}
      </p>
      <ul aria-busy={pending} className="flex flex-col gap-2">
        {users.map((user) => (
          <li key={user.id}>
            <Link
              href={`/admin/users/${user.id}`}
              className="flex min-h-13 items-center justify-between gap-3 rounded-row bg-surface px-4 py-3 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink"
            >
              <span className="truncate text-body-strong">{user.email}</span>
              <span className="text-caption whitespace-nowrap text-muted">
                {user.suspended ? "정지 · " : ""}
                {formatDate(user.createdAt, timeZone)} 가입
              </span>
            </Link>
          </li>
        ))}
      </ul>
      {total !== null && users.length < total && (
        <button
          type="button"
          disabled={pending}
          onClick={more}
          className="flex min-h-button items-center justify-center self-start rounded-button border border-outline px-4 text-label font-semibold text-ink focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink disabled:opacity-50"
        >
          더 보기
        </button>
      )}
    </div>
  );
}
