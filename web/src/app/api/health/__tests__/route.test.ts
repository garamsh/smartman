// @vitest-environment node
import { http, HttpResponse } from "msw";
import { describe, expect, it } from "vitest";

import { server } from "@/testing/mocks/server";

import { GET } from "../route";

describe("GET /api/health", () => {
  it("answers 200 without a request to Supabase", async () => {
    let supabaseRequests = 0;
    server.use(
      http.all("http://supabase.test/*", () => {
        supabaseRequests += 1;
        return HttpResponse.error();
      }),
    );

    const response = GET();

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ status: "ok" });
    expect(supabaseRequests).toBe(0);
  });
});
