/** The cookie the browser names its IANA time zone in, for the server to read the study day. */
export const timeZoneCookie = "smartman-tz";

/** The zone the server reads the study day in while the browser has named none. */
export const fallbackTimeZone = "Asia/Seoul";

/**
 * The script the root layout puts in `<head>`. It runs on every page, the sign-in page
 * included, so the cookie is set before any page that counts the day is requested; it keeps
 * the zone current when the browser's changes. A browser that cannot tell its zone sets none.
 */
export const timeZoneScript = `try{var z=Intl.DateTimeFormat().resolvedOptions().timeZone;if(z)document.cookie=${JSON.stringify(`${timeZoneCookie}=`)}+encodeURIComponent(z)+"; path=/; max-age=31536000; samesite=lax"}catch(e){}`;

/** The zone [value] names when it is one this runtime knows; otherwise [fallbackTimeZone]. */
export function parseTimeZone(value: string | undefined): string {
  if (!value) return fallbackTimeZone;
  try {
    return new Intl.DateTimeFormat("en-US", { timeZone: value }).resolvedOptions().timeZone;
  } catch {
    // A RangeError: the cookie names no zone this runtime knows.
    return fallbackTimeZone;
  }
}
