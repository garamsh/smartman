import { Suspense } from "react";

import { AdminGate } from "./_components/admin-gate";

/**
 * The admin area (ADR 0070), inside the shell. Nothing of it renders until the server says the
 * signed-in user is an admin; anyone else gets the not-found page, as for an address that does
 * not exist.
 */
export default function AdminLayout({ children }: LayoutProps<"/admin">) {
  return (
    <Suspense fallback={null}>
      <AdminGate>{children}</AdminGate>
    </Suspense>
  );
}
