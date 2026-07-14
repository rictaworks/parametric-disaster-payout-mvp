require "rails_helper"
require "securerandom"
require "tmpdir"
require_relative "../../../db/migrate/20260713213247_update_stage1_domain_models_for_review_comments"

class LegacyPayout < ActiveRecord::Base
  self.table_name = "legacy_payouts"
end

class LegacySurveyResponse < ActiveRecord::Base
  self.table_name = "legacy_survey_responses"
end

RSpec.describe UpdateStage1DomainModelsForReviewComments, type: :migration do
  self.use_transactional_tests = false

  subject(:migration) { described_class.new }

  let(:original_db_config) { ActiveRecord::Base.connection_db_config.configuration_hash }

  around do |example|
    run_against_legacy_database do
      example.run
    end
  end

  def run_against_legacy_database
    legacy_database_path = File.join(Dir.tmpdir, "legacy-migration-#{SecureRandom.hex(8)}.sqlite3")
    legacy_db_config = original_db_config.merge(database: legacy_database_path)

    ActiveRecord::Base.connection_handler.clear_all_connections!
    ActiveRecord::Base.establish_connection(legacy_db_config)
    ActiveRecord::MigrationContext.new([ Rails.root.join("db/migrate").to_s ]).migrate(20260713213246)
    reset_model_column_information

    yield
  ensure
    ActiveRecord::Base.remove_connection
    ActiveRecord::Base.establish_connection(original_db_config)
    reset_model_column_information
    Dir.glob("#{legacy_database_path}*").each { |path| FileUtils.rm_f(path) }
  end

  def reset_model_column_information
    [ User, Plan, Station, SeismicIntensityLevel, PolicyStatus, PayoutStatus, PayoutTier,
      Policy, Observation, Payout, SurveyResponse, LegacyPayout, LegacySurveyResponse ].each(&:reset_column_information)
  end

  def localized_attributes(name)
    {
      label_ja: name,
      label_en: name,
      label_fr: name,
      label_zh: name,
      label_ru: name,
      label_es: name,
      label_ar: name
    }
  end

  def legacy_insert(table, attrs)
    conn = ActiveRecord::Base.connection
    columns = attrs.keys.map { |column| conn.quote_column_name(column) }.join(", ")
    values = attrs.values.map do |value|
      value = value.to_json if value.is_a?(Hash) || value.is_a?(Array)
      conn.quote(value)
    end.join(", ")

    conn.execute("INSERT INTO #{table} (#{columns}) VALUES (#{values})")
    conn.select_value("SELECT last_insert_rowid()").to_i
  end

  let!(:user) { User.create!(google_sub: "google-sub-#{SecureRandom.hex(4)}") }
  let!(:policy_status) do
    PolicyStatus.create!(code: "active", sort_order: 1, **localized_attributes("active"))
  end
  let!(:payout_status) do
    PayoutStatus.create!(code: "decided", sort_order: 1, **localized_attributes("decided"))
  end
  let!(:payout_tier) do
    PayoutTier.create!(code: "tier_1", amount_yen: 10_000, **localized_attributes("tier_1"))
  end
  let!(:rainfall_plan) do
    Plan.create!(code: "rainfall_plan", trigger_type: "rainfall", **localized_attributes("rainfall plan"))
  end
  let!(:seismic_plan) do
    Plan.create!(code: "seismic_plan", trigger_type: "seismic", **localized_attributes("seismic plan"))
  end
  let!(:rainfall_station) do
    Station.create!(code: "rainfall_station", measurement_type: "rainfall", **localized_attributes("rainfall station"))
  end
  let!(:secondary_rainfall_station) do
    Station.create!(code: "rainfall_station_2", measurement_type: "rainfall", **localized_attributes("rainfall station 2"))
  end
  let!(:seismic_station) do
    Station.create!(code: "seismic_station", measurement_type: "seismic", **localized_attributes("seismic station"))
  end
  let!(:seismic_level_3) do
    SeismicIntensityLevel.create!(code: "3", sort_order: 3, **localized_attributes("3"))
  end
  let!(:seismic_level_5) do
    SeismicIntensityLevel.create!(code: "5_weak", sort_order: 5, **localized_attributes("5弱"))
  end

  describe "#up" do
    it "merges duplicate rainfall and seismic observations and rewires payouts to the representative observation" do
      policy_id = legacy_insert(
        :policies,
        user_id: user.id,
        plan_id: rainfall_plan.id,
        payout_tier_id: payout_tier.id,
        policy_status_id: policy_status.id,
        threshold: "50mm",
        expires_at: 1.year.from_now,
        created_at: 2.days.ago,
        updated_at: 2.days.ago
      )

      rainfall_observation_time = Time.zone.local(2026, 7, 1, 12, 0, 0)
      representative_rainfall_observation_id = legacy_insert(
        :observations,
        policy_id: policy_id,
        station_id: rainfall_station.id,
        rainfall_mm: BigDecimal("12.0"),
        observed_at: rainfall_observation_time,
        created_at: rainfall_observation_time,
        updated_at: rainfall_observation_time
      )
      duplicate_rainfall_observation_id = legacy_insert(
        :observations,
        policy_id: policy_id,
        station_id: rainfall_station.id,
        rainfall_mm: BigDecimal("12.0"),
        observed_at: rainfall_observation_time,
        created_at: rainfall_observation_time,
        updated_at: rainfall_observation_time
      )
      rainfall_payout_id = legacy_insert(
        :payouts,
        policy_id: policy_id,
        payout_tier_id: payout_tier.id,
        payout_status_id: payout_status.id,
        observation_id: duplicate_rainfall_observation_id,
        idempotency_key: "rainfall-dup-#{SecureRandom.hex(4)}",
        decided_at: 1.day.ago,
        created_at: 1.day.ago,
        updated_at: 1.day.ago
      )

      seismic_policy_id = legacy_insert(
        :policies,
        user_id: user.id,
        plan_id: seismic_plan.id,
        payout_tier_id: payout_tier.id,
        policy_status_id: policy_status.id,
        threshold: "5弱",
        expires_at: 1.year.from_now,
        created_at: 3.days.ago,
        updated_at: 3.days.ago
      )
      seismic_observation_time = Time.zone.local(2026, 7, 2, 12, 0, 0)
      representative_seismic_observation_id = legacy_insert(
        :observations,
        policy_id: seismic_policy_id,
        station_id: seismic_station.id,
        seismic_intensity_level_id: seismic_level_5.id,
        observed_at: seismic_observation_time,
        created_at: seismic_observation_time,
        updated_at: seismic_observation_time
      )
      duplicate_seismic_observation_id = legacy_insert(
        :observations,
        policy_id: seismic_policy_id,
        station_id: seismic_station.id,
        seismic_intensity_level_id: seismic_level_3.id,
        observed_at: seismic_observation_time,
        created_at: seismic_observation_time,
        updated_at: seismic_observation_time
      )
      seismic_payout_id = legacy_insert(
        :payouts,
        policy_id: seismic_policy_id,
        payout_tier_id: payout_tier.id,
        payout_status_id: payout_status.id,
        observation_id: duplicate_seismic_observation_id,
        idempotency_key: "seismic-dup-#{SecureRandom.hex(4)}",
        decided_at: 1.day.ago,
        created_at: 1.day.ago,
        updated_at: 1.day.ago
      )

      migration.up

      reset_model_column_information

      expect(Observation.exists?(duplicate_rainfall_observation_id)).to be(false)
      expect(Payout.find(rainfall_payout_id).observation_id).to eq(representative_rainfall_observation_id)

      expect(Observation.exists?(duplicate_seismic_observation_id)).to be(false)
      expect(Payout.find(seismic_payout_id).observation_id).to eq(representative_seismic_observation_id)
      expect(Observation.find(representative_seismic_observation_id).event_id).to eq("legacy-event-#{representative_seismic_observation_id}")
    end

    it "backfills payouts without observations using rainfall and seismic thresholds" do
      rainfall_policy_id = legacy_insert(
        :policies,
        user_id: user.id,
        plan_id: rainfall_plan.id,
        payout_tier_id: payout_tier.id,
        policy_status_id: policy_status.id,
        threshold: "0mm",
        expires_at: 1.year.from_now,
        created_at: 2.days.ago,
        updated_at: 2.days.ago
      )
      rainfall_payout_id = legacy_insert(
        :payouts,
        policy_id: rainfall_policy_id,
        payout_tier_id: payout_tier.id,
        payout_status_id: payout_status.id,
        observation_id: nil,
        idempotency_key: "rainfall-backfill-#{SecureRandom.hex(4)}",
        decided_at: nil,
        created_at: Time.zone.local(2026, 7, 3, 9, 0, 0),
        updated_at: Time.zone.local(2026, 7, 3, 9, 0, 0)
      )

      seismic_policy_id = legacy_insert(
        :policies,
        user_id: user.id,
        plan_id: seismic_plan.id,
        payout_tier_id: payout_tier.id,
        policy_status_id: policy_status.id,
        threshold: "5弱",
        expires_at: 1.year.from_now,
        created_at: 2.days.ago,
        updated_at: 2.days.ago
      )
      seismic_payout_id = legacy_insert(
        :payouts,
        policy_id: seismic_policy_id,
        payout_tier_id: payout_tier.id,
        payout_status_id: payout_status.id,
        observation_id: nil,
        idempotency_key: "seismic-backfill-#{SecureRandom.hex(4)}",
        decided_at: nil,
        created_at: Time.zone.local(2026, 7, 3, 10, 0, 0),
        updated_at: Time.zone.local(2026, 7, 3, 10, 0, 0)
      )

      migration.up

      reset_model_column_information

      rainfall_policy = Policy.find(rainfall_policy_id)
      rainfall_payout = Payout.find(rainfall_payout_id)
      rainfall_observation = Observation.find(rainfall_payout.observation_id)
      expect(Station.find(rainfall_policy.station_id).code).to eq("temp_rainfall_migration")
      expect(rainfall_observation.station_id).to eq(rainfall_policy.station_id)
      expect(rainfall_observation.rainfall_mm).to eq(BigDecimal("0.0"))
      expect(rainfall_observation.simulated).to be(true)

      seismic_policy = Policy.find(seismic_policy_id)
      seismic_payout = Payout.find(seismic_payout_id)
      seismic_observation = Observation.find(seismic_payout.observation_id)
      expect(Station.find(seismic_policy.station_id).code).to eq("temp_seismic_migration")
      expect(seismic_observation.station_id).to eq(seismic_policy.station_id)
      expect(seismic_observation.seismic_intensity_level_id).to eq(seismic_level_5.id)
      expect(seismic_observation.event_id).to eq("legacy-event-payout-#{seismic_payout_id}")
      expect(seismic_observation.simulated).to be(true)
    end

    it "corrects the payout_tier_id of existing payouts to match the policy's payout_tier_id" do
      alternative_payout_tier = PayoutTier.create!(
        code: "tier_2",
        amount_yen: 50_000,
        **localized_attributes("tier_2")
      )

      policy_id = legacy_insert(
        :policies,
        user_id: user.id,
        plan_id: rainfall_plan.id,
        payout_tier_id: payout_tier.id,
        policy_status_id: policy_status.id,
        threshold: "30mm",
        expires_at: 1.year.from_now,
        created_at: 2.days.ago,
        updated_at: 2.days.ago
      )

      observation_id = legacy_insert(
        :observations,
        policy_id: policy_id,
        station_id: rainfall_station.id,
        rainfall_mm: BigDecimal("10.0"),
        observed_at: Time.zone.local(2026, 7, 8, 12, 0, 0),
        created_at: 1.day.ago,
        updated_at: 1.day.ago
      )

      payout_id = legacy_insert(
        :payouts,
        policy_id: policy_id,
        payout_tier_id: alternative_payout_tier.id,
        payout_status_id: payout_status.id,
        observation_id: observation_id,
        idempotency_key: "tier-mismatch-#{SecureRandom.hex(4)}",
        decided_at: 1.day.ago,
        created_at: 1.day.ago,
        updated_at: 1.day.ago
      )

      migration.up

      reset_model_column_information

      expect(Payout.find(payout_id).payout_tier_id).to eq(Policy.find(policy_id).payout_tier_id)
      expect(Payout.find(payout_id).payout_tier_id).to eq(payout_tier.id)
    end

    it "keeps policies with multiple stations as nil and allows the integrity checks to continue" do
      policy_id = legacy_insert(
        :policies,
        user_id: user.id,
        plan_id: rainfall_plan.id,
        payout_tier_id: payout_tier.id,
        policy_status_id: policy_status.id,
        threshold: "50mm",
        expires_at: 1.year.from_now,
        created_at: 2.days.ago,
        updated_at: 2.days.ago
      )

      first_observation_id = legacy_insert(
        :observations,
        policy_id: policy_id,
        station_id: rainfall_station.id,
        rainfall_mm: BigDecimal("10.0"),
        observed_at: Time.zone.local(2026, 7, 4, 9, 0, 0),
        created_at: 1.day.ago,
        updated_at: 1.day.ago
      )
      second_observation_id = legacy_insert(
        :observations,
        policy_id: policy_id,
        station_id: secondary_rainfall_station.id,
        rainfall_mm: BigDecimal("11.0"),
        observed_at: Time.zone.local(2026, 7, 4, 10, 0, 0),
        created_at: 1.day.ago,
        updated_at: 1.day.ago
      )
      first_payout_id = legacy_insert(
        :payouts,
        policy_id: policy_id,
        payout_tier_id: payout_tier.id,
        payout_status_id: payout_status.id,
        observation_id: first_observation_id,
        idempotency_key: "ambiguous-1-#{SecureRandom.hex(4)}",
        decided_at: 1.day.ago,
        created_at: 1.day.ago,
        updated_at: 1.day.ago
      )
      second_payout_id = legacy_insert(
        :payouts,
        policy_id: policy_id,
        payout_tier_id: payout_tier.id,
        payout_status_id: payout_status.id,
        observation_id: second_observation_id,
        idempotency_key: "ambiguous-2-#{SecureRandom.hex(4)}",
        decided_at: 1.day.ago,
        created_at: 1.day.ago,
        updated_at: 1.day.ago
      )

      expect { migration.up }.not_to raise_error

      reset_model_column_information

      expect(Policy.find(policy_id).station_id).to be_nil
      expect(Payout.find(first_payout_id).observation_id).to eq(first_observation_id)
      expect(Payout.find(second_payout_id).observation_id).to eq(second_observation_id)
    end

    it "isolates orphan payouts and survey responses into the legacy tables" do
      orphan_payout_idempotency_key = "orphan-payout-#{SecureRandom.hex(4)}"
      policy_id = legacy_insert(
        :policies,
        user_id: user.id,
        plan_id: rainfall_plan.id,
        payout_tier_id: payout_tier.id,
        policy_status_id: policy_status.id,
        threshold: "30mm",
        expires_at: 1.year.from_now,
        created_at: 2.days.ago,
        updated_at: 2.days.ago
      )
      payout_id = legacy_insert(
        :payouts,
        policy_id: policy_id,
        payout_tier_id: payout_tier.id,
        payout_status_id: payout_status.id,
        observation_id: nil,
        idempotency_key: orphan_payout_idempotency_key,
        decided_at: nil,
        created_at: 1.day.ago,
        updated_at: 1.day.ago
      )
      survey_response_id = legacy_insert(
        :survey_responses,
        user_id: user.id,
        policy_id: policy_id,
        response_data: { "q1" => "yes" },
        created_at: 1.day.ago,
        updated_at: 1.day.ago
      )

      ActiveRecord::Base.connection.disable_referential_integrity do
        ActiveRecord::Base.connection.execute("DELETE FROM policies WHERE id = #{policy_id}")
      end

      migration.up

      reset_model_column_information

      expect(Payout.exists?(payout_id)).to be(false)
      legacy_payout = LegacyPayout.find_by(idempotency_key: orphan_payout_idempotency_key)
      expect(legacy_payout).to be_present
      expect(legacy_payout.isolation_reason).to include("Associated policy with ID")

      expect(SurveyResponse.exists?(survey_response_id)).to be(false)
      legacy_survey_response = LegacySurveyResponse.find_by(user_id: user.id, policy_id: policy_id)
      expect(legacy_survey_response).to be_present
      expect(legacy_survey_response.migration_error_reason).to include("Associated policy with ID")
    end

    it "raises when duplicate rainfall observations have conflicting rainfall values" do
      policy_id = legacy_insert(
        :policies,
        user_id: user.id,
        plan_id: rainfall_plan.id,
        payout_tier_id: payout_tier.id,
        policy_status_id: policy_status.id,
        threshold: "30mm",
        expires_at: 1.year.from_now,
        created_at: 2.days.ago,
        updated_at: 2.days.ago
      )

      observation_time = Time.zone.local(2026, 7, 6, 12, 0, 0)
      legacy_insert(
        :observations,
        policy_id: policy_id,
        station_id: rainfall_station.id,
        rainfall_mm: BigDecimal("10.0"),
        observed_at: observation_time,
        created_at: observation_time,
        updated_at: observation_time
      )
      legacy_insert(
        :observations,
        policy_id: policy_id,
        station_id: rainfall_station.id,
        rainfall_mm: BigDecimal("11.0"),
        observed_at: observation_time,
        created_at: observation_time,
        updated_at: observation_time
      )

      expect { migration.up }
        .to raise_error(/Conflicting duplicate rainfall values found/)
    end

    it "raises when duplicate seismic observations include an unresolvable intensity level" do
      policy_id = legacy_insert(
        :policies,
        user_id: user.id,
        plan_id: seismic_plan.id,
        payout_tier_id: payout_tier.id,
        policy_status_id: policy_status.id,
        threshold: "5弱",
        expires_at: 1.year.from_now,
        created_at: 2.days.ago,
        updated_at: 2.days.ago
      )

      observation_time = Time.zone.local(2026, 7, 7, 12, 0, 0)
      legacy_insert(
        :observations,
        policy_id: policy_id,
        station_id: seismic_station.id,
        seismic_intensity_level_id: seismic_level_5.id,
        observed_at: observation_time,
        created_at: observation_time,
        updated_at: observation_time
      )
      legacy_insert(
        :observations,
        policy_id: policy_id,
        station_id: seismic_station.id,
        seismic_intensity_level_id: nil,
        observed_at: observation_time,
        created_at: observation_time,
        updated_at: observation_time
      )

      expect { migration.up }
        .to raise_error(/references a missing or unresolvable SeismicIntensityLevel/)
    end

    it "raises when a payout observation station is corrupted after the policy station backfill" do
      policy_id = legacy_insert(
        :policies,
        user_id: user.id,
        plan_id: rainfall_plan.id,
        payout_tier_id: payout_tier.id,
        policy_status_id: policy_status.id,
        threshold: "30mm",
        expires_at: 1.year.from_now,
        created_at: 2.days.ago,
        updated_at: 2.days.ago
      )
      observation_id = legacy_insert(
        :observations,
        policy_id: policy_id,
        station_id: rainfall_station.id,
        rainfall_mm: BigDecimal("10.0"),
        observed_at: Time.zone.local(2026, 7, 8, 12, 0, 0),
        created_at: 1.day.ago,
        updated_at: 1.day.ago
      )
      legacy_insert(
        :payouts,
        policy_id: policy_id,
        payout_tier_id: payout_tier.id,
        payout_status_id: payout_status.id,
        observation_id: observation_id,
        idempotency_key: "corrupt-d-#{SecureRandom.hex(4)}",
        decided_at: 1.day.ago,
        created_at: 1.day.ago,
        updated_at: 1.day.ago
      )

      policy_update_calls = 0
      allow_any_instance_of(described_class::Policy).to receive(:update_columns).and_wrap_original do |original, *args|
        policy_update_calls += 1
        result = original.call(*args)
        if policy_update_calls == 1
          described_class::Policy.where(id: policy_id).update_all(station_id: secondary_rainfall_station.id)
        end
        result
      end

      expect { migration.up }
        .to raise_error(/Data corruption detected: Payout .*does not match policy station/)
    end

    it "raises when a backfilled payout observation station is corrupted after the policy station backfill" do
      policy_id = legacy_insert(
        :policies,
        user_id: user.id,
        plan_id: rainfall_plan.id,
        payout_tier_id: payout_tier.id,
        policy_status_id: policy_status.id,
        threshold: "30mm",
        expires_at: 1.year.from_now,
        created_at: 2.days.ago,
        updated_at: 2.days.ago
      )
      legacy_insert(
        :payouts,
        policy_id: policy_id,
        payout_tier_id: payout_tier.id,
        payout_status_id: payout_status.id,
        observation_id: nil,
        idempotency_key: "corrupt-e-#{SecureRandom.hex(4)}",
        decided_at: nil,
        created_at: Time.zone.local(2026, 7, 9, 12, 0, 0),
        updated_at: Time.zone.local(2026, 7, 9, 12, 0, 0)
      )

      policy_update_calls = 0
      allow_any_instance_of(described_class::Policy).to receive(:update_columns).and_wrap_original do |original, *args|
        policy_update_calls += 1
        result = original.call(*args)
        if policy_update_calls == 2
          described_class::Policy.where(id: policy_id).update_all(station_id: secondary_rainfall_station.id)
        end
        result
      end

      expect { migration.up }
        .to raise_error(/Data corruption detected after backfill: Payout .*does not match policy station/)
    end

    it "raises when the plan trigger type does not match the station measurement type" do
      policy_id = legacy_insert(
        :policies,
        user_id: user.id,
        plan_id: rainfall_plan.id,
        payout_tier_id: payout_tier.id,
        policy_status_id: policy_status.id,
        threshold: "30mm",
        expires_at: 1.year.from_now,
        created_at: 2.days.ago,
        updated_at: 2.days.ago
      )
      observation_id = legacy_insert(
        :observations,
        policy_id: policy_id,
        station_id: seismic_station.id,
        seismic_intensity_level_id: seismic_level_5.id,
        observed_at: Time.zone.local(2026, 7, 5, 12, 0, 0),
        created_at: 1.day.ago,
        updated_at: 1.day.ago
      )
      legacy_insert(
        :payouts,
        policy_id: policy_id,
        payout_tier_id: payout_tier.id,
        payout_status_id: payout_status.id,
        observation_id: observation_id,
        idempotency_key: "mismatch-#{SecureRandom.hex(4)}",
        decided_at: 1.day.ago,
        created_at: 1.day.ago,
        updated_at: 1.day.ago
      )

      expect { migration.up }
        .to raise_error(/measurement type does not match plan trigger type/)
    end
  end

  describe "#down" do
    it "raises ActiveRecord::IrreversibleMigration" do
      expect { migration.down }
        .to raise_error(ActiveRecord::IrreversibleMigration)
    end
  end
end
