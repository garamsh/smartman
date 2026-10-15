import Link from "next/link";
import { redirect } from "next/navigation";

import { AccountAvatar, getSession } from "@/features/auth";

/** The signed-in account's avatar, which opens the account page. */
export async function AccountLink() {
  const session = await getSession();
  if (session.kind === "signed-out") redirect("/login");
  return (
    <Link
      href="/account"
      aria-label="계정"
      className="flex size-tap-target items-center justify-center rounded-full focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink"
    >
      <AccountAvatar email={session.kind === "signed-in" ? session.email : null} size="small" />
    </Link>
  );
}
