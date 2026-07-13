import type { PayoutTier, Plan, Policy, PolicyCreateInput, Station } from '@/lib/types';

class ApiError extends Error {
  status: number;

  constructor(message: string, status: number) {
    super(message);
    this.status = status;
  }
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(path, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...(init?.headers ?? {})
    },
    cache: 'no-store'
  });

  const data = await response.json().catch(() => null);

  if (!response.ok) {
    throw new ApiError(data?.error ?? 'RequestFailed', response.status);
  }

  return data as T;
}

export const fetchPlans = (locale: string) => request<Plan[]>(`/api/master/plans?locale=${locale}`);
export const fetchStations = (locale: string) => request<Station[]>(`/api/master/stations?locale=${locale}`);
export const fetchPayoutTiers = (locale: string) => request<PayoutTier[]>(`/api/master/payout_tiers?locale=${locale}`);
export const fetchPolicies = (locale: string) => request<Policy[]>(`/api/policies?locale=${locale}`);
export const createPolicy = (payload: PolicyCreateInput) =>
  request<Policy>('/api/policies', {
    method: 'POST',
    body: JSON.stringify(payload)
  });
