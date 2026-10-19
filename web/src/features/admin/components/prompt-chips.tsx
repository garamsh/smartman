import type { PromptLabel } from "../read-admin";

const words: Record<PromptLabel, string> = { active: "사용 중", test: "테스트" };

/** The labels naming a version, in words: 사용 중 for every user, 테스트 for admins. */
export function PromptChips({ labels }: { labels: PromptLabel[] }) {
  return (
    <span className="flex flex-wrap gap-1">
      {labels.map((label) => (
        <span
          key={label}
          className={`rounded-full px-2 py-0.5 text-micro font-semibold ${
            label === "active" ? "bg-brand-tint text-ink" : "bg-ground text-ink-2"
          }`}
        >
          {words[label]}
        </span>
      ))}
    </span>
  );
}
