"use client";

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
    return <p className="text-muted">아직 카드가 없습니다. 휴대폰 앱에서 카드를 추가하세요.</p>;
  }
  return (
    <section aria-label="카드" className="flex flex-col gap-3">
      <input
        type="search"
        aria-label="검색"
        placeholder="검색"
        value={search}
        onChange={(event) => {
          setSearch(event.target.value);
        }}
        className="min-h-13 rounded-row border border-hairline bg-surface px-4 placeholder:text-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink"
      />
      {shown.length === 0 ? (
        <p role="status" className="text-muted">
          찾는 카드가 없습니다. 다른 말로 검색해 보세요.
        </p>
      ) : (
        <ul className="flex flex-col gap-2">
          {shown.map((row) => (
            <li
              key={row.id}
              className="grid grid-cols-2 divide-x divide-hairline rounded-row bg-surface py-3"
            >
              <span className="px-4 break-words">{row.front}</span>
              <span className="px-4 break-words text-muted">{row.back}</span>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
