"use client";

import { Play } from "lucide-react";
import Link from "next/link";
import { useEffect, useRef } from "react";

/**
 * The page's one study button, [label], which opens [href], showing its Enter key from 1024 px
 * wide. Enter opens it from anywhere on the page but a control or a field, which keep their own
 * Enter.
 */
export function EnterLink({ href, label }: { href: string; label: string }) {
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
      className="pressable flex min-h-cta items-center justify-center gap-2 rounded-button bg-on-hero px-6 text-label text-brand focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-on-hero flex-[1_1_100%] sm:flex-[0_1_240px]"
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
