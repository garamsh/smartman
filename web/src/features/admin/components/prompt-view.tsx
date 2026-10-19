import Link from "next/link";

import { activatePrompt } from "../activate-prompt";
import { clearTestPrompt } from "../clear-test-prompt";
import { formatTime } from "../format";
import { lineDiff } from "../prompt-diff";
import type { PromptDetail } from "../read-admin";
import { testPrompt } from "../test-prompt";
import { ConfirmAction } from "./confirm-action";
import { PromptChips } from "./prompt-chips";

/**
 * One version: its text, its difference from the active version, and the actions that serve it,
 * each asked first.
 */
export function PromptView({ version, timeZone }: { version: PromptDetail; timeZone: string }) {
  const active = version.labels.includes("active");
  const test = version.labels.includes("test");
  const diff =
    version.active === null || active ? null : lineDiff(version.active.text, version.text);
  const changed = diff?.filter((line) => line.kind !== "same").length ?? 0;
  return (
    <>
      <div className="flex flex-col gap-1">
        <h1 className="flex flex-wrap items-center gap-2 text-display">
          버전 {version.id}
          <PromptChips labels={version.labels} />
        </h1>
        <p className="text-caption text-muted">
          {version.note === "" ? "" : `${version.note} · `}
          {version.length.toLocaleString("ko-KR")}자 · {formatTime(version.createdAt, timeZone)}
          {version.createdByEmail === null ? "" : ` · ${version.createdByEmail}`}
        </p>
      </div>
      {diff !== null && version.active !== null && (
        <section aria-label="사용 중인 버전과 다른 점" className="flex flex-col gap-2">
          <h2 className="text-section">사용 중인 버전 {version.active.id}과 다른 점</h2>
          <p className="text-secondary text-muted">
            {changed === 0
              ? "내용이 같아요."
              : `바뀐 줄 ${String(changed)}개: 빼는 줄은 −, 더하는 줄은 +로 표시해요.`}
          </p>
          <ol className="flex flex-col rounded-field border border-outline bg-surface p-3 font-mono text-caption">
            {diff.map((line, index) => (
              <li
                key={index}
                className={`grid grid-cols-[1.5rem_1fr] whitespace-pre-wrap ${
                  line.kind === "removed"
                    ? "bg-tint-red text-dont-know-text"
                    : line.kind === "added"
                      ? "bg-brand-tint text-ink"
                      : "text-ink-2"
                }`}
              >
                <span aria-hidden>
                  {line.kind === "removed" ? "−" : line.kind === "added" ? "+" : ""}
                </span>
                <span>
                  <span className="sr-only">
                    {line.kind === "removed" ? "뺌: " : line.kind === "added" ? "더함: " : ""}
                  </span>
                  {line.text}
                </span>
              </li>
            ))}
          </ol>
        </section>
      )}
      <div className="flex flex-wrap gap-3">
        {!active && (
          <ConfirmAction
            label="모든 사용자에게 적용"
            question={`버전 ${String(version.id)}을 모든 사용자에게 적용할까요? 위에서 다른 점을 확인해 주세요.`}
            confirmLabel="적용"
            action={activatePrompt.bind(null, version.id)}
          />
        )}
        {!active && !test && (
          <ConfirmAction
            label="관리자만 테스트"
            question={`버전 ${String(version.id)}을 관리자에게만 쓸까요? 사용자는 지금 버전을 그대로 써요.`}
            confirmLabel="테스트 시작"
            action={testPrompt.bind(null, version.id)}
          />
        )}
        {test && (
          <ConfirmAction
            label="테스트 끝내기"
            question="테스트를 끝낼까요? 관리자도 사용 중인 버전을 쓰게 돼요."
            confirmLabel="테스트 끝내기"
            action={clearTestPrompt}
          />
        )}
      </div>
      <section aria-label="프롬프트" className="flex flex-col gap-2">
        <h2 className="text-section">프롬프트</h2>
        <Link
          href={`/admin/prompts?from=${String(version.id)}`}
          className="self-start text-label underline underline-offset-4 focus-visible:outline-2 focus-visible:outline-ink"
        >
          이 버전에서 새 버전 쓰기
        </Link>
        <pre className="rounded-field border border-outline bg-surface p-3 font-mono text-caption whitespace-pre-wrap">
          {version.text}
        </pre>
      </section>
    </>
  );
}
