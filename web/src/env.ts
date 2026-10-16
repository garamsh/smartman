/** The app's configuration, parsed once from the environment at module load. */
export type Env = {
  supabaseUrl: string;
  supabasePublishableKey: string;
};

/** Thrown when a variable is missing or malformed; names the variable, never its value. */
export class EnvError extends Error {
  override name = "EnvError";
}

/**
 * Parses the variables the app reads. The key must be a publishable key: a secret or
 * service-role key never belongs in a `NEXT_PUBLIC_` variable, which reaches the browser.
 */
export function parseEnv(source: {
  NEXT_PUBLIC_SUPABASE_URL: string | undefined;
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: string | undefined;
}): Env {
  const url = source.NEXT_PUBLIC_SUPABASE_URL ?? "";
  if (!/^https?:$/.test(protocolOf(url))) {
    throw new EnvError("NEXT_PUBLIC_SUPABASE_URL is not an http(s) URL");
  }
  const key = source.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if (!key?.startsWith("sb_publishable_")) {
    throw new EnvError("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY is not a Supabase publishable key");
  }
  return { supabaseUrl: url, supabasePublishableKey: key };
}

/** The protocol of [value] as a URL, or "" when it is none; `URL.canParse` is missing in Safari 16. */
function protocolOf(value: string): string {
  try {
    return new URL(value).protocol;
  } catch {
    return "";
  }
}

// Each variable is named in full so `next build` inlines it into the client bundle.
export const env = parseEnv({
  NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
});
