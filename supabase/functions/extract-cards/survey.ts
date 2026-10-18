/** The survey of a page a model returns before any card is made, its JSON schema, and its parser. */

import {
  type CardKind,
  KINDS,
  MAX_ANSWER_CHARS,
  MAX_FIELD_CHARS,
} from "./cards.ts";
import { MAX_GROUP_ID_CHARS, MAX_TITLE_CHARS } from "./request.ts";

export const MAX_SUMMARY_CHARS = 200;
export const MAX_GROUPS = 12;
export const MAX_SAMPLE_CHARS = 100;
export const MAX_COUNT = 100;

/**
 * A group of the page's items: what it is, how many items it holds, whether it is worth
 * memorising, one item as the page writes it, and one item as a card's question and answer.
 */
export type Group = {
  readonly id: string;
  readonly kind: CardKind;
  readonly title: string;
  readonly count: number;
  readonly memorise: boolean;
  readonly sample: string;
  readonly example: { readonly question: string; readonly answer: string };
};

/** A page described in a line, and its groups. */
export type Survey = {
  readonly summary: string;
  readonly groups: readonly Group[];
};

const field = (maxLength: number) => ({
  type: "string",
  minLength: 1,
  maxLength,
} as const);

/** The structured-output schema sent to the model; `parseSurvey` enforces the same limits. */
export const surveySchema = {
  type: "object",
  properties: {
    summary: field(MAX_SUMMARY_CHARS),
    groups: {
      type: "array",
      maxItems: MAX_GROUPS,
      items: {
        type: "object",
        properties: {
          id: field(MAX_GROUP_ID_CHARS),
          kind: { type: "string", enum: [...KINDS] },
          title: field(MAX_TITLE_CHARS),
          count: { type: "integer", minimum: 1, maximum: MAX_COUNT },
          memorise: { type: "boolean" },
          sample: field(MAX_SAMPLE_CHARS),
          example: {
            type: "object",
            properties: {
              question: field(MAX_FIELD_CHARS),
              answer: field(MAX_ANSWER_CHARS),
            },
            required: ["question", "answer"],
            additionalProperties: false,
          },
        },
        required: [
          "id",
          "kind",
          "title",
          "count",
          "memorise",
          "sample",
          "example",
        ],
        additionalProperties: false,
      },
    },
  },
  required: ["summary", "groups"],
  additionalProperties: false,
} as const;

/**
 * Parses a model's reply into a survey, or returns null when it is not JSON matching
 * `surveySchema` once each field is trimmed, or two groups share an id. Lengths count code
 * points, as JSON Schema does.
 */
export function parseSurvey(reply: string): Survey | null {
  let value: unknown;
  try {
    value = JSON.parse(reply);
  } catch {
    return null;
  }
  if (!isRecord(value) || !hasOnlyKeys(value, ["summary", "groups"])) {
    return null;
  }
  const summary = text(value.summary, MAX_SUMMARY_CHARS);
  if (
    summary === null || !Array.isArray(value.groups) ||
    value.groups.length > MAX_GROUPS
  ) return null;
  const groups: Group[] = [];
  for (const item of value.groups) {
    const group = parseGroup(item);
    if (group === null || groups.some((other) => other.id === group.id)) {
      return null;
    }
    groups.push(group);
  }
  return { summary, groups };
}

function parseGroup(item: unknown): Group | null {
  if (
    !isRecord(item) ||
    !hasOnlyKeys(item, [
      "id",
      "kind",
      "title",
      "count",
      "memorise",
      "sample",
      "example",
    ]) ||
    !isRecord(item.example) ||
    !hasOnlyKeys(item.example, ["question", "answer"])
  ) return null;
  const kind = KINDS.find((known) => known === item.kind);
  const id = text(item.id, MAX_GROUP_ID_CHARS);
  const title = text(item.title, MAX_TITLE_CHARS);
  const sample = text(item.sample, MAX_SAMPLE_CHARS);
  const question = text(item.example.question, MAX_FIELD_CHARS);
  const answer = text(item.example.answer, MAX_ANSWER_CHARS);
  const count = item.count;
  if (
    kind === undefined || id === null || title === null || sample === null ||
    question === null || answer === null ||
    typeof item.memorise !== "boolean" ||
    typeof count !== "number" || !Number.isInteger(count) || count < 1 ||
    count > MAX_COUNT
  ) return null;
  return {
    id,
    kind,
    title,
    count,
    memorise: item.memorise,
    sample,
    example: { question, answer },
  };
}

function text(value: unknown, max: number): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  const length = [...trimmed].length;
  return length >= 1 && length <= max ? trimmed : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasOnlyKeys(
  record: Record<string, unknown>,
  keys: readonly string[],
): boolean {
  const present = Object.keys(record);
  return present.length === keys.length &&
    keys.every((key) => Object.hasOwn(record, key));
}
