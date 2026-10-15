import { createServerClient } from "@supabase/ssr";

import { supabaseUrl, testAccessToken } from "./mocks/handlers";

type Cookie = { name: string; value: string };

/** A Supabase client over a cookie jar of its own, and the jar. */
function jarClient() {
  const jar = new Map<string, string>();
  const client = createServerClient(supabaseUrl, "sb_publishable_test", {
    cookies: {
      getAll: () => [...jar].map(([name, value]) => ({ name, value })),
      setAll: (cookies) => {
        for (const { name, value } of cookies) {
          if (value === "") jar.delete(name);
          else jar.set(name, value);
        }
      },
    },
  });
  const cookies = (): Cookie[] => {
    if (jar.size === 0) throw new Error("@supabase/ssr wrote no cookie");
    return [...jar].map(([name, value]) => ({ name, value }));
  };
  return { client, cookies };
}

/**
 * The cookies a browser holds after [testUser] signed in, written by @supabase/ssr itself
 * so the tests read the format the app reads.
 */
export async function signedInCookies(): Promise<Cookie[]> {
  const { client, cookies } = jarClient();
  const { error } = await client.auth.setSession({
    access_token: testAccessToken,
    refresh_token: "refresh-token",
  });
  if (error) throw error;
  return cookies();
}

/** The cookies a browser holds after starting Google sign-in: the PKCE code verifier. */
export async function signInStartedCookies(): Promise<Cookie[]> {
  const { client, cookies } = jarClient();
  const { error } = await client.auth.signInWithOAuth({
    provider: "google",
    options: { redirectTo: "http://localhost:3000/auth/callback", skipBrowserRedirect: true },
  });
  if (error) throw error;
  return cookies();
}
