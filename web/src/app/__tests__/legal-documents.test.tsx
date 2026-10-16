import { screen, within } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { render } from "@/testing/render";

import PrivacyPage from "../privacy/page";
import TermsPage from "../terms/page";

/** The headings issue #86 requires of each document, in the order they appear. */
const documents = [
  {
    name: "the privacy policy",
    page: PrivacyPage,
    title: "개인정보 처리방침",
    headings: [
      "수집하는 개인정보 항목과 수집 방법",
      "개인정보의 이용 목적",
      "보유 기간과 파기",
      "개인정보의 제3자 제공",
      "개인정보 처리의 위탁",
      "개인정보의 국외 이전",
      "이용자의 권리와 행사 방법",
      "자동으로 수집되는 정보와 쿠키",
      "개인정보의 안전성 확보 조치",
      "개인정보 보호 문의처",
      "시행일과 변경",
    ],
  },
  {
    name: "the terms of service",
    page: TermsPage,
    title: "이용약관",
    headings: [
      "서비스",
      "계정과 로그인",
      "이용자의 콘텐츠와 이용 허락",
      "공개 공유, 신고와 차단, 금지 콘텐츠",
      "AI로 만든 카드",
      "서비스의 변경과 중단",
      "계정 삭제",
      "면책과 책임의 제한",
      "준거법과 관할",
      "문의처",
      "시행일",
    ],
  },
] as const;

describe.each(documents)("$name", ({ page, title, headings }) => {
  it("is titled, states its effective date, and names the contact", async () => {
    await render(page, {});

    expect(screen.getByRole("heading", { level: 1, name: title })).toBeInTheDocument();
    expect(screen.getByText("시행일 2026년 10월 16일")).toBeInTheDocument();
    for (const link of screen.getAllByRole("link", { name: "sauce@garam.sh" })) {
      expect(link).toHaveAttribute("href", "mailto:sauce@garam.sh");
    }
    expect(screen.getAllByRole("link", { name: "sauce@garam.sh" }).length).toBeGreaterThan(0);
  });

  it("carries every required section, each a heading its table of contents links to", async () => {
    await render(page, {});

    const sections = screen
      .getAllByRole("heading", { level: 2 })
      .filter((heading) => heading.id !== "toc");
    expect(sections.map((heading) => heading.textContent)).toEqual(headings);

    const toc = within(screen.getByRole("navigation", { name: "목차" }));
    for (const heading of sections) {
      expect(toc.getByRole("link", { name: heading.textContent })).toHaveAttribute(
        "href",
        `#${heading.id}`,
      );
    }
  });
});
