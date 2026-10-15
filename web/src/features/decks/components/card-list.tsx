"use client";

import { Search } from "lucide-react";
import { useState } from "react";

import { describeContent } from "@/lib/card-content";
import type { Card } from "../library";

/**
 * A deck's cards, each a row of front and back, with a search that keeps the cards whose
 * front or back holds it, ignoring case.
 */
export function CardList({ cards }: { cards: Card[] }) {
  const [search, setSearch] = useState("");
  const rows = cards.map((card) => ({
    id: card.id,
    front: describeContent(card.front),
    back: describeContent(card.back),
  }));
  const needle = search.trim().toLocaleLowerCase();
  const shown = needle
    ? rows.filter(
        (row) =>
          row.front.toLocaleLowerCase().includes(needle) ||
          row.back.toLocaleLowerCase().includes(needle),
      )
    : rows;

  if (cards.length === 0) {
    return <p className="text-muted">아직 카드가 없어요. 휴대폰 앱에서 카드를 추가해 주세요.</p>;
  }
  return (
    <section aria-label="카드" className="flex flex-col gap-3">
      <div className="relative">
        <Search
          aria-hidden
          className="pointer-events-none absolute top-1/2 left-4 size-5 -translate-y-1/2 text-muted"
          strokeWidth={2}
        />
        <input
          type="search"
          aria-label="검색"
          placeholder="검색"
          value={search}
          onChange={(event) => {
            setSearch(event.target.value);
          }}
          className="h-12 w-full rounded-field border border-outline bg-surface pr-4 pl-12 text-body placeholder:text-muted focus-visible:outline-2 focus-visible:-outline-offset-1 focus-visible:outline-ink"
        />
      </div>
      {shown.length === 0 ? (
        <p role="status" className="text-muted">
          찾는 카드가 없어요. 다른 말로 검색해 보세요.
        </p>
      ) : (
        <ul className="divide-y divide-hairline overflow-hidden rounded-row bg-surface">
          {shown.map((row) => (
            <li key={row.id} className="grid grid-cols-2 divide-x divide-hairline">
              <span className="p-4 text-label break-words">{row.front}</span>
              <span className="p-4 text-secondary break-words text-ink-2">{row.back}</span>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
