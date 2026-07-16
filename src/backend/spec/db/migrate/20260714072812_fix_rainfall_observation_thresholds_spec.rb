require "rails_helper"
require_relative "../../../db/migrate/20260714072812_fix_rainfall_observation_thresholds"

class LegacyPayout < ActiveRecord::Base
  self.table_name = 'legacy_payouts'
end

class LegacySurveyResponse < ActiveRecord::Base
  self.table_name = 'legacy_survey_responses'
end

RSpec.describe FixRainfallObservationThresholds, type: :migration do
  subject(:migration) { described_class.new }

  describe "#resolve_rainfall_threshold_mm!" do
    it "resolves simple numeric threshold" do
      policy = double(threshold: "12.5", id: 1)
      expect(migration.send(:resolve_rainfall_threshold_mm!, policy)).to eq(BigDecimal("12.5"))
    end

    it "resolves threshold with 'mm-h'" do
      policy = double(threshold: "50mm-h", id: 2)
      expect(migration.send(:resolve_rainfall_threshold_mm!, policy)).to eq(BigDecimal("50.0"))
    end

    it "resolves threshold with 'mm'" do
      policy = double(threshold: "30mm", id: 3)
      expect(migration.send(:resolve_rainfall_threshold_mm!, policy)).to eq(BigDecimal("30.0"))
    end

    it "resolves threshold with 'mm/h'" do
      policy = double(threshold: "15mm/h", id: 4)
      expect(migration.send(:resolve_rainfall_threshold_mm!, policy)).to eq(BigDecimal("15.0"))
    end

    it "resolves threshold with 'mm_h'" do
      policy = double(threshold: "25mm_h", id: 5)
      expect(migration.send(:resolve_rainfall_threshold_mm!, policy)).to eq(BigDecimal("25.0"))
    end

    it "raises when rainfall threshold cannot be parsed" do
      policy = double(threshold: "invalid-value", id: 6)
      expect { migration.send(:resolve_rainfall_threshold_mm!, policy) }
        .to raise_error(
          RuntimeError,
          "Migration blocked: Cannot resolve rainfall threshold for Policy 6 threshold 'invalid-value'."
        )
    end

    it "resolves threshold with trailing whitespace after the unit" do
      policy = double(threshold: "50mm \t", id: 7)
      expect(migration.send(:resolve_rainfall_threshold_mm!, policy)).to eq(BigDecimal("50.0"))
    end

    it "resolves threshold with a unit followed by a tab character" do
      policy = double(threshold: "15mm/h\t", id: 8)
      expect(migration.send(:resolve_rainfall_threshold_mm!, policy)).to eq(BigDecimal("15.0"))
    end

    it "resolves threshold with leading whitespace" do
      policy = double(threshold: "  25mm_h", id: 9)
      expect(migration.send(:resolve_rainfall_threshold_mm!, policy)).to eq(BigDecimal("25.0"))
    end

    it "resolves threshold at the exact column maximum (9999.99)" do
      policy = double(threshold: "9999.99mm", id: 10)
      expect(migration.send(:resolve_rainfall_threshold_mm!, policy)).to eq(BigDecimal("9999.99"))
    end

    it "raises when the threshold exceeds the column maximum (decimal(6,2))" do
      policy = double(threshold: "10000mm", id: 11)
      expect { migration.send(:resolve_rainfall_threshold_mm!, policy) }
        .to raise_error(
          RuntimeError,
          "Migration blocked: Cannot resolve rainfall threshold for Policy 11 threshold '10000mm'."
        )
    end

    it "raises when the threshold is negative" do
      policy = double(threshold: "-5mm", id: 12)
      expect { migration.send(:resolve_rainfall_threshold_mm!, policy) }
        .to raise_error(
          RuntimeError,
          "Migration blocked: Cannot resolve rainfall threshold for Policy 12 threshold '-5mm'."
        )
    end

    it "raises when the threshold is NaN" do
      policy = double(threshold: "NaN", id: 13)
      expect { migration.send(:resolve_rainfall_threshold_mm!, policy) }
        .to raise_error(
          RuntimeError,
          "Migration blocked: Cannot resolve rainfall threshold for Policy 13 threshold 'NaN'."
        )
    end

    it "raises when the threshold is Infinity" do
      policy = double(threshold: "Infinity", id: 14)
      expect { migration.send(:resolve_rainfall_threshold_mm!, policy) }
        .to raise_error(
          RuntimeError,
          "Migration blocked: Cannot resolve rainfall threshold for Policy 14 threshold 'Infinity'."
        )
    end
  end

  describe "#up" do
    let!(:rainfall_station) do
      Station.create!(
        code: "test_rainfall_station",
        measurement_type: "rainfall",
        label_ja: "test", label_en: "test", label_fr: "test", label_zh: "test", label_ru: "test", label_es: "test", label_ar: "test"
      )
    end

    let!(:seismic_station) do
      Station.create!(
        code: "test_seismic_station",
        measurement_type: "seismic",
        label_ja: "test", label_en: "test", label_fr: "test", label_zh: "test", label_ru: "test", label_es: "test", label_ar: "test"
      )
    end

    let!(:user) { User.create!(google_sub: "test_sub") }
    let!(:plan) do
      Plan.find_or_create_by!(code: "rainfall_plan") do |p|
        p.trigger_type = "rainfall"
        p.label_ja = "降雨プラン"
        p.label_en = "Rainfall Plan"
        p.label_fr = "test"; p.label_zh = "test"; p.label_ru = "test"; p.label_es = "test"; p.label_ar = "test"
      end
    end
    let!(:seismic_plan) do
      Plan.find_or_create_by!(code: "seismic_plan") do |p|
        p.trigger_type = "seismic"
        p.label_ja = "地震プラン"
        p.label_en = "Seismic Plan"
        p.label_fr = "test"; p.label_zh = "test"; p.label_ru = "test"; p.label_es = "test"; p.label_ar = "test"
      end
    end
    let!(:policy_status) do
      PolicyStatus.find_or_create_by!(code: "active") do |s|
        s.sort_order = 1
        s.label_ja = "有効"
        s.label_en = "Active"
        s.label_fr = "test"; s.label_zh = "test"; s.label_ru = "test"; s.label_es = "test"; s.label_ar = "test"
      end
    end
    let!(:payout_status) do
      PayoutStatus.find_or_create_by!(code: "decided") do |s|
        s.sort_order = 1
        s.label_ja = "決定"
        s.label_en = "Decided"
        s.label_fr = "test"; s.label_zh = "test"; s.label_ru = "test"; s.label_es = "test"; s.label_ar = "test"
      end
    end
    let!(:payout_tier) do
      PayoutTier.find_or_create_by!(code: "tier_1") do |t|
        t.amount_yen = 10000
        t.label_ja = "1万円"
        t.label_en = "10k"
        t.label_fr = "test"; t.label_zh = "test"; t.label_ru = "test"; t.label_es = "test"; t.label_ar = "test"
      end
    end

    # 正常補正されるケース
    let!(:policy_1) do
      p = Policy.create!(user_id: user.id, plan_id: plan.id, policy_status_id: policy_status.id, expires_at: 1.year.from_now, station_id: rainfall_station.id, threshold: "50mm-h", payout_tier_id: payout_tier.id)
      p.update_columns(waiting_until: 4.days.ago)
      p
    end
    let!(:obs_1) { Observation.create!(station_id: rainfall_station.id, observed_at: Time.current, simulated: true, rainfall_mm: 0.0) }
    let!(:payout_1) { Payout.create!(policy_id: policy_1.id, observation_id: obs_1.id, payout_status_id: payout_status.id, payout_tier_id: payout_tier.id, idempotency_key: "key_1") }

    # 補正非対象ケース1: simulated: false (実測)
    let!(:policy_2) do
      p = Policy.create!(user_id: user.id, plan_id: plan.id, policy_status_id: policy_status.id, expires_at: 1.year.from_now, station_id: rainfall_station.id, threshold: "30mm", payout_tier_id: payout_tier.id)
      p.update_columns(waiting_until: 4.days.ago)
      p
    end
    let!(:obs_2) { Observation.create!(station_id: rainfall_station.id, observed_at: Time.current, simulated: false, rainfall_mm: 0.0) }
    let!(:payout_2) { Payout.create!(policy_id: policy_2.id, observation_id: obs_2.id, payout_status_id: payout_status.id, payout_tier_id: payout_tier.id, idempotency_key: "key_2") }

    # 補正非対象ケース2: 地震
    let!(:seismic_level) do
      SeismicIntensityLevel.find_or_create_by!(code: "5_weak") do |l|
        l.sort_order = 5
        l.label_ja = "5弱"
        l.label_en = "5 weak"
        l.label_fr = "5 weak"
        l.label_zh = "5 weak"
        l.label_ru = "5 weak"
        l.label_es = "5 weak"
        l.label_ar = "5 weak"
      end
    end
    let!(:policy_3) do
      p = Policy.create!(user_id: user.id, plan_id: seismic_plan.id, policy_status_id: policy_status.id, expires_at: 1.year.from_now, station_id: seismic_station.id, threshold: "5弱", payout_tier_id: payout_tier.id)
      p.update_columns(waiting_until: 4.days.ago)
      p
    end
    let!(:obs_3) { Observation.create!(station_id: seismic_station.id, observed_at: Time.current, simulated: true, seismic_intensity_level_id: seismic_level.id, event_id: "legacy-event-1") }
    let!(:payout_3) { Payout.create!(policy_id: policy_3.id, observation_id: obs_3.id, payout_status_id: payout_status.id, payout_tier_id: payout_tier.id, idempotency_key: "key_3") }

    # 共有観測で閾値が異なる競合ケース (隔離対象)
    let!(:policy_conflict_a) do
      p = Policy.create!(user_id: user.id, plan_id: plan.id, policy_status_id: policy_status.id, expires_at: 1.year.from_now, station_id: rainfall_station.id, threshold: "30mm", payout_tier_id: payout_tier.id)
      p.update_columns(waiting_until: 4.days.ago)
      p
    end
    let!(:policy_conflict_b) do
      p = Policy.create!(user_id: user.id, plan_id: plan.id, policy_status_id: policy_status.id, expires_at: 1.year.from_now, station_id: rainfall_station.id, threshold: "50mm-h", payout_tier_id: payout_tier.id)
      p.update_columns(waiting_until: 4.days.ago)
      p
    end
    let!(:obs_conflict) { Observation.create!(station_id: rainfall_station.id, observed_at: Time.current, simulated: true, rainfall_mm: 0.0) }
    let!(:completed_status) do
      PayoutStatus.find_or_create_by!(code: "completed_simulated") do |s|
        s.sort_order = 2
        s.label_ja = "完了（シミュレーション）"
        s.label_en = "Completed (simulated)"
        s.label_fr = "test"; s.label_zh = "test"; s.label_ru = "test"; s.label_es = "test"; s.label_ar = "test"
      end
    end
    let!(:payout_conflict_a) { Payout.create!(policy_id: policy_conflict_a.id, observation_id: obs_conflict.id, payout_status_id: completed_status.id, payout_tier_id: payout_tier.id, idempotency_key: "key_conflict_a") }
    let!(:payout_conflict_b) { Payout.create!(policy_id: policy_conflict_b.id, observation_id: obs_conflict.id, payout_status_id: payout_status.id, payout_tier_id: payout_tier.id, idempotency_key: "key_conflict_b") }
    let!(:notification_conflict_a) { Notification.create!(user_id: user.id, policy_id: policy_conflict_a.id, payout_id: payout_conflict_a.id, kind: "payout", message: "test") }
    let!(:survey_response_conflict_a) { SurveyResponse.create!(user_id: user.id, payout_id: payout_conflict_a.id, response_data: { "q1" => "yes" }) }

    # 不正閾値によるパースエラーで隔離されるケース
    let!(:policy_invalid) do
      p = Policy.create!(user_id: user.id, plan_id: plan.id, policy_status_id: policy_status.id, expires_at: 1.year.from_now, station_id: rainfall_station.id, threshold: "invalid-threshold", payout_tier_id: payout_tier.id)
      p.update_columns(waiting_until: 4.days.ago)
      p
    end
    let!(:obs_invalid) { Observation.create!(station_id: rainfall_station.id, observed_at: Time.current, simulated: true, rainfall_mm: 0.0) }
    let!(:payout_invalid) { Payout.create!(policy_id: policy_invalid.id, observation_id: obs_invalid.id, payout_status_id: payout_status.id, payout_tier_id: payout_tier.id, idempotency_key: "key_invalid_payout") }

    it "corrects simulated observations when thresholds match, and isolates payouts when thresholds conflict or are invalid" do
      expect { migration.up }.not_to raise_error

      # 正常ケース: 観測値が補正され、Payout は残る
      expect(obs_1.reload.rainfall_mm).to eq(BigDecimal("50.0"))
      expect(Payout.exists?(id: payout_1.id)).to be_truthy

      # 補正非対象ケース: simulated: false や地震は変更されない
      expect(obs_2.reload.rainfall_mm).to eq(BigDecimal("0.0"))
      expect(obs_3.reload.seismic_intensity_level_id).to eq(seismic_level.id)

      # 競合ケース: 2つの Payout は削除され、LegacyPayout に退避される
      expect(Payout.exists?(id: payout_conflict_a.id)).to be_falsey
      expect(Payout.exists?(id: payout_conflict_b.id)).to be_falsey

      legacy_a = LegacyPayout.find_by(idempotency_key: "key_conflict_a")
      legacy_b = LegacyPayout.find_by(idempotency_key: "key_conflict_b")
      expect(legacy_a).to be_present
      expect(legacy_b).to be_present
      expect(legacy_a.isolation_reason).to include("Ambiguous threshold resolution")

      # 通知の payout_id が nil に更新されていること
      expect(notification_conflict_a.reload.payout_id).to be_nil

      # アンケート回答は削除されず legacy_survey_responses へ退避されていること
      # （外部キー制約により、退避前に payout.destroy すると migration 全体が失敗する）
      expect(SurveyResponse.exists?(id: survey_response_conflict_a.id)).to be_falsey
      legacy_survey = LegacySurveyResponse.find_by(user_id: user.id, policy_id: policy_conflict_a.id)
      expect(legacy_survey).to be_present
      expect(legacy_survey.isolation_reason).to include("isolated during rainfall threshold backfill")

      # 不正閾値ケース: Payout は削除され、LegacyPayout に退避される
      expect(Payout.exists?(id: payout_invalid.id)).to be_falsey
      legacy_invalid = LegacyPayout.find_by(idempotency_key: "key_invalid_payout")
      expect(legacy_invalid).to be_present
      expect(legacy_invalid.isolation_reason).to include("Cannot resolve rainfall threshold")
    end
  end
end
