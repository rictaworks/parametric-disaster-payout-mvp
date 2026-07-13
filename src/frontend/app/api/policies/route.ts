import { getServerSession } from 'next-auth';
import { NextResponse } from 'next/server';
import { authOptions } from '@/lib/auth';
import { proxyToRails } from '@/lib/server-api';

export async function GET(request: Request) {
  const session = await getServerSession(authOptions);
  if (!session?.googleSub) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const { searchParams } = new URL(request.url);
  searchParams.set('google_sub', session.googleSub);
  return proxyToRails('/api/v1/policies', { method: 'GET' }, searchParams);
}

export async function POST(request: Request) {
  const session = await getServerSession(authOptions);
  if (!session?.googleSub) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const payload = await request.json();
  const body = JSON.stringify({ ...payload, google_sub: session.googleSub });
  return proxyToRails('/api/v1/policies', { method: 'POST', body });
}
