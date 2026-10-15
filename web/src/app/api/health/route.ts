/** Answers 200 while the server runs, without touching Supabase: the container's liveness check. */
export function GET() {
  return Response.json({ status: "ok" });
}
