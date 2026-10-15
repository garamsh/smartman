import { redirect } from "next/navigation";

import { getSession, SignOutForm } from "@/features/auth";

/** Who is signed in, read from the session on the server. */
export async function Account() {
  const session = await getSession();
  switch (session.kind) {
    case "signed-in":
      return (
        <div className="flex flex-col gap-6">
          <p className="text-muted">{session.email}(으)로 로그인했어요.</p>
          <SignOutForm />
        </div>
      );
    case "unreachable":
      return (
        <p role="alert" className="text-dont-know-text">
          서버에 연결할 수 없어요. 연결을 확인하고 다시 시도해 주세요.
        </p>
      );
    case "signed-out":
      redirect("/login");
  }
}
