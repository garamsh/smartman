import type { ReactNode } from "react";

/**
 * A page's placeholder while the server answers: [children] drawn in its layout, pulsing unless
 * reduced motion is asked for, hidden from screen readers, which hear [status] instead. The
 * [className] lays it out as the content that replaces it is laid out, so nothing moves.
 */
export function Skeleton({
  status,
  className,
  children,
}: {
  status: string;
  className: string;
  children: ReactNode;
}) {
  return (
    <div aria-busy="true">
      <p role="status" className="sr-only">
        {status}
      </p>
      <div aria-hidden className={`${className} motion-safe:animate-skeleton`}>
        {children}
      </div>
    </div>
  );
}

/**
 * A line of text not yet read: a rounded bar [width] wide in a line box as tall as the type
 * style [text] gives it, so the line that replaces it takes the same height.
 */
export function SkeletonLine({
  text,
  width,
  tone = "bg-hairline",
}: {
  text: string;
  width: string;
  tone?: string;
}) {
  return (
    <span className={`flex items-center ${text} ${width}`}>
      {/* The zero-width space opens a line box of the type style's height. */}
      {"​"}
      <span className={`h-3 flex-1 rounded-full ${tone}`} />
    </span>
  );
}
