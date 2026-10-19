/** The function's configuration, read once from the environment. */

export type Config =
  | {
    readonly kind: "configured";
    readonly supabaseUrl: string;
    readonly serviceRoleKey: string;
    readonly openRouterApiKey: string;
  }
  | { readonly kind: "not_configured" };

/**
 * Reads `OPENROUTER_API_KEY`; `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are set by the
 * platform. The model and the daily limit are the caller's plan's, read from the database at
 * each call (`supabase.ts`).
 */
export function readConfig(env: (name: string) => string | undefined): Config {
  const value = (name: string) => {
    const raw = env(name)?.trim();
    return raw === undefined || raw === "" ? null : raw;
  };
  const supabaseUrl = value("SUPABASE_URL");
  const serviceRoleKey = value("SUPABASE_SERVICE_ROLE_KEY");
  const openRouterApiKey = value("OPENROUTER_API_KEY");
  if (
    supabaseUrl === null || serviceRoleKey === null || openRouterApiKey === null
  ) {
    return { kind: "not_configured" };
  }
  return { kind: "configured", supabaseUrl, serviceRoleKey, openRouterApiKey };
}
