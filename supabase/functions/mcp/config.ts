/** The function's configuration, read once from the environment. */

export type Config =
  | {
    readonly kind: "configured";
    readonly supabaseUrl: string;
    /** The anon key: every request carries the caller's token, so row-level security applies. */
    readonly anonKey: string;
  }
  | { readonly kind: "not_configured" };

/** Reads `SUPABASE_URL` and `SUPABASE_ANON_KEY`, which the platform sets. */
export function readConfig(env: (name: string) => string | undefined): Config {
  const value = (name: string) => {
    const raw = env(name)?.trim();
    return raw === undefined || raw === "" ? null : raw;
  };
  const supabaseUrl = value("SUPABASE_URL");
  const anonKey = value("SUPABASE_ANON_KEY");
  if (supabaseUrl === null || anonKey === null) {
    return { kind: "not_configured" };
  }
  return { kind: "configured", supabaseUrl, anonKey };
}
