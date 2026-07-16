require "rails_helper"

RSpec.describe "Admin dashboard", type: :request do
  let(:admin_user) { "admin" }
  let(:admin_password) { "changeme" }
  let(:auth_headers) do
    {
      "Authorization" => "Basic #{Base64.strict_encode64("#{admin_user}:#{admin_password}")}"
    }
  end

  let(:user) { User.create!(google_sub: "google-sub-admin-dashboard") }
  let(:plan) do
    Plan.create!(
      code: "seismic_admin_dashboard",
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
      code: "seismic_tokyo_admin_dashboard",
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
      code: "ten_thousand_admin_dashboard",
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

  let!(:processing_status) { PolicyStatus.find_or_create_by!(code: "processing", sort_order: 2, label_ja: "支払処理中", label_en: "Processing", label_fr: "Processing", label_zh: "Processing", label_ru: "Processing", label_es: "Processing", label_ar: "Processing") }
  let!(:ordered_status) { PayoutStatus.find_or_create_by!(code: "ordered", sort_order: 0, label_ja: "指図済", label_en: "Ordered", label_fr: "Ordered", label_zh: "Ordered", label_ru: "Ordered", label_es: "Ordered", label_ar: "Ordered") }
  let!(:completed_status) { PayoutStatus.find_or_create_by!(code: "completed_simulated", sort_order: 1, label_ja: "支払完了（模擬）", label_en: "Completed", label_fr: "Completed", label_zh: "Completed", label_ru: "Completed", label_es: "Completed", label_ar: "Completed") }
  let!(:seismic_level) { SeismicIntensityLevel.create!(code: "5_strong_admin_dashboard", sort_order: 6, label_ja: "5強", label_en: "5 strong", label_fr: "5 strong", label_zh: "5 strong", label_ru: "5 strong", label_es: "5 strong", label_ar: "5 strong") }

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
      event_id: "event-admin-dashboard-001",
      observed_at: Time.zone.parse("2026-07-15 10:00:00"),
      seismic_intensity_level: seismic_level,
      max_value: seismic_level.sort_order,
      simulated: false
    )
  end

  let!(:ordered_payout) do
    Payout.create!(
      policy: policy,
      payout_tier: payout_tier,
      payout_status: ordered_status,
      observation: observation,
      idempotency_key: "policy_#{policy.id}_event_event-admin-dashboard-001",
      decided_at: Time.current
    )
  end

  let!(:completed_payout) do
    Payout.create!(
      policy: policy,
      payout_tier: payout_tier,
      payout_status: completed_status,
      observation: observation,
      idempotency_key: "policy_#{policy.id}_event_event-admin-dashboard-002",
      decided_at: Time.current
    )
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ADMIN_BASIC_USER").and_return(admin_user)
    allow(ENV).to receive(:[]).with("ADMIN_BASIC_PASSWORD").and_return(admin_password)
  end

  it "returns 401 without BASIC auth" do
    get "/admin"

    expect(response).to have_http_status(:unauthorized)
  end

  it "renders the contract list with real data" do
    get "/admin", headers: auth_headers

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("契約一覧")
    expect(response.body).to include(user.google_sub)
    expect(response.body).to include(plan.code)
    expect(response.body).to include(station.code)
    expect(response.body).to include("5強")
    expect(response.body).to include("processing")
    expect(response.body).to include("2")
    expect(response.body).to include("2025-12-31 09:00")
  end

  it "renders the payout list and action buttons" do
    get "/admin/payouts", headers: auth_headers

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("支払一覧")
    expect(response.body).to include(ordered_payout.id.to_s)
    expect(response.body).to include("支払完了（模擬）にする")
    expect(response.body).to include("無効化")
    expect(response.body).to include(completed_payout.payout_status.code)
  end

  describe "session cookie scope" do
    around do |example|
      orig = ActionController::Base.allow_forgery_protection
      begin
        ActionController::Base.allow_forgery_protection = true
        example.run
      ensure
        ActionController::Base.allow_forgery_protection = orig
      end
    end

    it "scopes the CSRF session cookie to /admin with SameSite=Strict, not the app-wide default" do
      get "/admin/payouts", headers: auth_headers

      set_cookie = response.headers["Set-Cookie"]

      expect(set_cookie).to include("_backend_admin_session=")
      expect(set_cookie).to include("path=/admin")
      expect(set_cookie).to include("samesite=strict")
      expect(set_cookie).not_to include("_session_id=")
    end
  end
end
