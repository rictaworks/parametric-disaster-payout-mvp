require "rails_helper"

RSpec.describe ExpirePolicies do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { User.create!(google_sub: "google-sub-expire-policies") }
  let(:plan) do
    Plan.create!(
      code: "seismic_expire_policies",
      trigger_type: "seismic",
      label_ja: "震度連動",
      label_en: "Seismic-linked",
      label_fr: "Seismic-linked",
      label_zh: "Seismic-linked",
      label_ru: "Seismic-linked",
      label_es: "Seismic-linked",
      label_ar: "Seismic-linked"
    )
  end
  let(:station) do
    Station.create!(
      code: "seismic_tokyo_expire_policies",
      measurement_type: "seismic",
      label_ja: "東京震度観測点",
      label_en: "Tokyo seismic station",
      label_fr: "Tokyo seismic station",
      label_zh: "Tokyo seismic station",
      label_ru: "Tokyo seismic station",
      label_es: "Tokyo seismic station",
      label_ar: "Tokyo seismic station"
    )
  end
  let(:payout_tier) do
    PayoutTier.create!(
      code: "ten_thousand_expire_policies",
      amount_yen: 10_000,
      label_ja: "1万円相当（模擬）",
      label_en: "Equivalent to JPY 10,000",
      label_fr: "Equivalent to JPY 10,000",
      label_zh: "Equivalent to JPY 10,000",
      label_ru: "Equivalent to JPY 10,000",
      label_es: "Equivalent to JPY 10,000",
      label_ar: "Equivalent to JPY 10,000"
    )
  end

  let!(:pending_status) { PolicyStatus.create!(code: "pending", sort_order: 0, label_ja: "待機中", label_en: "Pending", label_fr: "Pending", label_zh: "Pending", label_ru: "Pending", label_es: "Pending", label_ar: "Pending") }
  let!(:active_status) { PolicyStatus.create!(code: "active", sort_order: 1, label_ja: "有効", label_en: "Active", label_fr: "Active", label_zh: "Active", label_ru: "Active", label_es: "Active", label_ar: "Active") }
  let!(:processing_status) { PolicyStatus.create!(code: "processing", sort_order: 2, label_ja: "支払処理中", label_en: "Processing", label_fr: "Processing", label_zh: "Processing", label_ru: "Processing", label_es: "Processing", label_ar: "Processing") }
  let!(:cap_reached_status) { PolicyStatus.create!(code: "cap_reached", sort_order: 3, label_ja: "上限到達", label_en: "Cap reached", label_fr: "Cap reached", label_zh: "Cap reached", label_ru: "Cap reached", label_es: "Cap reached", label_ar: "Cap reached") }
  let!(:cancelled_status) { PolicyStatus.create!(code: "cancelled", sort_order: 4, label_ja: "解約", label_en: "Cancelled", label_fr: "Cancelled", label_zh: "Cancelled", label_ru: "Cancelled", label_es: "Cancelled", label_ar: "Cancelled") }
  let!(:expired_status) { PolicyStatus.create!(code: "expired", sort_order: 5, label_ja: "失効", label_en: "Expired", label_fr: "Expired", label_zh: "Expired", label_ru: "Expired", label_es: "Expired", label_ar: "Expired") }

  let(:service_now) { Time.zone.parse("2026-07-16 10:00:00") }

  def build_policy(policy_status:)
    Policy.create!(
      user: user,
      plan: plan,
      station: station,
      payout_tier: payout_tier,
      policy_status: policy_status,
      threshold: "5強"
    ).tap do |policy|
      policy.update_columns(
        waiting_until: Time.zone.parse("2025-12-31 09:00:00"),
        expires_at: Time.zone.parse("2026-07-15 09:00:00")
      )
    end
  end

  it "expires active and cap_reached policies whose expires_at has passed" do
    active_policy = build_policy(policy_status: active_status)
    cap_reached_policy = build_policy(policy_status: cap_reached_status)

    travel_to(service_now) do
      result = described_class.call

      expect(result).to be_success
      expect(result.updated_count).to eq(2)
    end

    expect(active_policy.reload.policy_status).to eq(expired_status)
    expect(cap_reached_policy.reload.policy_status).to eq(expired_status)
  end

  it "does not expire policies that are still pending during the waiting period" do
    pending_policy = build_policy(policy_status: pending_status)

    travel_to(service_now) do
      described_class.call
    end

    expect(pending_policy.reload.policy_status).to eq(pending_status)
  end

  it "does not expire cancelled policies" do
    cancelled_policy = build_policy(policy_status: cancelled_status)
    cancelled_policy.update_columns(terminated_at: Time.zone.parse("2026-07-15 08:59:59"))

    travel_to(service_now) do
      described_class.call
    end

    expect(cancelled_policy.reload.policy_status).to eq(cancelled_status)
  end
end
