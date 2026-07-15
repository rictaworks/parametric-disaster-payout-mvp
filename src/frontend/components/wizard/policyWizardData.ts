export const POLICY_WIZARD_STORAGE_KEY = "parametric_latest_policy_application";

export const POLICY_PLAN_OPTIONS = [
  { id: 1, key: "seismic" },
  { id: 2, key: "rainfall" },
] as const;

export type PolicyPlanKey = (typeof POLICY_PLAN_OPTIONS)[number]["key"];

export const POLICY_STATION_OPTIONS = {
  seismic: [
    { id: 1, key: "seismic_tokyo" },
    { id: 2, key: "seismic_osaka" },
  ],
  rainfall: [{ id: 3, key: "rainfall_tokyo" }],
} as const satisfies Record<PolicyPlanKey, readonly { id: number; key: string }[]>;

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
  { id: 1, key: "ten_thousand" },
  { id: 2, key: "thirty_thousand" },
] as const;

export const POLICY_AGE_GROUP_OPTIONS = [
  { value: "", key: "unspecified" },
  { value: "under_30", key: "under30" },
  { value: "30s", key: "thirties" },
  { value: "40s", key: "forties" },
  { value: "50plus", key: "fiftyPlus" },
] as const;

export type PolicyAgeGroupValue = (typeof POLICY_AGE_GROUP_OPTIONS)[number]["value"];

export type PolicyApplicationRecord = {
  policyId: number;
  statusKey: "pending";
  statusLabel: string;
  planId: number;
  planLabel: string;
  stationId: number;
  stationLabel: string;
  thresholdValue: string;
  thresholdLabel: string;
  payoutTierId: number;
  payoutTierLabel: string;
  ageGroupValue: PolicyAgeGroupValue;
  ageGroupLabel: string;
  submittedAt: string;
};

