import { NextResponse } from 'next/server';

export async function proxyToRails(path: string, init?: RequestInit, searchParams?: URLSearchParams) {
  const baseUrl = process.env.RAILS_API_URL ?? 'http://127.0.0.1:3001';
  const secret = process.env.INTERNAL_API_SECRET ?? 'dev-secret';
  const url = new URL(path, baseUrl);

  if (searchParams) {
    searchParams.forEach((value, key) => url.searchParams.set(key, value));
  }

  const response = await fetch(url, {
    ...init,
    headers: {
      Authorization: 'Bearer ' + secret,
      'Content-Type': 'application/json',
      ...(init?.headers ?? {})
    },
    cache: 'no-store'
  });

  const body = await response.text();
  const contentType = response.headers.get('content-type') ?? 'application/json';

  return new NextResponse(body, {
    status: response.status,
    headers: {
      'content-type': contentType
    }
  });
}
