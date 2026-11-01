import { Chip } from "@/design/chip";

import type { PromptLabel } from "../read-admin";

const words: Record<PromptLabel, string> = { active: "사용 중", test: "테스트" };

/** The labels naming a version, in words: 사용 중 for every user, 테스트 for admins. */
export function PromptChips({ labels }: { labels: PromptLabel[] }) {
  return (
    <span className="flex flex-wrap gap-1">
      {labels.map((label) => (
        <Chip key={label} tone={label === "active" ? "brand" : "neutral"}>
          {words[label]}
        </Chip>
      ))}
    </span>
  );
}
