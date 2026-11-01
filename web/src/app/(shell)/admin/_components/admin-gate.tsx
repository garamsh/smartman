import { notFound } from "next/navigation";
import type { ReactNode } from "react";

import { AdminNav, readIsAdmin } from "@/features/admin";

/**
 * [children] under the admin area's menu for an admin; the not-found page for anyone else. A
 * server that cannot answer is an error, which says nothing of the area.
 */
export async function AdminGate({ children }: { children: ReactNode }) {
  const admin = await readIsAdmin();
  if (admin === false) notFound();
  if (admin !== true) throw new Error(`the admin check failed: ${admin.failure}`);
  return (
    <>
      <AdminNav />
      {children}
    </>
  );
}
