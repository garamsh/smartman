import type { Metadata } from "next";
import { Suspense } from "react";

import { SignInButton } from "@/features/auth";

import { CallbackError } from "./_components/callback-error";

export const metadata: Metadata = { title: "로그인 · smartman" };

/** The sign-in page: the only page a signed-out visitor can open. */
export default function LoginPage({ searchParams }: PageProps<"/login">) {
  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-sm flex-col justify-center gap-8 px-6">
      <h1 className="text-3xl font-bold">smartman</h1>
      <div className="flex flex-col gap-3">
        <SignInButton />
        <Suspense>
          <CallbackError searchParams={searchParams} />
        </Suspense>
      </div>
    </main>
  );
}
