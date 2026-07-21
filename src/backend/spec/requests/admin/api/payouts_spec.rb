require "rails_helper"

RSpec.describe "PATCH /admin/api/payouts/:id/complete", type: :request do
  let(:admin_user) { "admin" }
  let(:admin_password) { "changeme" }
  let(:auth_headers) do
    {
      "Authorization" => "Basic #{Base64.strict_encode64("#{admin_user}:#{admin_password}")}"
    }
  end

  let(:user) { User.create!(google_sub: "google-sub-admin-payouts") }
  let(:plan) do
    Plan.create!(
      code: "seismic_admin_payouts_spec",
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
      code: "seismic_tokyo_admin_payouts_spec",
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
      code: "ten_thousand_admin_payouts_spec",
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
  let!(:active_status) { PolicyStatus.find_or_create_by!(code: "active", sort_order: 1, label_ja: "有効", label_en: "Active", label_fr: "Active", label_zh: "Active", label_ru: "Active", label_es: "Active", label_ar: "Active") }

  let!(:ordered_payout_status) { PayoutStatus.find_or_create_by!(code: "ordered", sort_order: 0, label_ja: "指図済", label_en: "Ordered", label_fr: "Ordered", label_zh: "Ordered", label_ru: "Ordered", label_es: "Ordered", label_ar: "Ordered") }
  let!(:completed_payout_status) { PayoutStatus.find_or_create_by!(code: "completed_simulated", sort_order: 1, label_ja: "支払完了（模擬）", label_en: "Completed", label_fr: "Completed", label_zh: "Completed", label_ru: "Completed", label_es: "Completed", label_ar: "Completed") }
  let!(:invalid_payout_status) { PayoutStatus.find_or_create_by!(code: "invalid", sort_order: 2, label_ja: "無効", label_en: "Invalid", label_fr: "Invalid", label_zh: "Invalid", label_ru: "Invalid", label_es: "Invalid", label_ar: "Invalid") }

  let!(:seismic_level_5_strong) { SeismicIntensityLevel.create!(code: "5_strong_admin_payouts_spec", sort_order: 6, label_ja: "5強", label_en: "5 strong", label_fr: "5 strong", label_zh: "5 strong", label_ru: "5 strong", label_es: "5 strong", label_ar: "5 strong") }

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
      event_id: "event-admin-payouts-001",
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
      idempotency_key: "policy_#{policy.id}_event_event-admin-payouts-001",
      decided_at: Time.current
    )
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ADMIN_BASIC_USER").and_return(admin_user)
    allow(ENV).to receive(:[]).with("ADMIN_BASIC_PASSWORD").and_return(admin_password)
  end

  it "returns 401 without BASIC auth" do
    patch "/admin/api/payouts/#{payout.id}/complete"

    expect(response).to have_http_status(:unauthorized)
  end

  it "completes the payout and creates completion notifications with BASIC auth" do
    patch "/admin/api/payouts/#{payout.id}/complete", headers: auth_headers

    expect(response).to have_http_status(:ok)

    body = JSON.parse(response.body)
    expect(body["payout"]).to include(
      "id" => payout.id,
      "payout_status_code" => "completed_simulated",
      "policy_status_code" => "active"
    )
    expect(payout.reload.payout_status).to eq(completed_payout_status)
    expect(policy.reload.policy_status).to eq(active_status)
    expect(Notification.pluck(:kind)).to contain_exactly(
      Notification::KIND_PAYOUT_COMPLETED,
      Notification::KIND_SURVEY_REQUEST
    )
  end

  it "returns 200 and does not change state when payout is already completed" do
    payout.update!(payout_status: completed_payout_status)
    Notification.create!(user: user, policy: policy, payout: payout, kind: Notification::KIND_PAYOUT_COMPLETED, message: "completed")
    Notification.create!(user: user, policy: policy, payout: payout, kind: Notification::KIND_SURVEY_REQUEST, message: "survey")

    expect {
      patch "/admin/api/payouts/#{payout.id}/complete", headers: auth_headers
    }.not_to change { Notification.count }

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["payout"]).to include(
      "id" => payout.id,
      "payout_status_code" => "completed_simulated"
    )
  end

  it "redirects back to the admin page when a return_to parameter is provided" do
    patch "/admin/api/payouts/#{payout.id}/complete", headers: auth_headers, params: { return_to_admin_payouts: "1" }

    expect(response).to have_http_status(:see_other)
    expect(response).to redirect_to("/admin/payouts")
    expect(payout.reload.payout_status).to eq(completed_payout_status)
  end

  it "handles POST request with _method=patch from HTML forms (Rack::MethodOverride)" do
    post "/admin/api/payouts/#{payout.id}/complete", headers: auth_headers, params: { _method: "patch", return_to_admin_payouts: "1" }

    expect(response).to have_http_status(:see_other)
    expect(response).to redirect_to("/admin/payouts")
    expect(payout.reload.payout_status).to eq(completed_payout_status)
  end

  it "returns 422 and does not process when payout is invalid" do
    invalid_status = PayoutStatus.find_or_create_by!(code: "invalid", sort_order: 2, label_ja: "無効", label_en: "Invalid", label_fr: "Invalid", label_zh: "Invalid", label_ru: "Invalid", label_es: "Invalid", label_ar: "Invalid")
    payout.update_columns(payout_status_id: invalid_status.id)

    expect {
      patch "/admin/api/payouts/#{payout.id}/complete", headers: auth_headers
    }.not_to change { Notification.count }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(payout.reload.payout_status).to eq(invalid_status)
    expect(policy.reload.policy_status.code).to eq("processing")
  end

  it "invalidates an ordered payout" do
    patch "/admin/api/payouts/#{payout.id}/invalidate", headers: auth_headers

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["payout"]).to include(
      "id" => payout.id,
      "payout_status_code" => "invalid"
    )
    expect(payout.reload.payout_status.code).to eq("invalid")
    expect(policy.reload.policy_status.code).to eq("active")
  end

  it "returns 422 when invalidating a completed payout" do
    payout.update!(payout_status: completed_payout_status)

    patch "/admin/api/payouts/#{payout.id}/invalidate", headers: auth_headers

    expect(response).to have_http_status(:unprocessable_entity)
    expect(payout.reload.payout_status).to eq(completed_payout_status)
  end

  describe "CSRF protection" do
    around do |example|
      orig_base = ActionController::Base.allow_forgery_protection
      begin
        ActionController::Base.allow_forgery_protection = true
        example.run
      ensure
        ActionController::Base.allow_forgery_protection = orig_base
      end
    end

    it "rejects complete request without CSRF token" do
      patch "/admin/api/payouts/#{payout.id}/complete", headers: auth_headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects invalidate request without CSRF token" do
      patch "/admin/api/payouts/#{payout.id}/invalidate", headers: auth_headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "accepts a CSRF-protected form submission for complete" do
      get "/admin/payouts", headers: auth_headers
      token = Nokogiri::HTML.parse(response.body)
        .at_css(%(form[action="/admin/api/payouts/#{payout.id}/complete"] input[name="authenticity_token"]))
        &.[]("value")

      expect(token).to be_present

      post "/admin/api/payouts/#{payout.id}/complete", headers: auth_headers, params: {
        _method: "patch",
        authenticity_token: token,
        return_to_admin_payouts: "1"
      }

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to("/admin/payouts")
      expect(payout.reload.payout_status).to eq(completed_payout_status)
    end

    it "accepts a CSRF-protected form submission for invalidate" do
      get "/admin/payouts", headers: auth_headers
      token = Nokogiri::HTML.parse(response.body)
        .at_css(%(form[action="/admin/api/payouts/#{payout.id}/invalidate"] input[name="authenticity_token"]))
        &.[]("value")

      expect(token).to be_present

      post "/admin/api/payouts/#{payout.id}/invalidate", headers: auth_headers, params: {
        _method: "patch",
        authenticity_token: token,
        return_to_admin_payouts: "1"
      }

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to("/admin/payouts")
      expect(payout.reload.payout_status.code).to eq("invalid")
    end
  end

  describe "Race conditions" do
    it "prevents overwriting completed payouts when invalidating concurrently" do
      allow_any_instance_of(Payout).to receive(:reload).and_wrap_original do |original_method, *args|
        unless @already_updated
          @already_updated = true
          payout.class.where(id: payout.id).update_all(payout_status_id: completed_payout_status.id)
        end
        original_method.call(*args)
      end

      patch "/admin/api/payouts/#{payout.id}/invalidate", headers: auth_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(payout.reload.payout_status).to eq(completed_payout_status)
    end
  end
end
