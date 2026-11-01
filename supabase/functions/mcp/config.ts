/** The function's configuration, read once from the environment. */

export type Config =
  | {
    readonly kind: "configured";
    readonly supabaseUrl: string;
    /** `SUPABASE_URL`'s origin: the project's own host, where Auth's issuer is (ADR 0133). */
    readonly projectOrigin: string;
    /** The anon key: every request carries the caller's token, so row-level security applies. */
    readonly anonKey: string;
  }
  | { readonly kind: "not_configured" };

/** Reads `SUPABASE_URL`, an http(s) URL, and `SUPABASE_ANON_KEY`, which the platform sets. */
export function readConfig(env: (name: string) => string | undefined): Config {
  const value = (name: string) => {
    const raw = env(name)?.trim();
    return raw === undefined || raw === "" ? null : raw;
  };
  const supabaseUrl = value("SUPABASE_URL");
  const anonKey = value("SUPABASE_ANON_KEY");
  const parsed = supabaseUrl === null ? null : URL.parse(supabaseUrl);
  if (
    supabaseUrl === null || anonKey === null || parsed === null ||
    (parsed.protocol !== "https:" && parsed.protocol !== "http:")
  ) {
    return { kind: "not_configured" };
  }
  return {
    kind: "configured",
    supabaseUrl,
    projectOrigin: parsed.origin,
    anonKey,
  };
}
