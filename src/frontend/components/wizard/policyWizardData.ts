export const POLICY_PLAN_OPTIONS = [
  { code: "seismic", key: "seismic" },
  { code: "rainfall", key: "rainfall" },
] as const;

export type PolicyPlanKey = (typeof POLICY_PLAN_OPTIONS)[number]["key"];

export const POLICY_STATION_OPTIONS = {
  seismic: [
    { code: "seismic_tokyo", key: "seismic_tokyo" },
    { code: "seismic_osaka", key: "seismic_osaka" },
  ],
  rainfall: [{ code: "rainfall_tokyo", key: "rainfall_tokyo" }],
} as const satisfies Record<PolicyPlanKey, readonly { code: string; key: string }[]>;

export const POLICY_THRESHOLD_OPTIONS = {
  seismic: [
    { value: "0", key: "seismic_0" },
    { value: "1", key: "seismic_1" },
    { value: "2", key: "seismic_2" },
    { value: "3", key: "seismic_3" },
    { value: "4", key: "seismic_4" },
    { value: "5弱", key: "seismic_5_weak" },
    { value: "5強", key: "seismic_5_strong" },
    { value: "6弱", key: "seismic_6_weak" },
    { value: "6強", key: "seismic_6_strong" },
    { value: "7", key: "seismic_7" },
  ],
  rainfall: [
    { value: "10 mm", key: "rainfall_10" },
    { value: "20 mm", key: "rainfall_20" },
    { value: "30 mm", key: "rainfall_30" },
    { value: "50 mm", key: "rainfall_50" },
    { value: "80 mm", key: "rainfall_80" },
  ],
} as const satisfies Record<PolicyPlanKey, readonly { value: string; key: string }[]>;

export const POLICY_PAYOUT_TIER_OPTIONS = [
  { code: "ten_thousand", key: "ten_thousand" },
  { code: "thirty_thousand", key: "thirty_thousand" },
] as const;

export const POLICY_AGE_GROUP_OPTIONS = [
  { value: "", key: "unspecified" },
  { value: "under_30", key: "under30" },
  { value: "30s", key: "thirties" },
  { value: "40s", key: "forties" },
  { value: "50plus", key: "fiftyPlus" },
] as const;

export type PolicyAgeGroupValue = (typeof POLICY_AGE_GROUP_OPTIONS)[number]["value"];

export type MasterPlan = { id: number; code: string; trigger_type: string };
export type MasterStation = { id: number; code: string; measurement_type: string };
export type MasterPayoutTier = { id: number; code: string; amount_yen: number };

export type PolicyMasters = {
  plans: MasterPlan[];
  stations: MasterStation[];
  payoutTiers: MasterPayoutTier[];
};

export async function fetchPolicyMasters(): Promise<PolicyMasters> {
  const response = await fetch("/api/v1/masters");

  if (!response.ok) {
    throw new Error("Failed to load policy masters");
  }

  const body = (await response.json()) as {
    plans: MasterPlan[];
    stations: MasterStation[];
    payout_tiers: MasterPayoutTier[];
  };

  return {
    plans: body.plans,
    stations: body.stations,
    payoutTiers: body.payout_tiers,
  };
}
