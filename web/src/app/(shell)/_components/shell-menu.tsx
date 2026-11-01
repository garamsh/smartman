"use client";

import { ChartColumn, Layers, type LucideIcon, Sun } from "lucide-react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import type { ReactNode } from "react";

import { BrandMark } from "@/design/brand";

/** A page the menus open, and whether a path is that page or below it. */
type Item = { href: string; label: string; Icon: LucideIcon; current: (path: string) => boolean };

const items: readonly Item[] = [
  { href: "/", label: "오늘", Icon: Sun, current: (path) => path === "/" },
  { href: "/decks", label: "덱", Icon: Layers, current: (path) => path.startsWith("/decks") },
  {
    href: "/record",
    label: "기록",
    Icon: ChartColumn,
    current: (path) => path.startsWith("/record"),
  },
];

const focus = "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink";

/**
 * The menu from 1024 px wide: the lockup, 오늘, 덱 and 기록, the current one on the brand tint,
 * and [account], the account's link, at its foot.
 */
export function SideMenu({ account }: { account: ReactNode }) {
  return <SideMenuAt path={usePathname()} account={account} />;
}

/**
 * [SideMenu] at [path], or with no page current while the path is not yet known. Its column takes
 * the surface and the border down the page's whole height, and the menu inside it stays pinned in
 * view as the page scrolls (ADR 0038).
 */
export function SideMenuAt({ path, account }: { path: string | null; account: ReactNode }) {
  return (
    <div className="hidden w-60 shrink-0 border-r border-hairline bg-surface lg:block">
      <nav aria-label="주 메뉴" className="sticky top-0 flex h-dvh flex-col gap-1.5 px-4 py-7">
        <Link
          href="/"
          aria-label="알아몰라, 오늘"
          className={`mx-2.5 mb-5 self-start rounded-field ${focus}`}
        >
          <BrandMark mark="lockup" alt="" className="h-7 w-auto" />
        </Link>
        {items.map(({ href, label, Icon, current }) => {
          const selected = path !== null && current(path);
          return (
            <Link
              key={href}
              href={href}
              aria-current={selected ? "page" : undefined}
              className={`pressable flex min-h-tap-target items-center gap-3 rounded-field px-3 text-label ${selected ? "bg-brand-tint text-ink" : "font-semibold text-ink-2"} ${focus}`}
            >
              <Icon aria-hidden className="size-5" strokeWidth={selected ? 2.2 : 2} />
              {label}
            </Link>
          );
        })}
        <span className="min-h-4 flex-1" />
        {account}
      </nav>
    </div>
  );
}

/** The menu below 1024 px wide: 오늘, 덱 and 기록 in a bar at the foot, the current one in ink. */
export function TabBar() {
  return <TabBarAt path={usePathname()} />;
}

/** [TabBar] at [path], or with no page current while the path is not yet known. */
export function TabBarAt({ path }: { path: string | null }) {
  return (
    <nav
      aria-label="주 메뉴"
      className="fixed inset-x-0 bottom-0 z-10 grid h-16 grid-cols-3 border-t border-hairline bg-surface lg:hidden"
    >
      {items.map(({ href, label, Icon, current }) => {
        const selected = path !== null && current(path);
        return (
          <Link
            key={href}
            href={href}
            aria-current={selected ? "page" : undefined}
            className={`pressable flex flex-col items-center justify-center gap-0.5 text-micro ${selected ? "font-bold text-ink" : "font-semibold text-muted"} ${focus} focus-visible:-outline-offset-2`}
          >
            <Icon aria-hidden className="size-6" strokeWidth={selected ? 2.2 : 2} />
            {label}
          </Link>
        );
      })}
    </nav>
  );
}
