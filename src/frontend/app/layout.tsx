import type { Metadata } from "next";
import { AppShell } from "@/components/AppShell";
import ja from "@/locales/ja.json";
import "./globals.css";

export const metadata: Metadata = {
  title: ja.app.title,
  description: ja.banner.notice,
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="ja">
      <body>
        <AppShell>{children}</AppShell>
      </body>
    </html>
  );
}
