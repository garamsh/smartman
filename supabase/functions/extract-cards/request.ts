/**
 * Parses the request body: one base64 image of a supported type, optional language hints, and
 * what the request asks for: a survey of the page, cards made to a plan, or today's cards.
 */

export const MAX_IMAGE_BYTES = 6 * 1024 * 1024;
// Base64 of the largest image, plus room for the JSON around it.
const MAX_BODY_BYTES = Math.ceil(MAX_IMAGE_BYTES / 3) * 4 + 64 * 1024;

export type ImageType = "image/jpeg" | "image/png" | "image/webp";

/** An image whose decoded size and type have been checked; `base64` is never logged or stored. */
export type Image = { readonly type: ImageType; readonly base64: string };

/** A BCP 47 language tag, such as `en` or `ko`, for one side of the deck. */
export type LanguageTag = string & { readonly __brand: "LanguageTag" };

export type LanguageHints = {
  readonly front?: LanguageTag;
  readonly back?: LanguageTag;
};

/** How a card of a chosen group is shaped: what its front asks and how full its answer is. */
export type Shape = {
  readonly front: "question" | "term" | "answer";
  readonly back: "short" | "answer";
};

/** A group of the survey the user chose, by its id and title, in the shape chosen for it. */
export type PlannedGroup = {
  readonly id: string;
  readonly title: string;
  readonly shape: Shape;
};

/** What the user chose on the choice screen: groups of the survey, and topics they typed. */
export type Plan = {
  readonly groups: readonly PlannedGroup[];
  readonly added: readonly string[];
};

export const MAX_PLAN_GROUPS = 12;
export const MAX_ADDED_TOPICS = 5;
export const MAX_GROUP_ID_CHARS = 40;
export const MAX_TITLE_CHARS = 60;
// A token is a few hundred characters; anything far longer is not one.
const MAX_CONVERSATION_CHARS = 1024;

/** A survey of the page; cards made to a plan; or, with neither, today's single call. */
export type Mode =
  | { readonly kind: "survey" }
  | { readonly kind: "plan"; readonly plan: Plan }
  | { readonly kind: "cards" };

export type ExtractRequest = {
  readonly image: Image;
  readonly languages: LanguageHints;
  readonly mode: Mode;
  /** The token a survey answered with, unchecked; null when none was sent. */
  readonly conversation: string | null;
};

export type RequestFailure = "bad_request" | "too_large" | "unsupported_type";

export type ParsedRequest =
  | { readonly ok: true; readonly request: ExtractRequest }
  | { readonly ok: false; readonly failure: RequestFailure };

const BASE64 = /^[A-Za-z0-9+/]*={0,2}$/;
const LANGUAGE_TAG = /^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$/;

/** Reads at most the body size an accepted image can take, and parses it. */
export async function parseRequest(
  body: ReadableStream<Uint8Array> | null,
): Promise<ParsedRequest> {
  if (body === null) return refuse("bad_request");
  const bytes = await readAtMost(body, MAX_BODY_BYTES);
  if (bytes === null) return refuse("too_large");

  let value: unknown;
  try {
    value = JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    return refuse("bad_request");
  }
  if (!isRecord(value)) return refuse("bad_request");

  const base64 = value.image;
  if (
    typeof base64 !== "string" || base64.length % 4 !== 0 ||
    !BASE64.test(base64)
  ) {
    return refuse("bad_request");
  }
  const padding = base64.endsWith("==") ? 2 : base64.endsWith("=") ? 1 : 0;
  if ((base64.length / 4) * 3 - padding > MAX_IMAGE_BYTES) {
    return refuse("too_large");
  }
  const type = sniffType(base64);
  if (type === null) return refuse("unsupported_type");

  const languages = parseLanguages(value.languages);
  if (languages === null) return refuse("bad_request");
  const mode = parseMode(value.survey, value.plan);
  if (mode === null) return refuse("bad_request");
  const conversation = value.conversation;
  if (
    conversation !== undefined &&
    (typeof conversation !== "string" || conversation === "" ||
      conversation.length > MAX_CONVERSATION_CHARS)
  ) {
    return refuse("bad_request");
  }
  return {
    ok: true,
    request: {
      image: { type, base64 },
      languages,
      mode,
      conversation: conversation ?? null,
    },
  };
}

/** `survey: true` asks for a survey and `plan` for cards made to it; never both. */
function parseMode(survey: unknown, plan: unknown): Mode | null {
  if (survey !== undefined && survey !== true) return null;
  if (survey === true) return plan === undefined ? { kind: "survey" } : null;
  if (plan === undefined) return { kind: "cards" };
  const parsed = parsePlan(plan);
  return parsed === null ? null : { kind: "plan", plan: parsed };
}

function parsePlan(value: unknown): Plan | null {
  if (!isRecord(value) || !Array.isArray(value.groups)) return null;
  const added = value.added ?? [];
  if (
    !Array.isArray(added) || added.length > MAX_ADDED_TOPICS ||
    value.groups.length > MAX_PLAN_GROUPS ||
    value.groups.length + added.length === 0
  ) {
    return null;
  }
  const groups: PlannedGroup[] = [];
  for (const group of value.groups) {
    if (!isRecord(group) || !isRecord(group.shape)) return null;
    const id = text(group.id, MAX_GROUP_ID_CHARS);
    const title = text(group.title, MAX_TITLE_CHARS);
    const { front, back } = group.shape;
    if (
      id === null || title === null ||
      (front !== "question" && front !== "term" && front !== "answer") ||
      (back !== "short" && back !== "answer")
    ) {
      return null;
    }
    groups.push({ id, title, shape: { front, back } });
  }
  const topics: string[] = [];
  for (const topic of added) {
    const parsed = text(topic, MAX_TITLE_CHARS);
    if (parsed === null) return null;
    topics.push(parsed);
  }
  return { groups, added: topics };
}

/** A string trimmed to 1 to `max` characters (code points), else null. */
function text(value: unknown, max: number): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  const length = [...trimmed].length;
  return length >= 1 && length <= max ? trimmed : null;
}

/** The type the image's leading bytes declare; a declared MIME type is not trusted. */
function sniffType(base64: string): ImageType | null {
  const head = Uint8Array.from(
    atob(base64.slice(0, 16)),
    (c) => c.charCodeAt(0),
  );
  const ascii = (from: number, to: number) =>
    String.fromCharCode(...head.slice(from, to));
  if (head[0] === 0xff && head[1] === 0xd8 && head[2] === 0xff) {
    return "image/jpeg";
  }
  if (ascii(0, 8) === "\x89PNG\r\n\x1a\n") return "image/png";
  if (ascii(0, 4) === "RIFF" && ascii(8, 12) === "WEBP") return "image/webp";
  return null;
}

function parseLanguages(value: unknown): LanguageHints | null {
  if (value === undefined) return {};
  if (!isRecord(value)) return null;
  const hints: { front?: LanguageTag; back?: LanguageTag } = {};
  for (const [key, tag] of Object.entries(value)) {
    if (
      (key !== "front" && key !== "back") || typeof tag !== "string" ||
      !LANGUAGE_TAG.test(tag)
    ) {
      return null;
    }
    hints[key] = tag as LanguageTag;
  }
  return hints;
}

async function readAtMost(
  body: ReadableStream<Uint8Array>,
  limit: number,
): Promise<Uint8Array | null> {
  const chunks: Uint8Array[] = [];
  let size = 0;
  for await (const chunk of body) {
    size += chunk.length;
    if (size > limit) return null;
    chunks.push(chunk);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  return bytes;
}

function refuse(failure: RequestFailure): ParsedRequest {
  return { ok: false, failure };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
