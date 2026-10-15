/**
 * The path [action] redirected to by throwing Next.js's redirect error, or a failure when it
 * returned instead or threw anything else.
 */
export async function redirectTarget(action: Promise<unknown>): Promise<string> {
  const thrown = await action.then(
    (value: unknown) => {
      throw new Error(`expected a redirect, got ${JSON.stringify(value)}`);
    },
    (error: unknown) => error,
  );
  // redirect() throws an error whose digest is "NEXT_REDIRECT;<type>;<url>;<status>;".
  const digest =
    typeof thrown === "object" && thrown !== null && "digest" in thrown ? thrown.digest : null;
  const [kind, , url] = typeof digest === "string" ? digest.split(";") : [];
  if (kind !== "NEXT_REDIRECT" || url === undefined) throw thrown;
  return url;
}
