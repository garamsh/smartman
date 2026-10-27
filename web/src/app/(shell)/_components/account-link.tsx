import Link from "next/link";
import { redirect } from "next/navigation";

import { AccountAvatar, getSession } from "@/features/account";

/**
 * The signed-in account's avatar, which opens the account page; [labelled], as the side menu
 * shows it, with "설정" beside it.
 */
export async function AccountLink({ labelled = false }: { labelled?: boolean }) {
  const session = await getSession();
  if (session.kind === "signed-out") redirect("/login");
  const avatar = (
    <AccountAvatar email={session.kind === "signed-in" ? session.email : null} size="small" />
  );
  if (labelled) {
    return (
      <Link
        href="/account"
        className="pressable flex min-h-13 items-center gap-2.5 rounded-field px-2.5 text-secondary font-semibold text-ink focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink"
      >
        {avatar}
        설정
      </Link>
    );
  }
  return (
    <Link
      href="/account"
      aria-label="설정"
      className="pressable flex size-tap-target items-center justify-center rounded-full focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink"
    >
      {avatar}
    </Link>
  );
}
