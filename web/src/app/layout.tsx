import type { Metadata } from "next";
import localFont from "next/font/local";

import "@/styles/globals.css";

// src/styles/fonts links to app/assets/fonts, so the app and the web share one copy.
const pretendard = localFont({
  src: [
    { path: "../styles/fonts/Pretendard-Regular.otf", weight: "400" },
    { path: "../styles/fonts/Pretendard-Medium.otf", weight: "500" },
    { path: "../styles/fonts/Pretendard-SemiBold.otf", weight: "600" },
    { path: "../styles/fonts/Pretendard-Bold.otf", weight: "700" },
    { path: "../styles/fonts/Pretendard-ExtraBold.otf", weight: "800" },
  ],
  variable: "--font-pretendard",
  display: "swap",
});

export const metadata: Metadata = {
  title: "smartman",
  description: "카드로 외우는 암기 앱",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="ko" className={`${pretendard.variable} antialiased`}>
      <body className="bg-ground font-sans text-ink">{children}</body>
    </html>
  );
}
