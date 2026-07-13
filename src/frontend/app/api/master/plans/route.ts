import { proxyToRails } from '@/lib/server-api';

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  return proxyToRails('/api/v1/plans', { method: 'GET' }, searchParams);
}
