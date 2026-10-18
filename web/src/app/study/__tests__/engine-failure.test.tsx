import { screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { seedDeck, start } from "@/testing/library";
import { FakePostgrest } from "@/testing/mocks/postgrest";
import { server } from "@/testing/mocks/server";
import { setRequestCookies } from "@/testing/next-headers";
import { render } from "@/testing/render";
import { signedInCookies } from "@/testing/session";

import { Study } from "../_components/study";

vi.mock("next/headers", () => import("@/testing/next-headers"));
// The server's engine module fails to load.
vi.mock("@/features/study/engine-server", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/features/study/engine-server")>()),
  readyServerEngine: () => Promise.resolve({ failure: "failed" }),
}));

describe("the study page", () => {
  beforeEach(async () => {
    vi.setSystemTime(start);
    setRequestCookies(await signedInCookies());
  });

  it("shows its own failure message when the server's engine cannot load", async () => {
    const postgrest = new FakePostgrest();
    server.use(...postgrest.handlers);
    seedDeck(postgrest, "d1", ["un"]);
    await render(Study, { searchParams: Promise.resolve({ decks: "d1" }) });

    expect(screen.getByRole("alert")).toHaveTextContent(
      "카드를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.",
    );
    expect(screen.queryByRole("group", { name: "문제" })).not.toBeInTheDocument();
  });
});
