import { estimatedCost } from "../model-costs";
import type { Overview } from "../read-admin";

/**
 * The overview: users, study and photo extractions with their estimated cost, at [usdPerPhoto],
 * the measured cost of [costModel], the Free plan's model, or none when it was not measured.
 */
export function OverviewView({
  overview,
  costModel,
  usdPerPhoto,
}: {
  overview: Overview;
  costModel: string | null;
  usdPerPhoto: number | null;
}) {
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
        ["오늘 예상 비용", estimatedCost(overview.extractionsToday, usdPerPhoto)],
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
          UTC 날짜 기준이에요.{" "}
          {usdPerPhoto === null
            ? `무료 요금제의 모델${costModel === null ? "" : `(${costModel})`}은 측정한 비용이 없어 예상 비용을 계산하지 않았어요.`
            : `예상 비용은 무료 요금제의 모델 ${costModel ?? ""}의 측정 비용, 사진 한 장에 ${estimatedCost(1, usdPerPhoto)}로 계산했어요.`}{" "}
          30일 합계 {month}장 · {estimatedCost(month, usdPerPhoto)}
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
                <td className="px-4 py-2 text-right">{estimatedCost(extractions, usdPerPhoto)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>
    </div>
  );
}
