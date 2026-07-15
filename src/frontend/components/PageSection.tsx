"use client";

import type { ReactNode } from "react";

export function PageSection({
  title,
  description,
  children,
}: {
  title: string;
  description: string;
  children: ReactNode;
}) {
  return (
    <section className="page-section panel">
      <div className="page-section__header">
        <h1>{title}</h1>
        <p>{description}</p>
      </div>
      {children}
    </section>
  );
}
