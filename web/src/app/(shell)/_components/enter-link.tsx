"use client";

import { Play } from "lucide-react";
import Link from "next/link";
import { useEffect, useRef } from "react";

/**
 * The page's one study button, [label], which opens [href], showing its Enter key from 1024 px
 * wide: white on a navy card, or with [primary] the navy fill on the page's ground. Enter opens it
 * from anywhere on the page but a control or a field, which keep their own Enter.
 */
export function EnterLink({
  href,
  label,
  primary = false,
}: {
  href: string;
  label: string;
  primary?: boolean;
}) {
  const link = useRef<HTMLAnchorElement>(null);
  useEffect(() => {
    const listener = (event: KeyboardEvent) => {
      if (event.key !== "Enter" || event.isComposing || event.altKey || event.ctrlKey) return;
      if (event.metaKey || event.shiftKey) return;
      const target = event.target;
      if (
        target instanceof Element &&
        target.closest("a, button, input, select, textarea, [role]")
      ) {
        return;
      }
      event.preventDefault();
      link.current?.click();
    };
    window.addEventListener("keydown", listener);
    return () => {
      window.removeEventListener("keydown", listener);
    };
  }, []);
  return (
    <Link
      ref={link}
      href={href}
      aria-keyshortcuts="Enter"
      className={`pressable flex min-h-cta items-center justify-center gap-2 rounded-button px-6 text-label focus-visible:outline-2 focus-visible:outline-offset-2 ${
        primary
          ? "bg-ink text-on-primary focus-visible:outline-ink lg:col-span-2"
          : "bg-on-hero text-brand focus-visible:outline-on-hero flex-[1_1_100%] whitespace-nowrap sm:min-w-60 sm:flex-none"
      }`}
    >
      <Play aria-hidden className="size-small-icon" strokeWidth={2} />
      {label}
      <kbd
        aria-hidden
        className="hidden rounded-md border border-outline px-1.5 text-micro font-bold lg:inline"
      >
        Enter
      </kbd>
    </Link>
  );
}
