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

        simulated_observation = Observation.create!(
          station: station,
          event_id: "event-kpi-simulated",
          observed_at: zone.parse("2026-07-17 00:00:00"),
          seismic_intensity_level: SeismicIntensityLevel.create!(
            code: "level-kpi-simulated",
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
        real_observation = Observation.create!(
          station: station,
          event_id: "event-kpi-real",
          observed_at: zone.parse("2026-07-17 22:30:00"),
          seismic_intensity_level: SeismicIntensityLevel.create!(
            code: "level-kpi-real",
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
          observation: simulated_observation,
          idempotency_key: "policy_#{policy_1.id}_event-kpi-simulated",
          decided_at: zone.parse("2026-07-17 00:10:00")
        )
        payout_2 = Payout.create!(
          policy: policy_2,
          payout_tier: payout_tier,
          payout_status: completed_status,
          observation: real_observation,
          idempotency_key: "policy_#{policy_2.id}_event-kpi-real",
          decided_at: zone.parse("2026-07-17 23:00:00")
        )

        SurveyResponse.create!(
          user: user_1,
          payout: payout_1,
          response_data: { satisfaction: 4 }
        )
        SurveyResponse.create!(
          user: user_2,
          payout: payout_2,
          response_data: { satisfaction: 5 }
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
          average_order_latency_minutes: 30.0
        )
      end
    end

    it "does not exceed 100% for application completion rate when a user has multiple policies" do
      user = User.create!(google_sub: "google-sub-kpi-mult")
      plan_1 = Plan.create!(code: "plan_1", trigger_type: "seismic", label_ja: "A", label_en: "A", label_fr: "A", label_zh: "A", label_ru: "A", label_es: "A", label_ar: "A")
      plan_2 = Plan.create!(code: "plan_2", trigger_type: "rainfall", label_ja: "B", label_en: "B", label_fr: "B", label_zh: "B", label_ru: "B", label_es: "B", label_ar: "B")

      station_1 = Station.create!(code: "station_seismic", measurement_type: "seismic", label_ja: "C", label_en: "C", label_fr: "C", label_zh: "C", label_ru: "C", label_es: "C", label_ar: "C")
      station_2 = Station.create!(code: "station_rainfall", measurement_type: "rainfall", label_ja: "C2", label_en: "C2", label_fr: "C2", label_zh: "C2", label_ru: "C2", label_es: "C2", label_ar: "C2")
      payout_tier = PayoutTier.create!(code: "tier_mult", amount_yen: 10_000, label_ja: "D", label_en: "D", label_fr: "D", label_zh: "D", label_ru: "D", label_es: "D", label_ar: "D")
      active_status = PolicyStatus.create!(code: "active_mult", sort_order: 1, label_ja: "E", label_en: "E", label_fr: "E", label_zh: "E", label_ru: "E", label_es: "E", label_ar: "E")

      Policy.create!(user: user, plan: plan_1, station: station_1, payout_tier: payout_tier, policy_status: active_status, threshold: "5強")
      Policy.create!(user: user, plan: plan_2, station: station_2, payout_tier: payout_tier, policy_status: active_status, threshold: "10 mm")

      expect(described_class.new.call[:application_completion_rate]).to eq(1.0)
    end

    it "correctly aggregates average satisfaction from legacy keys using fallback when validation is skipped" do
      user_1 = User.create!(google_sub: "google-sub-kpi-leg-1")
      user_2 = User.create!(google_sub: "google-sub-kpi-leg-2")
      user_3 = User.create!(google_sub: "google-sub-kpi-leg-3")
      user_4 = User.create!(google_sub: "google-sub-kpi-leg-4")

      plan = Plan.create!(code: "plan_leg", trigger_type: "seismic", label_ja: "A", label_en: "A", label_fr: "A", label_zh: "A", label_ru: "A", label_es: "A", label_ar: "A")
      station = Station.create!(code: "station_leg", measurement_type: "seismic", label_ja: "C", label_en: "C", label_fr: "C", label_zh: "C", label_ru: "C", label_es: "C", label_ar: "C")
      payout_tier = PayoutTier.create!(code: "tier_leg", amount_yen: 10_000, label_ja: "D", label_en: "D", label_fr: "D", label_zh: "D", label_ru: "D", label_es: "D", label_ar: "D")
      active_status = PolicyStatus.find_or_create_by!(code: "active") do |s|
        s.sort_order = 1; s.label_ja = "E"; s.label_en = "E"; s.label_fr = "E"; s.label_zh = "E"; s.label_ru = "E"; s.label_es = "E"; s.label_ar = "E"
      end
      processing_status = PolicyStatus.find_or_create_by!(code: "processing") do |s|
        s.sort_order = 2; s.label_ja = "E2"; s.label_en = "E2"; s.label_fr = "E2"; s.label_zh = "E2"; s.label_ru = "E2"; s.label_es = "E2"; s.label_ar = "E2"
      end
      completed_status = PayoutStatus.find_or_create_by!(code: "completed_simulated") do |s|
        s.sort_order = 1; s.label_ja = "F"; s.label_en = "F"; s.label_fr = "F"; s.label_zh = "F"; s.label_ru = "F"; s.label_es = "F"; s.label_ar = "F"
      end

      policy_1 = Policy.create!(user: user_1, plan: plan, station: station, payout_tier: payout_tier, policy_status: active_status, threshold: "5強").tap { |p| p.update_columns(waiting_until: 1.day.ago, expires_at: 1.year.from_now) }
      policy_2 = Policy.create!(user: user_2, plan: plan, station: station, payout_tier: payout_tier, policy_status: active_status, threshold: "5強").tap { |p| p.update_columns(waiting_until: 1.day.ago, expires_at: 1.year.from_now) }
      policy_3 = Policy.create!(user: user_3, plan: plan, station: station, payout_tier: payout_tier, policy_status: active_status, threshold: "5強").tap { |p| p.update_columns(waiting_until: 1.day.ago, expires_at: 1.year.from_now) }
      policy_4 = Policy.create!(user: user_4, plan: plan, station: station, payout_tier: payout_tier, policy_status: active_status, threshold: "5強").tap { |p| p.update_columns(waiting_until: 1.day.ago, expires_at: 1.year.from_now) }

      seismic_level = SeismicIntensityLevel.create!(code: "level_leg", sort_order: 5, label_ja: "5弱", label_en: "5 weak", label_fr: "5 weak", label_zh: "5 weak", label_ru: "5 weak", label_es: "5 weak", label_ar: "5 weak")
      observation = Observation.create!(station: station, event_id: "event-leg", observed_at: Time.current, seismic_intensity_level: seismic_level, max_value: 5, simulated: true)

      payout_1 = Payout.create!(policy: policy_1, payout_tier: payout_tier, payout_status: completed_status, observation: observation, idempotency_key: "payout-leg-1", decided_at: Time.current)
      payout_2 = Payout.create!(policy: policy_2, payout_tier: payout_tier, payout_status: completed_status, observation: observation, idempotency_key: "payout-leg-2", decided_at: Time.current)
      payout_3 = Payout.create!(policy: policy_3, payout_tier: payout_tier, payout_status: completed_status, observation: observation, idempotency_key: "payout-leg-3", decided_at: Time.current)
      payout_4 = Payout.create!(policy: policy_4, payout_tier: payout_tier, payout_status: completed_status, observation: observation, idempotency_key: "payout-leg-4", decided_at: Time.current)

      sr_1 = SurveyResponse.new(user: user_1, payout: payout_1, response_data: { satisfaction_score: 5 })
      sr_1.save!(validate: false)

      sr_2 = SurveyResponse.new(user: user_2, payout: payout_2, response_data: { rating: 4 })
      sr_2.save!(validate: false)

      sr_3 = SurveyResponse.new(user: user_3, payout: payout_3, response_data: { score: 3 })
      sr_3.save!(validate: false)

      sr_4 = SurveyResponse.new(user: user_4, payout: payout_4, response_data: { satisfaction: 2 })
      sr_4.save!(validate: false)

      expect(described_class.new.call[:average_satisfaction]).to eq(3.5)
    end
  end
end
