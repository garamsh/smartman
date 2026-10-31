import { redirect } from "next/navigation";

import { RetryButton } from "@/design/retry-button";
import { ThemeChoice } from "@/design/theme-choice";
import { getSession, SignOutForm } from "@/features/account";

import { AiConnection } from "./ai-connection";
import { readStudySetting, StudySetting } from "./study-setting";

/**
 * The settings read on the server, each section one group under its label, as the phone's 설정
 * draws them: "계정", the signed-in email and sign-out; "학습", the daily study minutes; "AI 연결",
 * the MCP server's address; and "화면", the theme the web is drawn in. While the server cannot be
 * reached, "다시 시도", AI 연결 and the theme.
 */
export async function Profile() {
  const session = await getSession();
  switch (session.kind) {
    case "signed-in": {
      const study = await readStudySetting();
      return (
        <>
          <section aria-labelledby="account-section" className="flex flex-col gap-2">
            <h2 id="account-section" className="px-1 text-section text-muted">
              계정
            </h2>
            <div className="flex flex-col divide-y divide-hairline rounded-group bg-surface">
              <p className="min-w-0 px-4 py-3 text-body-strong break-all">{session.email}</p>
              <SignOutForm />
            </div>
          </section>
          <StudySetting setting={study} />
          <AiConnection />
          <Display />
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
          <AiConnection />
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
    <section aria-labelledby="display-section" className="flex flex-col gap-2">
      <h2 id="display-section" className="px-1 text-section text-muted">
        화면
      </h2>
      <ThemeChoice labelledBy="display-section" />
    </section>
  );
}
