import { describe, expect, it } from "vitest";

import { EnvError, parseEnv } from "../env";

const valid = {
  NEXT_PUBLIC_SUPABASE_URL: "https://project.supabase.co",
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: "sb_publishable_abc",
};

describe("parseEnv", () => {
  it("returns the URL and the publishable key", () => {
    expect(parseEnv(valid)).toEqual({
      supabaseUrl: "https://project.supabase.co",
      supabasePublishableKey: "sb_publishable_abc",
    });
  });

  it("rejects a missing or non-http URL", () => {
    for (const url of [undefined, "", "project.supabase.co", "ftp://project.supabase.co"]) {
      expect(() => parseEnv({ ...valid, NEXT_PUBLIC_SUPABASE_URL: url })).toThrow(EnvError);
    }
  });

  it("rejects a key that is not a publishable key", () => {
    for (const key of [undefined, "", "sb_secret_abc", "eyJhbGciOiJIUzI1NiJ9.e30.x"]) {
      expect(() => parseEnv({ ...valid, NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: key })).toThrow(
        "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY is not a Supabase publishable key",
      );
    }
  });
});
