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
      termsUrl: null,
      privacyUrl: null,
    });
  });

  it("reads each legal link as an https URL, and an empty one as none", () => {
    expect(
      parseEnv({
        ...valid,
        NEXT_PUBLIC_TERMS_URL: "https://example.test/terms",
        NEXT_PUBLIC_PRIVACY_URL: " ",
      }),
    ).toMatchObject({ termsUrl: "https://example.test/terms", privacyUrl: null });
    for (const url of ["example.test/terms", "http://example.test/terms"]) {
      expect(() => parseEnv({ ...valid, NEXT_PUBLIC_TERMS_URL: url })).toThrow(
        "NEXT_PUBLIC_TERMS_URL is not an https URL",
      );
      expect(() => parseEnv({ ...valid, NEXT_PUBLIC_PRIVACY_URL: url })).toThrow(
        "NEXT_PUBLIC_PRIVACY_URL is not an https URL",
      );
    }
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
