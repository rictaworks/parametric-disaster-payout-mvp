require "rails_helper"

RSpec.describe "Admin simulated events", type: :request do
  include ActiveJob::TestHelper

  let(:admin_user) { "admin" }
  let(:admin_password) { "changeme" }
  let(:auth_headers) do
    {
      "Authorization" => "Basic #{Base64.strict_encode64("#{admin_user}:#{admin_password}")}"
    }
  end
  let(:internal_api_secret) { "shared-secret" }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ADMIN_BASIC_USER").and_return(admin_user)
    allow(ENV).to receive(:[]).with("ADMIN_BASIC_PASSWORD").and_return(admin_password)
    allow(ENV).to receive(:[]).with("INTERNAL_API_SECRET").and_return(internal_api_secret)
    ActiveJob::Base.queue_adapter = :test
  end

  after do
    clear_enqueued_jobs
    clear_performed_jobs
    ActiveJob::Base.queue_adapter = :test
  end

  let(:user) { User.create!(google_sub: "google-sub-admin-simulated-events") }
  let(:seismic_plan) do
    Plan.create!(
      code: "seismic_admin_simulated_events",
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
  let(:rainfall_plan) do
    Plan.create!(
      code: "rainfall_admin_simulated_events",
      trigger_type: "rainfall",
      label_ja: "降雨連動",
      label_en: "Rainfall-linked",
      label_fr: "Rainfall-linked",
      label_zh: "Rainfall-linked",
      label_ru: "Rainfall-linked",
      label_es: "Rainfall-linked",
      label_ar: "Rainfall-linked"
    )
  end
  let(:seismic_station) do
    Station.create!(
      code: "seismic_tokyo_admin_simulated_events",
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
  let(:rainfall_station) do
    Station.create!(
      code: "rainfall_tokyo_admin_simulated_events",
      measurement_type: "rainfall",
      label_ja: "東京雨量観測点",
      label_en: "Tokyo rainfall station",
      label_fr: "Tokyo rainfall station",
      label_zh: "Tokyo rainfall station",
      label_ru: "Tokyo rainfall station",
      label_es: "Tokyo rainfall station",
      label_ar: "Tokyo rainfall station"
    )
  end
  let(:payout_tier) do
    PayoutTier.create!(
      code: "ten_thousand_admin_simulated_events",
      amount_yen: 10_000,
      label_ja: "1万円相当（模擬）",
      label_en: "Equivalent to JPY 10,000 (simulated)",
      label_fr: "Equivalent to JPY 10,000 (simulated)",
      label_zh: "Equivalent to JPY 10,000 (simulated)",
      label_ru: "Equivalent to JPY 10,000 (simulated)",
      label_es: "Equivalent to JPY 10,000 (simulated)",
      label_ar: "Equivalent to JPY 10,000 (simulated)"
    )
  end
  let!(:processing_status) { PolicyStatus.find_or_create_by!(code: "processing", sort_order: 2, label_ja: "支払処理中", label_en: "Processing", label_fr: "Processing", label_zh: "Processing", label_ru: "Processing", label_es: "Processing", label_ar: "Processing") }
  let(:active_status) { PolicyStatus.find_or_create_by!(code: "active", sort_order: 1, label_ja: "有効", label_en: "Active", label_fr: "Active", label_zh: "Active", label_ru: "Active", label_es: "Active", label_ar: "Active") }
  let!(:ordered_status) { PayoutStatus.find_or_create_by!(code: "ordered", sort_order: 0, label_ja: "指図済", label_en: "Ordered", label_fr: "Ordered", label_zh: "Ordered", label_ru: "Ordered", label_es: "Ordered", label_ar: "Ordered") }
  let(:completed_status) { PayoutStatus.find_or_create_by!(code: "completed_simulated", sort_order: 1, label_ja: "支払完了（模擬）", label_en: "Completed", label_fr: "Completed", label_zh: "Completed", label_ru: "Completed", label_es: "Completed", label_ar: "Completed") }
  let(:seismic_level_4) { SeismicIntensityLevel.create!(code: "4_admin_simulated_events", sort_order: 4, label_ja: "4", label_en: "4", label_fr: "4", label_zh: "4", label_ru: "4", label_es: "4", label_ar: "4") }
  let(:seismic_level_5_weak) { SeismicIntensityLevel.create!(code: "5_weak_admin_simulated_events", sort_order: 5, label_ja: "5弱", label_en: "5 weak", label_fr: "5 weak", label_zh: "5 weak", label_ru: "5 weak", label_es: "5 weak", label_ar: "5 weak") }

  let!(:seismic_policy) do
    Policy.create!(
      user: user,
      plan: seismic_plan,
      station: seismic_station,
      payout_tier: payout_tier,
      policy_status: active_status,
      threshold: "5弱"
    ).tap do |policy|
      policy.update_columns(waiting_until: Time.zone.parse("2025-12-31 09:00:00"), expires_at: Time.zone.parse("2027-07-15 09:00:00"))
    end
  end

  let!(:rainfall_policy) do
    Policy.create!(
      user: user,
      plan: rainfall_plan,
      station: rainfall_station,
      payout_tier: payout_tier,
      policy_status: active_status,
      threshold: "10 mm"
    ).tap do |policy|
      policy.update_columns(waiting_until: Time.zone.parse("2025-12-31 09:00:00"), expires_at: Time.zone.parse("2027-07-15 09:00:00"))
    end
  end

  it "renders the injection UI and existing event list" do
    Observation.create!(
      station: seismic_station,
      event_id: "seed-event",
      observed_at: Time.zone.parse("2026-07-15 09:00:00"),
      seismic_intensity_level: seismic_level_4,
      max_value: seismic_level_4.sort_order,
      simulated: false
    )

    get "/admin/simulated_events", headers: auth_headers

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("模擬イベント注入")
    expect(response.body).to include("新規イベント")
    expect(response.body).to include("既存イベントへの続報")
    expect(response.body).to include("東京震度観測点 (seismic_tokyo_admin_simulated_events)")
    expect(response.body).to include("seed-event")
  end

  it "injects a seismic event, updates the max only when the new value is higher, and exposes the notification in mypage APIs" do
    post "/admin/simulated_events",
      headers: auth_headers,
      params: {
        station_id: seismic_station.id,
        event_mode: "new",
        seismic_intensity_level_id: seismic_level_4.id
      }

    observation = Observation.find_by!(station: seismic_station)
    ObservationReevaluationJob.perform_now(observation.id)
    expect(observation.simulated).to be(true)
    expect(observation.max_value).to eq(BigDecimal("4"))
    expect(Payout.count).to eq(0)

    post "/admin/simulated_events",
      headers: auth_headers,
      params: {
        station_id: seismic_station.id,
        event_mode: "follow_up",
        observation_id: observation.id,
        seismic_intensity_level_id: seismic_level_5_weak.id
      }

    ObservationReevaluationJob.perform_now(observation.id)

    expect(observation.reload.max_value).to eq(BigDecimal("5"))
    expect(Payout.count).to eq(1)
    expect(Notification.pluck(:kind)).to contain_exactly(Notification::KIND_PAYOUT_ORDERED)

    post "/admin/simulated_events",
      headers: auth_headers,
      params: {
        station_id: seismic_station.id,
        event_mode: "follow_up",
        observation_id: observation.id,
        seismic_intensity_level_id: seismic_level_4.id
      }

    ObservationReevaluationJob.perform_now(observation.id)

    expect(observation.reload.max_value).to eq(BigDecimal("5"))
    expect(Payout.count).to eq(1)

    get "/api/v1/notifications",
      headers: {
        "X-Internal-API-Secret" => internal_api_secret,
        "X-Internal-Session-Token" => user.internal_session_token
      }

    body = JSON.parse(response.body)
    expect(body["notifications"].map { |notification| notification["kind"] }).to include(Notification::KIND_PAYOUT_ORDERED)
  end

  it "injects a rainfall event with simulated=true and generates a payout" do
    post "/admin/simulated_events",
      headers: auth_headers,
      params: {
        station_id: rainfall_station.id,
        event_mode: "new",
        rainfall_mm: "12.5"
      }

    observation = Observation.find_by!(station: rainfall_station)
    ObservationReevaluationJob.perform_now(observation.id)
    expect(observation.simulated).to be(true)
    expect(observation.rainfall_mm).to eq(BigDecimal("12.5"))
    expect(observation.max_value).to eq(BigDecimal("12.5"))
    expect(Payout.count).to eq(1)
    expect(Payout.first.payout_status).to eq(ordered_status)
    expect(rainfall_policy.reload.policy_status.code).to eq("processing")
    expect(Notification.pluck(:kind)).to contain_exactly(Notification::KIND_PAYOUT_ORDERED)
  end
end
