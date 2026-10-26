import { formatTime } from "../format";
import { planLabels, termsLabel } from "../labels";
import { estimatedCost, measuredModels, usdPerPhoto } from "../model-costs";
import type { PlanId, PlanVersion } from "../read-admin";
import { PlanForm } from "./plan-form";

const plans: PlanId[] = ["free", "pro", "max"];

/**
 * Each plan's version a user subscribing now takes, with the eval's measured cost beside a measured
 * model, the form for a new version, and every version, the latest start first.
 */
export function PlansView({ versions, timeZone }: { versions: PlanVersion[]; timeZone: string }) {
  return (
    <div className="flex flex-col gap-section-gap">
      <div className="grid gap-row-gap lg:grid-cols-3">
        {plans.map((plan) => {
          const name = planLabels[plan] ?? plan;
          const own = versions.filter((version) => version.plan === plan);
          const current = own.find((version) => version.current) ?? null;
          const usd = current === null ? null : usdPerPhoto(current.model);
          // The form starts from the current terms, or the latest version's while none is current.
          const start = current ?? own[0] ?? null;
          return (
            <section
              key={plan}
              aria-label={name}
              className="flex flex-col gap-3 rounded-card bg-surface p-5"
            >
              <h2 className="text-section">{name}</h2>
              {current === null ? (
                <p className="text-body-strong">지금 가입하면 받을 버전이 없어요</p>
              ) : (
                <>
                  <p className="text-body-strong">
                    지금 가입하면 {termsLabel(current.quota, current.amount)} · {current.model}
                  </p>
                  <p className="text-caption text-muted">
                    {usd === null
                      ? "이 모델은 측정한 비용이 없어요."
                      : `측정 비용 사진 한 장에 ${estimatedCost(1, usd)}`}
                  </p>
                </>
              )}
              <PlanForm
                plan={plan}
                name={name}
                quota={start?.quota ?? "daily"}
                amount={start?.amount ?? 0}
                model={start?.model ?? ""}
              />
              <h3 className="text-label font-semibold">버전</h3>
              <ul aria-label={`${name} 버전`} className="flex flex-col gap-2">
                {own.map((version) => (
                  <li key={version.id} className="flex flex-col gap-0.5">
                    <span className="text-secondary">
                      {termsLabel(version.quota, version.amount)} · {version.model}
                      {version.current ? " · 지금 가입 시 적용" : ""}
                    </span>
                    <span className="text-caption text-muted">
                      {formatTime(version.startsAt, timeZone)}부터
                      {version.appliesToAll
                        ? " · 기존 사용자도 적용"
                        : " · 기존 사용자는 갱신일부터"}
                      {version.createdByEmail === null ? "" : ` · ${version.createdByEmail}`}
                    </span>
                  </li>
                ))}
              </ul>
            </section>
          );
        })}
      </div>
      <section aria-label="측정한 모델" className="flex flex-col gap-3">
        <h2 className="text-section">측정한 모델</h2>
        <p className="text-caption text-muted">
          평가(eval)가 프롬프트 v6, 표본 47장으로 잰 사진 한 장의 비용이에요.
        </p>
        <ul className="flex flex-col gap-2">
          {measuredModels.map(({ model, usdPerPhoto: usd }) => (
            <li
              key={model}
              className="flex items-baseline justify-between gap-3 rounded-row bg-surface px-4 py-3"
            >
              <span className="text-body-strong break-all">{model}</span>
              <span className="text-secondary">{estimatedCost(1, usd)}</span>
            </li>
          ))}
        </ul>
      </section>
    </div>
  );
}
