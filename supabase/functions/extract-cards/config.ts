/** The function's configuration, read once from the environment. */

import { type ModelId, modelId, type Models } from "./openrouter.ts";

export type Config =
  | {
    readonly kind: "configured";
    readonly supabaseUrl: string;
    readonly serviceRoleKey: string;
    readonly openRouterApiKey: string;
    readonly models: Models;
    /** The survey's model: `SURVEY_MODEL`, else `CARD_MODEL`. */
    readonly surveyModel: ModelId;
    /** The model cards are made on for a page of vocabulary alone: `VOCAB_MODEL`, else `CARD_MODEL`. */
    readonly vocabularyModel: ModelId;
  }
  | { readonly kind: "not_configured" };

/**
 * Reads `CARD_MODEL`, and `CARD_RETRY_MODEL` when set, else the same model, for the retry on
 * invalid output; `SURVEY_MODEL` and `VOCAB_MODEL` when set, else `CARD_MODEL`. A model set to
 * a malformed ID leaves the function unconfigured. `SUPABASE_URL` and
 * `SUPABASE_SERVICE_ROLE_KEY` are set by the platform.
 */
export function readConfig(env: (name: string) => string | undefined): Config {
  const value = (name: string) => {
    const raw = env(name)?.trim();
    return raw === undefined || raw === "" ? null : raw;
  };
  const supabaseUrl = value("SUPABASE_URL");
  const serviceRoleKey = value("SUPABASE_SERVICE_ROLE_KEY");
  const openRouterApiKey = value("OPENROUTER_API_KEY");
  const primary = model(value("CARD_MODEL"));
  const retryName = value("CARD_RETRY_MODEL");
  const retry = retryName === null ? primary : model(retryName);
  const orPrimary = (name: string | null) =>
    name === null ? primary : model(name);
  const surveyModel = orPrimary(value("SURVEY_MODEL"));
  const vocabularyModel = orPrimary(value("VOCAB_MODEL"));

  if (
    supabaseUrl === null || serviceRoleKey === null ||
    openRouterApiKey === null || primary === null ||
    retry === null || surveyModel === null || vocabularyModel === null
  ) {
    return { kind: "not_configured" };
  }
  return {
    kind: "configured",
    supabaseUrl,
    serviceRoleKey,
    openRouterApiKey,
    models: { primary, retry },
    surveyModel,
    vocabularyModel,
  };
}

function model(name: string | null): ModelId | null {
  return name === null ? null : modelId(name);
}
