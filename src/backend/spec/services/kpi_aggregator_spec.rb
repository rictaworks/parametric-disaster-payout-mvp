require "rails_helper"

RSpec.describe KpiAggregator do
  include ActiveSupport::Testing::TimeHelpers

  describe "#call" do
    it "returns zero values when there is no data" do
      expect(described_class.new.call).to eq(
        registered_users_count: 0,
        application_completion_rate: 0.0,
        contract_continuation_rate: 0.0,
        survey_response_count: 0,
        average_satisfaction: 0.0,
        todays_payout_orders_count: 0,
        average_order_latency_minutes: 0.0
      )
    end

    it "aggregates KPI metrics and uses JST for today's payout orders" do
      zone = Time.find_zone!("Asia/Tokyo")

      travel_to(zone.parse("2026-07-17 23:30:00")) do
        user_1 = User.create!(google_sub: "google-sub-kpi-1")
        user_2 = User.create!(google_sub: "google-sub-kpi-2")
        plan = Plan.create!(
          code: "seismic_kpi",
          trigger_type: "seismic",
          label_ja: "震度連動",
          label_en: "Seismic-linked",
          label_fr: "Seismic-linked",
          label_zh: "Seismic-linked",
          label_ru: "Seismic-linked",
          label_es: "Seismic-linked",
          label_ar: "Seismic-linked"
        )
        station = Station.create!(
          code: "seismic_tokyo_kpi",
          measurement_type: "seismic",
          label_ja: "東京震度観測点",
          label_en: "Tokyo seismic station",
          label_fr: "Tokyo seismic station",
          label_zh: "Tokyo seismic station",
          label_ru: "Tokyo seismic station",
          label_es: "Tokyo seismic station",
          label_ar: "Tokyo seismic station"
        )
        payout_tier = PayoutTier.create!(
          code: "ten_thousand_kpi",
          amount_yen: 10_000,
          label_ja: "1万円相当（模擬）",
          label_en: "Equivalent to JPY 10,000",
          label_fr: "Equivalent to JPY 10,000",
          label_zh: "Equivalent to JPY 10,000",
          label_ru: "Equivalent to JPY 10,000",
          label_es: "Equivalent to JPY 10,000",
          label_ar: "Equivalent to JPY 10,000"
        )
        active_status = PolicyStatus.create!(
          code: "active",
          sort_order: 1,
          label_ja: "有効",
          label_en: "Active",
          label_fr: "Active",
          label_zh: "Active",
          label_ru: "Active",
          label_es: "Active",
          label_ar: "Active"
        )
        cancelled_status = PolicyStatus.create!(
          code: "cancelled",
          sort_order: 9,
          label_ja: "解約",
          label_en: "Cancelled",
          label_fr: "Cancelled",
          label_zh: "Cancelled",
          label_ru: "Cancelled",
          label_es: "Cancelled",
          label_ar: "Cancelled"
        )
        cap_reached_status = PolicyStatus.create!(
          code: "cap_reached",
          sort_order: 8,
          label_ja: "上限到達",
          label_en: "Cap reached",
          label_fr: "Cap reached",
          label_zh: "Cap reached",
          label_ru: "Cap reached",
          label_es: "Cap reached",
          label_ar: "Cap reached"
        )

        completed_status = PayoutStatus.create!(
          code: "completed_simulated",
          sort_order: 1,
          label_ja: "支払完了（模擬）",
          label_en: "Completed",
          label_fr: "Completed",
          label_zh: "Completed",
          label_ru: "Completed",
          label_es: "Completed",
          label_ar: "Completed"
        )

        policy_1 = Policy.create!(
          user: user_1,
          plan: plan,
          station: station,
          payout_tier: payout_tier,
          policy_status: active_status,
          threshold: "5強"
        ).tap do |policy|
          policy.update_columns(
            waiting_until: zone.parse("2026-07-15 00:00:00"),
            expires_at: zone.parse("2026-12-31 23:59:59")
          )
        end
        policy_2 = Policy.create!(
          user: user_2,
          plan: plan,
          station: station,
          payout_tier: payout_tier,
          policy_status: active_status,
          threshold: "5強"
        ).tap do |policy|
          policy.update_columns(
            waiting_until: zone.parse("2026-07-15 00:00:00"),
            expires_at: zone.parse("2026-12-31 23:59:59")
          )
        end

        observation_1 = Observation.create!(
          station: station,
          event_id: "event-kpi-1",
          observed_at: zone.parse("2026-07-17 00:00:00"),
          seismic_intensity_level: SeismicIntensityLevel.create!(
            code: "level-kpi-1",
            sort_order: 5,
            label_ja: "5強",
            label_en: "5 strong",
            label_fr: "5 strong",
            label_zh: "5 strong",
            label_ru: "5 strong",
            label_es: "5 strong",
            label_ar: "5 strong"
          ),
          max_value: 5,
          simulated: true
        )
        observation_2 = Observation.create!(
          station: station,
          event_id: "event-kpi-2",
          observed_at: zone.parse("2026-07-16 22:50:00"),
          seismic_intensity_level: SeismicIntensityLevel.create!(
            code: "level-kpi-2",
            sort_order: 6,
            label_ja: "5強",
            label_en: "5 strong",
            label_fr: "5 strong",
            label_zh: "5 strong",
            label_ru: "5 strong",
            label_es: "5 strong",
            label_ar: "5 strong"
          ),
          max_value: 6,
          simulated: false
        )

        payout_1 = Payout.create!(
          policy: policy_1,
          payout_tier: payout_tier,
          payout_status: completed_status,
          observation: observation_1,
          idempotency_key: "policy_#{policy_1.id}_event-kpi-1",
          decided_at: zone.parse("2026-07-17 00:10:00")
        )
        payout_2 = Payout.create!(
          policy: policy_2,
          payout_tier: payout_tier,
          payout_status: completed_status,
          observation: observation_2,
          idempotency_key: "policy_#{policy_2.id}_event-kpi-2",
          decided_at: zone.parse("2026-07-16 23:50:00")
        )

        SurveyResponse.create!(
          user: user_1,
          payout: payout_1,
          response_data: { satisfaction: 4 }
        )
        SurveyResponse.create!(
          user: user_2,
          payout: payout_2,
          response_data: { satisfaction_score: 5 }
        )

        policy_2.update!(policy_status: cancelled_status)
        expect(PolicyStatus.exists?(code: cap_reached_status.code)).to be(true)

        expect(described_class.new.call).to include(
          registered_users_count: 2,
          application_completion_rate: 1.0,
          contract_continuation_rate: 0.5,
          survey_response_count: 2,
          average_satisfaction: 4.5,
          todays_payout_orders_count: 1,
          average_order_latency_minutes: 35.0
        )
      end
    end
  end
end
