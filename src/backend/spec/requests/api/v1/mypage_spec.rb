require "rails_helper"

RSpec.describe "GET /api/v1/payouts", type: :request do
  let(:user) { User.create!(google_sub: "google-sub-mypage-payouts") }
  let(:other_user) { User.create!(google_sub: "google-sub-mypage-payouts-other") }
  let(:internal_api_secret) { "shared-secret" }
  let(:headers) do
    {
      "X-Internal-API-Secret" => internal_api_secret,
      "X-Internal-Session-Token" => user.internal_session_token
    }
  end
  let(:plan) do
    Plan.create!(
      code: "seismic_mypage_payouts",
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
      code: "seismic_tokyo_mypage_payouts",
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
      code: "ten_thousand_mypage_payouts",
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
  let!(:active_status) { PolicyStatus.find_or_create_by!(code: "active", sort_order: 1, label_ja: "有効", label_en: "Active", label_fr: "Active", label_zh: "Active", label_ru: "Active", label_es: "Active", label_ar: "Active") }
  let!(:ordered_status) { PayoutStatus.find_or_create_by!(code: "ordered", sort_order: 0, label_ja: "指図済", label_en: "Ordered", label_fr: "Ordered", label_zh: "Ordered", label_ru: "Ordered", label_es: "Ordered", label_ar: "Ordered") }
  let!(:completed_status) { PayoutStatus.find_or_create_by!(code: "completed_simulated", sort_order: 1, label_ja: "支払完了（模擬）", label_en: "Completed", label_fr: "Completed", label_zh: "Completed", label_ru: "Completed", label_es: "Completed", label_ar: "Completed") }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("INTERNAL_API_SECRET").and_return(internal_api_secret)
  end

  it "returns only the authenticated user's payouts" do
    own_policy = Policy.create!(
      user: user,
      plan: plan,
      station: station,
      payout_tier: payout_tier,
      policy_status: active_status,
      threshold: "5弱"
    ).tap do |policy|
      policy.update_columns(waiting_until: Time.current - 1.hour, expires_at: Time.current + 1.year)
    end
    other_policy = Policy.create!(
      user: other_user,
      plan: plan,
      station: station,
      payout_tier: payout_tier,
      policy_status: active_status,
      threshold: "5弱"
    ).tap do |policy|
      policy.update_columns(waiting_until: Time.current - 1.hour, expires_at: Time.current + 1.year)
    end

    own_payout = Payout.create!(
      policy: own_policy,
      payout_tier: payout_tier,
      payout_status: completed_status,
      observation: Observation.create!(
        station: station,
        event_id: "event-own-payout",
        observed_at: Time.current,
        seismic_intensity_level: SeismicIntensityLevel.create!(
          code: "level-own-payout",
          sort_order: 5,
          label_ja: "5弱",
          label_en: "5 weak",
          label_fr: "5 weak",
          label_zh: "5 weak",
          label_ru: "5 weak",
          label_es: "5 weak",
          label_ar: "5 weak"
        ),
        max_value: 5,
        simulated: false
      ),
      idempotency_key: "policy_#{own_policy.id}_event-own-payout",
      decided_at: Time.current
    )
    Payout.create!(
      policy: other_policy,
      payout_tier: payout_tier,
      payout_status: ordered_status,
      observation: Observation.create!(
        station: station,
        event_id: "event-other-payout",
        observed_at: Time.current,
        seismic_intensity_level: SeismicIntensityLevel.create!(
          code: "level-other-payout",
          sort_order: 6,
          label_ja: "5弱",
          label_en: "5 weak",
          label_fr: "5 weak",
          label_zh: "5 weak",
          label_ru: "5 weak",
          label_es: "5 weak",
          label_ar: "5 weak"
        ),
        max_value: 5,
        simulated: false
      ),
      idempotency_key: "policy_#{other_policy.id}_event-other-payout",
      decided_at: Time.current
    )

    get "/api/v1/payouts", headers: headers

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)

    expect(body["payouts"].length).to eq(1)
    expect(body["payouts"].first).to include(
      "policy_id" => own_policy.id,
      "policy_plan_code" => "seismic_mypage_payouts",
      "payout_status_code" => "completed_simulated",
      "survey_response_submitted" => false
    )
  end
end

RSpec.describe "GET /api/v1/notifications", type: :request do
  let(:user) { User.create!(google_sub: "google-sub-mypage-notifications") }
  let(:other_user) { User.create!(google_sub: "google-sub-mypage-notifications-other") }
  let(:internal_api_secret) { "shared-secret" }
  let(:headers) do
    {
      "X-Internal-API-Secret" => internal_api_secret,
      "X-Internal-Session-Token" => user.internal_session_token
    }
  end
  let(:plan) do
    Plan.create!(
      code: "seismic_mypage_notifications",
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
      code: "seismic_tokyo_mypage_notifications",
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
      code: "ten_thousand_mypage_notifications",
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
  let!(:active_status) { PolicyStatus.find_or_create_by!(code: "active", sort_order: 1, label_ja: "有効", label_en: "Active", label_fr: "Active", label_zh: "Active", label_ru: "Active", label_es: "Active", label_ar: "Active") }
  let!(:completed_status) { PayoutStatus.find_or_create_by!(code: "completed_simulated", sort_order: 1, label_ja: "支払完了（模擬）", label_en: "Completed", label_fr: "Completed", label_zh: "Completed", label_ru: "Completed", label_es: "Completed", label_ar: "Completed") }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("INTERNAL_API_SECRET").and_return(internal_api_secret)
  end

  it "returns only the authenticated user's notifications" do
    own_policy = Policy.create!(
      user: user,
      plan: plan,
      station: station,
      payout_tier: payout_tier,
      policy_status: active_status,
      threshold: "5弱"
    ).tap do |policy|
      policy.update_columns(waiting_until: Time.current - 1.hour, expires_at: Time.current + 1.year)
    end
    other_policy = Policy.create!(
      user: other_user,
      plan: plan,
      station: station,
      payout_tier: payout_tier,
      policy_status: active_status,
      threshold: "5弱"
    ).tap do |policy|
      policy.update_columns(waiting_until: Time.current - 1.hour, expires_at: Time.current + 1.year)
    end
    own_payout = Payout.create!(
      policy: own_policy,
      payout_tier: payout_tier,
      payout_status: completed_status,
      observation: Observation.create!(
        station: station,
        event_id: "event-own-notification",
        observed_at: Time.current,
        seismic_intensity_level: SeismicIntensityLevel.create!(
          code: "level-own-notification",
          sort_order: 5,
          label_ja: "5弱",
          label_en: "5 weak",
          label_fr: "5 weak",
          label_zh: "5 weak",
          label_ru: "5 weak",
          label_es: "5 weak",
          label_ar: "5 weak"
        ),
        max_value: 5,
        simulated: false
      ),
      idempotency_key: "policy_#{own_policy.id}_event-own-notification",
      decided_at: Time.current
    )
    other_payout = Payout.create!(
      policy: other_policy,
      payout_tier: payout_tier,
      payout_status: completed_status,
      observation: Observation.create!(
        station: station,
        event_id: "event-other-notification",
        observed_at: Time.current,
        seismic_intensity_level: SeismicIntensityLevel.create!(
          code: "level-other-notification",
          sort_order: 6,
          label_ja: "5弱",
          label_en: "5 weak",
          label_fr: "5 weak",
          label_zh: "5 weak",
          label_ru: "5 weak",
          label_es: "5 weak",
          label_ar: "5 weak"
        ),
        max_value: 5,
        simulated: false
      ),
      idempotency_key: "policy_#{other_policy.id}_event-other-notification",
      decided_at: Time.current
    )

    Notification.create!(user: user, policy: own_policy, payout: own_payout, kind: Notification::KIND_PAYOUT_COMPLETED, message: "own")
    Notification.create!(user: other_user, policy: other_policy, payout: other_payout, kind: Notification::KIND_PAYOUT_COMPLETED, message: "other")

    get "/api/v1/notifications", headers: headers

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["notifications"].length).to eq(1)
    expect(body["notifications"].first).to include("message" => "own", "kind" => Notification::KIND_PAYOUT_COMPLETED)
  end
end

RSpec.describe "POST /api/v1/survey_responses", type: :request do
  let(:user) { User.create!(google_sub: "google-sub-mypage-survey") }
  let(:other_user) { User.create!(google_sub: "google-sub-mypage-survey-other") }
  let(:internal_api_secret) { "shared-secret" }
  let(:headers) do
    {
      "X-Internal-API-Secret" => internal_api_secret,
      "X-Internal-Session-Token" => user.internal_session_token,
      "CONTENT_TYPE" => "application/json"
    }
  end
  let(:plan) do
    Plan.create!(
      code: "seismic_mypage_survey",
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
      code: "seismic_tokyo_mypage_survey",
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
      code: "ten_thousand_mypage_survey",
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
  let!(:active_status) { PolicyStatus.find_or_create_by!(code: "active", sort_order: 1, label_ja: "有効", label_en: "Active", label_fr: "Active", label_zh: "Active", label_ru: "Active", label_es: "Active", label_ar: "Active") }
  let!(:completed_status) { PayoutStatus.find_or_create_by!(code: "completed_simulated", sort_order: 1, label_ja: "支払完了（模擬）", label_en: "Completed", label_fr: "Completed", label_zh: "Completed", label_ru: "Completed", label_es: "Completed", label_ar: "Completed") }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("INTERNAL_API_SECRET").and_return(internal_api_secret)
  end

  it "creates a survey response for the authenticated user's payout" do
    policy = Policy.create!(
      user: user,
      plan: plan,
      station: station,
      payout_tier: payout_tier,
      policy_status: active_status,
      threshold: "5弱"
    ).tap do |created_policy|
      created_policy.update_columns(waiting_until: Time.current - 1.hour, expires_at: Time.current + 1.year)
    end
    payout = Payout.create!(
      policy: policy,
      payout_tier: payout_tier,
      payout_status: completed_status,
      observation: Observation.create!(
        station: station,
        event_id: "event-own-survey",
        observed_at: Time.current,
        seismic_intensity_level: SeismicIntensityLevel.create!(
          code: "level-own-survey",
          sort_order: 5,
          label_ja: "5弱",
          label_en: "5 weak",
          label_fr: "5 weak",
          label_zh: "5 weak",
          label_ru: "5 weak",
          label_es: "5 weak",
          label_ar: "5 weak"
        ),
        max_value: 5,
        simulated: false
      ),
      idempotency_key: "policy_#{policy.id}_event-own-survey",
      decided_at: Time.current
    )

    post "/api/v1/survey_responses",
      params: {
        payout_id: payout.id,
        response_data: { feedback: "よかったです" }
      }.to_json,
      headers: headers

    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    expect(body["survey_response"]).to include(
      "payout_id" => payout.id,
      "response_data" => { "feedback" => "よかったです" }
    )
    expect(SurveyResponse.count).to eq(1)
  end

  it "returns 403 when another user's payout is targeted" do
    policy = Policy.create!(
      user: other_user,
      plan: plan,
      station: station,
      payout_tier: payout_tier,
      policy_status: active_status,
      threshold: "5弱"
    ).tap do |created_policy|
      created_policy.update_columns(waiting_until: Time.current - 1.hour, expires_at: Time.current + 1.year)
    end
    payout = Payout.create!(
      policy: policy,
      payout_tier: payout_tier,
      payout_status: completed_status,
      observation: Observation.create!(
        station: station,
        event_id: "event-other-survey",
        observed_at: Time.current,
        seismic_intensity_level: SeismicIntensityLevel.create!(
          code: "level-other-survey",
          sort_order: 5,
          label_ja: "5弱",
          label_en: "5 weak",
          label_fr: "5 weak",
          label_zh: "5 weak",
          label_ru: "5 weak",
          label_es: "5 weak",
          label_ar: "5 weak"
        ),
        max_value: 5,
        simulated: false
      ),
      idempotency_key: "policy_#{policy.id}_event-other-survey",
      decided_at: Time.current
    )

    post "/api/v1/survey_responses",
      params: {
        payout_id: payout.id,
        response_data: { feedback: "よかったです" }
      }.to_json,
      headers: headers

    expect(response).to have_http_status(:forbidden)
    expect(SurveyResponse.count).to eq(0)
  end

  it "returns 422 when the payout is not completed_simulated" do
    ordered_status = PayoutStatus.find_or_create_by!(code: "ordered", sort_order: 0, label_ja: "指示済", label_en: "Ordered", label_fr: "Ordered", label_zh: "Ordered", label_ru: "Ordered", label_es: "Ordered", label_ar: "Ordered")
    policy = Policy.create!(
      user: user,
      plan: plan,
      station: station,
      payout_tier: payout_tier,
      policy_status: active_status,
      threshold: "5弱"
    ).tap do |created_policy|
      created_policy.update_columns(waiting_until: Time.current - 1.hour, expires_at: Time.current + 1.year)
    end
    payout = Payout.create!(
      policy: policy,
      payout_tier: payout_tier,
      payout_status: ordered_status,
      observation: Observation.create!(
        station: station,
        event_id: "event-ordered-survey",
        observed_at: Time.current,
        seismic_intensity_level: SeismicIntensityLevel.find_or_create_by!(
          code: "level-ordered-survey",
          sort_order: 5,
          label_ja: "5弱",
          label_en: "5 weak",
          label_fr: "5 weak",
          label_zh: "5 weak",
          label_ru: "5 weak",
          label_es: "5 weak",
          label_ar: "5 weak"
        ),
        max_value: 5,
        simulated: false
      ),
      idempotency_key: "policy_#{policy.id}_event-ordered-survey",
      decided_at: Time.current
    )

    post "/api/v1/survey_responses",
      params: {
        payout_id: payout.id,
        response_data: { feedback: "よかったです" }
      }.to_json,
      headers: headers

    expect(response).to have_http_status(:unprocessable_entity)
    expect(SurveyResponse.count).to eq(0)
  end
end
