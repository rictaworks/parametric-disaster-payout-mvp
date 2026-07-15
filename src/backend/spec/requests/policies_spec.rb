require "rails_helper"

RSpec.describe "POST /api/v1/policies", type: :request do
  let(:user) { User.create!(google_sub: "google-sub-policy-request") }
  let(:internal_api_secret) { "shared-secret" }
  let(:session_token) { user.internal_session_token }
  let(:headers) do
    {
      "X-Internal-API-Secret" => internal_api_secret,
      "X-Internal-Session-Token" => session_token
    }
  end
  let(:recaptcha_client) { instance_double(RecaptchaVerifier, valid?: recaptcha_valid) }
  let(:recaptcha_valid) { true }
  let(:plan) do
    Plan.create!(
      code: "seismic_policy_request",
      trigger_type: "seismic",
      label_ja: "震度連動",
      label_en: "Seismic-linked",
      label_fr: "Lié aux séismes",
      label_zh: "震度連動",
      label_ru: "Сейсмическая привязка",
      label_es: "Vinculado a sismos",
      label_ar: "مرتبط بالزلازل"
    )
  end
  let(:station) do
    Station.create!(
      code: "seismic_tokyo_policy_request",
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
      code: "ten_thousand_policy_request",
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
  let!(:pending_status) do
    PolicyStatus.create!(
      code: "pending",
      sort_order: 0,
      label_ja: "待機中",
      label_en: "Pending",
      label_fr: "Pending",
      label_zh: "Pending",
      label_ru: "Pending",
      label_es: "Pending",
      label_ar: "Pending"
    )
  end
  let!(:active_status) do
    PolicyStatus.create!(
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
  end
  let!(:processing_status) do
    PolicyStatus.create!(
      code: "processing",
      sort_order: 2,
      label_ja: "支払処理中",
      label_en: "Processing payout",
      label_fr: "Processing payout",
      label_zh: "Processing payout",
      label_ru: "Processing payout",
      label_es: "Processing payout",
      label_ar: "Processing payout"
    )
  end
  let(:params) do
    {
      plan_id: plan.id,
      station_id: station.id,
      payout_tier_id: payout_tier.id,
      threshold: "5弱",
      recaptcha_token: "token-123"
    }
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("INTERNAL_API_SECRET").and_return(internal_api_secret)
    allow(RecaptchaVerifier).to receive(:new).and_return(recaptcha_client)
  end

  it "creates a pending policy and returns the created policy payload" do
    post "/api/v1/policies", params: params, headers: headers

    expect(response).to have_http_status(:created)

    body = JSON.parse(response.body)
    policy = Policy.find(body.fetch("policy").fetch("id"))

    expect(body["policy"]).to include(
      "user_id" => user.id,
      "plan_id" => plan.id,
      "station_id" => station.id,
      "payout_tier_id" => payout_tier.id,
      "policy_status_id" => pending_status.id,
      "threshold" => "5弱"
    )
    expect(policy.waiting_until).to be_within(5.seconds).of(Time.current + 72.hours)
  end

  it "returns 400 when reCAPTCHA verification fails" do
    allow(recaptcha_client).to receive(:valid?).and_return(false)

    post "/api/v1/policies", params: params, headers: headers

    expect(response).to have_http_status(:bad_request)
    expect(JSON.parse(response.body)).to include("error" => "recaptcha_failed")
    expect(Policy.count).to eq(0)
  end

  it "returns 422 when a master record is missing" do
    post "/api/v1/policies",
      params: params.merge(plan_id: 999_999),
      headers: headers

    expect(response).to have_http_status(422)
    body = JSON.parse(response.body)
    expect(body["error"]).to eq("master_not_found")
    expect(body["details"]).to include("plan")
  end

  it "returns 409 when the user already has an active policy for the same plan type" do
    Policy.create!(
      user: user,
      plan: plan,
      station: station,
      payout_tier: payout_tier,
      policy_status: active_status,
      threshold: "5弱"
    )

    post "/api/v1/policies", params: params, headers: headers

    expect(response).to have_http_status(:conflict)
    expect(JSON.parse(response.body)).to include("error" => "duplicate_policy")
  end

  it "returns 401 when the internal session token is missing" do
    post "/api/v1/policies", params: params, headers: { "X-Internal-API-Secret" => internal_api_secret }

    expect(response).to have_http_status(:unauthorized)
  end
end
