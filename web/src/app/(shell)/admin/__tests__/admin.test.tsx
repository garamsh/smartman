import { screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

import {
  dismissReports,
  grantAdmin,
  hideDeck,
  revokeAdmin,
  unpublishDeck,
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
    ).toEqual(["개요", "신고", "공개 덱", "사용자", "관리자", "작업 기록"]);
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

  it("is not found for a private deck no one reported, or an id that is no deck's", async () => {
    await expect(
      render(DeckContent, { params: Promise.resolve({ id: diary }) }),
    ).rejects.toMatchObject(notFound);
    await expect(
      render(DeckContent, { params: Promise.resolve({ id: "nope" }) }),
    ).rejects.toMatchObject(notFound);
  });
});

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
    expect(admin.calls.filter((call) => call.startsWith("admin_find_users"))).toHaveLength(1);
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

  it("is refused to a user who is not an admin", async () => {
    await signIn(otherUser);
    await render(AuditContent, {});
    expect(screen.getByRole("alert")).toHaveTextContent("관리자만 볼 수 있어요.");
  });
});
