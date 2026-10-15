// @vitest-environment node
import { describe, expect, it } from "vitest";

import { supabaseUnreachable } from "@/testing/mocks/handlers";
import { server } from "@/testing/mocks/server";

import { GET } from "../route";

describe("GET /api/health", () => {
  it("answers 200 while Supabase is unreachable, sending it no request", async () => {
    const supabaseRequests: string[] = [];
    server.events.on("request:start", ({ request }) => {
      supabaseRequests.push(request.url);
    });
    server.use(supabaseUnreachable);

    // Awaited, so a handler that waited on Supabase would fail here.
    const response = await Promise.resolve(GET());

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ status: "ok" });
    expect(supabaseRequests).toEqual([]);
    server.events.removeAllListeners();
  });
});
