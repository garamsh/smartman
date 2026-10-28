"use client";

import { useEffect, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { v7 } from "uuid";
import { createDeck, readAllowance, saveCards } from "../actions";
import type { Allowance } from "../read-allowance";
import { extractPhoto } from "../extract-photo";
import { type Candidate } from "../photo-candidates";
import { describeContent, parseContent } from "../card-content";
import type { Deck } from "../library";
import { AuthoringSheet } from "./authoring-sheet";
import { CardFields } from "./card-fields";
import { WholeCard } from "./whole-card";
import { SideText } from "./side-text";

type Photo = {
  id: string;
  file: File;
  state: "ready" | "reading" | "read" | "failed";
  message?: string;
  cards: Candidate[];
};

/** A browser-bound photo job: allowance first, per-photo progress, then an explicit reviewed save. */
export function PhotoImport({
  deck,
  decks,
  camera,
  close,
}: {
  deck?: Deck;
  decks: Deck[];
  camera: boolean;
  close: () => void;
}) {
  const [photos, setPhotos] = useState<Photo[]>([]);
  const [allowance, setAllowance] = useState<Allowance | null | "loading">("loading");
  const [reading, setReading] = useState(false);
  const [message, setMessage] = useState("");
  const [target, setTarget] = useState(deck?.id ?? "new");
  const [name, setName] = useState("");
  const [editing, setEditing] = useState<Candidate | null>(null);
  const [discarding, setDiscarding] = useState(false);
  const [pending, start] = useTransition();
  const busy = useRef(false);
  const controller = useRef<AbortController | null>(null);
  const newDeckId = useRef(v7());
  const [created, setCreated] = useState(false);
  const router = useRouter();
  useEffect(() => {
    let active = true;
    void readAllowance()
      .then((value) => {
        if (active) setAllowance(value);
      })
      .catch(() => {
        if (active) setAllowance(null);
      });
    return () => {
      active = false;
      controller.current?.abort();
    };
  }, []);
  const candidates = photos.flatMap((photo) => photo.cards);
  const selected = candidates.filter((card) => card.selected);
  function leave() {
    if (candidates.length) setDiscarding(true);
    else close();
  }
  function update(id: string, fields: Partial<Photo>) {
    setPhotos((current) =>
      current.map((photo) => (photo.id === id ? { ...photo, ...fields } : photo)),
    );
  }
  function changeCandidate(card: Candidate) {
    setPhotos((current) =>
      current.map((photo) => ({
        ...photo,
        cards: photo.cards.map((item) => (item.id === card.id ? card : item)),
      })),
    );
  }
  async function read(list: Photo[]) {
    if (busy.current) return;
    busy.current = true;
    setReading(true);
    setMessage("");
    const abort = new AbortController();
    controller.current = abort;
    try {
      for (const photo of list) {
        if (abort.signal.aborted) break;
        update(photo.id, { state: "reading", message: undefined });
        const result = await extractPhoto(photo.file, abort.signal);
        if ("cards" in result) update(photo.id, { state: "read", cards: result.cards });
        else update(photo.id, { state: "failed", message: result.message });
      }
    } catch {
      setMessage("사진을 읽지 못했어요. 다시 시도해 주세요.");
    } finally {
      busy.current = false;
      setReading(false);
      setAllowance(await readAllowance().catch(() => null));
    }
  }
  function save() {
    if (busy.current) return;
    busy.current = true;
    start(async () => {
      try {
        let deckId = target;
        if (target === "new") {
          deckId = newDeckId.current;
          if (!created) {
            const result = await createDeck(deckId, name);
            if (!result.saved) {
              setMessage(result.message);
              return;
            }
            setCreated(true);
          }
        }
        for (let offset = 0; offset < selected.length; offset += 25) {
          const result = await saveCards(
            deckId,
            selected.slice(offset, offset + 25).map(({ id, front, back }) => ({ id, front, back })),
            "import",
          );
          if (!result.saved) {
            setMessage(
              result.message +
                (result.duplicate ? ". 같은 앞면의 카드는 선택을 해제해 주세요." : ""),
            );
            return;
          }
        }
        close();
        router.push(`/decks/${deckId}`);
        router.refresh();
      } catch {
        setMessage("카드를 저장하지 못했어요. 다시 시도해 주세요.");
      } finally {
        busy.current = false;
      }
    });
  }
  return (
    <AuthoringSheet title={candidates.length ? "카드 확인" : "사진에서 카드 추가"} close={leave}>
      <div className="flex min-w-0 flex-col gap-4">
        <p role="status" className="text-caption break-keep text-muted">
          {allowance === "loading"
            ? "사진 한도를 불러오는 중이에요"
            : allowance
              ? `${allowance.period === "day" ? "오늘" : "이번 달"} ${String(allowance.remaining)}장 남음 · ${String(allowance.limit)}장 중`
              : "사진 한도를 불러오지 못했어요. 읽을 때 한도를 확인해요."}
        </p>
        {photos.length === 0 && (
          <p className="text-caption break-keep text-muted">
            브라우저에 따라 카메라 대신 파일 선택이 열려요. JPEG, PNG, WebP, 장당 6MB까지 읽어요.
            창을 닫으면 저장하지 않은 카드는 사라져요.
          </p>
        )}
        <label className="pressable flex min-h-button cursor-pointer items-center justify-center rounded-button border border-outline bg-surface px-4 text-label">
          {photos.length ? "사진 더 추가" : camera ? "사진 찍기" : "앨범에서 고르기"}
          <input
            aria-label={camera ? "사진 찍기" : "앨범에서 고르기"}
            type="file"
            accept="image/jpeg,image/png,image/webp"
            capture={camera ? "environment" : undefined}
            multiple={!camera}
            disabled={reading || pending}
            onChange={(event) => {
              const files = Array.from(event.currentTarget.files ?? []);
              if (files.length)
                setPhotos((current) => [
                  ...current,
                  ...files
                    .slice(0, 50 - current.length)
                    .map((file): Photo => ({ id: v7(), file, state: "ready", cards: [] })),
                ]);
              event.currentTarget.value = "";
            }}
            className="sr-only"
          />
        </label>
        {photos.length > 0 && (
          <>
            {photos.some((photo) => photo.state !== "read") && (
              <>
                <p aria-live="polite" className="text-body">
                  사진 {photos.length}장 중{" "}
                  {
                    photos.filter((photo) => photo.state === "read" || photo.state === "failed")
                      .length
                  }
                  장 읽음
                </p>
                <div
                  role="progressbar"
                  aria-label="사진 읽기 진행"
                  aria-valuemin={0}
                  aria-valuemax={photos.length}
                  aria-valuenow={
                    photos.filter((photo) => photo.state === "read" || photo.state === "failed")
                      .length
                  }
                  className="h-2 overflow-hidden rounded-full bg-hairline"
                >
                  <div
                    className="h-full bg-ink"
                    style={{
                      width: `${String((100 * photos.filter((photo) => photo.state === "read" || photo.state === "failed").length) / photos.length)}%`,
                    }}
                  />
                </div>
              </>
            )}
            <ul className="divide-y divide-hairline overflow-hidden rounded-group bg-surface">
              {photos.map((photo, at) => (
                <li key={photo.id} hidden={photo.state === "read"} className="min-w-0 p-4">
                  <div className="flex items-center justify-between gap-2">
                    <span className="text-body">사진 {at + 1}</span>
                    <span className="text-caption text-muted">
                      {
                        {
                          ready: "읽기 전",
                          reading: "읽는 중",
                          read: "읽음",
                          failed: "읽지 못함",
                        }[photo.state]
                      }
                    </span>
                  </div>
                  <p className="truncate text-caption text-muted">{photo.file.name}</p>
                  {photo.message && (
                    <p role="alert" className="mt-2 text-caption break-keep text-dont-know">
                      {photo.message}
                    </p>
                  )}
                  <div className="flex flex-wrap gap-3">
                    {photo.state === "failed" && (
                      <button
                        type="button"
                        disabled={reading || pending}
                        onClick={() => {
                          void read([photo]);
                        }}
                        className="pressable min-h-tap-target text-body"
                      >
                        다시 시도
                      </button>
                    )}
                    {photo.state !== "reading" && (
                      <button
                        type="button"
                        disabled={reading || pending}
                        onClick={() => {
                          setPhotos((current) => current.filter((item) => item.id !== photo.id));
                        }}
                        className="pressable min-h-tap-target text-body text-ink-2"
                      >
                        제외
                      </button>
                    )}
                  </div>
                </li>
              ))}
            </ul>
            {reading ? (
              <button
                type="button"
                className="pressable min-h-button text-body"
                onClick={() => controller.current?.abort()}
              >
                읽기 중지
              </button>
            ) : (
              photos.some((photo) => photo.state === "ready") && (
                <button
                  type="button"
                  disabled={
                    pending ||
                    allowance === "loading" ||
                    (allowance !== null && allowance.remaining === 0)
                  }
                  onClick={() => {
                    void read(photos.filter((photo) => photo.state === "ready"));
                  }}
                  className={`pressable min-h-cta rounded-button px-4 text-label disabled:opacity-50 ${candidates.length ? "border border-outline bg-surface" : "bg-ink text-on-primary"}`}
                >
                  사진 읽기
                </button>
              )
            )}
          </>
        )}
        {photos.map(
          (photo, photoIndex) =>
            photo.cards.length > 0 && (
              <section key={photo.id} className="flex min-w-0 flex-col gap-3">
                {photos.length > 1 && <h3 className="text-body-strong">사진 {photoIndex + 1}</h3>}
                {[...new Set(photo.cards.map((card) => card.topic))].map((topic) => (
                  <div key={topic} className="flex min-w-0 flex-col gap-2">
                    <h4 className="text-section text-muted">{topic || "카드"}</h4>
                    <ul className="divide-y divide-hairline overflow-hidden rounded-group bg-surface">
                      {photo.cards
                        .filter((card) => card.topic === topic)
                        .map((card) => {
                          const front = parseContent(card.front) ?? [];
                          const back = parseContent(card.back) ?? [];
                          const whole = front.some(
                            (item) => item.kind === "table" || item.kind === "cloze",
                          );
                          return (
                            <li key={card.id} className="flex min-w-0 items-start gap-2 p-3">
                              <button
                                type="button"
                                role="checkbox"
                                aria-checked={card.selected}
                                aria-label={`${describeContent(front)} 선택`}
                                onClick={() => {
                                  changeCandidate({ ...card, selected: !card.selected });
                                }}
                                className="pressable flex size-tap-target shrink-0 items-center justify-center rounded-full text-body"
                              >
                                <span
                                  aria-hidden
                                  className={`flex size-6 items-center justify-center rounded-full border ${card.selected ? "border-ink bg-ink text-on-primary" : "border-outline"}`}
                                >
                                  {card.selected ? "✓" : ""}
                                </span>
                              </button>
                              <button
                                type="button"
                                aria-label={`${describeContent(front)} 편집`}
                                onClick={() => {
                                  if (!whole) setEditing(structuredClone(card));
                                }}
                                className="pressable min-h-tap-target min-w-0 flex-1 py-2 text-left text-body break-words"
                              >
                                {whole ? (
                                  <div className="overflow-x-auto">
                                    <WholeCard blocks={front} revealed />
                                  </div>
                                ) : (
                                  <>
                                    <span className="block font-bold">
                                      <SideText blocks={front} />
                                    </span>
                                    <span className="mt-1 block text-caption text-muted">
                                      <SideText blocks={back} />
                                    </span>
                                  </>
                                )}
                              </button>
                            </li>
                          );
                        })}
                    </ul>
                  </div>
                ))}
              </section>
            ),
        )}
        {candidates.length > 0 && (
          <>
            {!deck && (
              <label className="text-section text-muted">
                추가할 덱
                <select
                  aria-label="추가할 덱"
                  value={target}
                  disabled={created}
                  onChange={(event) => {
                    setTarget(event.target.value);
                  }}
                  className="mt-2 min-h-field w-full rounded-field bg-surface px-3 text-body text-ink"
                >
                  <option value="new">새 덱 만들기</option>
                  {decks.map((item) => (
                    <option key={item.id} value={item.id}>
                      {item.name}
                    </option>
                  ))}
                </select>
              </label>
            )}
            {target === "new" && (
              <label className="text-section text-muted">
                이름
                <input
                  value={name}
                  disabled={created}
                  maxLength={500}
                  onChange={(event) => {
                    setName(event.target.value);
                  }}
                  className="mt-2 min-h-field w-full rounded-field border border-outline bg-surface px-3 text-body text-ink"
                />
              </label>
            )}
            <button
              type="button"
              disabled={
                pending || reading || selected.length === 0 || (target === "new" && !name.trim())
              }
              onClick={save}
              className="pressable sticky bottom-0 min-h-cta rounded-button bg-ink px-4 text-label text-on-primary disabled:opacity-50"
            >
              {pending ? "저장 중" : `${String(selected.length)}장 추가`}
            </button>
          </>
        )}
        {message && (
          <p role="alert" className="text-caption break-keep text-dont-know">
            {message}
          </p>
        )}
      </div>
      {editing && (
        <AuthoringSheet
          title="카드 편집"
          close={() => {
            setEditing(null);
          }}
        >
          <CardFields
            draft={editing}
            change={(draft) => {
              setEditing({ ...editing, ...draft });
            }}
          />
          <button
            type="button"
            onClick={() => {
              changeCandidate(editing);
              setEditing(null);
            }}
            className="pressable mt-5 min-h-cta w-full rounded-button bg-ink text-label text-on-primary"
          >
            완료
          </button>
        </AuthoringSheet>
      )}
      {discarding && (
        <AuthoringSheet
          title="찾은 카드를 버릴까요?"
          close={() => {
            setDiscarding(false);
          }}
        >
          <p className="text-secondary break-keep text-muted">
            다시 읽으면 사진 한도를 다시 사용해요.
          </p>
          <div className="mt-4 flex flex-col gap-2">
            <button
              type="button"
              onClick={() => {
                setDiscarding(false);
              }}
              className="pressable min-h-button text-body"
            >
              취소
            </button>
            <button
              type="button"
              onClick={close}
              className="pressable min-h-button rounded-button bg-dont-know text-label text-on-primary"
            >
              버리기
            </button>
          </div>
        </AuthoringSheet>
      )}
    </AuthoringSheet>
  );
}
