/** The function's configuration, read once from the environment. */

export type Config =
  | {
    readonly kind: "configured";
    readonly supabaseUrl: string;
    /** `SUPABASE_URL`'s origin: the project's own host, where Auth's issuer is (ADR 0133). */
    readonly projectOrigin: string;
    /** The function's public URL, which the 401 and the metadata name as the resource (ADR 0133). */
    readonly resourceUrl: string;
    /** The anon key: every request carries the caller's token, so row-level security applies. */
    readonly anonKey: string;
  }
  | { readonly kind: "not_configured" };

/** The path the platform's gateway serves the function under, which it strips before calling it. */
const FUNCTION_PATH = "/functions/v1/mcp";

/**
 * Reads `SUPABASE_URL`, an http(s) URL, and `SUPABASE_ANON_KEY`, which the platform sets, and the
 * optional `MCP_PUBLIC_URL`, an https URL ending in the function's path. A value set but invalid
 * leaves the function unconfigured.
 */
export function readConfig(env: (name: string) => string | undefined): Config {
  const value = (name: string) => {
    const raw = env(name)?.trim();
    return raw === undefined || raw === "" ? null : raw;
  };
  const supabaseUrl = value("SUPABASE_URL");
  const anonKey = value("SUPABASE_ANON_KEY");
  const publicUrl = value("MCP_PUBLIC_URL");
  const parsedPublic = publicUrl === null ? null : URL.parse(publicUrl);
  if (
    publicUrl !== null &&
    (parsedPublic === null || parsedPublic.protocol !== "https:" ||
      !parsedPublic.pathname.endsWith(FUNCTION_PATH) ||
      parsedPublic.search !== "" || parsedPublic.hash !== "")
  ) {
    return { kind: "not_configured" };
  }
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
    resourceUrl: parsedPublic === null
      ? `${parsed.origin}${FUNCTION_PATH}`
      : `${parsedPublic.origin}${parsedPublic.pathname}`,
    anonKey,
  };
}
