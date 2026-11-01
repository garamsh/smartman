import type { AdminFailure } from "../read-admin";

const messages: Record<AdminFailure, string> = {
  unreachable: "서버에 연결할 수 없어요. 연결을 확인하고 다시 시도해 주세요.",
  rejected: "관리자만 볼 수 있어요.",
  failed: "불러오지 못했어요. 잠시 후 다시 시도해 주세요.",
  unreadable: "이 화면이 읽을 수 없는 답이 와서 불러오지 못했어요.",
};

/** What an admin page shows in place of what it could not read. */
export function AdminFailureMessage({ failure }: { failure: AdminFailure }) {
  return (
    <p role="alert" className="text-dont-know-text">
      {messages[failure]}
    </p>
  );
}
