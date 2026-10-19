import Link from "next/link";

import { formatTime } from "../format";
import { actionLabels, labelOf, planLabels } from "../labels";
import type { AuditEntry } from "../read-admin";

/** What an entry acted on: the deck's name or the user's email it recorded, linked where it can be opened. */
function Target({ entry }: { entry: AuditEntry }) {
  const name = entry.detail.name;
  const email = entry.detail.email;
  const words =
    typeof name === "string"
      ? name
      : typeof email === "string"
        ? email
        : entry.targetKind === "plan"
          ? labelOf(planLabels, entry.targetId)
          : entry.targetId;
  const href =
    entry.targetKind === "deck"
      ? `/admin/decks/${entry.targetId}`
      : entry.targetKind === "user"
        ? `/admin/users/${entry.targetId}`
        : entry.targetKind === "plan"
          ? "/admin/plans"
          : null;
  return href === null ? (
    <span>{words}</span>
  ) : (
    <Link
      href={href}
      className="underline underline-offset-4 focus-visible:outline-2 focus-visible:outline-ink"
    >
      {words}
    </Link>
  );
}

/** The audit log, newest first: when, who, what and on what. */
export function AuditLog({ entries, timeZone }: { entries: AuditEntry[]; timeZone: string }) {
  if (entries.length === 0) return <p className="text-muted">기록된 작업이 없어요.</p>;
  return (
    <ul className="flex flex-col gap-2">
      {entries.map((entry) => (
        <li key={entry.id} className="flex flex-col gap-1 rounded-row bg-surface px-4 py-3">
          <span className="text-body-strong">
            {labelOf(actionLabels, entry.action)} · <Target entry={entry} />
            {typeof entry.detail.reports === "number" ? ` · ${String(entry.detail.reports)}건` : ""}
            {typeof entry.detail.plan === "string"
              ? ` · ${labelOf(planLabels, entry.detail.plan)}`
              : ""}
            {typeof entry.detail.model === "string" && typeof entry.detail.daily_limit === "number"
              ? ` · ${entry.detail.model} · 하루 ${String(entry.detail.daily_limit)}장`
              : ""}
          </span>
          <span className="text-caption text-muted">
            {formatTime(entry.at, timeZone)} · {entry.adminEmail}
          </span>
        </li>
      ))}
    </ul>
  );
}
