# PR#57 Playwright E2Eテスト用のサンプルデータ投入スクリプト。
#
# `bin/rails runner test/pr57/seed_sample_data.rb` として実行する想定。
# RAILS_ENV=test（storage/test.sqlite3、開発DB・本番DBとは別のファイル）でのみ
# 実行することを前提とする。マスタデータ（26件）を投入したうえで、
# 「リセット前は契約一覧・支払一覧にデータが見える」→「リセット後は消える」
# という非エンジニア向けテスト手順（手順5）を再現するためのサンプル1件を
# 冪等（何度実行しても同じ状態になる）に作成する。

if Rails.env.production?
  raise "このスクリプトは production では実行できません"
end

# Rails.env.production? のチェックだけでは不十分（本番向け DATABASE_URL が
# 設定されたまま RAILS_ENV=test で実行された場合、Railsは database.yml の
# test セクションよりも DATABASE_URL を優先して本番DBへ接続してしまう）。
# 破壊的な書き込みの前に、実際の接続先がローカルの使い捨てSQLite test DBで
# あることを検証する。
unless Rails.env.test?
  raise "このスクリプトは RAILS_ENV=test でのみ実行できます（現在: #{Rails.env}）"
end

config = ActiveRecord::Base.configurations.configs_for(env_name: "test").first
expected_db_path = Rails.root.join("storage", "test.sqlite3")
actual_db_path = Rails.root.join(config.database)

if config.adapter != "sqlite3" || actual_db_path != expected_db_path
  raise "安全チェック失敗: 接続先がローカルの使い捨てSQLite test DB(#{expected_db_path})ではありません" \
        "（adapter=#{config.adapter}, database=#{actual_db_path}）。DATABASE_URL等の環境変数が" \
        "接続先を上書きしていないか確認してください。破壊的な処理は中止します。"
end

load Rails.root.join("db/seeds.rb")

user = User.find_or_create_by!(google_sub: "google-sub-pr57-e2e-user")
plan = Plan.find_by!(code: "seismic")
station = Station.find_by!(code: "seismic_tokyo")
payout_tier = PayoutTier.find_by!(code: "ten_thousand")
processing_status = PolicyStatus.find_by!(code: "processing")
completed_payout_status = PayoutStatus.find_by!(code: "completed_simulated")
seismic_level = SeismicIntensityLevel.find_by!(code: "5_strong")

policy = Policy.find_or_create_by!(user: user, plan: plan, station: station) do |record|
  record.payout_tier = payout_tier
  record.policy_status = processing_status
  record.threshold = "5強"
end
policy.update_columns(
  waiting_until: 1.day.ago,
  expires_at: 1.year.from_now
)

observation = Observation.find_or_create_by!(event_id: "event-pr57-e2e-001") do |record|
  record.station = station
  record.observed_at = Time.current
  record.seismic_intensity_level = seismic_level
  record.max_value = seismic_level.sort_order
  record.simulated = true
end

payout = Payout.find_or_create_by!(idempotency_key: "policy_#{policy.id}_event_event-pr57-e2e-001") do |record|
  record.policy = policy
  record.payout_tier = payout_tier
  record.payout_status = completed_payout_status
  record.observation = observation
  record.decided_at = Time.current
end

Notification.find_or_create_by!(user: user, policy: policy, payout: payout, kind: Notification::KIND_PAYOUT_ORDERED) do |record|
  record.message = "ordered"
end

SurveyResponse.find_or_create_by!(user: user, payout: payout) do |record|
  record.response_data = { "satisfaction" => 5, "answer" => "yes" }
end

ProcessedJmaEntry.find_or_create_by!(entry_id: "urn:uuid:pr57-e2e-entry")

puts "PR#57 E2E sample data ready: policy=#{policy.id} payout=#{payout.id}"
