import type { Metadata } from "next";
import Script from "next/script";
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
        {/* GA4（RictaWorks 全デモ共通タグ） */}
        <Script
          src="https://www.googletagmanager.com/gtag/js?id=G-C04W1XKS16"
          strategy="afterInteractive"
        />
        <Script id="ga4" strategy="afterInteractive">
          {`
            window.dataLayer = window.dataLayer || [];
            function gtag(){dataLayer.push(arguments);}
            gtag('js', new Date());
            gtag('config', 'G-C04W1XKS16');
          `}
        </Script>
        <AppShell>{children}</AppShell>
      </body>
    </html>
  );
}
