require "rails_helper"

RSpec.describe Payout do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { User.create!(google_sub: "google-sub-payout-spec") }

  let(:plan) do
    Plan.create!(
      code: "seismic_payout_spec",
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
      code: "seismic_tokyo_payout_spec",
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
      code: "ten_thousand_payout_spec",
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

  let!(:active_status) { PolicyStatus.find_or_create_by!(code: "active", sort_order: 1, label_ja: "有効", label_en: "Active", label_fr: "Active", label_zh: "Active", label_ru: "Active", label_es: "Active", label_ar: "Active") }
  let!(:processing_status) { PolicyStatus.find_or_create_by!(code: "processing", sort_order: 2, label_ja: "支払処理中", label_en: "Processing", label_fr: "Processing", label_zh: "Processing", label_ru: "Processing", label_es: "Processing", label_ar: "Processing") }
  let!(:cap_reached_status) { PolicyStatus.find_or_create_by!(code: "cap_reached", sort_order: 3, label_ja: "上限到達", label_en: "Cap reached", label_fr: "Cap reached", label_zh: "Cap reached", label_ru: "Cap reached", label_es: "Cap reached", label_ar: "Cap reached") }
  let!(:cancelled_status) { PolicyStatus.find_or_create_by!(code: "cancelled", sort_order: 4, label_ja: "解約", label_en: "Cancelled", label_fr: "Cancelled", label_zh: "Cancelled", label_ru: "Cancelled", label_es: "Cancelled", label_ar: "Cancelled") }
  let!(:expired_status) { PolicyStatus.find_or_create_by!(code: "expired", sort_order: 5, label_ja: "失効", label_en: "Expired", label_fr: "Expired", label_zh: "Expired", label_ru: "Expired", label_es: "Expired", label_ar: "Expired") }

  let!(:ordered_payout_status) { PayoutStatus.find_or_create_by!(code: "ordered", sort_order: 0, label_ja: "指図済", label_en: "Ordered", label_fr: "Ordered", label_zh: "Ordered", label_ru: "Ordered", label_es: "Ordered", label_ar: "Ordered") }
  let!(:completed_payout_status) { PayoutStatus.find_or_create_by!(code: "completed_simulated", sort_order: 1, label_ja: "支払完了（模擬）", label_en: "Completed", label_fr: "Completed", label_zh: "Completed", label_ru: "Completed", label_es: "Completed", label_ar: "Completed") }
  let!(:invalid_payout_status) { PayoutStatus.find_or_create_by!(code: "invalid", sort_order: 2, label_ja: "無効", label_en: "Invalid", label_fr: "Invalid", label_zh: "Invalid", label_ru: "Invalid", label_es: "Invalid", label_ar: "Invalid") }

  let!(:seismic_level_5_strong) { SeismicIntensityLevel.find_or_create_by!(code: "5_strong_payout_spec", sort_order: 6, label_ja: "5強", label_en: "5 strong", label_fr: "5 strong", label_zh: "5 strong", label_ru: "5 strong", label_es: "5 strong", label_ar: "5 strong") }

  let!(:policy) do
    Policy.create!(
      user: user,
      plan: plan,
      station: station,
      payout_tier: payout_tier,
      policy_status: processing_status,
      threshold: "5強"
    ).tap do |p|
      p.update_columns(
        waiting_until: Time.zone.parse("2025-12-31 09:00:00"),
        expires_at: Time.zone.parse("2027-07-15 09:00:00")
      )
    end
  end

  let!(:observation) do
    Observation.create!(
      station: station,
      event_id: "event-payout-spec-001",
      observed_at: Time.zone.parse("2026-07-15 10:00:00"),
      seismic_intensity_level: seismic_level_5_strong,
      max_value: seismic_level_5_strong.sort_order,
      simulated: false
    )
  end

  let!(:payout) do
    Payout.create!(
      policy: policy,
      payout_tier: payout_tier,
      payout_status: ordered_payout_status,
      observation: observation,
      idempotency_key: "policy_#{policy.id}_event_event-payout-spec-001",
      decided_at: Time.current
    )
  end

  describe "#update_policy_status_on_state_change" do
    it "transitions the policy to active when a payout completes normally" do
      payout.update!(payout_status: completed_payout_status)
      expect(policy.reload.policy_status).to eq(active_status)
    end

    it "transitions the policy to active when a payout is invalidated normally" do
      payout.update!(payout_status: invalid_payout_status)
      expect(policy.reload.policy_status).to eq(active_status)
    end

    it "does not overwrite a cancelled policy when the payout completes afterwards" do
      policy.update_columns(policy_status_id: cancelled_status.id, terminated_at: Time.current)

      payout.update!(payout_status: completed_payout_status)

      expect(policy.reload.policy_status).to eq(cancelled_status)
    end

    it "does not overwrite an expired policy when the payout is invalidated afterwards" do
      policy.update_columns(policy_status_id: expired_status.id)

      payout.update!(payout_status: invalid_payout_status)

      expect(policy.reload.policy_status).to eq(expired_status)
    end

    context "when the policy has another payout that is still ordered" do
      let!(:observation2) do
        Observation.create!(
          station: station,
          event_id: "event-payout-spec-002",
          observed_at: Time.zone.parse("2026-07-15 11:00:00"),
          seismic_intensity_level: seismic_level_5_strong,
          max_value: seismic_level_5_strong.sort_order,
          simulated: false
        )
      end

      let!(:other_payout) do
        Payout.create!(
          policy: policy,
          payout_tier: payout_tier,
          payout_status: ordered_payout_status,
          observation: observation2,
          idempotency_key: "policy_#{policy.id}_event_event-payout-spec-002",
          decided_at: Time.current
        )
      end

      it "keeps the policy in processing when one payout is invalidated but the other is still ordered" do
        payout.update!(payout_status: invalid_payout_status)

        expect(policy.reload.policy_status).to eq(processing_status)
      end

      it "keeps the policy in processing when one payout completes but the other is still ordered" do
        payout.update!(payout_status: completed_payout_status)

        expect(policy.reload.policy_status).to eq(processing_status)
      end

      it "resolves to active once all payouts are settled and the annual count stays below the cap" do
        payout.update!(payout_status: invalid_payout_status)
        other_payout.update!(payout_status: completed_payout_status)

        expect(policy.reload.policy_status).to eq(active_status)
      end

      it "resolves to cap_reached once all payouts are settled and the annual count reaches the cap" do
        payout.update!(payout_status: completed_payout_status)
        other_payout.update!(payout_status: completed_payout_status)

        expect(policy.reload.policy_status).to eq(cap_reached_status)
      end
    end

    context "when a payout from a previous year is finally settled after this year's cap is already reached" do
      let!(:observation_this_year_1) do
        Observation.create!(
          station: station,
          event_id: "event-payout-spec-this-year-1",
          observed_at: Time.zone.parse("2026-02-01 10:00:00"),
          seismic_intensity_level: seismic_level_5_strong,
          max_value: seismic_level_5_strong.sort_order,
          simulated: false
        )
      end

      let!(:observation_this_year_2) do
        Observation.create!(
          station: station,
          event_id: "event-payout-spec-this-year-2",
          observed_at: Time.zone.parse("2026-03-01 10:00:00"),
          seismic_intensity_level: seismic_level_5_strong,
          max_value: seismic_level_5_strong.sort_order,
          simulated: false
        )
      end

      let!(:payout_this_year_1) do
        Payout.create!(
          policy: policy,
          payout_tier: payout_tier,
          payout_status: completed_payout_status,
          observation: observation_this_year_1,
          idempotency_key: "policy_#{policy.id}_event_event-payout-spec-this-year-1",
          decided_at: observation_this_year_1.observed_at
        )
      end

      let!(:payout_this_year_2) do
        Payout.create!(
          policy: policy,
          payout_tier: payout_tier,
          payout_status: completed_payout_status,
          observation: observation_this_year_2,
          idempotency_key: "policy_#{policy.id}_event_event-payout-spec-this-year-2",
          decided_at: observation_this_year_2.observed_at
        )
      end

      it "counts using the current year, not the settled payout's own (previous year) observation year" do
        # payout（let!）は前年（2025年）の観測に紐づいた、まだ ordered のままの支払
        policy.update_columns(waiting_until: Time.zone.parse("2025-01-01 00:00:00"))
        payout.observation.update_columns(observed_at: Time.zone.parse("2025-12-20 10:00:00"))

        travel_to Time.zone.parse("2026-07-15 12:00:00") do
          payout.update!(payout_status: invalid_payout_status)

          # 前年分は無効化されたので、当年の集計（2件・上限到達）に基づき cap_reached になるべき。
          # 支払が紐づく観測の年（2025年）で集計してしまうと、当年の実績が無視され
          # 誤って active に遷移してしまう
          expect(policy.reload.policy_status).to eq(cap_reached_status)
        end
      end
    end

    context "when the policy's coverage period has already ended while still processing" do
      before do
        policy.update_columns(expires_at: 1.day.ago)
      end

      it "transitions the policy to expired instead of active when the payout completes" do
        payout.update!(payout_status: completed_payout_status)

        expect(policy.reload.policy_status).to eq(expired_status)
      end

      it "transitions the policy to expired instead of active when the payout is invalidated" do
        payout.update!(payout_status: invalid_payout_status)

        expect(policy.reload.policy_status).to eq(expired_status)
      end
    end
  end
end
