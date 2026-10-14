/** The function's configuration, read once from the environment. */

import { type ModelId, modelId, type Models } from "./openrouter.ts";

export type Config =
  | {
    readonly kind: "configured";
    readonly supabaseUrl: string;
    readonly serviceRoleKey: string;
    readonly openRouterApiKey: string;
    readonly models: Models;
  }
  | { readonly kind: "not_configured" };

/**
 * Reads `CARD_MODEL`, and `CARD_RETRY_MODEL` when set, else the same model, for the retry on
 * invalid output. `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are set by the platform.
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

  if (
    supabaseUrl === null || serviceRoleKey === null ||
    openRouterApiKey === null || primary === null ||
    retry === null
  ) {
    return { kind: "not_configured" };
  }
  return {
    kind: "configured",
    supabaseUrl,
    serviceRoleKey,
    openRouterApiKey,
    models: { primary, retry },
  };
}

function model(name: string | null): ModelId | null {
  return name === null ? null : modelId(name);
}
