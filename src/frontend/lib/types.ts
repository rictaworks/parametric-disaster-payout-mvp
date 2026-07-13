export interface Plan { id: number; code: string; plan_type: 'seismic' | 'rainfall'; label: string }
export interface Station { id: number; code: string; plan_type: 'seismic' | 'rainfall'; label: string; prefecture: string }
export interface Threshold { code: string; label: string; value: number | string }
export interface PayoutTier { id: number; code: string; amount_jpy: number; label: string }
export interface WizardState {
  step: 1 | 2 | 3 | 4 | 5
  planId: number | null
  stationId: number | null
  threshold: string | null
  payoutTierId: number | null
  ageGroup: string | null
  recaptchaToken: string | null
}
export interface Policy {
  id: number
  status: string
  plan: Plan
  station: Station
  threshold: string
  payout_tier: PayoutTier
  created_at: string
  waiting_until: string
}

export interface PolicyCreateInput {
  plan_id: number
  station_id: number
  threshold: string | null
  payout_tier_id: number
  age_group: string | null
  recaptcha_token: string | null
  locale: string
}
