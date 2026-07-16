require "rails_helper"

RSpec.describe ExecutePayout do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { User.create!(google_sub: "google-sub-execute-payout") }
  let(:plan) do
    Plan.create!(
      code: "seismic_execute_payout_spec",
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
      code: "seismic_tokyo_execute_payout_spec",
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
      code: "ten_thousand_execute_payout_spec",
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

  let!(:ordered_payout_status) { PayoutStatus.find_or_create_by!(code: "ordered", sort_order: 0, label_ja: "指図済", label_en: "Ordered", label_fr: "Ordered", label_zh: "Ordered", label_ru: "Ordered", label_es: "Ordered", label_ar: "Ordered") }
  let!(:completed_payout_status) { PayoutStatus.find_or_create_by!(code: "completed_simulated", sort_order: 1, label_ja: "支払完了（模擬）", label_en: "Completed", label_fr: "Completed", label_zh: "Completed", label_ru: "Completed", label_es: "Completed", label_ar: "Completed") }

  let!(:seismic_level_5_strong) { SeismicIntensityLevel.create!(code: "5_strong_execute_payout_spec", sort_order: 6, label_ja: "5強", label_en: "5 strong", label_fr: "5 strong", label_zh: "5 strong", label_ru: "5 strong", label_es: "5 strong", label_ar: "5 strong") }

  let(:policy) do
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

  let(:observation) do
    Observation.create!(
      station: station,
      event_id: "event-execute-payout-001",
      observed_at: Time.zone.parse("2026-07-15 10:00:00"),
      seismic_intensity_level: seismic_level_5_strong,
      max_value: seismic_level_5_strong.sort_order,
      simulated: false
    )
  end

  let(:payout) do
    Payout.create!(
      policy: policy,
      payout_tier: payout_tier,
      payout_status: ordered_payout_status,
      observation: observation,
      idempotency_key: "policy_#{policy.id}_event_event-execute-payout-001",
      decided_at: Time.current
    )
  end

  describe "#call" do
    it "completes a payout, creates completion notifications, and transitions the policy to active" do
      travel_to Time.zone.parse("2026-07-15 12:00:00") do
        result = described_class.new(payout: payout).call

        expect(result).to be_success
        expect(payout.reload.payout_status).to eq(completed_payout_status)
        expect(policy.reload.policy_status).to eq(active_status)
        expect(Notification.count).to eq(2)
        expect(Notification.pluck(:kind)).to contain_exactly(
          Notification::KIND_PAYOUT_COMPLETED,
          Notification::KIND_SURVEY_REQUEST
        )
        expect(Notification.pluck(:message)).to contain_exactly(
          I18n.t("notifications.payout_completed"),
          I18n.t("notifications.survey_request")
        )
      end
    end

    it "moves the policy to cap_reached when this completion reaches the annual payout limit" do
      travel_to Time.zone.parse("2026-07-15 12:00:00") do
        first_observation = Observation.create!(
          station: station,
          event_id: "event-execute-payout-previous",
          observed_at: Time.zone.parse("2026-01-15 10:00:00"),
          seismic_intensity_level: seismic_level_5_strong,
          max_value: seismic_level_5_strong.sort_order,
          simulated: false
        )
        first_payout = Payout.create!(
          policy: policy,
          payout_tier: payout_tier,
          payout_status: ordered_payout_status,
          observation: first_observation,
          idempotency_key: "policy_#{policy.id}_event_event-execute-payout-previous",
          decided_at: Time.current
        )

        first_payout.update!(payout_status: completed_payout_status)

        described_class.new(payout: payout).call

        expect(policy.reload.policy_status).to eq(cap_reached_status)
      end
    end

    it "returns success when payout is already completed (idempotent)" do
      payout.update!(payout_status: completed_payout_status)
      Notification.create!(user: user, policy: policy, payout: payout, kind: Notification::KIND_PAYOUT_COMPLETED, message: "completed")
      Notification.create!(user: user, policy: policy, payout: payout, kind: Notification::KIND_SURVEY_REQUEST, message: "survey")

      expect {
        result = described_class.new(payout: payout).call
        expect(result).to be_success
        expect(result.status).to eq(:ok)
      }.not_to change { Notification.count }

      expect(payout.reload.payout_status).to eq(completed_payout_status)
    end

    it "returns unprocessable_entity and does not process when payout is invalid" do
      invalid_status = PayoutStatus.find_or_create_by!(code: "invalid", sort_order: 2, label_ja: "無効", label_en: "Invalid", label_fr: "Invalid", label_zh: "Invalid", label_ru: "Invalid", label_es: "Invalid", label_ar: "Invalid")
      payout.update_columns(payout_status_id: invalid_status.id)

      expect {
        result = described_class.new(payout: payout).call
        expect(result).not_to be_success
        expect(result.status).to eq(:unprocessable_entity)
      }.not_to change { Notification.count }

      expect(payout.reload.payout_status).to eq(invalid_status)
      expect(policy.reload.policy_status).to eq(processing_status)
    end
  end
end
