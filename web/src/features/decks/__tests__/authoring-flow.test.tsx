import { fireEvent, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { http, HttpResponse } from "msw";
import { render } from "@/testing/render";
import { deckRow, uuidOf } from "@/testing/library";
import { FakePostgrest } from "@/testing/mocks/postgrest";
import { server } from "@/testing/mocks/server";
import { supabaseUrl, testAccessToken } from "@/testing/mocks/handlers";
import { setRequestCookies } from "@/testing/next-headers";
import { signedInCookies } from "@/testing/session";
import { AuthoringButton } from "../components/authoring-button";
import { extractPhoto } from "../extract-photo";
import { readPhoto } from "../read-photo";
import { parseDeckId } from "../library";

vi.mock("next/headers", () => import("@/testing/next-headers"));
vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));
beforeAll(() => {
  HTMLDialogElement.prototype.showModal = function () {
    this.setAttribute("open", "");
  };
  HTMLDialogElement.prototype.close = function () {
    this.removeAttribute("open");
  };
});
let db: FakePostgrest;
beforeEach(async () => {
  db = new FakePostgrest();
  db.seed("decks", deckRow("deck", "단어장"));
  server.use(
    ...db.handlers,
    http.post(`${supabaseUrl}/rest/v1/rpc/extraction_allowance`, () =>
      HttpResponse.json([{ photo_limit: 10, used: 2, period: "month" }]),
    ),
  );
  setRequestCookies(await signedInCookies());
});
const deckId = parseDeckId(uuidOf("deck"));
if (!deckId) throw new Error("fixture deck id");
const deck = { id: deckId, name: "단어장", public: false };

describe("authoring from the page", () => {
  it("closes a pristine draft directly and confirms dirty dismissal without losing a kept draft", async () => {
    await render(() => <AuthoringButton deck={deck} />, {});
    await userEvent.click(screen.getByRole("button", { name: "카드 추가" }));
    await userEvent.click(screen.getByRole("button", { name: "직접 입력" }));
    await userEvent.click(screen.getByRole("button", { name: "닫기" }));
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "카드 추가" }));
    await userEvent.click(screen.getByRole("button", { name: "직접 입력" }));
    await userEvent.type(screen.getByRole("textbox", { name: "앞면 글 1" }), "draft");
    fireEvent(screen.getByRole("dialog"), new Event("cancel", { cancelable: true }));
    expect(screen.getByRole("heading", { name: "작성 중인 카드를 버릴까요?" })).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "계속 쓰기" }));
    expect(screen.getByRole("textbox", { name: "앞면 글 1" })).toHaveValue("draft");
    await userEvent.click(screen.getByRole("button", { name: "닫기" }));
    await userEvent.click(screen.getByRole("button", { name: "버리기" }));
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
    expect(db.rows.cards).toHaveLength(0);
  });

  it("keeps a manual draft after a failed save, then saves meanings and labels once", async () => {
    await render(() => <AuthoringButton deck={deck} />, {});
    await userEvent.click(screen.getByRole("button", { name: "카드 추가" }));
    await userEvent.click(screen.getByRole("button", { name: "직접 입력" }));
    await userEvent.type(screen.getByRole("textbox", { name: "앞면 글 1" }), "apple");
    const groups = screen.getAllByText("+ 추가");
    const back = groups[1];
    if (!back) throw new Error("back add control");
    await userEvent.click(back);
    const options = screen.getAllByRole("button", { name: "뜻 목록" });
    const option = options[1];
    if (!option) throw new Error("back senses option");
    await userEvent.click(option);
    await userEvent.type(screen.getByRole("textbox", { name: "뜻 1" }), "사과");
    await userEvent.type(screen.getByRole("textbox", { name: "뜻 1 라벨" }), "명");
    const release = db.fail("cards", 400);
    await userEvent.click(screen.getByRole("button", { name: "저장" }));
    expect(await screen.findByRole("alert")).toHaveTextContent("카드를 저장하지 못했어요");
    expect(screen.getByRole("textbox", { name: "앞면 글 1" })).toHaveValue("apple");
    release();
    await userEvent.dblClick(screen.getByRole("button", { name: "저장" }));
    await waitFor(() => {
      expect(db.rows.cards).toHaveLength(1);
    });
    expect(db.rows.cards[0]?.back).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          type: "senses",
          payload: {
            senses: [
              {
                labels: [{ kind: "part_of_speech", category: "noun", text: "명" }],
                meaning: "사과",
                examples: [],
              },
            ],
          },
        }),
      ]),
    );
  });
  it("keeps the picker usable after cancellation, shows the allowance before reading, and closes without writes", async () => {
    await render(() => <AuthoringButton deck={deck} />, {});
    const trigger = screen.getByRole("button", { name: "카드 추가" });
    await userEvent.click(trigger);
    await userEvent.click(screen.getByRole("button", { name: "앨범에서 고르기" }));
    expect(await screen.findByText("이번 달 8장 남음 · 10장 중")).toBeInTheDocument();
    const picker = screen.getByLabelText("앨범에서 고르기", { selector: "input" });
    fireEvent.change(picker, { target: { files: [] } });
    expect(screen.queryByRole("button", { name: "사진 읽기" })).not.toBeInTheDocument();
    expect(picker).toBeEnabled();
    fireEvent(screen.getByRole("dialog"), new Event("cancel", { cancelable: true }));
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
    expect(db.rows.cards).toHaveLength(0);
  });
});

describe("photo request refusals", () => {
  it("refuses empty, oversized and signed-out uploads before calling extraction beside a valid authenticated upload", async () => {
    let calls = 0;
    server.use(
      http.post(`${supabaseUrl}/functions/v1/extract-cards`, async ({ request }) => {
        calls += 1;
        expect(request.headers.get("authorization")).toBe(`Bearer ${testAccessToken}`);
        const body: unknown = await request.json();
        expect(body).toEqual({ image: Buffer.from([255, 216, 255, 0]).toString("base64") });
        return HttpResponse.json({
          cards: [{ kind: "note", type: "concept", front: "수도", answer: "서울", topic: "도시" }],
        });
      }),
    );
    expect(await readPhoto(new FormData())).toHaveProperty("message");
    const large = new FormData();
    large.set("photo", new File([new Uint8Array(3 * 1024 * 1024 + 1)], "large.jpg"));
    expect(await readPhoto(large)).toHaveProperty("message");
    expect(calls).toBe(0);
    const valid = new FormData();
    valid.set("photo", photo());
    expect(await readPhoto(valid)).toHaveProperty("cards");
    expect(calls).toBe(1);
    setRequestCookies([]);
    expect(await readPhoto(valid)).toHaveProperty("message", "다시 로그인해 주세요");
    expect(calls).toBe(1);
  });

  const photo = () => {
    const file = new File([new Uint8Array([255, 216, 255, 0])], "photo.jpg", {
      type: "image/jpeg",
    });
    Object.defineProperty(file, "arrayBuffer", {
      value: () => Promise.resolve(new Uint8Array([255, 216, 255, 0]).buffer),
    });
    return file;
  };
  it("sends the current session and handles candidates and quota refusal beside the accepted response", async () => {
    server.use(
      http.post(`${supabaseUrl}/functions/v1/extract-cards`, ({ request }) => {
        expect(request.headers.get("authorization")).toBe(`Bearer ${testAccessToken}`);
        return HttpResponse.json({
          cards: [{ kind: "note", type: "concept", front: "수도", answer: "서울", topic: "도시" }],
        });
      }),
    );
    expect(await extractPhoto(photo(), new AbortController().signal)).toMatchObject({
      cards: [{ topic: "도시", selected: true }],
    });
    server.use(
      http.post(`${supabaseUrl}/functions/v1/extract-cards`, () =>
        HttpResponse.json(
          { error: "rate_limited", photo_limit: 10, period: "month" },
          { status: 429 },
        ),
      ),
    );
    expect(await extractPhoto(photo(), new AbortController().signal)).toHaveProperty(
      "message",
      expect.stringContaining("이번 달 사진 10장"),
    );
    server.use(
      http.post(`${supabaseUrl}/functions/v1/extract-cards`, () =>
        HttpResponse.json({ error: "no_cards" }, { status: 422 }),
      ),
    );
    expect(await extractPhoto(photo(), new AbortController().signal)).toHaveProperty(
      "message",
      expect.stringContaining("글자가 선명한 사진"),
    );
  });
});
