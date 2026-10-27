"use client";

import { Search } from "lucide-react";
import { useId, useState } from "react";

import { describeContent, isWholeCard, spokenContent } from "../card-content";
import type { Card } from "../library";
import { SideText } from "./side-text";
import { EmptyDeck } from "./empty-home";
import { WholeCard } from "./whole-card";

/**
 * A deck's cards as one group of rows under a search that keeps the cards whose front or back
 * holds it, ignoring case (ADR 0118). Each row shows its front, and its back muted after it once
 * shown; nothing stands for a hidden back. "뒷면 보기", in a row pinned above the group under the
 * section label "카드", shows or hides every back, starting off each time the page opens. A click
 * on a row sets that card alone apart until the switch next changes. A whole card shows its front
 * with its blanks empty, filled in place where its back shows.
 */
export function CardGrid({ cards }: { cards: Card[] }) {
  const [search, setSearch] = useState("");
  const [all, setAll] = useState(false);
  const [apart, setApart] = useState<ReadonlySet<string>>(new Set());
  const label = useId();
  const rows = cards.map((card) => ({
    id: card.id,
    blocks: card.front,
    backBlocks: card.back,
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
    return <EmptyDeck />;
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
          aria-label="카드 검색"
          placeholder="카드 검색"
          value={search}
          onChange={(event) => {
            setSearch(event.target.value);
          }}
          className="h-search w-full rounded-field border border-outline bg-surface pr-4 pl-12 text-body placeholder:text-muted focus-visible:outline-2 focus-visible:-outline-offset-1 focus-visible:outline-ink"
        />
      </div>
      <div className="sticky top-0 z-[1] flex min-h-tap-target items-center justify-between bg-ground">
        <h2 className="px-1 text-section text-muted">카드</h2>
        <span className="flex items-center gap-3">
          <span id={label} className="text-secondary text-ink-2">
            뒷면 보기
          </span>
          <button
            type="button"
            role="switch"
            aria-checked={all}
            aria-labelledby={label}
            onClick={() => {
              setAll(!all);
              setApart(new Set());
            }}
            className={`pressable relative my-2 h-7 w-12 rounded-full transition-colors before:absolute before:-inset-2 before:content-[''] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink ${all ? "bg-ink" : "bg-outline"}`}
          >
            <span
              aria-hidden
              className={`absolute top-0.5 left-0.5 size-6 rounded-full bg-surface shadow-card transition-transform ${all ? "translate-x-5" : ""}`}
            />
          </button>
        </span>
      </div>
      {shown.length === 0 ? (
        <p role="status" className="text-muted">
          찾는 카드가 없어요. 다른 단어로 검색해 보세요.
        </p>
      ) : (
        <ul className="flex flex-col divide-y divide-hairline overflow-hidden rounded-group bg-surface">
          {shown.map((row) => {
            const open = all !== apart.has(row.id);
            return (
              <li key={row.id} className="flex">
                <button
                  type="button"
                  aria-expanded={open}
                  aria-label={
                    open
                      ? `${spokenContent(row.blocks, false)}, 뒷면 ${row.back}`
                      : `${spokenContent(row.blocks, false)}, 뒷면 가려짐`
                  }
                  onClick={() => {
                    const next = new Set(apart);
                    if (next.has(row.id)) next.delete(row.id);
                    else next.add(row.id);
                    setApart(next);
                  }}
                  className="pressable flex min-h-cta w-full items-center gap-3 px-4 py-3 text-left focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-ink"
                >
                  {isWholeCard(row.blocks) ? (
                    <WholeCard blocks={row.blocks} revealed={open} inRow />
                  ) : (
                    <>
                      <span className="min-w-0 flex-1 text-body-strong break-words">
                        <SideText blocks={row.blocks} />
                      </span>
                      {open && (
                        <span className="min-w-0 flex-1 text-right text-secondary break-words text-muted">
                          <SideText blocks={row.backBlocks} />
                        </span>
                      )}
                    </>
                  )}
                </button>
              </li>
            );
          })}
        </ul>
      )}
    </section>
  );
}
