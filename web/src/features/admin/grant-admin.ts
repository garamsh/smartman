"use server";

import { revalidatePath } from "next/cache";

import { call, failureMessages } from "./action-call";

/** What the grant form shows after an attempt. */
export type GrantState = { message: string | null };

/** Makes the existing user with the form's `email` an admin. */
export async function grantAdmin(_previous: GrantState, form: FormData): Promise<GrantState> {
  const email = form.get("email");
  if (typeof email !== "string" || email.trim() === "") {
    return { message: "이메일을 입력해 주세요." };
  }
  const result = await call("admin_grant_admin", { email: email.trim() });
  if ("failure" in result) return { message: failureMessages[result.failure] };
  switch (result.data) {
    case "granted":
      revalidatePath("/admin", "layout");
      return { message: `${email.trim()}님을 관리자로 지정했어요.` };
    case "already":
      return { message: "이미 관리자예요." };
    case "no_user":
      return { message: "이 이메일로 가입한 사용자가 없어요." };
    default:
      return { message: failureMessages.unreadable };
  }
}
