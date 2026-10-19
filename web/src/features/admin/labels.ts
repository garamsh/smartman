/** What a deck report's reason reads as, the app's words for each (`app_ko.arb`'s `report*`). */
export const reasonLabels: Record<string, string> = {
  inappropriate: "부적절한 내용",
  spam: "스팸",
  copyright: "저작권 침해",
  other: "기타",
};

/** What each recorded admin action reads as in the log; an action this version does not know shows its name. */
export const actionLabels: Record<string, string> = {
  hide_deck: "덱 숨기기",
  unhide_deck: "덱 숨김 해제",
  unpublish_deck: "덱 비공개로 전환",
  dismiss_reports: "신고 정리",
  grant_admin: "관리자 지정",
  revoke_admin: "관리자 해제",
};

/** [labels]' word for [key], or [key] itself when it has none. */
export function labelOf(labels: Record<string, string>, key: string): string {
  return labels[key] ?? key;
}
