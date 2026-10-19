import { screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { http, HttpResponse } from "msw";

import {
  dismissReports,
  grantPlan,
  revokePlan,
  setPlan,
  grantAdmin,
  hideDeck,
  removeDeck,
  revokeAdmin,
  suspendUser,
  unpublishDeck,
  unsuspendUser,
} from "@/features/admin/actions";
import { studyDayStart } from "@/features/study";
import { FakeAdmin } from "@/testing/mocks/admin";
import { otherUser, testUser } from "@/testing/mocks/handlers";
import { server } from "@/testing/mocks/server";
import { setRequestCookies } from "@/testing/next-headers";
import { render } from "@/testing/render";
import { signedInCookies } from "@/testing/session";

import { AdminGate } from "../_components/admin-gate";
import {
  AdminsContent,
  AuditContent,
  DeckContent,
  OverviewContent,
  PlansContent,
  PublicDecksContent,
  ReportsContent,
  UserContent,
  UsersContent,
} from "../_components/content";

vi.mock("next/headers", () => import("@/testing/next-headers"));
vi.mock("next/navigation", async (importOriginal) => ({
  ...(await importOriginal<typeof import("next/navigation")>()),
  usePathname: () => "/admin/reports",
}));
const revalidated = vi.hoisted(() => [] as string[]);
vi.mock("next/cache", () => ({
  revalidatePath: (path: string) => {
    revalidated.push(path);
  },
}));

const notFound = { digest: "NEXT_HTTP_ERROR_FALLBACK;404" };
const french = "d0000000-0000-4000-8000-0000000000f1";
const diary = "d0000000-0000-4000-8000-0000000000f2";

/** Signs the next request in as [user], with the browser's zone UTC. */
async function signIn(user: typeof testUser | typeof otherUser = testUser) {
  setRequestCookies([...(await signedInCookies(user)), { name: "smartman-tz", value: "UTC" }]);
}

let admin: FakeAdmin;
beforeEach(async () => {
  revalidated.length = 0;
  admin = new FakeAdmin();
  server.use(...admin.handlers);
  admin.seedDeck({
    id: french,
    name: "French",
    copies: 3,
    cards: [
      { id: "c1", front: "chat", back: "고양이" },
      { id: "c2", front: "chien", back: "개" },
    ],
    reports: [
      { reason: "spam", at: "2026-10-18T01:00:00Z" },
      { reason: "copyright", at: "2026-10-18T02:00:00Z" },
    ],
  });
  admin.seedDeck({ id: diary, name: "Diary", visibility: "private", publishedAt: null });
  await signIn();
});

describe("the admin area's gate", () => {
  it("gives a user who is not an admin the not-found page, and an admin the area's menu", async () => {
    await signIn(otherUser);
    await expect(render(AdminGate, { children: <p>내용</p> })).rejects.toMatchObject(notFound);
    expect(admin.calls.map((call) => call.split(" ")[0])).toEqual(["is_admin"]);

    // Control: the admin sees the menu and the page.
    await signIn();
    await render(AdminGate, { children: <p>내용</p> });
    const menu = screen.getByRole("navigation", { name: "관리 메뉴" });
    expect(
      within(menu)
        .getAllByRole("link")
        .map((link) => link.textContent),
    ).toEqual(["개요", "신고", "공개 덱", "사용자", "요금제", "관리자", "작업 기록"]);
    expect(within(menu).getByRole("link", { name: "신고" })).toHaveAttribute(
      "aria-current",
      "page",
    );
    expect(screen.getByText("내용")).toBeInTheDocument();
  });

  it("gives a revoked admin the not-found page at once", async () => {
    admin.admins.delete(testUser.id);
    await expect(render(AdminGate, { children: <p>내용</p> })).rejects.toMatchObject(notFound);
  });
});

describe("the overview", () => {
  it("shows users, study and today's photos with the estimated cost, and 30 days of photos", async () => {
    admin.extractionsByDay = [
      { day: "2026-10-18", extractions: 10 },
      { day: "2026-10-19", extractions: 5 },
    ];
    // The session's token holds for an hour from now, so the clock stays real.
    const now = Date.now();
    await render(OverviewContent, {});

    const users = screen.getByRole("region", { name: "사용자" });
    expect(within(users).getByText("전체").nextSibling).toHaveTextContent("2명");
    const photos = screen.getByRole("region", { name: "사진 추출" });
    expect(within(photos).getByText("오늘 예상 비용").nextSibling).toHaveTextContent("$0.0090");
    const days = within(screen.getByRole("region", { name: "최근 30일 사진 추출" }));
    expect(
      days
        .getAllByRole("row")
        .slice(1)
        .map((row) => row.textContent),
    ).toEqual(["2026-10-195장$0.0090", "2026-10-1810장$0.0180"]);
    // Today and the last 7 days are study days from 04:00 in the browser's zone.
    const call = admin.calls.find((made) => made.startsWith("admin_overview "));
    const args = JSON.parse(call?.slice("admin_overview ".length) ?? "{}") as Record<
      string,
      string
    >;
    const today = studyDayStart(now, "UTC");
    expect(new Date(today).toISOString().slice(11)).toBe("04:00:00.000Z");
    expect(args).toEqual({
      today_start: new Date(today).toISOString(),
      week_start: new Date(studyDayStart(now - 6 * 86_400_000, "UTC")).toISOString(),
    });
  });

  it("says a user who is not an admin may not see it, against an admin's figures", async () => {
    await signIn(otherUser);
    await render(OverviewContent, {});
    expect(screen.getByRole("alert")).toHaveTextContent("관리자만 볼 수 있어요.");
    expect(screen.queryByRole("region", { name: "사용자" })).not.toBeInTheDocument();
  });
});

describe("the reports page", () => {
  it("lists a reported deck with its reasons and state, and its actions", async () => {
    await render(ReportsContent, {});
    const row = screen.getByRole("listitem");
    expect(within(row).getByRole("link", { name: "French" })).toHaveAttribute(
      "href",
      `/admin/decks/${french}`,
    );
    // The row's line carries more than the count, so a substring is right.
    expect(row).toHaveTextContent(/신고 2건 · 저작권 침해, 스팸/);
    expect(within(row).getByText("공개")).toBeInTheDocument();
    expect(
      within(row)
        .getAllByRole("button")
        .map((button) => button.textContent),
    ).toEqual(["숨기기", "비공개로 전환", "신고 정리"]);
  });

  it("asks before it hides a deck, does nothing on 취소, and records the hide once confirmed", async () => {
    const user = userEvent.setup();
    await render(ReportsContent, {});
    await user.click(screen.getByRole("button", { name: "숨기기" }));
    const question = screen.getByRole("group", { name: "'French' 덱을 공개 목록에서 숨길까요?" });
    expect(within(question).getByRole("button", { name: "숨기기" })).toHaveFocus();
    await user.click(within(question).getByRole("button", { name: "취소" }));
    expect(admin.decks[0]?.hidden).toBe(false);
    expect(admin.calls.some((call) => call.startsWith("admin_set_deck_hidden"))).toBe(false);

    await user.click(screen.getByRole("button", { name: "숨기기" }));
    await user.click(
      within(screen.getByRole("group", { name: /숨길까요/ })).getByRole("button", {
        name: "숨기기",
      }),
    );
    expect(await screen.findByText("덱을 숨겼어요.")).toHaveAttribute("role", "status");
    expect(admin.decks[0]?.hidden).toBe(true);
    expect(admin.audit).toMatchObject([{ action: "hide_deck", target_id: french }]);
    expect(revalidated).toEqual(["/admin"]);
  });

  it("says when there are no reports", async () => {
    admin.decks.length = 0;
    await render(ReportsContent, {});
    expect(screen.getByText("신고된 덱이 없어요.")).toBeInTheDocument();
  });
});

describe("the moderation actions", () => {
  it("are refused for a user who is not an admin, and change nothing", async () => {
    await signIn(otherUser);
    for (const action of [hideDeck, unpublishDeck, dismissReports]) {
      expect(await action(french)).toEqual({ changed: false, message: "관리자만 할 수 있어요." });
    }
    expect(admin.decks[0]).toMatchObject({ hidden: false, visibility: "public" });
    expect(admin.decks[0]?.reports).toHaveLength(2);
    expect(admin.audit).toEqual([]);
    expect(revalidated).toEqual([]);
  });

  it("each change the deck for an admin, and say when there was nothing to change", async () => {
    expect(await hideDeck(french)).toEqual({ changed: true, message: "덱을 숨겼어요." });
    expect(await hideDeck(french)).toEqual({ changed: false, message: "이미 숨겨진 덱이에요." });
    expect(await unpublishDeck(french)).toEqual({ changed: true, message: "비공개로 바꿨어요." });
    expect(await unpublishDeck(french)).toEqual({
      changed: false,
      message: "이미 비공개인 덱이에요.",
    });
    expect(await dismissReports(french)).toEqual({
      changed: true,
      message: "신고 2건을 정리했어요.",
    });
    expect(await dismissReports(french)).toEqual({
      changed: false,
      message: "정리할 신고가 없어요.",
    });
    expect(admin.audit.map((entry) => entry.action)).toEqual([
      "dismiss_reports",
      "unpublish_deck",
      "hide_deck",
    ]);
  });

  it("refuse an id that is not a deck's without asking the server", async () => {
    expect(await hideDeck("not-an-id")).toMatchObject({ changed: false });
    expect(admin.calls).toEqual([]);
  });
});

describe("the public decks page", () => {
  it("lists public decks by name, with their counts, and says when the search finds none", async () => {
    await render(PublicDecksContent, { searchParams: Promise.resolve({}) });
    const row = screen.getByRole("listitem");
    // The line carries the owner and counts together.
    expect(row).toHaveTextContent(/other@example.com · 카드 2장 · 가져오기 3회 · 신고 2건/);
    expect(screen.queryByText("Diary")).not.toBeInTheDocument();

    await render(PublicDecksContent, { searchParams: Promise.resolve({ q: "spanish" }) });
    expect(screen.getByText("찾는 덱이 없어요. 다른 단어로 검색해 보세요.")).toBeInTheDocument();
  });
});

describe("a deck's page", () => {
  it("shows a reported deck read-only with its cards and actions", async () => {
    await render(DeckContent, { params: Promise.resolve({ id: french }) });
    expect(screen.getByRole("heading", { name: "French" })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "other@example.com" })).toHaveAttribute(
      "href",
      `/admin/users/${otherUser.id}`,
    );
    const cards = within(screen.getByRole("region", { name: "카드" }));
    expect(cards.getAllByRole("listitem").map((card) => card.textContent)).toEqual([
      "chat고양이",
      "chien개",
    ]);
    expect(screen.queryByRole("textbox")).not.toBeInTheDocument();
  });

  it("shows a private deck no one reported, read-only, and is not found for an id that is no deck's", async () => {
    await render(DeckContent, { params: Promise.resolve({ id: diary }) });
    expect(screen.getByRole("heading", { name: "Diary" })).toBeInTheDocument();
    // A private deck is not shared, so there is nothing to remove from sharing.
    expect(screen.queryByRole("button", { name: "공유에서 영구 삭제" })).not.toBeInTheDocument();

    await expect(
      render(DeckContent, { params: Promise.resolve({ id: "nope" }) }),
    ).rejects.toMatchObject(notFound);
    await expect(
      render(DeckContent, {
        params: Promise.resolve({ id: "d0000000-0000-4000-8000-0000000000ff" }),
      }),
    ).rejects.toMatchObject(notFound);
  });

  it("removes a public deck from sharing with a reason once confirmed, and then shows why", async () => {
    const user = userEvent.setup();
    const view = await render(DeckContent, { params: Promise.resolve({ id: french }) });
    await user.click(screen.getByRole("button", { name: "공유에서 영구 삭제" }));
    const confirm = screen.getByRole("button", { name: "영구 삭제" });
    expect(confirm).toBeDisabled();
    await user.click(screen.getByRole("button", { name: "취소" }));
    expect(admin.removals.size).toBe(0);

    await user.click(screen.getByRole("button", { name: "공유에서 영구 삭제" }));
    await user.type(screen.getByLabelText("삭제하는 이유"), "copyright");
    await user.click(screen.getByRole("button", { name: "영구 삭제" }));
    expect(await screen.findByText("공유에서 영구 삭제했어요.")).toHaveAttribute("role", "status");
    expect(admin.removals.get(french)).toBe("copyright");
    expect(admin.decks[0]?.visibility).toBe("private");

    view.unmount();
    await render(DeckContent, { params: Promise.resolve({ id: french }) });
    expect(screen.getByRole("note")).toHaveTextContent("공유에서 영구 삭제됨 · copyright");
    expect(screen.queryByRole("button", { name: "공유에서 영구 삭제" })).not.toBeInTheDocument();
  });
});

describe("removing a deck from sharing", () => {
  it("is refused for a user who is not an admin, changing nothing, and done for an admin", async () => {
    await signIn(otherUser);
    expect(await removeDeck(french, "spam")).toEqual({
      changed: false,
      message: "관리자만 할 수 있어요.",
    });
    expect(admin.removals.size).toBe(0);
    expect(admin.decks[0]?.visibility).toBe("public");
    expect(admin.audit).toEqual([]);

    // Control: the same call by an admin removes it.
    await signIn();
    expect(await removeDeck(french, "spam")).toMatchObject({ changed: true });
  });

  it("needs a reason, and says when the deck was already removed", async () => {
    expect(await removeDeck(french, "  ")).toMatchObject({ changed: false });
    expect(admin.calls).toEqual([]);
    expect(await removeDeck(french, " spam ")).toEqual({
      changed: true,
      message: "공유에서 영구 삭제했어요.",
    });
    expect(await removeDeck(french, "spam")).toEqual({
      changed: false,
      message: "이미 공유에서 삭제된 덱이에요.",
    });
    expect(admin.audit).toHaveLength(1);
  });
});

/** Adds [count] users whose emails are `user01@example.com` onward. */
function seedUsers(count: number) {
  for (let index = 1; index <= count; index++) {
    const number = String(index).padStart(2, "0");
    admin.users.push({
      id: `a0000000-0000-4000-8000-0000000000${number}`,
      email: `user${number}@example.com`,
      createdAt: "2026-10-10T00:00:00Z",
      lastAnswerAt: null,
      decks: 0,
      cards: 0,
      extractionsToday: 0,
    });
  }
}

/** The emails the users list shows. */
const listedEmails = () =>
  screen
    .queryAllByRole("listitem")
    .map((item) => item.textContent.split("정지")[0]?.split("2026")[0]);

describe("the users pages", () => {
  it("finds users by email and opens one, read-only, with today's photos against the limit", async () => {
    await render(UsersContent, { searchParams: Promise.resolve({ q: "OTHER" }) });
    expect(screen.getByRole("link", { name: /other@example.com/ })).toHaveAttribute(
      "href",
      `/admin/users/${otherUser.id}`,
    );

    await render(UserContent, { params: Promise.resolve({ id: otherUser.id }) });
    expect(screen.getByRole("heading", { name: "other@example.com" })).toBeInTheDocument();
    expect(screen.getByText("오늘 사진 추출 (UTC)").nextSibling).toHaveTextContent(
      "4장 / 하루 30장",
    );
    expect(screen.getByText("마지막 학습").nextSibling).toHaveTextContent("2026-10-18 09:30");
    expect(
      within(screen.getByRole("region", { name: "공개 덱" })).getByRole("link", { name: "French" }),
    ).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /삭제|편집/ })).not.toBeInTheDocument();
  });

  it("says when the search finds no one, and shows no list before a search", async () => {
    await render(UsersContent, { searchParams: Promise.resolve({ q: "nobody" }) });
    expect(
      screen.getByText("찾는 사용자가 없어요. 다른 단어로 검색해 보세요."),
    ).toBeInTheDocument();
    await render(UsersContent, { searchParams: Promise.resolve({}) });
    expect(admin.calls.filter((call) => call.startsWith("admin_search_users"))).toHaveLength(1);
  });

  it("searches as the admin types, once after the typing pauses, and updates the list in place", async () => {
    const user = userEvent.setup();
    await render(UsersContent, { searchParams: Promise.resolve({ q: "learner" }) });
    expect(listedEmails()).toEqual([testUser.email]);

    const field = screen.getByRole("searchbox", { name: "이메일 검색" });
    await user.clear(field);
    await user.type(field, "other");
    await vi.waitFor(() => {
      expect(listedEmails()).toEqual([otherUser.email]);
    });
    expect(screen.getByRole("status")).toHaveTextContent("1명");
    // One search for the page's own query, and one for the whole typed word.
    expect(admin.calls.filter((call) => call.startsWith("admin_search_users"))).toHaveLength(2);
  });

  it("shows twenty users at a time, the prefix matches first, and adds the next page on 더 보기", async () => {
    const user = userEvent.setup();
    seedUsers(21);
    await render(UsersContent, { searchParams: Promise.resolve({ q: "user" }) });
    expect(screen.getByRole("status")).toHaveTextContent("21명");
    expect(listedEmails()).toHaveLength(20);
    expect(listedEmails()[0]).toBe("user01@example.com");

    await user.click(screen.getByRole("button", { name: "더 보기" }));
    await vi.waitFor(() => {
      expect(listedEmails()).toHaveLength(21);
    });
    expect(listedEmails()[20]).toBe("user21@example.com");
    expect(screen.queryByRole("button", { name: "더 보기" })).not.toBeInTheDocument();
  });

  it("lists every live deck of a user, private ones too, each opening the deck", async () => {
    await render(UserContent, { params: Promise.resolve({ id: otherUser.id }) });
    const decks = within(screen.getByRole("region", { name: "덱" }));
    expect(decks.getByRole("link", { name: /Diary/ })).toHaveAttribute(
      "href",
      `/admin/decks/${diary}`,
    );
    expect(decks.getByRole("link", { name: /French/ })).toHaveTextContent("카드 2장");
  });
});

describe("a user's suspension", () => {
  it("suspends a user with a reason once confirmed, shows it, and lifts it", async () => {
    const user = userEvent.setup();
    await render(UserContent, { params: Promise.resolve({ id: otherUser.id }) });
    const section = within(screen.getByRole("region", { name: "이용 정지" }));
    await user.click(section.getByRole("button", { name: "이용 정지" }));
    await user.type(section.getByLabelText("정지하는 이유"), "spam decks");
    await user.click(section.getByRole("button", { name: "정지" }));
    expect(await section.findByRole("status")).toHaveTextContent("이용을 정지했어요.");
    expect(admin.suspensions.get(otherUser.id)).toEqual({ reason: "spam decks", by: testUser.id });

    await render(UserContent, { params: Promise.resolve({ id: otherUser.id }) });
    expect(screen.getByText("정지됨 · spam decks")).toBeInTheDocument();
    await render(UsersContent, { searchParams: Promise.resolve({ q: "other" }) });
    expect(screen.getByRole("link", { name: /other@example.com/ })).toHaveTextContent("정지 ·");

    expect(await unsuspendUser(otherUser.id)).toEqual({
      changed: true,
      message: "정지를 풀었어요.",
    });
    expect(await unsuspendUser(otherUser.id)).toEqual({
      changed: false,
      message: "정지된 사용자가 아니에요.",
    });
    expect(admin.suspensions.size).toBe(0);
  });

  it("refuses one's own account, a second suspension and a missing reason", async () => {
    expect(await suspendUser(otherUser.id, "")).toMatchObject({ changed: false });
    expect(admin.calls).toEqual([]);
    expect(await suspendUser(testUser.id, "test")).toEqual({
      changed: false,
      message: "내 계정은 정지할 수 없어요.",
    });
    expect(await suspendUser(otherUser.id, "spam")).toMatchObject({ changed: true });
    expect(await suspendUser(otherUser.id, "spam")).toEqual({
      changed: false,
      message: "이미 정지된 사용자예요.",
    });
    expect(admin.audit.map((entry) => entry.action)).toEqual(["suspend_user"]);
  });

  it("is refused to a user who is not an admin, changing nothing, and done for an admin", async () => {
    await signIn(otherUser);
    expect(await suspendUser(testUser.id, "spam")).toEqual({
      changed: false,
      message: "관리자만 할 수 있어요.",
    });
    admin.suspensions.set(testUser.id, { reason: "seeded", by: otherUser.id });
    expect(await unsuspendUser(testUser.id)).toEqual({
      changed: false,
      message: "관리자만 할 수 있어요.",
    });
    expect(admin.suspensions.get(testUser.id)?.reason).toBe("seeded");
    expect(admin.audit).toEqual([]);

    // Control: the same calls by an admin, on a user who is not the caller.
    await signIn();
    expect(await suspendUser(otherUser.id, "spam")).toMatchObject({ changed: true });
    expect(await unsuspendUser(otherUser.id)).toMatchObject({ changed: true });
  });
});

describe("the admins page", () => {
  it("lists the admins and offers no revoke of one's own role", async () => {
    admin.admins.set(otherUser.id, { grantedAt: "2026-10-19T02:00:00Z", grantedBy: testUser.id });
    await render(AdminsContent, {});
    const rows = screen.getAllByRole("listitem");
    expect(rows.map((row) => row.querySelector("span span")?.textContent)).toEqual([
      "learner@example.com (나)",
      "other@example.com",
    ]);
    expect(within(rows[0] as HTMLElement).queryByRole("button", { name: "해제" })).toBeNull();
    expect(
      within(rows[1] as HTMLElement).getByRole("button", { name: "해제" }),
    ).toBeInTheDocument();
  });

  it("grants the role by an existing user's email, and refuses an unknown one", async () => {
    const form = (email: string) => {
      const data = new FormData();
      data.set("email", email);
      return data;
    };
    expect(await grantAdmin({ message: null }, form("nobody@example.com"))).toEqual({
      message: "이 이메일로 가입한 사용자가 없어요.",
    });
    expect(await grantAdmin({ message: null }, form(" Other@Example.com "))).toEqual({
      message: "Other@Example.com님을 관리자로 지정했어요.",
    });
    expect(admin.admins.has(otherUser.id)).toBe(true);
    expect(await grantAdmin({ message: null }, form("other@example.com"))).toEqual({
      message: "이미 관리자예요.",
    });
    expect(admin.audit).toMatchObject([{ action: "grant_admin", target_id: otherUser.id }]);
  });

  it("revokes another admin, refuses one's own role, and refuses a user who is not an admin", async () => {
    admin.admins.set(otherUser.id, { grantedAt: "2026-10-19T02:00:00Z", grantedBy: testUser.id });
    expect(await revokeAdmin(testUser.id)).toEqual({
      changed: false,
      message: "내 관리자 권한은 해제할 수 없어요.",
    });
    expect(await revokeAdmin(otherUser.id)).toEqual({
      changed: true,
      message: "관리자에서 해제했어요.",
    });
    expect(admin.admins.has(otherUser.id)).toBe(false);

    await signIn(otherUser);
    expect(await revokeAdmin(testUser.id)).toEqual({
      changed: false,
      message: "관리자만 할 수 있어요.",
    });
    expect(admin.admins.has(testUser.id)).toBe(true);
  });
});

describe("the audit log", () => {
  it("shows each write, newest first, with who acted and on what", async () => {
    await hideDeck(french);
    const data = new FormData();
    data.set("email", "other@example.com");
    await grantAdmin({ message: null }, data);
    await render(AuditContent, {});
    expect(screen.getAllByRole("listitem").map((entry) => entry.firstChild?.textContent)).toEqual([
      "관리자 지정 · other@example.com",
      "덱 숨기기 · French",
    ]);
    expect(screen.getByRole("link", { name: "French" })).toHaveAttribute(
      "href",
      `/admin/decks/${french}`,
    );
  });

  it("names a suspension and a removal from sharing, with each one's reason", async () => {
    await suspendUser(otherUser.id, "spam decks");
    await unsuspendUser(otherUser.id);
    await removeDeck(french, "copyright");
    await render(AuditContent, {});
    expect(screen.getAllByRole("listitem").map((entry) => entry.firstChild?.textContent)).toEqual([
      "공유에서 영구 삭제 · French · copyright",
      "정지 해제 · other@example.com",
      "이용 정지 · other@example.com · spam decks",
    ]);
  });

  it("is refused to a user who is not an admin", async () => {
    await signIn(otherUser);
    await render(AuditContent, {});
    expect(screen.getByRole("alert")).toHaveTextContent("관리자만 볼 수 있어요.");
  });
});

/** OpenRouter's public model list: Haiku takes images with structured outputs; the text model does not. */
const openRouterModels = http.get("https://openrouter.ai/api/v1/models", () =>
  HttpResponse.json({
    data: [
      {
        id: "anthropic/claude-haiku-5.5",
        architecture: { input_modalities: ["text", "image"] },
        supported_parameters: ["structured_outputs", "max_tokens"],
      },
      {
        id: "openai/gpt-6-luna",
        architecture: { input_modalities: ["text", "image"] },
        supported_parameters: ["structured_outputs"],
      },
      {
        id: "vendor/text-only",
        architecture: { input_modalities: ["text"] },
        supported_parameters: ["structured_outputs"],
      },
      {
        id: "vendor/no-schema",
        architecture: { input_modalities: ["text", "image"] },
        supported_parameters: ["max_tokens"],
      },
    ],
  }),
);

/** A form of [fields], as the browser posts it. */
function form(fields: Record<string, string>): FormData {
  const data = new FormData();
  for (const [name, value] of Object.entries(fields)) data.set(name, value);
  return data;
}

describe("the plans page", () => {
  it("shows each plan's model and daily limit, with the measured cost beside a measured model", async () => {
    admin.plans[1] = { id: "pro", model: "openai/gpt-6-luna", daily_limit: 100, updated_by: null };
    await render(PlansContent, {});
    const free = within(screen.getByRole("region", { name: "무료" }));
    expect(free.getByRole("textbox", { name: "모델" })).toHaveValue("anthropic/claude-haiku-5.5");
    expect(free.getByRole("spinbutton", { name: "하루 사진 한도" })).toHaveValue(30);
    expect(free.getByText("측정 비용 사진 한 장에 $0.0018")).toBeInTheDocument();
    const pro = within(screen.getByRole("region", { name: "프로" }));
    expect(pro.getByText("이 모델은 측정한 비용이 없어요.")).toBeInTheDocument();
    expect(screen.getByRole("region", { name: "스페셜" })).toBeInTheDocument();
    const measured = within(screen.getByRole("region", { name: "측정한 모델" }));
    expect(measured.getAllByRole("listitem").map((row) => row.textContent)).toEqual([
      "anthropic/claude-haiku-5.5$0.0018",
      "anthropic/claude-sonnet-5.5$0.0267",
    ]);
  });

  it("saves a plan's model and limit when OpenRouter lists the model with images and structured outputs, and records it", async () => {
    server.use(openRouterModels);
    const save = () =>
      setPlan(
        { message: null },
        form({ plan: "pro", model: "openai/gpt-6-luna", daily_limit: "100" }),
      );
    expect(await save()).toEqual({ message: "저장했어요." });
    expect(admin.plans[1]).toMatchObject({ model: "openai/gpt-6-luna", daily_limit: 100 });
    expect(admin.audit).toMatchObject([
      { action: "set_plan", target_kind: "plan", target_id: "pro" },
    ]);
    expect(revalidated).toEqual(["/admin"]);
    expect(await save()).toEqual({ message: "바뀐 것이 없어요." });
  });

  it("cannot save a model OpenRouter does not list, one without images or structured outputs, a malformed id or limit, or any while OpenRouter cannot be reached", async () => {
    server.use(openRouterModels);
    const attempt = (model: string, limit = "30") =>
      setPlan({ message: null }, form({ plan: "free", model, daily_limit: limit }));
    expect(await attempt("vendor/unknown")).toEqual({
      message: "OpenRouter에 없는 모델이에요. 모델 ID를 확인해 주세요.",
    });
    for (const model of ["vendor/text-only", "vendor/no-schema"]) {
      expect(await attempt(model), model).toEqual({
        message: "사진과 구조화된 답을 함께 지원하지 않는 모델이에요.",
      });
    }
    expect(await attempt("not a model")).toEqual({
      message: "모델 ID는 vendor/model 꼴로 적어 주세요.",
    });
    expect(await attempt("anthropic/claude-haiku-5.5", "1001")).toEqual({
      message: "하루 한도는 0에서 1000 사이의 정수로 적어 주세요.",
    });
    server.use(
      http.get(
        "https://openrouter.ai/api/v1/models",
        () => new HttpResponse(null, { status: 503 }),
      ),
    );
    expect(await attempt("openai/gpt-6-luna")).toEqual({
      message: "OpenRouter에 연결할 수 없어 모델을 확인하지 못했어요. 잠시 후 다시 시도해 주세요.",
    });
    expect(admin.plans[0]).toMatchObject({ model: "anthropic/claude-haiku-5.5", daily_limit: 30 });
    expect(admin.calls.some((call) => call.startsWith("admin_set_plan"))).toBe(false);
  });

  it("refuses a user who is not an admin, and changes nothing", async () => {
    server.use(openRouterModels);
    await signIn(otherUser);
    expect(
      await setPlan(
        { message: null },
        form({ plan: "free", model: "openai/gpt-6-luna", daily_limit: "5" }),
      ),
    ).toEqual({ message: "관리자만 할 수 있어요." });
    expect(admin.plans[0]).toMatchObject({ model: "anthropic/claude-haiku-5.5", daily_limit: 30 });
    await render(PlansContent, {});
    expect(screen.getByRole("alert")).toHaveTextContent("관리자만 볼 수 있어요.");
  });

  it("estimates the overview's cost at the Free plan's model, and none for a model never measured", async () => {
    admin.plans[0] = { id: "free", model: "openai/gpt-6-luna", daily_limit: 30, updated_by: null };
    await render(OverviewContent, {});
    const photos = screen.getByRole("region", { name: "사진 추출" });
    expect(within(photos).getByText("오늘 예상 비용").nextSibling).toHaveTextContent("—");
  });
});

describe("a user's plan", () => {
  it("shows Free with its limit, grants Special until a day's end in the admin's zone, and goes back to Free", async () => {
    await render(UserContent, { params: Promise.resolve({ id: otherUser.id }) });
    const plan = within(screen.getByRole("region", { name: "요금제" }));
    expect(plan.getByText("무료 · anthropic/claude-haiku-5.5 · 하루 30장")).toBeInTheDocument();
    expect(plan.queryByRole("button", { name: "무료로 되돌리기" })).not.toBeInTheDocument();

    const ends = new Date(Date.now() + 10 * 86_400_000).toISOString().slice(0, 10);
    expect(
      await grantPlan(
        { message: null },
        form({ user: otherUser.id, plan: "special", ends_on: ends }),
      ),
    ).toEqual({ message: "스페셜로 지정했어요." });
    // The last day ends at the next study day's start, 04:00 in the admin's zone, UTC here.
    const next = new Date(Date.parse(`${ends}T00:00:00Z`) + 86_400_000).toISOString().slice(0, 10);
    expect(admin.userPlans.get(otherUser.id)).toEqual({
      plan: "special",
      endsAt: `${next}T04:00:00.000Z`,
      grantedBy: testUser.id,
    });
    expect(admin.audit).toMatchObject([{ action: "grant_plan", target_id: otherUser.id }]);

    await render(UserContent, { params: Promise.resolve({ id: otherUser.id }) });
    const granted = within(screen.getAllByRole("region", { name: "요금제" }).at(-1) as HTMLElement);
    expect(
      granted.getByText("스페셜 · anthropic/claude-haiku-5.5 · 하루 30장"),
    ).toBeInTheDocument();
    // The grant's line carries its time and granter too, so a substring is right.
    expect(granted.getByText(new RegExp(`${ends}까지`))).toBeInTheDocument();
    expect(granted.getByRole("button", { name: "무료로 되돌리기" })).toBeInTheDocument();

    expect(await revokePlan(otherUser.id)).toEqual({
      changed: true,
      message: "무료로 되돌렸어요.",
    });
    expect(await revokePlan(otherUser.id)).toEqual({ changed: false, message: "이미 무료예요." });
    expect(admin.userPlans.has(otherUser.id)).toBe(false);
  });

  it("refuses an end on Pro and an end already past, and refuses a user who is not an admin", async () => {
    expect(
      await grantPlan(
        { message: null },
        form({ user: otherUser.id, plan: "pro", ends_on: "2030-01-01" }),
      ),
    ).toEqual({ message: "끝나는 날은 스페셜에만 정할 수 있어요." });
    expect(
      await grantPlan(
        { message: null },
        form({ user: otherUser.id, plan: "special", ends_on: "2020-01-01" }),
      ),
    ).toEqual({ message: "끝나는 날은 오늘 이후로 정해 주세요." });
    expect(
      await grantPlan({ message: null }, form({ user: otherUser.id, plan: "pro", ends_on: "" })),
    ).toEqual({ message: "프로로 지정했어요." });

    await signIn(otherUser);
    expect(
      await grantPlan(
        { message: null },
        form({ user: otherUser.id, plan: "special", ends_on: "" }),
      ),
    ).toEqual({ message: "관리자만 할 수 있어요." });
    expect(await revokePlan(otherUser.id)).toEqual({
      changed: false,
      message: "관리자만 할 수 있어요.",
    });
    expect(admin.userPlans.get(otherUser.id)?.plan).toBe("pro");
  });

  it("names each plan change in the audit log", async () => {
    server.use(openRouterModels);
    await setPlan(
      { message: null },
      form({ plan: "pro", model: "openai/gpt-6-luna", daily_limit: "100" }),
    );
    await grantPlan({ message: null }, form({ user: otherUser.id, plan: "pro", ends_on: "" }));
    await render(AuditContent, {});
    expect(screen.getAllByRole("listitem").map((entry) => entry.firstChild?.textContent)).toEqual([
      "요금제 지정 · other@example.com · 프로",
      "요금제 설정 · 프로 · openai/gpt-6-luna · 하루 100장",
    ]);
    expect(screen.getByRole("link", { name: "프로" })).toHaveAttribute("href", "/admin/plans");
  });
});
