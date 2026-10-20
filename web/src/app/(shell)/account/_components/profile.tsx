import { redirect } from "next/navigation";

import { RetryButton } from "@/design/retry-button";
import { ThemeChoice } from "@/design/theme-choice";
import { AccountAvatar, getSession, SignOutForm } from "@/features/account";

import { readStudySetting, StudySetting } from "./study-setting";

/**
 * Who is signed in, read from the session on the server, the daily study minutes, the theme the web
 * is drawn in, and the account's actions; while the server cannot be reached, "다시 시도" and the
 * theme.
 */
export async function Profile() {
  const session = await getSession();
  switch (session.kind) {
    case "signed-in": {
      const study = await readStudySetting();
      return (
        <>
          <section
            aria-label="프로필"
            className="flex items-center gap-4 rounded-card bg-surface p-5"
          >
            <AccountAvatar email={session.email} size="large" />
            <p className="min-w-0 text-body-strong break-all">{session.email}</p>
          </section>
          <StudySetting setting={study} />
          <Display />
          <section aria-labelledby="account-section" className="flex flex-col gap-3">
            <h2 id="account-section" className="text-section text-ink-2">
              계정
            </h2>
            <SignOutForm />
          </section>
        </>
      );
    }
    case "unreachable":
      return (
        <>
          <div role="alert" className="flex flex-col gap-3">
            <p className="text-dont-know-text">
              서버에 연결할 수 없어요. 연결을 확인하고 다시 시도해 주세요.
            </p>
            <RetryButton />
          </div>
          <Display />
        </>
      );
    case "signed-out":
      redirect("/login");
  }
}

/** "화면": the theme the web is drawn in, which needs no server. */
function Display() {
  return (
    <section aria-labelledby="display-section" className="flex flex-col gap-3">
      <h2 id="display-section" className="text-section text-ink-2">
        화면
      </h2>
      <ThemeChoice labelledBy="display-section" />
    </section>
  );
}
