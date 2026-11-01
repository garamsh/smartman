import { studyDayStart } from "@/features/study";

import { revokePlan } from "../revoke-plan";
import { formatDate, formatTime } from "../format";
import { planLabels, termsLabel } from "../labels";
import type { UserPlan as Plan } from "../read-admin";
import { ConfirmAction } from "./confirm-action";
import { GrantPlanForm } from "./grant-plan-form";

/** A user's plan now and the grant behind it, with the form to grant another and the way back to Free. */
export function UserPlan({
  userId,
  email,
  plan,
  timeZone,
}: {
  userId: string;
  email: string;
  plan: Plan;
  timeZone: string;
}) {
  const grant = plan.grant;
  const entitlement = plan.entitlement;
  const ended = grant !== null && entitlement?.plan !== grant.plan;
  return (
    <section aria-label="요금제" className="flex flex-col gap-3">
      <h2 className="text-section">요금제</h2>
      <div className="flex flex-col gap-2 rounded-card bg-surface p-5">
        <p className="text-body-strong">
          {entitlement === null
            ? "요금제 버전이 없어요"
            : `${planLabels[entitlement.plan] ?? entitlement.plan} · ${entitlement.model} · ${termsLabel(entitlement.quota, entitlement.amount)}`}
        </p>
        {grant !== null && (
          <p className="text-caption text-muted">
            {planLabels[grant.plan]} 지정 {formatTime(grant.grantedAt, timeZone)}
            {grant.grantedByEmail === null ? "" : ` · ${grant.grantedByEmail}`}
            {grant.endsAt === null
              ? ""
              : ` · ${formatDate(studyDayStart(grant.endsAt - 1, timeZone), timeZone)}까지`}
            {ended ? " · 끝났어요" : ""}
          </p>
        )}
      </div>
      <GrantPlanForm userId={userId} />
      {grant !== null && (
        <ConfirmAction
          label="무료로 되돌리기"
          question={`${email}의 요금제를 무료로 되돌릴까요?`}
          confirmLabel="무료로 되돌리기"
          action={revokePlan.bind(null, userId)}
        />
      )}
    </section>
  );
}
