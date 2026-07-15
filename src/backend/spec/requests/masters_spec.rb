require "rails_helper"

RSpec.describe "GET /api/v1/masters", type: :request do
  let(:internal_api_secret) { "shared-secret" }
  let(:headers) { { "X-Internal-API-Secret" => internal_api_secret } }

  let!(:plan) do
    Plan.create!(
      code: "seismic_masters",
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
  let!(:station) do
    Station.create!(
      code: "seismic_tokyo_masters",
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
  let!(:payout_tier) do
    PayoutTier.create!(
      code: "ten_thousand_masters",
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
  let!(:seismic_intensity_level) do
    SeismicIntensityLevel.create!(
      code: "5_weak_masters",
      sort_order: 900,
      label_ja: "5弱",
      label_en: "5 weak",
      label_fr: "5 weak",
      label_zh: "5 weak",
      label_ru: "5 weak",
      label_es: "5 weak",
      label_ar: "5 weak"
    )
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("INTERNAL_API_SECRET").and_return(internal_api_secret)
  end

  it "returns plan, station, payout tier, and seismic intensity level masters with their real IDs" do
    get "/api/v1/masters", headers: headers

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)

    expect(body["plans"]).to include(
      "id" => plan.id,
      "code" => "seismic_masters",
      "trigger_type" => "seismic"
    )
    expect(body["stations"]).to include(
      "id" => station.id,
      "code" => "seismic_tokyo_masters",
      "measurement_type" => "seismic"
    )
    expect(body["payout_tiers"]).to include(
      "id" => payout_tier.id,
      "code" => "ten_thousand_masters",
      "amount_yen" => 10_000
    )
    expect(body["seismic_intensity_levels"]).to include(
      "code" => "5_weak_masters",
      "label_ja" => "5弱",
      "sort_order" => 900
    )
  end

  it "does not require an internal session token, only the internal API secret" do
    get "/api/v1/masters", headers: headers

    expect(response).to have_http_status(:ok)
  end

  it "returns 403 when the internal API secret is missing or invalid" do
    get "/api/v1/masters", headers: { "X-Internal-API-Secret" => "wrong-secret" }

    expect(response).to have_http_status(:forbidden)
  end
end
