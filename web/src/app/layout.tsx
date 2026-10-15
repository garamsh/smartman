import type { Metadata } from "next";
import localFont from "next/font/local";

import "@/styles/globals.css";

// src/styles/fonts links to app/assets/fonts, so the app and the web share one copy.
const plexSansKr = localFont({
  src: [
    { path: "../styles/fonts/IBMPlexSansKR-Regular.ttf", weight: "400" },
    { path: "../styles/fonts/IBMPlexSansKR-Medium.ttf", weight: "500" },
    { path: "../styles/fonts/IBMPlexSansKR-SemiBold.ttf", weight: "600" },
    { path: "../styles/fonts/IBMPlexSansKR-Bold.ttf", weight: "700" },
  ],
  variable: "--font-plex-sans-kr",
  display: "swap",
});

export const metadata: Metadata = {
  title: "smartman",
  description: "카드로 외우는 암기 앱",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="ko" className={`${plexSansKr.variable} antialiased`}>
      <body className="bg-ground font-sans text-ink">{children}</body>
    </html>
  );
}
