import { fireEvent, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { http, HttpResponse } from "msw";
import { render } from "@/testing/render";
import { deckRow, uuidOf } from "@/testing/library";
import { FakePostgrest } from "@/testing/mocks/postgrest";
import { server } from "@/testing/mocks/server";
import { supabaseUrl, testAccessToken } from "@/testing/mocks/handlers";
import { setRequestCookies } from "@/testing/next-headers";
import { signedInCookies } from "@/testing/session";
import { AuthoringButton } from "../components/authoring-button";
import { preparePhoto } from "../extract-photo";
import { describeFailure } from "../photo-failure";
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
  it("opens nothing when the picker is cancelled, and keeps the choices usable", async () => {
    await render(() => <AuthoringButton deck={deck} />, {});
    await userEvent.click(screen.getByRole("button", { name: "카드 추가" }));
    const picker = screen.getByLabelText("앨범에서 고르기", { selector: "input" });
    fireEvent.change(picker, { target: { files: [] } });
    expect(screen.getByRole("heading", { name: "카드 추가" })).toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: "카드를 찾고 있어요" })).not.toBeInTheDocument();
    expect(picker).toBeEnabled();
    fireEvent(screen.getByRole("dialog"), new Event("cancel", { cancelable: true }));
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
    expect(db.rows.cards).toHaveLength(0);
  });
});

/** A JPEG's first bytes, which `readPhoto` reads as its type. */
const jpegBytes = [255, 216, 255, 0];
function upload() {
  const file = new File([new Uint8Array(jpegBytes)], "photo.jpg", { type: "image/jpeg" });
  Object.defineProperty(file, "arrayBuffer", {
    value: () => Promise.resolve(new Uint8Array(jpegBytes).buffer),
  });
  return file;
}
const card = { kind: "note", type: "concept", front: "수도", answer: "서울", topic: "도시" };

/** jsdom decodes and draws nothing: the browser's decoder and canvas, as far as preparation uses them. */
function stubBrowserImages({
  width = 1200,
  height = 900,
  decodes = true,
  sizes = [] as number[],
} = {}) {
  const drawn: { width: number; height: number }[] = [];
  const qualities: number[] = [];
  vi.stubGlobal(
    "createImageBitmap",
    vi.fn((_: Blob, options?: ImageBitmapOptions) =>
      decodes
        ? Promise.resolve({ width, height, close: vi.fn(), options })
        : Promise.reject(new DOMException("unsupported", "InvalidStateError")),
    ),
  );
  vi.spyOn(HTMLCanvasElement.prototype, "getContext").mockImplementation(function (
    this: HTMLCanvasElement,
  ) {
    return {
      fillStyle: "",
      fillRect: vi.fn(),
      drawImage: () => {
        drawn.push({ width: this.width, height: this.height });
      },
    } as unknown as CanvasRenderingContext2D;
  });
  vi.spyOn(HTMLCanvasElement.prototype, "toBlob").mockImplementation(
    (callback: BlobCallback, type?: string, quality?: number) => {
      qualities.push(quality ?? 1);
      const size = sizes[qualities.length - 1] ?? 1000;
      const bytes = new Uint8Array(size);
      bytes.set(jpegBytes);
      const blob = new Blob([bytes], { type });
      Object.defineProperty(blob, "arrayBuffer", {
        value: () => Promise.resolve(bytes.buffer),
      });
      callback(blob);
    },
  );
  return { drawn, qualities };
}
afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe("photo preparation", () => {
  it("scales a large photo to 2048 px on its long side and asks the decoder for its EXIF orientation", async () => {
    const { drawn } = stubBrowserImages({ width: 4000, height: 3000 });
    const prepared = await preparePhoto(new File([new Uint8Array(8 * 1024 * 1024)], "big.jpg"));
    expect(prepared).toBeInstanceOf(File);
    expect(prepared).toHaveProperty("type", "image/jpeg");
    expect(drawn).toEqual([{ width: 2048, height: 1536 }]);
    expect(vi.mocked(createImageBitmap).mock.calls[0]?.[1]).toEqual({
      imageOrientation: "from-image",
    });
  });
  it("re-encodes a small PNG as JPEG at its own size, rather than sending it as it is", async () => {
    const { drawn } = stubBrowserImages({ width: 800, height: 600 });
    const png = new File([new Uint8Array([137, 80, 78, 71])], "small.png", { type: "image/png" });
    const prepared = await preparePhoto(png);
    expect(prepared).not.toBe(png);
    expect(prepared).toHaveProperty("type", "image/jpeg");
    expect(drawn).toEqual([{ width: 800, height: 600 }]);
  });
  it("lowers the quality until the photo is under the upload bound, and refuses one that never is", async () => {
    const over = 3 * 1024 * 1024 + 1;
    const fits = stubBrowserImages({ sizes: [over, over, 1000] });
    expect(await preparePhoto(new Blob())).toBeInstanceOf(File);
    expect(fits.qualities).toEqual([0.85, 0.7, 0.55]);
    vi.restoreAllMocks();
    stubBrowserImages({ sizes: [over, over, over, over] });
    expect(await preparePhoto(new Blob())).toEqual({ kind: "refused" });
  });
  it("names the formats to choose for a photo the browser cannot decode", async () => {
    stubBrowserImages({ decodes: false });
    const failure = await preparePhoto(new File([new Uint8Array(4)], "photo.heic"));
    expect(failure).toEqual({ kind: "unreadable" });
    if (!("kind" in failure)) throw new Error("decoded");
    expect(describeFailure(failure)).toBe(
      "이 사진을 읽을 수 없어요. JPEG, PNG, WebP 사진을 골라 주세요.",
    );
  });
});

describe("photo request", () => {
  it("refuses empty, oversized and signed-out uploads before calling extraction beside a valid authenticated upload", async () => {
    let calls = 0;
    server.use(
      http.post(`${supabaseUrl}/functions/v1/extract-cards`, async ({ request }) => {
        calls += 1;
        expect(request.headers.get("authorization")).toBe(`Bearer ${testAccessToken}`);
        const body: unknown = await request.json();
        expect(body).toEqual({ image: Buffer.from(jpegBytes).toString("base64") });
        return HttpResponse.json({ cards: [card] });
      }),
    );
    expect(await readPhoto(new FormData())).toEqual({ failure: { kind: "refused" } });
    const large = new FormData();
    large.set("photo", new File([new Uint8Array(3 * 1024 * 1024 + 1)], "large.jpg"));
    expect(await readPhoto(large)).toEqual({ failure: { kind: "refused" } });
    expect(calls).toBe(0);
    const valid = new FormData();
    valid.set("photo", upload());
    expect(await readPhoto(valid)).toMatchObject({ cards: [{ topic: "도시", selected: true }] });
    expect(calls).toBe(1);
    setRequestCookies([]);
    expect(await readPhoto(valid)).toEqual({ failure: { kind: "signIn" } });
    expect(calls).toBe(1);
  });
  it.each([
    [502, {}, { kind: "model" }],
    [503, {}, { kind: "service" }],
    [403, { error: "suspended" }, { kind: "suspended" }],
    [403, { error: "forbidden" }, { kind: "service" }],
    [413, {}, { kind: "refused" }],
    [415, {}, { kind: "refused" }],
    [422, { error: "no_cards" }, { kind: "noCards" }],
    [429, { photo_limit: 10, period: "month" }, { kind: "limit", limit: 10, period: "month" }],
    [429, {}, { kind: "service" }],
    [401, {}, { kind: "signIn" }],
    [200, { cards: [] }, { kind: "service" }],
  ])(
    "reads a %i answer as the phone's failure kind, sending the photo once",
    async (status, body, failure) => {
      let calls = 0;
      server.use(
        http.post(`${supabaseUrl}/functions/v1/extract-cards`, () => {
          calls += 1;
          return HttpResponse.json(body, { status });
        }),
      );
      const form = new FormData();
      form.set("photo", upload());
      expect(await readPhoto(form)).toEqual({ failure });
      expect(calls).toBe(1);
    },
  );
  it("sends a photo once more after no response, and logs one line with the status and latency, never the image or token", async () => {
    const log = vi.spyOn(console, "info").mockImplementation(() => undefined);
    let calls = 0;
    server.use(
      http.post(`${supabaseUrl}/functions/v1/extract-cards`, () => {
        calls += 1;
        return calls === 1 ? HttpResponse.error() : HttpResponse.json({ cards: [card] });
      }),
    );
    const form = new FormData();
    form.set("photo", upload());
    expect(await readPhoto(form)).toHaveProperty("cards");
    expect(calls).toBe(2);
    expect(log).toHaveBeenCalledTimes(1);
    const line = String(log.mock.calls[0]?.[0]);
    expect(JSON.parse(line)).toMatchObject({
      event: "read_photo",
      status: 200,
      attempts: 2,
      outcome: "cards",
      cards: 1,
      ms: expect.any(Number) as unknown,
    });
    expect(line).not.toContain(testAccessToken);
    expect(line).not.toContain(Buffer.from(jpegBytes).toString("base64"));
  });
  it("gives up after a second request with no response, as a service failure to retry", async () => {
    vi.spyOn(console, "info").mockImplementation(() => undefined);
    let calls = 0;
    server.use(
      http.post(`${supabaseUrl}/functions/v1/extract-cards`, () => {
        calls += 1;
        return HttpResponse.error();
      }),
    );
    const form = new FormData();
    form.set("photo", upload());
    expect(await readPhoto(form)).toEqual({ failure: { kind: "service" } });
    expect(calls).toBe(2);
  });
});

describe("photo import", () => {
  beforeEach(() => {
    stubBrowserImages();
    vi.spyOn(console, "info").mockImplementation(() => undefined);
    URL.createObjectURL = () => "blob:photo";
    URL.revokeObjectURL = () => undefined;
  });
  async function choose(count: number) {
    await render(() => <AuthoringButton deck={deck} />, {});
    await userEvent.click(screen.getByRole("button", { name: "카드 추가" }));
    const picker = screen.getByLabelText("앨범에서 고르기", { selector: "input" });
    fireEvent.change(picker, {
      target: {
        files: Array.from({ length: count }, (_, at) => new File([], `${String(at)}.jpg`)),
      },
    });
  }
  /** The function's answers in turn, counting the photos sent. */
  function answer(...answers: { status: number; body: Record<string, unknown> }[]) {
    const sent = { count: 0 };
    server.use(
      http.post(`${supabaseUrl}/functions/v1/extract-cards`, () => {
        const next = answers[Math.min(sent.count, answers.length - 1)];
        sent.count += 1;
        return HttpResponse.json(next?.body, { status: next?.status });
      }),
    );
    return sent;
  }
  const failed502 = { status: 502, body: { error: "model_error" } };
  const read = { status: 200, body: { cards: [card] } };

  it("shows one photo's 502 as the phone's model failure, and its retry sends that photo again into the list", async () => {
    const sent = answer(failed502, read);
    await choose(1);
    expect(
      await screen.findByText("카드를 읽지 못했어요. 잠시 후 다시 시도해 주세요."),
    ).toBeInTheDocument();
    expect(sent.count).toBe(1);
    await userEvent.click(screen.getByRole("button", { name: "다시 시도" }));
    expect(
      await screen.findByRole("heading", { name: "카드 1장을 만들었어요" }),
    ).toBeInTheDocument();
    expect(sent.count).toBe(2);
    expect(screen.getByRole("heading", { name: "도시 1" })).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "카드 1장 추가" }));
    await waitFor(() => {
      expect(db.rows.cards).toHaveLength(1);
    });
  });
  it("offers no retry for a failure sending again cannot fix, against the retake it does offer", async () => {
    answer({ status: 422, body: { error: "no_cards" } });
    await choose(1);
    expect(
      await screen.findByText("카드를 찾지 못했어요. 더 밝고 반듯하게 찍어 보세요."),
    ).toBeInTheDocument();
    expect(screen.getByLabelText("다른 사진 고르기", { selector: "input" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "다시 시도" })).not.toBeInTheDocument();
  });
  it("reads several photos with a row each, retries only the failed one in place, then opens the list", async () => {
    const sent = answer(failed502, read, read);
    await choose(2);
    expect(
      await screen.findByRole("heading", { name: "사진 1장을 읽지 못했어요" }),
    ).toBeInTheDocument();
    expect(sent.count).toBe(2);
    expect(screen.getByText("카드 1장")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "사진 1 빼기" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "사진 2 다시 시도" })).not.toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "사진 1 다시 시도" }));
    expect(
      await screen.findByRole("heading", { name: "카드 2장을 만들었어요" }),
    ).toBeInTheDocument();
    expect(sent.count).toBe(3);
    expect(screen.getByRole("heading", { name: "사진 1" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "사진 2" })).toBeInTheDocument();
  });
  it("re-sends every retryable failed photo at once, leaving a failure sending cannot fix on its row", async () => {
    const sent = answer(failed502, { status: 422, body: { error: "no_cards" } }, failed502, read);
    await choose(3);
    expect(
      await screen.findByRole("heading", { name: "사진 3장을 읽지 못했어요" }),
    ).toBeInTheDocument();
    expect(sent.count).toBe(3);
    await userEvent.click(screen.getByRole("button", { name: "실패한 사진 다시 시도" }));
    expect(
      await screen.findByRole("heading", { name: "사진 1장을 읽지 못했어요" }),
    ).toBeInTheDocument();
    expect(sent.count).toBe(5);
    expect(screen.getAllByText("카드 1장")).toHaveLength(2);
    expect(screen.getByRole("button", { name: "사진 2 빼기" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "실패한 사진 다시 시도" })).not.toBeInTheDocument();
  });
  it("reads only the photos the period leaves, and says so", async () => {
    server.use(
      http.post(`${supabaseUrl}/rest/v1/rpc/extraction_allowance`, () =>
        HttpResponse.json([{ photo_limit: 10, used: 9, period: "day" }]),
      ),
    );
    const sent = answer(failed502);
    await choose(3);
    expect(
      await screen.findByText("오늘 1장 더 만들 수 있어요. 처음 1장만 읽어요."),
    ).toBeInTheDocument();
    expect(screen.queryByText("사진 2")).not.toBeInTheDocument();
    await waitFor(() => {
      expect(sent.count).toBe(1);
    });
  });
  it("shows the period's limit before sending any photo when none is left", async () => {
    server.use(
      http.post(`${supabaseUrl}/rest/v1/rpc/extraction_allowance`, () =>
        HttpResponse.json([{ photo_limit: 10, used: 10, period: "month" }]),
      ),
    );
    const sent = answer(read);
    await choose(2);
    expect(
      await screen.findByText(
        "이번 달 사진으로 만들 수 있는 10장을 다 썼어요. 다음 달 1일에 다시 시도해 주세요.",
      ),
    ).toBeInTheDocument();
    expect(sent.count).toBe(0);
    expect(screen.queryByRole("button", { name: "다시 시도" })).not.toBeInTheDocument();
  });
});
