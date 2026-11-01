import Link from "next/link";

import { formatTime } from "../format";
import type { PromptVersion } from "../read-admin";
import { AdminSection, group } from "./admin-section";
import { PromptChips } from "./prompt-chips";

/** Every saved version, newest first, each opening the version. */
export function PromptVersions({
  versions,
  timeZone,
}: {
  versions: PromptVersion[];
  timeZone: string;
}) {
  return (
    <AdminSection label="저장된 버전">
      <ul className={`${group} overflow-hidden`}>
        {versions.map((version) => (
          <li key={version.id}>
            <Link
              href={`/admin/prompts/${String(version.id)}`}
              className="pressable flex min-h-13 flex-col gap-1 px-4 py-3 focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-ink"
            >
              <span className="flex flex-wrap items-center gap-2">
                <span className="text-body-strong">버전 {version.id}</span>
                <PromptChips labels={version.labels} />
                {version.note !== "" && (
                  <span className="text-body text-ink-2">{version.note}</span>
                )}
              </span>
              <span className="text-caption text-muted">
                {version.length.toLocaleString("ko-KR")}자 ·{" "}
                {formatTime(version.createdAt, timeZone)}
                {version.createdByEmail === null ? "" : ` · ${version.createdByEmail}`}
              </span>
            </Link>
          </li>
        ))}
      </ul>
    </AdminSection>
  );
}
