import type { Overview } from "../read-admin";
import type { Usage } from "../usage";
import { AdminSection, group } from "./admin-section";
import { UsageView } from "./usage-view";

/** The overview: users and study, then the last 30 days of photo extractions and their cost. */
export function OverviewView({ overview, usage }: { overview: Overview; usage: Usage }) {
  const figures = [
    {
      heading: "사용자",
      items: [
        ["전체", `${String(overview.users)}명`],
        ["최근 7일 가입", `${String(overview.newUsers7d)}명`],
        ["최근 30일 가입", `${String(overview.newUsers30d)}명`],
      ],
    },
    {
      heading: "학습",
      items: [
        ["오늘 학습", `${String(overview.studiedToday)}명`],
        ["최근 7일 학습", `${String(overview.studied7d)}명`],
      ],
    },
  ] as const;
  return (
    <div className="flex flex-col gap-section-gap">
      <div className="grid items-start gap-section-gap lg:grid-cols-2 lg:gap-4">
        {figures.map(({ heading, items }) => (
          <AdminSection key={heading} label={heading}>
            <dl className={group}>
              {items.map(([term, value]) => (
                <div key={term} className="flex items-baseline justify-between gap-3 px-4 py-3">
                  <dt className="text-body text-ink-2">{term}</dt>
                  <dd className="text-body-strong tabular-nums">{value}</dd>
                </div>
              ))}
            </dl>
          </AdminSection>
        ))}
      </div>
      <UsageView usage={usage} />
    </div>
  );
}
