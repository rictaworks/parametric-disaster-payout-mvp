require "rails_helper"
require "securerandom"
require "tmpdir"
require_relative "../../../db/migrate/20260717130000_add_admin_injected_to_observations"

RSpec.describe AddAdminInjectedToObservations, type: :migration do
  self.use_transactional_tests = false

  subject(:migration) { described_class.new }

  let(:original_db_config) { ActiveRecord::Base.connection_db_config.configuration_hash }

  around do |example|
    run_against_pre_migration_database do
      example.run
    end
  end

  # このマイグレーション適用前（=デプロイ前に管理画面から模擬イベント注入済みの
  # 本番相当の状態）を再現するため、1つ前のマイグレーションまでで止めた
  # 使い捨てDBを用意する。
  def run_against_pre_migration_database
    db_path = File.join(Dir.tmpdir, "pre-admin-injected-migration-#{SecureRandom.hex(8)}.sqlite3")
    db_config = original_db_config.merge(database: db_path)

    ActiveRecord::Base.connection_handler.clear_all_connections!
    ActiveRecord::Base.establish_connection(db_config)
    ActiveRecord::MigrationContext.new([ Rails.root.join("db/migrate").to_s ]).migrate(20260716145154)
    reset_model_column_information

    yield
  ensure
    ActiveRecord::Base.remove_connection
    ActiveRecord::Base.establish_connection(original_db_config)
    reset_model_column_information
  end

  def reset_model_column_information
    [ Station, SeismicIntensityLevel, Observation, ObservationEvent ].each(&:reset_column_information)
  end

  def localized_attributes(name)
    {
      label_ja: name, label_en: name, label_fr: name, label_zh: name,
      label_ru: name, label_es: name, label_ar: name
    }
  end

  let!(:station) { Station.create!(code: "seismic_migration_test", measurement_type: "seismic", **localized_attributes("5強")) }
  let!(:seismic_level) { SeismicIntensityLevel.create!(code: "5_strong_migration_test", sort_order: 6, **localized_attributes("5強")) }

  it "管理画面注入由来（payloadにstation_id）のsimulated観測だけをadmin_injected: trueへバックフィルする" do
    # 管理画面注入由来（Admin::SimulatedEventsController は payload に station_id を使う）
    admin_observation = Observation.create!(
      station: station, event_id: "simulated-seismic_migration_test-abc123", observed_at: Time.current,
      seismic_intensity_level: seismic_level, max_value: seismic_level.sort_order, simulated: true
    )
    admin_observation.observation_events.create!(
      occurred_at: Time.current,
      payload: { station_id: station.id, event_id: admin_observation.event_id, seismic_intensity_level_id: seismic_level.id, simulated: true }
    )

    # 気象庁ポーリング由来の訓練報（JmaPoller は payload に station_code を使う）
    jma_training_observation = Observation.create!(
      station: station, event_id: "training-report-xyz", observed_at: Time.current,
      seismic_intensity_level: seismic_level, max_value: seismic_level.sort_order, simulated: true
    )
    jma_training_observation.observation_events.create!(
      occurred_at: Time.current,
      payload: { station_code: station.code, event_id: jma_training_observation.event_id, seismic_intensity_level_label_ja: "5強", simulated: true }
    )

    # 通常の実観測（simulated: false）はバックフィル対象外
    real_observation = Observation.create!(
      station: station, event_id: "real-event", observed_at: Time.current,
      seismic_intensity_level: seismic_level, max_value: seismic_level.sort_order, simulated: false
    )
    real_observation.observation_events.create!(
      occurred_at: Time.current,
      payload: { station_code: station.code, event_id: real_observation.event_id, seismic_intensity_level_label_ja: "5強", simulated: false }
    )

    migration.up

    Observation.reset_column_information
    expect(Observation.find(admin_observation.id).admin_injected).to be true
    expect(Observation.find(jma_training_observation.id).admin_injected).to be false
    expect(Observation.find(real_observation.id).admin_injected).to be false
  end

  it "履歴（observation_events）が存在しないsimulated観測はadmin_injected: falseのままになる（安全側のデフォルト）" do
    orphan_observation = Observation.create!(
      station: station, event_id: "no-history-event", observed_at: Time.current,
      seismic_intensity_level: seismic_level, max_value: seismic_level.sort_order, simulated: true
    )

    migration.up

    Observation.reset_column_information
    expect(Observation.find(orphan_observation.id).admin_injected).to be false
  end

  it "downでカラムが削除される" do
    migration.up
    migration.down

    expect(ActiveRecord::Base.connection.column_exists?(:observations, :admin_injected)).to be false
  end
end
