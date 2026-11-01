import Link from "next/link";

import { Chip } from "@/design/chip";

import { formatTime } from "../format";
import { labelOf, planLabels } from "../labels";
import {
  type ExtractionCall,
  failed,
  failureRate,
  failureWords,
  type OutcomeCounts,
  outcomeWords,
  type OutcomeSummary,
} from "../outcomes";
import { AdminSection, button, Empty, group, row } from "./admin-section";

/** [rate] as a percent with one decimal, as "3.2%". */
function percent(rate: number): string {
  return `${(rate * 100).toFixed(1)}%`;
}

/** The second line of a version's or the period's counts. */
function countsLine(counts: OutcomeCounts): string {
  return [
    `추출 ${String(counts.calls)}건`,
    `형식 오류 ${String(counts.invalidOutput)}건`,
    `모델 오류 ${String(counts.modelError)}건`,
    `재시도 ${String(counts.retried)}건 중 ${String(counts.recovered)}건 복구`,
  ].join(" · ");
}

/**
 * Whether photo import works: the failure rate of the last 30 days with each outcome's count, the
 * rate by day as bars drawn as the 기록 page draws its weeks, the rate by prompt version, and the
 * recent extractions, a page at a time.
 */
export function OutcomesView({
  summary,
  calls,
  before,
  more,
  timeZone,
}: {
  summary: OutcomeSummary;
  calls: ExtractionCall[];
  /** The usage id the page of [calls] lists before, or null for the newest page. */
  before: number | null;
  /** Whether a page older than [calls] may exist. */
  more: boolean;
  timeZone: string;
}) {
  return (
    <div className="flex flex-col gap-section-gap">
      {summary.total.calls === 0 && summary.total.unrecorded === 0 ? (
        <Empty>최근 30일에 기록된 추출이 없어요. 사진으로 카드를 만들면 여기에 쌓여요.</Empty>
      ) : (
        <>
          <Period total={summary.total} />
          <DailyRates days={summary.days} />
          <AdminSection label="프롬프트 버전별">
            <ul className={group}>
              {summary.versions.map(({ version, counts }) => {
                const rate = failureRate(counts);
                return (
                  <li key={version} className={row}>
                    <span className="flex items-baseline justify-between gap-3">
                      <Link
                        href={`/admin/prompts/${String(version)}`}
                        className="text-body-strong underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-ink"
                      >
                        버전 {version}
                      </Link>
                      <span className="text-body-strong tabular-nums">
                        {rate === null ? "기록 없음" : `실패 ${percent(rate)}`}
                      </span>
                    </span>
                    <span className="text-caption text-muted">{countsLine(counts)}</span>
                  </li>
                );
              })}
            </ul>
          </AdminSection>
        </>
      )}
      <AdminSection label="최근 추출">
        {before !== null && (
          <Link
            href="/admin/extractions"
            className="self-start px-1 text-body text-ink-2 underline underline-offset-4 focus-visible:outline-2 focus-visible:outline-ink"
          >
            최신 추출로
          </Link>
        )}
        {calls.length === 0 ? (
          <Empty>
            {before === null
              ? "기록된 추출이 없어요. 사진으로 카드를 만들면 여기에 쌓여요."
              : "이보다 이전 추출이 없어요. 최신 추출로 돌아가 보세요."}
          </Empty>
        ) : (
          <ul aria-label="최근 추출" className={group}>
            {calls.map((call) => (
              <CallRow key={call.usageId} call={call} timeZone={timeZone} />
            ))}
          </ul>
        )}
        {more && calls.length > 0 && (
          <Link
            href={`/admin/extractions?before=${String(calls[calls.length - 1]?.usageId)}`}
            className={button.secondary}
          >
            이전 추출 더 보기
          </Link>
        )}
      </AdminSection>
    </div>
  );
}

/** The period's failure rate as a figure, then each outcome's count. */
function Period({ total }: { total: OutcomeCounts }) {
  const rate = failureRate(total);
  const items = [
    ["성공", total.ok],
    ["카드 없음", total.noCards],
    ["형식 오류", total.invalidOutput],
    ["모델 오류", total.modelError],
  ] as const;
  return (
    <AdminSection label="최근 30일">
      <div className={group}>
        <div className={row}>
          <span className="text-caption text-muted">실패율</span>
          <p className="text-figure tabular-nums">
            {rate === null ? "–" : (rate * 100).toFixed(1)}
            {rate !== null && <span className="ml-0.5 text-body text-muted">%</span>}
          </p>
          <span className="text-caption text-muted">
            기록된 추출 {total.calls}건 중 {total.invalidOutput + total.modelError}건이 카드 없이
            실패했어요
          </span>
        </div>
        <dl className="flex flex-col divide-y divide-hairline">
          {items.map(([term, value]) => (
            <div key={term} className="flex items-baseline justify-between gap-3 px-4 py-3">
              <dt className="text-body text-ink-2">{term}</dt>
              <dd className="text-body-strong tabular-nums">{value}건</dd>
            </div>
          ))}
          <div className="flex items-baseline justify-between gap-3 px-4 py-3">
            <dt className="text-body text-ink-2">재시도</dt>
            <dd className="text-body-strong tabular-nums">
              {total.retried}건 중 {total.recovered}건 복구
            </dd>
          </div>
          {total.unrecorded > 0 && (
            <div className="flex flex-col gap-1 px-4 py-3">
              <div className="flex items-baseline justify-between gap-3">
                <dt className="text-body text-ink-2">기록 없음</dt>
                <dd className="text-body-strong tabular-nums">{total.unrecorded}건</dd>
              </div>
              <p className="text-caption text-muted">결과를 기록하기 전에 요청이 끝난 추출이에요</p>
            </div>
          )}
        </dl>
      </div>
    </AdminSection>
  );
}

/** The scale's top: the highest day's rate rounded up to a step of 5%, at least 5%. */
function scaleTop(days: OutcomeSummary["days"]): number {
  const highest = Math.max(0, ...days.map(({ counts }) => failureRate(counts) ?? 0));
  return Math.max(5, Math.ceil((highest * 100) / 5) * 5);
}

/**
 * Each day's failure rate as a bar, today's in ink and the others ink at 55%, as the 기록 page
 * draws its weeks; a day without a recorded call draws none. One image named by every day's rate.
 */
function DailyRates({ days }: { days: OutcomeSummary["days"] }) {
  const top = scaleTop(days);
  const shown = days.filter(({ counts }) => counts.calls > 0);
  const label =
    shown.length === 0
      ? "날짜별 실패율: 기록된 추출이 없어요."
      : `날짜별 실패율, 최근 30일: ${shown
          .map(({ day, counts }) => `${day.slice(5)} ${percent(failureRate(counts) ?? 0)}`)
          .join(", ")}`;
  return (
    <AdminSection label="날짜별 실패율" note="날짜는 UTC 기준이에요">
      <div className="flex flex-col gap-1 rounded-group bg-surface p-4">
        <div className="flex gap-2">
          <div
            aria-hidden
            className="flex w-9 flex-col justify-between text-right text-micro text-muted"
          >
            <span className="-translate-y-2">{top}%</span>
            <span className="translate-y-2">0%</span>
          </div>
          <div
            role="img"
            aria-label={label}
            className="flex h-28 min-w-0 flex-1 items-end gap-0.5 border-b border-hairline"
          >
            {days.map(({ day, counts }, index) => {
              const rate = failureRate(counts);
              return (
                <span
                  key={day}
                  className={`flex-1 rounded-t-sm ${index === days.length - 1 ? "bg-ink" : "bg-ink/55"}`}
                  style={{ height: rate === null ? 0 : `${String((rate * 100 * 100) / top)}%` }}
                />
              );
            })}
          </div>
        </div>
        <div aria-hidden className="flex justify-between pl-11 text-caption text-muted">
          <span>{days.length - 1}일 전</span>
          <span>오늘</span>
        </div>
      </div>
    </AdminSection>
  );
}

/** One extraction: its outcome and time, then its plan, version, calls, latency and cards. */
function CallRow({ call, timeZone }: { call: ExtractionCall; timeZone: string }) {
  const { result } = call;
  const details = [labelOf(planLabels, call.plan), `버전 ${String(call.promptVersion)}`];
  if (result !== null) {
    details.push(
      result.failures.length === 0
        ? `시도 ${String(result.attempts)}회`
        : `시도 ${String(result.attempts)}회 (${result.failures.map((kind) => failureWords[kind]).join(", ")})`,
      `${(result.latencyMs / 1000).toFixed(1)}초`,
      `카드 ${String(result.cardsReturned)}장`,
    );
    if (result.cardsDropped > 0) details.push(`거른 카드 ${String(result.cardsDropped)}장`);
  }
  return (
    <li className={row}>
      <span className="flex items-center justify-between gap-3">
        {result === null ? (
          <Chip>기록 없음</Chip>
        ) : (
          <Chip tone={failed(result.outcome) ? "amber" : "neutral"}>
            {outcomeWords[result.outcome]}
          </Chip>
        )}
        <span className="text-caption text-muted tabular-nums">
          {formatTime(call.at, timeZone)}
        </span>
      </span>
      <span className="text-caption text-ink-2">{details.join(" · ")}</span>
    </li>
  );
}
