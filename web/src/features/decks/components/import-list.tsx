"use client";

import { Check, ChevronDown, ChevronUp } from "lucide-react";
import { describeContent, parseContent } from "../card-content";
import type { Candidate } from "../photo-candidates";
import { cardsOf, isWhole, type Section, type SectionForm } from "../section-form";
import { SectionMenu } from "./section-menu";
import { SideText } from "./side-text";
import { WholeCard } from "./whole-card";

/** One read photo's part of the list: its thumbnail, its number and its sections. */
export type PhotoGroup = { id: string; url: string; sections: Section[] };

/**
 * The read cards as the phone's `ImportListView` lists them: the deck line, then, with one photo,
 * its sections, or, with several, each photo's group, collapsible from its header. Each section
 * is headed by its topic, its count and its form menu, and its rows show their first card in
 * that form.
 */
export function ImportList({
  groups,
  deckName,
  chooseDeck,
  formOf,
  changeForm,
  collapsed,
  toggleGroup,
  toggleCard,
  toggleSection,
  edit,
}: {
  groups: PhotoGroup[];
  /** The deck the cards go into; null for a new deck. */
  deckName: string | null;
  chooseDeck: () => void;
  formOf: (section: Section) => SectionForm;
  changeForm: (section: Section, form: SectionForm) => void;
  /** The photos whose groups are collapsed, by id. */
  collapsed: ReadonlySet<string>;
  toggleGroup: (photo: string) => void;
  toggleCard: (card: Candidate) => void;
  toggleSection: (section: Section) => void;
  edit: (card: Candidate) => void;
}) {
  function sections(group: PhotoGroup) {
    return group.sections.map((section) => {
      const form = formOf(section);
      const title = section.identify ? `판별 · ${section.topic}` : section.topic || "카드";
      return (
        <section key={section.id} className="flex min-w-0 flex-col pt-5">
          <div className="flex items-end gap-2">
            <h4 className="min-w-0 flex-1 pb-3 pl-1 text-caption break-keep text-muted">
              {title} {section.cards.length}
            </h4>
            <SectionMenu
              title={title}
              form={form}
              pronunciations={section.cards.some((card) => card.pronunciation !== null)}
              extras={section.cards.some((card) => card.extras.length > 0)}
              swappable={section.cards.some((card) => !isWhole(card))}
              anyIncluded={section.cards.some((card) => card.selected)}
              change={(next) => {
                changeForm(section, next);
              }}
              toggleSection={() => {
                toggleSection(section);
              }}
            />
          </div>
          <ul className="mt-2 divide-y divide-hairline overflow-hidden rounded-group bg-surface">
            {section.cards.map((card) => (
              <CandidateRow
                key={card.id}
                card={card}
                form={form}
                toggle={() => {
                  toggleCard(card);
                }}
                edit={() => {
                  edit(card);
                }}
              />
            ))}
          </ul>
        </section>
      );
    });
  }
  return (
    <div className="flex min-w-0 flex-col">
      <DeckLine name={deckName} choose={chooseDeck} />
      {groups.length === 1 && groups[0]
        ? sections(groups[0])
        : groups.map((group, at) => {
            const expanded = !collapsed.has(group.id);
            const rows = group.sections.reduce((count, section) => count + section.cards.length, 0);
            const label = `사진 ${String(at + 1)}, 카드 ${String(rows)}장`;
            return (
              <div key={group.id} className="flex min-w-0 flex-col pt-7">
                <div className="flex items-center gap-2">
                  <span
                    aria-hidden
                    className="block h-14 w-12 shrink-0 rounded-button bg-hairline bg-cover bg-center"
                    style={{ backgroundImage: `url(${group.url})` }}
                  />
                  <h3 aria-label={label} className="min-w-0 flex-1">
                    <button
                      type="button"
                      aria-label={label}
                      aria-expanded={expanded}
                      onClick={() => {
                        toggleGroup(group.id);
                      }}
                      className="pressable flex min-h-tap-target w-full items-center gap-3 rounded-group text-left"
                    >
                      <span className="flex min-w-0 flex-1 flex-col">
                        <span className="text-body-strong text-ink">사진 {at + 1}</span>
                        <span className="text-secondary text-ink-2">카드 {rows}장</span>
                      </span>
                      {expanded ? (
                        <ChevronUp aria-hidden className="size-small-icon shrink-0 text-ink-2" />
                      ) : (
                        <ChevronDown aria-hidden className="size-small-icon shrink-0 text-ink-2" />
                      )}
                    </button>
                  </h3>
                </div>
                {expanded && sections(group)}
              </div>
            );
          })}
    </div>
  );
}

/**
 * "덱 'name'에 추가돼요", or "새 덱에 추가돼요" while no deck is chosen, the name a button that
 * opens the deck chooser, as the phone's `_DeckLine`.
 */
function DeckLine({ name, choose }: { name: string | null; choose: () => void }) {
  const button = (
    <button
      type="button"
      onClick={choose}
      className="pressable inline-flex min-h-tap-target items-center font-semibold text-ink underline underline-offset-4"
    >
      {name ?? "새 덱"}
    </button>
  );
  return (
    <p className="text-label break-keep text-muted">
      {name === null ? <>{button}에 추가돼요</> : <>덱 &apos;{button}&apos;에 추가돼요</>}
    </p>
  );
}

/**
 * A candidate's row: its round check, and its first card in its section's form, or a whole card's
 * front, to edit.
 */
function CandidateRow({
  card,
  form,
  toggle,
  edit,
}: {
  card: Candidate;
  form: SectionForm;
  toggle: () => void;
  edit: () => void;
}) {
  const [shown] = cardsOf(card, form);
  const front = parseContent(shown?.front ?? card.front) ?? [];
  const back = parseContent(shown?.back ?? card.back) ?? [];
  return (
    <li className="flex min-w-0 items-start gap-2 p-3">
      <button
        type="button"
        role="checkbox"
        aria-checked={card.selected}
        aria-label={`${describeContent(front)} 선택`}
        onClick={toggle}
        className="pressable flex size-tap-target shrink-0 items-center justify-center rounded-full text-body"
      >
        <span
          aria-hidden
          className={`flex size-6 items-center justify-center rounded-full border ${card.selected ? "border-ink bg-ink text-on-primary" : "border-outline"}`}
        >
          {card.selected && <Check className="size-4" />}
        </span>
      </button>
      {isWhole(card) ? (
        <div className="min-w-0 flex-1 overflow-x-auto py-2">
          <WholeCard blocks={front} revealed />
        </div>
      ) : (
        <button
          type="button"
          aria-label={`${describeContent(front)} 편집`}
          onClick={edit}
          className="pressable min-h-tap-target min-w-0 flex-1 py-2 text-left text-body break-words"
        >
          <span className="block font-bold whitespace-pre-line">
            <SideText blocks={front} />
          </span>
          <span className="mt-1 block text-caption whitespace-pre-line text-muted">
            <SideText blocks={back} />
          </span>
        </button>
      )}
    </li>
  );
}
