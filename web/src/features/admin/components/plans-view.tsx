import { formatTime } from "../format";
import { planLabels } from "../labels";
import { estimatedCost, measuredModels, usdPerPhoto } from "../model-costs";
import type { PlanSettings } from "../read-admin";
import { PlanForm } from "./plan-form";

/** Each plan's model and daily limit, with the eval's measured cost beside a measured model. */
export function PlansView({ plans, timeZone }: { plans: PlanSettings[]; timeZone: string }) {
  return (
    <div className="flex flex-col gap-section-gap">
      <div className="grid gap-row-gap lg:grid-cols-3">
        {plans.map((plan) => {
          const name = planLabels[plan.id] ?? plan.id;
          const usd = usdPerPhoto(plan.model);
          return (
            <section
              key={plan.id}
              aria-label={name}
              className="flex flex-col gap-3 rounded-card bg-surface p-5"
            >
              <h2 className="text-section">{name}</h2>
              <p className="text-caption text-muted">
                {usd === null
                  ? "이 모델은 측정한 비용이 없어요."
                  : `측정 비용 사진 한 장에 ${estimatedCost(1, usd)}`}
              </p>
              <PlanForm
                plan={plan.id}
                name={name}
                model={plan.model}
                dailyLimit={plan.dailyLimit}
              />
              <p className="text-caption text-muted">
                {formatTime(plan.updatedAt, timeZone)}
                {plan.updatedByEmail === null ? "" : ` · ${plan.updatedByEmail}`}
              </p>
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
