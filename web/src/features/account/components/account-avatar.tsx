/**
 * The account's initial in a circle: the primary fill with its text colour, cocoa in the light
 * theme and inverted in the dark one. Decorative; the control around it carries the name.
 */
export function AccountAvatar({ email, size }: { email: string | null; size: "small" | "large" }) {
  const initial = email?.trim().charAt(0).toLocaleUpperCase() ?? "";
  return (
    <span
      aria-hidden
      className={`flex shrink-0 items-center justify-center rounded-full bg-ink text-on-ink ${
        size === "small" ? "size-small-avatar text-label" : "size-avatar text-title"
      }`}
    >
      {initial}
    </span>
  );
}
