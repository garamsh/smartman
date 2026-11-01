import type { Overview } from "../read-admin";
import type { Usage } from "../usage";
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
      <div className="grid gap-row-gap lg:grid-cols-2">
        {figures.map(({ heading, items }) => (
          <section
            key={heading}
            aria-label={heading}
            className="flex flex-col gap-3 rounded-card bg-surface p-5"
          >
            <h2 className="text-section">{heading}</h2>
            <dl className="flex flex-col gap-2">
              {items.map(([term, value]) => (
                <div key={term} className="flex items-baseline justify-between gap-3">
                  <dt className="text-secondary text-muted">{term}</dt>
                  <dd className="text-body-strong">{value}</dd>
                </div>
              ))}
            </dl>
          </section>
        ))}
      </div>
      <UsageView usage={usage} />
    </div>
  );
}
