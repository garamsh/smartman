import { notFound } from "next/navigation";

import {
  AdminFailureMessage,
  AdminList,
  adminTimeZone,
  AuditLog,
  DeckView,
  GrantAdminForm,
  OverviewView,
  PlansView,
  PublicDecks,
  readAdmins,
  readAuditLog,
  readDeck,
  readOverview,
  readPlans,
  readPublicDecks,
  readReportedDecks,
  readUser,
  searchUsers,
  ReportedDecks,
  UserSearch,
  UserView,
  usdPerPhoto,
} from "@/features/admin";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/** The text of a search parameter, or "" when it is absent or repeated. */
function searchText(value: string | string[] | undefined): string {
  return typeof value === "string" ? value.trim() : "";
}

export async function OverviewContent() {
  const [read, plans] = await Promise.all([readOverview(), readPlans()]);
  if ("failure" in read) return <AdminFailureMessage failure={read.failure} />;
  if ("failure" in plans) return <AdminFailureMessage failure={plans.failure} />;
  const free = plans.data.find((plan) => plan.id === "free")?.model ?? null;
  return (
    <OverviewView
      overview={read.data}
      costModel={free}
      usdPerPhoto={free === null ? null : usdPerPhoto(free)}
    />
  );
}

export async function PlansContent() {
  const [read, timeZone] = await Promise.all([readPlans(), adminTimeZone()]);
  if ("failure" in read) return <AdminFailureMessage failure={read.failure} />;
  return <PlansView plans={read.data} timeZone={timeZone} />;
}

export async function ReportsContent() {
  const [read, timeZone] = await Promise.all([readReportedDecks(), adminTimeZone()]);
  if ("failure" in read) return <AdminFailureMessage failure={read.failure} />;
  return <ReportedDecks decks={read.data} timeZone={timeZone} />;
}

export async function PublicDecksContent({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const search = searchText((await searchParams).q);
  const [read, timeZone] = await Promise.all([readPublicDecks({ search }), adminTimeZone()]);
  return (
    <>
      <form role="search" action="/admin/decks">
        <input
          type="search"
          name="q"
          aria-label="덱 이름 검색"
          placeholder="덱 이름 검색"
          defaultValue={search}
          className="h-search w-full rounded-field border border-outline bg-surface px-4 text-body placeholder:text-muted focus-visible:outline-2 focus-visible:-outline-offset-1 focus-visible:outline-ink"
        />
      </form>
      {"failure" in read ? (
        <AdminFailureMessage failure={read.failure} />
      ) : (
        <PublicDecks
          decks={read.data}
          timeZone={timeZone}
          empty={search ? "찾는 덱이 없어요. 다른 단어로 검색해 보세요." : "공개된 덱이 없어요."}
        />
      )}
    </>
  );
}

export async function DeckContent({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!uuid.test(id)) notFound();
  const [read, timeZone] = await Promise.all([readDeck(id), adminTimeZone()]);
  if ("failure" in read) return <AdminFailureMessage failure={read.failure} />;
  if (read.data === null) notFound();
  return <DeckView deck={read.data} timeZone={timeZone} />;
}

export async function UsersContent({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const query = searchText((await searchParams).q);
  const timeZone = await adminTimeZone();
  // An address with a query opens on its first page, read on the server.
  const read = query === "" ? null : await searchUsers(query, 0);
  return (
    <>
      <UserSearch
        initialQuery={query}
        initialPage={read === null || "failure" in read ? null : read.data}
        timeZone={timeZone}
      />
      {read !== null && "failure" in read && <AdminFailureMessage failure={read.failure} />}
    </>
  );
}

export async function UserContent({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!uuid.test(id)) notFound();
  const [read, timeZone] = await Promise.all([readUser(id), adminTimeZone()]);
  if ("failure" in read) return <AdminFailureMessage failure={read.failure} />;
  if (read.data === null) notFound();
  return <UserView user={read.data} timeZone={timeZone} />;
}

export async function AdminsContent() {
  const [read, timeZone] = await Promise.all([readAdmins(), adminTimeZone()]);
  return (
    <>
      <GrantAdminForm />
      {"failure" in read ? (
        <AdminFailureMessage failure={read.failure} />
      ) : (
        <AdminList admins={read.data} timeZone={timeZone} />
      )}
    </>
  );
}

export async function AuditContent() {
  const [read, timeZone] = await Promise.all([readAuditLog(), adminTimeZone()]);
  if ("failure" in read) return <AdminFailureMessage failure={read.failure} />;
  return <AuditLog entries={read.data} timeZone={timeZone} />;
}
