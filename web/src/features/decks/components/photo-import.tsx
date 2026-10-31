"use client";

import { useEffect, useEffectEvent, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Check, CircleAlert, Clock, ImagePlus, LoaderCircle } from "lucide-react";
import { v7 } from "uuid";
import { createDeck, readAllowance, saveCards } from "../actions";
import { preparePhoto, sendPhoto } from "../extract-photo";
import { describeFailure, isRetakeable, isRetryable, type PhotoFailure } from "../photo-failure";
import { type Candidate } from "../photo-candidates";
import { describeContent, parseContent } from "../card-content";
import type { Deck } from "../library";
import { AuthoringSheet } from "./authoring-sheet";
import { CardFields } from "./card-fields";
import { WholeCard } from "./whole-card";
import { SideText } from "./side-text";

/** A photo's place in the job, as the phone's `PhotoState`. */
type PhotoState =
  | { kind: "waiting" }
  | { kind: "reading" }
  | { kind: "read"; cards: Candidate[] }
  | { kind: "failed"; failure: PhotoFailure };
type Photo = { id: string; file: File; url: string; upload?: File; state: PhotoState };

/** The most photos one import holds, as the phone's `maxPhotosPerImport`. */
const maxPhotos = 50;
const privacyNote = "사진은 카드를 만드는 데만 쓰고 서버에 남기지 않아요";

/**
 * A browser-bound photo job drawn as the phone's photo import: one photo at 카드를 찾고 있어요 or
 * its failure, several at 사진 n장 중 k장 읽음 with a row per photo, then the list to review.
 */
export function PhotoImport({
  deck,
  decks,
  camera,
  files,
  close,
}: {
  deck?: Deck;
  decks: Deck[];
  camera: boolean;
  files: File[];
  close: () => void;
}) {
  const [photos, setPhotos] = useState(() => photosOf(files, maxPhotos));
  const photosRef = useRef(photos);
  const [jobFailure, setJobFailure] = useState<PhotoFailure | null>(null);
  const [note, setNote] = useState("");
  const [listOpen, setListOpen] = useState(false);
  const [message, setMessage] = useState("");
  const [target, setTarget] = useState(deck?.id ?? "new");
  const [name, setName] = useState("");
  const [editing, setEditing] = useState<Candidate | null>(null);
  const [discarding, setDiscarding] = useState(false);
  const [pending, start] = useTransition();
  const pumping = useRef(false);
  const closed = useRef(false);
  const started = useRef(false);
  const busy = useRef(false);
  const newDeckId = useRef(v7());
  const [created, setCreated] = useState(false);
  const router = useRouter();

  function change(next: (current: Photo[]) => Photo[]) {
    photosRef.current = next(photosRef.current);
    setPhotos(photosRef.current);
    // Once every photo is read, the list opens; photos added later return to it.
    if (photosRef.current.length && photosRef.current.every((photo) => photo.state.kind === "read"))
      setListOpen(true);
  }
  function update(id: string, fields: Partial<Photo>) {
    change((current) =>
      current.map((photo) => (photo.id === id ? { ...photo, ...fields } : photo)),
    );
  }
  function remove(keep: (photo: Photo) => boolean) {
    for (const photo of photosRef.current) if (!keep(photo)) URL.revokeObjectURL(photo.url);
    change((current) => current.filter(keep));
  }
  async function readOne(photo: Photo): Promise<PhotoState> {
    let upload = photo.upload;
    if (!upload) {
      const prepared = await preparePhoto(photo.file);
      if (!(prepared instanceof File)) return { kind: "failed", failure: prepared };
      upload = prepared;
      update(photo.id, { upload });
    }
    const result = await sendPhoto(upload);
    return "cards" in result
      ? { kind: "read", cards: result.cards }
      : { kind: "failed", failure: result.failure };
  }
  // Reads the waiting photos in order, one call at a time, as Server Actions run one at a time.
  async function pump() {
    if (pumping.current) return;
    pumping.current = true;
    try {
      for (;;) {
        const next = photosRef.current.find((photo) => photo.state.kind === "waiting");
        if (closed.current || !next) break;
        update(next.id, { state: { kind: "reading" } });
        const state = await readOne(next);
        // A photo left out or cancelled while it was read keeps nothing of its answer.
        if (photosRef.current.some((photo) => photo.id === next.id)) update(next.id, { state });
      }
    } finally {
      pumping.current = false;
    }
  }
  async function addBatch(chosen: File[]) {
    const batch = photosOf(chosen, maxPhotos - photosRef.current.length);
    if (!batch.length) return;
    change((current) => [...current, ...batch]);
    await startBatch(batch, true);
  }
  async function startBatch(batch: Photo[], toList: boolean) {
    setMessage("");
    setNote("");
    // Where the allowance cannot be read every photo is sent, and a refusal shows on its photo.
    const allowance = await readAllowance().catch(() => null);
    if (closed.current) return;
    if (allowance && allowance.remaining < batch.length) {
      const left = new Set(batch.slice(allowance.remaining).map((photo) => photo.id));
      remove((photo) => !left.has(photo.id));
      if (allowance.remaining === 0) {
        const failure: PhotoFailure = {
          kind: "limit",
          limit: allowance.limit,
          period: allowance.period,
        };
        if (toList) setMessage(describeFailure(failure));
        else setJobFailure(failure);
        return;
      }
      const count = String(allowance.remaining);
      setNote(
        `${allowance.period === "day" ? "오늘" : "이번 달"} ${count}장 더 만들 수 있어요. 처음 ${count}장만 읽어요.`,
      );
    }
    void pump();
  }
  function replace(chosen: File[]) {
    setJobFailure(null);
    remove(() => false);
    const batch = photosOf(chosen, maxPhotos);
    change(() => batch);
    void startBatch(batch, false);
  }
  // The photos chosen before the sheet opened start the job, once.
  const begin = useEffectEvent(() => {
    if (started.current) return;
    started.current = true;
    void startBatch(photosRef.current, false);
  });
  useEffect(() => {
    closed.current = false;
    begin();
    return () => {
      closed.current = true;
    };
  }, []);
  useEffect(
    () => () => {
      for (const photo of photosRef.current) URL.revokeObjectURL(photo.url);
    },
    [],
  );

  const unfinished = photos.some((photo) => photo.state.kind !== "read");

  const read = photos.filter((photo) => photo.state.kind === "read");
  const candidates = read.flatMap((photo) =>
    photo.state.kind === "read" ? photo.state.cards : [],
  );
  const selected = candidates.filter((card) => card.selected);
  function leave() {
    if (candidates.length) setDiscarding(true);
    else close();
  }
  function cancel() {
    if (listOpen) remove((photo) => photo.state.kind === "read");
    else leave();
  }
  function retry(photo: Photo) {
    update(photo.id, { state: { kind: "waiting" } });
    void pump();
  }
  // Sends every photo whose failure sending again can help, as one action beside each row's own.
  function retryFailed() {
    change((current) =>
      current.map((photo) =>
        photo.state.kind === "failed" && isRetryable(photo.state.failure)
          ? { ...photo, state: { kind: "waiting" } }
          : photo,
      ),
    );
    void pump();
  }
  function changeCandidate(card: Candidate) {
    change((current) =>
      current.map((photo) =>
        photo.state.kind === "read"
          ? {
              ...photo,
              state: {
                kind: "read",
                cards: photo.state.cards.map((item) => (item.id === card.id ? card : item)),
              },
            }
          : photo,
      ),
    );
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

  const source = camera ? "사진 찍기" : "앨범에서 고르기";
  const single = !listOpen && photos.length === 1 ? photos[0] : undefined;
  const singleFailure = single?.state.kind === "failed" ? single.state.failure : null;
  const failure = jobFailure ?? singleFailure;
  const failed = photos.filter((photo) => photo.state.kind === "failed").length;
  const waiting = photos.some(
    (photo) => photo.state.kind === "waiting" || photo.state.kind === "reading",
  );
  const readingTitle =
    waiting || failed === 0
      ? `사진 ${String(photos.length)}장 중 ${String(read.length)}장 읽음`
      : `사진 ${String(failed)}장을 읽지 못했어요`;
  const vocabulary =
    candidates.length > 0 && candidates.every((card) => card.kind === "vocabulary");
  const title = failure
    ? source
    : single
      ? "카드를 찾고 있어요"
      : unfinished || photos.length === 0
        ? readingTitle
        : vocabulary
          ? "단어를 찾았어요"
          : `카드 ${String(candidates.length)}장을 만들었어요`;

  return (
    <AuthoringSheet title={title} close={unfinished && !failure ? cancel : leave}>
      {failure ? (
        <div className="flex min-w-0 flex-col">
          <p aria-live="polite" className="py-10 text-center text-body-strong break-keep">
            {describeFailure(failure)}
          </p>
          {note && !jobFailure && (
            <p className="pb-4 text-center text-body break-keep text-ink-2">{note}</p>
          )}
          {(isRetakeable(failure) || (single && isRetryable(failure))) && (
            <div className="sticky -bottom-4 flex gap-3 bg-ground pt-3 pb-7">
              {isRetakeable(failure) && (
                <PhotoPicker
                  label={camera ? "다시 찍기" : "다른 사진 고르기"}
                  camera={camera}
                  multiple={false}
                  primary={!(single && isRetryable(failure))}
                  pick={replace}
                />
              )}
              {single && isRetryable(failure) && (
                <button
                  type="button"
                  onClick={() => {
                    retry(single);
                  }}
                  className="pressable min-h-cta flex-1 rounded-button bg-ink px-4 text-label text-on-primary"
                >
                  다시 시도
                </button>
              )}
            </div>
          )}
        </div>
      ) : single ? (
        <div className="flex min-w-0 flex-col gap-5">
          <div className="flex items-center gap-4">
            <Thumbnail url={single.url} className="h-24 w-18" />
            <div
              role="progressbar"
              aria-label="카드를 찾고 있어요"
              className="h-2 flex-1 overflow-hidden rounded-full bg-hairline"
            >
              <div className="h-full w-full rounded-full bg-ink motion-safe:animate-skeleton" />
            </div>
          </div>
          {note && <p className="text-body break-keep text-ink-2">{note}</p>}
          <div aria-hidden className="flex flex-col gap-row-gap">
            {[0, 1, 2, 3].map((row) => (
              <div
                key={row}
                className="flex gap-4 rounded-group bg-surface p-5 motion-safe:animate-skeleton"
              >
                <span className="h-3 w-[35%] rounded-full bg-hairline" />
                <span className="ml-auto h-3 w-[25%] rounded-full bg-hairline" />
              </div>
            ))}
          </div>
          <p className="text-center text-caption break-keep text-muted">{privacyNote}</p>
          <CancelBar cancel={cancel} />
        </div>
      ) : unfinished ? (
        <div className="flex min-w-0 flex-col gap-5">
          <p role="status" className="sr-only">
            {readingTitle}
          </p>
          <div aria-hidden className="h-2 overflow-hidden rounded-full bg-hairline">
            <div
              className="h-full rounded-full bg-ink transition-[width]"
              style={{
                width: `${String(photos.length ? (100 * read.length) / photos.length : 0)}%`,
              }}
            />
          </div>
          {note && <p className="text-body break-keep text-ink-2">{note}</p>}
          <ul className="flex flex-col gap-row-gap">
            {photos.map((photo, at) => (
              <PhotoRow
                key={photo.id}
                photo={photo}
                number={at + 1}
                retry={() => {
                  retry(photo);
                }}
                drop={() => {
                  remove((item) => item.id !== photo.id);
                  // With every photo left out, the screen closes.
                  if (!photosRef.current.length) close();
                }}
              />
            ))}
          </ul>
          <p className="text-center text-caption break-keep text-muted">{privacyNote}</p>
          <CancelBar
            cancel={cancel}
            retryFailed={
              photos.some(
                (photo) => photo.state.kind === "failed" && isRetryable(photo.state.failure),
              )
                ? retryFailed
                : undefined
            }
          />
        </div>
      ) : (
        <div className="flex min-w-0 flex-col gap-4">
          {read.map((photo, photoIndex) => {
            const cards = photo.state.kind === "read" ? photo.state.cards : [];
            return (
              <section key={photo.id} className="flex min-w-0 flex-col gap-3">
                {read.length > 1 && (
                  <div className="flex items-center gap-3 pt-2">
                    <Thumbnail url={photo.url} className="h-16 w-12" />
                    <div className="flex min-w-0 flex-col">
                      <h3 className="text-body-strong">사진 {photoIndex + 1}</h3>
                      <span className="text-caption text-muted">카드 {cards.length}장</span>
                    </div>
                  </div>
                )}
                {[...new Set(cards.map((card) => card.topic))].map((topic) => {
                  const rows = cards.filter((card) => card.topic === topic);
                  return (
                    <div key={topic} className="flex min-w-0 flex-col gap-2">
                      <h4 className="text-section text-muted">
                        {topic || "카드"} {rows.length}
                      </h4>
                      <ul className="divide-y divide-hairline overflow-hidden rounded-group bg-surface">
                        {rows.map((card) => (
                          <CandidateRow
                            key={card.id}
                            card={card}
                            toggle={() => {
                              changeCandidate({ ...card, selected: !card.selected });
                            }}
                            edit={() => {
                              setEditing(structuredClone(card));
                            }}
                          />
                        ))}
                      </ul>
                    </div>
                  );
                })}
              </section>
            );
          })}
          {photos.length < maxPhotos && (
            <PhotoPicker
              label="사진 더 추가"
              icon
              camera={false}
              multiple
              primary={false}
              disabled={pending}
              pick={(chosen) => {
                void addBatch(chosen);
              }}
            />
          )}
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
          {message && (
            <p role="alert" className="text-caption break-keep text-dont-know-text">
              {message}
            </p>
          )}
          <div className="sticky -bottom-4 bg-ground pt-3 pb-7">
            <button
              type="button"
              disabled={pending || selected.length === 0 || (target === "new" && !name.trim())}
              onClick={save}
              className="pressable min-h-cta w-full rounded-button bg-ink px-4 text-label text-on-primary disabled:opacity-50"
            >
              {pending ? "저장 중" : `카드 ${String(selected.length)}장 추가`}
            </button>
          </div>
        </div>
      )}
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
            찾은 카드 {candidates.length}장이 사라져요. 다시 읽으면 오늘 사진 한도가 다시 쓰여요.
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

/** Up to [room] chosen files as photos waiting to be read, each with a URL for its thumbnail. */
function photosOf(files: File[], room: number): Photo[] {
  return files.slice(0, Math.max(0, room)).map((file) => ({
    id: v7(),
    file,
    url: URL.createObjectURL(file),
    state: { kind: "waiting" },
  }));
}

/** A prepared photo's thumbnail, drawn upright; a photo the browser cannot show is its hairline. */
function Thumbnail({ url, className }: { url: string; className: string }) {
  return (
    <span
      aria-hidden
      className={`${className} block shrink-0 rounded-button bg-hairline bg-cover bg-center`}
      style={{ backgroundImage: `url(${url})` }}
    />
  );
}

/** "취소" at the bottom of the reading screens, and "실패한 사진 다시 시도" beside it while one can be sent again. */
function CancelBar({ cancel, retryFailed }: { cancel: () => void; retryFailed?: () => void }) {
  return (
    <div className="sticky -bottom-4 flex gap-3 bg-ground pt-3 pb-7">
      <button
        type="button"
        onClick={cancel}
        className="pressable min-h-cta flex-1 rounded-button border border-outline bg-surface px-4 text-label"
      >
        취소
      </button>
      {retryFailed && (
        <button
          type="button"
          onClick={retryFailed}
          className="pressable min-h-cta flex-[2] rounded-button bg-ink px-4 text-label break-keep text-on-primary"
        >
          실패한 사진 다시 시도
        </button>
      )}
    </div>
  );
}

/** One photo: its thumbnail, "사진 n" and its state in words with an icon; a failed one its actions. */
function PhotoRow({
  photo,
  number,
  retry,
  drop,
}: {
  photo: Photo;
  number: number;
  retry: () => void;
  drop: () => void;
}) {
  const { state } = photo;
  const status =
    state.kind === "waiting"
      ? "기다리는 중"
      : state.kind === "reading"
        ? "읽는 중"
        : state.kind === "read"
          ? `카드 ${String(state.cards.length)}장`
          : describeFailure(state.failure);
  // Green means 안다 alone: a photo read is ink, its words saying so.
  const icon =
    state.kind === "waiting" ? (
      <Clock aria-hidden className="size-small-icon shrink-0 text-muted" />
    ) : state.kind === "reading" ? (
      <LoaderCircle
        aria-hidden
        className="size-small-icon shrink-0 text-ink motion-safe:animate-spin"
      />
    ) : state.kind === "read" ? (
      <Check aria-hidden className="size-small-icon shrink-0 text-ink" />
    ) : (
      <CircleAlert aria-hidden className="size-small-icon shrink-0 text-dont-know" />
    );
  return (
    <li className="flex min-w-0 flex-col gap-3 rounded-group bg-surface p-3">
      <div className="flex items-center gap-3">
        <Thumbnail url={photo.url} className="h-16 w-12" />
        <p className="flex min-w-0 flex-1 flex-col gap-1">
          <span className="text-body-strong">사진 {number}</span>
          <span
            aria-live={state.kind === "failed" ? "polite" : undefined}
            className={`text-body break-keep ${state.kind === "failed" ? "text-ink" : "text-ink-2"}`}
          >
            {status}
          </span>
        </p>
        {icon}
      </div>
      {state.kind === "failed" && (
        <div className="flex gap-2">
          {isRetryable(state.failure) && (
            <button
              type="button"
              aria-label={`사진 ${String(number)} 다시 시도`}
              onClick={retry}
              className="pressable min-h-button flex-1 rounded-button border border-outline bg-surface px-3 text-label"
            >
              다시 시도
            </button>
          )}
          <button
            type="button"
            aria-label={`사진 ${String(number)} 빼기`}
            onClick={drop}
            className="pressable min-h-button flex-1 rounded-button border border-outline bg-surface px-3 text-label"
          >
            빼기
          </button>
        </div>
      )}
    </li>
  );
}

/** A candidate's row: its round check, and its sides, or a whole card's front, to edit. */
function CandidateRow({
  card,
  toggle,
  edit,
}: {
  card: Candidate;
  toggle: () => void;
  edit: () => void;
}) {
  const front = parseContent(card.front) ?? [];
  const back = parseContent(card.back) ?? [];
  const whole = front.some((item) => item.kind === "table" || item.kind === "cloze");
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
      {whole ? (
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
          <span className="block font-bold">
            <SideText blocks={front} />
          </span>
          <span className="mt-1 block text-caption text-muted">
            <SideText blocks={back} />
          </span>
        </button>
      )}
    </li>
  );
}

/** A file picker drawn as a button: any image, which the browser then prepares as JPEG. */
function PhotoPicker({
  label,
  camera,
  multiple,
  primary,
  pick,
  icon = false,
  disabled = false,
}: {
  label: string;
  camera: boolean;
  multiple: boolean;
  primary: boolean;
  pick: (files: File[]) => void;
  icon?: boolean;
  disabled?: boolean;
}) {
  return (
    <label
      className={`pressable flex min-h-cta flex-1 cursor-pointer items-center justify-center gap-2 rounded-button px-4 text-label focus-within:outline-2 focus-within:outline-offset-2 focus-within:outline-ink ${primary ? "bg-ink text-on-primary" : "border border-outline bg-surface"}`}
    >
      {icon && <ImagePlus aria-hidden className="size-small-icon" />}
      {label}
      <input
        type="file"
        accept="image/*"
        capture={camera ? "environment" : undefined}
        multiple={multiple}
        disabled={disabled}
        onChange={(event) => {
          const chosen = Array.from(event.currentTarget.files ?? []);
          event.currentTarget.value = "";
          // A cancelled picker opens nothing and shows no error.
          if (chosen.length) pick(chosen);
        }}
        className="sr-only"
      />
    </label>
  );
}
