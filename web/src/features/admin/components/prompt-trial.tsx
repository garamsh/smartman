"use client";

import { useId, useState, useTransition } from "react";

import { encodePhoto } from "../encode-photo";
import { type TrialCard, tryPrompt } from "../try-prompt";
import { button, group } from "./admin-section";

/**
 * Runs extract-cards on one photo as the signed-in admin, who is served [served]: the test version
 * when one is set, else the active one. The photo counts against the admin's own daily limit.
 */
export function PromptTrial({ served }: { served: { id: number; test: boolean } }) {
  const [cards, setCards] = useState<TrialCard[] | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();
  const id = useId();
  return (
    <section aria-label="사진 한 장으로 시험" className="flex flex-col gap-2">
      <h2 className="px-1 text-section text-muted">사진 한 장으로 시험</h2>
      <p className="px-1 text-caption text-muted">
        {served.test ? "테스트" : "사용 중인"} 버전 {served.id}로 카드를 만들어요. 내 오늘 사진
        한도에서 1장을 써요.
      </p>
      <form
        className="flex flex-col gap-2"
        onSubmit={(event) => {
          event.preventDefault();
          const input = event.currentTarget.elements.namedItem("photo");
          const file = input instanceof HTMLInputElement ? input.files?.[0] : undefined;
          if (file === undefined) return;
          setMessage(null);
          setCards(null);
          startTransition(async () => {
            const photo = await encodePhoto(file);
            if (photo === null) {
              setMessage("이 사진을 읽지 못했어요. 다른 사진을 골라 주세요.");
              return;
            }
            const form = new FormData();
            form.set("photo", photo);
            const result = await tryPrompt(form);
            if ("message" in result) setMessage(result.message);
            else setCards(result.cards);
          });
        }}
      >
        <div className={`${group} gap-2 px-4 py-3`}>
          <label htmlFor={id} className="text-body">
            사진
          </label>
          <input
            id={id}
            name="photo"
            type="file"
            accept="image/jpeg,image/png,image/webp"
            className="min-w-0 text-caption text-ink-2 file:mr-3 file:rounded-button file:border file:border-outline file:bg-surface file:px-3 file:py-2 file:text-body file:text-ink"
          />
        </div>
        <button type="submit" disabled={pending} className={button.secondary}>
          {pending ? "만드는 중…" : "시험"}
        </button>
      </form>
      <p role="status" className="text-caption text-muted empty:hidden">
        {message ?? (cards === null ? null : `카드 ${String(cards.length)}장을 만들었어요.`)}
      </p>
      {cards !== null && (
        <ul aria-label="만든 카드" className={group}>
          {cards.map((card, index) => (
            <li key={index} className="grid gap-1 px-4 py-3 md:grid-cols-2 md:gap-4">
              <span className="text-body-strong">{card.front}</span>
              <span className="text-body whitespace-pre-wrap">{card.back}</span>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
