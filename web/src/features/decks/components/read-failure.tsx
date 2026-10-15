import Link from "next/link";

import type { LibraryFailure } from "../read-library";

const messages: Record<LibraryFailure, string> = {
  unreachable: "서버에 연결할 수 없어요. 연결을 확인하고 다시 시도해 주세요.",
  rejected: "로그인이 끝났어요. 다시 로그인해 주세요.",
  failed: "카드를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.",
  unreadable:
    "이 앱이 읽을 수 없는 카드가 있어 불러오지 못했어요. 휴대폰 앱에서 카드를 확인해 주세요.",
};

/** What a page shows in place of the decks or cards it could not read. */
export function ReadFailure({ failure }: { failure: LibraryFailure }) {
  return (
    <div role="alert" className="flex flex-col gap-3">
      <p className="text-dont-know-text">{messages[failure]}</p>
      {failure === "rejected" && (
        <Link href="/login" className="font-semibold underline">
          로그인
        </Link>
      )}
    </div>
  );
}
