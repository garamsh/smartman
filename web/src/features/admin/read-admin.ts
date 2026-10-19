import "server-only";

import { cookies } from "next/headers";

import { describeContent, parseContent } from "@/features/decks";
import { parseTimeZone, studyDayStart, timeZoneCookie } from "@/features/study";
import { classifyFailure, requestTimeoutMs, type ServerFailure } from "@/supabase/failure";
import { field, parseTime } from "@/supabase/row";
import { createClient } from "@/supabase/server";
import { readUserId } from "@/supabase/session";

import type { BreakdownRow } from "./usage";

/** Why an admin read failed: the server's failure, `rejected` for a caller who is not an admin, or a row this version cannot read. */
export type AdminFailure = ServerFailure | "unreadable";

/** An admin read's result: its value, or why there is none. */
export type AdminRead<T> = { data: T } | { failure: AdminFailure };

/** A deck's place in the public listing: public or private, hidden by moderation, deleted by its owner. */
export type DeckState = { visibility: "public" | "private"; hidden: boolean; deleted: boolean };

/** Who owns a deck: the account's email and, once the owner published, its display name. */
export type Owner = { id: string; email: string; name: string | null };

export type Overview = {
  users: number;
  newUsers7d: number;
  newUsers30d: number;
  studiedToday: number;
  studied7d: number;
};

export type ReportedDeck = {
  id: string;
  name: string;
  owner: Owner;
  state: DeckState;
  reports: number;
  reasons: string[];
  lastReportedAt: number;
};

export type PublicDeck = {
  id: string;
  name: string;
  owner: Owner;
  hidden: boolean;
  cards: number;
  copies: number;
  reports: number;
  publishedAt: number | null;
};

export type AdminDeck = {
  id: string;
  name: string;
  description: string | null;
  owner: Owner;
  state: DeckState;
  copies: number;
  reports: number;
  reasons: string[];
  /** Its removal from sharing for good, when an admin removed it (ADR 0072). */
  removal: { reason: string; removedAt: number } | null;
  /** The live cards, oldest first, each side as the one line of text it shows. */
  cards: { id: string; front: string; back: string }[];
};

export type UserMatch = { id: string; email: string; createdAt: number; suspended: boolean };

/** A page of the users a search matched, and how many it matched in all. */
export type UserPage = { users: UserMatch[]; total: number };

/** A user's deck as the user's page lists it. */
export type UserDeck = {
  id: string;
  name: string;
  visibility: "public" | "private";
  hidden: boolean;
  removed: boolean;
  cards: number;
};

/** Why, when and by whom a user was suspended. */
export type Suspension = { reason: string; suspendedAt: number; suspendedByEmail: string | null };

/** A plan, as the server names it. */
export type PlanId = "free" | "pro" | "special";

/** A plan's settings, as the admin area sets them. */
export type PlanSettings = {
  id: PlanId;
  model: string;
  dailyLimit: number;
  updatedAt: number;
  updatedByEmail: string | null;
};

/**
 * A user's plan now, with its model and daily limit, null while its settings are missing, and the
 * grant behind it, when there is one; an ended Special grant shows beside Free.
 */
export type UserPlan = {
  plan: PlanId | null;
  model: string | null;
  dailyLimit: number | null;
  grant: {
    plan: "pro" | "special";
    endsAt: number | null;
    grantedAt: number;
    grantedByEmail: string | null;
  } | null;
};

export type AdminUser = {
  id: string;
  email: string;
  createdAt: number;
  lastAnswerAt: number | null;
  decks: number;
  cards: number;
  extractionsToday: number;
  admin: boolean;
  publicDecks: PublicDeck[];
  plan: UserPlan;
  suspension: Suspension | null;
  /** Every live deck of the user, public or private, newest first. */
  allDecks: UserDeck[];
};

export type AdminMember = {
  id: string;
  email: string;
  grantedAt: number;
  grantedByEmail: string | null;
  /** Whether this is the signed-in admin, whose own role the area does not offer to revoke. */
  self: boolean;
};

export type AuditEntry = {
  id: number;
  at: number;
  adminEmail: string;
  action: string;
  targetKind: string;
  targetId: string;
  detail: Record<string, unknown>;
};

const day = 86_400_000;

/** The zone the browser names in its cookie, in which the admin area shows times, or the fallback. */
export async function adminTimeZone(): Promise<string> {
  return parseTimeZone(
    (await cookies()).getAll().find((cookie) => cookie.name === timeZoneCookie)?.value,
  );
}

/**
 * Whether the signed-in user is an admin, as the server's `is_admin` answers; false without a
 * session the server accepts. A server that cannot be reached, or an answer this version cannot
 * read, is a failure.
 */
export async function readIsAdmin(): Promise<boolean | { failure: AdminFailure }> {
  const read = await call("is_admin");
  if ("failure" in read) return read.failure === "rejected" ? false : read;
  return typeof read.data === "boolean" ? read.data : { failure: "unreadable" };
}

/**
 * The overview, with "today" and "the last 7 days" the study days, from 04:00, of the zone the
 * browser names in its cookie, and the extractions by UTC day, the daily limit's day.
 */
export async function readOverview(): Promise<AdminRead<Overview>> {
  const timeZone = await adminTimeZone();
  const now = Date.now();
  const totals = await call("admin_overview", {
    today_start: new Date(studyDayStart(now, timeZone)).toISOString(),
    week_start: new Date(studyDayStart(now - 6 * day, timeZone)).toISOString(),
  });
  if ("failure" in totals) return totals;
  const row = only(totals.data);
  const counts = ["users", "new_users_7d", "new_users_30d", "studied_today", "studied_7d"].map(
    (key) => count(field(row, key)),
  );
  const [users, newUsers7d, newUsers30d, studiedToday, studied7d] = counts;
  if (
    users == null ||
    newUsers7d == null ||
    newUsers30d == null ||
    studiedToday == null ||
    studied7d == null
  ) {
    return { failure: "unreadable" };
  }
  return {
    data: {
      users,
      newUsers7d,
      newUsers30d,
      studiedToday,
      studied7d,
    },
  };
}

/** Every reported deck, the latest report first. */
export async function readReportedDecks(): Promise<AdminRead<ReportedDeck[]>> {
  return parsed(await call("admin_reported_decks"), (row) => {
    const id = text(field(row, "deck_id"));
    const name = text(field(row, "name"));
    const owner = parseOwner(row);
    const state = parseState(row);
    const reports = count(field(row, "reports"));
    const reasons = strings(field(row, "reasons"));
    const lastReportedAt = parseTime(field(row, "last_reported_at"));
    if (id === null || name === null || !owner || !state || reports === null || !reasons) {
      return null;
    }
    if (lastReportedAt === null) return null;
    return { id, name, owner, state, reports, reasons, lastReportedAt };
  });
}

/** Every public deck whose name holds [search], or every public deck of [owner]. */
export async function readPublicDecks(
  query: { search: string } | { owner: string },
): Promise<AdminRead<PublicDeck[]>> {
  const args = "owner" in query ? { owner: query.owner } : { search: query.search };
  return parsed(await call("admin_public_decks", args), parsePublicDeck);
}

/** Any deck with its live cards and its removal from sharing, or null for a deck that does not exist. */
export async function readDeck(id: string): Promise<AdminRead<AdminDeck | null>> {
  const [deckRead, cardsRead] = await Promise.all([
    call("admin_user_deck", { deck_id: id }),
    call("admin_user_deck_cards", { deck_id: id }),
  ]);
  if ("failure" in deckRead) return deckRead;
  if ("failure" in cardsRead) return cardsRead;
  if (Array.isArray(deckRead.data) && deckRead.data.length === 0) return { data: null };
  const row = only(deckRead.data);
  const name = text(field(row, "name"));
  const description = field(row, "description");
  const owner = parseOwner(row);
  const state = parseState(row);
  const copies = count(field(row, "copy_count"));
  const reports = count(field(row, "reports"));
  const reasons = strings(field(row, "reasons"));
  const removalReason = field(row, "removal_reason");
  const removedAt = parseTime(field(row, "removed_at"));
  const removal =
    typeof removalReason === "string" && removedAt !== null
      ? { reason: removalReason, removedAt }
      : null;
  if (removalReason !== null && removal === null) return { failure: "unreadable" };
  const cards = rows(cardsRead.data, (cardRow) => {
    const cardId = text(field(cardRow, "card_id"));
    const front = parseContent(field(cardRow, "front"));
    const back = parseContent(field(cardRow, "back"));
    return cardId !== null && front && back
      ? { id: cardId, front: describeContent(front), back: describeContent(back) }
      : null;
  });
  if (name === null || (description !== null && typeof description !== "string")) {
    return { failure: "unreadable" };
  }
  if (!owner || !state || copies === null || reports === null || !reasons || !cards) {
    return { failure: "unreadable" };
  }
  return {
    data: { id, name, description, owner, state, copies, reports, reasons, removal, cards },
  };
}

/** How many users a page of the search holds. */
const userPageSize = 20;

/**
 * The [page]th page of the users whose email holds [query], ignoring case, those it starts first,
 * with the matches in all.
 */
export async function searchUsers(query: string, page: number): Promise<AdminRead<UserPage>> {
  const read = await call("admin_search_users", {
    query,
    page_size: userPageSize,
    page_offset: page * userPageSize,
  });
  if ("failure" in read) return read;
  let total = 0;
  const users = rows(read.data, (row) => {
    const id = text(field(row, "user_id"));
    const email = text(field(row, "email"));
    const createdAt = parseTime(field(row, "created_at"));
    const suspended = field(row, "suspended");
    const matches = count(field(row, "total"));
    if (id === null || email === null || createdAt === null || matches === null) return null;
    if (typeof suspended !== "boolean") return null;
    total = matches;
    return { id, email, createdAt, suspended };
  });
  return users ? { data: { users, total } } : { failure: "unreadable" };
}

/** One user with their public decks, or null when no user has [id]. */
export async function readUser(id: string): Promise<AdminRead<AdminUser | null>> {
  const [userRead, decksRead, planRead, suspensionRead, allDecksRead] = await Promise.all([
    call("admin_user", { user_id: id }),
    readPublicDecks({ owner: id }),
    call("admin_user_plan", { user_id: id }),
    call("admin_user_suspension", { user_id: id }),
    call("admin_user_decks", { user_id: id }),
  ]);
  if ("failure" in userRead) return userRead;
  if ("failure" in decksRead) return decksRead;
  if ("failure" in planRead) return planRead;
  if ("failure" in suspensionRead) return suspensionRead;
  if ("failure" in allDecksRead) return allDecksRead;
  const suspensions = rows(suspensionRead.data, parseSuspension);
  const allDecks = rows(allDecksRead.data, parseUserDeck);
  if (!suspensions || !allDecks) return { failure: "unreadable" };
  if (Array.isArray(userRead.data) && userRead.data.length === 0) return { data: null };
  const plan = parseUserPlan(only(planRead.data));
  if (!plan) return { failure: "unreadable" };
  const row = only(userRead.data);
  const email = text(field(row, "email"));
  const createdAt = parseTime(field(row, "created_at"));
  const lastAnswer = field(row, "last_answer_at");
  const lastAnswerAt = lastAnswer === null ? null : parseTime(lastAnswer);
  const decks = count(field(row, "decks"));
  const cards = count(field(row, "cards"));
  const extractionsToday = count(field(row, "extractions_today"));
  const admin = field(row, "admin");
  if (email === null || createdAt === null || (lastAnswer !== null && lastAnswerAt === null)) {
    return { failure: "unreadable" };
  }
  if (decks === null || cards === null || extractionsToday === null || typeof admin !== "boolean") {
    return { failure: "unreadable" };
  }
  return {
    data: {
      id,
      email,
      createdAt,
      lastAnswerAt,
      decks,
      cards,
      extractionsToday,
      admin,
      publicDecks: decksRead.data,
      plan,
      suspension: suspensions[0] ?? null,
      allDecks,
    },
  };
}

/** The plans and their settings, Free first. */
export async function readPlans(): Promise<AdminRead<PlanSettings[]>> {
  return parsed(await call("admin_plans"), (row) => {
    const id = planId(field(row, "id"));
    const model = text(field(row, "model"));
    const dailyLimit = count(field(row, "daily_limit"));
    const updatedAt = parseTime(field(row, "updated_at"));
    const updatedBy = field(row, "updated_by_email");
    if (id === null || model === null || dailyLimit === null || updatedAt === null) return null;
    if (updatedBy !== null && typeof updatedBy !== "string") return null;
    return { id, model, dailyLimit, updatedAt, updatedByEmail: updatedBy };
  });
}

function parseUserPlan(row: unknown): UserPlan | null {
  const plan = field(row, "plan");
  const model = field(row, "model");
  const dailyLimit = field(row, "daily_limit");
  const granted = field(row, "granted_plan");
  const endsAtValue = field(row, "ends_at");
  const grantedAtValue = field(row, "granted_at");
  const grantedBy = field(row, "granted_by_email");
  // The plan's columns are null together, while its settings are missing.
  const settings =
    plan === null && model === null && dailyLimit === null
      ? { plan: null, model: null, dailyLimit: null }
      : { plan: planId(plan), model: text(model), dailyLimit: count(dailyLimit) };
  if (plan !== null && (settings.plan === null || settings.model === null)) return null;
  if (plan !== null && settings.dailyLimit === null) return null;
  if (granted === null) return { ...settings, grant: null };
  const endsAt = endsAtValue === null ? null : parseTime(endsAtValue);
  const grantedAt = parseTime(grantedAtValue);
  if (granted !== "pro" && granted !== "special") return null;
  if ((endsAtValue !== null && endsAt === null) || grantedAt === null) return null;
  if (grantedBy !== null && typeof grantedBy !== "string") return null;
  return { ...settings, grant: { plan: granted, endsAt, grantedAt, grantedByEmail: grantedBy } };
}

function parseSuspension(row: unknown): Suspension | null {
  const reason = text(field(row, "reason"));
  const suspendedAt = parseTime(field(row, "suspended_at"));
  const by = field(row, "suspended_by_email");
  if (reason === null || suspendedAt === null) return null;
  if (by !== null && typeof by !== "string") return null;
  return { reason, suspendedAt, suspendedByEmail: by };
}

function parseUserDeck(row: unknown): UserDeck | null {
  const id = text(field(row, "deck_id"));
  const name = field(row, "name");
  const visibility = field(row, "visibility");
  const hidden = field(row, "hidden");
  const removed = field(row, "removed");
  const cards = count(field(row, "cards"));
  if (id === null || typeof name !== "string" || cards === null) return null;
  if (visibility !== "public" && visibility !== "private") return null;
  if (typeof hidden !== "boolean" || typeof removed !== "boolean") return null;
  return { id, name, visibility, hidden, removed, cards };
}

function planId(value: unknown): PlanId | null {
  return value === "free" || value === "pro" || value === "special" ? value : null;
}

/** The admins, earliest granted first, the signed-in one marked. */
export async function readAdmins(): Promise<AdminRead<AdminMember[]>> {
  const supabase = await createClient();
  const session = await readUserId(supabase);
  if ("failure" in session) return session;
  return parsed(await call("admin_admins"), (row) => {
    const id = text(field(row, "user_id"));
    const email = text(field(row, "email"));
    const grantedAt = parseTime(field(row, "granted_at"));
    const grantedBy = field(row, "granted_by_email");
    if (id === null || email === null || grantedAt === null) return null;
    if (grantedBy !== null && typeof grantedBy !== "string") return null;
    return { id, email, grantedAt, grantedByEmail: grantedBy, self: id === session.userId };
  });
}

/** The latest 100 entries of the audit log, newest first. */
export async function readAuditLog(): Promise<AdminRead<AuditEntry[]>> {
  return parsed(await call("admin_audit_log"), (row) => {
    const id = count(field(row, "id"));
    const at = parseTime(field(row, "created_at"));
    const adminEmail = field(row, "admin_email");
    const action = text(field(row, "action"));
    const targetKind = text(field(row, "target_kind"));
    const targetId = text(field(row, "target_id"));
    const detail = field(row, "detail");
    if (id === null || at === null || typeof adminEmail !== "string" || action === null) {
      return null;
    }
    if (targetKind === null || targetId === null || !isRecord(detail)) return null;
    return { id, at, adminEmail, action, targetKind, targetId, detail };
  });
}

/** The last 30 UTC days' photos by the plan, model and prompt version that served them (ADR 0074). */
export async function readExtractionBreakdown(): Promise<AdminRead<BreakdownRow[]>> {
  return parsed(await call("admin_extraction_breakdown", { days: 30 }), (row) => {
    const date = field(row, "day");
    const plan = field(row, "plan");
    const model = field(row, "model");
    const version = field(row, "prompt_version_id");
    const photos = count(field(row, "photos"));
    if (typeof date !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(date) || photos === null)
      return null;
    // A photo counted before calls were recorded has none of the three.
    if (plan === null && model === null && version === null) {
      return { day: date, plan: null, model: null, promptVersion: null, photos };
    }
    const id = planId(plan);
    const versionId = count(version);
    if (id === null || typeof model !== "string" || versionId === null) return null;
    return { day: date, plan: id, model, promptVersion: versionId, photos };
  });
}

/** A prompt label: `active` serves every user, `test` the admins (ADR 0073). */
export type PromptLabel = "active" | "test";

/** A saved prompt version, as the prompts page lists it. */
export type PromptVersion = {
  id: number;
  note: string;
  length: number;
  createdByEmail: string | null;
  createdAt: number;
  labels: PromptLabel[];
};

/** One version with its text, and the active version's beside it for the diff. */
export type PromptDetail = PromptVersion & {
  text: string;
  active: { id: number; text: string } | null;
};

/** Every saved prompt version, newest first. */
export async function readPromptVersions(): Promise<AdminRead<PromptVersion[]>> {
  return parsed(await call("admin_prompt_versions"), (row) =>
    parsePromptVersion(row, count(field(row, "length"))),
  );
}

/** Version [id] with its text and the active version's, or null when there is no such version. */
export async function readPromptVersion(id: number): Promise<AdminRead<PromptDetail | null>> {
  const read = parsed(await call("admin_prompt_version", { version_id: id }), (row) => {
    const text = field(row, "text");
    if (typeof text !== "string") return null;
    const version = parsePromptVersion(row, text.length);
    const activeId = field(row, "active_id");
    const activeText = field(row, "active_text");
    if (version === null) return null;
    // Both are null together while no version is active.
    if (activeId === null && activeText === null) return { ...version, text, active: null };
    const active = count(activeId);
    if (active === null || typeof activeText !== "string") return null;
    return { ...version, text, active: { id: active, text: activeText } };
  });
  if ("failure" in read) return read;
  return { data: read.data[0] ?? null };
}

function parsePromptVersion(row: unknown, length: number | null): PromptVersion | null {
  const id = count(field(row, "id"));
  const note = field(row, "note");
  const createdBy = field(row, "created_by_email");
  const createdAt = parseTime(field(row, "created_at"));
  const labels = promptLabels(field(row, "labels"));
  if (id === null || typeof note !== "string" || length === null || createdAt === null) return null;
  if ((createdBy !== null && typeof createdBy !== "string") || labels === null) return null;
  return { id, note, length, createdByEmail: createdBy, createdAt, labels };
}

function promptLabels(value: unknown): PromptLabel[] | null {
  const list = strings(value);
  if (list === null) return null;
  const labels: PromptLabel[] = [];
  for (const label of list) {
    if (label !== "active" && label !== "test") return null;
    labels.push(label);
  }
  return labels;
}

/** Calls the server function [name] with [args] as the signed-in user. */
async function call(
  name: string,
  args?: Record<string, unknown>,
): Promise<{ data: unknown } | { failure: AdminFailure }> {
  const supabase = await createClient();
  const result = await supabase.rpc(name, args).abortSignal(AbortSignal.timeout(requestTimeoutMs));
  if (result.error) return { failure: classifyFailure(result.error, result.status) };
  const data: unknown = result.data;
  return { data };
}

function parsed<T>(
  read: { data: unknown } | { failure: AdminFailure },
  parse: (row: unknown) => T | null,
): AdminRead<T[]> {
  if ("failure" in read) return read;
  const list = rows(read.data, parse);
  return list ? { data: list } : { failure: "unreadable" };
}

function parsePublicDeck(row: unknown): PublicDeck | null {
  const id = text(field(row, "deck_id"));
  const name = text(field(row, "name"));
  const owner = parseOwner(row);
  const hidden = field(row, "hidden");
  const cards = count(field(row, "cards"));
  const copies = count(field(row, "copy_count"));
  const reports = count(field(row, "reports"));
  const published = field(row, "published_at");
  const publishedAt = published === null ? null : parseTime(published);
  if (id === null || name === null || !owner || typeof hidden !== "boolean") return null;
  if (cards === null || copies === null || reports === null) return null;
  if (published !== null && publishedAt === null) return null;
  return { id, name, owner, hidden, cards, copies, reports, publishedAt };
}

function parseOwner(row: unknown): Owner | null {
  const id = text(field(row, "owner_id"));
  const email = field(row, "owner_email");
  const name = field(row, "owner_name");
  if (id === null || typeof email !== "string") return null;
  if (name !== null && typeof name !== "string") return null;
  return { id, email, name };
}

function parseState(row: unknown): DeckState | null {
  const visibility = field(row, "visibility");
  const hidden = field(row, "hidden");
  const deleted = field(row, "deleted");
  if (visibility !== "public" && visibility !== "private") return null;
  if (typeof hidden !== "boolean" || typeof deleted !== "boolean") return null;
  return { visibility, hidden, deleted };
}

/** Each of [value]'s rows parsed by [parse], or null when it is not an array or one does not parse. */
function rows<T>(value: unknown, parse: (row: unknown) => T | null): T[] | null {
  if (!Array.isArray(value)) return null;
  const parsedRows: T[] = [];
  for (const row of value) {
    const one = parse(row);
    if (one === null) return null;
    parsedRows.push(one);
  }
  return parsedRows;
}

/** The one row of a function that returns a table of one row, or undefined. */
function only(value: unknown): unknown {
  return Array.isArray(value) && value.length === 1 ? (value[0] as unknown) : undefined;
}

function text(value: unknown): string | null {
  return typeof value === "string" && value !== "" ? value : null;
}

function strings(value: unknown): string[] | null {
  if (!Array.isArray(value)) return null;
  const list: string[] = [];
  for (const item of value as unknown[]) {
    if (typeof item !== "string") return null;
    list.push(item);
  }
  return list;
}

/** [value] when it is a whole number at least zero, or null. */
function count(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 ? value : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
