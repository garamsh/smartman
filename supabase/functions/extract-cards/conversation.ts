/**
 * The conversation token a survey answers with: proof that the user's photo has been counted
 * against the daily limit, so the make call on the same photo within its life counts nothing.
 * It holds the user, the SHA-256 of the image, whether every group of the survey was
 * vocabulary, and an expiry, signed with HMAC-SHA-256 under a key derived from the service-role
 * key. The server keeps nothing: the token is the conversation.
 */

import type { UserId } from "../_shared/auth.ts";
import type { Image } from "./request.ts";

/** How long a conversation lasts after its survey. */
export const CONVERSATION_MS = 30 * 60 * 1000;

const KEY_LABEL = "extract-cards conversation";

/** What a verified token says. */
export type Conversation = {
  /** Every group of the survey was vocabulary, so the cards are made on the vocabulary model. */
  readonly vocabulary: boolean;
};

type Payload = { u: string; h: string; v: boolean; e: number };

/** A token for `userId`'s `image`, valid until `CONVERSATION_MS` after `now` (epoch ms). */
export async function issueToken(
  secret: string,
  userId: UserId,
  image: Image,
  vocabulary: boolean,
  now: number,
): Promise<string> {
  const payload: Payload = {
    u: userId,
    h: await imageHash(image),
    v: vocabulary,
    e: now + CONVERSATION_MS,
  };
  const body = base64Url(new TextEncoder().encode(JSON.stringify(payload)));
  return `${body}.${await sign(secret, body)}`;
}

/**
 * The conversation `token` proves for `userId`'s `image` at `now`, or null when it is malformed,
 * forged, expired, or for another user or image.
 */
export async function verifyToken(
  secret: string,
  token: string,
  userId: UserId,
  image: Image,
  now: number,
): Promise<Conversation | null> {
  const [body, signature, ...rest] = token.split(".");
  if (rest.length > 0 || body === undefined || signature === undefined) {
    return null;
  }
  if (!await verify(secret, body, signature)) return null;
  let payload: unknown;
  try {
    payload = JSON.parse(new TextDecoder().decode(fromBase64Url(body)));
  } catch {
    return null;
  }
  if (
    !isPayload(payload) || payload.u !== userId || payload.e <= now ||
    payload.h !== await imageHash(image)
  ) {
    return null;
  }
  return { vocabulary: payload.v };
}

async function imageHash(image: Image): Promise<string> {
  const bytes = Uint8Array.from(atob(image.base64), (c) => c.charCodeAt(0));
  return base64Url(
    new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
  );
}

/** The HMAC key, derived from the service-role key with HKDF under this token's own label. */
async function hmacKey(secret: string): Promise<CryptoKey> {
  const material = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    "HKDF",
    false,
    ["deriveKey"],
  );
  return crypto.subtle.deriveKey(
    {
      name: "HKDF",
      hash: "SHA-256",
      salt: new Uint8Array(),
      info: new TextEncoder().encode(KEY_LABEL),
    },
    material,
    { name: "HMAC", hash: "SHA-256", length: 256 },
    false,
    ["sign", "verify"],
  );
}

async function sign(secret: string, body: string): Promise<string> {
  const signature = await crypto.subtle.sign(
    "HMAC",
    await hmacKey(secret),
    new TextEncoder().encode(body),
  );
  return base64Url(new Uint8Array(signature));
}

async function verify(
  secret: string,
  body: string,
  signature: string,
): Promise<boolean> {
  let bytes: Uint8Array<ArrayBuffer>;
  try {
    bytes = fromBase64Url(signature);
  } catch {
    return false;
  }
  // The platform's verify compares in constant time.
  return crypto.subtle.verify(
    "HMAC",
    await hmacKey(secret),
    bytes,
    new TextEncoder().encode(body),
  );
}

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(
    /=+$/,
    "",
  );
}

function fromBase64Url(text: string): Uint8Array<ArrayBuffer> {
  if (!/^[A-Za-z0-9_-]*$/.test(text)) throw new SyntaxError("not base64url");
  const base64 = text.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);
  return Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
}

function isPayload(value: unknown): value is Payload {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return false;
  }
  const record: Record<string, unknown> = { ...value };
  return typeof record.u === "string" && typeof record.h === "string" &&
    typeof record.v === "boolean" && typeof record.e === "number";
}
