"use client";

import { useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { v7 } from "uuid";
import { createDeck, saveCards } from "../actions";
import { type CardDraft, block } from "../authoring";
import type { Deck } from "../library";
import { AuthoringSheet } from "./authoring-sheet";
import { CardFields } from "./card-fields";
import { PhotoImport } from "./photo-import";

/** A creation entry opens the phone's three choices without leaving the current page. */
export function AuthoringButton({ deck, decks = [] }: { deck?: Deck; decks?: Deck[] }) {
  const [screen, setScreen] = useState<"options" | "name" | "manual" | "photo" | null>(null);
  const [camera, setCamera] = useState(false);
  const label = deck ? "카드 추가" : "새 덱 만들기";
  return (
    <>
      <button
        type="button"
        onClick={() => {
          setScreen("options");
        }}
        className="pressable min-h-cta w-full rounded-button border border-outline bg-surface px-5 text-label focus-visible:outline-2 focus-visible:outline-ink"
      >
        {label}
      </button>
      {screen === "options" && (
        <AuthoringSheet
          title={deck ? "카드 추가" : "새 덱"}
          close={() => {
            setScreen(null);
          }}
        >
          <div className="divide-y divide-hairline overflow-hidden rounded-group bg-surface">
            {["직접 입력", "사진 찍기", "앨범에서 고르기"].map((choice, index) => (
              <button
                type="button"
                key={choice}
                aria-label={choice}
                className="pressable flex min-h-button w-full flex-col items-start px-4 py-4 text-left text-body"
                onClick={() => {
                  if (index === 0) setScreen(deck ? "manual" : "name");
                  else {
                    setCamera(index === 1);
                    setScreen("photo");
                  }
                }}
              >
                {choice}
                {index !== 0 && (
                  <span className="text-caption text-muted">
                    {index === 1
                      ? "단어장을 찍으면 카드를 찾아 드려요"
                      : "사진에서 카드를 찾아 드려요"}
                  </span>
                )}
              </button>
            ))}
          </div>
        </AuthoringSheet>
      )}
      {screen === "name" && (
        <NewDeck
          close={() => {
            setScreen(null);
          }}
        />
      )}
      {screen === "manual" && deck && (
        <ManualEntry
          deck={deck}
          close={() => {
            setScreen(null);
          }}
        />
      )}
      {screen === "photo" && (
        <PhotoImport
          deck={deck}
          decks={decks}
          camera={camera}
          close={() => {
            setScreen(null);
          }}
        />
      )}
    </>
  );
}

function NewDeck({ close }: { close: () => void }) {
  const [name, setName] = useState("");
  const [message, setMessage] = useState("");
  const [pending, start] = useTransition();
  const id = useRef(v7());
  const busy = useRef(false);
  const router = useRouter();
  return (
    <AuthoringSheet title="새 덱" close={close}>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          if (busy.current) return;
          busy.current = true;
          start(async () => {
            try {
              const result = await createDeck(id.current, name);
              if (result.saved) {
                close();
                router.push(`/decks/${result.deckId}`);
                router.refresh();
              } else setMessage(result.message);
            } catch {
              setMessage("덱을 만들지 못했어요. 다시 시도해 주세요.");
            } finally {
              busy.current = false;
            }
          });
        }}
        className="flex flex-col gap-4"
      >
        <label className="text-section text-muted">
          이름
          <input
            autoFocus
            required
            maxLength={500}
            value={name}
            onChange={(event) => {
              setName(event.target.value);
            }}
            className="mt-2 min-h-field w-full rounded-field border border-outline bg-surface px-4 text-body text-ink focus:outline-2 focus:outline-ink"
          />
        </label>
        {message && (
          <p role="alert" className="text-caption text-dont-know">
            {message}
          </p>
        )}
        <button
          disabled={pending}
          className="pressable min-h-cta rounded-button bg-ink px-5 text-label text-on-primary disabled:opacity-50"
        >
          {pending ? "만드는 중" : "만들기"}
        </button>
      </form>
    </AuthoringSheet>
  );
}
function emptyDraft(): CardDraft {
  return { id: v7(), front: [block("text", { text: "" })], back: [block("text", { text: "" })] };
}
function ManualEntry({ deck, close }: { deck: Deck; close: () => void }) {
  const [draft, setDraft] = useState(emptyDraft);
  const [message, setMessage] = useState("");
  const [duplicate, setDuplicate] = useState(false);
  const [discarding, setDiscarding] = useState(false);
  const [pending, start] = useTransition();
  const busy = useRef(false);
  const router = useRouter();
  function save(next: boolean, allow = false) {
    if (busy.current) return;
    busy.current = true;
    start(async () => {
      try {
        const clean = {
          ...draft,
          front: draft.front.filter((item) => item.type !== "text" || item.payload.text !== ""),
          back: draft.back.filter((item) => item.type !== "text" || item.payload.text !== ""),
        };
        const result = await saveCards(deck.id, [clean], "manual", allow);
        if (result.saved) {
          setMessage("");
          setDuplicate(false);
          router.refresh();
          if (next) setDraft(emptyDraft());
          else close();
        } else {
          setMessage(result.message);
          setDuplicate(!!result.duplicate);
        }
      } catch {
        setMessage("카드를 저장하지 못했어요. 다시 시도해 주세요.");
      } finally {
        busy.current = false;
      }
    });
  }
  return (
    <AuthoringSheet
      title="새 카드"
      close={() => {
        if (busy.current) return;
        const dirty =
          draft.front.length !== 1 ||
          draft.back.length !== 1 ||
          [...draft.front, ...draft.back].some(
            (item) => item.type !== "text" || item.payload.text !== "",
          );
        if (dirty) setDiscarding(true);
        else close();
      }}
    >
      <p className="mb-4 text-caption text-muted">{deck.name}</p>
      <CardFields
        draft={draft}
        change={(value) => {
          setDraft(value);
          setDuplicate(false);
          setMessage("");
        }}
      />
      {message && (
        <p role="alert" className="my-3 text-caption text-dont-know">
          {message}
        </p>
      )}
      {duplicate && (
        <button
          type="button"
          disabled={pending}
          onClick={() => {
            save(false, true);
          }}
          className="pressable min-h-button w-full text-body"
        >
          그래도 추가
        </button>
      )}
      <div className="sticky bottom-0 mt-5 flex gap-3 bg-ground py-3">
        <button
          type="button"
          disabled={pending}
          onClick={() => {
            save(false);
          }}
          className="pressable min-h-cta flex-1 rounded-button border border-outline bg-surface px-3 text-label disabled:opacity-50"
        >
          저장
        </button>
        <button
          type="button"
          disabled={pending}
          onClick={() => {
            save(true);
          }}
          className="pressable min-h-cta flex-1 rounded-button bg-ink px-3 text-label text-on-primary disabled:opacity-50"
        >
          {pending ? "저장 중" : "저장하고 다음 카드"}
        </button>
      </div>
      {discarding && (
        <AuthoringSheet
          title="작성 중인 카드를 버릴까요?"
          close={() => {
            setDiscarding(false);
          }}
        >
          <p className="text-secondary text-muted">저장하지 않은 내용은 사라져요.</p>
          <div className="mt-4 flex flex-col gap-2">
            <button
              type="button"
              onClick={() => {
                setDiscarding(false);
              }}
              className="pressable min-h-button text-body"
            >
              계속 쓰기
            </button>
            <button
              type="button"
              onClick={close}
              className="pressable min-h-button rounded-button bg-dont-know px-4 text-label text-on-primary"
            >
              버리기
            </button>
          </div>
        </AuthoringSheet>
      )}
    </AuthoringSheet>
  );
}
