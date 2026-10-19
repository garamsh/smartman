import { formatDate, formatTime } from "../format";
import type { AdminUser } from "../read-admin";
import { PublicDecks } from "./public-decks";
import { UserDecks } from "./user-decks";
import { UserPlan } from "./user-plan";
import { UserSuspension } from "./user-suspension";

/** One user, read-only: sign-up, last study, decks and cards, public decks and today's photos. */
export function UserView({ user, timeZone }: { user: AdminUser; timeZone: string }) {
  const facts = [
    ["가입일", formatDate(user.createdAt, timeZone)],
    [
      "마지막 학습",
      user.lastAnswerAt === null ? "없어요" : formatTime(user.lastAnswerAt, timeZone),
    ],
    ["덱", `${String(user.decks)}개`],
    ["카드", `${String(user.cards)}장`],
    [
      "오늘 사진 추출 (UTC)",
      user.plan.dailyLimit === null
        ? `${String(user.extractionsToday)}장`
        : `${String(user.extractionsToday)}장 / 하루 ${String(user.plan.dailyLimit)}장`,
    ],
  ] as const;
  return (
    <div className="flex flex-col gap-section-gap">
      <header className="flex flex-wrap items-center gap-2">
        <h1 className="text-display break-all">{user.email}</h1>
        {user.admin && (
          <span className="rounded-full bg-brand-tint px-2 py-0.5 text-micro font-semibold text-ink">
            관리자
          </span>
        )}
        {user.suspension !== null && (
          <span className="rounded-full bg-tint-red px-2 py-0.5 text-micro font-semibold text-dont-know-text">
            정지됨
          </span>
        )}
      </header>
      <dl className="flex flex-col gap-2 rounded-card bg-surface p-5">
        {facts.map(([term, value]) => (
          <div key={term} className="flex items-baseline justify-between gap-3">
            <dt className="text-secondary text-muted">{term}</dt>
            <dd className="text-body-strong">{value}</dd>
          </div>
        ))}
      </dl>
      <UserSuspension
        userId={user.id}
        email={user.email}
        suspension={user.suspension}
        timeZone={timeZone}
      />
      <UserPlan userId={user.id} email={user.email} plan={user.plan} timeZone={timeZone} />
      <UserDecks decks={user.allDecks} />
      <section aria-label="공개 덱" className="flex flex-col gap-3">
        <h2 className="text-section">공개 덱</h2>
        <PublicDecks decks={user.publicDecks} timeZone={timeZone} empty="공개한 덱이 없어요." />
      </section>
    </div>
  );
}
