import { estimatedCost, estimatedUsdPerPhoto } from "../extraction";
import type { Overview } from "../read-admin";

/** The overview: users, study and photo extractions with their estimated cost. */
export function OverviewView({ overview }: { overview: Overview }) {
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
    {
      heading: "사진 추출",
      items: [
        ["오늘", `${String(overview.extractionsToday)}장`],
        ["오늘 예상 비용", estimatedCost(overview.extractionsToday)],
      ],
    },
  ] as const;
  const month = overview.days.reduce((total, day) => total + day.extractions, 0);
  return (
    <div className="flex flex-col gap-section-gap">
      <div className="grid gap-row-gap lg:grid-cols-3">
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
      <section aria-label="최근 30일 사진 추출" className="flex flex-col gap-3">
        <h2 className="text-section">최근 30일 사진 추출</h2>
        <p className="text-caption text-muted">
          UTC 날짜 기준, 사진 한 장에 ${estimatedUsdPerPhoto}로 계산한 예상 비용이에요. 30일 합계{" "}
          {month}장 · {estimatedCost(month)}
        </p>
        <table className="w-full rounded-card bg-surface text-secondary">
          <thead>
            <tr className="text-left text-muted">
              <th scope="col" className="px-4 py-2 font-medium">
                날짜
              </th>
              <th scope="col" className="px-4 py-2 text-right font-medium">
                사진
              </th>
              <th scope="col" className="px-4 py-2 text-right font-medium">
                예상 비용
              </th>
            </tr>
          </thead>
          <tbody>
            {overview.days.toReversed().map(({ day, extractions }) => (
              <tr key={day} className="border-t border-hairline">
                <th scope="row" className="px-4 py-2 text-left font-normal">
                  {day}
                </th>
                <td className="px-4 py-2 text-right">{extractions}장</td>
                <td className="px-4 py-2 text-right">{estimatedCost(extractions)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>
    </div>
  );
}
